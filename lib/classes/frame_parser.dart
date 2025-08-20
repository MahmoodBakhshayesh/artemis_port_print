import 'dart:typed_data';

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