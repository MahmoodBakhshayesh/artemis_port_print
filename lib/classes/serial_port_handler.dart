import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data'; // Added missing import
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import '../artemis_port_util.dart';
import 'frame_parser.dart';
import 'serial_device_config.dart';

enum _HandlerMode { none, readWrite, readOnly }

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
  Timer? _hotplugTimer; // Added for hotplug monitoring
  Duration pinPollInterval = const Duration(milliseconds: 200);

  bool _bootstrapped = false;

  String _lastStatus = 'unknown';
  DateTime _lastOccurred = DateTime.fromMillisecondsSinceEpoch(0);

  bool _lastCts = false;
  bool _lastDsr = false;
  
  // Hotplug state tracking
  bool _intendedOpen = false;
  _HandlerMode _mode = _HandlerMode.none;

  // Command Queue to serialize writes
  Future<void> _taskQueue = Future.value();

  SerialPortHandler({
    required this.portName,
    required this.config,
    this.enableLogging = true,
  }) : _inner = SerialPort(portName) {
    _startHotplugMonitor();
  }

  bool get isConnected => _inner.isOpen;

  bool get isOpen => isConnected;

  /// Schedules a task to be executed sequentially in the command queue.
  /// [isPrinting] : If true, sets the device status to 'Busy'/'Printing' before starting.
  Future<T> scheduleTask<T>(Future<T> Function() task, {bool isPrinting = false}) {
    final completer = Completer<T>();
    
    // Ensure the queue chain continues regardless of previous task success/failure
    _taskQueue = _taskQueue.then((_) async {
       if (isPrinting) _setPrinting();
       await _runTask(task, completer);
    }).catchError((_) async {
       if (isPrinting) _setPrinting();
       await _runTask(task, completer);
    });
    
    return completer.future;
  }

  Future<void> _runTask<T>(Future<T> Function() task, Completer<T> completer) async {
    try {
      final result = await task();
      completer.complete(result);
    } catch (e, s) {
      completer.completeError(e, s);
    }
  }

  Future<bool> open() async {
    log("open handler1");
    _intendedOpen = true;
    _mode = _HandlerMode.readWrite;

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
      _internalClose(keepIntent: true);
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
      if (!_inner.isOpen) return;

      final (newCts, newDsr) = _readCtsDsr(_inner);

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
    _intendedOpen = true;
    _mode = _HandlerMode.readOnly;

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
      _internalClose(keepIntent: true);
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
      if (!_inner.isOpen) return;

      final (newCts, newDsr) = _readCtsDsr(_inner);

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

  Future<bool> close() async {
    return _internalClose(keepIntent: false);
  }

  Future<bool> _internalClose({bool keepIntent = false}) async {
    _log('[PORT][$portName] Closing (keepIntent=$keepIntent)...');
    portStatus.value = PortStatus.closing;
    
    if (!keepIntent) {
      _intendedOpen = false;
      _mode = _HandlerMode.none;
    }

    _pollTimer?.cancel();
    _pollTimer = null;
    _pinPollTimer?.cancel();
    _pinPollTimer = null;
    await _sub?.cancel();
    _sub = null;
    _reader?.close();
    _reader = null;

    if (_inner.isOpen) {
      try { _inner.close(); } catch (_) {}
      _log('[PORT][$portName] Closed.');
    }
    
    portStatus.value = keepIntent ? PortStatus.error : PortStatus.closed;
    _setOffline();
    return true;
  }

  void dispose() {
    _hotplugTimer?.cancel();
    _hotplugTimer = null;
    close();
    _dataCtrl.close();
  }

  /// Use this method for general writing. It will be queued.
  Future<bool> sendBytes(List<int> message) {
    return scheduleTask(() => sendBytesImmediate(message), isPrinting: true);
  }

  /// Use this method ONLY inside a scheduled task to avoid deadlock.
  Future<bool> sendBytesImmediate(List<int> message) async {
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

  /// Internal method to send a command and wait for a response.
  /// Must be called from within a scheduled task to ensure atomic operation.
  Future<DataReceive> _sendCommandAndWaitImmediate(String cmd, {Duration timeout = const Duration(seconds: 15)}) async {
    final completer = Completer<DataReceive>();

    // Listen for the next response
    // Note: this assumes strict request-response or that the next message is relevant.
    final sub = _dataCtrl.stream.listen((data) {
      if (!completer.isCompleted) {
        completer.complete(data);
      }
    });

    _log('[CMD][$portName] Sending "$cmd" and waiting...');
    final sent = await sendBytesImmediate(cmd.codeUnits);
    if (!sent) {
      sub.cancel();
      throw Exception("Failed to send command $cmd");
    }

    final timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException("Command '$cmd' timed out", timeout));
      }
    });

    try {
      return await completer.future;
    } finally {
      timer.cancel();
      sub.cancel();
    }
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
    // Queue bootstrap commands to ensure no interleaving
    await scheduleTask(() async {
      final boot1Res = await _sendCommandAndWaitImmediate("MX");
      log(boot1Res.text);
      final boot2Res = await _sendCommandAndWaitImmediate("UG#GID");
      log(boot2Res.text);
      final boot3Res = await _sendCommandAndWaitImmediate("EP#AIRLINEID=GID#HARDCODE=HDC#UNSOL=Y");
      log(boot3Res.text);
      final boot4Res = await _sendCommandAndWaitImmediate("UC#999");
      log(boot4Res.text);
      final boot5Res = await _sendCommandAndWaitImmediate("AV");
      log(boot5Res.text);
      final boot6Res = await _sendCommandAndWaitImmediate("PV");
      log(boot6Res.text);
      final boot7Res = await _sendCommandAndWaitImmediate("SQ");
      log(boot7Res.text);
    });
  }

  Future<void> _pollOnce() async {
    // Queue status poll
    await scheduleTask(() async {
      await _sendCommandAndWaitImmediate("SQ");
    });
  }

  Future<void> _sendCmd(String cmd) async {
    // Deprecated for internal use in favor of _sendCommandAndWaitImmediate inside scheduled task
    // But keeping it if used elsewhere.
    await sendBytesImmediate(cmd.codeUnits);
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
    _setBusyState('Connecting...');
  }
  
  void _setPrinting() {
    _setBusyState('Printing...');
  }
  
  void _setBusyState(String desc) {
    final s = statusMgr.status.clone()
      ..state = StatusState.busy
      ..desc = desc
      ..ready = false;
    statusMgr.statusNotifier.value = s;
    _log('[STATUS][$portName] $desc');
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

  (bool cts, bool dsr) _readCtsDsr(SerialPort port) {
    try {
      // port.signals is a bitmask of SerialPortSignal.* constants. :contentReference[oaicite:2]{index=2}
      final signals = port.signals;
      final cts = (signals & SerialPortSignal.cts) != 0;
      final dsr = (signals & SerialPortSignal.dsr) != 0;
      // log("_readCtsDsr done  ${cts}  $dsr");
      return (cts, dsr);
    }catch(e){
      // This is often where we catch unplug events during polling
      _internalClose(keepIntent: true);
      return (false,false);
    }

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
      return;

    } else if (dsrHolding && !ctsHolding) {
      portStatus.value = PortStatus.error;
      log("set port status error");
      return;
    } else if (dsrHolding && ctsHolding) {
      portStatus.value = PortStatus.open;
      log("set port status open");
      return;
    }

    _lastOccurred = occurred;
  }

  void _startHotplugMonitor() {
    _hotplugTimer?.cancel();
    _hotplugTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final ports = SerialPort.availablePorts;
        final isAvailable = ports.contains(portName);

        if (!isAvailable && _inner.isOpen) {
           _log('[HOTPLUG][$portName] Port disconnected (unplugged).');
           await _internalClose(keepIntent: true);
           // Force status to error to indicate unplug
           portStatus.value = PortStatus.error;
        } else if (isAvailable && !_inner.isOpen && _intendedOpen) {
           _log('[HOTPLUG][$portName] Port detected. Reconnecting...');
           if (_mode == _HandlerMode.readWrite) {
             await open();
           } else if (_mode == _HandlerMode.readOnly) {
             if (savedHandler != null) {
               await openReader(savedHandler);
             }
           }
        }
      } catch (e) {
        _log('[HOTPLUG][$portName] Check error: $e');
      }
    });
  }
}

// Match your existing types
class DataReceive {
  final String text;
  final List<int> bytes;
  final int? indexOfBinaryByte;
  DataReceive({required this.text, required this.bytes, this.indexOfBinaryByte});
}
