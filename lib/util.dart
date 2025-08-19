// SerialPortBase.dart — rewrite of your C# SerialPortBase using flutter_libserialport
// Requires: flutter_libserialport: ^0.4.0 (or compatible)
// Platform: Windows (also works on Linux/macOS with matching drivers)

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'enums.dart';

/// Simple protocol selector to emulate the C# behavior.


/// Event payload similar to DataReceive in your C# code.
class DataReceive {
  final String text;
  final List<int> bytes;
  final int? indexOfBinaryByte; // first control byte (<= 31) after STX
  DataReceive({required this.text, required this.bytes, this.indexOfBinaryByte});
}

/// Pin change snapshot
class PinSnapshot {
  final bool? cts;
  final bool? dsr;
  final bool? dcd;
  final bool? ri;

  PinSnapshot({this.cts, this.dsr, this.dcd, this.ri});
}

/// Minimal configuration analogous to your CUPPS peripheral config
class SerialDeviceConfig {
  final String portName; // e.g., "COM3"
  final int baudRate; // e.g., 9600
  final int dataBits; // typically 8
  final int parity; // 0 none, 1 odd, 2 even
  final int stopBits; // 1 or 2
  final bool dtrEnable;
  final bool rtsEnable;
  final int flowControl; // none, rtsCts, xonXoff
  final Duration readTimeout; // used in polling reads
  final Duration writeTimeout; // not strictly used by lib, but kept for API symmetry
  final ProtocolMode protocolMode;

  const SerialDeviceConfig({
    required this.portName,
    this.baudRate = 9600,
    this.dataBits = 8,
    this.parity = 0,
    this.stopBits = 1,
    this.dtrEnable = true,
    this.rtsEnable = true,
    this.flowControl = SerialPortFlowControl.none,
    this.readTimeout = const Duration(milliseconds: 500),
    this.writeTimeout = const Duration(milliseconds: 500),
    this.protocolMode = ProtocolMode.framed,
  });
}

/// Dart rewrite of SerialPortBase (C#) built on flutter_libserialport.
class SerialPortBaseDart {
  final SerialDeviceConfig config;

  // Protocol constants
  int stx = 0x02; // STX
  int etx = 0x03; // ETX

  // Public state mirrors
  String response = '';
  String statusResponse = '';

  // Port
  late final SerialPort _port;
  SerialPortReader? _reader;
  final FrameParser _parser = FrameParser(
    stx: 0x02, // your existing fields
    etx: 0x03,
    includeTrailingControl: false, // set true if you want LRC after ETX
  );
  // Streams
  final _dataStream = StreamController<DataReceive>.broadcast();

  Stream<DataReceive> get onData => _dataStream.stream;

  final _pinStream = StreamController<PinSnapshot>.broadcast();

  Stream<PinSnapshot> get onPinChanged => _pinStream.stream;

  // Buffering/parse state
  final List<int> _rxFrame = <int>[];
  bool _inEscape = false; // DLE state
  bool _inMessage = false; // between STX..ETX
  bool _hasSpecialCharStart = false; // leading special

  Timer? _pinPoll;
  PinSnapshot? _lastPins;

  SerialPortBaseDart(this.config) {
    _port = SerialPort(config.portName);
  }

  bool get isConnected => _port.isOpen;

  /// Try opening the port with the configured mode.
  Future<bool> open() async {
    if (_port.isOpen) return true;

    if (!SerialPort.availablePorts.contains(config.portName)) {
      return false;
    }

    final ok = _port.openReadWrite();
    if (!ok) return false;

    final cfg = SerialPortConfig()
      ..baudRate = config.baudRate
      ..bits = config.dataBits
      ..parity = config.parity
      ..stopBits = config.stopBits
      ..setFlowControl(config.flowControl);
    _port.config = cfg;
    // NOTE: flutter_libserialport does not expose manual DTR/RTS toggling.
    // Use flow control in SerialPortConfig instead (none / rtsCts / dtrDsr).


    // Start reader
    _reader = SerialPortReader(_port);
    _reader!.stream.listen(
      _onBytes,
      onError: (e, st) {
        // bubble up as an empty receive (or log)
      },
    );

    // Start pin polling (lib doesn’t expose pin change events)
    _pinPoll?.cancel();
    _pinPoll = Timer.periodic(const Duration(milliseconds: 250), (_) => _pollPins());

    return true;
  }

  Future<bool> close() async {
    _pinPoll?.cancel();
    _pinPoll = null;
    _reader?.close();
    _reader = null;
    if (_port.isOpen) {
      try {
        _port.close();
      } catch (_) {}
    }
    return true;
  }

