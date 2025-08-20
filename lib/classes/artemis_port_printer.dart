import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import 'artemis_port_print_setting.dart';
import 'enums.dart';
import 'print_result.dart';
import 'serial_port_handler.dart';
import 'serial_print_queue.dart';
import 'status_class.dart';

class ArtemisPortPrinter {
  final String portName;
  final ArtemisPortPrintSetting settings;
  final bool enableLogging;

  late final SerialPortHandler _handler;
  late final SerialPrintQueue _queue;

  ArtemisPortPrinter({
    required this.portName,
    ArtemisPortPrintSetting? config,
    this.enableLogging = false,
  }) : settings = config ?? ArtemisPortPrintSetting(portName: portName) {
    _handler = SerialPortHandler(
      portName: portName,
      config: settings.getConfig,
      enableLogging: enableLogging,
    );

    _queue = SerialPrintQueue(
      _handler,
      timeout: const Duration(seconds: 2),
      quietWindow: const Duration(milliseconds: 150),
      stripFraming: true,
    );
  }

  // -------- Public API --------

  /// device status (parsed status from printer)
  ValueListenable<DeviceStatus> get statusListenable =>
      _handler.statusMgr.statusNotifier;
  DeviceStatus get currentStatus => _handler.statusMgr.status;

  /// port status (open/closing/etc)
  ValueListenable<PortStatus> get portStatusListenable => _handler.portStatus;
  PortStatus get portStatus => _handler.portStatus.value;

  /// direct port handler accessor (if you need lower-level calls)
  SerialPortHandler get port => _handler;

  Future<bool> connect() => _handler.open();
  Future<bool> disconnect() => _handler.close();

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
}


