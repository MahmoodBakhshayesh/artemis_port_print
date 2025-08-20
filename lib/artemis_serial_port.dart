// serial_port_plus.dart
import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:convert';
import 'package:artemis_port_print/artemis_port_print.dart';
import 'package:artemis_port_print/util.dart';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'classes/enums.dart';
import 'classes/status_class.dart';
export 'package:flutter_libserialport/flutter_libserialport.dart';

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

// class DataReceive {
//   final String text;
//   final List<int> bytes;
//   final int? indexOfBinaryByte;
//
//   DataReceive({required this.text, required this.bytes, this.indexOfBinaryByte});
// }

// class ArtemisSerialPort implements SerialPort {
//   final SerialPort _inner;
//   final ProtocolMode protocolMode;
//   final FrameParser _parser;
//   SerialDeviceConfig? serialDeviceConfig;
//
//   final _status = ValueNotifier<PrinterStatus>(PrinterStatus.offline);
//
//   ValueNotifier<PrinterStatus> get status => _status;
//
//   SerialPortReader? _reader;
//   final _dataCtrl = StreamController<DataReceive>.broadcast();
//
//   Stream<DataReceive> get onData => _dataCtrl.stream;
//
//   ArtemisSerialPort(String name, {this.protocolMode = ProtocolMode.none, this.serialDeviceConfig, FrameParser? parser}) : _inner = SerialPort(name), _parser = parser ?? FrameParser();
//
//   // ---------- Extra helpers ----------
//   Future<bool> openReadWriteSafe() async => _inner.openReadWrite();
//
//   ArtemisSerialPort setConfig(ArtemisPortPrintSetting config) {
//     serialDeviceConfig = config.getConfig;
//     return this;
//   }
//
//   Future<PrintResult> printData(String data) {
//     return ArtemisPortPrint.print(this, data);
//   }
//
//   Future<void> connect() async {
//     status.value = PrinterStatus.connecting;
//     await ArtemisPortPrint.open(this);
//     status.value = PrinterStatus.ready;
//   }
//
//   Future<void> disconnect() async {
//     status.value = PrinterStatus.connecting;
//     await ArtemisPortPrint.close(this);
//     status.value = PrinterStatus.offline;
//   }
//
//   Future<void> queryStatus() async {
//     // final res = await printDataRaw(Uint8List.fromList([0x10, 0x04, 0x04]));
//     final status = await ArtemisPortPrint.testQuery(this);
//     log(status.toString());
//   }
//
//   // your previous function turned into a queued, returning call
//
//   void startListening() {
//     _reader?.close();
//     _reader = SerialPortReader(_inner);
//     _reader!.stream.listen(_onBytes, onError: (_) {}, onDone: () {});
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
//       if (n <= 0) return false;
//       off += n;
//     }
//     return true;
//   }
//
//   /// Send bytes and collect response until quiet or timeout.
//   Future<Uint8List> sendAndRead({required List<int> request, Duration timeout = const Duration(seconds: 1), Duration quietWindow = const Duration(milliseconds: 150)}) async {
//     if (!_inner.isOpen) throw StateError('Port not open');
//     // ensure listening
//     startListening();
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
//     // Listen to payloads only (from _onBytes)
//     sub = onData.listen((e) {
//       acc.addAll(e.bytes);
//       quiet?.cancel();
//       quiet = Timer(quietWindow, finish);
//     });
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
//       // passthrough
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
//         if (payload[i] <= 31) {
//           idx = i;
//           break;
//         }
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
//   // ---------- SerialPort interface (delegation) ----------
//   @override
//   void dispose() {
//     stopListening();
//     _inner.dispose();
//   }
//
//   @override
//   bool open({required int mode}) => _inner.open(mode: mode);
//
//   @override
//   bool openRead() => _inner.openRead();
//
//   @override
//   bool openWrite() => _inner.openWrite();
//
//   @override
//   bool openReadWrite() => _inner.openReadWrite();
//
//   @override
//   bool close() => _inner.close();
//
//   @override
//   bool get isOpen => _inner.isOpen;
//
//   @override
//   String? get name => _inner.name;
//
//   @override
//   String? get description => _inner.description;
//
//   @override
//   int get transport => _inner.transport;
//
//   @override
//   int? get busNumber => _inner.busNumber;
//
//   @override
//   int? get deviceNumber => _inner.deviceNumber;
//
//   @override
//   int? get vendorId => _inner.vendorId;
//
//   @override
//   int? get productId => _inner.productId;
//
//   @override
//   String? get manufacturer => _inner.manufacturer;
//
//   @override
//   String? get productName => _inner.productName;
//
//   @override
//   String? get serialNumber => _inner.serialNumber;
//
//   @override
//   String? get macAddress => _inner.macAddress;
//
//   @override
//   SerialPortConfig get config => _inner.config;
//
//   @override
//   set config(SerialPortConfig c) => _inner.config = c;
//
//   @override
//   Uint8List read(int bytes, {int timeout = -1}) => _inner.read(bytes, timeout: timeout);
//
//   @override
//   int write(Uint8List bytes, {int timeout = -1}) => _inner.write(bytes, timeout: timeout);
//
//   @override
//   int get bytesAvailable => _inner.bytesAvailable;
//
//   @override
//   int get bytesToWrite => _inner.bytesToWrite;
//
//   @override
//   void flush([int buffers = SerialPortBuffer.both]) => _inner.flush(buffers);
//
//   @override
//   void drain() => _inner.drain();
//
//   @override
//   int get signals => _inner.signals;
//
//   @override
//   bool startBreak() => _inner.startBreak();
//
//   @override
//   bool endBreak() => _inner.endBreak();
//
//   @override
//   int get address => _inner.address;
//
//   Widget get getWidget => ValueListenableBuilder(
//     valueListenable: status,
//     builder: (context, PrinterStatus status, _) {
//       switch (status) {
//         case PrinterStatus.offline:
//           return const Text("🔴 Offline");
//         case PrinterStatus.ready:
//           return const Text("🟢 Ready");
//         case PrinterStatus.printing:
//           return const Text("🖨 Printing...");
//         case PrinterStatus.waiting:
//           return const Text("⌛ Waiting response...");
//         case PrinterStatus.error:
//           return const Text("⚠️ Error");
//         case PrinterStatus.connecting:
//           return const Text("🔄 Connecting...");
//       }
//     },
//   );
//
//   // Note: static members (availablePorts, lastError) are accessed via SerialPort.
// }
