import 'enums.dart';
import 'serial_device_config.dart';

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