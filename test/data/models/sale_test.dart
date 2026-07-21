import 'package:dar_al_turab_pos/data/models/receipt.dart';
import 'package:dar_al_turab_pos/data/models/sale.dart';
import 'package:dar_al_turab_pos/data/models/sale_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SaleListItem', () {
    test('parses a list row', () {
      final sale = SaleListItem.fromJson({
        'id': 101,
        'reference_no': 'posr-20260718-142233',
        'date': '2026-07-18T14:22:33+04:00',
        'customer': {'id': 5, 'name': 'Walk-in', 'phone': '0501234567'},
        'item_count': 3,
        'total_qty': 5.0,
        'grand_total': 420.0,
        'paid_amount': 420.0,
        'returned_amount': 0.0,
        'ip_discount': 0.0,
        'due': 0.0,
        'sale_status': 1,
        'sale_status_label': 'Completed',
        'payment_status': 4,
        'payment_status_label': 'Paid',
      });

      expect(sale.id, 101);
      expect(sale.referenceNo, 'posr-20260718-142233');
      expect(sale.customer?.name, 'Walk-in');
      expect(sale.saleStatus, SaleStatus.completed);
      expect(sale.paymentStatus, PaymentStatus.paid);
      expect(sale.hasDue, isFalse);
    });

    test('parses numerics delivered as strings', () {
      // Laravel emits decimal columns as strings, so a naive cast would throw.
      final sale = SaleListItem.fromJson({
        'id': '7',
        'grand_total': '420.50',
        'due': '20.25',
        'total_qty': '5.5',
      });

      expect(sale.id, 7);
      expect(sale.grandTotal, 420.50);
      expect(sale.due, 20.25);
      expect(sale.totalQty, 5.5);
    });

    test('prefers the server label over the local enum', () {
      // Keeps client and web in step if the server adds a status the enum
      // does not know about yet.
      final sale = SaleListItem.fromJson({
        'id': 1,
        'sale_status': 99,
        'sale_status_label': 'Some New Status',
      });

      expect(sale.saleStatus, isNull);
      expect(sale.saleStatusText, 'Some New Status');
    });

    test('falls back to Unknown when neither code nor label is usable', () {
      final sale = SaleListItem.fromJson({'id': 1});

      expect(sale.saleStatusText, 'Unknown');
      expect(sale.paymentStatusText, 'Unknown');
    });

    test('treats sub-rounding dues as settled', () {
      // The server's own tolerance is 0.005, so a 0.001 residue is noise.
      expect(SaleListItem.fromJson({'id': 1, 'due': 0.001}).hasDue, isFalse);
      expect(SaleListItem.fromJson({'id': 1, 'due': 0.01}).hasDue, isTrue);
    });

    test('survives a payload with only an id', () {
      final sale = SaleListItem.fromJson({'id': 1});

      expect(sale.referenceNo, '-');
      expect(sale.customer, isNull);
      expect(sale.grandTotal, 0);
      expect(sale.date, isNull);
    });
  });

  group('SaleDetail', () {
    final payload = {
      'id': 101,
      'reference_no': 'posr-1',
      'serial_no': 'INV202607181422330012',
      'date': '2026-07-18T14:22:33+04:00',
      'customer': {'id': 5, 'name': 'Ahmed', 'trn_number': '100123456700003'},
      'sale_status': 1,
      'payment_status': 4,
      'items': [
        {
          'id': 1,
          'product_id': 12,
          'product_name': 'Steel Rebar 12mm',
          'variant_name': '12mm',
          'qty': 95.5,
          'no_of_pcs': 10,
          'gross_weight': 100.0,
          'waste_qty': 4.5,
          'sale_unit': 'KG',
          'net_unit_price': 4.0,
          'tax': 19.1,
          'total': 401.1,
        },
      ],
      'payments': [
        {'id': 1, 'paid_amount': 401.1, 'discount': 0},
      ],
      'totals': {
        'total_price': 401.1,
        'total_tax': 19.1,
        'grand_total': 401.1,
        'paid_amount': 401.1,
        'due': 0,
      },
    };

    test('parses the full document', () {
      final sale = SaleDetail.fromJson(payload);

      expect(sale.id, 101);
      expect(sale.serialNo, 'INV202607181422330012');
      expect(sale.customer?.trnNumber, '100123456700003');
      expect(sale.items, hasLength(1));
      expect(sale.payments, hasLength(1));
    });

    test('parses the weight-based line fields this business trades on', () {
      final item = SaleDetail.fromJson(payload).items.first;

      expect(item.noOfPcs, 10);
      expect(item.grossWeight, 100.0);
      expect(item.wasteQty, 4.5);
      expect(item.qty, 95.5); // net weight
      expect(item.saleUnit, 'KG');
      expect(item.displayName, 'Steel Rebar 12mm (12mm)');
    });

    test('derives sub total by removing tax from the tax-inclusive total', () {
      final totals = SaleDetail.fromJson(payload).totals;

      expect(totals.subTotal, closeTo(382.0, 0.001));
    });

    test('reports change as zero, matching the API contract', () {
      // The legacy payments table that held change has no rows in production
      // and invoice_payments has no such column, so the server sends 0.
      expect(SaleDetail.fromJson(payload).totals.change, 0);
    });

    test('handles a sale with no items or payments', () {
      final sale = SaleDetail.fromJson({'id': 1, 'reference_no': 'x'});

      expect(sale.items, isEmpty);
      expect(sale.payments, isEmpty);
      expect(sale.totals.grandTotal, 0);
    });
  });

  group('InvoiceDocument', () {
    test('parses invoice extras alongside the sale', () {
      final doc = InvoiceDocument.fromJson({
        'id': 101,
        'reference_no': 'posr-1',
        'totals': <String, dynamic>{},
        'company': {
          'name': 'DAR AL TURAB',
          'vat_registration_number': '100123456700003',
        },
        'currency_code': 'AED',
        'amount_in_words': 'four hundred twenty',
        'qr_code': 'BASE64TLV',
        'default_printer': {
          'printer_name': 'PM400',
          'paper_width': '110 mm',
          'characters_per_line': 64,
        },
        'lines': [
          {'text': 'DAR AL TURAB', 'align': 'center', 'bold': true},
        ],
      });

      expect(doc.company.name, 'DAR AL TURAB');
      expect(doc.amountInWords, 'four hundred twenty');
      expect(doc.hasQrCode, isTrue);
      expect(doc.defaultPrinter?.charactersPerLine, 64);
      expect(doc.hasPrintableLines, isTrue);
      expect(doc.lines.first.align, ReceiptAlign.center);
      expect(doc.lines.first.bold, isTrue);
    });

    test('reports no printable lines for the /invoice endpoint', () {
      // /invoice omits lines[]; only /receipt includes them.
      final doc = InvoiceDocument.fromJson({
        'id': 1,
        'reference_no': 'x',
        'totals': <String, dynamic>{},
      });

      expect(doc.hasPrintableLines, isFalse);
      expect(doc.hasQrCode, isFalse);
      expect(doc.currencyCode, 'AED');
    });
  });

  group('Enums', () {
    test('map known integer codes', () {
      expect(SaleStatus.fromValue(1), SaleStatus.completed);
      expect(PaymentStatus.fromValue(2), PaymentStatus.due);
      expect(PaymentMethod.fromValue(1), PaymentMethod.cash);
    });

    test('return null for unknown or missing codes', () {
      expect(SaleStatus.fromValue(99), isNull);
      expect(PaymentStatus.fromValue(null), isNull);
    });

    test('exclude points, which the server rejects', () {
      // paid_by_id 7 is POINTS_PAYMENT_UNSUPPORTED, so it must never be
      // offered as a payment option.
      expect(PaymentMethod.fromValue(7), isNull);
      expect(PaymentMethod.values.any((m) => m.value == 7), isFalse);
    });
  });
}
