import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'printer_transport.dart';

/// Bluetooth Classic (SPP) transport.
///
/// This is the preferred path for the PM400 on Android: SPP is a plain
/// stream socket, so a whole receipt can be written without MTU chunking or
/// inter-packet pacing.
///
/// Unsupported on iOS, which requires MFi certification for Classic
/// accessories. [isSupported] is false there and the app must fall back to
/// the BLE transport.
class BluetoothClassicTransport implements PrinterTransport {
  DiscoveredPrinter? _connected;

  @override
  PrinterTransportKind get kind => PrinterTransportKind.bluetoothClassic;

  /// Uses [defaultTargetPlatform] rather than `dart:io`'s `Platform` so this
  /// file still compiles for web, where `dart:io` is unavailable.
  @override
  bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<bool> get isBluetoothOn async {
    if (!isSupported) return false;
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } on Object {
      return false;
    }
  }

  @override
  Future<bool> get isConnected async {
    if (!isSupported) return false;
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } on Object {
      return false;
    }
  }

  /// Returns printers already paired in Android's Bluetooth settings.
  ///
  /// SPP has no discovery step here — the user pairs the PM400 once in system
  /// settings, and it then appears in this list.
  @override
  Future<List<DiscoveredPrinter>> discover({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    _ensureSupported();

    if (!await isBluetoothOn) {
      throw const PrintException(
        PrintFailure.bluetoothOff,
        'Bluetooth is turned off.',
      );
    }

    try {
      final devices = await PrintBluetoothThermal.pairedBluetooths.timeout(
        timeout,
      );

      return devices
          .map(
            (device) => DiscoveredPrinter(
              name: device.name.isEmpty ? 'Unknown printer' : device.name,
              address: device.macAdress,
              transport: PrinterTransportKind.bluetoothClassic,
            ),
          )
          .toList(growable: false);
    } on PrintException {
      rethrow;
    } on Object catch (e) {
      throw PrintException(
        PrintFailure.permissionDenied,
        'Could not list paired devices: $e',
      );
    }
  }

  @override
  Future<void> connect(DiscoveredPrinter printer) async {
    _ensureSupported();

    if (!await isBluetoothOn) {
      throw const PrintException(
        PrintFailure.bluetoothOff,
        'Bluetooth is turned off.',
      );
    }

    // Reconnecting while a socket is already open fails on some Android
    // stacks, so always start from a clean state.
    if (await isConnected) {
      await disconnect();
    }

    final ok = await PrintBluetoothThermal.connect(
      macPrinterAddress: printer.address,
    );

    if (!ok) {
      throw PrintException(
        PrintFailure.notConnected,
        'Could not connect to ${printer.name}.',
      );
    }

    _connected = printer;
  }

  @override
  Future<void> disconnect() async {
    if (!isSupported) return;
    try {
      await PrintBluetoothThermal.disconnect;
    } on Object {
      // Already gone; nothing to release.
    }
    _connected = null;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    _ensureSupported();

    if (!await isConnected) {
      throw PrintException(
        PrintFailure.notConnected,
        _connected == null
            ? 'No printer is connected.'
            : 'Lost connection to ${_connected!.name}.',
      );
    }

    final ok = await PrintBluetoothThermal.writeBytes(bytes);
    if (!ok) {
      // The plugin reports a boolean only, so we cannot tell paper-out from a
      // dropped link here. The PM400 shows the specific fault on its OLED.
      throw const PrintException(
        PrintFailure.connectionLost,
        'The printer rejected the data or the connection dropped.',
      );
    }
  }

  void _ensureSupported() {
    if (!isSupported) {
      throw const PrintException(
        PrintFailure.unknown,
        'Bluetooth Classic printing is only available on Android. '
        'iOS must use the Bluetooth LE transport.',
      );
    }
  }
}
