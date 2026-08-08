import 'package:dar_al_turab_pos/data/models/catalogue.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SaleFormMetadata.effectiveWarehouseId', () {
    // Guards a real server-side gap: GET /sales/product-search resolves an
    // admin's null warehouse_id to `(int) null` == 0, which matches no stock
    // and returns an empty catalogue. The endpoint does honour an explicit
    // warehouse_id from an admin, so the app supplies one.
    test('falls back to the first warehouse when the server sends null', () {
      final meta = SaleFormMetadata.fromJson({
        'warehouse_id': null,
        'warehouses': [
          {'id': 3, 'name': 'Main Warehouse'},
          {'id': 5, 'name': 'Second'},
        ],
      });

      expect(meta.effectiveWarehouseId, 3);
      expect(meta.warehouseWasInferred, isTrue);
      expect(meta.effectiveWarehouse?.name, 'Main Warehouse');
    });

    test('falls back when the server sends 0', () {
      final meta = SaleFormMetadata.fromJson({
        'warehouse_id': 0,
        'warehouses': [
          {'id': 3, 'name': 'Main Warehouse'},
        ],
      });

      expect(meta.effectiveWarehouseId, 3);
      expect(meta.warehouseWasInferred, isTrue);
    });

    test('uses the assigned warehouse when there is one', () {
      final meta = SaleFormMetadata.fromJson({
        'warehouse_id': 7,
        'warehouses': [
          {'id': 3, 'name': 'Main Warehouse'},
          {'id': 7, 'name': 'Mine'},
        ],
      });

      expect(meta.effectiveWarehouseId, 7);
      expect(meta.warehouseWasInferred, isFalse);
      expect(meta.effectiveWarehouse?.name, 'Mine');
    });

    test('is null when there is nothing to fall back to', () {
      final meta = SaleFormMetadata.fromJson({
        'warehouse_id': null,
        'warehouses': <Map<String, dynamic>>[],
      });

      expect(meta.effectiveWarehouseId, isNull);
      expect(meta.warehouseWasInferred, isFalse);
    });
  });

  group('SaleFormMetadata payment methods', () {
    test('excludes methods the server marks disabled', () {
      // Points (7) is always disabled — POST /sales rejects it outright, so
      // offering it would 422 after the cashier has taken the money.
      final meta = SaleFormMetadata.fromJson({
        'payment_methods': [
          {'id': 1, 'name': 'Cash', 'enabled': true},
          {'id': 2, 'name': 'Gift Card', 'enabled': false},
          {'id': 7, 'name': 'Points', 'enabled': false},
        ],
      });

      expect(meta.usablePaymentMethods.map((m) => m.id), [1]);
    });

    test('excludes ids the client has no enum for, even if enabled', () {
      final meta = SaleFormMetadata.fromJson({
        'payment_methods': [
          {'id': 1, 'name': 'Cash', 'enabled': true},
          {'id': 7, 'name': 'Points', 'enabled': true},
        ],
      });

      expect(meta.usablePaymentMethods.map((m) => m.id), [1]);
    });
  });

  group('SaleFormMetadata.billerFor', () {
    final meta = SaleFormMetadata.fromJson({
      'billers': [
        {'id': 1, 'name': 'HAMZA ISHFAQ'},
        {'id': 5, 'name': 'Sara Khan'},
      ],
    });

    test('returns the biller matching the user\'s own biller_id', () {
      expect(meta.billerFor(5)?.name, 'Sara Khan');
    });

    test('returns null for a null biller_id (e.g. admin)', () {
      expect(meta.billerFor(null), isNull);
    });

    test('returns null when no biller matches', () {
      expect(meta.billerFor(99), isNull);
    });
  });

  group('CatalogueProduct', () {
    final json = {
      'id': 2,
      'name': 'KENYAN MUTTON',
      'code': 'KEN001',
      'category': 'Meat',
      'unit': {
        'id': 4,
        'name': 'KG',
        'code': 'kg',
        'compatible_units': [
          {
            'id': 4,
            'unit_name': 'KG',
            'unit_code': 'kg',
            'operator': '*',
            'operation_value': 1,
          },
        ],
      },
      'pricing': {
        'base_price': 250.0,
        'resolved_price': 225.0,
        'discount_source': 'discount_plan',
        'discount_name': 'VIP 10%',
        'tax_rate': 5.0,
        'tax_method': 'exclusive',
      },
      'stock': {'warehouse_id': 3, 'qty': 40.0},
    };

    test('parses the documented shape', () {
      final p = CatalogueProduct.fromJson(json);

      expect(p.id, 2);
      expect(p.name, 'KENYAN MUTTON');
      expect(p.unit?.name, 'KG');
      expect(p.stock, 40.0);
      expect(p.pricing.resolvedPrice, 225.0);
      expect(p.inStock, isTrue);
    });

    test('reads compatible_units, which use unit_name not name', () {
      final p = CatalogueProduct.fromJson(json);

      expect(p.compatibleUnits, hasLength(1));
      expect(p.compatibleUnits.first.name, 'KG');
      expect(p.sellableUnits.first.name, 'KG');
    });

    test('flags a genuine discount but not an equal price', () {
      expect(CatalogueProduct.fromJson(json).pricing.isDiscounted, isTrue);

      final undiscounted = CatalogueProduct.fromJson({
        ...json,
        'pricing': {
          'base_price': 250.0,
          'resolved_price': 250.0,
          'discount_source': null,
        },
      });
      expect(undiscounted.pricing.isDiscounted, isFalse);
    });

    test('defaults per-piece weights to zero when absent', () {
      // product-search does not currently return these, so the piece-count
      // shortcut must stay hidden rather than deriving from zeros.
      final p = CatalogueProduct.fromJson(json);

      expect(p.perPieceGrossWeight, 0);
      expect(p.hasPerPieceWeights, isFalse);
    });

    test('reads per-piece weights when the server does send them', () {
      final p = CatalogueProduct.fromJson({
        ...json,
        'per_piece_gross_weight': 250.0,
        'per_piece_waste': 15.0,
      });

      expect(p.hasPerPieceWeights, isTrue);
      expect(p.perPieceGrossWeight, 250.0);
    });

    test('survives a minimal payload', () {
      final p = CatalogueProduct.fromJson({'id': 1, 'name': 'X'});

      expect(p.unit, isNull);
      expect(p.stock, 0);
      expect(p.inStock, isFalse);
      expect(p.pricing.resolvedPrice, 0);
      expect(p.sellableUnits, isEmpty);
    });
  });

  group('CatalogueCustomer', () {
    test('parses the documented shape', () {
      final c = CatalogueCustomer.fromJson({
        'id': 1,
        'name': 'Walk in',
        'phone_number': null,
        'is_default': true,
      });

      expect(c.id, 1);
      expect(c.isDefault, isTrue);
      expect(c.subtitle, isNull);
    });

    test('builds a subtitle from whichever fields exist', () {
      final c = CatalogueCustomer.fromJson({
        'id': 2,
        'name': 'Ahmed',
        'phone_number': '0501234567',
        'company_name': 'Acme',
      });

      expect(c.subtitle, contains('0501234567'));
      expect(c.subtitle, contains('Acme'));
    });
  });
}
