import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/formatting.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/models/auth_user.dart';
import '../../../data/models/sale.dart';
import '../../auth/providers/auth_providers.dart';
import '../../dashboard/providers/dashboard_providers.dart';
import '../../pos/providers/pos_providers.dart';
import '../../printing/printer_transport.dart';
import '../../printing/providers/printer_providers.dart';
import '../providers/sales_providers.dart';
import 'receipt_preview_screen.dart';
import 'widgets/add_payment_sheet.dart';
import 'widgets/status_chip.dart';

class SaleDetailScreen extends ConsumerStatefulWidget {
  const SaleDetailScreen({required this.saleId, super.key});

  final int saleId;

  @override
  ConsumerState<SaleDetailScreen> createState() => _SaleDetailScreenState();
}

class _SaleDetailScreenState extends ConsumerState<SaleDetailScreen> {
  bool _printing = false;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(saleDetailProvider(widget.saleId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sale'),
        actions: [
          IconButton(
            icon: const Icon(Icons.preview_outlined),
            tooltip: 'Print preview',
            onPressed: detail.hasValue && !_printing ? _openPreview : null,
          ),
          IconButton(
            icon: _printing
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined),
            tooltip: 'Print receipt',
            onPressed: detail.hasValue && !_printing ? _print : null,
          ),
          if (detail.hasValue) _actionsMenu(detail.requireValue),
        ],
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _DetailError(
          error: error,
          onRetry: () => ref.invalidate(saleDetailProvider(widget.saleId)),
        ),
        data: (sale) => _DetailBody(
          sale: sale,
          onEditPayment: (p) => _addOrEditPayment(sale, existing: p),
          onDeletePayment: (p) => _deletePayment(sale, p),
        ),
      ),
      floatingActionButton: _settleButton(detail),
    );
  }

  /// Settling a due invoice is the most common follow-up action, so it gets a
  /// FAB rather than being buried in the overflow menu.
  Widget? _settleButton(AsyncValue<SaleDetail> detail) {
    final sale = detail.value;
    if (sale == null || sale.totals.due <= 0.004) return null;
    if (!(ref.watch(currentUserProvider)?.can(Permissions.salesEdit) ??
        false)) {
      return null;
    }

    return FloatingActionButton.extended(
      onPressed: () => _addOrEditPayment(sale),
      icon: const Icon(Icons.payments_outlined),
      label: Text('Settle ${Format.amount(sale.totals.due)}'),
    );
  }

  Widget _actionsMenu(SaleDetail sale) {
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.can(Permissions.salesEdit) ?? false;
    final canDelete = user?.can(Permissions.salesDelete) ?? false;

    // Never render a menu whose every entry would 403.
    if (!canEdit && !canDelete) return const SizedBox.shrink();

    return PopupMenuButton<String>(
      onSelected: (value) => switch (value) {
        'edit' => _editSale(sale),
        'payment' => _addOrEditPayment(sale),
        'delete' => _deleteSale(sale),
        _ => null,
      },
      itemBuilder: (context) => [
        if (canEdit)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit sale'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canEdit)
          const PopupMenuItem(
            value: 'payment',
            child: ListTile(
              leading: Icon(Icons.payments_outlined),
              title: Text('Add payment'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canDelete)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text(
                'Delete sale',
                style: TextStyle(color: AppColors.error),
              ),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  void _editSale(SaleDetail sale) {
    context.push('${Routes.sales}/${sale.id}/edit');
  }

  Future<void> _addOrEditPayment(
    SaleDetail sale, {
    SalePayment? existing,
  }) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => AddPaymentSheet(
        saleId: sale.id,
        outstanding: sale.totals.due,
        existing: existing,
      ),
    );

    if (saved ?? false) {
      _refreshEverything();
      if (mounted) _toast('Payment recorded.');
    }
  }

  Future<void> _deletePayment(SaleDetail sale, SalePayment payment) async {
    final ok = await _confirm(
      title: 'Remove payment?',
      message:
          'This removes ${Format.amount(payment.paidAmount)} from the invoice, '
          'increasing the amount due.',
      confirmLabel: 'Remove',
    );
    if (!ok) return;

    try {
      await ref
          .read(salePaymentsApiProvider)
          .remove(sale.id, payment.id!);
      _refreshEverything();
      if (mounted) _toast('Payment removed.');
    } on ApiException catch (e) {
      if (mounted) _toast(e.message, isError: true);
    }
  }

  Future<void> _deleteSale(SaleDetail sale) async {
    final ok = await _confirm(
      title: 'Delete this sale?',
      message:
          'Sale ${sale.referenceNo} will be removed and its stock returned to '
          'the warehouse. This cannot be undone.',
      confirmLabel: 'Delete',
    );
    if (!ok) return;

    try {
      await ref.read(salesApiProvider).destroy(sale.id);
      _refreshEverything();
      if (!mounted) return;
      context.pop();
      _toast('Sale ${sale.referenceNo} deleted.');
    } on ApiException catch (e) {
      if (mounted) _toast(e.message, isError: true);
    }
  }

  /// A money change touches the sale, the list, and the dashboard totals.
  void _refreshEverything() {
    ref.invalidate(saleDetailProvider(widget.saleId));
    ref.invalidate(salesListProvider);
    ref.invalidate(dashboardRecentProvider);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    return result ?? false;
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

  Future<void> _print() async {
    final unsupported = ref.read(printingUnsupportedReasonProvider);
    if (unsupported != null) {
      _showMessage(unsupported, isError: true);
      return;
    }

    final printerState = ref.read(printerControllerProvider);
    if (!printerState.hasPrinter) {
      _showMessage(
        'No printer paired. Set one up in Printer settings first.',
        isError: true,
      );
      return;
    }

    setState(() => _printing = true);

    try {
      // Reconnect first: Bluetooth links drop when the phone sleeps, and a
      // stale "connected" flag would otherwise fail mid-print.
      await ref.read(printerControllerProvider.notifier).reconnect();

      final saved = printerState.saved!;
      // Ask the server to lay the body out at the centred content width, then
      // print it shifted right by the margin so both sides have room.
      final document = await ref
          .read(salesApiProvider)
          .receipt(widget.saleId, charactersPerLine: saved.contentWidth);

      await ref
          .read(receiptPrinterProvider)
          .printReceipt(
            document,
            copies: _receiptCopies,
            contentWidth: saved.contentWidth,
            leftMargin: saved.leftMargin,
          );

      if (!mounted) return;
      _showMessage('Receipt sent to ${saved.name}.');
    } on PrintException catch (e) {
      if (mounted) _showMessage('${e.message} ${e.remedy}', isError: true);
    } on ApiException catch (e) {
      if (mounted) _showMessage(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _openPreview() {
    final unsupported = ref.read(printingUnsupportedReasonProvider);
    if (unsupported != null) {
      _showMessage(unsupported, isError: true);
      return;
    }
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ReceiptPreviewScreen(saleId: widget.saleId),
      ),
    );
  }

  /// One physical print. The server's SaleReceiptFormatter now emits both the
  /// CUSTOMER COPY and COMPANY COPY (labelled) inside a single lines[] payload,
  /// so printing more than once would duplicate the pair.
  static const _receiptCopies = 1;

  void _showMessage(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: isError ? 6 : 3),
          backgroundColor: isError
              ? Theme.of(context).colorScheme.error
              : null,
        ),
      );
  }
}

class _DetailBody extends StatelessWidget {
  const _DetailBody({
    required this.sale,
    required this.onEditPayment,
    required this.onDeletePayment,
  });

  final SaleDetail sale;
  final void Function(SalePayment) onEditPayment;
  final void Function(SalePayment) onDeletePayment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _HeaderCard(sale: sale),
        const SizedBox(height: AppSpacing.md),

        _SectionCard(
          title: 'Items',
          icon: Icons.inventory_2_outlined,
          child: Column(
            children: [
              for (final item in sale.items) _ItemRow(item: item),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.md),

        _SectionCard(
          title: 'Totals',
          icon: Icons.receipt_long_outlined,
          child: Column(
            children: [
              _TotalRow('Sub Total', sale.totals.subTotal),
              _TotalRow('Total Tax', sale.totals.totalTax),
              if (sale.totals.totalDiscount + sale.totals.orderDiscount > 0)
                _TotalRow(
                  'Discount',
                  sale.totals.totalDiscount + sale.totals.orderDiscount,
                ),
              if (sale.totals.ipDiscount > 0)
                _TotalRow('IP Discount', sale.totals.ipDiscount),
              if (sale.totals.shippingCost > 0)
                _TotalRow('Shipping', sale.totals.shippingCost),
              const Divider(height: AppSpacing.lg),
              _TotalRow('Grand Total', sale.totals.grandTotal, emphasis: true),
              _TotalRow('Paid', sale.totals.paidAmount),
              if (sale.totals.returnAdjustment > 0)
                _TotalRow('Return Adjustment', sale.totals.returnAdjustment),
              if (sale.totals.partySupportAdjustment > 0)
                _TotalRow(
                  'Party Support',
                  sale.totals.partySupportAdjustment,
                ),
              _TotalRow(
                'Due',
                sale.totals.due,
                emphasis: true,
                color: sale.totals.due > 0.004 ? AppColors.error : null,
              ),
            ],
          ),
        ),

        if (sale.payments.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _SectionCard(
            title: 'Payments',
            icon: Icons.payments_outlined,
            child: Column(
              children: [
                for (final payment in sale.payments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(
                      payment.referenceNumber ?? 'Payment',
                      style: theme.textTheme.bodyMedium,
                    ),
                    subtitle: Text(
                      Format.dateTime(payment.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Format.amount(payment.paidAmount),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        // Editing needs the payment's id to address it; the
                        // list endpoint always supplies one, but a defensive
                        // check keeps a malformed row from crashing the menu.
                        if (payment.id != null)
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 18),
                            onSelected: (v) => v == 'edit'
                                ? onEditPayment(payment)
                                : onDeletePayment(payment),
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(
                                value: 'delete',
                                child: Text(
                                  'Remove',
                                  style: TextStyle(color: AppColors.error),
                                ),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],

        const SizedBox(height: AppSpacing.xl),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.sale});

  final SaleDetail sale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              sale.referenceNo,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              Format.dateTime(sale.date),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              children: [
                StatusChip.sale(sale.saleStatus, sale.saleStatusText),
                StatusChip.payment(sale.paymentStatus, sale.paymentStatusText),
                if (sale.deliveryStatusText != null)
                  StatusChip(
                    label: sale.deliveryStatusText!,
                    color: sale.deliveryStatus == 1
                        ? AppColors.success
                        : AppColors.warning,
                    icon: Icons.local_shipping_outlined,
                  ),
              ],
            ),
            const Divider(height: AppSpacing.lg),
            _MetaRow('Customer', sale.customer?.name),
            if (sale.customer?.phone != null)
              _MetaRow('Mobile', sale.customer!.phone),
            if (sale.customer?.trnNumber != null)
              _MetaRow('TRN', sale.customer!.trnNumber),
            _MetaRow('Warehouse', sale.warehouse?.name),
            _MetaRow('Sales Person', sale.createdBy?.name),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(this.label, this.value);

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value ?? '-',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.icon});

  final String title;
  final Widget child;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: AppColors.primary),
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
          ],
        ),
      ),
    );
  }
}

