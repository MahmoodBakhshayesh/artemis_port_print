// // serial_port_plus.dart
// import 'dart:async';
// import 'dart:developer';
// import 'dart:typed_data';
// import 'dart:convert';
// import 'package:artemis_port_print/artemis_port_print.dart';
// import 'package:artemis_port_print/util.dart';
// import 'package:flutter/foundation.dart';
// import 'package:flutter/material.dart';
// import 'package:flutter_libserialport/flutter_libserialport.dart';
//
// import 'enums.dart';
// import 'status_class.dart';
// export 'package:flutter_libserialport/flutter_libserialport.dart';
//
// class FrameParser {
//   final int stx, etx, dle;
//   final bool includeTrailingControl;
//
//   FrameParser({this.stx = 0x02, this.etx = 0x03, this.dle = 0x10, this.includeTrailingControl = false});
//
//   final List<int> _payload = [];
//   bool _in = false, _esc = false;
//
//   List<Uint8List> feed(Uint8List chunk) {
//     final out = <Uint8List>[];
//     for (var i = 0; i < chunk.length; i++) {
//       final b = chunk[i];
//       if (!_in) {
//         if (b == stx) {
//           _in = true;
//           _esc = false;
//           _payload.clear();
//         }
//         continue;
//       }
//       if (_esc) {
//         _payload.add(b);
//         _esc = false;
//         continue;
//       }
//       if (b == dle) {
//         _esc = true;
//         continue;
//       }
//       if (b == etx) {
//         if (includeTrailingControl && i + 1 < chunk.length) {
//           final n = chunk[i + 1];
//           if (n < 0x20) {
//             _payload.add(n);
//             i++;
//           }
//         }
//         out.add(Uint8List.fromList(_payload));
//         _payload.clear();
//         _in = false;
//         _esc = false;
//         continue;
//       }
//       _payload.add(b);
//     }
//     return out;
//   }
//
//   void reset() {
//     _payload.clear();
//     _in = false;
//     _esc = false;
//   }
// }
//
// class DataReceive {
//   final String text;
//   final List<int> bytes;
//   final int? indexOfBinaryByte;
//
//   DataReceive({required this.text, required this.bytes, this.indexOfBinaryByte});
// }
//
// // queue_port.dart
// abstract class QueuePort {
//   bool get isConnected;
//   Future<bool> open();                 // ensure open (no-op if already open)
//   Future<bool> close();                // optional
//   Stream<DataReceive> get onData;      // incoming payloads (already framed => payload only)
//   Future<bool> sendBytes(Uint8List message);
// }
//
//
// // --- Add this enum somewhere shared (e.g., port_status.dart) ---
// enum PortStatus { closed, opening, open, closing, error }
//
// extension PortStatusLabel on PortStatus {
//   String get label {
//     switch (this) {
//       case PortStatus.closed:  return 'Closed';
//       case PortStatus.opening: return 'Opening…';
//       case PortStatus.open:    return 'Open';
//       case PortStatus.closing: return 'Closing…';
//       case PortStatus.error:   return 'Error';
//     }
//   }
// }
//
// // ---------------- ArtemisSerialPort (refactored to PortStatus) ----------------
//
// class ArtemisSerialPort implements SerialPort {
//   final SerialPort _inner;
//   final ProtocolMode protocolMode;
//   final FrameParser _parser;
//   SerialDeviceConfig? serialDeviceConfig;
//
//   // Port connection lifecycle status
//   final ValueNotifier<PortStatus> portStatus = ValueNotifier(PortStatus.closed);
//   ValueListenable<PortStatus> get portStatusListenable => portStatus;
//
//   SerialPortReader? _reader;
//   final _dataCtrl = StreamController<DataReceive>.broadcast();
//   Stream<DataReceive> get onData => _dataCtrl.stream;
//
//   ArtemisSerialPort(
//       String name, {
//         this.protocolMode = ProtocolMode.none,
//         this.serialDeviceConfig,
//         FrameParser? parser,
//       })  : _inner = SerialPort(name),
//         _parser = parser ?? FrameParser();
//
//   // ---------- Extra helpers ----------
//   Future<bool> openReadWriteSafe() async {
//     portStatus.value = PortStatus.opening;
//     final ok = _inner.openReadWrite();
//     if (ok) {
//       _applyConfigIfAny();
//       _startListeningInternal();
//       log("it ok port is opened");
//       portStatus.value = PortStatus.open;
//     } else {
//       portStatus.value = PortStatus.error;
//     }
//     return ok;
//   }
//
//   ArtemisSerialPort setConfig(ArtemisPortPrintSetting config) {
//     serialDeviceConfig = config.getConfig;
//     if (_inner.isOpen) _applyConfigIfAny();
//     return this;
//   }
//
//   void startListening() {
//     // public method kept for compatibility (delegates to internal that sets status on errors)
//     if (_reader != null) return;
//     _startListeningInternal();
//   }
//
//   Future<void> stopListening() async {
//     _reader?.close();
//     _reader = null;
//   }
//
//   Future<bool> writeAll(List<int> data, {int timeoutMs = -1}) async {
//     final buf = Uint8List.fromList(data);
//     var off = 0;
//     while (off < buf.length) {
//       final n = _inner.write(buf.sublist(off), timeout: timeoutMs);
//       if (n <= 0) {
//         portStatus.value = PortStatus.error; // write failed
//         return false;
//       }
//       off += n;
//     }
//     return true;
//   }
//
//
//
//   /// Send bytes and collect response until quiet or timeout.
//   Future<Uint8List> sendAndRead({
//     required List<int> request,
//     Duration timeout = const Duration(seconds: 1),
//     Duration quietWindow = const Duration(milliseconds: 150),
//   }) async {
//     if (!_inner.isOpen) throw StateError('Port not open');
//     _startListeningInternal();
//
//     final completer = Completer<Uint8List>();
//     final acc = <int>[];
//     Timer? quiet;
//     late StreamSubscription sub;
//
//     void finish() async {
//       if (!completer.isCompleted) completer.complete(Uint8List.fromList(acc));
//       await sub.cancel();
//       quiet?.cancel();
//     }
//
//     sub = onData.listen((e) {
//       acc.addAll(e.bytes);
//       quiet?.cancel();
//       quiet = Timer(quietWindow, finish);
//     }, onError: (_) {
//       portStatus.value = PortStatus.error;
//       finish();
//     }, onDone: finish);
//
//     final hard = Timer(timeout, finish);
//
//     final ok = await writeAll(request);
//     if (!ok) {
//       hard.cancel();
//       await sub.cancel();
//       return Uint8List(0);
//     }
//
//     final res = await completer.future;
//     hard.cancel();
//     return res;
//   }
//
//   void _onBytes(Uint8List chunk) {
//     if (protocolMode == ProtocolMode.none) {
//       final text = utf8.decode(chunk, allowMalformed: true);
//       _dataCtrl.add(DataReceive(text: text, bytes: chunk.toList()));
//       return;
//     }
//
//     final frames = _parser.feed(chunk); // payloads only
//     for (final payload in frames) {
//       final text = utf8.decode(payload, allowMalformed: true);
//
//       int? idx;
//       for (var i = 0; i < payload.length; i++) {
//         if (payload[i] <= 31) { idx = i; break; }
//       }
//
//       _dataCtrl.add(
//         DataReceive(
//           text: text,
//           bytes: payload.toList(), // no STX/ETX here
//           indexOfBinaryByte: idx,
//         ),
//       );
//     }
//   }
//
//   void _startListeningInternal() {
//     if (!_inner.isOpen) return;
//     // DO NOT close an existing reader here; guard above prevents that.
//     _reader = SerialPortReader(_inner);
//     _reader!.stream.listen(
//       _onBytes,
//       onError: (e, st) {
//         // log('[reader] onError: $e');
//         portStatus.value = PortStatus.error;
//       },
//       onDone: () {
//         // If we intentionally restarted listening elsewhere, avoid flagging error.
//         // Only mark closed if the port is closed; otherwise keep status as-is.
//         if (!_inner.isOpen) {
//           portStatus.value = PortStatus.closed;
//         }
//         // else: leave as-is (still open)
//       },
//     );
//   }
//
//   void _applyConfigIfAny() {
//     final cfg = serialDeviceConfig;
//     if (cfg == null) return;
//     try {
//       _inner.config = SerialPortConfig()
//         ..baudRate = cfg.baudRate
//         ..bits = cfg.dataBits
//         ..parity = cfg.parity
//         ..stopBits = cfg.stopBits
//         ..setFlowControl(cfg.flowControl);
//     } catch (_) {
//       portStatus.value = PortStatus.error;
//     }
//   }
//
//   // ---------- SerialPort interface (delegation) ----------
//   @override
//   void dispose() {
//     stopListening();
//     _dataCtrl.close();
//     portStatus.value = PortStatus.closed;
//     _inner.dispose();
//   }
//
//   @override
//   bool open({required int mode}) {
//     portStatus.value = PortStatus.opening;
//     final ok = _inner.open(mode: mode);
//     if (ok) {
//       _applyConfigIfAny();
//       _startListeningInternal();
//       portStatus.value = PortStatus.open;
//     } else {
//       portStatus.value = PortStatus.error;
//     }
//     return ok;
//   }
//
//   @override
//   bool openRead() {
//     portStatus.value = PortStatus.opening;
//     final ok = _inner.openRead();
//     if (ok) {
//       _applyConfigIfAny();
//       _startListeningInternal();
//       portStatus.value = PortStatus.open;
//     } else {
//       portStatus.value = PortStatus.error;
//     }
//     return ok;
//   }
//
//   @override
//   bool openWrite() {
//     portStatus.value = PortStatus.opening;
//     final ok = _inner.openWrite();
//     if (ok) {
//       _applyConfigIfAny();
//       _startListeningInternal();
//       portStatus.value = PortStatus.open;
//     } else {
//       portStatus.value = PortStatus.error;
//     }
//     return ok;
//   }
//
//   @override
//   bool openReadWrite() {
//     portStatus.value = PortStatus.opening;
//     final ok = _inner.openReadWrite();
//     if (ok) {
//       _applyConfigIfAny();
//       _startListeningInternal();
//       portStatus.value = PortStatus.open;
//     } else {
//       portStatus.value = PortStatus.error;
//     }
//     return ok;
//   }
//
//   @override
//   bool close() {
//     portStatus.value = PortStatus.closing;
//     final ok = _inner.close();
//     // closing reader is harmless even if already closed
//     _reader?.close();
//     _reader = null;
//     portStatus.value = ok ? PortStatus.closed : PortStatus.error;
//     return ok;
//   }
//
//   @override
//   bool get isOpen => _inner.isOpen;
//
//   @override
//   String? get name => _inner.name;
//   @override
//   String? get description => _inner.description;
//   @override
//   int get transport => _inner.transport;
//   @override
//   int? get busNumber => _inner.busNumber;
//   @override
//   int? get deviceNumber => _inner.deviceNumber;
//   @override
//   int? get vendorId => _inner.vendorId;
//   @override
//   int? get productId => _inner.productId;
//   @override
//   String? get manufacturer => _inner.manufacturer;
//   @override
//   String? get productName => _inner.productName;
//   @override
//   String? get serialNumber => _inner.serialNumber;
//   @override
//   String? get macAddress => _inner.macAddress;
//
//   @override
//   SerialPortConfig get config => _inner.config;
//   @override
//   set config(SerialPortConfig c) => _inner.config = c;
//
//   @override
//   Uint8List read(int bytes, {int timeout = -1}) =>
//       _inner.read(bytes, timeout: timeout);
//
//   @override
//   int write(Uint8List bytes, {int timeout = -1}) =>
//       _inner.write(bytes, timeout: timeout);
//
//   @override
//   int get bytesAvailable => _inner.bytesAvailable;
//   @override
//   int get bytesToWrite => _inner.bytesToWrite;
//   @override
//   void flush([int buffers = SerialPortBuffer.both]) => _inner.flush(buffers);
//   @override
//   void drain() => _inner.drain();
//   @override
//   int get signals => _inner.signals;
//   @override
//   bool startBreak() => _inner.startBreak();
//   @override
//   bool endBreak() => _inner.endBreak();
//   @override
//   int get address => _inner.address;
//
//   // Optional helper widget (now shows PortStatus)
//   Widget get getWidget => ValueListenableBuilder<PortStatus>(
//     valueListenable: portStatus,
//     builder: (context, ps, _) {
//       switch (ps) {
//         case PortStatus.closed:
//           return const Text('🔒 Port: Closed');
//         case PortStatus.opening:
//           return const Text('⏳ Port: Opening…');
//         case PortStatus.open:
//           return const Text('🟢 Port: Open');
//         case PortStatus.closing:
//           return const Text('🔄 Port: Closing…');
//         case PortStatus.error:
//           return const Text('⚠️ Port: Error');
//       }
//     },
//   );
// }
//


