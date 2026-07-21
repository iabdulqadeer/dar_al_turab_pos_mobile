import 'sale_status.dart';

/// Helpers for the loose typing the API returns — Laravel emits numerics as
/// either JSON numbers or strings depending on the column, so every numeric
/// read goes through these rather than a raw cast.
double _toDouble(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

int _toInt(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? 0;
}

int? _toIntOrNull(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

String? _toStringOrNull(dynamic value) {
  if (value == null) return null;
  final s = value.toString().trim();
  return s.isEmpty ? null : s;
}

Map<String, dynamic>? _mapOrNull(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

/// A named entity referenced by a sale (customer, biller, warehouse, user).
class SaleParty {
  const SaleParty({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    this.trnNumber,
    this.companyName,
    this.email,
    this.isWalkingCustomer = false,
  });

  static SaleParty? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    return SaleParty(
      id: _toIntOrNull(json['id']),
      name: _toStringOrNull(json['name']) ?? '-',
      phone: _toStringOrNull(json['phone'] ?? json['phone_number']),
      address: _toStringOrNull(json['address']),
      trnNumber: _toStringOrNull(json['trn_number']),
      companyName: _toStringOrNull(json['company_name']),
      email: _toStringOrNull(json['email']),
      isWalkingCustomer: json['is_walking_customer'] == true,
    );
  }

  final int? id;
  final String name;
  final String? phone;
  final String? address;
  final String? trnNumber;
  final String? companyName;
  final String? email;
  final bool isWalkingCustomer;
}

/// A row in `GET /v1/sales` (`SaleListResource`).
class SaleListItem {
  const SaleListItem({
    required this.id,
    required this.referenceNo,
    required this.date,
    required this.itemCount,
    required this.totalQty,
    required this.grandTotal,
    required this.paidAmount,
    required this.returnedAmount,
    required this.ipDiscount,
    required this.due,
    this.customer,
    this.biller,
    this.warehouse,
    this.createdBy,
    this.saleStatus,
    this.saleStatusLabel,
    this.paymentStatus,
    this.paymentStatusLabel,
  });

  factory SaleListItem.fromJson(Map<String, dynamic> json) {
    return SaleListItem(
      id: _toInt(json['id']),
      referenceNo: _toStringOrNull(json['reference_no']) ?? '-',
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      customer: SaleParty.fromJson(_mapOrNull(json['customer'])),
      biller: SaleParty.fromJson(_mapOrNull(json['biller'])),
      warehouse: SaleParty.fromJson(_mapOrNull(json['warehouse'])),
      createdBy: SaleParty.fromJson(_mapOrNull(json['created_by'])),
      itemCount: _toInt(json['item_count']),
      totalQty: _toDouble(json['total_qty']),
      grandTotal: _toDouble(json['grand_total']),
      paidAmount: _toDouble(json['paid_amount']),
      returnedAmount: _toDouble(json['returned_amount']),
      ipDiscount: _toDouble(json['ip_discount']),
      due: _toDouble(json['due']),
      saleStatus: SaleStatus.fromValue(_toIntOrNull(json['sale_status'])),
      saleStatusLabel: _toStringOrNull(json['sale_status_label']),
      paymentStatus: PaymentStatus.fromValue(
        _toIntOrNull(json['payment_status']),
      ),
      paymentStatusLabel: _toStringOrNull(json['payment_status_label']),
    );
  }

  final int id;
  final String referenceNo;
  final DateTime? date;
  final SaleParty? customer;
  final SaleParty? biller;
  final SaleParty? warehouse;
  final SaleParty? createdBy;
  final int itemCount;
  final double totalQty;
  final double grandTotal;
  final double paidAmount;
  final double returnedAmount;
  final double ipDiscount;
  final double due;
  final SaleStatus? saleStatus;
  final String? saleStatusLabel;
  final PaymentStatus? paymentStatus;
  final String? paymentStatusLabel;

  /// Prefer the server's label so client and web stay in step even if the
  /// server adds a status the enum does not know about yet.
  String get saleStatusText =>
      saleStatusLabel ?? saleStatus?.label ?? 'Unknown';

  String get paymentStatusText =>
      paymentStatusLabel ?? paymentStatus?.label ?? 'Unknown';

  bool get hasDue => due > 0.004;
}

/// A line on a sale. Carries the weight-based fields this business trades on
/// (`no_of_pcs`, `gross_weight`, `waste_qty`) alongside the standard ones.
class SaleItem {
  const SaleItem({
    required this.id,
    required this.productId,
    required this.productName,
    required this.qty,
    required this.noOfPcs,
    required this.grossWeight,
    required this.wasteQty,
    required this.netUnitPrice,
    required this.discount,
    required this.taxRate,
    required this.tax,
    required this.total,
    this.productCode,
    this.variantName,
    this.batchNo,
    this.imeiNumber,
    this.saleUnit,
  });

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: _toIntOrNull(json['id']),
      productId: _toIntOrNull(json['product_id']),
      productName: _toStringOrNull(json['product_name']) ?? '-',
      productCode: _toStringOrNull(json['product_code']),
      variantName: _toStringOrNull(json['variant_name']),
      batchNo: _toStringOrNull(json['batch_no']),
      imeiNumber: _toStringOrNull(json['imei_number']),
      qty: _toDouble(json['qty']),
      noOfPcs: _toDouble(json['no_of_pcs']),
      grossWeight: _toDouble(json['gross_weight']),
      wasteQty: _toDouble(json['waste_qty']),
      saleUnit: _toStringOrNull(json['sale_unit']),
      netUnitPrice: _toDouble(json['net_unit_price']),
      discount: _toDouble(json['discount']),
      taxRate: _toDouble(json['tax_rate']),
      tax: _toDouble(json['tax']),
      total: _toDouble(json['total']),
    );
  }

  final int? id;
  final int? productId;
  final String productName;
  final String? productCode;
  final String? variantName;
  final String? batchNo;
  final String? imeiNumber;

  /// Net weight / quantity sold.
  final double qty;
  final double noOfPcs;
  final double grossWeight;
  final double wasteQty;
  final String? saleUnit;
  final double netUnitPrice;
  final double discount;
  final double taxRate;
  final double tax;
  final double total;

  String get displayName =>
      variantName == null ? productName : '$productName ($variantName)';
}

