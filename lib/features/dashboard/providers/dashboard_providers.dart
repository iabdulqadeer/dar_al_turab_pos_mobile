import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/remote/sales_api.dart';
import '../../../data/models/sale.dart';
import '../../sales/providers/sales_providers.dart';

/// The dashboard's Recent Sales list. The salesman dashboard shows a quick menu
/// and recent activity only — no statistics — so this is a single cheap call
/// rather than the several the stats cards used to make.
///
/// Kept `autoDispose` and invalidated after a sale is created, edited or
/// settled so Recent Sales stays current.
final dashboardRecentProvider =
    FutureProvider.autoDispose<List<SaleListItem>>((ref) async {
  final sales = ref.watch(salesApiProvider);

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);

  final page = await sales.list(
    SaleFilters(
      startDate: today.subtract(
        const Duration(days: SaleFilters.defaultLookbackDays - 1),
      ),
      endDate: today,
      perPage: 5,
    ),
  );

  return page.items;
});
