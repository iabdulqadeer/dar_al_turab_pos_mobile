import 'dart:typed_data';

import 'package:dar_al_turab_pos/features/printing/bluetooth_classic_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression guard for the print_bluetooth_thermal marshalling bug.
///
/// The plugin's Android side does `call.arguments as List<Int>`. Flutter's
/// StandardMessageCodec serialises a [Uint8List] as a Java `byte[]`, which the
/// cast rejects with "byte[] cannot be cast to java.util.List" — the plugin
/// then returns a bare `false` and printing fails silently. Confirmed
/// on-device via logcat. The transport must therefore hand `writeBytes` a
/// plain `List<int>`, never a `Uint8List`.
///
/// A channel-level test is not possible on a Windows test host: the plugin
/// branches on `Platform.isWindows` and bypasses the MethodChannel entirely,
/// so [toPluginPayload] is the isolated, platform-free seam that the fix lives
/// in.
void main() {
  test('toPluginPayload yields a List, never a Uint8List', () {
    final payload = BluetoothClassicTransport.toPluginPayload(
      Uint8List.fromList([27, 64, 10]),
    );

    expect(
      payload,
      isNot(isA<Uint8List>()),
      reason: 'A Uint8List marshals as byte[] and the plugin rejects it.',
    );
    expect(payload, [27, 64, 10]);
  });
}
