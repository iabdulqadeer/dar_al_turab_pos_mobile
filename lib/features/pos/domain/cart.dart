import '../../../data/models/catalogue.dart';
import '../../../data/models/sale.dart';

/// One line in the POS cart.
///
/// Money and weight arithmetic mirror the web sale form exactly, because a
/// mobile sale of the same basket must produce the same totals as the web one
/// or the printed receipt will disagree with the web invoice.
class CartLine {
  CartLine({
    required this.product,
    required this.unit,
    required this.unitPrice,
    this.qty = 1,
    this.noOfPcs = 0,
    this.grossWeight = 0,
    this.wasteQty = 0,
    this.discount = 0,
    this.taxRate = 0,
    this.batchId,
    this.imeiNumber,
    this.id,
  });

  /// Builds a line from a search result, seeding price and unit from the
  /// server-resolved pricing so the cashier starts from the right number.
  factory CartLine.fromProduct(CatalogueProduct product) {
    final units = product.sellableUnits;

    return CartLine(
      product: product,
      unit: units.isEmpty ? null : units.first,
      unitPrice: product.pricing.resolvedPrice,
      qty: 1,
    );
  }

  /// Rebuilds an editable line from a sale that already exists.
  ///
  /// A sale line carries no stock or pricing metadata, so a stand-in
  /// [CatalogueProduct] is synthesised from what it does carry. Stock shows as
  /// 0, which would wrongly flag every line as over-stock — [stockOverride]
  /// lets the caller supply the real figure when a product lookup is
  /// available, and until then over-stock warnings are suppressed by seeding
  /// stock with the line's own quantity.
  factory CartLine.fromSaleItem(SaleItem item, {double? stockOverride}) {
    final unit = item.saleUnit == null
        ? null
        : SaleUnit(id: 0, name: item.saleUnit!);

    return CartLine(
      id: item.id,
      product: CatalogueProduct(
        id: item.productId ?? 0,
        name: item.productName,
        code: item.productCode,
        unit: unit,
        pricing: ProductPricing(
          basePrice: item.netUnitPrice,
          resolvedPrice: item.netUnitPrice,
          taxRate: item.taxRate,
        ),
        stock: stockOverride ?? item.qty,
      ),
      unit: unit,
      unitPrice: item.netUnitPrice,
      qty: item.qty,
      noOfPcs: item.noOfPcs,
      grossWeight: item.grossWeight,
      wasteQty: item.wasteQty,
      discount: item.discount,
    );
  }

  final CatalogueProduct product;
  SaleUnit? unit;

  /// Editable: operators set the price by hand, and the server accepts it.
  double unitPrice;

  /// Net quantity — for weight-based goods this is net KG.
  double qty;

  double noOfPcs;
  double grossWeight;
  double wasteQty;
  double discount;

  /// Global sale tax rate (percent), applied to every line's net total. Comes
  /// from `GET /settings/general` `data.tax`, not per-product, and is seeded by
  /// the cart controller. 0 means no tax.
  double taxRate;

  int? batchId;
  String? imeiNumber;

  /// The `product_sales` row id, present only when this line came from an
  /// existing sale being edited.
  ///
  /// `PUT /sales/{id}` matches lines by this id: supplied ids are updated in
  /// place, omitted existing lines are deleted, and lines without an id are
  /// inserted. Losing it would delete and re-create the row, detaching any
  /// history attached to it.
  final int? id;

  /// Line net total: net weight (qty) × net unit price.
  double get netTotal => _round(unitPrice * qty);

  /// Tax for this line — exclusive, on the net total, at the global [taxRate].
  ///
  /// e.g. net 120 × 220 = 26,400, at 5% → 1,320.
  double get tax {
    if (taxRate <= 0) return 0;
    return _round(netTotal * taxRate / 100);
  }

  /// Line total, tax included — matches the web's `sub_total`.
  double get subtotal => _round(netTotal + tax);

