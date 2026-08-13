import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../models/voucher.dart';

/// `GET /v1/vouchers` list query.
class VoucherListQuery {
  const VoucherListQuery({
    required this.type,
    this.personId,
    this.bankId,
    this.paymentMethod,
    this.startDate,
    this.endDate,
    this.perPage = 20,
  });

  final VoucherType type;
  final int? personId;
  final int? bankId;
  final String? paymentMethod;
  final String? startDate;
  final String? endDate;
  final int perPage;

  Map<String, dynamic> toQuery({required int page}) {
    // CRV filters by customer_id, CPV by supplier_id — same underlying param
    // name pair the create body uses.
    final personKey =
        type == VoucherType.crv ? 'customer_id' : 'supplier_id';
    return {
      'type': type.slug,
      if (personId != null) personKey: personId,
      if (bankId != null) 'bank_id': bankId,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      'per_page': perPage,
      'page': page,
    };
  }
}

/// Cash Received / Cash Payment vouchers.
class VouchersApi {
  const VouchersApi(this._client);

  final ApiClient _client;

  /// `GET /v1/vouchers/create-form?type=`
  Future<VoucherCreateForm> createForm(VoucherType type) {
    return _client.get(
      'v1/vouchers/create-form',
      query: {'type': type.slug},
      parse: (data) =>
          VoucherCreateForm.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `GET /v1/vouchers/customer-search?q=` (CRV) /
  /// `GET /v1/vouchers/supplier-search?q=` (CPV).
  Future<List<VoucherPerson>> searchPeople(VoucherType type, String query) {
    final path = type == VoucherType.crv
        ? 'v1/vouchers/customer-search'
        : 'v1/vouchers/supplier-search';
    return _client.get(
      path,
      query: {'q': query},
      parse: (data) => (data as List? ?? const [])
          .whereType<Map>()
          .map((e) => VoucherPerson.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  /// `GET /v1/vouchers/unpaid-invoices?person_type=&person_id=`
  Future<List<UnpaidInvoice>> unpaidInvoices({
    required String personType,
    required int personId,
  }) {
    return _client.get(
      'v1/vouchers/unpaid-invoices',
      query: {'person_type': personType, 'person_id': personId},
      parse: (data) => (data as List? ?? const [])
          .whereType<Map>()
          .map((e) => UnpaidInvoice.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  /// `GET /v1/vouchers?type=`
  Future<Paginated<Voucher>> list(VoucherListQuery query, {int page = 1}) {
    return _client.getList<Voucher>(
      'v1/vouchers',
      query: query.toQuery(page: page),
      parseItem: Voucher.fromJson,
    );
  }

  /// `GET /v1/vouchers/{id}`
  Future<Voucher> show(int id) {
    return _client.get(
      'v1/vouchers/$id',
      parse: (data) => Voucher.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `POST /v1/vouchers`
  Future<Voucher> create(Map<String, dynamic> body) {
    return _client.post(
      'v1/vouchers',
      body: body,
      parse: (data) => Voucher.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `PUT /v1/vouchers/{id}`
  Future<Voucher> update(int id, Map<String, dynamic> body) {
    return _client.put(
      'v1/vouchers/$id',
      body: body,
      parse: (data) => Voucher.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `DELETE /v1/vouchers/{id}`
  Future<void> destroy(int id) =>
      _client.delete('v1/vouchers/$id', parse: (_) {});

  /// `DELETE /v1/vouchers/{id}/invoice-payments/{invoicePaymentId}` — removes a
  /// single invoice allocation and returns the updated voucher (recomputed
  /// totals), without deleting the voucher itself.
  Future<Voucher> deleteInvoicePayment(int voucherId, int invoicePaymentId) {
    return _client.delete(
      'v1/vouchers/$voucherId/invoice-payments/$invoicePaymentId',
      parse: (data) => Voucher.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }
}
