import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dar_al_turab_pos/data/models/catalogue.dart';
import 'package:dar_al_turab_pos/features/pos/domain/cart.dart';
import 'package:dar_al_turab_pos/features/pos/providers/pos_providers.dart';

CartLine line({
  required int productId,
  required String name,
  double qty = 1,
}) {
  return CartLine(
    product: CatalogueProduct(
      id: productId,
      name: name,
      unit: SaleUnit(id: 1, name: 'KG'),
      pricing: const ProductPricing(
        basePrice: 10,
        resolvedPrice: 10,
        taxRate: 0,
      ),
      stock: 100,
    ),
    unit: SaleUnit(id: 1, name: 'KG'),
    unitPrice: 10,
    qty: qty,
  );
}

void main() {
  // Keep the controller off the network: it listens to the form metadata and
  // tax providers on build, so stub both.
  ProviderContainer makeContainer() => ProviderContainer(
    overrides: [
      saleTaxRateProvider.overrideWithValue(0),
      saleFormMetadataProvider.overrideWith(
        (ref) => Completer<SaleFormMetadata>().future,
      ),
    ],
  );

  group('CartController.upsertLine', () {
    test('appends a line for a product not yet in the cart', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final controller = container.read(cartProvider.notifier);

      controller.upsertLine(line(productId: 1, name: 'Beef'));
      controller.upsertLine(line(productId: 2, name: 'Chicken'));

      expect(container.read(cartProvider).lines.length, 2);
    });

    test('replaces the existing line for the same product — no duplicate', () {
      final container = makeContainer();
      addTearDown(container.dispose);
      final controller = container.read(cartProvider.notifier);

      controller.upsertLine(line(productId: 1, name: 'Beef', qty: 3));
      controller.upsertLine(line(productId: 1, name: 'Beef', qty: 9));

      final lines = container.read(cartProvider).lines;
      expect(lines.length, 1);
      expect(lines.single.qty, 9);
    });
  });
}
