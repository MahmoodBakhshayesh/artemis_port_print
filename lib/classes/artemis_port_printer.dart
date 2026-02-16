import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'artemis_logger.dart';
import 'artemis_port_device.dart';
import 'enums.dart';
import 'i_artemis_device.dart';
import 'print_result.dart';
import 'serial_port_handler.dart';
import 'serial_print_queue.dart';
import 'status_class.dart';

class ArtemisPortPrinter extends ArtemisPortDevice implements IArtemisDevice {
  late final SerialPortHandler _handler;
  late final SerialPrintQueue _queue;
  final ValueNotifier<DeviceConnectionStatus> _connectionStatus =
      ValueNotifier(DeviceConnectionStatus.disconnected);
  final ValueNotifier<String> _statusImagePathNotifier =
      ValueNotifier('assets/images/devices/notExist/PRN.png');

  ArtemisPortPrinter({
    required super.portName,
    super.config,
    super.enableLogging = false,
    ArtemisLogger? existingLogger,
  }) : super(existingLogger: existingLogger) {
    _handler = SerialPortHandler(
      portName: portName,
      config: settings.getConfig,
      enableLogging: enableLogging,
      logger: logger, // Use inherited logger
    );

    _queue = SerialPrintQueue(
      _handler,
      timeout: const Duration(seconds: 2),
      quietWindow: const Duration(milliseconds: 150),
      stripFraming: true,
    );

    // Listen to both status notifiers to update the image path and connection status
    _handler.portStatus.addListener(_updateStatus);
    _handler.statusMgr.statusNotifier.addListener(_updateStatus);
    _updateStatus(); // Initial status check
  }

  // -------- IArtemisDevice Implementation --------

  @override
  ValueListenable<DeviceConnectionStatus> get connectionStatus => _connectionStatus;

  @override
  DeviceConnectionStatus get currentConnectionStatus => _connectionStatus.value;

  @override
  Future<bool> connect() => _handler.open();

  @override
  Future<bool> disconnect() => _handler.close();

  @override
  void dispose() {
    _handler.portStatus.removeListener(_updateStatus);
    _handler.statusMgr.statusNotifier.removeListener(_updateStatus);
    _connectionStatus.dispose();
    _statusImagePathNotifier.dispose();
    _handler.dispose(); // Use dispose to clean up hotplug timers
    super.dispose();
  }

  // -------- Public API --------

  /// Themed image path that changes based on the current status.
  ValueListenable<String> get statusImagePath => _statusImagePathNotifier;

  /// Returns an Image widget based on the current status.
  Widget icon([double size = 24]) => Image.asset(
        _statusImagePathNotifier.value,
        width: size,
        package: 'artemis_acps', // Assuming this is your package name
      );

  /// Detailed device status (paper jam, etc.)
  ValueListenable<DeviceStatus> get statusListenable =>
      _handler.statusMgr.statusNotifier;
  DeviceStatus get currentStatus => _handler.statusMgr.status;

  Future<PrintResult> printText(String data) async {
    await _handler.open();
    return _queue.printText(data);
  }

  Future<PrintResult> printBytes(Uint8List bytes) async {
    await _handler.open();
    return _queue.enqueue(bytes);
  }

  Future<DeviceStatus> testQuery() async {
    await _handler.open();
    await _handler.sendBytes("SQ".codeUnits);
    return _handler.statusMgr.status;
  }

  void _updateStatus() {
    // First, update the generic connection status based on PortStatus
    switch (_handler.portStatus.value) {
      case PortStatus.open:
        _connectionStatus.value = DeviceConnectionStatus.connected;
        break;
      case PortStatus.opening:
        _connectionStatus.value = DeviceConnectionStatus.connecting;
        break;
      case PortStatus.closed:
      case PortStatus.closing:
        _connectionStatus.value = DeviceConnectionStatus.disconnected;
        break;
      case PortStatus.error:
        _connectionStatus.value = DeviceConnectionStatus.error;
        break;
    }

    // Then, determine the image path
    String statusFolder;
    final portStatus = _handler.portStatus.value;
    final deviceStatus = _handler.statusMgr.status;

    if (portStatus == PortStatus.closed || portStatus == PortStatus.closing) {
      statusFolder = 'notExist';
    } else if (portStatus == PortStatus.error) {
      statusFolder = 'hasError';
    } else if (portStatus == PortStatus.opening) {
      statusFolder = 'init';
    } else {
      // Port is open, so use the detailed device status
      if (deviceStatus.paperJam) {
        statusFolder = 'paperJam';
      } else if (deviceStatus.paperOut) {
        statusFolder = 'paperOut';
      } else if (deviceStatus.headLifted) {
        statusFolder = 'headLifted';
      } else if (deviceStatus.powerOff) {
        statusFolder = 'powerOff';
      } else if (!deviceStatus.ready) {
        statusFolder = 'unknown';
      } else {
        statusFolder = 'ready';
      }
    }
    _statusImagePathNotifier.value = 'assets/images/devices/$statusFolder/PRN.png';
  }
}
