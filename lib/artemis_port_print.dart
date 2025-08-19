library artemis_port_print;

import 'dart:async';
import 'dart:developer';
import 'package:artemis_port_print/enums.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'artemis_serial_port.dart';
import 'classes/SerialPrintQueue.dart';
import 'classes/_QueuePortAdapter.dart';
import 'status_class.dart';
import 'util.dart' hide SerialDeviceConfig;
export 'ext.dart';

class SerialPrintError implements Exception {
  final String message;

  SerialPrintError(this.message);

  @override
  String toString() => 'SerialPrintError: $message';
}

// artemis_port_print.dart

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

// class _QueuePortAdapter implements QueuePort {
//   final ArtemisSerialPort port;
//   _QueuePortAdapter(this.port);
//
//   @override
//   bool get isConnected => port.isOpen;
//
//   @override
//   Future<bool> open() async {
//     final ok = await port.openReadWriteSafe();
//     if (ok) port.startListening();
//     return ok;
//   }
//
//   @override
//   Future<bool> close() async {
//     await port.stopListening();
//     return port.close(); // bool
//   }
//
//   @override
//   Stream<DataReceive> get onData => port.onData;
//
//   @override
//   Future<bool> sendBytes(Uint8List message) => port.writeAll(message);
// }

// class _QueuePortAdapter implements SerialPortBaseDart {
//   final ArtemisSerialPort port;
//   _QueuePortAdapter(this.port);
//
//   @override
//   bool get isOpen => port.isOpen;
//
//   @override
//   Future<bool> openReadWrite() async {
//     final ok = await port.openReadWriteSafe();
//     if (ok) port.startListening();
//     return ok;
//   }
//
//   @override
//   Future<bool> close() async {
//     port.stopListening();
//     return port.close(); // already returns bool
//   }
//
//   @override
//   Stream<DataReceive> get onData => port.onData;
//
//   @override
//   Future<bool> writeBytes(List<int> message) => port.writeAll(message);
// }

class ArtemisPortPrinter {
  /// List available ports (utility, not tied to any instance).
  static List<String> get availablePorts => SerialPort.availablePorts;

  final String portName;
  final ArtemisPortPrintSetting? setting;

  // Transport (your refactored class with PortStatus and onData)
  late final ArtemisSerialPort _port = ArtemisSerialPort(portName, config: _config);

  ArtemisSerialPort get port => _port;

  // Device status (parsed OS/SI/etc.)
  final StatusManager _statusMgr = StatusManager();

  ValueListenable<DeviceStatus> get statusListenable => _statusMgr.statusNotifier;

  DeviceStatus get status => _statusMgr.status;

  // Re-expose port status from the transport
  ValueListenable<PortStatus> get portStatusListenable => _port.portStatusListenable;

  PortStatus get portStatus => _port.portStatus.value;

  bool get isOpen => _port.isOpen;

  // Allow external status updates (e.g., from a sequencer)
  void updateStatusFrom(String text, {bool isSqni = false}) {
    _statusMgr.updateFrom(text, sqni: isSqni);
  }

  SerialDeviceConfig? get _config => setting?.getConfig;

  /// Adapter so SerialPrintQueue can work with ArtemisSerialPort
  late final QueuePortAdapter _queuePort = QueuePortAdapter(_port);

  late final SerialPrintQueue _queue = SerialPrintQueue(_queuePort, timeout: const Duration(seconds: 2), quietWindow: const Duration(milliseconds: 150), stripFraming: true);

  StreamSubscription<DataReceive>? _sub; // unsolicited listener
  Timer? _pollTimer;
  bool _bootstrapped = false;

  ArtemisPortPrinter(this.portName, {this.setting});

  // ---------- Lifecycle ----------

  /// Opens the port (if not already), attaches listener, runs bootstrap once,
  /// and starts periodic polling (optional safety net).
  ///

  Future<void> open({bool startPolling = true, Duration pollEvery = const Duration(seconds: 5)}) async {
    if (!_port.isOpen) {
      _setConnecting();

      final ok = await _port.openReadWriteSafe();
      if (!ok) return;

      _port.startListening();

      _sub ??= _port.onData.listen(
        (evt) {
          if(evt is DataReceive) {
            final text = evt.text;
            if (text.isEmpty) return;
            final isSqni = text.toUpperCase().contains('SQNI');
            _statusMgr.updateFrom(text, sqni: isSqni);
          }
        },
        onError: (_) {
          _setOffline();
        },
        onDone: () {
          _setOffline();
        },
      );
    }

    if (!_bootstrapped) {
      await _runBootstrap();
      _bootstrapped = true;
      await _pollOnce();

      // 🔧 if we’re still in “busy/printing” after the initial poll,
      // promote to Ready to clear the transient state.
      if (_statusMgr.status.state == StatusState.busy) {
        _setReady('Connected');
      }
    }

    // ⬇️ Ensure we leave “busy/printing” by actively asking for status once
    // await _awaitFirstStatusSnapshot(maxWait: const Duration(seconds: 2));

    if (startPolling && _pollTimer == null) {
      _pollTimer = Timer.periodic(pollEvery, (_) => _pollOnce());
    }
  }

  /// Closes the port and stops listeners/polling.
  Future<void> close() async {
    _pollTimer?.cancel();
    _pollTimer = null;

    await _sub?.cancel();
    _sub = null;

    if (_port.isOpen) {
      _port.stopListening();
      _port.close();
    }
    _setOffline();
  }

  // ---------- Printing / Commands ----------

