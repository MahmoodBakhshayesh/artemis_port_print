import 'dart:convert';
import 'dart:developer';

import 'package:flutter_libserialport/flutter_libserialport.dart';

export 'ext.dart';
/// A Calculator.
class Calculator {
  /// Returns [value] plus 1.
  int addOne(int value) {
    log("add one to $value");
    return value + 1;
  }
}

class ArtemisPortPrint {
  ArtemisPortPrint._();

  static List<String> get getPorts => SerialPort.availablePorts;

  static SerialPort createSerialPort(String name) {
    return SerialPort(name);
  }
  static void print(SerialPort port,String msg) {
    if(port.openWrite()){
      port.write(utf8.encode(msg));
    }
  }
}