/// A payment recorded against a sale (`invoice_payments`).
class SalePayment {
  const SalePayment({
    required this.id,
    required this.paidAmount,
    required this.discount,
    this.referenceNumber,
    this.paymentNote,
    this.createdAt,
  });

  factory SalePayment.fromJson(Map<String, dynamic> json) {
    return SalePayment(
      id: _toIntOrNull(json['id']),
      paidAmount: _toDouble(json['paid_amount']),
      discount: _toDouble(json['discount']),
      referenceNumber: _toStringOrNull(json['reference_number']),
      paymentNote: _toStringOrNull(json['payment_note']),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }

  final int? id;
  final double paidAmount;
  final double discount;
  final String? referenceNumber;
  final String? paymentNote;
  final DateTime? createdAt;
}

/// Money summary for a sale.
class SaleTotals {
  const SaleTotals({
    required this.totalQty,
    required this.totalDiscount,
    required this.totalTax,
    required this.totalPrice,
    required this.orderDiscount,
    required this.shippingCost,
    required this.ipDiscount,
    required this.grandTotal,
    required this.paidAmount,
    required this.returnAdjustment,
    required this.partySupportAdjustment,
    required this.due,
    required this.change,
  });

  factory SaleTotals.fromJson(Map<String, dynamic> json) {
    return SaleTotals(
      totalQty: _toDouble(json['total_qty']),
      totalDiscount: _toDouble(json['total_discount']),
      totalTax: _toDouble(json['total_tax']),
      totalPrice: _toDouble(json['total_price']),
      orderDiscount: _toDouble(json['order_discount']),
      shippingCost: _toDouble(json['shipping_cost']),
      ipDiscount: _toDouble(json['ip_discount']),
      grandTotal: _toDouble(json['grand_total']),
      paidAmount: _toDouble(json['paid_amount']),
      returnAdjustment: _toDouble(json['return_adjustment']),
      partySupportAdjustment: _toDouble(json['party_support_adjustment']),
      due: _toDouble(json['due']),
      change: _toDouble(json['change']),
    );
  }

