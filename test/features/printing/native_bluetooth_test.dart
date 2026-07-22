import 'package:dar_al_turab_pos/features/printing/native_bluetooth.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  BondedDevice device(int majorClass) => BondedDevice(
    name: 'x',
    address: '00:11:22:33:44:55',
    majorClass: majorClass,
  );

  group('BondedDevice.looksLikePrinter', () {
    test('accepts the Imaging class (printers)', () {
      expect(device(1536).looksLikePrinter, isTrue);
    });

    test('accepts uncategorised / misc, where cheap printers often land', () {
      expect(device(7936).looksLikePrinter, isTrue);
      expect(device(0).looksLikePrinter, isTrue);
    });

    test('rejects the Audio/Video class (earbuds, speakers)', () {
      expect(device(1024).looksLikePrinter, isFalse);
    });

    test('rejects the Phone class', () {
      expect(device(512).looksLikePrinter, isFalse);
    });
  });
}
