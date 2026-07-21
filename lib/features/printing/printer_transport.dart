import 'dart:typed_data';

/// A printer the user can select.
class DiscoveredPrinter {
  const DiscoveredPrinter({
    required this.name,
    required this.address,
    required this.transport,
  });

  final String name;

  /// MAC address on Android SPP, or the peripheral UUID on iOS BLE.
  final String address;
  final PrinterTransportKind transport;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredPrinter &&
      other.address == address &&
      other.transport == transport;

  @override
  int get hashCode => Object.hash(address, transport);
}

enum PrinterTransportKind {
  /// Bluetooth Classic Serial Port Profile. Android only — iOS requires MFi
  /// certification for SPP, which the PM400 does not carry.
  bluetoothClassic,

  /// Bluetooth Low Energy GATT. The only option on iOS.
  bluetoothLe,
}

/// Why a print attempt failed. Distinguished so the UI can tell a cashier
/// what to physically do, rather than showing a generic error.
enum PrintFailure {
  notConnected,
  connectionLost,
  outOfPaper,
  coverOpen,
  permissionDenied,
  bluetoothOff,
  timeout,
  unknown,
}

class PrintException implements Exception {
  const PrintException(this.failure, this.message);

  final PrintFailure failure;
  final String message;

  /// Guidance the cashier can act on without leaving the till.
  String get remedy => switch (failure) {
    PrintFailure.outOfPaper => 'Load a new paper roll and try again.',
    PrintFailure.coverOpen => 'Close the printer cover and try again.',
    PrintFailure.bluetoothOff => 'Turn on Bluetooth and try again.',
    PrintFailure.permissionDenied =>
      'Allow Bluetooth access for this app in Settings.',
    PrintFailure.notConnected ||
    PrintFailure.connectionLost =>
      'Check the printer is on and in range, then reconnect.',
    PrintFailure.timeout => 'The printer stopped responding. Try again.',
    PrintFailure.unknown => 'Try again, or reconnect the printer.',
  };

  @override
  String toString() => 'PrintException($failure): $message';
}

/// Sends raw bytes to a thermal printer.
///
/// Implementations differ per platform (SPP on Android, BLE on iOS) but the
/// receipt pipeline never knows which is in use.
abstract interface class PrinterTransport {
  PrinterTransportKind get kind;

  /// Whether this transport can run on the current platform.
  bool get isSupported;

  Future<bool> get isBluetoothOn;

  /// Printers already paired at the OS level (Classic), or discovered by
  /// scanning (BLE).
  Future<List<DiscoveredPrinter>> discover({
    Duration timeout = const Duration(seconds: 10),
  });

  Future<void> connect(DiscoveredPrinter printer);

  Future<void> disconnect();

  Future<bool> get isConnected;

  /// Writes [bytes] to the connected printer.
  ///
  /// Implementations are responsible for chunking to the transport's MTU;
  /// callers hand over the whole receipt at once.
  Future<void> write(Uint8List bytes);
}
