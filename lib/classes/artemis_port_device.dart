import 'package:flutter/foundation.dart';
import '../artemis_port_barcode_listener.dart';
import 'artemis_port_print_setting.dart';
import 'artemis_port_printer.dart';
import 'i_artemis_device.dart';

class ArtemisPortDevice {
  final String portName;
  final ArtemisPortDeviceSetting settings;
  final bool enableLogging;

  IArtemisDevice? _activeDevice;

  ArtemisPortDevice({
    required this.portName,
    ArtemisPortDeviceSetting? config,
    this.enableLogging = false,
  }) : settings = config ?? ArtemisPortDeviceSetting(portName: portName);

  ArtemisPortPrinter get asPrinter {
    if (_activeDevice is ArtemisPortPrinter) {
      return _activeDevice as ArtemisPortPrinter;
    }
    _activeDevice?.dispose();
    final printer = ArtemisPortPrinter(
        portName: portName, config: settings, enableLogging: enableLogging);
    _activeDevice = printer;
    return printer;
  }

  ArtemisPortBarcodeListener get asBarcodeReader {
    if (_activeDevice is ArtemisPortBarcodeListener) {
      return _activeDevice as ArtemisPortBarcodeListener;
    }
    _activeDevice?.dispose();
    final barcodeReader = ArtemisPortBarcodeListener(
        portName: portName, config: settings, enableLogging: enableLogging);
    _activeDevice = barcodeReader;
    return barcodeReader;
  }

  /// Disposes the currently active device.
  void dispose() {
    _activeDevice?.dispose();
    _activeDevice = null;
  }

  Map<String, dynamic> toJson() {
    return {
      'portName': portName,
      'settings': settings.toJson(),
      'enableLogging': enableLogging,
    };
  }

  factory ArtemisPortDevice.fromJson(Map<String, dynamic> json) {
    return ArtemisPortDevice(
      portName: json['portName'],
      config: ArtemisPortDeviceSetting.fromJson(json['settings']),
      enableLogging: json['enableLogging'],
    );
  }
}
