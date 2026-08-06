import 'package:dar_al_turab_pos/data/models/catalogue.dart';
import 'package:dar_al_turab_pos/data/models/sale.dart';
import 'package:dar_al_turab_pos/features/pos/domain/cart.dart';
import 'package:flutter_test/flutter_test.dart';

CatalogueProduct product({
  double price = 10,
  double taxRate = 5,
  String taxMethod = 'exclusive',
  double stock = 100,
  double perPieceGross = 0,
  double perPieceWaste = 0,
  String unitName = 'KG',
}) {
  return CatalogueProduct(
    id: 1,
    name: 'Test Product',
    code: 'TP1',
    unit: SaleUnit(id: 4, name: unitName),
    pricing: ProductPricing(
      basePrice: price,
      resolvedPrice: price,
      taxRate: taxRate,
      taxMethod: taxMethod,
    ),
    stock: stock,
    perPieceGrossWeight: perPieceGross,
    perPieceWaste: perPieceWaste,
  );
}

void main() {
  group('CartLine tax and subtotal', () {
    test('applies the global tax rate on top of net total', () {
      // taxRate is now the global sale rate (from settings/general), seeded on
      // the line, not read from the product.
      final line = CartLine.fromProduct(product())
        ..taxRate = 5
        ..qty = 10;

      // 10 x 10 = 100, +5% = 5
      expect(line.tax, 5);
      expect(line.subtotal, 105);
    });

    test('matches the spec example: 120 x 220 at 5%', () {
      final line = CartLine.fromProduct(product(price: 220))
        ..taxRate = 5
        ..qty = 120;

      expect(line.tax, 1320);
      expect(line.subtotal, 120 * 220 + 1320);
    });

    test('is tax-free when the rate is zero', () {
      final line = CartLine.fromProduct(product())
        ..taxRate = 0
        ..qty = 3;

      expect(line.tax, 0);
      expect(line.subtotal, 30);
    });
  });

  group('CartLine weight derivation', () {
    test('derives gross, waste and net from a piece count', () {
      // Per-piece values are in GRAMS, so 10 pieces at 250g gross and 15g
      // waste give 2.5kg gross, 0.15kg waste, 2.35kg net.
      final line = CartLine.fromProduct(
        product(perPieceGross: 250, perPieceWaste: 15),
      );

      line.applyPieceCount(
        10,
        perPieceGrossWeightGrams: 250,
        perPieceWasteGrams: 15,
      );

      expect(line.noOfPcs, 10);
      expect(line.grossWeight, 2.5);
      expect(line.wasteQty, 0.15);
      expect(line.qty, 2.35);
    });

    test('derives net from gross and waste (net = gross - waste)', () {
      final line = CartLine.fromProduct(product())
        ..grossWeight = 10
        ..wasteQty = 0.6;

      line.syncNetFromWeights();

      expect(line.qty, closeTo(9.4, 0.001));
    });
  });

  group('CartLine.fromSaleItem', () {
    final item = SaleItem.fromJson({
      'id': 42,
      'product_id': 7,
      'product_name': 'BEEF LIVER',
      'product_code': 'BFL001',
      'qty': 12.5,
      'no_of_pcs': 5,
      'gross_weight': 13,
      'waste_qty': 0.5,
      'sale_unit': 'KG',
      'net_unit_price': 20,
      'tax_rate': 5,
      'discount': 0,
    });

    test('carries the line id so an edit updates in place', () {
      // PUT /sales/{id} matches lines by id; losing it would delete and
      // re-insert the row.
      expect(CartLine.fromSaleItem(item).id, 42);
    });

    test('restores quantities, weights and price', () {
      final line = CartLine.fromSaleItem(item);

      expect(line.qty, 12.5);
      expect(line.noOfPcs, 5);
      expect(line.grossWeight, 13);
      expect(line.wasteQty, 0.5);
      expect(line.unitPrice, 20);
      expect(line.unit?.name, 'KG');
    });

    test('does not flag an existing line as over-stock', () {
      // A sale line carries no stock figure. Seeding stock with the line's own
      // quantity avoids every line on an edited sale showing a false warning.
      expect(CartLine.fromSaleItem(item).exceedsStock, isFalse);
    });

    test('honours a real stock figure when one is supplied', () {
      final line = CartLine.fromSaleItem(item, stockOverride: 5);

      expect(line.exceedsStock, isTrue);
    });

    test('survives round-tripping through copy()', () {
      final copy = CartLine.fromSaleItem(item).copy();

      expect(copy.id, 42);
      expect(copy.qty, 12.5);
    });
  });

  group('Cart totals', () {
    Cart cartWith(List<CartLine> lines) => Cart(
      lines: lines,
      customer: const CatalogueCustomer(id: 1, name: 'Walk in'),
      biller: const NamedRef(id: 1, name: 'Biller'),
      warehouse: const NamedRef(id: 1, name: 'Warehouse'),
      removeDecimalAmount: false,
    );

    test('sums line subtotals', () {
      final cart = cartWith([
        CartLine.fromProduct(product())
          ..taxRate = 5
          ..qty = 10, // 105
        CartLine.fromProduct(product())
          ..taxRate = 5
          ..qty = 5, // 52.50
      ]);

      expect(cart.subtotal, closeTo(157.5, 0.01));
      expect(cart.grandTotal, closeTo(157.5, 0.01));
    });

    test('adds shipping and subtracts order discount', () {
      final cart =
          cartWith([
            CartLine.fromProduct(product())
              ..taxRate = 5
              ..qty = 10,
          ])
            ..shippingCost = 10
            ..orderDiscount = 5;

      expect(cart.grandTotal, closeTo(110, 0.01));
    });

    test('floors the grand total when remove_decimal_amount is set', () {
      final cart = Cart(
        lines: [
          CartLine.fromProduct(product(price: 10.07))
            ..taxRate = 5
            ..qty = 10,
        ],
        removeDecimalAmount: true,
      );

      // 100.70 + 5% = 105.735 -> floored to 105
      expect(cart.grandTotal, 105);
    });

    test('never goes negative on an oversized discount', () {
      final cart = cartWith([CartLine.fromProduct(product())..qty = 1])
        ..orderDiscount = 9999;

      expect(cart.grandTotal, 0);
    });
  });

  group('CartLine.isWeightBased / isComplete', () {
    // A KG line uses the weight form and needs pieces + gross + net.
    CartLine weightLine() => CartLine.fromProduct(product())
      ..noOfPcs = 2
      ..grossWeight = 10
      ..wasteQty = 1
      ..qty = 9; // net = gross - waste

    // A PC line uses the simple form and needs only quantity.
    CartLine simpleLine() =>
        CartLine.fromProduct(product(unitName: 'PC'))..qty = 3;

    test('a KG unit is weight-based; a PC unit is not', () {
      expect(CartLine.fromProduct(product()).isWeightBased, isTrue);
      expect(CartLine.fromProduct(product(unitName: 'PC')).isWeightBased, isFalse);
    });

    test('a fully-filled weight line is complete', () {
      expect(weightLine().isComplete, isTrue);
    });

    test('a weight line missing pieces or gross is incomplete', () {
      expect((weightLine()..noOfPcs = 0).isComplete, isFalse);
      expect((weightLine()..grossWeight = 0).isComplete, isFalse);
    });

    test('any line with a zero unit price is incomplete', () {
      expect((weightLine()..unitPrice = 0).isComplete, isFalse);
      expect((simpleLine()..unitPrice = 0).isComplete, isFalse);
    });

    test('a simple line only needs a positive quantity + price', () {
      expect(simpleLine().isComplete, isTrue);
      expect((simpleLine()..qty = 0).isComplete, isFalse);
    });
  });

  group('Cart validation', () {
    CartLine completeLine() => CartLine.fromProduct(product())
      ..noOfPcs = 2
      ..grossWeight = 10
      ..wasteQty = 0
      ..qty = 10;

    test('rejects an empty basket', () {
      expect(Cart(lines: []).validationError, isNotNull);
    });

    test('requires a customer, warehouse and biller', () {
      final noCustomer = Cart(
        lines: [CartLine.fromProduct(product())],
        biller: const NamedRef(id: 1, name: 'B'),
        warehouse: const NamedRef(id: 1, name: 'W'),
      );
      expect(noCustomer.validationError, contains('customer'));

      final noWarehouse = Cart(
        lines: [CartLine.fromProduct(product())],
        customer: const CatalogueCustomer(id: 1, name: 'C'),
        biller: const NamedRef(id: 1, name: 'B'),
      );
      expect(noWarehouse.validationError, contains('warehouse'));

      final noBiller = Cart(
        lines: [CartLine.fromProduct(product())],
        customer: const CatalogueCustomer(id: 1, name: 'C'),
        warehouse: const NamedRef(id: 1, name: 'W'),
      );
      expect(noBiller.validationError, contains('biller'));
    });

    Cart cartOf(List<CartLine> lines) => Cart(
      lines: lines,
      customer: const CatalogueCustomer(id: 1, name: 'C'),
      biller: const NamedRef(id: 1, name: 'B'),
      warehouse: const NamedRef(id: 1, name: 'W'),
    );

    test('accepts a complete basket', () {
      expect(cartOf([completeLine()]).validationError, isNull);
    });

    test('rejects a line with incomplete details (issue #4)', () {
      // Product added but its details never filled in.
      final error = cartOf([CartLine.fromProduct(product())]).validationError;
      expect(error, contains('Product details'));
    });

    test('rejects a zero grand total (issue #2)', () {
      // A "complete" line whose price is 0 → total 0. Give it a price so the
      // per-line check passes, then force the total to 0 via a matching
      // order discount so only the total rule can fire.
      final cart = cartOf([completeLine()])..orderDiscount = 100; // 10*10 = 100
      expect(cart.grandTotal, 0);
      expect(cart.validationError, contains('greater than zero'));
    });
  });

  group('Cart.toCreateJson', () {
    Cart full() => Cart(
      lines: [CartLine.fromProduct(product())..qty = 10],
      customer: const CatalogueCustomer(id: 3, name: 'C'),
      biller: const NamedRef(id: 4, name: 'B'),
      warehouse: const NamedRef(id: 5, name: 'W'),
      removeDecimalAmount: false,
    );

    test('sends the unit NAME, which is what the API matches on', () {
      // sale_unit is a name string; an unknown one is rejected with
      // UNKNOWN_SALE_UNIT.
      final json = full().toCreateJson(saleStatus: 1, paymentStatus: 4);

      expect(json['items'][0]['sale_unit'], 'KG');
    });

    test('omits the payment block when nothing was paid', () {
      final json = full().toCreateJson(saleStatus: 1, paymentStatus: 2);

      expect(json.containsKey('payment'), isFalse);
    });

    test('includes the payment block when money changed hands', () {
      final json = full().toCreateJson(
        saleStatus: 1,
        paymentStatus: 4,
        paidAmount: 105,
        paymentMethodId: 1,
      );

      expect(json['payment']['paid_by_id'], 1);
      expect(json['payment']['paid_amount'], 105);
    });

    test('omits line ids, since a create has none', () {
      final json = full().toCreateJson(saleStatus: 1, paymentStatus: 4);

      expect(json['items'][0].containsKey('id'), isFalse);
    });
  });

  group('Cart.toUpdateJson', () {
    test('carries ids for existing lines and omits them for new ones', () {
      final existing = SaleItem.fromJson({
        'id': 42,
        'product_id': 7,
        'product_name': 'Existing',
        'qty': 2,
        'sale_unit': 'KG',
        'net_unit_price': 10,
      });

      final cart = Cart(
        lines: [
          CartLine.fromSaleItem(existing),
          CartLine.fromProduct(product()), // newly added, no id
        ],
        customer: const CatalogueCustomer(id: 3, name: 'C'),
        biller: const NamedRef(id: 4, name: 'B'),
        warehouse: const NamedRef(id: 5, name: 'W'),
      );

      final json = cart.toUpdateJson(
        saleStatus: 1,
        paymentStatus: 4,
        paidAmount: 0,
      );

      expect(json['items'][0]['id'], 42);
      expect(json['items'][1].containsKey('id'), isFalse);
    });

    test('omits fields the update endpoint does not accept', () {
      // PUT /sales/{id} takes no is_pos, reference_no or payment block, but
      // warehouse_id/biller_id ARE sent (the server honours a biller change and,
      // for an admin, a warehouse change).
      final cart = Cart(
        lines: [CartLine.fromProduct(product())],
        customer: const CatalogueCustomer(id: 3, name: 'C'),
        biller: const NamedRef(id: 4, name: 'B'),
        warehouse: const NamedRef(id: 5, name: 'W'),
      );

      final json = cart.toUpdateJson(
        saleStatus: 1,
        paymentStatus: 4,
        paidAmount: 50,
      );

      expect(json.containsKey('payment'), isFalse);
      expect(json['warehouse_id'], 5);
      expect(json.containsKey('is_pos'), isFalse);
      expect(json.containsKey('reference_no'), isFalse);
      expect(json['paid_amount'], 50);
    });
  });
}
