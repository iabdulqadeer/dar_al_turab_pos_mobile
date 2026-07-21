import 'dart:typed_data';

import 'package:dar_al_turab_pos/data/models/receipt.dart';
import 'package:dar_al_turab_pos/features/printing/printer_transport.dart';
import 'package:dar_al_turab_pos/features/printing/receipt_printer.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records what would have gone to a real printer.
class FakeTransport implements PrinterTransport {
  FakeTransport({this.connected = true});

  bool connected;
  final List<Uint8List> writes = [];

  @override
  PrinterTransportKind get kind => PrinterTransportKind.bluetoothClassic;

  @override
  bool get isSupported => true;

  @override
  Future<bool> get isBluetoothOn async => true;

  @override
  Future<bool> get isConnected async => connected;

  @override
  Future<List<DiscoveredPrinter>> discover({
    Duration timeout = const Duration(seconds: 10),
  }) async => const [];

  @override
  Future<void> connect(DiscoveredPrinter printer) async {
    connected = true;
  }

  @override
  Future<void> disconnect() async {
    connected = false;
  }

  @override
  Future<void> write(Uint8List bytes) async {
    writes.add(bytes);
  }

  int get totalBytes => writes.fold(0, (sum, w) => sum + w.length);
}

void main() {
  // Building the document through fromJson avoids constructing a SaleDetail
  // by hand, and exercises the same parsing the app uses.
  InvoiceDocument build({
    List<Map<String, dynamic>> lines = const [
      {'text': 'Hello'},
    ],
    String? qrCode,
    int? serverCpl,
  }) {
    return InvoiceDocument.fromJson({
      'id': 1,
      'reference_no': 'posr-1',
      'totals': <String, dynamic>{},
      'company': {'name': 'DAR AL TURAB'},
      'lines': lines,
      'qr_code': ?qrCode,
      if (serverCpl != null)
        'default_printer': {'characters_per_line': serverCpl},
    });
  }

  group('printReceipt', () {
    test('writes encoded bytes to the transport', () async {
      final transport = FakeTransport();
      final printer = ReceiptPrinter(transport: transport);

      final outcome = await printer.printReceipt(build());

      expect(transport.writes, hasLength(1));
      expect(transport.totalBytes, greaterThan(0));
      expect(outcome.copies, 1);
      expect(outcome.hasWarning, isFalse);
    });

    test('sends more bytes when printing multiple copies', () async {
      final single = FakeTransport();
      final double_ = FakeTransport();

      await ReceiptPrinter(transport: single).printReceipt(build());
      await ReceiptPrinter(
        transport: double_,
      ).printReceipt(build(), copies: 2);

      expect(double_.totalBytes, greaterThan(single.totalBytes));
    });

    test('refuses to print when no printer is connected', () async {
      final transport = FakeTransport(connected: false);

      expect(
        () => ReceiptPrinter(transport: transport).printReceipt(build()),
        throwsA(
          isA<PrintException>().having(
            (e) => e.failure,
            'failure',
            PrintFailure.notConnected,
          ),
        ),
      );
    });

    test('refuses a document with no printable lines', () async {
      // /invoice omits lines[]; printing it would emit a blank receipt.
      final transport = FakeTransport();

      expect(
        () => ReceiptPrinter(
          transport: transport,
        ).printReceipt(build(lines: const [])),
        throwsA(isA<PrintException>()),
      );
      expect(transport.writes, isEmpty);
    });

    test('refuses Arabic rather than printing broken glyphs', () async {
      // Text mode cannot shape Arabic, so it would print disconnected or
      // reversed letters that still look like a valid receipt.
      final transport = FakeTransport();

      expect(
        () => ReceiptPrinter(transport: transport).printReceipt(
          build(
            lines: const [
              {'text': 'دار التراب'},
            ],
          ),
        ),
        throwsA(
          isA<PrintException>().having(
            (e) => e.message,
            'message',
            contains('raster'),
          ),
        ),
      );
      expect(transport.writes, isEmpty);
    });
  });

  group('QR printing', () {
    test('sends the QR as a second write when present', () async {
      final transport = FakeTransport();

      await ReceiptPrinter(
        transport: transport,
      ).printReceipt(build(qrCode: 'BASE64TLV'));

      expect(transport.writes, hasLength(2));
    });

    test('skips the QR when the caller opts out', () async {
      final transport = FakeTransport();

      await ReceiptPrinter(transport: transport).printReceipt(
        build(qrCode: 'BASE64TLV'),
        printQrCode: false,
      );

      expect(transport.writes, hasLength(1));
    });

    test('sends only the body when the sale has no QR', () async {
      final transport = FakeTransport();

      await ReceiptPrinter(transport: transport).printReceipt(build());

      expect(transport.writes, hasLength(1));
    });
  });

  group('Column width mismatch', () {
    test('warns when the printer is narrower than the server assumed', () async {
      // The server pre-pads columns, so this cannot be corrected client-side;
      // the honest outcome is a printed receipt plus a warning.
      final transport = FakeTransport();

      final outcome = await ReceiptPrinter(transport: transport).printReceipt(
        build(serverCpl: 64),
        connectedPrinterCharactersPerLine: 42,
      );

      expect(outcome.hasWarning, isTrue);
      expect(outcome.warning, contains('64'));
      expect(outcome.warning, contains('42'));
      // It still printed - the warning is advisory, not a failure.
      expect(transport.writes, hasLength(1));
    });

    test('stays silent when the widths agree', () async {
      final outcome = await ReceiptPrinter(
        transport: FakeTransport(),
      ).printReceipt(
        build(serverCpl: 64),
        connectedPrinterCharactersPerLine: 64,
      );

      expect(outcome.hasWarning, isFalse);
    });

    test('compares against the server default of 42 when unset', () async {
      // SaleController falls back to 42 when no printer_settings row exists,
      // so a PM400 at 64 must still be flagged.
      final outcome = await ReceiptPrinter(
        transport: FakeTransport(),
      ).printReceipt(
        build(),
        connectedPrinterCharactersPerLine:
            ReceiptPrinter.pm400CharactersPerLine,
      );

      expect(outcome.hasWarning, isTrue);
      expect(outcome.warning, contains('42'));
    });

    test('stays silent when the caller does not know the printer width', () async {
      final outcome = await ReceiptPrinter(
        transport: FakeTransport(),
      ).printReceipt(build(serverCpl: 64));

      expect(outcome.hasWarning, isFalse);
    });
  });

  group('PrintException remedies', () {
    test('gives a physical action for each failure mode', () {
      const cases = {
        PrintFailure.outOfPaper: 'paper roll',
        PrintFailure.coverOpen: 'cover',
        PrintFailure.bluetoothOff: 'Bluetooth',
        PrintFailure.permissionDenied: 'Settings',
      };

      cases.forEach((failure, expected) {
        expect(PrintException(failure, 'x').remedy, contains(expected));
      });
    });
  });
}
