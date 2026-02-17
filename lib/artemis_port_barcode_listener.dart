import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'classes/artemis_logger.dart';
import 'classes/artemis_port_device.dart';
import 'classes/artemis_port_print_setting.dart';
import 'classes/enums.dart';
import 'classes/i_artemis_device.dart';
import 'classes/serial_port_handler.dart';

class ArtemisPortBarcodeListener extends ArtemisPortDevice implements IArtemisDevice {
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

  ArtemisPortBarcodeListener({
    required super.portName,
    super.config,
    super.enableLogging,
    super.logPeriodicStatus = false,
    this.onData,
    ArtemisLogger? existingLogger,
    SerialPortHandler? existingHandler,
  }) : super(existingLogger: existingLogger, existingHandler: existingHandler) {
    _statusNotifier.addListener(_updateStatus);
    handler.portStatus.addListener(_updateStatus);
    _updateStatus(); // Initial status check
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
    _statusNotifier.removeListener(_updateStatus);
    handler.portStatus.removeListener(_updateStatus);
    _controller.close();
    _connectionStatus.dispose();
    _statusImagePathNotifier.dispose();
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
    bool opened = await handler.openReader((data) {
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

    if (!opened || !handler.isOpen) {
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
    if (!handler.isOpen) {
      open().then((success) {
        if (success) {
          log("Starting to listen for barcodes");
          _statusNotifier.value = BarcodeReaderStatus.listening;
        }
      });
    } else {
      _statusNotifier.value = BarcodeReaderStatus.listening;
    }
  }

  void stopListening() {
    if (currentBarcodeReaderStatus == BarcodeReaderStatus.listening) {
      _statusNotifier.value = BarcodeReaderStatus.connected;
    }
  }

  static List<String> get availablePorts => SerialPort.availablePorts;

  void _updateStatus() {
    // First, update the generic connection status
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

    // Then, update the image path
    String statusFolder;
    switch (_statusNotifier.value) {
      case BarcodeReaderStatus.connected:
        statusFolder = 'ready';
        break;

      case BarcodeReaderStatus.listening:
        statusFolder = 'ready';
        break;
      case BarcodeReaderStatus.connecting:
        statusFolder = 'init';
        break;
      case BarcodeReaderStatus.error:
        statusFolder = 'diskError';
        break;
      case BarcodeReaderStatus.disconnected:
        statusFolder = 'notExist';
        break;
    }

    _statusImagePathNotifier.value =
        'assets/images/devices/$statusFolder/BC.png';
  }

  Widget icon([double size = 24]) => ValueListenableBuilder(
      valueListenable: statusImagePath,
      builder: (c, s, _) {
        return Image.asset(s, width: size, package: 'artemis_port_util');
      });
}
