import 'dart:async';
import 'dart:typed_data';

import '../artemis_serial_port.dart';

// Uses your ArtemisSerialPort and DataReceive types
// import 'package:your_pkg/artemis_serial_port.dart';

/// Minimal interface the queue needs.
abstract class QueuePort {
  bool get isConnected;
  Future<bool> open();
  Future<bool> close();
  Stream<DataReceive> get onData;
  Future<bool> sendBytes(Uint8List message);
}

/// Adapter: map ArtemisSerialPort to QueuePort without changing send semantics.
/// Important: uses port.writeAll(...) so outgoing data is sent *as-is*
/// (i.e., framing/CRLF can be handled in SerialPrintQueue if you enable those flags).
class QueuePortAdapter implements QueuePort {
  final ArtemisSerialPort port;
  QueuePortAdapter(this.port);

  @override
  bool get isConnected => port.isOpen;

  @override
  Future<bool> open() async {
    final ok = await port.openReadWriteSafe();
    if (ok) port.startListening();
    return ok;
  }

  @override
  Future<bool> close() async => port.close();

  @override
  Stream<DataReceive> get onData => port.onData;

  @override
  Future<bool> sendBytes(Uint8List message) => port.writeAll(message);
}
