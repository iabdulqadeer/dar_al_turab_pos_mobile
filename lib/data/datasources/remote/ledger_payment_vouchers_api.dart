import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../models/voucher.dart';

/// `GET /v1/ledger-payment-vouchers` list query.
class LedgerVoucherListQuery {
  const LedgerVoucherListQuery({
    this.personType,
    this.personId,
    this.transactionType,
    this.paymentMethod,
    this.startDate,
    this.endDate,
    this.perPage = 20,
  });

  final String? personType;
  final int? personId;
  final String? transactionType;
  final String? paymentMethod;
  final String? startDate;
  final String? endDate;
  final int perPage;

  Map<String, dynamic> toQuery({required int page}) {
    final personKey = personType == 'Supplier' ? 'supplier_id' : 'customer_id';
    return {
      if (personId != null) personKey: personId,
      if (transactionType != null) 'transaction_type': transactionType,
      if (paymentMethod != null) 'payment_method': paymentMethod,
      if (startDate != null) 'start_date': startDate,
      if (endDate != null) 'end_date': endDate,
      'per_page': perPage,
      'page': page,
    };
  }
}

/// Ledger Payment Vouchers — standalone debit/credit entries.
class LedgerPaymentVouchersApi {
  const LedgerPaymentVouchersApi(this._client);

  final ApiClient _client;

  /// `GET /v1/ledger-payment-vouchers/create-form`
  Future<VoucherCreateForm> createForm() {
    return _client.get(
      'v1/ledger-payment-vouchers/create-form',
      parse: (data) =>
          VoucherCreateForm.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `GET /v1/ledger-payment-vouchers/customer-search?q=` /
  /// `.../supplier-search?q=`
  Future<List<VoucherPerson>> searchPeople(String personType, String query) {
    final path = personType == 'Supplier'
        ? 'v1/ledger-payment-vouchers/supplier-search'
        : 'v1/ledger-payment-vouchers/customer-search';
    return _client.get(
      path,
      query: {'q': query},
      parse: (data) => (data as List? ?? const [])
          .whereType<Map>()
          .map((e) => VoucherPerson.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  /// `GET /v1/ledger-payment-vouchers`
  Future<Paginated<LedgerPaymentVoucher>> list(
    LedgerVoucherListQuery query, {
    int page = 1,
  }) {
    return _client.getList<LedgerPaymentVoucher>(
      'v1/ledger-payment-vouchers',
      query: query.toQuery(page: page),
      parseItem: LedgerPaymentVoucher.fromJson,
    );
  }

  /// `GET /v1/ledger-payment-vouchers/{id}`
  Future<LedgerPaymentVoucher> show(int id) {
    return _client.get(
      'v1/ledger-payment-vouchers/$id',
      parse: (data) =>
          LedgerPaymentVoucher.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `POST /v1/ledger-payment-vouchers`
  Future<LedgerPaymentVoucher> create(Map<String, dynamic> body) {
    return _client.post(
      'v1/ledger-payment-vouchers',
      body: body,
      parse: (data) =>
          LedgerPaymentVoucher.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `PUT /v1/ledger-payment-vouchers/{id}` — admin only (server enforces).
  Future<LedgerPaymentVoucher> update(int id, Map<String, dynamic> body) {
    return _client.put(
      'v1/ledger-payment-vouchers/$id',
      body: body,
      parse: (data) =>
          LedgerPaymentVoucher.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `DELETE /v1/ledger-payment-vouchers/{id}` — admin only (server enforces).
  Future<void> destroy(int id) =>
      _client.delete('v1/ledger-payment-vouchers/$id', parse: (_) {});
}
