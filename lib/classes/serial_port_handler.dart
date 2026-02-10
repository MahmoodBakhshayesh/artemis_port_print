import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import '../artemis_port_util.dart';
import 'frame_parser.dart';
import 'serial_device_config.dart';

// Match your existing types
class DataReceive {
  final String text;
  final List<int> bytes;
  final int? indexOfBinaryByte;
  DataReceive({required this.text, required this.bytes, this.indexOfBinaryByte});
}

// ---- SerialPortHandler (libserialport + restored framing & writeAll) ----

class SerialPortHandler {
  final String portName;
  final SerialDeviceConfig config;
  final StatusManager statusMgr = StatusManager();

  final int stx = 0x02;
  final int etx = 0x03;

  /// enable/disable debug logs
  final bool enableLogging;

  /// PORT STATUS (notify UI about port lifecycle)
  final ValueNotifier<PortStatus> portStatus = ValueNotifier(PortStatus.closed);

  late final SerialPort _inner;
  SerialPortReader? _reader;
  SerialPortReader? get reader =>_reader;

  final _dataCtrl = StreamController<DataReceive>.broadcast();
  Stream<DataReceive> get onData => _dataCtrl.stream;

  dynamic savedHandler;
  final FrameParser _parser = FrameParser(
    stx: 0x02,
    etx: 0x03,
    includeTrailingControl: false,
  );

  StreamSubscription<Uint8List>? _sub;
  Timer? _pollTimer;
  Timer? _pinPollTimer;
  Duration pinPollInterval = const Duration(milliseconds: 200);

  bool _bootstrapped = false;

  String _lastStatus = 'unknown';
  DateTime _lastOccurred = DateTime.fromMillisecondsSinceEpoch(0);

  bool _lastCts = false;
  bool _lastDsr = false;

  SerialPortHandler({
    required this.portName,
    required this.config,
    this.enableLogging = true,
  }) : _inner = SerialPort(portName);

  bool get isConnected => _inner.isOpen;

  bool get isOpen => isConnected;

  Future<bool> open() async {
    log("open handler1");

    if (_inner.isOpen) {
      portStatus.value = PortStatus.open;
      return true;

    }

    _setConnecting();
    portStatus.value = PortStatus.opening;
    _log('[PORT][$portName] Opening...');

    if (!_inner.openReadWrite()) {
      portStatus.value = PortStatus.error;

      _log('[PORT][$portName] Failed to open.');
      return false;
    }
    _log('[PORT][$portName] Opened.');

    try {
      final c = SerialPortConfig()
        ..baudRate = config.baudRate
        ..bits     = config.dataBits
        ..parity   = config.parity
        ..stopBits = config.stopBits
        ..setFlowControl(config.flowControl);
      _inner.config = c;
      _log('[PORT][$portName] Config applied.');
    } catch (e) {
      _log('[PORT][$portName] Config error: $e');
      try { _inner.close(); } catch (_) {}
      portStatus.value = PortStatus.error;
      _setOffline();
      return false;
    }
    log("open handler2");

    _reader = SerialPortReader(_inner);
    _sub ??= _reader!.stream.listen(_onBytes, onError: (err, st) {
      _log('[PORT][$portName] Read error: $err');
      portStatus.value = PortStatus.error;
    }, onDone: () {
      _log('[PORT][$portName] Reader closed.');
      if (!_inner.isOpen) {
        portStatus.value = PortStatus.closed;
        _setOffline();
      }
    });

    log("open handler3");

    portStatus.value = PortStatus.open;

    if (!_bootstrapped) {
      _log('[PORT][$portName] Bootstrapping...');
      await _runBootstrap();
      _bootstrapped = true;
      await _pollOnce();
    }
    _pollTimer ??=
        Timer.periodic(const Duration(seconds: 5), (_) => _pollOnce());

    final (cts, dsr) = _readCtsDsr(_inner);
    _lastCts = cts;
    _lastDsr = dsr;

    log("open handler4");

    // ---- PinChanged equivalent: poll and detect changes ----
    _pinPollTimer = Timer.periodic(pinPollInterval, (_) async {
      if (_inner == null) return;

      final (newCts, newDsr) = _readCtsDsr(_inner!);

      if (newCts == _lastCts && newDsr == _lastDsr) return;

      _lastCts = newCts;
      _lastDsr = newDsr;

      // Match your "Task.Delay(500)" debounce
      await Future<void>.delayed(const Duration(milliseconds: 500));

      _handlePinChanged(
        ctsHolding: newCts,
        dsrHolding: newDsr,
        occurred: DateTime.now(),
      );

    });

    return true;
  }
  Future<bool> openReader(void Function(dynamic data) handler) async {
    log("open handler1");

    if (_inner.isOpen) {
      portStatus.value = PortStatus.open;
      return true;

    }

    _setConnecting();
    portStatus.value = PortStatus.opening;
    _log('[PORT][$portName] Opening...');

    if (!_inner.openRead()) {
      portStatus.value = PortStatus.error;

      _log('[PORT][$portName] Failed to open.');
      return false;
    }
    _log('[PORT][$portName] Opened.');

    try {
      final c = SerialPortConfig()
        ..baudRate = config.baudRate
        ..bits     = config.dataBits
        ..parity   = config.parity
        ..stopBits = config.stopBits
        ..setFlowControl(config.flowControl);
      _inner.config = c;
      _log('[PORT][$portName] Config applied.');
    } catch (e) {
      _log('[PORT][$portName] Config error: $e');
      try { _inner.close(); } catch (_) {}
      portStatus.value = PortStatus.error;
      _setOffline();
      return false;
    }
    log("open handler2");

    _reader = SerialPortReader(_inner);
    _sub ??= _reader!.stream.listen(handler, onError: (err, st) {
      _log('[PORT][$portName] Read error: $err');
      portStatus.value = PortStatus.error;
    }, onDone: () {
      _log('[PORT][$portName] Reader closed.');
      if (!_inner.isOpen) {
        portStatus.value = PortStatus.closed;
        _setOffline();
      }
    });

    log("open handler3");

    portStatus.value = PortStatus.open;
    savedHandler = handler;
    final (cts, dsr) = _readCtsDsr(_inner);
    _lastCts = cts;
    _lastDsr = dsr;

    log("open handler4");

    // ---- PinChanged equivalent: poll and detect changes ----
    _pinPollTimer = Timer.periodic(pinPollInterval, (_) async {

      final (newCts, newDsr) = _readCtsDsr(_inner!);

      // if (newCts == _lastCts && newDsr == _lastDsr) return;

      _lastCts = newCts;
      _lastDsr = newDsr;

      // Match your "Task.Delay(500)" debounce
      await Future<void>.delayed(const Duration(milliseconds: 500));
      log("should _handlePinChanged");
      _handlePinChanged(
        ctsHolding: newCts,
        dsrHolding: newDsr,
        occurred: DateTime.now(),
      );

    });

    return true;
  }


