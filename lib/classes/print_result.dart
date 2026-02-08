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
    T enumFromString<T>(List<T> values, String value) {
      return values.firstWhere((v) => v.toString().split('.').last.toLowerCase() == value.toLowerCase());
    }
    return PrintResult(
      enumFromString(PrintStatus.values, json['status']),
      text: json['text'],
      bytes: json['bytes'] != null ? Uint8List.fromList(json['bytes'].cast<int>()) : null,
    );
  }
}
