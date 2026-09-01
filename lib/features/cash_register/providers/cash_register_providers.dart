import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/remote/cash_register_api.dart';
import '../../../data/models/cash_register.dart';
import '../../auth/providers/auth_providers.dart';

final cashRegisterApiProvider = Provider<CashRegisterApi>((ref) {
  return CashRegisterApi(ref.watch(apiClientProvider));
});

/// The selected date range for the register. Defaults to today.
class CashRegisterFilters {
  const CashRegisterFilters({required this.startDate, required this.endDate});

  factory CashRegisterFilters.today() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return CashRegisterFilters(startDate: today, endDate: today);
  }

  final DateTime startDate;
  final DateTime endDate;

  CashRegisterFilters copyWith({DateTime? startDate, DateTime? endDate}) =>
      CashRegisterFilters(
        startDate: startDate ?? this.startDate,
        endDate: endDate ?? this.endDate,
      );

  static String format(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }
}

class CashRegisterFiltersController extends Notifier<CashRegisterFilters> {
  @override
  CashRegisterFilters build() => CashRegisterFilters.today();

  void setRange(DateTime start, DateTime end) {
    state = CashRegisterFilters(startDate: start, endDate: end);
  }
}

final cashRegisterFiltersProvider =
    NotifierProvider<CashRegisterFiltersController, CashRegisterFilters>(
      CashRegisterFiltersController.new,
    );

/// The report for the current date range. Scope (staff-own vs admin-full) is
/// enforced server-side, so no client filter is sent beyond the dates.
final cashRegisterReportProvider =
    FutureProvider.autoDispose<CashRegisterReport>((ref) async {
  final filters = ref.watch(cashRegisterFiltersProvider);
  return ref.watch(cashRegisterApiProvider).daily(
        startDate: CashRegisterFilters.format(filters.startDate),
        endDate: CashRegisterFilters.format(filters.endDate),
      );
});