import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'enums.dart';

// ---------- Types you already have ----------
// enum ProtocolMode { none, framed }


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
class DataReceive {
  final String text;
  final List<int> bytes;
  final int? indexOfBinaryByte;

  DataReceive({required this.text, required this.bytes, this.indexOfBinaryByte});
}
enum PrintStatus { ok, error, unknown, timeout }

class PrintResult {
  final PrintStatus status;
  final String? text; // decoded string, if any
  final Uint8List? bytes; // raw bytes, if any

  const PrintResult(this.status, {this.text, this.bytes});

  @override
  String toString() => 'PrintResult(status: $status, text: $text, bytes: ${bytes?.length ?? 0})';
}


class ArtemisPortPrintSetting {
  PrintType printType;
  ConnectionType connectionType;
  String portName;
  BaudRate baudRate;
  DataBits dataBits;
  Parity parity;
  StopBits stopBits;
  ProtocolMode protocolMode;
  int receivedBytesThreshold;
  Handshake handshake;
  bool dtr;
  bool rts;
  bool logoBinary;
  bool resetBin;
  int readTimeOut;
  int writeTimoOut;

  ArtemisPortPrintSetting({
    this.printType = PrintType.aea,
    this.connectionType = ConnectionType.com,
    required this.portName,
    this.baudRate = BaudRate.br_19200,
    this.dataBits = DataBits.db_8,
    this.parity = Parity.none,
    this.stopBits = StopBits.one,
    this.protocolMode = ProtocolMode.none,
    this.receivedBytesThreshold = 1,
    this.handshake = Handshake.none,
    this.dtr = true,
    this.rts = true,
    this.logoBinary = false,
    this.resetBin = false,
    this.readTimeOut = 8000,
    this.writeTimoOut = 8000,
  });

