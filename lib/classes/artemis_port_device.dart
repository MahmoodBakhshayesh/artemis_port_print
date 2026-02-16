import 'dart:developer';

import 'package:artemis_port_util/classes/serial_port_monitor.dart';
import 'package:flutter/foundation.dart';
import '../artemis_port_barcode_listener.dart';
import 'artemis_logger.dart';
import 'artemis_port_print_setting.dart';
import 'artemis_port_printer.dart';
import 'enums.dart';
import 'i_artemis_device.dart';
import 'serial_port_handler.dart';

class ArtemisPortDevice {
  late final SerialPortHandler handler;
  final String portName;
  late final ArtemisPortDeviceSetting settings;
  final bool enableLogging;
  late final SerialPortMonitor monitor;
  late final ArtemisLogger logger;
  IArtemisDevice? _activeDevice;

  ArtemisPortDevice({
    required this.portName, 
    ArtemisPortDeviceSetting? config, 
    this.enableLogging = false,
    String? deviceName,
    String? logDirectory,
    ArtemisLogger? existingLogger,
  }) {
    settings = config ?? ArtemisPortDeviceSetting(portName: portName);
    monitor = SerialPortMonitor(portName);
    
    if (existingLogger != null) {
      logger = existingLogger;
    } else {
      logger = ArtemisLogger(
        deviceName: deviceName ?? portName, 
        logDirectory: logDirectory,
        enableConsole: enableLogging
      );
    }

    handler = SerialPortHandler(
      portName: portName,
      config: settings.getConfig,
      enableLogging: enableLogging,
      logger: logger,
    );
    handler.portStatus.addListener(_updateStatus);
  }

  ValueListenable<PortStatus> get portStatus => handler.portStatus;


  void _updateStatus() {
    log("should update port status ${handler.portStatus.value}");
  }

  ArtemisPortPrinter get asPrinter {
    if (_activeDevice is ArtemisPortPrinter) {
      return _activeDevice as ArtemisPortPrinter;
    }
    _activeDevice?.dispose();
    final printer = ArtemisPortPrinter(
      portName: portName, 
      config: settings, 
      enableLogging: enableLogging,
      existingLogger: logger
    );
    _activeDevice = printer;
    return printer;
  }

  ArtemisPortBarcodeListener get asBarcodeReader {
    if (_activeDevice is ArtemisPortBarcodeListener) {
      return _activeDevice as ArtemisPortBarcodeListener;
    }
    _activeDevice?.dispose();
    final barcodeReader = ArtemisPortBarcodeListener(
      portName: portName, 
      config: settings, 
      enableLogging: enableLogging,
      existingLogger: logger
    );
    _activeDevice = barcodeReader;
    return barcodeReader;
  }

  /// Disposes the currently active device.
  void dispose() {
    _activeDevice?.dispose();
    _activeDevice = null;
    handler.dispose(); 
  }

  Map<String, dynamic> toJson() {
    return {'portName': portName, 'settings': settings.toJson(), 'enableLogging': enableLogging};
  }

  factory ArtemisPortDevice.fromJson(Map<String, dynamic> json) {
    return ArtemisPortDevice(portName: json['portName'], config: ArtemisPortDeviceSetting.fromJson(json['settings']), enableLogging: json['enableLogging']);
  }
}
