import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/remote/sales_api.dart';
import '../../../data/models/catalogue.dart';
import '../../../data/models/sale.dart';
import '../../../data/models/sale_status.dart';
import '../../pos/providers/pos_providers.dart';
import '../../sales/providers/sales_providers.dart';

/// Everything the dashboard renders, fetched together so the screen has one
/// loading and error state instead of four independent spinners.
class DashboardData {
  const DashboardData({
    required this.today,
    required this.month,
    required this.outstanding,
    required this.recent,
  });

  final SaleStatistics today;
  final SaleStatistics month;

  /// Unpaid and part-paid sales this month — the figure a cashier chases.
  final SaleStatistics outstanding;

  /// Newest sales, for the "Recent activity" section.
  final List<SaleListItem> recent;
}

/// The dashboard's statistics, exposed separately so a completed sale can
/// invalidate just the totals without refetching the recent-sales list.
final dashboardStatisticsProvider =
    FutureProvider.autoDispose<DashboardData>((ref) async {
  final catalogue = ref.watch(catalogueApiProvider);
  final sales = ref.watch(salesApiProvider);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final monthStart = DateTime(now.year, now.month, 1);

  SaleFilters range(DateTime start, DateTime end, {PaymentStatus? status}) =>
      SaleFilters(startDate: start, endDate: end, paymentStatus: status);

  // /sales/statistics returns the whole-filtered-set totals directly, so each
  // of these is one cheap call rather than a page of rows we throw away.
  final (todayStats, monthStats, outstandingStats, recentPage) = await (
    catalogue.statistics(range(today, today)),
    catalogue.statistics(range(monthStart, today)),
    catalogue.statistics(range(monthStart, today, status: PaymentStatus.due)),
    sales.list(
      SaleFilters(
        startDate: today.subtract(
          const Duration(days: SaleFilters.defaultLookbackDays - 1),
        ),
        endDate: today,
        perPage: 5,
      ),
    ),
  ).wait;

  return DashboardData(
    today: todayStats,
    month: monthStats,
    outstanding: outstandingStats,
    recent: recentPage.items,
  );
});

/// Backwards-compatible alias used by the dashboard screen.
final dashboardProvider = dashboardStatisticsProvider;
