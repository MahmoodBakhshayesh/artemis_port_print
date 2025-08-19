import 'dart:developer';

import 'package:flutter/material.dart';

import 'artemis_serial_port.dart';

enum StatusState { online, offline, printHeadLifted, busy, unknown, paperOut, paperJam }

class DeviceStatus {
  bool ready = false;
  bool init = false;
  bool notExist = false;
  bool diskError = false;
  bool paperJam = false;
  bool paperOut = false;
  bool powerOff = false;
  bool unknown = false;
  bool headLifted = false;
  bool maxWeightExceeded = false;
  String desc = 'Unknown';
  StatusState state = StatusState.unknown;

  @override
  String toString() => 'DeviceStatus(state: $state, desc: $desc, ready:$ready, paperOut:$paperOut, paperJam:$paperJam, powerOff:$powerOff, headLifted:$headLifted, unknown:$unknown)';

  DeviceStatus clone() {
    final d = DeviceStatus();
    d..ready = ready
      ..init = init
      ..notExist = notExist
      ..diskError = diskError
      ..paperJam = paperJam
      ..paperOut = paperOut
      ..powerOff = powerOff
      ..unknown = unknown
      ..headLifted = headLifted
      ..maxWeightExceeded = maxWeightExceeded
      ..desc = desc
      ..state = state;
    return d;
  }
}


class StatusParsers {
  // OS=0 or OS#0 or OS:0  (captures one digit 0..9)
  static final RegExp _osExp =
  RegExp(r'\bOS\s*[#=:]\s*([0-9])', caseSensitive: false);

  // SI=00 / SI=11 / SI=1O / SI=1J (two chars after the delimiter)
  // Accepts 0/O ambiguity.
  static final RegExp _siExp =
  RegExp(r'\bSI\s*[#=:]\s*([A-Za-z0-9]{2})', caseSensitive: false);

  static String? extractOS(String s) {
    final m = _osExp.firstMatch(s);
    return m == null ? null : m.group(1); // e.g., "0"
  }

  static String? extractSI(String s) {
    final m = _siExp.firstMatch(s);
    if (m == null) return null;
    final v = m.group(1)!.toUpperCase();
    // Normalize letter 'O' to zero for convenience
    return (v == '1O') ? '10' : v; // map 1O -> 10
  }
}


class StatusManager {
  final DeviceStatus _status = DeviceStatus();
  final ValueNotifier<DeviceStatus> statusNotifier =
  ValueNotifier<DeviceStatus>(DeviceStatus());

  DeviceStatus get status => statusNotifier.value;

