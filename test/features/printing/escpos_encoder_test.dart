import 'package:dar_al_turab_pos/data/models/receipt.dart';
import 'package:dar_al_turab_pos/features/printing/escpos_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

/// Finds [needle] inside [haystack], for asserting a command was emitted.
bool containsSequence(List<int> haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) return false;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) return true;
  }
  return false;
}

int countSequence(List<int> haystack, List<int> needle) {
  var count = 0;
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    var match = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        match = false;
        break;
      }
    }
    if (match) count++;
  }
  return count;
}

void main() {
  const encoder = EscPosEncoder();

  group('EscPosEncoder', () {
    test('starts every copy with an init and code page command', () {
      final bytes = encoder.encode([const ReceiptLine(text: 'Hello')]);

      expect(bytes.sublist(0, 2), [0x1B, 0x40]); // ESC @
      expect(containsSequence(bytes, [0x1B, 0x74, 0x00]), isTrue); // ESC t 0
    });

    test('encodes line text followed by a line feed', () {
      final bytes = encoder.encode([const ReceiptLine(text: 'AB')]);

      expect(containsSequence(bytes, [0x41, 0x42, 0x0A]), isTrue);
    });

    test('emits centre alignment for centered lines', () {
      final bytes = encoder.encode([
        const ReceiptLine(text: 'TITLE', align: ReceiptAlign.center),
      ]);

      expect(containsSequence(bytes, [0x1B, 0x61, 0x01]), isTrue);
    });

    test('emits right alignment for right-aligned lines', () {
      final bytes = encoder.encode([
        const ReceiptLine(text: 'X', align: ReceiptAlign.right),
      ]);

      expect(containsSequence(bytes, [0x1B, 0x61, 0x02]), isTrue);
    });

    test('turns bold on and off around a bold line', () {
      final bytes = encoder.encode([
        const ReceiptLine(text: 'plain'),
        const ReceiptLine(text: 'bold', bold: true),
        const ReceiptLine(text: 'plain again'),
      ]);

      expect(containsSequence(bytes, [0x1B, 0x45, 0x01]), isTrue);
      expect(containsSequence(bytes, [0x1B, 0x45, 0x00]), isTrue);
    });

    test('emits double size only for large lines', () {
      final normal = encoder.encode([const ReceiptLine(text: 'a')]);
      final large = encoder.encode([
        const ReceiptLine(text: 'a', size: ReceiptSize.large),
      ]);

      expect(containsSequence(normal, [0x1D, 0x21, 0x11]), isFalse);
      expect(containsSequence(large, [0x1D, 0x21, 0x11]), isTrue);
    });

    test('does not repeat control codes for unchanged styling', () {
      // Three consecutive centered lines should set alignment once, not
      // three times - thermal links are slow and redundant escapes cost time.
      final bytes = encoder.encode([
        const ReceiptLine(text: 'a', align: ReceiptAlign.center),
        const ReceiptLine(text: 'b', align: ReceiptAlign.center),
        const ReceiptLine(text: 'c', align: ReceiptAlign.center),
      ]);

      expect(countSequence(bytes, [0x1B, 0x61, 0x01]), 1);
    });

    test('repeats the whole document for multiple copies', () {
      final one = encoder.encode([const ReceiptLine(text: 'x')]);
      final two = encoder.encode([const ReceiptLine(text: 'x')], copies: 2);

      // Each copy re-inits, so ESC @ appears once per copy.
      expect(countSequence(one, [0x1B, 0x40]), 1);
      expect(countSequence(two, [0x1B, 0x40]), 2);
      expect(two.length, greaterThan(one.length));
    });

    test('resets styling and feeds paper at the end of a copy', () {
      final bytes = encoder.encode([
        const ReceiptLine(text: 'x', bold: true),
      ]);

      expect(containsSequence(bytes, [0x1B, 0x45, 0x00]), isTrue);
      expect(containsSequence(bytes, [0x1B, 0x64, 0x04]), isTrue); // ESC d 4
    });

    test('substitutes characters outside the code page', () {
      // Arabic cannot be represented in PC437; it must degrade to '?' rather
      // than emit truncated multi-byte sequences that corrupt the stream.
      final bytes = encoder.encode([const ReceiptLine(text: 'مرحبا')]);

      expect(bytes.every((b) => b <= 0xFF), isTrue);
      expect(containsSequence(bytes, [0x3F]), isTrue);
    });

    test('preserves the server\'s column padding verbatim', () {
      // The server pre-pads columns; re-wrapping here would break alignment
      // with the web receipt, so the exact bytes must survive.
      const padded = 'Sub Total                          420.00';
      final bytes = encoder.encode([const ReceiptLine(text: padded)]);

      expect(containsSequence(bytes, padded.codeUnits), isTrue);
    });
  });

  group('QR encoding', () {
    test('emits the store and print commands with the payload', () {
      final bytes = encoder.encodeQrCode('ABC');

      // Store command: GS ( k pL pH 49 80 48 then payload.
      expect(
        containsSequence(bytes, [0x1D, 0x28, 0x6B, 0x06, 0x00, 0x31, 0x50, 0x30]),
        isTrue,
      );
      expect(containsSequence(bytes, 'ABC'.codeUnits), isTrue);
      // Print command.
      expect(
        containsSequence(bytes, [0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30]),
        isTrue,
      );
    });

    test('computes a two-byte length for long payloads', () {
      // A ZATCA TLV base64 blob easily exceeds 255 bytes, so the high byte
      // must be populated or the printer truncates the QR.
      final payload = 'A' * 300;
      final bytes = encoder.encodeQrCode(payload);

      const expectedLength = 303; // payload + 3
      expect(
        containsSequence(bytes, [
          0x1D, 0x28, 0x6B,
          expectedLength & 0xFF,
          (expectedLength >> 8) & 0xFF,
          0x31, 0x50, 0x30,
        ]),
        isTrue,
      );
    });
  });

  group('containsUnsupportedGlyphs', () {
    test('accepts plain ASCII receipts', () {
      expect(
        EscPosEncoder.containsUnsupportedGlyphs([
          const ReceiptLine(text: 'DAR AL TURAB'),
          const ReceiptLine(text: 'Grand Total   420.00'),
        ]),
        isFalse,
      );
    });

    test('flags Arabic text, which text mode cannot shape', () {
      expect(
        EscPosEncoder.containsUnsupportedGlyphs([
          const ReceiptLine(text: 'دار التراب'),
        ]),
        isTrue,
      );
    });
  });
}
