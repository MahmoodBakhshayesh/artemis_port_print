import '../artemis_serial_port.dart';
import 'enums.dart';

class SerialDeviceConfig {
  final String portName; // e.g., "COM3"
  final int baudRate; // e.g., 9600
  final int dataBits; // typically 8
  final int parity; // 0 none, 1 odd, 2 even
  final int stopBits; // 1 or 2
  final bool dtrEnable;
  final bool rtsEnable;
  final int flowControl; // none, rtsCts, xonXoff
  final Duration readTimeout; // used in polling reads
  final Duration writeTimeout; // not strictly used by lib, but kept for API symmetry
  final ProtocolMode protocolMode;

  const SerialDeviceConfig({
    required this.portName,
    this.baudRate = 9600,
    this.dataBits = 8,
    this.parity = 0,
    this.stopBits = 1,
    this.dtrEnable = true,
    this.rtsEnable = true,
    this.flowControl = SerialPortFlowControl.none,
    this.readTimeout = const Duration(milliseconds: 500),
    this.writeTimeout = const Duration(milliseconds: 500),
    this.protocolMode = ProtocolMode.framed,
  });
}