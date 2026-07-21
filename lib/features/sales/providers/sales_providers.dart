import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/network/api_response.dart';
import '../../../data/datasources/remote/sales_api.dart';
import '../../../data/models/receipt.dart';
import '../../../data/models/sale.dart';
import '../../auth/providers/auth_providers.dart';

final salesApiProvider = Provider<SalesApi>((ref) {
  return SalesApi(ref.watch(apiClientProvider));
});

/// Current list filters. Changing this re-runs [salesListProvider].
final saleFiltersProvider = NotifierProvider<SaleFiltersController, SaleFilters>(
  SaleFiltersController.new,
);

class SaleFiltersController extends Notifier<SaleFilters> {
  @override
  SaleFilters build() => SaleFilters.recent();

  void update(SaleFilters filters) => state = filters;

  void reset() => state = SaleFilters.recent();

  void setSearch(String? search) => state = search == null || search.isEmpty
      ? state.copyWith(clearSearch: true)
      : state.copyWith(search: search);

  void setDateRange(DateTime start, DateTime end) =>
      state = state.copyWith(startDate: start, endDate: end);
}

/// Paginated sales list state.
class SalesListState {
  const SalesListState({
    this.items = const [],
    this.meta,
    this.isLoading = false,
    this.isLoadingMore = false,
    this.error,
  });

  final List<SaleListItem> items;
  final PageMeta? meta;
  final bool isLoading;
  final bool isLoadingMore;
  final ApiException? error;

  bool get hasMore => meta?.hasMore ?? false;
  bool get isEmpty => items.isEmpty && !isLoading && error == null;

  /// Totals across the whole filtered set, not just loaded pages — the server
  /// computes these in `SaleQueryService::summaryTotals`.
  double get summaryGrandTotal => meta?.summaryValue('total_grand') ?? 0;
  double get summaryPaid => meta?.summaryValue('total_paid') ?? 0;
  double get summaryDue => meta?.summaryValue('total_due') ?? 0;

  SalesListState copyWith({
    List<SaleListItem>? items,
    PageMeta? meta,
    bool? isLoading,
    bool? isLoadingMore,
    ApiException? error,
    bool clearError = false,
  }) {
    return SalesListState(
      items: items ?? this.items,
      meta: meta ?? this.meta,
      isLoading: isLoading ?? this.isLoading,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

class SalesListController extends Notifier<SalesListState> {
  @override
  SalesListState build() {
    // Re-fetch from page 1 whenever filters change.
    ref.listen(saleFiltersProvider, (previous, next) {
      if (previous != next) refresh();
    });

    Future.microtask(refresh);
    return const SalesListState(isLoading: true);
  }

  SalesApi get _api => ref.read(salesApiProvider);

  Future<void> refresh() async {
    state = state.copyWith(isLoading: true, clearError: true);

    try {
      final page = await _api.list(ref.read(saleFiltersProvider));
      state = SalesListState(items: page.items, meta: page.meta);
    } on ApiException catch (e) {
      state = SalesListState(error: e);
    }
  }

  Future<void> loadMore() async {
    final meta = state.meta;
    if (meta == null || !meta.hasMore) return;
    if (state.isLoading || state.isLoadingMore) return;

    state = state.copyWith(isLoadingMore: true);

    try {
      final page = await _api.list(
        ref.read(saleFiltersProvider),
        page: meta.nextPage,
      );
      state = state.copyWith(
        items: [...state.items, ...page.items],
        meta: page.meta,
        isLoadingMore: false,
      );
    } on ApiException catch (e) {
      // Keep the pages already loaded; only surface the failure.
      state = state.copyWith(isLoadingMore: false, error: e);
    }
  }
}

final salesListProvider =
    NotifierProvider<SalesListController, SalesListState>(
      SalesListController.new,
    );

/// A single sale's full detail.
final saleDetailProvider = FutureProvider.family<SaleDetail, int>((
  ref,
  id,
) async {
  return ref.watch(salesApiProvider).show(id);
});

/// A sale's printable receipt, formatted server-side for the PM400's width.
final saleReceiptProvider = FutureProvider.family<InvoiceDocument, int>((
  ref,
  id,
) async {
  return ref
      .watch(salesApiProvider)
      .receipt(id, charactersPerLine: 64);
});
