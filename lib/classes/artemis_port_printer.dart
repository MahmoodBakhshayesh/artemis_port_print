import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'artemis_port_device.dart';
import 'enums.dart';
import 'i_artemis_device.dart';
import 'print_result.dart';
import 'serial_port_handler.dart';
import 'serial_print_queue.dart';
import 'status_class.dart';

class ArtemisPortPrinter extends ArtemisPortDevice implements IArtemisDevice {
  // late final SerialPortHandler handler;
  late final SerialPrintQueue _queue;

  // final ValueNotifier<DeviceConnectionStatus> _connectionStatus =
  //     ValueNotifier(DeviceConnectionStatus.disconnected);
  final ValueNotifier<String> _statusImagePathNotifier = ValueNotifier('assets/images/devices/notExist/BP.png');

  ArtemisPortPrinter({required super.portName, super.config, super.enableLogging = true}) {
    // handler = SerialPortHandler(portName: portName, config: settings.getConfig, enableLogging: enableLogging);

    _queue = SerialPrintQueue(handler, timeout: const Duration(seconds: 2), quietWindow: const Duration(milliseconds: 150), stripFraming: true);

    // Listen to both status notifiers to update the image path and connection status
    handler.portStatus.addListener(_updateStatus);
    handler.statusMgr.statusNotifier.addListener(_updateStatus);
    _updateStatus(); // Initial status check
  }

  // -------- IArtemisDevice Implementation --------

  @override
  Future<bool> connect() {
    return handler.open();
  }

  @override
  Future<bool> disconnect() => handler.close();

  @override
  void dispose() {
    handler.portStatus.removeListener(_updateStatus);
    handler.statusMgr.statusNotifier.removeListener(_updateStatus);
    // _connectionStatus.dispose();
    _statusImagePathNotifier.dispose();
    handler.close();
    super.dispose();
  }

  // -------- Public API --------

  /// Themed image path that changes based on the current status.
  ValueListenable<String> get statusImagePath => _statusImagePathNotifier;

  /// Detailed device status (paper jam, etc.)
  ValueListenable<DeviceStatus> get statusListenable => handler.statusMgr.statusNotifier;

  DeviceStatus get currentStatus => handler.statusMgr.status;

  Future<PrintResult> printText(String data) async {
    await handler.open();
    return _queue.printText(data);
  }

  Future<PrintResult> setBtPec() async {
    String btPec =
        'BTT1039~H0510255=#02C0 E502250304#03B1 A494250541#04C0M1120370201#06B1 A002250541=03#11C0MA146250304=02#12B1M3150454041=03#14B1 A190259041=03#19B1 A270255041=03#20C0 E484250304=02#21B1 A475250541=03#22C0 E466250304=02#23B1 A457250541=03#47C0M1092370201=73#48C0M1092090303=71#49C0M1092180303=72#50C0 1036090201=EA#51C0 1032090201=85#53C0 1024220201=81#54C0 1020090201TO:#55C0 1020150201=86#56C0 1020250201=71#57C0 1020300201=72#60C0 1030090202=E1#61C0 1030200202=E2#62C0 1030280202=E0#63C0 1028090201=89#64C0 1016090201=75#65C0 1008090201=71#66C0M1092340201=83#67C0M1096090201TO:#68C0 1012090201=02#69C0M1085090201VIA1:#71C0M1120090303#72C0M1120180303#73C0M1124370201#74C0M1112090201#75C0 1024310201#81C0M1112370201#83C0 1028250201#85C0M1116090201#86C0MA100271011#87L0MA125300000#89C0M1120370201#91S0MA110250450#93S0MA090250450#94S0MA070250450#E0C0M1072160304#E1C0M1080131011#E2C0M1072050304#E3C0M1065050201#E4C0M1065090201#E5C0M1065150201#E6C0M1072350201#E7C0M1065200201#E8C0M1072450202#E9C0M1065250201#EAC0M1124090201#EDC0MB064250404-TEXT-#EEC0M1096150201#EFC0MA076250201#F0C0 1024090201#F1C0 1016180201#F2C0 1012350201#F3C0 1030400202#F4C0M1065350201#F5C0M1065450201#F6C0 A008220201#FEC0 1001010201#FFC0 1001010201#';

    await handler.open();
    // await _queue.enqueue(Uint8List.fromList(btPec.codeUnits));
    final printRes = await _queue.printText(btPec);
    log("print res ${printRes.text}");
    if ((printRes.text ?? '').startsWith("HDCERRM")) {
      await initIt();
      return setBtPec();
    }

    return printRes;
    // await handler.sendBytes(btPec.codeUnits);
  }

