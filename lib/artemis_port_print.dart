
library artemis_port_print;
import 'dart:async';
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

  static ArtemisSerialPort createSerialPort(String name) {
    return ArtemisSerialPort(name);
  }

  static Future<PrintResult> print(SerialPort port, String data) async {
    final sp = SerialPortBaseDart(
      SerialDeviceConfig(
        portName: port.name??'',
        // << change me
        baudRate: 9600,
        dataBits: 8,
        parity: 0,
        stopBits: 1,
        flowControl: SerialPortFlowControl.none,
        protocolMode: ProtocolMode.none, // no STX/ETX framing for loopback
      ),
    );
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

// extension MoreMethods on SerialPort {
//   static void printData(String data){
//     final port = this;
//     ArtemisPortPrint.print(this, data);
//   }
// }
