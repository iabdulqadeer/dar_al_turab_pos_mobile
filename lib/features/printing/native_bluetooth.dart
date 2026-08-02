import 'package:flutter/services.dart';

/// A paired Bluetooth device as reported by the OS, including its major device
/// class — the piece `print_bluetooth_thermal` does not expose and which lets
/// us tell a printer apart from earbuds or a phone.
class BondedDevice {
  const BondedDevice({
    required this.name,
    required this.address,
    required this.majorClass,
  });

  final String name;
  final String address;

  /// Android `BluetoothClass.getMajorDeviceClass()`. See [printerMajorClasses].
  final int majorClass;

  /// True when the OS classifies this device as a printer (or leaves it
  /// uncategorised, which many cheap thermal printers do).
  bool get looksLikePrinter => printerMajorClasses.contains(majorClass);

  /// `IMAGING` (1536) is the printer class; `UNCATEGORIZED` (7936) and `MISC`
  /// (0) are lenient catch-alls for printers with a poorly-set class of device.
  static const printerMajorClasses = {1536, 7936, 0};
}

/// Thin wrapper over the platform channel implemented in `MainActivity.kt`.
class NativeBluetooth {
  const NativeBluetooth();

  static const _channel = MethodChannel('dar_al_turab/bluetooth');

  /// Paired devices with their major class. Throws [PlatformException] /
  /// [MissingPluginException] when the channel is unavailable (non-Android, or
  /// permission not yet granted) — callers should fall back.
  Future<List<BondedDevice>> bondedDevices() async {
    final raw = await _channel.invokeMethod<List<dynamic>>('bondedDevices');
    if (raw == null) return const [];

    return raw.whereType<Map>().map((e) {
      final map = Map<Object?, Object?>.from(e);
      return BondedDevice(
        name: (map['name'] as String?)?.trim().isNotEmpty == true
            ? map['name'] as String
            : 'Unknown device',
        address: map['address'] as String? ?? '',
        majorClass: (map['majorClass'] as num?)?.toInt() ?? -1,
      );
    }).where((d) => d.address.isNotEmpty).toList(growable: false);
  }

  /// Whether the Bluetooth adapter is currently on. Safe on any platform —
  /// returns false when the channel is unavailable.
  Future<bool> isBluetoothOn() async {
    try {
      return await _channel.invokeMethod<bool>('isBluetoothOn') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Asks the OS to turn Bluetooth on, showing the system consent dialog. The
  /// result arrives asynchronously via the app resuming, so callers should
  /// re-read [isBluetoothOn] on resume rather than trusting an immediate value.
  Future<void> requestEnable() async {
    await _channel.invokeMethod<void>('requestEnable');
  }

  /// Attempts to turn Bluetooth off. Returns the native status:
  /// `'disabled'` (turned off), `'already_off'`, or `'unsupported'` (blocked by
  /// the OS on Android 13+, where the caller should [openSettings] instead).
  Future<String> disable() async {
    try {
      return await _channel.invokeMethod<String>('disable') ?? 'unsupported';
    } on PlatformException {
      return 'unsupported';
    } on MissingPluginException {
      return 'unsupported';
    }
  }

  /// Opens the system Bluetooth settings — the fallback for turning Bluetooth
  /// off where the app is not allowed to.
  Future<void> openSettings() async {
    await _channel.invokeMethod<void>('openSettings');
  }
}
