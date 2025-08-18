enum PrintType {
  aea,
  zpl,
  stimulSoft,
  ePos;

  @override
  toString() => name.toUpperCase();
}
enum ConnectionType {
  com,
  lan;

  @override
  toString() => name.toUpperCase();
}

enum BaudRate {
  br_75,
  br_110,
  br_134,
  br_150,
  br_300,
  br_600,
  br_1200,
  br_1800,
  br_2400,
  br_4800,
  br_7200,
  br_14400,
  br_19200,
  br_28800,
  br_9600,
  br_38400,
  br_57600,
  br_115200,
  br_128000;

  @override
  toString() => name.toString().replaceFirst("br_", '').toUpperCase();

  int get value => int.parse(toString());
}

enum DataBits {
  db_4,
  db_5,
  db_6,
  db_7,
  db_8;

  @override
  toString() => name.replaceAll("db_", '').toString().toUpperCase();

  int get value => int.parse(toString());
}

enum Parity {
  none,
  odd,
  even,
  mark,
  space;

  @override
  toString() => name.toString();

  int get value => index;
}
enum StopBits {
  none,
  one,
  two,
  onePointFive;

  @override
  toString() => name.toString();

  int get value => index;
}

// enum ProtocolMode {
//   mode0,
//   mode1,
//   auto;
//
//   @override
//   toString() => name.toString();
//
//   int get value => index;
// }
enum Handshake {
  none,
  xOnXoff,
  requestToSendXonXoff,
  requestToSend;

  @override
  toString() => name.toString();

  int get value => index;
}

enum ProtocolMode { none, framed }