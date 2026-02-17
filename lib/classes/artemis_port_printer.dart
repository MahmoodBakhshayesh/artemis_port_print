import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'artemis_logger.dart';
import 'artemis_port_device.dart';
import 'artemis_port_print_setting.dart';
import 'enums.dart';
import 'i_artemis_device.dart';
import 'print_result.dart';
import 'serial_port_handler.dart';
import 'serial_print_queue.dart';
import 'status_class.dart';

class ArtemisPortPrinter extends ArtemisPortDevice implements IArtemisDevice {
  late final SerialPrintQueue _queue;
  final PrinterType printerType;
  bool _isConfiguring = false;

  final ValueNotifier<DeviceConnectionStatus> _connectionStatus =
      ValueNotifier(DeviceConnectionStatus.disconnected);
  final ValueNotifier<String> _statusImagePathNotifier =
      ValueNotifier('assets/images/devices/notExist/BP.png');

  ArtemisPortPrinter({
    required super.portName,
    super.config,
    super.enableLogging = false,
    super.logPeriodicStatus = false,
    this.printerType = PrinterType.bp,
    ArtemisLogger? existingLogger,
    SerialPortHandler? existingHandler,
  }) : super(existingLogger: existingLogger, existingHandler: existingHandler) {
    _queue = SerialPrintQueue(
      handler, 
      timeout: const Duration(seconds: 2),
      quietWindow: const Duration(milliseconds: 150),
      stripFraming: true,
    );

    // Listen to both status notifiers to update the image path and connection status
    handler.portStatus.addListener(_updateStatus);
    handler.statusMgr.statusNotifier.addListener(_updateStatus);
    _updateStatus(); // Initial status check
  }

  // -------- IArtemisDevice Implementation --------

  @override
  ValueListenable<DeviceConnectionStatus> get connectionStatus => _connectionStatus;

  @override
  DeviceConnectionStatus get currentConnectionStatus => _connectionStatus.value;

  @override
  Future<bool> connect() => handler.open(source: "connect");

  @override
  Future<bool> disconnect() => handler.close();

  @override
  void dispose() {
    handler.portStatus.removeListener(_updateStatus);
    handler.statusMgr.statusNotifier.removeListener(_updateStatus);
    _connectionStatus.dispose();
    _statusImagePathNotifier.dispose();
  }

  // -------- Public API --------

  /// Themed image path that changes based on the current status.
  ValueListenable<String> get statusImagePath => _statusImagePathNotifier;

  /// Returns an Image widget based on the current status.
  Widget icon([double size = 24]) => ValueListenableBuilder<String>(
        valueListenable: _statusImagePathNotifier,
        builder: (context, path, _) => Image.asset(
          path,
          width: size,
          package: 'artemis_port_util',
        ),
      );

  /// Detailed device status (paper jam, etc.)
  ValueListenable<DeviceStatus> get statusListenable =>
      handler.statusMgr.statusNotifier;
  DeviceStatus get currentStatus => handler.statusMgr.status;

  Future<PrintResult> printText(String data) async {
    return _queue.printText(data);
  }

  Future<PrintResult> printBytes(Uint8List bytes) async {
    return _queue.enqueue(bytes);
  }

  Future<DeviceStatus> testQuery() async {
    await handler.sendBytes("SQ".codeUnits);
    return handler.statusMgr.status;
  }

  Future<PrintResult> setPec(String pectab) async {
    _isConfiguring = true;
    _updateStatus();
    // Keep it in configuring state for a short moment to show the animation
    await Future.delayed(const Duration(seconds: 3));
    try {
      final printRes = await _queue.printText(pectab);
      if ((printRes.text ?? '').startsWith("HDCERRM")) {
        await initIt();
        return setPec(pectab);
      }
      log("pec res ==> ${printRes.text}");
      return printRes;
    } finally {
      _isConfiguring = false;
      _updateStatus();
    }
  }

  Future<PrintResult> testPrint(String data) async {
    final printRes = await _queue.printText(data);
    if ((printRes.text ?? '').startsWith("HDCERRM")) {
      await initIt();
      return testPrint(data);
    }
    return printRes;
  }

  Future<void> initIt() async {
    String command1 = "UK";
    String command2 = "MX";
    String command3 = "UG#GID";
    String command4 = "EP#AIRLINEID=GID#HARDCODE=HDC#UNSOL=Y";
    String command5 = "UC#999";

    await handler.sendBytes(command1.codeUnits);
    await handler.sendBytes(command2.codeUnits);
    await handler.sendBytes(command3.codeUnits);
    await handler.sendBytes(command4.codeUnits);
    await handler.sendBytes(command5.codeUnits);
  }

  void _updateStatus() {
    switch (handler.portStatus.value) {
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

    String statusFolder;
    String extension = 'png';
    final portStatusValue = handler.portStatus.value;
    final deviceStatus = handler.statusMgr.status;

    if (portStatusValue == PortStatus.closed || portStatusValue == PortStatus.closing) {
      statusFolder = 'notExist';
    } else if (portStatusValue == PortStatus.error) {
      statusFolder = 'hasError';
    } else if (portStatusValue == PortStatus.opening) {
      statusFolder = 'init';
    } else if (_isConfiguring) {
      statusFolder = 'configuring';
      extension = 'gif'; // Use gif for configuring state
    } else {
      // Port is open, so use the detailed device status
      if (deviceStatus.state == StatusState.busy) {
        statusFolder = 'printing';
        extension = 'gif';
      } else if (deviceStatus.paperJam) {
        statusFolder = 'paperJam';
      } else if (deviceStatus.paperOut) {
        statusFolder = 'paperOut';
      } else if (deviceStatus.headLifted) {
        statusFolder = 'headLifted';
      } else if (deviceStatus.paperOut) {
         statusFolder = 'paperOut';
      } else if (deviceStatus.powerOff) {
        statusFolder = 'powerOff';
      } else if (deviceStatus.ready) {
        statusFolder = 'ready';
      } else {
        statusFolder = 'unknown';
      }
    }
    
    final devicePrefix = printerType == PrinterType.bt ? 'BT' : 'BP';
    final newPath = 'assets/images/devices/$statusFolder/$devicePrefix.$extension';
    if (_statusImagePathNotifier.value != newPath) {
       _statusImagePathNotifier.value = newPath;
    }
  }
}