  SerialDeviceConfig get getConfig => SerialDeviceConfig(
    portName: portName,
    baudRate: baudRate.value,
    dataBits: dataBits.value,
    parity: parity.value,
    stopBits: stopBits.value,
    protocolMode: protocolMode,
    readTimeout: Duration(milliseconds: readTimeOut),
    writeTimeout: Duration(milliseconds: writeTimoOut),
    dtrEnable: dtr,
    rtsEnable: rts,
    flowControl: handshake.value,
  );
}

enum PortStatus { closed, opening, open, closing, error }

/// Very small frame parser utility (STX/ETX). Returns payloads (no STX/ETX).
class FrameParser {
  final int stx;
  final int etx;
  final bool includeTrailingControl;

  final _buf = BytesBuilder();

  FrameParser({
    this.stx = 0x02,
    this.etx = 0x03,
    this.includeTrailingControl = false,
  });

  List<Uint8List> feed(Uint8List chunk) {
    final out = <Uint8List>[];
    for (final b in chunk) {
      _buf.add([b]);
      final bytes = _buf.toBytes();
      // find first STX
      final s = bytes.indexOf(stx);
      if (s < 0) {
        // keep buffering (no STX yet)
        _buf.clear();
        _buf.add(bytes);
        continue;
      }
      // keep only from STX
      if (s > 0) {
        _buf.clear();
        _buf.add(bytes.sublist(s));
      }
      final current = _buf.toBytes();
      final e = current.lastIndexOf(etx);
      if (e > 0) {
        // payload between (0:STX ... e:ETX)
        final payload = current.sublist(1, e);
        if (includeTrailingControl) {
          // (optional) keep one control/check byte after ETX if protocol needs it
        }
        out.add(Uint8List.fromList(payload));
        // keep remainder (after ETX) for next feeds
        final rem = current.sublist(e + 1);
        _buf.clear();
        if (rem.isNotEmpty) _buf.add(rem);
      }
    }
    return out;
  }
}

