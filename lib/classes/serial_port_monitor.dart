import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';

/// Similar to your DeviceAvailableEvent payload
class DeviceAvailable {
  final bool available;
  final bool offline;
  final String lastStatus;

  DeviceAvailable({
    required this.available,
    this.offline = false,
    required this.lastStatus,
  });

  @override
  String toString() =>
      'DeviceAvailable(available=$available, offline=$offline, lastStatus=$lastStatus)';
}

class SerialPortMonitor {
  SerialPortMonitor(this.portName);

  final String portName;

  SerialPort? _port;
  SerialPortReader? _reader;

  StreamSubscription<Uint8List>? _dataSub;
  Timer? _pinPollTimer;

  final _dataController = StreamController<Uint8List>.broadcast();
  final _availabilityController = StreamController<DeviceAvailable>.broadcast();

  Stream<Uint8List> get onData => _dataController.stream; // DataReceived equivalent
  Stream<DeviceAvailable> get onAvailability => _availabilityController.stream;

  // State similar to your C# logic
  bool _deviceAvailable = false;
  String _lastStatus = 'unknown';
  DateTime _lastOccurred = DateTime.fromMillisecondsSinceEpoch(0);

  bool _lastCts = false;
  bool _lastDsr = false;

  Future<void> start({
    required int baudRate,
    Duration pinPollInterval = const Duration(milliseconds: 200),
  }) async {
    final port = SerialPort(portName);

    if (!port.openReadWrite()) {
      throw StateError(
        'Could not open $portName: ${SerialPort.lastError}',
      );
    }

    // Configure port
    final config = port.config;
    config.baudRate = baudRate;
    config.bits = 8;
    config.stopBits = 1;
    config.parity = SerialPortParity.none;
    port.config = config;

    _port = port;

    // ---- DataReceived equivalent: async stream of bytes ----
    _reader = SerialPortReader(port);
    _dataSub = _reader!.stream.listen(
          (Uint8List bytes) {
        _dataController.add(bytes);
      },
      onError: (e, st) {
        // handle/log error
      },
      cancelOnError: false,
    );

    // Initialize last pin states
    final (cts, dsr) = _readCtsDsr(port);
    _lastCts = cts;
    _lastDsr = dsr;

    // ---- PinChanged equivalent: poll and detect changes ----
    _pinPollTimer = Timer.periodic(pinPollInterval, (_) async {
      if (_port == null) return;

      final (newCts, newDsr) = _readCtsDsr(_port!);

      if (newCts == _lastCts && newDsr == _lastDsr) return;

      _lastCts = newCts;
      _lastDsr = newDsr;

      // Match your "Task.Delay(500)" debounce
      await Future<void>.delayed(const Duration(milliseconds: 500));

      _handlePinChanged(
        ctsHolding: newCts,
        dsrHolding: newDsr,
        occurred: DateTime.now(),
      );
    });
  }

  (bool cts, bool dsr) _readCtsDsr(SerialPort port) {
    // port.signals is a bitmask of SerialPortSignal.* constants. :contentReference[oaicite:2]{index=2}
    final signals = port.signals;
    final cts = (signals & SerialPortSignal.cts) != 0;
    final dsr = (signals & SerialPortSignal.dsr) != 0;
    return (cts, dsr);
  }

  void _handlePinChanged({
    required bool ctsHolding,
    required bool dsrHolding,
    required DateTime occurred,
  }) {
    // (Optional) log like your C#:
    // print('[CTS: $ctsHolding, DSR: $dsrHolding] Changed.');

    // Direct mapping of your state machine:
    if (!ctsHolding && !dsrHolding) {
      _deviceAvailable = false;
      _lastStatus = 'poweroff';
      _availabilityController.add(
        DeviceAvailable(available: _deviceAvailable, lastStatus: _lastStatus),
      );
      _lastOccurred = occurred;
      return;
    } else if (dsrHolding && !ctsHolding) {
      _deviceAvailable = false;
      _lastStatus = 'offline';
      _availabilityController.add(
        DeviceAvailable(
          available: _deviceAvailable,
          offline: true,
          lastStatus: _lastStatus,
        ),
      );
      _lastOccurred = occurred;
      return;
    } else if (dsrHolding && ctsHolding) {
      _deviceAvailable = true;
      _lastStatus = 'ready';
      _availabilityController.add(
        DeviceAvailable(available: _deviceAvailable, lastStatus: _lastStatus),
      );
      _lastOccurred = occurred;
      return;
    }

    // Your "within 1 second" heuristic:
    final diffSeconds = occurred.difference(_lastOccurred).inMilliseconds / 1000.0;
    if (diffSeconds <= 1) {
      _deviceAvailable = dsrHolding || ctsHolding;
    } else {
      _deviceAvailable = !(!ctsHolding && !dsrHolding);
    }

    _availabilityController.add(
      DeviceAvailable(available: _deviceAvailable, lastStatus: _lastStatus),
    );

    _lastOccurred = occurred;
  }

  Future<void> stop() async {
    _pinPollTimer?.cancel();
    _pinPollTimer = null;

    await _dataSub?.cancel();
    _dataSub = null;

    _reader = null;

    final port = _port;
    _port = null;
    if (port != null) {
      try {
        port.close();
      } finally {
        port.dispose();
      }
    }
  }
}
