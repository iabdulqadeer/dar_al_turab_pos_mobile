import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';

import 'native_bluetooth.dart';
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

  final NativeBluetooth _native = const NativeBluetooth();

  /// Returns printers already paired in Android's Bluetooth settings.
  ///
  /// SPP has no discovery step here — the user pairs the PM400 once in system
  /// settings, and it then appears in this list. By default the list is limited
  /// to printer-class devices (via the OS device class) so earbuds and phones
  /// don't clutter it; [includeAll] returns every paired device.
  @override
  Future<List<DiscoveredPrinter>> discover({
    Duration timeout = const Duration(seconds: 10),
    bool includeAll = false,
  }) async {
    _ensureSupported();

    if (!await isBluetoothOn) {
      throw const PrintException(
        PrintFailure.bluetoothOff,
        'Bluetooth is turned off.',
      );
    }

    // Preferred path: the native channel gives each device's major class, so we
    // can show printers only. If it is unavailable (permission timing, etc.),
    // fall back to the plugin's unfiltered list rather than showing nothing.
    try {
      final bonded = await _native.bondedDevices().timeout(timeout);
      final devices = [
        for (final d in bonded)
          if (includeAll || d.looksLikePrinter)
            DiscoveredPrinter(
              name: d.name,
              address: d.address,
              transport: PrinterTransportKind.bluetoothClassic,
              majorClass: d.majorClass,
            ),
      ];
      // If the class filter hid everything (e.g. a printer with an odd class),
      // show the full list so the user is never stuck with an empty screen.
      if (devices.isEmpty && !includeAll && bonded.isNotEmpty) {
        return _fromPlugin(timeout);
      }
      return devices;
    } on Object {
      return _fromPlugin(timeout);
    }
  }

  /// Fallback listing via the printing plugin (name + MAC only, unfiltered).
  Future<List<DiscoveredPrinter>> _fromPlugin(Duration timeout) async {
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

    final ok = await PrintBluetoothThermal.writeBytes(toPluginPayload(bytes));
    if (!ok) {
      // The plugin reports a boolean only, so we cannot tell paper-out from a
      // dropped link here. The PM400 shows the specific fault on its OLED.
      throw const PrintException(
        PrintFailure.connectionLost,
        'The printer rejected the data or the connection dropped.',
      );
    }
  }

  /// Converts the receipt bytes into the exact type the plugin expects.
  ///
  /// `print_bluetooth_thermal`'s Android handler does
  /// `call.arguments as List<Int>`, but Flutter's method-channel codec
  /// serialises a [Uint8List] as a Java `byte[]`, not a `List`. Passing the
  /// [Uint8List] straight through throws "byte[] cannot be cast to
  /// java.util.List" on the native side, which the plugin swallows into a bare
  /// `false` — indistinguishable from a real write failure, and the cause of
  /// every "printer rejected the data" error (confirmed on-device via logcat).
  ///
  /// A plain growable `List<int>` marshals as a codec LIST, which the cast
  /// accepts. Kept as a named, testable seam so this never silently regresses
  /// to a [Uint8List].
  static List<int> toPluginPayload(Uint8List bytes) => List<int>.from(bytes);

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