  /// True when the line would sell more than the warehouse holds. Advisory:
  /// the server is the authority and rejects with INSUFFICIENT_STOCK.
  bool get exceedsStock => qty > product.stock + 0.0001;

  /// Recomputes weight fields from a piece count, mirroring the web form.
  ///
  /// Per-piece values are stored in GRAMS, hence the /1000. Only applies to
  /// products that actually carry per-piece weights; for everything else the
  /// cashier edits qty directly.
  void applyPieceCount(
    double pieces, {
    required double perPieceGrossWeightGrams,
    required double perPieceWasteGrams,
  }) {
    noOfPcs = pieces;
    grossWeight = _round(pieces * perPieceGrossWeightGrams / 1000);
    wasteQty = _round(pieces * perPieceWasteGrams / 1000);
    qty = _round(grossWeight - wasteQty);
  }

  /// Derives net from the entered gross and waste: net = gross − waste.
  /// The cashier enters Gross and Waste; Net is the computed output.
  void syncNetFromWeights() {
    qty = _round(grossWeight - wasteQty);
    if (qty < 0) qty = 0;
  }

  /// Legacy inverse (waste = gross − net); retained for callers/tests that
  /// still drive waste from an entered net.
  void syncWasteFromWeights() {
    wasteQty = _round(grossWeight - qty);
  }

  CartLine copy() {
    return CartLine(
      product: product,
      unit: unit,
      unitPrice: unitPrice,
      qty: qty,
      noOfPcs: noOfPcs,
      grossWeight: grossWeight,
      wasteQty: wasteQty,
      discount: discount,
      taxRate: taxRate,
      batchId: batchId,
      imeiNumber: imeiNumber,
      id: id,
    );
  }

  /// The `items[]` entry POST /sales expects.
  ///
  /// [includeId] is set when building an update body, so an existing line is
  /// modified rather than replaced.
  Map<String, dynamic> toJson({bool includeId = false}) {
    return {
      if (includeId) 'id': ?id,
      'product_id': product.id,
      if (product.code != null) 'product_code': product.code,
      'qty': qty,
      // A unit NAME, not an id — an unknown name is rejected with
      // UNKNOWN_SALE_UNIT.
      'sale_unit': unit?.name ?? 'n/a',
      'net_unit_price': unitPrice,
      'discount': discount,
      'tax_rate': taxRate,
      'tax': tax,
      'subtotal': subtotal,
      if (noOfPcs > 0) 'no_of_pcs': noOfPcs,
      if (grossWeight > 0) 'gross_weight': grossWeight,
      if (wasteQty != 0) 'waste_qty': wasteQty,
      if (batchId != null) 'product_batch_id': batchId,
      if (imeiNumber != null) 'imei_number': imeiNumber,
    };
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;
}

/// The cart as a whole.
class Cart {
  Cart({
    this.lines = const [],
    this.customer,
    this.biller,
    this.orderDiscount = 0,
    this.shippingCost = 0,
    this.removeDecimalAmount = true,
  });

  final List<CartLine> lines;
  CatalogueCustomer? customer;
  NamedRef? biller;
  double orderDiscount;
  double shippingCost;

  /// Floors the grand total to a whole number. Defaults true, matching the
  /// server's own default for this deployment.
  bool removeDecimalAmount;

  bool get isEmpty => lines.isEmpty;
  int get itemCount => lines.length;

  double get totalQty =>
      lines.fold(0.0, (sum, l) => sum + l.qty);

  double get totalTax =>
      _round(lines.fold(0.0, (sum, l) => sum + l.tax));

  /// Sum of line totals, tax included.
  double get subtotal =>
      _round(lines.fold(0.0, (sum, l) => sum + l.subtotal));

  double get totalDiscount =>
      _round(lines.fold(0.0, (sum, l) => sum + l.discount));

  /// Matches the web formula: (subtotal + shipping) - order discount, then
  /// floored when remove_decimal_amount is set.
  double get grandTotal {
    final raw = subtotal + shippingCost - orderDiscount;
    final clamped = raw < 0 ? 0.0 : raw;
    return removeDecimalAmount
        ? clamped.floorToDouble()
        : _round(clamped);
  }

