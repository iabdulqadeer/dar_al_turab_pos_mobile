import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dar_al_turab_pos/data/models/catalogue.dart';
import 'package:dar_al_turab_pos/features/pos/presentation/widgets/product_search_sheet.dart';
import 'package:dar_al_turab_pos/features/pos/providers/pos_providers.dart';

CatalogueProduct _simpleProduct() => CatalogueProduct(
      id: 1,
      name: 'Test Widget',
      code: 'TW1',
      // A per-piece unit → not weight-based, so the details form only needs
      // quantity + price, both pre-filled valid by CartLine.fromProduct.
      unit: SaleUnit(id: 2, name: 'PC'),
      pricing: const ProductPricing(
        basePrice: 10,
        resolvedPrice: 10,
        taxRate: 0,
      ),
      stock: 100,
    );

/// Host with a button that opens the product search sheet, mirroring the POS
/// screen's `_openProductSearch`.
class _Host extends StatelessWidget {
  const _Host();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Builder(
          builder: (ctx) => ElevatedButton(
            onPressed: () => showModalBottomSheet<void>(
              context: ctx,
              isScrollControlled: true,
              builder: (_) => const ProductSearchSheet(),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
  }
}

void main() {
  Widget harness() => ProviderScope(
        overrides: [
          productSearchProvider.overrideWith((ref) async => [_simpleProduct()]),
          saleTaxRateProvider.overrideWithValue(0),
          saleFormMetadataProvider.overrideWith(
            (ref) => Completer<SaleFormMetadata>().future,
          ),
        ],
        child: const MaterialApp(home: _Host()),
      );

  testWidgets(
    'tapping Done on the details form closes only the editor — the product '
    'search sheet stays open (aug_23 #2 / aug_25 #1)',
    (tester) async {
      await tester.pumpWidget(harness());

      // Open the product search sheet.
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Add product'), findsOneWidget); // sheet header
      expect(find.text('Test Widget'), findsOneWidget); // the one result

      // Pick the product → the details editor opens over the search sheet.
      await tester.tap(find.text('Test Widget'));
      await tester.pumpAndSettle();
      expect(find.text('Done'), findsOneWidget);

      // Tap Done.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();

      // The editor is gone…
      expect(find.text('Done'), findsNothing);
      // …but the product search sheet is STILL open (its header is present),
      // so the cashier can immediately pick the next product.
      expect(find.text('Add product'), findsOneWidget);

      // Drain the "added to the sale" toast's auto-dismiss timer so it does
      // not outlive the test.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
    },
  );
}
