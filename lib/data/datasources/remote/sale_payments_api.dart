import '../../../core/network/api_client.dart';
import '../../models/sale.dart';

/// The payments sub-resource on a sale.
///
/// This is how a payment is added to an *existing* invoice. `PUT /sales/{id}`
/// deliberately does not accept a `payment` block — settling a due invoice
/// goes through here so the `invoice_payments` ledger stays the single source
/// of truth for `paid_amount`.
class SalePaymentsApi {
  const SalePaymentsApi(this._client);

  final ApiClient _client;

  /// `GET /v1/sales/{id}/payments`
  Future<List<SalePayment>> list(int saleId) {
    return _client.get(
      'v1/sales/$saleId/payments',
      parse: (data) => (data as List? ?? const [])
          .whereType<Map>()
          .map((e) => SalePayment.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }

  /// `POST /v1/sales/{id}/payments`
  ///
  /// [paidById] must be an enabled method from `/sales/create-form`; 7
  /// (Points) is rejected server-side with POINTS_PAYMENT_UNSUPPORTED.
  Future<SalePayment> add(
    int saleId, {
    required int paidById,
    required double amount,
    String? chequeNo,
    DateTime? chequeDate,
    String? note,
    int? bankId,
  }) {
    return _client.post(
      'v1/sales/$saleId/payments',
      body: _body(
        paidById: paidById,
        amount: amount,
        chequeNo: chequeNo,
        chequeDate: chequeDate,
        note: note,
        bankId: bankId,
      ),
      parse: (data) =>
          SalePayment.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `PUT /v1/sales/{id}/payments/{paymentId}`
  Future<SalePayment> update(
    int saleId,
    int paymentId, {
    required int paidById,
    required double amount,
    String? chequeNo,
    DateTime? chequeDate,
    String? note,
    int? bankId,
  }) {
    return _client.put(
      'v1/sales/$saleId/payments/$paymentId',
      body: _body(
        paidById: paidById,
        amount: amount,
        chequeNo: chequeNo,
        chequeDate: chequeDate,
        note: note,
        bankId: bankId,
      ),
      parse: (data) =>
          SalePayment.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `DELETE /v1/sales/{id}/payments/{paymentId}`
  Future<void> remove(int saleId, int paymentId) {
    return _client.delete(
      'v1/sales/$saleId/payments/$paymentId',
      parse: (_) {},
    );
  }

  Map<String, dynamic> _body({
    required int paidById,
    required double amount,
    String? chequeNo,
    DateTime? chequeDate,
    String? note,
    int? bankId,
  }) {
    return {
      'paid_by_id': paidById,
      'paid_amount': amount,
      'bank_id': ?bankId,
      if (chequeNo != null && chequeNo.isNotEmpty) 'cheque_no': chequeNo,
      if (chequeDate != null) 'cheque_date': _date(chequeDate),
      if (note != null && note.isNotEmpty) 'payment_note': note,
    };
  }

  /// The API takes plain `YYYY-MM-DD` for date-only fields.
  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
}