  final double totalQty;
  final double totalDiscount;
  final double totalTax;

  /// Line total *including* tax, matching the web receipt's arithmetic.
  final double totalPrice;
  final double orderDiscount;
  final double shippingCost;
  final double ipDiscount;
  final double grandTotal;
  final double paidAmount;
  final double returnAdjustment;
  final double partySupportAdjustment;
  final double due;

  /// Always 0 from the API: the legacy `payments` table that held change has
  /// no rows in production and `invoice_payments` has no such column.
  final double change;

  double get subTotal => totalPrice - totalTax;
}

/// Full sale from `GET /v1/sales/{id}`.
class SaleDetail {
  const SaleDetail({
    required this.id,
    required this.referenceNo,
    required this.items,
    required this.payments,
    required this.totals,
    this.serialNo,
    this.date,
    this.warehouse,
    this.biller,
    this.customer,
    this.createdBy,
    this.saleStatus,
    this.saleStatusLabel,
    this.paymentStatus,
    this.paymentStatusLabel,
    this.deliveryStatus,
  });

  factory SaleDetail.fromJson(Map<String, dynamic> json) {
    return SaleDetail(
      id: _toInt(json['id']),
      referenceNo: _toStringOrNull(json['reference_no']) ?? '-',
      serialNo: _toStringOrNull(json['serial_no']),
      date: DateTime.tryParse(json['date']?.toString() ?? ''),
      warehouse: SaleParty.fromJson(_mapOrNull(json['warehouse'])),
      biller: SaleParty.fromJson(_mapOrNull(json['biller'])),
      customer: SaleParty.fromJson(_mapOrNull(json['customer'])),
      createdBy: SaleParty.fromJson(_mapOrNull(json['created_by'])),
      saleStatus: SaleStatus.fromValue(_toIntOrNull(json['sale_status'])),
      saleStatusLabel: _toStringOrNull(json['sale_status_label']),
      paymentStatus: PaymentStatus.fromValue(
        _toIntOrNull(json['payment_status']),
      ),
      paymentStatusLabel: _toStringOrNull(json['payment_status_label']),
      deliveryStatus: _toIntOrNull(json['delivery_status']),
      items: (json['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => SaleItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      payments: (json['payments'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => SalePayment.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      totals: SaleTotals.fromJson(_mapOrNull(json['totals']) ?? const {}),
    );
  }

  final int id;
  final String referenceNo;
  final String? serialNo;
  final DateTime? date;
  final SaleParty? warehouse;
  final SaleParty? biller;
  final SaleParty? customer;
  final SaleParty? createdBy;
  final SaleStatus? saleStatus;
  final String? saleStatusLabel;
  final PaymentStatus? paymentStatus;
  final String? paymentStatusLabel;

  /// 1 = Delivered, 2 = Pending. The API exposes no label for this one, so
  /// the mapping lives here.
  final int? deliveryStatus;

  final List<SaleItem> items;
  final List<SalePayment> payments;
  final SaleTotals totals;

  String get saleStatusText =>
      saleStatusLabel ?? saleStatus?.label ?? 'Unknown';

  String get paymentStatusText =>
      paymentStatusLabel ?? paymentStatus?.label ?? 'Unknown';

  String? get deliveryStatusText => switch (deliveryStatus) {
    1 => 'Delivered',
    2 => 'Pending delivery',
    _ => null,
  };
}
