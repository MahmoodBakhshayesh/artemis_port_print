import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'classes/artemis_port_device.dart';
import 'classes/enums.dart';
import 'classes/i_artemis_device.dart';

class ArtemisPortBarcodeListener extends ArtemisPortDevice implements IArtemisDevice {
  late final SerialPort _port;
  SerialPortReader? _reader;
  final _controller = StreamController<String>.broadcast();
  final void Function(String data)? onData;
  List<int> _buffer = [];

  final ValueNotifier<BarcodeReaderStatus> _statusNotifier =
      ValueNotifier(BarcodeReaderStatus.disconnected);
  final ValueNotifier<DeviceConnectionStatus> _connectionStatus =
      ValueNotifier(DeviceConnectionStatus.disconnected);
  final ValueNotifier<String> _statusImagePathNotifier =
      ValueNotifier('assets/images/devices/notExist/BC.png');

  /// Detailed status specific to the barcode reader
  ValueListenable<BarcodeReaderStatus> get barcodeReaderStatus => _statusNotifier;
  BarcodeReaderStatus get currentBarcodeReaderStatus => _statusNotifier.value;

  /// Themed image path that changes based on the current status.
  ValueListenable<String> get statusImagePath => _statusImagePathNotifier;

  ArtemisPortBarcodeListener(
      {required super.portName,
      super.config,
      super.enableLogging,
      this.onData}) {
    // _port = SerialPort(portName);
    _statusNotifier.addListener(_updateStatus);
    handler.portStatus.addListener(_updateStatus);
  }

  // -------- IArtemisDevice Implementation --------

  @override
  ValueListenable<DeviceConnectionStatus> get connectionStatus => _connectionStatus;

  @override
  DeviceConnectionStatus get currentConnectionStatus => _connectionStatus.value;
  
  @override
  Future<bool> connect() async => open();

  @override
  Future<bool> disconnect() async {
    close();
    return true;
  }

  @override
  void dispose() {
    stopListening();
    close();
    _controller.close();
    // _port.dispose();
    _statusNotifier.removeListener(_updateStatus);
    _statusNotifier.dispose();
    _connectionStatus.dispose();
    _statusImagePathNotifier.dispose();
    super.dispose();
  }

  // -------- Public API --------

  Stream<String> get onBarcode => _controller.stream;
  Timer? _flushTimer;

  Future<bool> open() async {
    if (handler.isOpen) {
      log("Port is already open");
      return true;
    }
    _statusNotifier.value = BarcodeReaderStatus.connecting;
    await handler.openReader((data) {
      _buffer.addAll(data);
      _flushTimer?.cancel();
      _flushTimer = Timer(const Duration(milliseconds: 30), () {
        final barcode = ascii.decode(_buffer).trim();
        if (barcode.isNotEmpty) {
          onData?.call(barcode);
          _controller.add(barcode);
        }
        _buffer.clear();
      });
    });
    if (!handler.isOpen) {
      final error =
          'Failed to open port $portName. Check permissions or if the port is in use.';
      _controller.addError(error);
      log(error);
      _statusNotifier.value = BarcodeReaderStatus.error;
      return false;
    }
    _statusNotifier.value = BarcodeReaderStatus.connected;
    log("Port opened successfully");
    return true;
  }

  void close() {
    if (handler.isOpen) {
      handler.close();
      _statusNotifier.value = BarcodeReaderStatus.disconnected;
    }
  }

  void startListening() {
    return;


    if (!handler.isOpen) {
      open().then((_){
        log("Starting to listen for barcodes");
        _statusNotifier.value = BarcodeReaderStatus.listening;
        _reader = handler.reader;
        _reader!.stream.listen((data) {
          _buffer.addAll(data);
          _flushTimer?.cancel();
          _flushTimer = Timer(const Duration(milliseconds: 30), () {
            final barcode = ascii.decode(_buffer).trim();
            if (barcode.isNotEmpty) {
              onData?.call(barcode);
              _controller.add(barcode);
            }
            _buffer.clear();
          });
        }, onError: (error) {
          log("Error while listening to port: $error");
          _controller.addError(error);
          _statusNotifier.value = BarcodeReaderStatus.error;
        });
      });
      // if (!open()) {
      //   return;
      // }
    }

  }

  void stopListening() {
    _reader?.close();
    _reader = null;
    if (currentBarcodeReaderStatus == BarcodeReaderStatus.listening) {
      _statusNotifier.value = BarcodeReaderStatus.connected;
    }
  }

  // bool get isOpen => _port.isOpen;

  static List<String> get availablePorts => SerialPort.availablePorts;

  void _updateStatus() {
    // First, update the generic connection status
    // switch (portStatus.value) {
    //   case PortStatus.open:
    //     _connectionStatus.value = DeviceConnectionStatus.connected;
    //     break;
    //   case PortStatus.opening:
    //     _connectionStatus.value = DeviceConnectionStatus.connecting;
    //     break;
    //   case PortStatus.closed:
    //     _connectionStatus.value = DeviceConnectionStatus.disconnected;
    //     break;
    //   case PortStatus.error:
    //     _connectionStatus.value = DeviceConnectionStatus.error;
    //     break;
    //   case PortStatus.closing:
    //     _connectionStatus.value = DeviceConnectionStatus.disconnected;
    //
    // }

    String statusFolder;
    final portStatus = handler.portStatus.value;
    final deviceStatus = handler.statusMgr.status;

    if (portStatus == PortStatus.closed || portStatus == PortStatus.closing) {
      statusFolder = 'diskError';
    } else if (portStatus == PortStatus.error) {
      statusFolder = 'diskError';
    } else if (portStatus == PortStatus.opening) {
      statusFolder = 'init';
    } else {
      statusFolder = 'ready';
    }
    _statusImagePathNotifier.value = 'assets/images/devices/$statusFolder/BC.png';
    //
    // // Then, update the image path
    // String statusFolder;
    // switch (_statusNotifier.value) {
    //   case BarcodeReaderStatus.connected:
    //     statusFolder = 'ready';
    //     break;
    //
    //   case BarcodeReaderStatus.listening:
    //     statusFolder = 'ready'; // Using 'printing' to indicate active listening
    //     break;
    //   case BarcodeReaderStatus.connecting:
    //     statusFolder = 'init';
    //     break;
    //   case BarcodeReaderStatus.error:
    //     statusFolder = 'diskError';
    //     break;
    //   case BarcodeReaderStatus.disconnected:
    //
    //   statusFolder = 'notExist';
    //     break;
    // }

    //
    // _statusImagePathNotifier.value = 'assets/images/devices/$statusFolder/BC.png';

  }

  Widget icon([double size = 24])=>ValueListenableBuilder(valueListenable: statusImagePath, builder: (c,s,_){
    return Image.asset(s, width: size, package: 'artemis_port_util');
  });
}
