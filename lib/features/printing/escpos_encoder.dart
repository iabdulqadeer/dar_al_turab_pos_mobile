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
  /// Lays a line out inside a fixed [contentWidth] field and shifts it right by
  /// [leftMargin], so the whole receipt prints as one centred block rather than
  /// hugging the paper's left edge.
  ///
  /// Alignment is baked into leading spaces (never trailing) and the caller
  /// emits every line left-aligned — this keeps the margin uniform across left,
  /// centre and right lines, which per-line `ESC a` centring cannot do when the
  /// paper is wider than the content. The preview renders with this same
  /// function, so what is shown is what prints.
  static String layoutLine(
    String text,
    ReceiptAlign align,
    int contentWidth,
    int leftMargin,
  ) {
    final margin = ' ' * (leftMargin < 0 ? 0 : leftMargin);
    final slack = contentWidth - text.length;
    if (slack <= 0) return '$margin$text';

    return switch (align) {
      ReceiptAlign.left => '$margin$text',
      ReceiptAlign.center => '$margin${' ' * (slack ~/ 2)}$text',
      ReceiptAlign.right => '$margin${' ' * slack}$text',
    };
  }

  /// Encodes [lines] into a printable byte stream.
  ///
  /// [copies] prints the same receipt more than once. When [contentWidth] > 0,
  /// each line is laid out via [layoutLine] and emitted left-aligned so the
  /// receipt sits as a centred block with [leftMargin] on the left; when it is
  /// 0, the server's per-line alignment is used verbatim.
  Uint8List encode(
    List<ReceiptLine> lines, {
    int copies = 1,
    int trailingFeed = 4,
    int contentWidth = 0,
    int leftMargin = 0,
  }) {
    assert(copies >= 1, 'copies must be at least 1');

    final centred = contentWidth > 0;
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
        // In centred mode every line is left-aligned and the alignment is
        // pre-baked into the text; otherwise honour the line's own alignment.
        final emitAlign = centred ? ReceiptAlign.left : line.align;
        final text = centred
            ? layoutLine(line.text, line.align, contentWidth, leftMargin)
            : line.text;

        if (emitAlign != currentAlign) {
          bytes.addAll(EscPos.align(emitAlign));
          currentAlign = emitAlign;
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
          ..addAll(_encodeText(text))
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
