import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'enums.dart';
import 'print_result.dart';
import 'serial_port_handler.dart';

typedef ResponseClassifier = PrintStatus Function(Uint8List bytes, String text);

class SerialPrintQueue {
  final SerialPortHandler sp;
  final Duration timeout;
  final Duration quietWindow;
  final bool stripFraming;
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

  /// Enqueue a text print (sends as UTF-8).
  Future<PrintResult> printText(String data) =>
      enqueue(Uint8List.fromList(utf8.encode(data)));

  /// Enqueue raw bytes.
  Future<PrintResult> printBytes(Uint8List bytes) => enqueue(bytes);

  /// Enqueue request; returns classified result.
  Future<PrintResult> enqueue(Uint8List requestBytes) {
    final completer = Completer<PrintResult>();
    _tail = _tail
        .then((_) => _run(requestBytes).then(completer.complete).catchError(completer.completeError));
    return completer.future;
  }

  static PrintStatus _defaultClassifier(Uint8List bytes, String text) {
    final t = text.toUpperCase();
    final ok = t.contains('OK') || t.contains('EPOK') || t.contains('ESOK');
    final err = t.contains('ERR') || t.contains('ERROR') || t.contains('NOK');
    if (ok) return PrintStatus.ok;
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
    final done = Completer<void>();
    Timer? quiet;

    void finish() {
      if (!done.isCompleted) done.complete();
      quiet?.cancel();
    }

    final sub = sp.onData.listen((evt) {
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
