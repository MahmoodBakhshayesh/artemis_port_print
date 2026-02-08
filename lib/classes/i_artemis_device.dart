import 'package:flutter/foundation.dart';
import 'enums.dart';

/// Defines a common interface for all Artemis port devices.
abstract class IArtemisDevice {
  /// A listenable that notifies about the device's connection status.
  ValueListenable<DeviceConnectionStatus> get connectionStatus;

  /// The current connection status of the device.
  DeviceConnectionStatus get currentConnectionStatus;

  /// Opens the connection to the device.
  Future<bool> connect();

  /// Closes the connection to the device.
  Future<bool> disconnect();

  /// Releases all resources held by the device.
  void dispose();
}
