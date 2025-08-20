import 'dart:typed_data';

import 'enums.dart';

class PrintResult {
  final PrintStatus status;
  final String? text;       // decoded string, if any
  final Uint8List? bytes;   // raw bytes, if any

  const PrintResult(this.status, {this.text, this.bytes});

  @override
  String toString() =>
      'PrintResult(status: $status, text: $text, bytes: ${bytes?.length ?? 0})';
}