  Future<PrintResult> print(String data) async {
    await open(); // ensure open
    return _queue.printText(data);
  }

  Future<PrintResult> printBytes(Uint8List bytes) async {
    await open(); // ensure open
    return _queue.enqueue(bytes);
  }

  /// Runs the AEA init/status sequence once (like your C#).
  Future<DeviceStatus> testQuery() async {
    await open();
    await _runBootstrap();
    await _pollOnce(); // get fresh OS/SI snapshot
    final st = _statusMgr.status;
    log(st.toString());
    return st;
  }

  // ---------- Internals ----------

  Future<void> _runBootstrap() async {
    await _sendAndUpdate("MX");
    await _sendAndUpdate("UG#GID");
    await _sendAndUpdate("EP#AIRLINEID=GID#HARDCODE=HDC#UNSOL=Y");
    await _sendAndUpdate("UC#999");
    await _sendAndUpdate("AV");
    await _sendAndUpdate("PV");
    await _sendAndUpdate("SQ", isSqni: true);
  }

  Future<void> _pollOnce() async {
    await _sendAndUpdate("SQ", isSqni: true);
  }

  Future<void> _sendAndUpdate(String cmd, {bool isSqni = false}) async {
    log("_sendAndUpdate $cmd ==> ");

    // Mark busy while a request is in flight
    if (_statusMgr.status.state != StatusState.busy) {
      log("StatusState was not busy became busy");
      final busy = _statusMgr.status.clone()
        ..state = StatusState.busy
        ..desc = 'Printing...';
      _statusMgr.statusNotifier.value = busy;
    }

    try {
      log("_queue.printText(cmd)");
      final res = await _queue.printText(cmd);
      final text = res.text?.trim() ?? (res.bytes != null ? String.fromCharCodes(res.bytes!).trim() : '');
      if (text.isNotEmpty) {
        _statusMgr.updateFrom(text, sqni: isSqni);

        log("_sendAndUpdate $cmd ==> ${text}");
      } else {
        log("text is empty");
      }
    } catch (e) {
      log("$e");
    } finally {
      // If parser didn’t move us off BUSY, clear to Ready
      if (_statusMgr.status.state == StatusState.busy) {
        _setReady();
      }
    }
  }

  // Future<void> _sendAndUpdate(String cmd, {bool isSqni = false}) async {
  //   final res = await _queue.printText(cmd);
  //   final text = res.text?.trim() ??
  //       (res.bytes != null ? String.fromCharCodes(res.bytes!).trim() : '');
  //   if (text.isEmpty) return;
  //   _statusMgr.updateFrom(text, sqni: isSqni);
  //
  //   // Optional debug:
  //   // final st = _statusMgr.status;
  //   // debugPrint('[AEA:$portName] TX="$cmd"  RX="$text"  -> ${st.state} "${st.desc}"');
  // }

  void _setConnecting() {
    final s = _statusMgr.status.clone()
      ..state = StatusState.busy
      ..desc = 'Connecting...'
      ..ready = false;
    _statusMgr.statusNotifier.value = s;
  }

  void _setOffline() {
    final s = _statusMgr.status.clone()
      ..state = StatusState.offline
      ..desc = 'Offline'
      ..ready = false;
    _statusMgr.statusNotifier.value = s;
  }

  void _setReady([String desc = 'Ready']) {
    final prev = _statusMgr.status; // snapshot current
    final next = prev.clone()
      ..state = StatusState.online
      ..desc = desc
      ..ready = true;
    // If you want to preserve other flags, they're already copied by clone()

    _statusMgr.statusNotifier.value = next;
  }

  Future<void> _awaitFirstStatusSnapshot({Duration maxWait = const Duration(seconds: 2)}) async {
    // Complete when device status changes away from BUSY
    final done = Completer<void>();

    void check() {
      if (_statusMgr.status.state != StatusState.busy) {
        if (!done.isCompleted) done.complete();
      }
    }

    // Listen to status changes
    void listener() => check();
    _statusMgr.statusNotifier.addListener(listener);

    // Kick an explicit status query (“SQ”) to elicit OS/SI immediately
    try {
      await _queue.printText("SQ");
    } catch (_) {
      // ignore; fallback below will handle
    }

    // Failsafe timeout
    final t = Timer(maxWait, () {
      if (!done.isCompleted) done.complete();
    });

    await done.future;
    t.cancel();
    _statusMgr.statusNotifier.removeListener(listener);

    // If still BUSY after waiting, force Ready so we don’t get stuck
    if (_statusMgr.status.state == StatusState.busy) {
      _setReady('Connected');
    }
  }
}

/// Minimal adapter so SerialPrintQueue can work with ArtemisSerialPort.
/// It forwards open/close/send and exposes onData.
/// If your SerialPrintQueue already accepts a custom interface, align this type accordingly.
// class _QueuePortAdapter {
//   final ArtemisSerialPort port;
//   _QueuePortAdapter(this.port);
//
//   bool get isConnected => port.isOpen;
//
//   Future<bool> open() async {
//     final ok = await port.openReadWriteSafe();
//     if (ok) port.startListening();
//     return ok;
//   }
//
//   Future<bool> close() async {
//     port.stopListening();
//     return port.close(); // bool
//   }
//
//   Stream<DataReceive> get onData => port.onData;
//
//   Future<bool> sendBytes(List<int> message) => port.writeAll(message);
// }

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



// extension MoreMethods on SerialPort {

//   static void printData(String data){
//     final port = this;
//     ArtemisPortPrint.print(this, data);
//   }
// }
