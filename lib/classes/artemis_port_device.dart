import 'dart:developer';

import 'package:artemis_port_util/artemis_port_util.dart';
import 'package:artemis_port_util/classes/serial_port_monitor.dart';
import 'package:flutter/foundation.dart';
import '../artemis_port_barcode_listener.dart';
import 'artemis_port_print_setting.dart';
import 'artemis_port_printer.dart';
import 'i_artemis_device.dart';
import 'serial_port_handler.dart';

class ArtemisPortDevice {
  late final SerialPortHandler handler;
  final String portName;
  late final ArtemisPortDeviceSetting settings;
  final bool enableLogging;
  late final SerialPortMonitor monitor;
  // final ValueNotifier<PortStatus> _portStatus = ValueNotifier(PortStatus.closed);
  IArtemisDevice? _activeDevice;

  ArtemisPortDevice({required this.portName, ArtemisPortDeviceSetting? config, this.enableLogging = false}) {
    settings = config ?? ArtemisPortDeviceSetting(portName: portName);
    monitor = SerialPortMonitor(portName);
    handler = SerialPortHandler(
      portName: portName,
      config: (config ?? ArtemisPortDeviceSetting(portName: portName)).getConfig,
      enableLogging: enableLogging,
    );
    handler.portStatus.addListener(_updateStatus);
  }

  ValueListenable<PortStatus> get portStatus => handler.portStatus;


  void _updateStatus() {
    log("should update port status ${handler.portStatus.value}");
    // First, update the generic connection status based on PortStatus
    // switch (_handler.portStatus.value) {
    //   case PortStatus.open:
    //     _portStatus.value = PortStatus.open;
    //     break;
    //   case PortStatus.opening:
    //     _portStatus.value = PortStatus.opening;
    //     break;
    //   case PortStatus.closed:
    //   case PortStatus.closing:
    //     _portStatus.value = PortStatus.closing;
    //     break;
    //   case PortStatus.error:
    //     _portStatus.value = PortStatus.error;
    //     break;
    // }
  }

  ArtemisPortPrinter get asPrinter {
    if (_activeDevice is ArtemisPortPrinter) {
      return _activeDevice as ArtemisPortPrinter;
    }
    _activeDevice?.dispose();
    final printer = ArtemisPortPrinter(portName: portName, config: settings, enableLogging: enableLogging);
    _activeDevice = printer;
    return printer;
  }

  ArtemisPortBarcodeListener get asBarcodeReader {
    if (_activeDevice is ArtemisPortBarcodeListener) {
      return _activeDevice as ArtemisPortBarcodeListener;
    }
    _activeDevice?.dispose();
    final barcodeReader = ArtemisPortBarcodeListener(portName: portName, config: settings, enableLogging: enableLogging);
    _activeDevice = barcodeReader;
    return barcodeReader;
  }

  // startMonitoring() {
  //   _portStatus.value = PortStatus.opening;
  //   monitor.start(baudRate: settings.baudRate.value);
  //   monitor.onAvailability.listen((availability) {
  //     if (availability.offline) {
  //       _portStatus.value = PortStatus.closed;
  //     }
  //     if (!availability.available) {
  //       _portStatus.value = PortStatus.error;
  //     }
  //     if (availability.available && !availability.offline) {
  //       _portStatus.value = PortStatus.open;
  //     }
  //   });
  // }

  /// Disposes the currently active device.
  void dispose() {
    _activeDevice?.dispose();
    _activeDevice = null;
  }

  Map<String, dynamic> toJson() {
    return {'portName': portName, 'settings': settings.toJson(), 'enableLogging': enableLogging};
  }

  factory ArtemisPortDevice.fromJson(Map<String, dynamic> json) {
    return ArtemisPortDevice(portName: json['portName'], config: ArtemisPortDeviceSetting.fromJson(json['settings']), enableLogging: json['enableLogging']);
  }
}