// ---------- Rewritten class ----------
class ArtemisSerialPort implements SerialPort {
  final SerialPort _inner;
  final FrameParser _parser;
  SerialDeviceConfig? serialDeviceConfig;

  // Protocol constants (align with working class)
  int stx = 0x02; // STX
  int etx = 0x03; // ETX

  // Mirror fields (optional)
  String response = '';
  String statusResponse = '';

  // Status
  final ValueNotifier<PortStatus> portStatus = ValueNotifier(PortStatus.closed);
  ValueListenable<PortStatus> get portStatusListenable => portStatus;

  // IO
  SerialPortReader? _reader;
  final _dataCtrl = StreamController<DataReceive>.broadcast();
  Stream<DataReceive> get onData => _dataCtrl.stream;

  ArtemisSerialPort(
      String name, {
        SerialDeviceConfig? config,
        FrameParser? parser,
      })  : _inner = SerialPort(name),
        serialDeviceConfig = config,
        _parser = parser ?? FrameParser();

  // -------------------------- Open / Close --------------------------

  Future<bool> openReadWriteSafe() async {
    portStatus.value = PortStatus.opening;

    if (_inner.isOpen) {
      _applyConfigIfAny();
      _startListeningInternal();
      portStatus.value = PortStatus.open;
      return true;
    }

    final ok = _inner.openReadWrite();
    if (!ok) {
      portStatus.value = PortStatus.error;
      return false;
    }

    _applyConfigIfAny();
    _startListeningInternal();
    portStatus.value = PortStatus.open;
    return true;
  }