  void dispose() {
    _dataStream.close();
    _pinStream.close();
    _pinPoll?.cancel();
    if (_port.isOpen) {
      try {
        _port.close();
      } catch (_) {}
    }
  }

  /// Equivalent to Send(byte[] message) in C#.
  Future<bool> sendBytes(List<int> message) async {
    response = '';
    statusResponse = '';
    if (!isConnected) {
      final ok = await open();
      if (!ok) return false;
    }

    final framed = _dataPreparationBytes(stx, Uint8List.fromList(message), etx);
    return _writeAll(framed);
  }

  /// Equivalent to Send(params string[] messages) in C#.
  Future<bool> sendStrings(List<String> messages) async {
    response = '';
    statusResponse = '';
    if (!isConnected) {
      final ok = await open();
      if (!ok) return false;
    }

    final framed = _dataPreparationStrings(stx, messages, etx);
    if (framed == null) return false;
    return _writeAll(framed);
  }

  Future<Uint8List> sendAndRead({required List<int> request, Duration timeout = const Duration(seconds: 1), Duration quietWindow = const Duration(milliseconds: 120)}) async {
    await sendBytes(request);
    // Accumulate until quiet or timeout
    final completer = Completer<Uint8List>();
    final chunks = <int>[];
    Timer? quiet;
    late final StreamSubscription sub;

    void finish() async {
      if (!completer.isCompleted) completer.complete(Uint8List.fromList(chunks));
      await sub.cancel();
      quiet?.cancel();
    }

    final hard = Timer(timeout, finish);
    sub = onData.listen((evt) {
      // log("Listen");
      chunks.addAll(evt.bytes);
      quiet?.cancel();
      quiet = Timer(quietWindow, finish);
    });

    final resp = await completer.future;
    hard.cancel();
    return resp;
  }

  // ---------------------- Internals ----------------------

  Future<bool> _writeAll(Uint8List data) async {
    var off = 0;
    while (off < data.length) {
      final n = _port.write(data.sublist(off));
      if (n == null || n <= 0) return false;
      off += n;
    }
    return true;
  }

  void _onBytes(Uint8List chunk) {
    if (config.protocolMode == ProtocolMode.none) {
      // auto-detect framed replies even in 'none' mode
      final looksFramed =
          chunk.contains(stx) || chunk.contains(etx); // quick heuristic

      if (looksFramed) {
        final frames = _parser.feed(chunk); // returns payloads WITHOUT STX/ETX
        for (final payload in frames) {
          final text = utf8.decode(payload, allowMalformed: true);

          if (!(text.contains('SQNI#') && !text.contains('EPOK') && !text.contains('ESOK'))) {
            response = text;
          }

          int? indexOfBinary;
          for (var k = 0; k < payload.length; k++) {
            if (_binaryDetect(payload[k])) { indexOfBinary = k; break; }
          }

          _dataStream.add(DataReceive(
            text: text,
            bytes: payload.toList(),            // ✅ payload only
            indexOfBinaryByte: indexOfBinary,
          ));
        }
        return; // handled
      }

      // pure pass-through (no framing detected)
      final text = utf8.decode(chunk, allowMalformed: true);
      response = text;
      _dataStream.add(DataReceive(text: text, bytes: chunk.toList()));
      return;
    }

    final frames = _parser.feed(chunk); // frames already WITHOUT STX/ETX

    for (final payload in frames) {
      // optional: hard trim if a stray STX/ETX slipped in
      final clean = _stripStxEtx(payload);

      final text = utf8.decode(clean, allowMalformed: true);
      if (!(text.contains('SQNI#') && !text.contains('EPOK') && !text.contains('ESOK'))) {
        response = text;
      }

      int? indexOfBinary;
      for (var k = 0; k < clean.length; k++) {
        if (_binaryDetect(clean[k])) { indexOfBinary = k; break; }
      }

      _dataStream.add(DataReceive(
        text: text,
        bytes: clean.toList(), // payload only
        indexOfBinaryByte: indexOfBinary,
      ));
    }
  }

// safety guard (just in case)
  Uint8List _stripStxEtx(Uint8List data) {
    var start = 0, end = data.length;
    if (end > 0 && data[0] == stx) start = 1;
    if (end - start > 0 && data[end - 1] == etx) end -= 1;
    return Uint8List.fromList(data.sublist(start, end));
  }




