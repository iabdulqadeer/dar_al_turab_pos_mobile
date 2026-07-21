import 'package:dar_al_turab_pos/data/datasources/remote/sales_api.dart';
import 'package:dar_al_turab_pos/data/models/sale_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = SaleFilters(
    startDate: DateTime(2026, 7, 1),
    endDate: DateTime(2026, 7, 20),
  );

  group('Date formatting', () {
    test('pads month and day to the required Y-m-d format', () {
      // The server validates date_format:Y-m-d strictly, so 2026-7-5 is
      // rejected outright.
      expect(SaleFilters.formatDate(DateTime(2026, 7, 5)), '2026-07-05');
      expect(SaleFilters.formatDate(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });

  group('Query building', () {
    test('always sends the required date range', () {
      final query = base.toQuery(page: 1);

      expect(query['start_date'], '2026-07-01');
      expect(query['end_date'], '2026-07-20');
    });

    test('omits optional filters when unset', () {
      final query = base.toQuery(page: 1);

      expect(query.containsKey('sale_status'), isFalse);
      expect(query.containsKey('payment_status'), isFalse);
      expect(query.containsKey('customer_id'), isFalse);
      expect(query.containsKey('search'), isFalse);
    });

    test('sends status filters as their integer codes', () {
      final query = base
          .copyWith(
            saleStatus: SaleStatus.completed,
            paymentStatus: PaymentStatus.due,
          )
          .toQuery(page: 1);

      expect(query['sale_status'], 1);
      expect(query['payment_status'], 2);
    });

    test('trims search text and drops it when blank', () {
      expect(
        base.copyWith(search: '  posr-2026  ').toQuery(page: 1)['search'],
        'posr-2026',
      );
      expect(
        base.copyWith(search: '   ').toQuery(page: 1).containsKey('search'),
        isFalse,
      );
    });

    test('maps sort direction to the API vocabulary', () {
      expect(base.toQuery(page: 1)['direction'], 'desc');
      expect(base.copyWith(descending: false).toQuery(page: 1)['direction'], 'asc');
      expect(
        base.copyWith(sort: SaleSort.grandTotal).toQuery(page: 1)['sort'],
        'grand_total',
      );
    });

    test('passes pagination through', () {
      final query = base.copyWith(perPage: 50).toQuery(page: 3);

      expect(query['per_page'], 50);
      expect(query['page'], 3);
    });
  });

  group('copyWith clearing', () {
    test('clear flags remove a filter rather than keeping the old value', () {
      // copyWith(x: null) cannot distinguish "unset" from "leave alone", so
      // explicit clear flags exist; this guards that they actually work.
      final filtered = base.copyWith(
        saleStatus: SaleStatus.draft,
        paymentStatus: PaymentStatus.paid,
        search: 'abc',
        customerId: 5,
      );

      expect(filtered.copyWith(clearSaleStatus: true).saleStatus, isNull);
      expect(filtered.copyWith(clearPaymentStatus: true).paymentStatus, isNull);
      expect(filtered.copyWith(clearSearch: true).search, isNull);
      expect(filtered.copyWith(clearCustomer: true).customerId, isNull);
    });

    test('clearing one filter leaves the others intact', () {
      final filtered = base.copyWith(
        saleStatus: SaleStatus.draft,
        search: 'abc',
      );
      final cleared = filtered.copyWith(clearSearch: true);

      expect(cleared.search, isNull);
      expect(cleared.saleStatus, SaleStatus.draft);
    });
  });

  group('Active filter reporting', () {
    test('a plain date range is not an active filter', () {
      expect(base.hasActiveFilters, isFalse);
      expect(base.activeFilterCount, 0);
    });

    test('counts each narrowing filter once', () {
      final filtered = base.copyWith(
        saleStatus: SaleStatus.completed,
        paymentStatus: PaymentStatus.due,
        search: 'x',
      );

      expect(filtered.hasActiveFilters, isTrue);
      expect(filtered.activeFilterCount, 3);
    });

    test('whitespace-only search does not count as active', () {
      expect(base.copyWith(search: '   ').hasActiveFilters, isFalse);
    });
  });

  group('SaleFilters.recent', () {
    test('covers the default lookback window ending today', () {
      final filters = SaleFilters.recent();
      final days = filters.endDate.difference(filters.startDate).inDays;

      expect(days, SaleFilters.defaultLookbackDays - 1);
    });

    test('ends today and is not an active filter', () {
      final now = DateTime.now();
      final filters = SaleFilters.recent();

      expect(filters.endDate.year, now.year);
      expect(filters.endDate.month, now.month);
      expect(filters.endDate.day, now.day);
      expect(filters.hasActiveFilters, isFalse);
    });

    test('looks back far enough to survive an inactive trading week', () {
      // Trading is not daily for this business; a short window opens on an
      // empty list that reads as a broken app.
      expect(SaleFilters.defaultLookbackDays, greaterThanOrEqualTo(14));
    });
  });
}