  ArtemisSerialPort setConfig(ArtemisPortPrintSetting cfg) {
    serialDeviceConfig = cfg.getConfig;
    if (_inner.isOpen) _applyConfigIfAny();
    return this;
  }

  void startListening() {
    if (_reader != null) return;
    _startListeningInternal();
  }

  Future<void> stopListening() async {
    _reader?.close();
    _reader = null;
  }

  // -------------------------- Write helpers --------------------------

  /// Low-level chunked write (returns true if all bytes written).
  Future<bool> writeAll(List<int> data, {int timeoutMs = -1}) async {
    final buf = Uint8List.fromList(data);
    var off = 0;
    while (off < buf.length) {
      final n = _inner.write(buf.sublist(off), timeout: timeoutMs);
      if (n <= 0) {
        portStatus.value = PortStatus.error;
        return false;
      }
      off += n;
    }
    return true;
  }

  /// Frame and send raw bytes: STX + payload + ETX.
  Future<bool> sendBytes(List<int> message) async {
    response = '';
    statusResponse = '';
    if (!_inner.isOpen) {
      final ok = await openReadWriteSafe();
      if (!ok) return false;
    }
    final framed = _frameBytes(Uint8List.fromList(message));
    return writeAll(framed);
  }

  /// Frame and send a list of strings. Encodes with ASCII and strips CR/LF inside.
  Future<bool> sendStrings(List<String> messages, {Encoding enc = ascii}) async {
    response = '';
    statusResponse = '';
    if (!_inner.isOpen) {
      final ok = await openReadWriteSafe();
      if (!ok) return false;
    }
    final payload = _packStrings(messages, enc: enc);
    if (payload == null) return false;
    final framed = _frameBytes(payload);
    return writeAll(framed);
  }

