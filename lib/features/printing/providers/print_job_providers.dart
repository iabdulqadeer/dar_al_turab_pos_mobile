import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sales/providers/sales_providers.dart';
import '../printer_transport.dart';
import '../receipt_printer.dart';
import 'printer_providers.dart';

/// Prints a saved sale's receipt on the connected printer.
///
/// The single source of truth for "print this sale" — used by the sale-detail
/// print button, the POS "Save & Print" action, and the sales-list row menu, so
/// they can't drift. Throws [PrintException] when it can't print (unsupported
/// platform, no printer paired, connection/receipt failure); callers surface
/// `e.message`/`e.remedy`.
final printSaleReceiptProvider =
    Provider<Future<PrintOutcome> Function(int saleId, {int copies})>((ref) {
  return (int saleId, {int copies = 1}) async {
    final unsupported = ref.read(printingUnsupportedReasonProvider);
    if (unsupported != null) {
      throw PrintException(PrintFailure.unknown, unsupported);
    }

    final printerState = ref.read(printerControllerProvider);
    if (!printerState.hasPrinter) {
      throw const PrintException(
        PrintFailure.notConnected,
        'No printer paired. Set one up in Printer settings first.',
      );
    }

    // Reconnect first: Bluetooth links drop when the phone sleeps, and a stale
    // "connected" flag would otherwise fail mid-print.
    await ref.read(printerControllerProvider.notifier).reconnect();

    final saved = printerState.saved!;
    final document = await ref
        .read(salesApiProvider)
        .receipt(saleId, charactersPerLine: saved.contentWidth);

    return ref.read(receiptPrinterProvider).printReceipt(
          document,
          copies: copies,
          contentWidth: saved.contentWidth,
          leftMargin: saved.leftMargin,
        );
  };
});