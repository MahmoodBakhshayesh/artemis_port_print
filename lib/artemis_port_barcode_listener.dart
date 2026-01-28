import 'dart:async';
import 'dart:convert';
import 'package:flutter_libserialport/flutter_libserialport.dart';

class ArtemisPortBarcodeListener {
  final String portName;
  late final SerialPort _port;
  SerialPortReader? _reader;
  final _controller = StreamController<String>.broadcast();
  List<int> _buffer = [];

  ArtemisPortBarcodeListener(this.portName) {
    _port = SerialPort(portName);
  }

  Stream<String> get onBarcode => _controller.stream;

  bool open() {
    if (_port.isOpen) {
      return true;
    }
    if(!_port.openRead()){
      _controller.addError('Failed to open port $portName. Check permissions or if the port is in use.');
      return false;
    }
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
    _reader = SerialPortReader(_port);
    _reader!.stream.listen((data) {
      _buffer.addAll(data);
      // Barcode scanners often terminate with a newline or carriage return.
      // We'll check for newline (\n, ASCII 10) and carriage return (\r, ASCII 13).
      if (_buffer.contains(10) || _buffer.contains(13)) {
        // We assume UTF8 encoding. Some scanners might use other encodings.
        final barcode = utf8.decode(_buffer, allowMalformed: true).trim();
        if (barcode.isNotEmpty) {
          _controller.add(barcode);
        }
        _buffer.clear();
      }
    }, onError: (error) {
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
