import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/formatting.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/catalogue.dart';
import '../../../data/models/sale.dart';
import '../../dashboard/providers/dashboard_providers.dart';
import '../../sales/providers/sales_providers.dart';
import '../domain/cart.dart';
import '../providers/pos_providers.dart';
import 'widgets/cart_line_editor.dart';

/// Loads a sale's edit form and lets its lines be corrected.
///
/// Scoped deliberately to what `PUT /sales/{id}` supports: line quantities,
/// prices, weights, and removal. Payments are not touched here — money on an
/// existing sale goes through the payments sub-resource, and the update
/// endpoint accepts no payment block at all.
class EditSaleScreen extends ConsumerStatefulWidget {
  const EditSaleScreen({required this.saleId, super.key});

  final int saleId;

  @override
  ConsumerState<EditSaleScreen> createState() => _EditSaleScreenState();
}

class _EditSaleScreenState extends ConsumerState<EditSaleScreen> {
  Cart? _cart;
  SaleDetail? _sale;

  Object? _loadError;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });

    try {
      final form = await ref
          .read(catalogueApiProvider)
          .editForm(widget.saleId);
      final sale = SaleDetail.fromJson(form.saleJson);

      setState(() {
        // form.metadata carries billers, banks and payment methods. This
        // screen edits lines only — the sale's own customer and biller come
        // from the sale itself — so the bundle is deliberately unused.
        _sale = sale;
        _cart = Cart(
          lines: sale.items
              .map((i) => CartLine.fromSaleItem(i))
              .toList(),
          // The sale's own customer and biller, rebuilt from the detail so
          // the header reads correctly without a second lookup.
          customer: sale.customer == null
              ? null
              : CatalogueCustomer(
                  id: sale.customer!.id ?? 0,
                  name: sale.customer!.name,
                  phoneNumber: sale.customer!.phone,
                  address: sale.customer!.address,
                  trnNumber: sale.customer!.trnNumber,
                ),
          biller: sale.biller == null
              ? null
              : NamedRef(
                  id: sale.biller!.id ?? 0,
                  name: sale.biller!.name,
                ),
          orderDiscount: sale.totals.orderDiscount,
          shippingCost: sale.totals.shippingCost,
          // Preserve how this sale was originally rounded, or editing a line
          // would silently change the total by up to a dirham.
          removeDecimalAmount: sale.totals.grandTotal ==
              sale.totals.grandTotal.floorToDouble(),
        );
        _loading = false;
      });
    } on Object catch (e) {
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cart = _cart;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _sale == null ? 'Edit sale' : 'Edit ${_sale!.referenceNo}',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _loadError != null
          ? _LoadError(error: _loadError!, onRetry: _load)
          : cart == null
          ? const SizedBox.shrink()
          : _body(cart),
      bottomNavigationBar: cart == null || _loadError != null
          ? null
          : _SaveBar(cart: cart, saving: _saving, onSave: _save),
    );
  }

  Widget _body(Cart cart) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Container(
          width: double.infinity,
          color: AppColors.primary.withValues(alpha: 0.06),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                cart.customer?.name ?? '-',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'Paid ${Format.amount(_sale!.totals.paidAmount)}'
                '  ·  editing lines only',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        if (cart.isEmpty)
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Text(
                  'Every line has been removed.\n'
                  'A sale needs at least one item, so add one back or cancel.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            ),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: cart.lines.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final line = cart.lines[index];

                return ListTile(
                  title: Text(
                    line.product.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    '${Format.quantity(line.qty)} ${line.unit?.name ?? ''}'
                    ' × ${Format.amount(line.unitPrice)}',
                    style: theme.textTheme.bodySmall,
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        Format.amount(line.subtotal),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: AppColors.error,
                        ),
                        tooltip: 'Remove line',
                        onPressed: () => setState(() {
                          cart.lines.removeAt(index);
                        }),
                      ),
                    ],
                  ),
                  onTap: () => _editLine(cart, index),
                );
              },
            ),
          ),
      ],
    );
  }

  Future<void> _editLine(Cart cart, int index) async {
    final edited = await showModalBottomSheet<CartLine>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CartLineEditor(line: cart.lines[index].copy()),
    );

    if (edited != null) {
      setState(() => cart.lines[index] = edited);
    }
  }

  Future<void> _save() async {
    final cart = _cart;
    final sale = _sale;
    if (cart == null || sale == null) return;

    final error = cart.validationError;
    if (error != null) {
      _toast(error, isError: true);
      return;
    }

    setState(() => _saving = true);

    try {
      await ref.read(salesApiProvider).update(
            widget.saleId,
            cart.toUpdateJson(
              saleStatus: sale.saleStatus?.value ?? 1,
              // Recomputed server-side from paid vs grand total; sending the
              // sale's current status keeps a non-POS edit consistent.
              paymentStatus: sale.paymentStatus?.value ?? 1,
              paidAmount: sale.totals.paidAmount,
            ),
          );

      ref.invalidate(saleDetailProvider(widget.saleId));
      ref.invalidate(salesListProvider);
      ref.invalidate(dashboardRecentProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
      _toast('Sale ${sale.referenceNo} updated.');
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast(_messageFor(e), isError: true);
    }
  }

  String _messageFor(ApiException e) {
    return switch (e.code) {
      ApiErrorCode.insufficientStock =>
        'Not enough stock for one or more lines. Lower the quantity and retry.',
      ApiErrorCode.unknownSaleUnit =>
        'A line has an unrecognised unit. Open it and pick a unit.',
      ApiErrorCode.forbidden =>
        'You are not allowed to edit this sale.',
      _ => e.message,
    };
  }

  void _toast(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? AppColors.error : null,
        ),
      );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.cart,
    required this.saving,
    required this.onSave,
  });

  final Cart cart;
  final bool saving;
  final VoidCallback onSave;

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
                    'New total',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    Format.amount(cart.grandTotal),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
            FilledButton.icon(
              onPressed: saving || cart.isEmpty ? null : onSave,
              icon: saving
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check),
              label: Text(saving ? 'Saving…' : 'Save changes'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(150, AppSpacing.minTouchTarget),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final api = error is ApiException ? error as ApiException : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              api?.code == ApiErrorCode.forbidden
                  ? 'You are not allowed to edit this sale'
                  : 'Could not load this sale',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              api?.message ?? '$error',
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
