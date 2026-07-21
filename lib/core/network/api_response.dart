/// Pagination metadata from the v1 list endpoints.
///
/// Note: the API does NOT return a Laravel paginator object. `data` is a plain
/// array and pagination lives in `meta` (see `SaleController::index`, which
/// calls `->resolve()` to strip the framework's `data` wrapper). So there is
/// no `links` object to rely on — page numbers are the only cursor.
class PageMeta {
  const PageMeta({
    required this.currentPage,
    required this.perPage,
    required this.total,
    required this.lastPage,
    this.summary,
  });

  factory PageMeta.fromJson(Map<String, dynamic> json) {
    return PageMeta(
      currentPage: (json['current_page'] as num?)?.toInt() ?? 1,
      perPage: (json['per_page'] as num?)?.toInt() ?? 20,
      total: (json['total'] as num?)?.toInt() ?? 0,
      lastPage: (json['last_page'] as num?)?.toInt() ?? 1,
      summary: json['summary'] is Map
          ? Map<String, dynamic>.from(json['summary'] as Map)
          : null,
    );
  }

  final int currentPage;
  final int perPage;
  final int total;
  final int lastPage;

  /// Totals across the whole filtered set, not just this page
  /// (`SaleQueryService::summaryTotals`): total_grand, total_paid, total_due.
  final Map<String, dynamic>? summary;

  bool get hasMore => currentPage < lastPage;
  int get nextPage => currentPage + 1;

  double? summaryValue(String key) => (summary?[key] as num?)?.toDouble();
}

/// A list payload plus its pagination metadata.
class Paginated<T> {
  const Paginated({required this.items, required this.meta});

  final List<T> items;
  final PageMeta meta;

  bool get hasMore => meta.hasMore;
}