  Future<bool> close() async {
    _log('[PORT][$portName] Closing...');
    portStatus.value = PortStatus.closing;

    _pollTimer?.cancel();
    _pollTimer = null;
    await _sub?.cancel();
    _sub = null;
    _reader?.close();
    _reader = null;

    if (_inner.isOpen) {
      try { _inner.close(); } catch (_) {}
      _log('[PORT][$portName] Closed.');
    }
    portStatus.value = PortStatus.closed;
    _setOffline();
    return true;
  }

  Future<bool> sendBytes(List<int> message) async {
    if (!_inner.isOpen) {
      _log('[PORT][$portName] sendBytes failed: port not open.');
      return false;
    }

    final payload = Uint8List.fromList(message);
    final framed = (payload.isNotEmpty &&
        payload.first == stx &&
        payload.last  == etx)
        ? payload
        : _frameBytes(payload);

    _log('[TX][$portName] ${ascii.decode(payload, allowInvalid: true)} '
        '(${framed.length} bytes: ${framed})');

    return _writeAll(framed);
  }

  // ---- internals (unchanged except logging) ----
  void _onBytes(Uint8List chunk) {
    _log('[RX raw][$portName] ${chunk.length} bytes: $chunk');

    final looksFramed = chunk.contains(stx) || chunk.contains(etx);

    if (!looksFramed && config.protocolMode == ProtocolMode.none) {
      final text = ascii.decode(chunk, allowInvalid: true);
      _log('[RX text][$portName] "$text"');
      _dataCtrl.add(DataReceive(text: text, bytes: chunk.toList()));
      _maybeUpdateStatus(text);
      return;
    }

    final frames = _parser.feed(chunk);
    for (final payload in frames) {
      final clean = _stripStxEtx(payload);
      final text = ascii.decode(clean, allowInvalid: true);

      _log('[RX parsed][$portName] "$text" (${clean.length} bytes)');
      
      // if(text.startsWith("HDCERRM")){
      //   _reInit();
      // }

      int? idx;
      for (var i = 0; i < clean.length; i++) {
        if (clean[i] <= 31) { idx = i; break; }
      }

      _dataCtrl.add(
        DataReceive(text: text, bytes: clean.toList(), indexOfBinaryByte: idx),
      );
      _maybeUpdateStatus(text);
    }
  }

  void _maybeUpdateStatus(String text) {
    if (text.isEmpty) return;
    final isSqni = text.toUpperCase().contains('SQNI');
    statusMgr.updateFrom(text, sqni: isSqni);
    final st = statusMgr.status;
    _log('[STATUS][$portName] state=${st.state} desc="${st.desc}"');
  }

  Future<void> _runBootstrap() async {
    await _sendCmd("MX");
    await _sendCmd("UG#GID");
    await _sendCmd("EP#AIRLINEID=GID#HARDCODE=HDC#UNSOL=Y");
    await _sendCmd("UC#999");
    await _sendCmd("AV");
    await _sendCmd("PV");
    await _sendCmd("SQ");
  }