/// A sale line. Shows the weight breakdown (pcs / gross / net / waste) that
/// this business actually trades on, not just quantity and price.
class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item});

  final SaleItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasWeightData =
        item.noOfPcs > 0 || item.grossWeight > 0 || item.wasteQty > 0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  item.displayName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                Format.amount(item.total),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${Format.quantity(item.qty)} ${item.saleUnit ?? ''} '
            '× ${Format.amount(item.netUnitPrice)}'
            '${item.tax > 0 ? '  (tax ${Format.amount(item.tax)})' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (hasWeightData)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Wrap(
                spacing: AppSpacing.md,
                children: [
                  if (item.noOfPcs > 0)
                    _Metric('Pcs', Format.quantity(item.noOfPcs)),
                  if (item.grossWeight > 0)
                    _Metric('G.Wt', Format.quantity(item.grossWeight)),
                  _Metric('N.Wt', Format.quantity(item.qty)),
                  if (item.wasteQty > 0)
                    _Metric('Waste', Format.quantity(item.wasteQty)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RichText(
      text: TextSpan(
        style: theme.textTheme.labelSmall,
        children: [
          TextSpan(
            text: '$label ',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
          TextSpan(
            text: value,
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(
    this.label,
    this.value, {
    this.emphasis = false,
    this.color,
  });

  final String label;
  final double value;
  final bool emphasis;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = emphasis
        ? theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)
        : theme.textTheme.bodyMedium;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: style?.copyWith(
                color: color ?? (emphasis ? null : theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
          Text(
            Format.amount(value),
            style: style?.copyWith(color: color),
          ),
        ],
      ),
    );
  }
}

class _DetailError extends StatelessWidget {
  const _DetailError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apiError = error is ApiException ? error as ApiException : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: AppSpacing.md),
            Text(
              apiError?.code == ApiErrorCode.forbidden
                  ? 'You do not have access to this sale'
                  : 'Could not load this sale',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              apiError?.message ?? '$error',
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
