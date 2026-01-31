import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'classes/artemis_port_device.dart';
class ArtemisPortBarcodeListener extends ArtemisPortDevice{
  late final SerialPort _port;
  SerialPortReader? _reader;
  final _controller = StreamController<String>.broadcast();
  final void Function(String data)? onData;
  List<int> _buffer = [];

  ArtemisPortBarcodeListener({required super.portName,super.config,super.enableLogging,  this.onData}) {
    _port = SerialPort(portName);
  }

  Stream<String> get onBarcode => _controller.stream;
  Timer? _flushTimer;

  bool open() {

    if (_port.isOpen) {
      log("already open");
      return true;

    }
    if(!_port.openRead()){
      _controller.addError('Failed to open port $portName. Check permissions or if the port is in use.');
      log("Failed to open port $portName. Check permissions or if the port is in use.");
      return false;
    }
    log("already open ok");
    return true;
  }

  void close() {
    if (_port.isOpen) {
      _port.close();
    }
  }

  void dispose() {
    stopListening();
    close();
    _controller.close();
    _port.dispose();
  }

  void startListening() {
    if (!_port.isOpen) {
      if (!open()) {
        return;
      }
    }
    log("should start listen");
    _reader = SerialPortReader(_port);
    _reader!.stream.listen((data) {
      // Reset idle timer
      _buffer.addAll(data);

      // log("data recieved");
      _flushTimer?.cancel();
      _flushTimer = Timer(const Duration(milliseconds: 30), () {
        final barcode = ascii.decode(_buffer).trimRight();
        // log("barcode is $barcode");
        if (barcode.isNotEmpty) {
          // log("adding to stream $barcode");
          onData?.call(barcode);
          _controller.add(barcode);
        }
        _buffer.clear();
      });
    }, onError: (error) {
      log("on error listen");
      _controller.addError(error);
    });
  }

  void stopListening() {
    _reader?.close();
    _reader = null;
  }

  bool get isOpen => _port.isOpen;

  static List<String> get availablePorts => SerialPort.availablePorts;
}
