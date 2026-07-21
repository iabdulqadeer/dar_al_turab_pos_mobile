import 'dart:convert';
import 'dart:typed_data';

import '../../data/models/receipt.dart';

/// Raw ESC/POS control sequences.
///
/// The Pegasus PM400 speaks ESC/POS (and CPCL). At 203dpi with a 104mm
/// printable width it has 832 dots per line, so Font A (12 dots wide) fits
/// 69 characters and Font B (9 dots) fits 92. The server clamps its layout to
/// 32-64 characters, which sits comfortably inside Font A.
abstract final class EscPos {
  /// ESC @ — reset to power-on defaults.
  static const init = [0x1B, 0x40];

  /// ESC a n — 0 left, 1 center, 2 right.
  static List<int> align(ReceiptAlign align) => [
    0x1B,
    0x61,
    switch (align) {
      ReceiptAlign.left => 0,
      ReceiptAlign.center => 1,
      ReceiptAlign.right => 2,
    },
  ];

  /// ESC E n — emphasised (bold) on/off.
  static List<int> bold(bool on) => [0x1B, 0x45, on ? 1 : 0];

  /// GS ! n — character size. Low nibble height, high nibble width.
  static List<int> size(ReceiptSize size) => [
    0x1D,
    0x21,
    size == ReceiptSize.large ? 0x11 : 0x00,
  ];

  /// ESC t n — select character code table.
  static List<int> codePage(int page) => [0x1B, 0x74, page];

  /// ESC d n — feed n lines.
  static List<int> feed(int lines) => [0x1B, 0x64, lines];

  /// GS V m — cut paper. The PM400 has no cutter (tear bar only), so this is
  /// a no-op there; kept because the same encoder drives counter printers.
  static const cut = [0x1D, 0x56, 0x01];

  static const lineFeed = [0x0A];
}

/// Builds an ESC/POS byte stream from server-formatted receipt lines.
///
/// Deliberately does **no** layout: `SaleReceiptFormatter` on the Laravel side
/// has already padded columns and wrapped text to a fixed character width.
/// Re-wrapping here would break agreement with the web receipt.
class EscPosEncoder {
  const EscPosEncoder({this.codePage = 0});

  /// Character code table selected with `ESC t`. 0 is PC437 (US/Europe),
  /// which covers the ASCII the server emits. Arabic needs a different table
  /// *and* pre-shaped text, which text mode cannot do — see
  /// [EscPosEncoder.containsUnsupportedGlyphs].
  final int codePage;

  /// Encodes [lines] into a printable byte stream.
  ///
  /// [copies] prints the same receipt more than once. The API returns a
  /// single copy, whereas the web app printed Customer + Company copies, so
  /// the number of physical copies is a client decision.
  Uint8List encode(
    List<ReceiptLine> lines, {
    int copies = 1,
    int trailingFeed = 4,
  }) {
    assert(copies >= 1, 'copies must be at least 1');

    final bytes = <int>[];

    for (var copy = 0; copy < copies; copy++) {
      bytes
        ..addAll(EscPos.init)
        ..addAll(EscPos.codePage(codePage));

      // Track emitted state so we only send control codes on change; thermal
      // printers are slow on the wire and redundant escapes cost throughput.
      var currentAlign = ReceiptAlign.left;
      var currentBold = false;
      var currentSize = ReceiptSize.normal;

      for (final line in lines) {
        if (line.align != currentAlign) {
          bytes.addAll(EscPos.align(line.align));
          currentAlign = line.align;
        }
        if (line.bold != currentBold) {
          bytes.addAll(EscPos.bold(line.bold));
          currentBold = line.bold;
        }
        if (line.size != currentSize) {
          bytes.addAll(EscPos.size(line.size));
          currentSize = line.size;
        }

        bytes
          ..addAll(_encodeText(line.text))
          ..addAll(EscPos.lineFeed);
      }

      // Leave the printer in a known state for whatever prints next.
      bytes
        ..addAll(EscPos.bold(false))
        ..addAll(EscPos.size(ReceiptSize.normal))
        ..addAll(EscPos.align(ReceiptAlign.left))
        ..addAll(EscPos.feed(trailingFeed));
    }

    return Uint8List.fromList(bytes);
  }

  /// Encodes a QR payload using the GS ( k command set.
  ///
  /// Used for the ZATCA TLV blob the server returns as `qr_code`. Note the
  /// server already base64-encodes the TLV; that base64 string is what gets
  /// printed, matching what the web template embeds.
  Uint8List encodeQrCode(String data, {int moduleSize = 6}) {
    final payload = latin1.encode(data);
    // Command length is payload + 3 for the cn/fn/m prefix bytes.
    final length = payload.length + 3;
    final pL = length & 0xFF;
    final pH = (length >> 8) & 0xFF;

    return Uint8List.fromList([
      // Model 2.
      0x1D, 0x28, 0x6B, 0x04, 0x00, 0x31, 0x41, 0x32, 0x00,
      // Module size.
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x43, moduleSize,
      // Error correction level M.
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x45, 0x31,
      // Store the payload.
      0x1D, 0x28, 0x6B, pL, pH, 0x31, 0x50, 0x30, ...payload,
      // Print it.
      0x1D, 0x28, 0x6B, 0x03, 0x00, 0x31, 0x51, 0x30,
    ]);
  }

  /// Encodes text for the selected code page, substituting anything the
  /// table cannot represent so a stray glyph never corrupts the stream.
  List<int> _encodeText(String text) {
    final out = <int>[];
    for (final unit in text.codeUnits) {
      out.add(unit <= 0xFF ? unit : 0x3F); // '?' for out-of-range glyphs
    }
    return out;
  }

  /// True when [lines] contain characters ESC/POS text mode cannot render
  /// correctly — principally Arabic, which needs contextual shaping the
  /// printer does not perform.
  ///
  /// Callers should fall back to raster rendering for these receipts rather
  /// than printing mojibake.
  static bool containsUnsupportedGlyphs(List<ReceiptLine> lines) {
    return lines.any((line) => line.text.runes.any((rune) => rune > 0xFF));
  }
}
