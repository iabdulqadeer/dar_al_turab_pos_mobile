import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/extensions/formatting.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_message.dart';
import '../../../data/models/catalogue.dart';
import '../../../data/models/sale.dart';
import '../../auth/providers/auth_providers.dart';
import '../../branding/providers/branding_providers.dart';
import '../../dashboard/providers/dashboard_providers.dart';
import '../../sales/providers/sales_providers.dart';
import '../domain/cart.dart';
import '../providers/pos_providers.dart';
import 'widgets/cart_line_editor.dart';
import 'widgets/customer_picker.dart';
import 'widgets/product_search_sheet.dart';
import 'widgets/sale_context_bar.dart';

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
  SaleFormMetadata? _meta;

  Object? _loadError;
  bool _loading = true;
  bool _saving = false;

  /// Warehouse/biller editable for an admin or a non-admin with no fixed
  /// biller; otherwise locked to the account's values.
  bool get _contextEditable {
    final user = ref.read(currentUserProvider);
    if (user == null) return false;
    return user.isAdmin || user.billerId == null;
  }

  @override
  void initState() {
    super.initState();
    // Pull the global tax rate fresh from /settings/general, same as the New
    // Sale screen, so lines are re-taxed at the current rate while editing.
    // Best-effort; the saleTaxRateProvider listener applies it when it lands.
    Future.microtask(
      () => ref.read(brandingProvider.notifier).refresh(),
    );
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

      // Re-tax every line at the current global rate (from /settings/general),
      // rather than the rate frozen on the sale — so an edit recalculates tax
      // exactly like the New Sale screen does.
      final taxRate = ref.read(saleTaxRateProvider);

      setState(() {
        // form.metadata carries the warehouse + biller options for the
        // context bar; banks/payment methods in it are unused here.
        _meta = form.metadata;
        _sale = sale;
        _cart = Cart(
          lines: sale.items
              .map((i) => CartLine.fromSaleItem(i)..taxRate = taxRate)
              .toList(),
          // The sale's own customer, biller and warehouse, rebuilt from the
          // detail so the header reads correctly without a second lookup.
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
          warehouse: sale.warehouse == null
              ? null
              : NamedRef(
                  id: sale.warehouse!.id ?? 0,
                  name: sale.warehouse!.name,
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

    // When the fresh tax rate lands after the sale has loaded, re-tax the
    // existing lines so the totals reflect it without a reload.
    ref.listen(saleTaxRateProvider, (previous, next) {
      final current = _cart;
      if (current == null) return;
      setState(() {
        for (final line in current.lines) {
          line.taxRate = next;
        }
      });
    });

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
      floatingActionButton: cart == null || _loadError != null
          ? null
          : FloatingActionButton(
              onPressed: () => _addProduct(cart),
              tooltip: 'Add item',
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _body(Cart cart) {
    final theme = Theme.of(context);

    return Column(
      children: [
        Material(
          color: AppColors.primary.withValues(alpha: 0.06),
          child: InkWell(
            onTap: () => _changeCustomer(cart),
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
                        Text(
                          'Paid ${Format.amount(_sale!.totals.paidAmount)}'
                          '  ·  tap to change customer',
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
        ),
        if (_meta != null)
          SaleContextBar(
            warehouses: _meta!.warehouses,
            billers: _meta!.billers,
            warehouse: cart.warehouse,
            biller: cart.biller,
            editable: _contextEditable,
            onWarehouseChanged: (w) => setState(() => cart.warehouse = w),
            onBillerChanged: (b) => setState(() => cart.biller = b),
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
      // Keep the line on the current global rate; the edited copy carries
      // whatever rate it was opened with.
      edited.taxRate = ref.read(saleTaxRateProvider);
      setState(() => cart.lines[index] = edited);
    }
  }

  /// Swaps the sale's customer, reusing the New Sale picker against this
  /// screen's local cart.
  Future<void> _changeCustomer(Cart cart) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => CustomerPicker(
        onSelected: (customer) => setState(() => cart.customer = customer),
      ),
    );
  }

  /// Appends a new line via the shared product search, seeding it with the
  /// current tax rate. The sheet stays open so several items can be added.
  Future<void> _addProduct(Cart cart) async {
    final rate = ref.read(saleTaxRateProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductSearchSheet(
        onSelected: (product) => setState(
          () => cart.lines.add(CartLine.fromProduct(product)..taxRate = rate),
        ),
      ),
    );
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
      // Toast before popping so it shows via the still-mounted context; the
      // root-overlay message persists after this screen leaves.
      _toast('Sale ${sale.referenceNo} updated.');
      Navigator.of(context).pop();
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
    showAppMessage(
      context,
      message,
      kind: isError ? AppMessageKind.error : AppMessageKind.success,
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
