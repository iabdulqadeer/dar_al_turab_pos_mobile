import '../../data/models/receipt.dart';
import 'escpos_encoder.dart';
import 'printer_transport.dart';

/// Outcome of a print attempt, including any non-fatal warning worth showing.
class PrintOutcome {
  const PrintOutcome({required this.copies, this.warning});

  final int copies;

  /// Set when the receipt printed but something may look wrong, e.g. a
  /// column-width mismatch. Not an error — the paper did come out.
  final String? warning;

  bool get hasWarning => warning != null;
}

/// Turns an [InvoiceDocument] into bytes and pushes them to a printer.
///
/// Layout is entirely the server's responsibility (`SaleReceiptFormatter`);
/// this class only styles, encodes, and transmits.
class ReceiptPrinter {
  const ReceiptPrinter({
    required PrinterTransport transport,
    EscPosEncoder encoder = const EscPosEncoder(),
  }) : _transport = transport,
       _encoder = encoder;

  final PrinterTransport _transport;
  final EscPosEncoder _encoder;

  /// The PM400 prints 104mm at 203dpi (832 dots). Font A is 12 dots wide, so
  /// 64 characters occupy 768 dots and fit with margin to spare.
  static const pm400CharactersPerLine = 64;

  /// Prints [document]'s flat lines, optionally more than once.
  ///
  /// Throws [PrintException] when the receipt cannot be printed at all.
  /// Returns a [PrintOutcome] carrying a warning when it printed but may be
  /// visually wrong. Pass [contentWidth]/[leftMargin] to centre the block.
  Future<PrintOutcome> printReceipt(
    InvoiceDocument document, {
    int copies = 1,
    int? connectedPrinterCharactersPerLine,
    bool printQrCode = true,
    int contentWidth = 0,
    int leftMargin = 0,
  }) async {
    if (!document.hasPrintableLines) {
      throw const PrintException(
        PrintFailure.unknown,
        'This receipt has no printable content. '
        'Fetch it from the /receipt endpoint rather than /invoice.',
      );
    }

    await _printLines(
      document.lines,
      copies: copies,
      contentWidth: contentWidth,
      leftMargin: leftMargin,
      qrCode: printQrCode ? document.qrCode : null,
    );

    return PrintOutcome(
      copies: copies,
      warning: _columnWidthWarning(
        document,
        connectedPrinterCharactersPerLine,
      ),
    );
  }

  /// Prints the chosen [pages] (Customer / Company copies), each repeated
  /// [copies] times, as one centred block. Used by the print-preview screen.
  Future<PrintOutcome> printPages(
    List<ReceiptPage> pages, {
    int copies = 1,
    int contentWidth = 0,
    int leftMargin = 0,
    String? qrCode,
    bool printQrCode = true,
  }) async {
    final lines = [for (final page in pages) ...page.lines];
    if (lines.isEmpty) {
      throw const PrintException(
        PrintFailure.unknown,
        'Nothing selected to print.',
      );
    }

    await _printLines(
      lines,
      copies: copies,
      contentWidth: contentWidth,
      leftMargin: leftMargin,
      qrCode: printQrCode ? qrCode : null,
    );

    return PrintOutcome(copies: copies);
  }

  Future<void> _printLines(
    List<ReceiptLine> lines, {
    required int copies,
    required int contentWidth,
    required int leftMargin,
    String? qrCode,
  }) async {
    if (!await _transport.isConnected) {
      throw const PrintException(
        PrintFailure.notConnected,
        'No printer is connected.',
      );
    }

    // Arabic and other non-Latin text cannot be rendered in ESC/POS text
    // mode: the printer does not do contextual shaping, so it would emit
    // disconnected or wrong glyphs. Refuse rather than print a receipt that
    // looks valid but is not.
    if (EscPosEncoder.containsUnsupportedGlyphs(lines)) {
      throw const PrintException(
        PrintFailure.unknown,
        'This receipt contains characters that text-mode printing cannot '
        'render correctly (for example Arabic). It needs raster printing, '
        'which is not implemented yet.',
      );
    }

    final bytes = _encoder.encode(
      lines,
      copies: copies,
      contentWidth: contentWidth,
      leftMargin: leftMargin,
    );
    await _transport.write(bytes);

    if (qrCode != null && qrCode.isNotEmpty) {
      // ZATCA QR goes after the text body, matching the web layout's order.
      await _transport.write(_encoder.encodeQrCode(qrCode));
    }
  }

  /// Detects the server/printer column-width mismatch described in
  /// [SalesApi.receipt].
  ///
  /// The server pads columns to the width stored in `printer_settings`. If
  /// the physically connected printer is narrower, lines wrap and every
  /// column shifts; if wider, the receipt just sits narrow. Neither is
  /// fixable client-side because the text arrives pre-padded, so the honest
  /// move is to say so.
  String? _columnWidthWarning(InvoiceDocument document, int? actual) {
    if (actual == null) return null;

    final serverWidth = document.defaultPrinter?.charactersPerLine ?? 42;
    if (serverWidth == actual) return null;

    return 'Receipt was formatted for $serverWidth characters per line but '
        'this printer uses $actual. Columns may not line up. Update the '
        'printer settings on the server to match.';
  }
}
