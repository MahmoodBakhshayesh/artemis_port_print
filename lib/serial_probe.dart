import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class SerialProbe {
  /// Returns [value] plus 1.

  Future<void> test6() async {
    const portName = 'COM3'; // <-- change to your port
    log('Available: ${SerialPort.availablePorts}');

    final candidatesBaud = [9600, 19200, 38400, 57600, 115200];
    final candidatesParity = [0, 1, 2]; // none, odd, even
    final candidatesStop = [1, 2];
    final candidatesFlow = [SerialPortFlowControl.none, SerialPortFlowControl.rtsCts, SerialPortFlowControl.xonXoff, SerialPortFlowControl.dtrDsr];

    // Common queries:
    final escposInit = [0x1B, 0x40]; // ESC @
    final escposStat1 = [0x10, 0x04, 0x01]; // DLE EOT 1
    final escposStat2 = [0x10, 0x04, 0x04]; // DLE EOT 4 (paper)
    final zplHS = '~HS\r\n'.codeUnits; // ZPL: printer status
    final zplHelp = '^XA^HH^XZ\r\n'.codeUnits; // ZPL: config/help
    final tsplAuto = 'AUTOBAUD\r\n'.codeUnits; // TSPL: sync baud (some)
    final tsplGet = 'GET STATUS\r\n'.codeUnits; // TSPL: status (varies)

    for (final baud in candidatesBaud) {
      for (final parity in candidatesParity) {
        for (final stop in candidatesStop) {
          for (final flow in candidatesFlow) {
            final port = SerialPort(portName);
            log('\n--- Trying baud=$baud parity=$parity stop=$stop flow=$flow ---');

            if (!port.openReadWrite()) {
              log('openReadWrite() failed: ${SerialPort.lastError}');
              continue;
            }

            final cfg = SerialPortConfig()
              ..baudRate = baud
              ..bits = 8
              ..parity = parity
              ..stopBits = stop
              ..setFlowControl(flow);
            port.config = cfg;

            // Small settle + drain any stale bytes
            await Future<void>.delayed(const Duration(milliseconds: 120));
            await drainSerial(port);

            final tests = <List<int>>[escposInit, escposStat1, escposStat2, zplHS, zplHelp, tsplAuto, tsplGet];

            bool any = false;
            for (final t in tests) {
              final ok = await writeAll(port, t);
              if (!ok) {
                log('write failed');
                break;
              }
              final res = await readUntilQuiet(port);
              if (res.isNotEmpty) {
                any = true;
                log('RESPONSE ${res.length} bytes  hex:[${hex(res)}]  ascii:"${asciiPreview(res)}"');
                log('>>> WORKS with baud=$baud parity=$parity stop=$stop flow=$flow');
                break;
              } else {
                await Future<void>.delayed(const Duration(milliseconds: 120));
              }
            }

            try {
              port.close();
            } catch (_) {}

            if (any) {
              log('\nFound a working configuration above — stop scanning further.');
              return;
            }
          }
        }
      }
    }

    log(
      '\nNo responses on any tried combination.\n'
          '- Check wiring (TX/RX crossed if needed, or use a proper USB-serial)\n'
          '- Confirm device actually replies on serial and which commands\n'
          '- Ensure no other app has the COM port open\n'
          '- Verify exact baud/parity/stop/flow from the printer manual\n',
    );
  }
}

String hex(List<int> b) => b.map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');

String asciiPreview(List<int> b) => String.fromCharCodes(b.map((x) => (x >= 32 && x <= 126) ? x : 46));

Future<void> drainSerial(SerialPort port, {Duration forTime = const Duration(milliseconds: 120)}) async {
  // Drain any stale input by listening briefly and discarding.
  final reader = SerialPortReader(port);
  late StreamSubscription sub;
  sub = reader.stream.listen((_) {}, onError: (_) {});
  await Future<void>.delayed(forTime);
  await sub.cancel();
}

Future<Uint8List> readUntilQuiet(SerialPort port, {Duration timeout = const Duration(seconds: 2), Duration quiet = const Duration(milliseconds: 180)}) async {
  final reader = SerialPortReader(port);
  final out = <int>[];
  final done = Completer<Uint8List>();
  Timer? q;
  late StreamSubscription sub;

  void finish() async {
    if (!done.isCompleted) done.complete(Uint8List.fromList(out));
    await sub.cancel();
    q?.cancel();
  }

  final hard = Timer(timeout, finish);

  sub = reader.stream.listen(
    (chunk) {
      out.addAll(chunk);
      q?.cancel();
      q = Timer(quiet, finish);
    },
    onError: (_) => finish(),
    onDone: finish,
  );

  final res = await done.future;
  hard.cancel();
  return res;
}

Future<bool> writeAll(SerialPort port, List<int> data) async {
  final buf = Uint8List.fromList(data);
  var off = 0;
  while (off < buf.length) {
    final n = port.write(buf.sublist(off));
    if (n == null || n <= 0) return false;
    off += n;
  }
  return true;
}

