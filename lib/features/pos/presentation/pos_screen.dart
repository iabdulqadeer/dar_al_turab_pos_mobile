import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/formatting.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_message.dart';
import '../../../data/models/catalogue.dart';
import '../../branding/providers/branding_providers.dart';
import '../domain/cart.dart';
import '../providers/pos_providers.dart';
import 'widgets/cart_line_editor.dart';
import 'widgets/customer_picker.dart';
import 'widgets/payment_sheet.dart';
import 'widgets/product_search_sheet.dart';

class PosScreen extends ConsumerStatefulWidget {
  const PosScreen({super.key});

  @override
  ConsumerState<PosScreen> createState() => _PosScreenState();
}

class _PosScreenState extends ConsumerState<PosScreen> {
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Pull the global tax rate fresh from /settings/general at the start of
    // every sale, so it is current (not a stale cache) and clearly
    // endpoint-sourced. Best-effort: refresh() swallows failures and keeps the
    // cached value; the cart's saleTaxRateProvider listener applies the rate to
    // lines when it arrives.
    Future.microtask(
      () => ref.read(brandingProvider.notifier).refresh(),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final metadata = ref.watch(saleFormMetadataProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('New sale'),
        actions: [
          if (!cart.isEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Clear cart',
              onPressed: _confirmClear,
            ),
        ],
      ),
      body: metadata.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _MetadataError(
          error: error,
          onRetry: () => ref.invalidate(saleFormMetadataProvider),
        ),
        data: (meta) => Column(
          children: [
            _CustomerBar(cart: cart, meta: meta),
            ProductSearchField(
              controller: _searchController,
              onChanged: (value) =>
                  ref.read(productSearchQueryProvider.notifier).set(value),
            ),
            Expanded(
              child: cart.isEmpty
                  ? const ProductResults()
                  : _CartList(cart: cart),
            ),
          ],
        ),
      ),
      bottomNavigationBar: cart.isEmpty
          ? null
          : _CheckoutBar(cart: cart, onCheckout: _checkout),
      floatingActionButton: cart.isEmpty
          ? null
          : FloatingActionButton(
              onPressed: _openProductSearch,
              tooltip: 'Add item',
              child: const Icon(Icons.add),
            ),
    );
  }

  Future<void> _openProductSearch() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ProductSearchSheet(),
    );
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear cart?'),
        content: const Text('This removes every item from the current sale.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (ok ?? false) ref.read(cartProvider.notifier).clearLines();
  }

  Future<void> _checkout() async {
    final cart = ref.read(cartProvider);

    final error = cart.validationError;
    if (error != null) {
      _toast(error, isError: true);
      return;
    }

    // No stock-availability gate (flutter_app_issues #6): the sale proceeds
    // regardless of recorded stock, and the server no longer rejects on it.
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const PaymentSheet(),
    );
  }

  void _toast(String message, {bool isError = false}) {
    showAppMessage(
      context,
      message,
      kind: isError ? AppMessageKind.error : AppMessageKind.info,
    );
  }
}

class _CustomerBar extends ConsumerWidget {
  const _CustomerBar({required this.cart, required this.meta});

  final Cart cart;
  final SaleFormMetadata meta;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Material(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: InkWell(
        onTap: () => showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          builder: (_) => const CustomerPicker(),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cart.customer?.name ?? 'Choose a customer',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (cart.biller != null)
                      Text(
                        'Biller: ${cart.biller!.name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              const Icon(Icons.expand_more, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class _CartList extends ConsumerWidget {
  const _CartList({required this.cart});

  final Cart cart;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl * 2),
      itemCount: cart.lines.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final line = cart.lines[index];

        return Dismissible(
          key: ValueKey('${line.product.id}-$index'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            color: AppColors.error,
            padding: const EdgeInsets.only(right: AppSpacing.lg),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          onDismissed: (_) =>
              ref.read(cartProvider.notifier).removeLine(index),
          child: _CartLineTile(
            line: line,
            onTap: () async {
              final edited = await showModalBottomSheet<CartLine>(
                context: context,
                isScrollControlled: true,
                builder: (_) => CartLineEditor(line: line.copy()),
              );
              if (edited != null) {
                ref.read(cartProvider.notifier).replaceLine(index, edited);
              }
            },
          ),
        );
      },
    );
  }
}

class _CartLineTile extends StatelessWidget {
  const _CartLineTile({required this.line, required this.onTap});

  final CartLine line;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasWeight = line.noOfPcs > 0 || line.grossWeight > 0;

    return ListTile(
      onTap: onTap,
      title: Text(
        line.product.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${Format.quantity(line.qty)} ${line.unit?.name ?? ''}'
            ' × ${Format.amount(line.unitPrice)}',
            style: theme.textTheme.bodySmall,
          ),
          if (hasWeight)
            Text(
              'Pcs ${Format.quantity(line.noOfPcs)}  ·  '
              'G.Wt ${Format.quantity(line.grossWeight)}  ·  '
              'Waste ${Format.quantity(line.wasteQty)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: Text(
        Format.amount(line.subtotal),
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CheckoutBar extends StatelessWidget {
  const _CheckoutBar({required this.cart, required this.onCheckout});

  final Cart cart;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(top: BorderSide(color: theme.colorScheme.outline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${cart.itemCount} item${cart.itemCount == 1 ? '' : 's'}'
                    '  ·  tax ${Format.amount(cart.totalTax)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    Format.amount(cart.grandTotal),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: onCheckout,
              icon: const Icon(Icons.point_of_sale),
              label: const Text('Continue'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(140, AppSpacing.minTouchTarget),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetadataError extends StatelessWidget {
  const _MetadataError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              'Could not load the sale form',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$error',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}