  /// Send and collect response until quiet or timeout.
  Future<Uint8List> sendAndRead({
    required List<int> request,
    Duration timeout = const Duration(seconds: 1),
    Duration quietWindow = const Duration(milliseconds: 150),
  }) async {
    if (!_inner.isOpen) {
      final ok = await openReadWriteSafe();
      if (!ok) return Uint8List(0);
    }
    _startListeningInternal();

    final completer = Completer<Uint8List>();
    final chunks = <int>[];
    Timer? quiet;
    late StreamSubscription sub;

    void finish() async {
      if (!completer.isCompleted) completer.complete(Uint8List.fromList(chunks));
      await sub.cancel();
      quiet?.cancel();
    }

    final hard = Timer(timeout, finish);
    sub = onData.listen((evt) {
      chunks.addAll(evt.bytes);
      quiet?.cancel();
      quiet = Timer(quietWindow, finish);
    }, onError: (_) {
      portStatus.value = PortStatus.error;
      finish();
    }, onDone: finish);

    final ok = await sendBytes(request);
    if (!ok) {
      hard.cancel();
      await sub.cancel();
      return Uint8List(0);
    }

    final resp = await completer.future;
    hard.cancel();
    return resp;
  }

  // -------------------------- RX path --------------------------

  void _onBytes(Uint8List chunk) {
    // Auto-detect frames even if config says 'none'
    final looksFramed = chunk.contains(stx) || chunk.contains(etx);

    if (!looksFramed && (serialDeviceConfig?.protocolMode ?? ProtocolMode.none) == ProtocolMode.none) {
      // pass-through, no framing
      final text = ascii.decode(chunk, allowInvalid: true);
      response = text;
      _dataCtrl.add(DataReceive(text: text, bytes: chunk.toList()));
      return;
    }

    // Framed: return payloads only (no STX/ETX)
    final frames = _parser.feed(chunk);
    for (final payload in frames) {
      final clean = _stripStxEtx(payload);
      final text = ascii.decode(clean, allowInvalid: true);

      // keep last human-readable response; skip SQNI noise per your working class
      if (!(text.contains('SQNI#') && !text.contains('EPOK') && !text.contains('ESOK'))) {
        response = text;
      }

      int? idx;
      for (var i = 0; i < clean.length; i++) {
        if (clean[i] <= 31) { idx = i; break; }
      }

      _dataCtrl.add(
        DataReceive(text: text, bytes: clean.toList(), indexOfBinaryByte: idx),
      );
    }
  }

  // -------------------------- Internals --------------------------

  Uint8List _frameBytes(Uint8List message) {
    if (message.isNotEmpty && message.first == stx && message.last == etx) {
      return message; // already framed
    }
    final framed = Uint8List(message.length + 2);
    framed[0] = stx;
    framed[framed.length - 1] = etx;
    framed.setRange(1, framed.length - 1, message);
    return framed;
  }

  Uint8List? _packStrings(List<String> messages, {Encoding enc = ascii}) {
    try {
      final result = BytesBuilder();
      var isLogoBinary = false;

      final anyMG = messages.any((m) => m.trim().startsWith('MG'));

      for (final msg in messages) {
        if (msg.startsWith('kiosk')) {
          // raw kiosk bytes in base64, bypass framing of payload
          final base64 = msg.replaceFirst('kiosk', '');
          final raw = base64Decode(base64);
          return Uint8List.fromList(raw);
        }

        if (msg.startsWith('base64')) {
          final base64 = msg.replaceFirst('base64', '');
          var bytes = base64Decode(base64);

          if (isLogoBinary) {
            // escape non-printable with DLE=0x10 like your working class
            final esc = <int>[];
            for (final b in bytes) {
              if (!(b >= 33 && b <= 127)) esc.add(0x10);
              esc.add(b);
            }
            bytes = Uint8List.fromList(esc);
          }

          if (result.length > 0 && anyMG) {
            result.add([10]); // LF between MG segments
          }
          result.add(bytes);
        } else {
          // plain text segment (strip CR/LF inside)
          final stripped = msg.replaceAll('\r', '').replaceAll('\n', '');
          final bytes = enc.encode(stripped);
          if (result.length > 0 && anyMG) {
            result.add([10]); // LF between MG segments
          }
          if (stripped.trim().startsWith('LT') && messages.any((m) => m.contains('base64'))) {
            isLogoBinary = true;
          }
          result.add(bytes);
        }
      }

      return result.toBytes();
    } catch (_) {
      return null;
    }
  }

  void _startListeningInternal() {
    if (!_inner.isOpen) return;
    if (_reader != null) return; // don’t double-attach

    _reader = SerialPortReader(_inner);
    _reader!.stream.listen(
      _onBytes,
      onError: (e, st) {
        portStatus.value = PortStatus.error;
      },
      onDone: () {
        if (!_inner.isOpen) {
          portStatus.value = PortStatus.closed;
        }
      },
      cancelOnError: false,
    );
  }

