import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import '../artemis_serial_port.dart';
import '_QueuePortAdapter.dart';

typedef ResponseClassifier = PrintStatus Function(Uint8List bytes, String text);



class SerialPrintQueue {
  final QueuePort sp;

  /// Hard timeout for a full request (no activity until this expires).
  final Duration timeout;

  /// Quiet window: once we receive data, if nothing else comes in for this long,
  /// we finish and return what we collected.
  final Duration quietWindow;

  /// If true, removes STX/ETX from *incoming* frames.
  final bool stripFraming;

  /// Optional: add CRLF to outgoing text/bytes before sending.
  final bool addCrlfOnSend;

  /// Optional: wrap outgoing bytes with STX/ETX.
  final bool addFramingOnSend;

  /// Framing bytes for addFramingOnSend.
  final int stx;
  final int etx;

  /// Classifier -> map reply to ok/error/timeout/unknown.
  final ResponseClassifier classify;

  // Serialize requests to avoid concurrent sends on the same port.
  Future<void> _tail = Future<void>.value();

  SerialPrintQueue(
      this.sp, {
        this.timeout = const Duration(seconds: 2),
        this.quietWindow = const Duration(milliseconds: 150),
        this.stripFraming = true,
        this.addCrlfOnSend = false,
        this.addFramingOnSend = false,
        this.stx = 0x02,
        this.etx = 0x03,
        ResponseClassifier? classifier,
      }) : classify = classifier ?? _defaultClassifier;

  /// Enqueue a text send (ASCII by default) — applies CRLF/framing if enabled.
  Future<PrintResult> printText(String data, {Encoding encoding = ascii}) {
    var bytes = Uint8List.fromList(encoding.encode(data));
    if (addCrlfOnSend) {
      // ensure CRLF just once
      final str = data.endsWith('\r\n')
          ? data
          : data.endsWith('\r') || data.endsWith('\n')
          ? '${data.replaceAll(RegExp(r'[\r\n]+$'), '')}\r\n'
          : '$data\r\n';
      bytes = Uint8List.fromList(encoding.encode(str));
    }
    return enqueue(bytes);
  }

  /// Enqueue raw bytes — applies framing if enabled.
  Future<PrintResult> printBytes(Uint8List bytes) => enqueue(bytes);

  /// Enqueue raw bytes, serialize, send, and collect reply.
  Future<PrintResult> enqueue(Uint8List requestBytes) {
    final completer = Completer<PrintResult>();
    _tail = _tail.then((_) async {
      try {
        final res = await _run(requestBytes);
        if (!completer.isCompleted) completer.complete(res);
      } catch (e, st) {
        if (!completer.isCompleted) {
          completer.complete(
            PrintResult(PrintStatus.error, text: 'Queue error: $e'),
          );
        }
      }
    });
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

    // Prepare outgoing bytes (optional CRLF/framing – framing applied after CRLF)
    Uint8List out = requestBytes;
    if (addFramingOnSend) {
      out = _frame(out, stx: stx, etx: etx);
    }

    final chunks = <int>[];
    final done = Completer<void>();
    Timer? quiet;

    void finish() {
      if (!done.isCompleted) done.complete();
      quiet?.cancel();
    }

    // Listen to port
    final sub = sp.onData.listen((evt) {
      final raw = Uint8List.fromList(evt.bytes);

      // Optionally strip STX/ETX from *incoming* payloads.
      final payload = stripFraming ? _stripStxEtx(raw, stx, etx) : raw;

      if (payload.isNotEmpty) {
        chunks.addAll(payload);
      }
      // reset quiet window
      quiet?.cancel();
      quiet = Timer(quietWindow, finish);
    }, onError: (_) => finish(), onDone: finish);

    // Send
    final sent = await sp.sendBytes(out);
    if (!sent) {
      await sub.cancel();
      return const PrintResult(PrintStatus.error, text: 'Write failed');
    }

    // Hard timeout
    final hard = Timer(timeout, finish);

    // Wait until quiet or timeout
    await done.future;
    hard.cancel();
    await sub.cancel();

    if (chunks.isEmpty) {
      return const PrintResult(PrintStatus.timeout);
    }

    final bytes = Uint8List.fromList(chunks);
    // Prefer ASCII to avoid multibyte surprises; switch to utf8 if you expect UTF-8.
    final text = ascii.decode(bytes, allowInvalid: true);
    final status = classify(bytes, text);
    return PrintResult(status, text: text, bytes: bytes);
  }

  // ---- helpers ----

  static Uint8List _frame(Uint8List message, {required int stx, required int etx}) {
    if (message.isNotEmpty && message.first == stx && message.last == etx) {
      return message; // already framed
    }
    final framed = Uint8List(message.length + 2);
    framed[0] = stx;
    framed[framed.length - 1] = etx;
    framed.setRange(1, framed.length - 1, message);
    return framed;
  }

  static Uint8List _stripStxEtx(Uint8List input, int stx, int etx) {
    if (input.isEmpty) return input;
    var start = 0, end = input.length;
    if (input.first == stx) start = 1;
    if (end - start > 0 && input[end - 1] == etx) end -= 1;
    if (start == 0 && end == input.length) return input;
    return Uint8List.fromList(input.sublist(start, end));
  }
}
