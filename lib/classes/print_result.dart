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

  Map<String, dynamic> toJson() {
    return {
      'status': status.toString().split('.').last,
      'text': text,
      'bytes': bytes,
    };
  }

  factory PrintResult.fromJson(Map<String, dynamic> json) {
    return PrintResult(
      PrintStatus.values.byName(json['status']),
      text: json['text'],
      bytes: json['bytes'] != null ? Uint8List.fromList(json['bytes'].cast<int>()) : null,
    );
  }
}
