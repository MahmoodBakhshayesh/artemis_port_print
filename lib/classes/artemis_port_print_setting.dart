import 'enums.dart';
import 'serial_device_config.dart';

class ArtemisPortDeviceSetting {
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

  ArtemisPortDeviceSetting({
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

  Map<String, dynamic> toJson() {
    return {
      'printType': printType.toString().split('.').last,
      'connectionType': connectionType.toString().split('.').last,
      'portName': portName,
      'baudRate': baudRate.toString().split('.').last,
      'dataBits': dataBits.toString().split('.').last,
      'parity': parity.toString().split('.').last,
      'stopBits': stopBits.toString().split('.').last,
      'protocolMode': protocolMode.toString().split('.').last,
      'receivedBytesThreshold': receivedBytesThreshold,
      'handshake': handshake.toString().split('.').last,
      'dtr': dtr,
      'rts': rts,
      'logoBinary': logoBinary,
      'resetBin': resetBin,
      'readTimeOut': readTimeOut,
      'writeTimoOut': writeTimoOut,
    };
  }

  factory ArtemisPortDeviceSetting.fromJson(Map<String, dynamic> json) {
    return ArtemisPortDeviceSetting(
      printType: PrintType.values.byName(json['printType']),
      connectionType: ConnectionType.values.byName(json['connectionType']),
      portName: json['portName'],
      baudRate: BaudRate.values.byName(json['baudRate']),
      dataBits: DataBits.values.byName(json['dataBits']),
      parity: Parity.values.byName(json['parity']),
      stopBits: StopBits.values.byName(json['stopBits']),
      protocolMode: ProtocolMode.values.byName(json['protocolMode']),
      receivedBytesThreshold: json['receivedBytesThreshold'],
      handshake: Handshake.values.byName(json['handshake']),
      dtr: json['dtr'],
      rts: json['rts'],
      logoBinary: json['logoBinary'],
      resetBin: json['resetBin'],
      readTimeOut: json['readTimeOut'],
      writeTimoOut: json['writeTimoOut'],
    );
  }
}