  bool get hasStockIssue => lines.any((l) => l.exceedsStock);

  /// Whether this cart can legally be submitted.
  String? get validationError {
    if (isEmpty) return 'Add at least one item.';
    if (customer == null) return 'Choose a customer.';
    if (biller == null) return 'Choose a biller.';
    if (lines.any((l) => l.qty <= 0)) {
      return 'Every line needs a quantity greater than zero.';
    }
    if (lines.any((l) => l.unit == null)) {
      return 'Every line needs a unit.';
    }
    return null;
  }

  /// The POST /sales body.
  ///
  /// [paidAmount] and [paymentMethodId] are omitted entirely for an unpaid
  /// sale — the server treats a missing `payment` block as "nothing paid".
  Map<String, dynamic> toCreateJson({
    required int saleStatus,
    required int paymentStatus,
    double paidAmount = 0,
    int? paymentMethodId,
    String? paymentNote,
    String? chequeNo,
    DateTime? chequeDate,
    int? bankId,
    String? saleNote,
    bool isPos = true,
  }) {
    return {
      'customer_id': customer!.id,
      'biller_id': biller!.id,
      'sale_status': saleStatus,
      'payment_status': paymentStatus,
      'is_pos': isPos,
      'remove_decimal_amount': removeDecimalAmount,
      'total_qty': totalQty,
      'total_discount': totalDiscount,
      'total_tax': totalTax,
      'total_price': subtotal,
      'order_discount': orderDiscount,
      'shipping_cost': shippingCost,
      'grand_total': grandTotal,
      'paid_amount': paidAmount,
      if (saleNote != null && saleNote.isNotEmpty) 'sale_note': saleNote,
      'items': lines.map((l) => l.toJson()).toList(),
      if (paymentMethodId != null && paidAmount > 0)
        'payment': {
          'paid_by_id': paymentMethodId,
          'paid_amount': paidAmount,
          // Cheque (id 4) carries its number/date; Deposit (id 6) a bank_id.
          // Both persist on create: the backend validates payment.cheque_no/
          // cheque_date and (since 2026-07-26) payment.bank_id.
          if (chequeNo != null && chequeNo.isNotEmpty) 'cheque_no': chequeNo,
          if (chequeDate != null)
            'cheque_date': chequeDate.toIso8601String().split('T').first,
          'bank_id': ?bankId,
          if (paymentNote != null && paymentNote.isNotEmpty)
            'payment_note': paymentNote,
        },
    };
  }

  /// The PUT /sales/{id} body.
  ///
  /// Differs from create in three ways the API documents:
  ///   - no `warehouse_id`, `is_pos`, `reference_no` or `serial_no`; those are
  ///     fixed once a sale exists,
  ///   - no `payment` block — money on an existing sale goes through the
  ///     payments sub-resource so the ledger stays authoritative,
  ///   - `items[].id` is carried so lines are updated rather than replaced.
  ///
  /// [paidAmount] is the sale's existing paid total, passed straight back
  /// because the endpoint recomputes payment status from it.
  Map<String, dynamic> toUpdateJson({
    required int saleStatus,
    required int paymentStatus,
    required double paidAmount,
    String? saleNote,
  }) {
    return {
      'customer_id': customer!.id,
      'biller_id': biller!.id,
      'sale_status': saleStatus,
      'payment_status': paymentStatus,
      'remove_decimal_amount': removeDecimalAmount,
      'total_qty': totalQty,
      'total_discount': totalDiscount,
      'total_tax': totalTax,
      'total_price': subtotal,
      'order_discount': orderDiscount,
      'shipping_cost': shippingCost,
      'grand_total': grandTotal,
      'paid_amount': paidAmount,
      if (saleNote != null && saleNote.isNotEmpty) 'sale_note': saleNote,
      'items': lines.map((l) => l.toJson(includeId: true)).toList(),
    };
  }

  static double _round(double v) => (v * 100).roundToDouble() / 100;
}
