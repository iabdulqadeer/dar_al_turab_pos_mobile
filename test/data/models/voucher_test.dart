import 'package:dar_al_turab_pos/data/models/voucher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoucherInvoice.fromJson', () {
    test('parses the created_by object and date (aug-13 additions)', () {
      // The exact invoice-payment shape from the aug-13 doc.
      final ip = VoucherInvoice.fromJson({
        'invoice_payment_id': 3626,
        'invoice_id': 140,
        'invoice_type': 'purchase',
        'reference_number': '67059',
        'paid_amount': 14335.42,
        'discount_amount': 0,
        'note': null,
        'created_by': {'id': 1, 'name': 'admin'},
        'date': '2026-08-13T12:58:00+05:00',
      });

      expect(ip.invoicePaymentId, 3626);
      expect(ip.referenceNumber, '67059');
      expect(ip.paidAmount, 14335.42);
      expect(ip.createdBy?.name, 'admin');
      expect(ip.date, '2026-08-13T12:58:00+05:00');
    });

    test('tolerates a missing created_by/date', () {
      final ip = VoucherInvoice.fromJson({
        'invoice_payment_id': 1,
        'invoice_id': 2,
        'reference_number': 'SV-1',
        'paid_amount': 10,
        'discount_amount': 0,
      });

      expect(ip.createdBy, isNull);
      expect(ip.date, isNull);
    });
  });

  group('Voucher.fromJson', () {
    test('reads embedded person, biller and invoice payments', () {
      final v = Voucher.fromJson({
        'id': 1,
        'voucher_no': 'CRV - 123',
        'voucher_type': 'CRV',
        'date': '2026-08-08',
        'warehouse': {'id': 1, 'name': 'Main Warehouse'},
        'biller': {'id': 1, 'name': 'HAMZA ISHFAQ'},
        'person': {'type': 'Customer', 'id': 1, 'name': 'Al Madina Grocery'},
        'payment_method': 'cash',
        'total_amount': 200,
        'total_discount': 0,
        'invoices': [
          {
            'invoice_payment_id': 1,
            'invoice_id': 1,
            'reference_number': 'SV-001424',
            'paid_amount': 200,
            'discount_amount': 0,
            'created_by': {'id': 2, 'name': 'cashier'},
            'date': '2026-08-08T18:55:54+05:00',
          },
        ],
      });

      expect(v.person?.type, 'Customer');
      expect(v.person?.name, 'Al Madina Grocery');
      expect(v.biller?.name, 'HAMZA ISHFAQ');
      expect(v.invoices.single.createdBy?.name, 'cashier');
    });
  });
}
