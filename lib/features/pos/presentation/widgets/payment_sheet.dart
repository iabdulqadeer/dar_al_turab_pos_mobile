import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/extensions/formatting.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/catalogue.dart';
import '../../../../data/models/sale_status.dart';
import '../../providers/pos_providers.dart';

/// Takes payment and submits the sale.
class PaymentSheet extends ConsumerStatefulWidget {
  const PaymentSheet({super.key});

  @override
  ConsumerState<PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<PaymentSheet> {
  final _tendered = TextEditingController();
  PaymentMethodOption? _method;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final total = ref.read(cartProvider).grandTotal;
    _tendered.text = total.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _tendered.dispose();
    super.dispose();
  }

  double get _paid => double.tryParse(_tendered.text) ?? 0;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final meta = ref.watch(saleFormMetadataProvider).value;
    final theme = Theme.of(context);

    final methods = meta?.usablePaymentMethods ?? const <PaymentMethodOption>[];
    _method ??= methods.isEmpty ? null : methods.first;

    final total = cart.grandTotal;
    final change = _paid - total;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Amount due',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    Format.amount(total),
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const Divider(height: AppSpacing.xl),

              Text(
                'Payment method',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              // Only methods the server marks enabled are offered. Points (7)
              // is always disabled — POST /sales rejects it outright.
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final m in methods)
                    ChoiceChip(
                      label: Text(m.name),
                      selected: _method?.id == m.id,
                      onSelected: (_) => setState(() => _method = m),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              Text(
                'Amount tendered',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _tendered,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                onChanged: (_) => setState(() {}),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                decoration: const InputDecoration(isDense: true),
              ),
              const SizedBox(height: AppSpacing.sm),

              Wrap(
                spacing: AppSpacing.sm,
                children: [
                  _QuickAmount(
                    label: 'Exact',
                    onTap: () => _setAmount(total),
                  ),
                  for (final v in _suggestions(total))
                    _QuickAmount(
                      label: Format.amount(v),
                      onTap: () => _setAmount(v),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: (change >= 0 ? AppColors.success : AppColors.warning)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        change >= 0 ? 'Change due' : 'Remaining balance',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      Format.amount(change.abs()),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: change >= 0
                            ? AppColors.success
                            : AppColors.warning,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              SizedBox(
                width: double.infinity,
                height: AppSpacing.minTouchTarget,
                child: FilledButton.icon(
                  onPressed: _submitting || _method == null ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    _submitting ? 'Saving sale…' : 'Complete sale',
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setAmount(double v) {
    _tendered.text = v.toStringAsFixed(2);
    setState(() {});
  }

  /// Round-number suggestions above the total, for cash handling.
  List<double> _suggestions(double total) {
    final out = <double>[];
    for (final step in [10, 50, 100, 500]) {
      final v = (total / step).ceil() * step.toDouble();
      if (v > total && !out.contains(v)) out.add(v);
    }
    return out.take(3).toList();
  }

  Future<void> _submit() async {
    final cart = ref.read(cartProvider);
    final total = cart.grandTotal;

    // Never send more than the invoice as paid: the server treats any
    // mismatch — including an overpayment — as "due", so the sale would be
    // recorded unpaid. Change is physical cash, not part of the invoice.
    final applied = _paid > total ? total : _paid;

    setState(() => _submitting = true);

    try {
      final sale = await ref.read(createSaleProvider)(
        saleStatus: SaleStatus.completed.value,
        // The server recomputes this for POS sales anyway; send our best
        // guess so a non-POS path still records it sensibly.
        paymentStatus: applied >= total - 0.005
            ? PaymentStatus.paid.value
            : (applied > 0
                  ? PaymentStatus.partial.value
                  : PaymentStatus.due.value),
        paidAmount: applied,
        paymentMethodId: _method!.id,
      );

      ref.read(cartProvider.notifier).clearLines();

      if (!mounted) return;
      Navigator.pop(context);

      // Straight to the sale so the cashier can print the receipt.
      context.push('${Routes.sales}/${sale.id}');

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Sale ${sale.referenceNo} created.')),
        );
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(_messageFor(e)),
            backgroundColor: AppColors.error,
            duration: const Duration(seconds: 6),
          ),
        );
    }
  }

  /// Turns the server's error codes into something a cashier can act on.
  String _messageFor(ApiException e) {
    return switch (e.code) {
      ApiErrorCode.insufficientStock =>
        'Not enough stock for one or more items. Adjust quantities and retry.',
      ApiErrorCode.unknownSaleUnit =>
        'A line has an unrecognised unit. Reopen it and pick a unit.',
      ApiErrorCode.pointsPaymentUnsupported =>
        'Points payments are not supported. Choose another method.',
      ApiErrorCode.noWarehouseAssigned || ApiErrorCode.warehouseRequired =>
        'Your account has no warehouse assigned. Ask an administrator.',
      _ => e.message,
    };
  }
}

class _QuickAmount extends StatelessWidget {
  const _QuickAmount({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(label: Text(label), onPressed: onTap);
  }
}