  void _pollPins() {
    // flutter_libserialport does not expose CTS/DSR/DCD/RI getters.
    // If you need pin-state monitoring, add a small FFI extension binding to
    // libserialport's sp_get_signals() or a Win32 CreateFile/EscapeCommFunction wrapper.
    // For now, this is a no-op to avoid compile errors.
    return;
  }

  // ---------------------- Message building (Send) ----------------------

  Uint8List? _dataPreparationStrings(int s, List<String> messages, int e) {
    try {
      final result = BytesBuilder();
      var length = 0;
      var isLogoBinary = false;

      for (var i = 0; i < messages.length; i++) {
        final msg = messages[i];

        if (_isBase64(msg)) {
          var base64 = msg.replaceFirst('base64', '');
          var messageBytes = base64Decode(base64);

          if (!isLogoBinary) length += messageBytes.length;

          if (result.length > 0 && messages.any((m) => m.trim().startsWith('MG'))) {
            result.add([10]);
            length += 1;
          } else if (isLogoBinary) {
            final logoEscaped = <int>[];
            for (final b in messageBytes) {
              if (_addDLE(b)) logoEscaped.add(0x10);
              logoEscaped.add(b);
            }
            messageBytes = Uint8List.fromList(logoEscaped);
            length += messageBytes.length;
          }

          result.add(messageBytes);
        } else if (_isKioskCommand(msg)) {
          final base64 = msg.replaceFirst('kiosk', '');
          final messageBytes = base64Decode(base64);
          return Uint8List.fromList(messageBytes);
        } else {
          final messageBytes = utf8.encode(msg.replaceAll('\r', '').replaceAll('\n', ''));
          length += messageBytes.length;

          if (result.length > 0 && messages.any((m) => m.trim().startsWith('MG'))) {
            result.add([10]);
            length += 1;
          }

          if (msg.trim().startsWith('LT') && messages.any((m) => m.contains('base64'))) {
            isLogoBinary = true;
          }

          result.add(messageBytes);
        }
      }

      final payload = result.toBytes();
      if (payload.isNotEmpty && payload.first == s && payload.last == e) {
        return payload; // already framed
      }

      final framed = Uint8List(payload.length + 2);
      framed[0] = s;
      framed[framed.length - 1] = e;
      framed.setRange(1, framed.length - 1, payload);
      return framed;
    } catch (_) {
      return null;
    }
  }

  Uint8List _dataPreparationBytes(int s, Uint8List message, int e) {
    if (message.isNotEmpty && message.first == s && message.last == e) {
      return message; // already framed
    }
    final framed = Uint8List(message.length + 2);
    framed[0] = s;
    framed[framed.length - 1] = e;
    framed.setRange(1, framed.length - 1, message);
    return framed;
  }

  // ---------------------- Helpers (ported heuristics) ----------------------

  bool _isBase64(String s) => s.startsWith('base64');

  bool _isKioskCommand(String s) => s.startsWith('kiosk');

  bool _addDLE(int b) {
    // C# logic: return false for printable 33..127, true otherwise
    return !(b >= 33 && b <= 127);
  }

  bool _binaryDetect(int b) => b <= 31;

  bool _detectStartSpecial(int b) {
    // Placeholder for Control_Characters.DetectStartSepecialCharacter
    // Treat most control chars (except STX/ETX/DLE) as special starts
    if (b == stx || b == etx || b == 0x10) return false;
    return b < 0x20;
  }

  bool _detectEndSpecial(int b) {
    // Placeholder for Control_Characters.DetectEndSepecialCharacter
    // Consider control chars as possible trailing checksum/LRC/etc.
    return b < 0x20;
  }
}


class FrameParser {
  final int stx;
  final int etx;
  final int dle;
  final bool includeTrailingControl;

  FrameParser({
    this.stx = 0x02,
    this.etx = 0x03,
    this.dle = 0x10,
    this.includeTrailingControl = false, // set true if you need LRC after ETX
  });

  // Internal state
  final List<int> _payload = [];
  bool _inMessage = false;
  bool _inEscape = false;

  /// Feed a chunk; returns completed payloads (without STX/ETX).
  List<Uint8List> feed(Uint8List chunk) {
    final out = <Uint8List>[];

    for (var i = 0; i < chunk.length; i++) {
      final b = chunk[i];

      if (!_inMessage) {
        if (b == stx) {
          _inMessage = true;
          _inEscape = false;
          _payload.clear();
        }
        // else: ignore until STX
        continue;
      }

      // in message
      if (_inEscape) {
        _payload.add(b);
        _inEscape = false;
        continue;
      }

      if (b == dle) {
        _inEscape = true;
        continue;
      }

      if (b == etx) {
        // Optionally include a single trailing control byte (e.g., LRC)
        if (includeTrailingControl && i + 1 < chunk.length) {
          final next = chunk[i + 1];
          if (next < 0x20) {
            _payload.add(next);
            i++; // consume it
          }
        }

        out.add(Uint8List.fromList(_payload));
        _payload.clear();
        _inMessage = false;
        _inEscape = false;
        continue;
      }

      _payload.add(b);
    }

    return out;
  }

