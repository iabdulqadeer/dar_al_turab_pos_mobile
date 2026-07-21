import '../../../core/network/api_client.dart';
import '../../../core/network/api_response.dart';
import '../../models/catalogue.dart';
import 'sales_api.dart';

/// The sale-composition endpoints.
///
/// All of these live under `/sales/` in the API and require `sales-add`
/// (except statistics, which requires `sales-index`). Route order on the
/// server puts these literal paths before `sales/{id}`, so they are not
/// swallowed by the id route.
class CatalogueApi {
  const CatalogueApi(this._client);

  final ApiClient _client;

  /// `GET /v1/sales/create-form` — reference data for a new sale.
  ///
  /// One call replaces what would otherwise be six: billers, banks, taxes,
  /// payment methods, the default customer, and the reference-number preview.
  Future<SaleFormMetadata> createForm({int? warehouseId}) {
    return _client.get(
      'v1/sales/create-form',
      query: {'warehouse_id': ?warehouseId},
      parse: (data) =>
          SaleFormMetadata.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `GET /v1/sales/{id}/edit-form` — metadata resolved to the sale's own
  /// warehouse, plus the sale itself for prefill.
  Future<SaleEditForm> editForm(int saleId) {
    return _client.get(
      'v1/sales/$saleId/edit-form',
      parse: (data) =>
          SaleEditForm.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `GET /v1/sales/product-search`
  ///
  /// [customerId] matters: the server resolves that customer's discount-plan
  /// pricing into `pricing.resolved_price`, so searching without it can show
  /// a different price than the sale will actually use.
  ///
  /// [qty] affects quantity-range discount matching for the same reason.
  Future<Paginated<CatalogueProduct>> searchProducts({
    String? query,
    int? customerId,
    double qty = 1,
    int? warehouseId,
    int page = 1,
    int perPage = 20,
  }) {
    return _client.getList<CatalogueProduct>(
      'v1/sales/product-search',
      query: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'customer_id': ?customerId,
        'warehouse_id': ?warehouseId,
        'qty': qty,
        'page': page,
        'per_page': perPage,
      },
      parseItem: CatalogueProduct.fromJson,
    );
  }

  /// `GET /v1/sales/customer-search`. Results are default-customer-first.
  Future<Paginated<CatalogueCustomer>> searchCustomers({
    String? query,
    int? warehouseId,
    int page = 1,
    int perPage = 20,
  }) {
    return _client.getList<CatalogueCustomer>(
      'v1/sales/customer-search',
      query: {
        if (query != null && query.trim().isNotEmpty) 'q': query.trim(),
        'warehouse_id': ?warehouseId,
        'page': page,
        'per_page': perPage,
      },
      parseItem: CatalogueCustomer.fromJson,
    );
  }

  /// `POST /v1/sales/customers` — inline "add customer" on the sale screen.
  Future<CatalogueCustomer> quickCreateCustomer({
    required String name,
    String? phoneNumber,
    String? address,
    String? email,
    int? customerGroupId,
  }) {
    return _client.post(
      'v1/sales/customers',
      body: {
        'name': name,
        'phone_number': ?phoneNumber,
        'address': ?address,
        'email': ?email,
        'customer_group_id': ?customerGroupId,
      },
      parse: (data) =>
          CatalogueCustomer.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }

  /// `GET /v1/sales/statistics` — the same totals as `GET /sales`'s
  /// `meta.summary`, without paying for a page of rows.
  Future<SaleStatistics> statistics(SaleFilters filters) {
    final query = filters.toQuery(page: 1)
      ..remove('page')
      ..remove('per_page')
      ..remove('sort')
      ..remove('direction');

    return _client.get(
      'v1/sales/statistics',
      query: query,
      parse: (data) =>
          SaleStatistics.fromJson(Map<String, dynamic>.from(data as Map)),
    );
  }
}
