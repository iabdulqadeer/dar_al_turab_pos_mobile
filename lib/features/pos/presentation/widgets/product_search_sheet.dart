import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/formatting.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_message.dart';
import '../../../../core/widgets/sheet_header.dart';
import '../../../../data/models/catalogue.dart';
import '../../domain/cart.dart';
import '../../providers/pos_providers.dart';
import 'barcode_scanner_sheet.dart';
import 'cart_line_editor.dart';

/// Product search box with an inline barcode scan button. Feeds the shared
/// [productSearchQueryProvider], so it drives both the New Sale results and any
/// [ProductSearchSheet].
class ProductSearchField extends StatelessWidget {
  const ProductSearchField({
    required this.controller,
    required this.onChanged,
    super.key,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search products by name, code or barcode',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder(
                valueListenable: controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          controller.clear();
                          onChanged('');
                        },
                      ),
              ),
              IconButton(
                icon: const Icon(Icons.qr_code_scanner, size: 20),
                tooltip: 'Scan barcode',
                onPressed: () => _scan(context),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Scanning just fills the search box — `/sales/product-search` already
  /// matches barcodes, so there is no separate lookup path to maintain.
  Future<void> _scan(BuildContext context) async {
    final code = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const BarcodeScannerSheet(),
    );

    if (code != null && code.isNotEmpty) {
      controller.text = code;
      onChanged(code);
    }
  }
}

/// The product results list. A tap is delegated to [onProductTap] — the sheet
/// opens the product-details form and only then commits the line.
class ProductResults extends ConsumerWidget {
  const ProductResults({required this.onProductTap, super.key});

  final void Function(CatalogueProduct product) onProductTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final results = ref.watch(productSearchProvider);
    final theme = Theme.of(context);

    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Could not load products.\n$error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      ),
      data: (products) {
        if (products.isEmpty) {
          // Before the cashier has typed, guide them; only call it "not found"
          // once a search has actually returned nothing.
          final searching =
              ref.watch(productSearchQueryProvider).trim().isNotEmpty;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    searching
                        ? Icons.search_off_outlined
                        : Icons.storefront_outlined,
                    size: 48,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    searching ? 'No products found' : 'Start a sale',
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    searching
                        ? 'Try a different name, code or barcode.'
                        : 'Search a product by name, code or barcode '
                              'to add it to the sale.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          itemCount: products.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final product = products[index];
            return _ProductTile(
              product: product,
              onTap: () => onProductTap(product),
            );
          },
        );
      },
    );
  }
}

/// A full-height modal sheet wrapping [ProductSearchField] + [ProductResults],
/// used to add items to an in-progress sale.
///
/// Tapping a product opens the product-details form first; the line is only
/// committed once its details are entered and confirmed, then the sheet stays
/// open so more products can be added in one flow.
///
/// By default commits go to the global New-Sale cart. The Edit Sale screen
/// supplies [onAddLine]/[existingLineFor] to target its own local cart instead.
class ProductSearchSheet extends ConsumerStatefulWidget {
  const ProductSearchSheet({this.onAddLine, this.existingLineFor, super.key});

  /// Commits a confirmed line. Null → the global New-Sale cart.
  final void Function(CartLine line)? onAddLine;

  /// Returns the line already present for [product], so a re-tap edits it
  /// rather than duplicating it. Null → look in the global cart.
  final CartLine? Function(CatalogueProduct product)? existingLineFor;

  @override
  ConsumerState<ProductSearchSheet> createState() => _ProductSearchSheetState();
}

class _ProductSearchSheetState extends ConsumerState<ProductSearchSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Opens the product-details form for the tapped product and only commits the
  /// line once it is filled in and confirmed. Cancelling adds nothing and
  /// returns to the list; a re-tap of an already-added product edits it.
  Future<void> _handleTap(CatalogueProduct product) async {
    final rate = ref.read(saleTaxRateProvider);
    final existing = (widget.existingLineFor ?? _globalExisting)(product);
    final line = existing?.copy() ?? (CartLine.fromProduct(product)..taxRate = rate);

    final confirmed = await showModalBottomSheet<CartLine>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CartLineEditor(line: line),
    );
    if (confirmed == null || !mounted) return;

    // Keep the line on the current global tax rate regardless of what it was
    // opened with.
    confirmed.taxRate = rate;
    (widget.onAddLine ?? _globalCommit)(confirmed);

    // A brief confirmation. showAppMessage renders in the root overlay, so it
    // survives closing the sheets below.
    showAppMessage(
      context,
      existing == null
          ? '${product.name} added to the sale'
          : '${product.name} updated',
      kind: AppMessageKind.success,
    );

    // Once the product's details are confirmed, close the product-search sheet
    // too (the details editor has already popped itself), returning the cashier
    // to the sale screen — one product added per open of the search
    // (product-owner request, 2026-08-27).
    if (mounted) Navigator.pop(context);
  }

  CartLine? _globalExisting(CatalogueProduct product) {
    final lines = ref.read(cartProvider).lines;
    final index = lines.indexWhere((l) => l.product.id == product.id);
    return index >= 0 ? lines[index] : null;
  }

  void _globalCommit(CartLine line) =>
      ref.read(cartProvider.notifier).upsertLine(line);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            SheetHeader(
              title: 'Add product',
              onBack: () => Navigator.pop(context),
            ),
            ProductSearchField(
              controller: _controller,
              onChanged: (value) =>
                  ref.read(productSearchQueryProvider.notifier).set(value),
            ),
            Expanded(child: ProductResults(onProductTap: _handleTap)),
          ],
        ),
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});

  final CatalogueProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pricing = product.pricing;

    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      title: Text(
        product.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: product.subtitle.isEmpty
          ? null
          : Text(
              product.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Format.amount(pricing.resolvedPrice),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          // Show the struck-through base price only when a discount plan or
          // promotion actually changed it.
          if (pricing.isDiscounted)
            Text(
              Format.amount(pricing.basePrice),
              style: theme.textTheme.labelSmall?.copyWith(
                decoration: TextDecoration.lineThrough,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }
}