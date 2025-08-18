library artemis_port_print;

import 'dart:async';
import 'package:artemis_port_print/enums.dart';

import 'artemis_serial_port.dart';
export 'artemis_serial_port.dart';
import 'util.dart';
export 'ext.dart';

class SerialPrintError implements Exception {
  final String message;

  SerialPrintError(this.message);

  @override
  String toString() => 'SerialPrintError: $message';
}

class ArtemisPortPrint {
  ArtemisPortPrint._();

  static List<String> get getPorts => SerialPort.availablePorts;

  static ArtemisSerialPort createSerialPort(String name, {ArtemisPortPrintSetting? config}) {
    final port = ArtemisSerialPort(name, serialDeviceConfig: (config ?? ArtemisPortPrintSetting(portName: name)).getConfig);
    return port;
  }

  static Future<PrintResult> print(ArtemisSerialPort port, String data) async {
    final sp = SerialPortBaseDart(
      port.serialDeviceConfig ??
          SerialDeviceConfig(
            portName: port.name ?? '',
            // << change me
            baudRate: 9600,
            dataBits: 8,
            parity: 0,
            stopBits: 1,
            flowControl: SerialPortFlowControl.none,
            protocolMode: ProtocolMode.none, // no STX/ETX framing for loopback
          ),
    );
    sp.config;
    final queue = SerialPrintQueue(
      sp,
      timeout: const Duration(seconds: 2),
      quietWindow: const Duration(milliseconds: 150),
      stripFraming: true, // removes 0x02/0x03 if present
      // Optional: provide your exact classifier
      // classifier: (bytes, text) { ... }
    );

    // (Optional) ensure port open once; queue will open if needed anyway
    await sp.open();

    // Subscribe once if you want to log payloads globally (not required)
    final sub = sp.onData.listen((e) {
      // NOTE: onData may already be payload-only if you set ProtocolMode.framed in sp
      // print('RX: ${e.text}');
    });

    final result = await queue.printText(data);

    await sub.cancel();
    // keep port open if you plan to send more, or close:
    await sp.close();

    return result;
  }
}

class ArtemisPortPrintSetting {
  PrintType printType;
  ConnectionType connectionType;
  String portName;
  BaudRate baudRate;
  DataBits dataBits;
  Parity parity;
  StopBits stopBits;
  ProtocolMode protocolMode;
  int receivedBytesThreshold;
  Handshake handshake;
  bool dtr;
  bool rts;
  bool logoBinary;
  bool resetBin;
  int readTimeOut;
  int writeTimoOut;

  ArtemisPortPrintSetting({
    this.printType = PrintType.aea,
    this.connectionType = ConnectionType.com,
    required this.portName,
    this.baudRate = BaudRate.br_19200,
    this.dataBits = DataBits.db_8,
    this.parity = Parity.none,
    this.stopBits = StopBits.one,
    this.protocolMode = ProtocolMode.none,
    this.receivedBytesThreshold = 1,
    this.handshake = Handshake.none,
    this.dtr = true,
    this.rts = true,
    this.logoBinary = false,
    this.resetBin = false,
    this.readTimeOut = 8000,
    this.writeTimoOut = 8000,
  });

  SerialDeviceConfig get getConfig => SerialDeviceConfig(
    portName: portName,
    baudRate: baudRate.value,
    dataBits: dataBits.value,
    parity: parity.value,
    stopBits: stopBits.value,
    protocolMode: protocolMode,
    readTimeout: Duration(milliseconds: readTimeOut),
    writeTimeout: Duration(milliseconds: writeTimoOut),
    dtrEnable: dtr,
    rtsEnable: rts,
    flowControl: handshake.value,
  );
}

// extension MoreMethods on SerialPort {
//   static void printData(String data){
//     final port = this;
//     ArtemisPortPrint.print(this, data);
//   }
// }
