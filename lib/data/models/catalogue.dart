import 'sale_status.dart';

double _toDouble(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString()) ?? 0;
}

double? _toDoubleOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

int _toInt(dynamic v) {
  if (v == null) return 0;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString()) ?? 0;
}

int? _toIntOrNull(dynamic v) {
  if (v == null) return null;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

String? _str(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

List<Map<String, dynamic>> _mapList(dynamic v) => (v as List? ?? const [])
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList(growable: false);

/// A minimal `{id, name}` reference, used throughout `/sales/create-form`.
class NamedRef {
  const NamedRef({required this.id, required this.name, this.extra});

  factory NamedRef.fromJson(Map<String, dynamic> json) {
    return NamedRef(
      id: _toInt(json['id']),
      name: _str(json['name']) ?? _str(json['unit_name']) ?? '-',
      extra: _str(json['company_name']) ??
          _str(json['phone_number']) ??
          _str(json['account_number']) ??
          _str(json['code']),
    );
  }

  final int id;
  final String name;

  /// Secondary label (company, phone, account number) where the endpoint
  /// provides one — shown as a subtitle in pickers.
  final String? extra;

  @override
  bool operator ==(Object other) => other is NamedRef && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// A sale unit and its conversion factor back to the product's base unit.
class SaleUnit {
  const SaleUnit({
    required this.id,
    required this.name,
    this.code,
    this.operator,
    this.operationValue = 1,
  });

  factory SaleUnit.fromJson(Map<String, dynamic> json) {
    return SaleUnit(
      id: _toInt(json['id']),
      // `/sales/product-search` returns `unit_name` inside compatible_units
      // but `name` on the primary unit object.
      name: _str(json['unit_name']) ?? _str(json['name']) ?? '-',
      code: _str(json['unit_code']) ?? _str(json['code']),
      operator: _str(json['operator']),
      operationValue: _toDouble(json['operation_value'] ?? 1),
    );
  }

  final int id;

  /// POST /sales sends `sale_unit` as this NAME string, not an id — an
  /// unknown name is rejected with UNKNOWN_SALE_UNIT.
  final String name;
  final String? code;

  /// `*` or `/`, applied with [operationValue] to convert to the base unit.
  final String? operator;
  final double operationValue;

  @override
  bool operator ==(Object other) => other is SaleUnit && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Server-resolved pricing for a product.
///
/// The server applies discount-plan → active-promotion → plain-price
/// precedence, so the client never computes a price itself. [resolvedPrice]
/// is what should populate the cart line.
class ProductPricing {
  const ProductPricing({
    required this.basePrice,
    required this.resolvedPrice,
    required this.taxRate,
    this.discountSource,
    this.discountName,
    this.taxId,
    this.taxName,
    this.taxMethod = 'exclusive',
  });

  factory ProductPricing.fromJson(Map<String, dynamic> json) {
    return ProductPricing(
      basePrice: _toDouble(json['base_price']),
      resolvedPrice: _toDouble(json['resolved_price']),
      discountSource: _str(json['discount_source']),
      discountName: _str(json['discount_name']),
      taxId: _toIntOrNull(json['tax_id']),
      taxRate: _toDouble(json['tax_rate']),
      taxName: _str(json['tax_name']),
      taxMethod: _str(json['tax_method']) ?? 'exclusive',
    );
  }

  final double basePrice;
  final double resolvedPrice;

  /// `discount_plan`, `promotion`, or null when the plain price applies.
  final String? discountSource;
  final String? discountName;

  final int? taxId;
  final double taxRate;
  final String? taxName;

  /// `exclusive` (tax added on top) or `inclusive` (tax already inside).
  final String taxMethod;

  bool get isDiscounted =>
      discountSource != null && resolvedPrice < basePrice - 0.004;

  bool get isTaxInclusive => taxMethod == 'inclusive';
}

/// A product row from `GET /sales/product-search`.
class CatalogueProduct {
  const CatalogueProduct({
    required this.id,
    required this.name,
    required this.pricing,
    this.code,
    this.type,
    this.category,
    this.isVariant = false,
    this.isBatch = false,
    this.isImei = false,
    this.unit,
    this.compatibleUnits = const [],
    this.stock = 0,
    this.stockWarehouseId,
    this.batches = const [],
    this.variants = const [],
    this.perPieceGrossWeight = 0,
    this.perPieceWaste = 0,
  });

  factory CatalogueProduct.fromJson(Map<String, dynamic> json) {
    final unitJson = json['unit'] is Map
        ? Map<String, dynamic>.from(json['unit'] as Map)
        : null;
    final stockJson = json['stock'] is Map
        ? Map<String, dynamic>.from(json['stock'] as Map)
        : null;

    return CatalogueProduct(
      id: _toInt(json['id']),
      name: _str(json['name']) ?? '-',
      code: _str(json['code']),
      type: _str(json['type']),
      category: _str(json['category']),
      isVariant: json['is_variant'] == true,
      isBatch: json['is_batch'] == true,
      isImei: json['is_imei'] == true,
      unit: unitJson == null ? null : SaleUnit.fromJson(unitJson),
      compatibleUnits: unitJson == null
          ? const []
          : _mapList(unitJson['compatible_units'])
              .map(SaleUnit.fromJson)
              .toList(growable: false),
      pricing: ProductPricing.fromJson(
        json['pricing'] is Map
            ? Map<String, dynamic>.from(json['pricing'] as Map)
            : const {},
      ),
      stock: _toDouble(stockJson?['qty']),
      stockWarehouseId: _toIntOrNull(stockJson?['warehouse_id']),
      batches: _mapList(json['batches']),
      variants: _mapList(json['variants']),
      perPieceGrossWeight: _toDouble(json['per_piece_gross_weight']),
      perPieceWaste: _toDouble(json['per_piece_waste']),
    );
  }

  final int id;
  final String name;
  final String? code;
  final String? type;
  final String? category;
  final bool isVariant;
  final bool isBatch;
  final bool isImei;

  final SaleUnit? unit;

  /// Units this product may be sold in. Falls back to [unit] when the server
  /// returns none, so the picker is never empty.
  final List<SaleUnit> compatibleUnits;

  final ProductPricing pricing;
  final double stock;
  final int? stockWarehouseId;

  /// Raw batch/variant payloads. Kept unmodelled until the POS screen needs
  /// them — no live rows exist for either in this deployment.
  final List<Map<String, dynamic>> batches;
  final List<Map<String, dynamic>> variants;

  /// Per-piece weights in GRAMS, used to derive a weight-based line:
  ///   gross = pcs * perPieceGrossWeight / 1000
  ///   waste = pcs * perPieceWaste       / 1000
  ///   qty   = gross - waste                      (net KG)
  ///
  /// `GET /sales/product-search` does not currently return these, so they
  /// arrive as 0 and the piece-count shortcut stays hidden — the cashier
  /// enters gross/net/waste by hand instead. Parsed here so the shortcut
  /// starts working the moment the endpoint includes them.
  final double perPieceGrossWeight;
  final double perPieceWaste;

  /// Whether the piece-count shortcut can be offered for this product.
  bool get hasPerPieceWeights =>
      perPieceGrossWeight > 0 || perPieceWaste > 0;

  bool get inStock => stock > 0;

  List<SaleUnit> get sellableUnits =>
      compatibleUnits.isNotEmpty ? compatibleUnits : [?unit];

  String get subtitle {
    final parts = <String>[?code, ?category];
    return parts.join('  ·  ');
  }
}

/// A customer row from `GET /sales/customer-search`.
class CatalogueCustomer {
  const CatalogueCustomer({
    required this.id,
    required this.name,
    this.phoneNumber,
    this.companyName,
    this.address,
    this.trnNumber,
    this.points = 0,
    this.isDefault = false,
  });

  factory CatalogueCustomer.fromJson(Map<String, dynamic> json) {
    return CatalogueCustomer(
      id: _toInt(json['id']),
      name: _str(json['name']) ?? '-',
      phoneNumber: _str(json['phone_number']) ?? _str(json['phone']),
      companyName: _str(json['company_name']),
      address: _str(json['address']),
      trnNumber: _str(json['trn_number']),
      points: _toDouble(json['points']),
      isDefault: json['is_default'] == true,
    );
  }

  final int id;
  final String name;
  final String? phoneNumber;
  final String? companyName;
  final String? address;
  final String? trnNumber;
  final double points;

  /// The walk-in customer. POST /sales needs a real customer_id even for an
  /// anonymous sale, so this is what the cart defaults to.
  final bool isDefault;

  String? get subtitle {
    final parts = <String>[?phoneNumber, ?companyName];
    return parts.isEmpty ? null : parts.join('  ·  ');
  }
}

/// A payment method offered by `/sales/create-form`.
///
/// The server marks unusable methods `enabled: false` — notably id 7
/// (Points), which POST /sales rejects outright.
class PaymentMethodOption {
  const PaymentMethodOption({
    required this.id,
    required this.name,
    required this.enabled,
    this.note,
  });

  factory PaymentMethodOption.fromJson(Map<String, dynamic> json) {
    return PaymentMethodOption(
      id: _toInt(json['id']),
      name: _str(json['name']) ?? '-',
      enabled: json['enabled'] != false,
      note: _str(json['note']),
    );
  }

  final int id;
  final String name;
  final bool enabled;
  final String? note;

  PaymentMethod? get method => PaymentMethod.fromValue(id);
}

/// Everything `GET /sales/create-form` returns.
class SaleFormMetadata {
  const SaleFormMetadata({
    this.warehouseId,
    this.warehouses = const [],
    this.billers = const [],
    this.customerGroups = const [],
    this.banks = const [],
    this.taxes = const [],
    this.paymentMethods = const [],
    this.defaultCustomer,
    this.invoiceOption,
    this.nextReferenceNoPreview,
  });

  factory SaleFormMetadata.fromJson(Map<String, dynamic> json) {
    return SaleFormMetadata(
      warehouseId: _toIntOrNull(json['warehouse_id']),
      warehouses: _mapList(json['warehouses']).map(NamedRef.fromJson).toList(),
      billers: _mapList(json['billers']).map(NamedRef.fromJson).toList(),
      customerGroups:
          _mapList(json['customer_groups']).map(NamedRef.fromJson).toList(),
      banks: _mapList(json['banks']).map(NamedRef.fromJson).toList(),
      taxes: _mapList(json['taxes']).map(NamedRef.fromJson).toList(),
      paymentMethods: _mapList(json['payment_methods'])
          .map(PaymentMethodOption.fromJson)
          .toList(),
      defaultCustomer: json['default_customer'] is Map
          ? CatalogueCustomer.fromJson(
              Map<String, dynamic>.from(json['default_customer'] as Map),
            )
          : null,
      invoiceOption: _str(json['invoice_option']),
      nextReferenceNoPreview: _str(json['next_reference_no_preview']),
    );
  }

  final int? warehouseId;
  final List<NamedRef> warehouses;
  final List<NamedRef> billers;
  final List<NamedRef> customerGroups;
  final List<NamedRef> banks;
  final List<NamedRef> taxes;
  final List<PaymentMethodOption> paymentMethods;
  final CatalogueCustomer? defaultCustomer;
  final String? invoiceOption;

  /// A preview, not a reservation — the real reference number is assigned
  /// atomically at submit time and may differ.
  final String? nextReferenceNoPreview;

  /// Only the methods the server says are usable.
  List<PaymentMethodOption> get usablePaymentMethods =>
      paymentMethods.where((m) => m.enabled && m.method != null).toList();

  NamedRef? get defaultBiller => billers.isEmpty ? null : billers.first;

  /// The biller whose id matches [billerId], or null when no id is given or no
  /// biller matches. Used to default the New Sale biller to the logged-in
  /// user's own biller rather than whoever is first in the list.
  NamedRef? billerFor(int? billerId) {
    if (billerId == null) return null;
    for (final biller in billers) {
      if (biller.id == billerId) return biller;
    }
    return null;
  }

  /// The warehouse to actually search stock and customers in.
  ///
  /// Works around a server-side gap: for an admin whose own `warehouse_id` is
  /// null, `/sales/product-search` resolves the warehouse to `(int) null` —
  /// i.e. `0` — which matches no stock rows, so the catalogue comes back
  /// empty. The endpoint does honour an explicit `warehouse_id` from an
  /// admin, so falling back to the first warehouse it offered us makes the
  /// screen work for admins and staff alike.
  int? get effectiveWarehouseId {
    if (warehouseId != null && warehouseId != 0) return warehouseId;
    return warehouses.isEmpty ? null : warehouses.first.id;
  }

  /// True when the fallback above is doing the work, so the UI can say which
  /// warehouse it picked rather than silently choosing one.
  bool get warehouseWasInferred =>
      (warehouseId == null || warehouseId == 0) && warehouses.isNotEmpty;

  NamedRef? get effectiveWarehouse {
    final id = effectiveWarehouseId;
    if (id == null) return null;
    for (final w in warehouses) {
      if (w.id == id) return w;
    }
    return null;
  }
}

/// `GET /sales/{id}/edit-form` — the create-form metadata bundle plus the
/// sale being edited.
///
/// The nested sale is the full detail shape, and critically includes each
/// line's `id`, which `PUT /sales/{id}` needs to update lines in place rather
/// than deleting and re-inserting them.
class SaleEditForm {
  const SaleEditForm({required this.metadata, required this.saleJson});

  factory SaleEditForm.fromJson(Map<String, dynamic> json) {
    return SaleEditForm(
      metadata: SaleFormMetadata.fromJson(json),
      saleJson: json['sale'] is Map
          ? Map<String, dynamic>.from(json['sale'] as Map)
          : const {},
    );
  }

  final SaleFormMetadata metadata;

  /// Left raw so the caller can hand it to `SaleDetail.fromJson` without this
  /// file depending on the sale models.
  final Map<String, dynamic> saleJson;
}

/// `GET /sales/statistics` — whole-filtered-set totals.
class SaleStatistics {
  const SaleStatistics({
    required this.totalCount,
    required this.totalGrand,
    required this.totalPaid,
    required this.totalDue,
  });

  static const empty = SaleStatistics(
    totalCount: 0,
    totalGrand: 0,
    totalPaid: 0,
    totalDue: 0,
  );

  factory SaleStatistics.fromJson(Map<String, dynamic> json) {
    return SaleStatistics(
      totalCount: _toInt(json['total_count']),
      totalGrand: _toDouble(json['total_grand']),
      totalPaid: _toDouble(json['total_paid']),
      totalDue: _toDouble(json['total_due']),
    );
  }

  final int totalCount;
  final double totalGrand;
  final double totalPaid;
  final double totalDue;

  /// 0..1, clamped — this drives a progress indicator, which throws on NaN.
  double get collectionRate =>
      totalGrand <= 0 ? 0 : (totalPaid / totalGrand).clamp(0, 1).toDouble();
}

/// Optional numeric range filter, used by `min_total` / `max_total`.
class AmountRange {
  const AmountRange({this.min, this.max});

  final double? min;
  final double? max;

  static AmountRange? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return AmountRange(
      min: _toDoubleOrNull(json['min_total']),
      max: _toDoubleOrNull(json['max_total']),
    );
  }

  bool get isEmpty => min == null && max == null;
}