  void _applyConfigIfAny() {
    final cfg = serialDeviceConfig;
    if (cfg == null) return;
    try {
      final c = SerialPortConfig()
        ..baudRate = cfg.baudRate
        ..bits = cfg.dataBits
        ..parity = cfg.parity
        ..stopBits = cfg.stopBits
        ..setFlowControl(cfg.flowControl);
      _inner.config = c;
    } catch (_) {
      portStatus.value = PortStatus.error;
    }
  }

  Uint8List _stripStxEtx(Uint8List data) {
    var start = 0, end = data.length;
    if (end > 0 && data[0] == stx) start = 1;
    if (end - start > 0 && data[end - 1] == etx) end -= 1;
    return Uint8List.fromList(data.sublist(start, end));
  }

  // -------------------------- SerialPort interface (delegation) --------------------------

  @override
  void dispose() {
    stopListening();
    _dataCtrl.close();
    portStatus.value = PortStatus.closed;
    _inner.dispose();
  }

  @override
  bool open({required int mode}) {
    portStatus.value = PortStatus.opening;
    final ok = _inner.open(mode: mode);
    if (ok) {
      _applyConfigIfAny();
      _startListeningInternal();
      portStatus.value = PortStatus.open;
    } else {
      portStatus.value = PortStatus.error;
    }
    return ok;
  }

  @override
  bool openRead() => open(mode: SerialPortMode.read);

  @override
  bool openWrite() => open(mode: SerialPortMode.write);

  @override
  bool openReadWrite() => open(mode: SerialPortMode.readWrite);

  @override
  bool close() {
    portStatus.value = PortStatus.closing;
    final ok = _inner.close();
    _reader?.close();
    _reader = null;
    portStatus.value = ok ? PortStatus.closed : PortStatus.error;
    return ok;
  }

  @override
  bool get isOpen => _inner.isOpen;

  @override
  String? get name => _inner.name;
  @override
  String? get description => _inner.description;
  @override
  int get transport => _inner.transport;
  @override
  int? get busNumber => _inner.busNumber;
  @override
  int? get deviceNumber => _inner.deviceNumber;
  @override
  int? get vendorId => _inner.vendorId;
  @override
  int? get productId => _inner.productId;
  @override
  String? get manufacturer => _inner.manufacturer;
  @override
  String? get productName => _inner.productName;
  @override
  String? get serialNumber => _inner.serialNumber;
  @override
  String? get macAddress => _inner.macAddress;

  @override
  SerialPortConfig get config => _inner.config;
  @override
  set config(SerialPortConfig c) => _inner.config = c;

  @override
  Uint8List read(int bytes, {int timeout = -1}) =>
      _inner.read(bytes, timeout: timeout);

  @override
  int write(Uint8List bytes, {int timeout = -1}) =>
      _inner.write(bytes, timeout: timeout);

  @override
  int get bytesAvailable => _inner.bytesAvailable;
  @override
  int get bytesToWrite => _inner.bytesToWrite;
  @override
  void flush([int buffers = SerialPortBuffer.both]) => _inner.flush(buffers);
  @override
  void drain() => _inner.drain();
  @override
  int get signals => _inner.signals;
  @override
  bool startBreak() => _inner.startBreak();
  @override
  bool endBreak() => _inner.endBreak();
  @override
  int get address => _inner.address;

  // -------------------------- Tiny UI helper --------------------------
  Widget get getWidget => ValueListenableBuilder<PortStatus>(
    valueListenable: portStatus,
    builder: (context, ps, _) {
      switch (ps) {
        case PortStatus.closed:
          return const Text('🔒 Port: Closed');
        case PortStatus.opening:
          return const Text('⏳ Port: Opening…');
        case PortStatus.open:
          return const Text('🟢 Port: Open');
        case PortStatus.closing:
          return const Text('🔄 Port: Closing…');
        case PortStatus.error:
          return const Text('⚠️ Port: Error');
      }
    },
  );
}