  Future<void> _pollOnce() async {
    await _sendCmd("SQ");
  }

  Future<void> _sendCmd(String cmd) async {
    _log('[CMD][$portName] Sending "$cmd"...');
    await sendBytes(cmd.codeUnits);
  }

  Uint8List _frameBytes(Uint8List message) {
    final out = Uint8List(message.length + 2);
    out[0] = stx;
    out[out.length - 1] = etx;
    out.setRange(1, out.length - 1, message);
    return out;
  }

  Uint8List _stripStxEtx(Uint8List data) {
    var start = 0, end = data.length;
    if (end > 0 && data[0] == stx) start = 1;
    if (end - start > 0 && data[end - 1] == etx) end -= 1;
    return Uint8List.fromList(data.sublist(start, end));
  }

  Future<bool> _writeAll(Uint8List data) async {
    var off = 0;
    while (off < data.length) {
      final wrote = _inner.write(data.sublist(off));
      if (wrote == null || wrote <= 0) {
        _log('[TX][$portName] write failed at offset $off');
        return false;
      }
      off += wrote;
    }
    return true;
  }

  void _setConnecting() {
    final s = statusMgr.status.clone()
      ..state = StatusState.busy
      ..desc = 'Connecting...'
      ..ready = false;
    statusMgr.statusNotifier.value = s;
    _log('[STATUS][$portName] Connecting...');
  }


  void _setOffline() {
    final s = statusMgr.status.clone()
      ..state = StatusState.offline
      ..desc = 'Offline'
      ..ready = false;
    statusMgr.statusNotifier.value = s;
    _log('[STATUS][$portName] Offline.');
  }

  void _log(String msg) {
    // log(msg);
    if (enableLogging) debugPrint(msg);
  }

  // Future<void> _reInit() async {
  //   String command1 = "UK";
  //   String command2 = "MX";
  //   String command3 = "UG#GID";
  //   String command4 = "EP#AIRLINEID=GID#HARDCODE=HDC#UNSOL=Y";
  //   String command5 = "UC#999";
  //   await sendBytes(command1.codeUnits);
  //   await sendBytes(command2.codeUnits);
  //   await sendBytes(command3.codeUnits);
  //   await sendBytes(command4.codeUnits);
  //   await sendBytes(command5.codeUnits);
  // }



  (bool cts, bool dsr) _readCtsDsr(SerialPort port) {
    // try {
      // port.signals is a bitmask of SerialPortSignal.* constants. :contentReference[oaicite:2]{index=2}
      final signals = port.signals;
      final cts = (signals & SerialPortSignal.cts) != 0;
      final dsr = (signals & SerialPortSignal.dsr) != 0;
      log("_readCtsDsr done  ${cts}  $dsr");
      return (cts, dsr);
    // }catch(e){
    //   // if(savedHandler!=null){
    //   //   openReader(savedHandler);
    //   // }
    //   return (false,false);
    // }

  }

  void _handlePinChanged({
    required bool ctsHolding,
    required bool dsrHolding,
    required DateTime occurred,
  }) {
    // (Optional) log like your C#:
    log('[CTS: $ctsHolding, DSR: $dsrHolding] Changed.');

    // Direct mapping of your state machine:
    if (!ctsHolding && !dsrHolding) {

      portStatus.value = PortStatus.closed;
      log("set port status close");

      // _deviceAvailable = false;
      // _lastStatus = 'poweroff';
      // _availabilityController.add(
      //   DeviceAvailable(available: _deviceAvailable, lastStatus: _lastStatus),
      // );
      // _lastOccurred = occurred;
      return;

    } else if (dsrHolding && !ctsHolding) {
      portStatus.value = PortStatus.error;
      log("set port status error");

      // _deviceAvailable = false;
      // _lastStatus = 'offline';
      // _availabilityController.add(
      //   DeviceAvailable(
      //     available: _deviceAvailable,
      //     offline: true,
      //     lastStatus: _lastStatus,
      //   ),
      // );
      // _lastOccurred = occurred;
      return;
    } else if (dsrHolding && ctsHolding) {
      portStatus.value = PortStatus.open;
      log("set port status open");
      // _deviceAvailable = true;
      // _lastStatus = 'ready';
      // _availabilityController.add(
      //   DeviceAvailable(available: _deviceAvailable, lastStatus: _lastStatus),
      // );
      // _lastOccurred = occurred;
      return;
    }

    // Your "within 1 second" heuristic:
    // final diffSeconds = occurred.difference(_lastOccurred).inMilliseconds / 1000.0;
    // if (diffSeconds <= 1) {
    //   _deviceAvailable = dsrHolding || ctsHolding;
    // } else {
    //   _deviceAvailable = !(!ctsHolding && !dsrHolding);
    // }
    //
    // _availabilityController.add(
    //   DeviceAvailable(available: _deviceAvailable, lastStatus: _lastStatus),
    // );

    _lastOccurred = occurred;
  }
}

