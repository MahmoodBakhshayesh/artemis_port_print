import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:libserialport/libserialport.dart';

import 'enums.dart';
import 'frame_parser.dart';
import 'serial_device_config.dart';
import 'status_class.dart';

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

  final _dataCtrl = StreamController<DataReceive>.broadcast();
  Stream<DataReceive> get onData => _dataCtrl.stream;

  final FrameParser _parser = FrameParser(
    stx: 0x02,
    etx: 0x03,
    includeTrailingControl: false,
  );

  StreamSubscription<Uint8List>? _sub;
  Timer? _pollTimer;
  bool _bootstrapped = false;

  SerialPortHandler({
    required this.portName,
    required this.config,
    this.enableLogging = true,
  }) : _inner = SerialPort(portName);

  bool get isConnected => _inner.isOpen;

  Future<bool> open() async {
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

    portStatus.value = PortStatus.open;

    if (!_bootstrapped) {
      _log('[PORT][$portName] Bootstrapping...');
      await _runBootstrap();
      _bootstrapped = true;
      await _pollOnce();
    }
    _pollTimer ??=
        Timer.periodic(const Duration(seconds: 5), (_) => _pollOnce());

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
    if (enableLogging) debugPrint(msg);
  }
}