  /// Reset parser state (optional).
  void reset() {
    _payload.clear();
    _inMessage = false;
    _inEscape = false;
  }



}

enum PrintStatus { ok, error, unknown, timeout }

class PrintResult {
  final PrintStatus status;
  final String? text;       // decoded string, if any
  final Uint8List? bytes;   // raw bytes, if any

  const PrintResult(this.status, {this.text, this.bytes});

  @override
  String toString() =>
      'PrintResult(status: $status, text: $text, bytes: ${bytes?.length ?? 0})';
}

typedef ResponseClassifier = PrintStatus Function(Uint8List bytes, String text);

class SerialPrintQueue {
  final SerialPortBaseDart sp;
  final Duration timeout;
  final Duration quietWindow;
  final bool stripFraming; // if STX/ETX appear in raw, strip them
  final ResponseClassifier classify;

  // serialize requests
  Future<void> _tail = Future<void>.value();

  SerialPrintQueue(
      this.sp, {
        this.timeout = const Duration(seconds: 2),
        this.quietWindow = const Duration(milliseconds: 150),
        this.stripFraming = true,
        ResponseClassifier? classifier,
      }) : classify = classifier ?? _defaultClassifier;

  /// Enqueue a text print (sends as UTF-8 code units).
  Future<PrintResult> printText(String data) {
    return enqueue(Uint8List.fromList(utf8.encode(data)));
  }
  /// Enqueue a text print (sends as UTF-8 code units).
  Future<PrintResult> printBytes(Uint8List bytes) {
    return enqueue(bytes);
  }

  /// Enqueue raw bytes to send; returns the classified result.
  Future<PrintResult> enqueue(Uint8List requestBytes) {
    final completer = Completer<PrintResult>();
    _tail = _tail.then((_) => _run(requestBytes).then(completer.complete).catchError(completer.completeError));
    return completer.future;
  }

  static PrintStatus _defaultClassifier(Uint8List bytes, String text) {
    final t = text.toUpperCase();

    final ok  = t.contains('OK')   || t.contains('EPOK') || t.contains('ESOK');
    final err = t.contains('ERR')  || t.contains('ERROR') || t.contains('NOK');

    if (ok)  return PrintStatus.ok;
    if (err) return PrintStatus.error;
    if (bytes.isNotEmpty) return PrintStatus.unknown;
    return PrintStatus.timeout;
  }

  Future<PrintResult> _run(Uint8List requestBytes) async {
    if (!sp.isConnected) {
      final opened = await sp.open();
      if (!opened) {
        return const PrintResult(PrintStatus.error, text: 'Open failed');
      }
    }

    final chunks = <int>[];
    late final StreamSubscription<DataReceive> sub;
    final done = Completer<void>();
    Timer? quiet;

    void finish() {
      if (!done.isCompleted) done.complete();
      quiet?.cancel();
    }

    sub = sp.onData.listen((evt) {
      final payload = stripFraming
          ? _stripStxEtx(Uint8List.fromList(evt.bytes))
          : Uint8List.fromList(evt.bytes);
      chunks.addAll(payload);
      quiet?.cancel();
      quiet = Timer(quietWindow, finish);
    }, onError: (_) => finish(), onDone: finish);

    final sent = await sp.sendBytes(requestBytes);
    if (!sent) {
      await sub.cancel();
      return const PrintResult(PrintStatus.error, text: 'Write failed');
    }

    final hard = Timer(timeout, finish);

    await done.future;
    hard.cancel();
    await sub.cancel();

    if (chunks.isEmpty) {
      return const PrintResult(PrintStatus.timeout);
    }

    final bytes = Uint8List.fromList(chunks);
    final text = utf8.decode(bytes, allowMalformed: true);

    final status = classify(bytes, text);
    return PrintResult(status, text: text, bytes: bytes);
  }

  static Uint8List _stripStxEtx(Uint8List data) {
    if (data.isEmpty) return data;
    var start = 0, end = data.length;
    if (data.first == 0x02) start = 1;
    if (end - start > 0 && data[end - 1] == 0x03) end -= 1;
    return Uint8List.fromList(data.sublist(start, end));
  }


}
