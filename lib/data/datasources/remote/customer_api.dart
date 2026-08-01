import '../../../core/network/api_client.dart';
import '../../models/catalogue.dart';
import '../../models/customer_form.dart';

/// The dedicated "Add Customer" module (`/v1/customers`), separate from the
/// sale screen's inline quick-create (`POST /v1/sales/customers`,
/// [CatalogueApi.quickCreateCustomer]). Neither endpoint requires a
/// permission — only a valid session.
class CustomerApi {
  const CustomerApi(this._client);

  final ApiClient _client;

  /// `GET /v1/customers/create-form` — customer groups + areas for the two
  /// dropdowns. `warehouse_id` in the response is informational only.
  Future<CustomerCreateForm> createForm() {
    return _client.get(
      'v1/customers/create-form',
      parse: (data) =>
          CustomerCreateForm.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `POST /v1/customers` — the fuller customer create. Returns `201` with the
  /// created customer; `area`/`customer_group` come back as `{id,name}` but
  /// [CatalogueCustomer] only needs the flat fields, so it slots straight into
  /// the sale cart.
  ///
  /// warehouse_id, opening_balance, balance_limit and is_active are resolved or
  /// hardcoded server-side, so they are deliberately never sent.
  Future<CatalogueCustomer> create({
    required int customerGroupId,
    required int areaId,
    required String name,
    required String phoneNumber,
    required String address,
    required String city,
    required String country,
    String? trnNumber,
    String? managerName,
  }) {
    return _client.post(
      'v1/customers',
      body: {
        'customer_group_id': customerGroupId,
        'area_id': areaId,
        'name': name,
        'phone_number': phoneNumber,
        'address': address,
        'city': city,
        'country': country,
        'trn_number': ?trnNumber,
        'manager_name': ?managerName,
      },
      parse: (data) =>
          CatalogueCustomer.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }
}