  void updateFrom(String statusString, {required bool sqni}) {
    try {
      if (statusString.isEmpty) return;

      final sUp = statusString.toUpperCase();

      // ---- First: look for OS in strings like "HDCSQOK#OS=0#...#SI=00"
      final os = StatusParsers.extractOS(sUp);
      if (os != null) {
        switch (os) {
          case '0': // online
            _status
              ..ready = true
              ..init = false
              ..notExist = false
              ..diskError = false
              ..paperJam = false
              ..paperOut = false
              ..powerOff = false
              ..unknown = false
              ..headLifted = false
              ..maxWeightExceeded = false
              ..desc = 'Device is Ready'
              ..state = StatusState.online;
            break;

          case '1': // offline
            _status
              ..ready = false
              ..init = false
              ..notExist = false
              ..diskError = false
              ..paperJam = false
              ..paperOut = false
              ..powerOff = true
              ..unknown = false
              ..headLifted = false
              ..maxWeightExceeded = false
              ..desc = 'Device is Offline'
              ..state = StatusState.offline;
            if (sqni) {
              // match your C# tweak for SQNI case
              _status.powerOff = false;
              _status.unknown = true;
            }
            break;

          case '2': // print head lifted (your C# also set paperJam=true)
            _status
              ..ready = true
              ..init = false
              ..notExist = false
              ..diskError = false
              ..paperJam = true
              ..headLifted = true
              ..paperOut = false
              ..powerOff = false
              ..unknown = false
              ..maxWeightExceeded = false
              ..desc = 'Printer Head Lifted'
              ..state = StatusState.printHeadLifted;
            break;

          case '3': // busy
            _status
              ..ready = true
              ..init = false
              ..notExist = false
              ..diskError = false
              ..paperJam = false
              ..paperOut = false
              ..powerOff = false
              ..unknown = false
              ..headLifted = false
              ..maxWeightExceeded = false
              ..desc = 'Busy'
              ..state = StatusState.busy;
            break;

          default:  // other error/unknown
            _status
              ..ready = false
              ..init = false
              ..notExist = false
              ..diskError = false
              ..paperJam = false
              ..paperOut = false
              ..powerOff = false
              ..unknown = true
              ..headLifted = false
              ..maxWeightExceeded = false
              ..desc = 'Unknown'
              ..state = StatusState.unknown;
        }
      }

      // ---- Then: look for SI=.. flags (paper state), if present
      final si = StatusParsers.extractSI(sUp);
      if (si != null) {
        switch (si) {
          case '00':
          case '11':
            _status.paperJam = false;
            _status.paperOut = false;
            break;

          case '10': // normalized from 1O -> paper out
            _status
              ..ready = true
              ..init = false
              ..notExist = false
              ..diskError = false
              ..paperJam = false
              ..paperOut = true
              ..powerOff = false
              ..unknown = false
              ..maxWeightExceeded = false
              ..desc = 'Paper Out'
              ..state = StatusState.paperOut;
            break;

          case '1J': // paper jam
            _status
              ..ready = true
              ..init = false
              ..notExist = false
              ..diskError = false
              ..paperJam = true
              ..paperOut = false
              ..powerOff = false
              ..unknown = false
              ..maxWeightExceeded = false
              ..desc = 'Paper Jam'
              ..state = StatusState.paperJam;
            break;
        }
      }

      // ---- Fallbacks for single-word replies like HDCMXOK / HDCUCOK#999
      if (os == null && si == null) {
        if (sUp.contains('OK')) {
          _status
            ..ready = true
            ..init = false
            ..notExist = false
            ..diskError = false
            ..paperJam = false
            ..paperOut = false
            ..powerOff = false
            ..unknown = false
            ..maxWeightExceeded = false
            ..desc = 'Device is Ready'
            ..state = StatusState.online;
        } else if (sUp.contains('ERR')) {
          // mirrors your C# (ERR still set to Ready/online)
          _status
            ..ready = true
            ..init = false
            ..notExist = false
            ..diskError = false
            ..paperJam = false
            ..paperOut = false
            ..powerOff = false
            ..unknown = false
            ..maxWeightExceeded = false
            ..desc = 'Device is Ready'
            ..state = StatusState.online;
        }
      }

      // publish snapshot
      statusNotifier.value = _status.clone();
    } catch (_) {
      // swallow/log as in C#
    }
  }
}


class AeaSequencer {
  final ArtemisSerialPort port; // your wrapper
  final StatusManager statusMgr;

  AeaSequencer(this.port, this.statusMgr);

  /// Runs the AEA bootstrap/status sequence in order.
  /// Returns the final status snapshot.
  Future<DeviceStatus> run() async {
    // MX
    await _sendAndUpdate("MX");

    // UG#GID
    await _sendAndUpdate("UG#GID");

    // EP#AIRLINEID=GID#HARDCODE=HDC#UNSOL=Y
    await _sendAndUpdate("EP#AIRLINEID=GID#HARDCODE=HDC#UNSOL=Y");

    // UC#999
    await _sendAndUpdate("UC#999");

    // AV
    await _sendAndUpdate("AV");

    // PV
    await _sendAndUpdate("PV");

    // SQ
    await _sendAndUpdate("SQ", isSqni: true); // mark as unsolicited/status-query if needed

    return statusMgr.status;
  }

  Future<void> _sendAndUpdate(String cmd, {bool isSqni = false}) async {
    final res = await port.printData(cmd);
    // Prefer decoded text; if null, try bytes as ASCII.
    final text = res.text ?? (res.bytes != null ? String.fromCharCodes(res.bytes!) : '');
    log("_sendAndUpdate $cmd ==> ${text}");

    statusMgr.updateFrom(text, sqni: isSqni);
  }
}
