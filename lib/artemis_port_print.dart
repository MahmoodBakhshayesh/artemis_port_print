library artemis_port_print;

import 'artemis_serial_port.dart';



export 'classes/artemis_port_printer.dart';
// import 'dart:async';
// import 'dart:developer';
// import 'package:artemis_port_print/classes/enums.dart';
// import 'package:flutter/cupertino.dart';
// import 'package:flutter/foundation.dart';
//
// import 'artemis_serial_port.dart' hide DataReceive;
// export 'artemis_serial_port.dart';
// import 'classes/status_class.dart';
// import 'util.dart';
// export 'ext.dart';
//
// class SerialPrintError implements Exception {
//   final String message;
//
//   SerialPrintError(this.message);
//
//   @override
//   String toString() => 'SerialPrintError: $message';
// }


class ArtemisPortPrint {
  ArtemisPortPrint._();

  static List<String> get getPorts => SerialPort.availablePorts;
}

// class ArtemisPortPrint {
//   ArtemisPortPrint._();
//
//   static List<String> get getPorts => SerialPort.availablePorts;
//
//   static ArtemisSerialPort createSerialPort(
//       String name, {
//         ArtemisPortPrintSetting? config,
//       }) {
//     return ArtemisSerialPort(
//       name,
//       serialDeviceConfig:
//       (config ?? ArtemisPortPrintSetting(portName: name)).getConfig,
//     );
//   }
//
//
//   static ValueListenable<DeviceStatus> statusListenable(ArtemisSerialPort port) {
//     final h = _getHandle(port);            // ensures a handle exists
//     return h.statusMgr.statusNotifier;     // never null
//   }
//
//   // Widget get getWidget {
//   //   final listenable = statusListenable(_);
//   //   if (listenable != null)
//   //     return ValueListenableBuilder<DeviceStatus>(
//   //       valueListenable: listenable,
//   //       builder: (context, status, _) {
//   //         switch (status.state) {
//   //           case StatusState.online:  return const Text('🟢 Ready');
//   //           case StatusState.busy:    return const Text('🖨 Printing…');
//   //           case StatusState.paperOut:return const Text('📄❌ Paper out');
//   //           case StatusState.paperJam:return const Text('🧩 Paper jam');
//   //           case StatusState.printHeadLifted: return const Text('🔧 Head lifted');
//   //           case StatusState.offline: return const Text('🔴 Offline');
//   //           case StatusState.unknown: return Text('❔ ${status.desc}');
//   //         }
//   //       },
//   //     );
//   //   return SizedBox();
//   // }
//
//   // ---------- Public API ----------
//
//   static Future<void> open(ArtemisSerialPort port) async {
//     final h = _getHandle(port);
//     await h.openIfNeeded();
//   }
//
//   static Future<void> close(ArtemisSerialPort port) async {
//     final key = _key(port);
//     final h = _handles.remove(key);
//     if (h != null) {
//       await h.close();
//     }
//   }
//
//   static Future<PrintResult> print(ArtemisSerialPort port, String data) async {
//     final h = _getHandle(port);
//     await h.openIfNeeded();
//     return h.queue.printText(data);
//   }
//
//   static Future<PrintResult> printBytes(
//       ArtemisSerialPort port, Uint8List bytes) async {
//     final h = _getHandle(port);
//     await h.openIfNeeded();
//     return h.queue.enqueue(bytes);
//   }
//
//   static Future<DeviceStatus> testQuery(ArtemisSerialPort port) async {
//     final h = _getHandle(port);
//     await h.openIfNeeded();
//     await _runAeaSequence(h);
//     return h.statusMgr.status;
//   }
//
//   static DeviceStatus? getStatus(ArtemisSerialPort port) {
//     final h = _handles[_key(port)];
//     return h?.statusMgr.status;
//   }
//
//   // ---------- Internals ----------
//
//   static final Map<String, _PortHandle> _handles = {};
//   static String _key(ArtemisSerialPort p) => (p.name ?? '').toUpperCase();
//
//   static _PortHandle _getHandle(ArtemisSerialPort port) {
//     final key = _key(port);
//     return _handles.putIfAbsent(key, () => _PortHandle(port));
//   }
//
//   static Future<void> _runAeaSequence(_PortHandle h) async {
//     await h._sendAndUpdate("MX");
//     await h._sendAndUpdate("UG#GID");
//     await h._sendAndUpdate("EP#AIRLINEID=GID#HARDCODE=HDC#UNSOL=Y");
//     await h._sendAndUpdate("UC#999");
//     await h._sendAndUpdate("AV");
//     await h._sendAndUpdate("PV");
//     await h._sendAndUpdate("SQ", isSqni: true);
//   }
// }
//
// class _PortHandle {
//   _PortHandle(this.port);
//
//   final ArtemisSerialPort port;
//   final StatusManager statusMgr = StatusManager();
//
//   late final SerialPortBaseDart sp = SerialPortBaseDart(
//     port.serialDeviceConfig ??
//         SerialDeviceConfig(
//           portName: port.name ?? '',
//           baudRate: 9600,
//           dataBits: 8,
//           parity: 0,
//           stopBits: 1,
//           flowControl: SerialPortFlowControl.none,
//           protocolMode: ProtocolMode.framed, // important if you get STX/ETX
//         ),
//   );
//
//   late final SerialPrintQueue queue = SerialPrintQueue(
//     sp,
//     timeout: const Duration(seconds: 2),
//     quietWindow: const Duration(milliseconds: 150),
//     stripFraming: true,
//   );
//
//   StreamSubscription<DataReceive>? _sub;
//   Timer? _pollTimer;
//   bool _bootstrapped = false;
//
//   Future<void> openIfNeeded() async {
//     if (!sp.isConnected) {
//       // show “connecting” immediately
//       _setConnecting();
//
//       await sp.open();
//
//       // listen for unsolicited messages (e.g., after UNSOL=Y)
//       _sub ??= sp.onData.listen((evt) {
//         final text = evt.text;
//         if (text.isEmpty) return;
//         final isSqni = text.toUpperCase().contains('SQNI');
//         // log raw + status
//         // debugPrint('[DEV] RX: "$text"  isSqni=$isSqni');
//         statusMgr.updateFrom(text, sqni: isSqni);
//         // 🪵 Log the parsed status snapshot right after updating
//         final st = statusMgr.status;
//         debugPrint('[STATUS] state=${st.state} desc="${st.desc}" '
//             'ready=${st.ready} paperOut=${st.paperOut} paperJam=${st.paperJam} '
//             'powerOff=${st.powerOff} headLifted=${st.headLifted}');
//       });
//
//       // First time: run your AEA sequence to enable UNSOL, etc.
//       if (!_bootstrapped) {
//         await _runBootstrap();
//         _bootstrapped = true;
//
//         // Kick a first poll right away, so UI sees Ready/Online
//         await _pollOnce();
//       }
//
//       // Start periodic polling as a safety net (e.g., every 3–5s)
//       _pollTimer ??=
//           Timer.periodic(const Duration(seconds: 5), (_) => _pollOnce());
//     }
//   }
//
//   Future<void> close() async {
//     _pollTimer?.cancel();
//     _pollTimer = null;
//     await _sub?.cancel();
//     _sub = null;
//     if (sp.isConnected) await sp.close();
//     _setOffline(); // optional: reflect closed state
//   }
//
//   Future<void> _runBootstrap() async {
//     await _sendAndUpdate("MX");
//     await _sendAndUpdate("UG#GID");
//     await _sendAndUpdate("EP#AIRLINEID=GID#HARDCODE=HDC#UNSOL=Y");
//     await _sendAndUpdate("UC#999");
//     await _sendAndUpdate("AV");
//     await _sendAndUpdate("PV");
//     await _sendAndUpdate("SQ", isSqni: true);
//   }
//
//   Future<void> _pollOnce() async {
//
//     // “SQ” is your status query; mark as sqni-ish so offline→unknown tweak applies
//     await _sendAndUpdate("SQ", isSqni: true);
//   }
//
//   Future<void> _sendAndUpdate(String cmd, {bool isSqni = false}) async {
//     final res = await queue.printText(cmd);
//     final text =
//         res.text?.trim() ?? (res.bytes != null ? String.fromCharCodes(res.bytes!).trim() : '');
//     if (text.isEmpty) return;
//     statusMgr.updateFrom(text, sqni: isSqni);
//
//     // Optional logging:
//     // final st = statusMgr.status;
//     // debugPrint('[AEA] TX="$cmd"  RX="$text"  -> ${st.state} "${st.desc}"');
//   }
//
//   void _setConnecting() {
//     final s = statusMgr.status.clone()
//       ..state = StatusState.busy
//       ..desc = 'Connecting...'
//       ..ready = false;
//     statusMgr.statusNotifier.value = s;
//   }
//
//   void _setOffline() {
//     final s = statusMgr.status.clone()
//       ..state = StatusState.offline
//       ..desc = 'Offline'
//       ..ready = false;
//     statusMgr.statusNotifier.value = s;
//   }
// }
//
// class ArtemisPortPrintSetting {
//   PrintType printType;
//   ConnectionType connectionType;
//   String portName;
//   BaudRate baudRate;
//   DataBits dataBits;
//   Parity parity;
//   StopBits stopBits;
//   ProtocolMode protocolMode;
//   int receivedBytesThreshold;
//   Handshake handshake;
//   bool dtr;
//   bool rts;
//   bool logoBinary;
//   bool resetBin;
//   int readTimeOut;
//   int writeTimoOut;
//
//   ArtemisPortPrintSetting({
//     this.printType = PrintType.aea,
//     this.connectionType = ConnectionType.com,
//     required this.portName,
//     this.baudRate = BaudRate.br_19200,
//     this.dataBits = DataBits.db_8,
//     this.parity = Parity.none,
//     this.stopBits = StopBits.one,
//     this.protocolMode = ProtocolMode.none,
//     this.receivedBytesThreshold = 1,
//     this.handshake = Handshake.none,
//     this.dtr = true,
//     this.rts = true,
//     this.logoBinary = false,
//     this.resetBin = false,
//     this.readTimeOut = 8000,
//     this.writeTimoOut = 8000,
//   });
//
//   SerialDeviceConfig get getConfig => SerialDeviceConfig(
//     portName: portName,
//     baudRate: baudRate.value,
//     dataBits: dataBits.value,
//     parity: parity.value,
//     stopBits: stopBits.value,
//     protocolMode: protocolMode,
//     readTimeout: Duration(milliseconds: readTimeOut),
//     writeTimeout: Duration(milliseconds: writeTimoOut),
//     dtrEnable: dtr,
//     rtsEnable: rts,
//     flowControl: handshake.value,
//   );
// }
