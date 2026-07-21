import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../models/receipt.dart';
import '../../models/sale.dart';
import '../../models/sale_status.dart';

/// Sort columns accepted by `GET /v1/sales`.
enum SaleSort {
  date('date', 'Date'),
  grandTotal('grand_total', 'Amount'),
  referenceNo('reference_no', 'Reference');

  const SaleSort(this.value, this.label);

  final String value;
  final String label;
}

/// Query parameters for the sales list.
///
/// `start_date` and `end_date` are **required** by the server
/// (`ListSalesRequest`), which defaults both to today when omitted. We always
/// send them explicitly so the visible range is never a surprise.
class SaleFilters {
  const SaleFilters({
    required this.startDate,
    required this.endDate,
    this.warehouseId,
    this.customerId,
    this.saleStatus,
    this.paymentStatus,
    this.search,
    this.sort = SaleSort.date,
    this.descending = true,
    this.perPage = 20,
    this.minTotal,
    this.maxTotal,
  });

  /// Number of days the default view looks back.
  ///
  /// The server defaults both dates to *today*, which shows an empty list
  /// whenever the shop has not sold yet that day. A 30-day window was chosen
  /// after checking live data: trading is not daily here (at the time of
  /// writing the most recent sale was 17 days old), so a 7-day default opened
  /// on an empty screen that reads as a broken app.
  static const defaultLookbackDays = 30;

  factory SaleFilters.recent() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return SaleFilters(
      startDate: today.subtract(
        const Duration(days: defaultLookbackDays - 1),
      ),
      endDate: today,
    );
  }

  final DateTime startDate;
  final DateTime endDate;
  final int? warehouseId;
  final int? customerId;
  final SaleStatus? saleStatus;
  final PaymentStatus? paymentStatus;
  final String? search;
  final SaleSort sort;
  final bool descending;
  final int perPage;

  /// Inclusive `grand_total` range. The server requires `max_total >= min_total`
  /// when both are supplied.
  final double? minTotal;
  final double? maxTotal;

  SaleFilters copyWith({
    DateTime? startDate,
    DateTime? endDate,
    int? warehouseId,
    int? customerId,
    SaleStatus? saleStatus,
    PaymentStatus? paymentStatus,
    String? search,
    SaleSort? sort,
    bool? descending,
    int? perPage,
    double? minTotal,
    double? maxTotal,
    bool clearSaleStatus = false,
    bool clearPaymentStatus = false,
    bool clearSearch = false,
    bool clearCustomer = false,
    bool clearAmountRange = false,
  }) {
    return SaleFilters(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      warehouseId: warehouseId ?? this.warehouseId,
      customerId: clearCustomer ? null : (customerId ?? this.customerId),
      saleStatus: clearSaleStatus ? null : (saleStatus ?? this.saleStatus),
      paymentStatus: clearPaymentStatus
          ? null
          : (paymentStatus ?? this.paymentStatus),
      search: clearSearch ? null : (search ?? this.search),
      sort: sort ?? this.sort,
      descending: descending ?? this.descending,
      perPage: perPage ?? this.perPage,
      minTotal: clearAmountRange ? null : (minTotal ?? this.minTotal),
      maxTotal: clearAmountRange ? null : (maxTotal ?? this.maxTotal),
    );
  }

  bool get hasAmountRange => minTotal != null || maxTotal != null;

  /// True when anything beyond the date range is narrowing the result set.
  bool get hasActiveFilters =>
      saleStatus != null ||
      paymentStatus != null ||
      customerId != null ||
      hasAmountRange ||
      (search != null && search!.trim().isNotEmpty);

  int get activeFilterCount => [
    saleStatus != null,
    paymentStatus != null,
    customerId != null,
    hasAmountRange,
    search != null && search!.trim().isNotEmpty,
  ].where((active) => active).length;

  Map<String, dynamic> toQuery({required int page}) {
    final trimmedSearch = search?.trim();

    return {
      'start_date': formatDate(startDate),
      'end_date': formatDate(endDate),
      'warehouse_id': ?warehouseId,
      'customer_id': ?customerId,
      if (saleStatus != null) 'sale_status': saleStatus!.value,
      if (paymentStatus != null) 'payment_status': paymentStatus!.value,
      if (trimmedSearch != null && trimmedSearch.isNotEmpty)
        'search': trimmedSearch,
      // Inclusive grand_total range. Sent only when set — the server rejects
      // a max below a min.
      'min_total': ?minTotal,
      'max_total': ?maxTotal,
      'sort': sort.value,
      'direction': descending ? 'desc' : 'asc',
      'per_page': perPage,
      'page': page,
    };
  }

  /// The server validates `date_format:Y-m-d` strictly.
  static String formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class SalesApi {
  const SalesApi(this._client);

  final ApiClient _client;

  /// `GET /v1/sales`
  Future<Paginated<SaleListItem>> list(
    SaleFilters filters, {
    int page = 1,
  }) {
    return _client.getList<SaleListItem>(
      'v1/sales',
      query: filters.toQuery(page: page),
      parseItem: SaleListItem.fromJson,
    );
  }

  /// `GET /v1/sales/{id}`
  Future<SaleDetail> show(int id) {
    return _client.get(
      'v1/sales/$id',
      parse: (data) =>
          SaleDetail.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `GET /v1/sales/{id}/invoice`
  Future<InvoiceDocument> invoice(int id) {
    return _client.get(
      'v1/sales/$id/invoice',
      parse: (data) =>
          InvoiceDocument.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `GET /v1/sales/{id}/receipt`
  ///
  /// [charactersPerLine] is the *connected printer's* real width.
  ///
  /// Caveat: the server currently ignores this parameter. It pads columns
  /// using `default_printer.characters_per_line` from the `printer_settings`
  /// row alone (`SaleController::receipt`, falling back to 42). So when the
  /// paired printer's width differs from what the DB holds, columns will
  /// misalign and no client-side fix is possible — the receipt text arrives
  /// pre-padded. [ReceiptPrinter] detects that mismatch and surfaces it
  /// rather than printing a silently broken receipt.
  ///
  /// The parameter is sent anyway so it starts working the moment the server
  /// honours it (a one-line change at SaleController.php:176).
  Future<InvoiceDocument> receipt(int id, {required int charactersPerLine}) {
    return _client.get(
      'v1/sales/$id/receipt',
      query: {'characters_per_line': charactersPerLine},
      parse: (data) =>
          InvoiceDocument.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `POST /v1/sales` — create a sale. Returns the full detail shape.
  ///
  /// Note the API is explicitly NOT idempotent (docs §2.6): a retry after a
  /// network timeout creates a second sale. Callers must not blind-retry —
  /// search by `reference_no` first, or hold the id from the first success.
  Future<SaleDetail> create(Map<String, dynamic> body) {
    return _client.post(
      'v1/sales',
      body: body,
      parse: (data) =>
          SaleDetail.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `PUT /v1/sales/{id}`
  Future<SaleDetail> update(int id, Map<String, dynamic> body) {
    return _client.put(
      'v1/sales/$id',
      body: body,
      parse: (data) =>
          SaleDetail.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `DELETE /v1/sales/{id}`
  Future<void> destroy(int id) =>
      _client.delete('v1/sales/$id', parse: (_) {});
}