  Future<PrintResult> testPrintTag() async {
    String btData = 'BTP103901#020000116431#030000116431#04028#71ZZ#721313#7303NOV#74TORENTO-#75YTZ#811/25#83E#85AMATO/ROSALIE#86YVR#89028#EASMARTLYNX#EEVANCOUVER#F0NL1V4#F104NOV/05:23#F22675#F3#F5#F6116431#';

    await handler.open();
    // await _queue.enqueue(Uint8List.fromList(btPec.codeUnits));
    final printRes = await _queue.printText(btData);
    log("print res ${printRes.text}");
    if ((printRes.text ?? '').startsWith("HDCERRM")) {
      await initIt();
      return testPrintTag();
    }
    return printRes;
  }

  Future<void> initIt() async {
    String command1 = "UK";
    String command2 = "MX";
    String command3 = "UG#GID";
    String command4 = "EP#AIRLINEID=GID#HARDCODE=HDC#UNSOL=Y";
    String command5 = "UC#999";
    // String command6 = "PC";
    // String command7 = "TC";
    // String command8 = "LC";

    // await handler.open();
    // await _queue.enqueue(Uint8List.fromList(btData.codeUnits));

    await handler.sendBytes(command1.codeUnits);
    await handler.sendBytes(command2.codeUnits);
    await handler.sendBytes(command3.codeUnits);
    await handler.sendBytes(command4.codeUnits);
    await handler.sendBytes(command5.codeUnits);
    // await handler.sendBytes(command6.codeUnits);
    // await handler.sendBytes(command7.codeUnits);
    // await handler.sendBytes(command8.codeUnits);
  }

  Future<PrintResult> printBytes(Uint8List bytes) async {
    await handler.open();
    return _queue.enqueue(bytes);
  }

  Future<DeviceStatus> testQuery() async {
    await handler.open();
    await handler.sendBytes("SQ".codeUnits);
    return handler.statusMgr.status;
  }

  void _updateStatus() {
    // First, update the generic connection status based on PortStatus
    // switch (handler.portStatus.value) {
    //   case PortStatus.open:
    //     _connectionStatus.value = DeviceConnectionStatus.connected;
    //     break;
    //   case PortStatus.opening:
    //     _connectionStatus.value = DeviceConnectionStatus.connecting;
    //     break;
    //   case PortStatus.closed:
    //   case PortStatus.closing:
    //     _connectionStatus.value = DeviceConnectionStatus.disconnected;
    //     break;
    //   case PortStatus.error:
    //     _connectionStatus.value = DeviceConnectionStatus.error;
    //     break;
    // }

    // Then, determine the image path
    String statusFolder;
    // final portStatus = handler.portStatus.value;
    // final portStatus = port;
    final deviceStatus = handler.statusMgr.status;

    if (portStatus.value == PortStatus.closed || portStatus.value == PortStatus.closing) {
      statusFolder = 'notExist';
    } else if (portStatus.value == PortStatus.error) {
      statusFolder = 'hasError';
    } else if (portStatus.value == PortStatus.opening) {
      statusFolder = 'init';
    } else {
      if(deviceStatus.state == StatusState.busy){
        _statusImagePathNotifier.value = 'assets/images/devices/printing/BP.gif';
        return;
      }
      // Port is open, so use the detailed device status
      if (deviceStatus.paperJam) {
        statusFolder = 'paperJam';
      } else if (deviceStatus.paperOut) {
        statusFolder = 'paperOut';
      } else if (deviceStatus.headLifted) {
        statusFolder = 'headLifted';
      } else if (deviceStatus.powerOff) {
        statusFolder = 'powerOff';
      } else if (!deviceStatus.ready) {
        statusFolder = 'unknown';
      } else {
        statusFolder = 'ready';
      }
    }
    _statusImagePathNotifier.value = 'assets/images/devices/$statusFolder/BP.png';
  }

  Widget icon([double size = 24]) => ValueListenableBuilder(
    valueListenable: statusImagePath,
    builder: (c, s, _) {
      return Image.asset(s, width: size, package: 'artemis_port_util');
    },
  );
}
