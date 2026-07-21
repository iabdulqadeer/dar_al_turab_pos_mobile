import 'package:dar_al_turab_pos/data/models/catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SaleStatistics.collectionRate', () {
    test('is zero when nothing was billed, not NaN', () {
      // A division guard matters here: the dashboard feeds this straight into
      // a LinearProgressIndicator, which throws on NaN.
      expect(SaleStatistics.empty.collectionRate, 0);
    });

    test('reports a full collection as 1', () {
      const stats = SaleStatistics(
        totalCount: 3,
        totalGrand: 1000,
        totalPaid: 1000,
        totalDue: 0,
      );

      expect(stats.collectionRate, 1);
    });

    test('reports a partial collection proportionally', () {
      const stats = SaleStatistics(
        totalCount: 2,
        totalGrand: 400,
        totalPaid: 100,
        totalDue: 300,
      );

      expect(stats.collectionRate, 0.25);
    });

    test('clamps overpayment to 1 so the progress bar stays valid', () {
      // The server's POS path can record paid > grand_total; an unclamped
      // ratio would exceed the indicator's 0..1 contract.
      const stats = SaleStatistics(
        totalCount: 1,
        totalGrand: 100,
        totalPaid: 150,
        totalDue: 0,
      );

      expect(stats.collectionRate, 1);
    });

    test('never returns a negative rate', () {
      const stats = SaleStatistics(
        totalCount: 1,
        totalGrand: 100,
        totalPaid: -50,
        totalDue: 150,
      );

      expect(stats.collectionRate, greaterThanOrEqualTo(0));
    });
  });

  group('SaleStatistics.fromJson', () {
    test('parses the statistics payload', () {
      final stats = SaleStatistics.fromJson({
        'total_count': 137,
        'total_grand': 48210.5,
        'total_paid': 46100.0,
        'total_due': 2110.5,
      });

      expect(stats.totalCount, 137);
      expect(stats.totalGrand, 48210.5);
      expect(stats.totalPaid, 46100.0);
      expect(stats.totalDue, 2110.5);
    });

    test('defaults missing fields to zero rather than throwing', () {
      final stats = SaleStatistics.fromJson({});

      expect(stats.totalCount, 0);
      expect(stats.totalGrand, 0);
      expect(stats.collectionRate, 0);
    });
  });
}
