import 'dart:typed_data';
import 'package:flutter/foundation.dart';

import '../artemis_port_barcode_listener.dart';
import 'artemis_port_print_setting.dart';
import 'enums.dart';
import 'print_result.dart';
import 'serial_port_handler.dart';
import 'serial_print_queue.dart';
import 'status_class.dart';
import 'artemis_port_printer.dart';
class ArtemisPortDevice {
  final String portName;
  final ArtemisPortDeviceSetting settings;
  final bool enableLogging;


  ArtemisPortDevice({
    required this.portName,
    ArtemisPortDeviceSetting? config,
    this.enableLogging = false,
  }) : settings = config ?? ArtemisPortDeviceSetting(portName: portName);


  ArtemisPortPrinter get asPrinter => ArtemisPortPrinter(portName: portName,config: settings,enableLogging: enableLogging);
  ArtemisPortBarcodeListener get asBarcodeReader => ArtemisPortBarcodeListener(portName: portName,config: settings,enableLogging: enableLogging);
}


