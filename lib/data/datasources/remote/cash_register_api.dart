import '../../../core/network/api_client.dart';
import '../../models/cash_register.dart';

/// `GET /v1/cash-register/daily` — the daily cash-register report.
class CashRegisterApi {
  const CashRegisterApi(this._client);

  final ApiClient _client;

  /// [warehouseId]/[userId] are honoured only for an admin; the server ignores
  /// them (and re-scopes) for a staff account. Dates default to today when
  /// omitted.
  Future<CashRegisterReport> daily({
    String? startDate,
    String? endDate,
    int? warehouseId,
    int? userId,
  }) {
    return _client.get(
      'v1/cash-register/daily',
      query: {
        'start_date': ?startDate,
        'end_date': ?endDate,
        'warehouse_id': ?warehouseId,
        'user_id': ?userId,
      },
      parse: (data) =>
          CashRegisterReport.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }
}
