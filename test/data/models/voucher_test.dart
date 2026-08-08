import 'package:dar_al_turab_pos/data/models/voucher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('VoucherType', () {
    test('maps to the API slug, voucher_type value and locked person type', () {
      expect(VoucherType.crv.slug, 'cash-received-voucher');
      expect(VoucherType.crv.value, 'CRV');
      expect(VoucherType.crv.personType, 'Customer');
      expect(VoucherType.cpv.slug, 'cash-payment-voucher');
      expect(VoucherType.cpv.value, 'CPV');
      expect(VoucherType.cpv.personType, 'Supplier');
    });
  });

  group('UnpaidInvoice', () {
    UnpaidInvoice invoice() => UnpaidInvoice.fromJson({
          'invoice_id': 1,
          'reference_no': 'SV-001424',
          'date': '2026-07-20',
          'due': 250,
          'pay_amount': 250,
          'discount_amount': 0,
          'note': null,
        });

    test('pay amount defaults to the full due, discount to 0', () {
      final inv = invoice();
      expect(inv.due, 250);
      expect(inv.payAmount, 250);
      expect(inv.discountAmount, 0);
    });

    test('editing discount recalculates pay = due − discount', () {
      final inv = invoice()..applyDiscount(10);
      expect(inv.discountAmount, 10);
      expect(inv.payAmount, 240);
    });

    test('pay never goes below zero on an oversized discount', () {
      final inv = invoice()..applyDiscount(9999);
      expect(inv.payAmount, 0);
    });

    test('toJson sends the allocation shape the API expects', () {
      final inv = invoice()
        ..applyDiscount(10)
        ..note = ' partial ';
      expect(inv.toJson(), {
        'invoice_id': 1,
        'pay_amount': 240,
        'discount_amount': 10,
        'note': 'partial',
      });
    });
  });

  group('VoucherCreateForm', () {
    test('lockedBiller resolves the default biller id, or null', () {
      final form = VoucherCreateForm.fromJson({
        'billers': [
          {'id': 1, 'name': 'HAMZA ISHFAQ'},
          {'id': 5, 'name': 'Sara Khan'},
        ],
        'default_biller_id': 5,
        'biller_locked': true,
      });
      expect(form.billerLocked, isTrue);
      expect(form.lockedBiller?.name, 'Sara Khan');

      final noLock = VoucherCreateForm.fromJson({'billers': []});
      expect(noLock.lockedBiller, isNull);
    });

    test('captures the payment-method value verbatim (deposit vs bank)', () {
      final crv = VoucherCreateForm.fromJson({
        'payment_methods': [
          {'value': 'cash', 'name': 'Cash'},
          {'value': 'deposit', 'name': 'Bank'},
        ],
      });
      expect(crv.paymentMethods.map((m) => m.value), ['cash', 'deposit']);
    });
  });

  group('Voucher.fromJson', () {
    test('parses a CPV with a null biller and an allocated invoice', () {
      final v = Voucher.fromJson({
        'id': 2,
        'voucher_no': 'CPV - 1786197354-c71e',
        'voucher_type': 'CPV',
        'date': '2026-08-08',
        'biller': null,
        'person': {'type': 'Supplier', 'id': 1, 'name': 'Gulf Meat Supplies'},
        'payment_method': 'deposit',
        'bank': {'id': 1, 'name': 'Emirates NBD'},
        'total_amount': 500,
        'total_discount': 0,
        'created_by': 2,
        'invoices': [
          {
            'invoice_payment_id': 2,
            'invoice_id': 1,
            'invoice_type': 'purchase',
            'reference_number': 'PU-000512',
            'paid_amount': 500,
            'discount_amount': 0,
            'note': null,
          }
        ],
      });
      expect(v.biller, isNull);
      expect(v.person?.name, 'Gulf Meat Supplies');
      expect(v.bank?.name, 'Emirates NBD');
      expect(v.invoices.single.referenceNumber, 'PU-000512');
      expect(v.createdBy, 2);
    });
  });
}
