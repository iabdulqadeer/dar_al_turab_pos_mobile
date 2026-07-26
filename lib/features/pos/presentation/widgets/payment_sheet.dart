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
  final _discount = TextEditingController();
  final _chequeNo = TextEditingController();
  PaymentMethodOption? _method;
  int? _bankId;
  DateTime? _chequeDate;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final cart = ref.read(cartProvider);
    _tendered.text = cart.grandTotal.toStringAsFixed(2);
    if (cart.orderDiscount > 0) {
      _discount.text = cart.orderDiscount.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _tendered.dispose();
    _discount.dispose();
    _chequeNo.dispose();
    super.dispose();
  }

  double get _paid => double.tryParse(_tendered.text) ?? 0;

  bool get _isCheque => _method?.id == 4;
  bool get _isDeposit => _method?.id == 6;

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(cartProvider);
    final meta = ref.watch(saleFormMetadataProvider).value;
    final taxRate = ref.watch(saleTaxRateProvider);
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
              const SizedBox(height: AppSpacing.sm),
              // Tax breakdown, at the global rate from settings/general.
              if (taxRate > 0)
                _breakdownRow(
                  theme,
                  'Tax (${Format.quantity(taxRate)})%',
                  Format.amount(cart.totalTax),
                ),
              const Divider(height: AppSpacing.xl),

              // Invoice-level discount (flutter_app_issues #8): lowers the grand
              // total live.
              Text(
                'Discount',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextField(
                controller: _discount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
                ],
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.discount_outlined, size: 20),
                  hintText: '0.00',
                ),
                onChanged: (text) {
                  ref
                      .read(cartProvider.notifier)
                      .setOrderDiscount(double.tryParse(text) ?? 0);
                  _syncTendered();
                },
              ),
              const SizedBox(height: AppSpacing.sm),

              // Remove-decimal toggle (flutter_app_issues #9): truncates the
              // grand total to a whole number.
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: cart.removeDecimalAmount,
                title: const Text('Remove decimal'),
                subtitle: const Text('Drop the decimals from the grand total'),
                onChanged: (value) {
                  ref.read(cartProvider.notifier).setRemoveDecimalAmount(value);
                  _syncTendered();
                },
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

              // Deposit (id 6) needs a bank; Cheque (id 4) a number + date.
              if (_isDeposit) ...[
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<int>(
                  initialValue: _bankId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Bank',
                    prefixIcon: Icon(Icons.account_balance_outlined, size: 20),
                  ),
                  items: [
                    for (final b in meta?.banks ?? const <NamedRef>[])
                      DropdownMenuItem(value: b.id, child: Text(b.name)),
                  ],
                  onChanged: (v) => setState(() => _bankId = v),
                ),
              ],
              if (_isCheque) ...[
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: _chequeNo,
                  decoration: const InputDecoration(
                    isDense: true,
                    labelText: 'Cheque number',
                    prefixIcon: Icon(Icons.receipt_outlined, size: 20),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                OutlinedButton.icon(
                  onPressed: _pickChequeDate,
                  icon: const Icon(Icons.event_outlined, size: 18),
                  label: Text(
                    _chequeDate == null
                        ? 'Cheque date'
                        : Format.date(_chequeDate),
                  ),
                ),
              ],
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

  /// Keeps the tendered amount on the (recalculated) total after a discount or
  /// remove-decimal change, so "amount due" and "tendered" stay in step.
  void _syncTendered() {
    _tendered.text = ref.read(cartProvider).grandTotal.toStringAsFixed(2);
    setState(() {});
  }

  Future<void> _pickChequeDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _chequeDate ?? now,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _chequeDate = picked);
  }

  Widget _breakdownRow(ThemeData theme, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 1),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(value, style: theme.textTheme.bodySmall),
      ],
    ),
  );

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
        chequeNo: _isCheque ? _chequeNo.text.trim() : null,
        chequeDate: _isCheque ? _chequeDate : null,
        bankId: _isDeposit ? _bankId : null,
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
