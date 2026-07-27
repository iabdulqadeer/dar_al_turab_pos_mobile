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
import '../../../printing/printer_transport.dart';
import '../../../printing/providers/print_job_providers.dart';
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
  // How the sale is being settled. Drives whether a payment is taken now; the
  // server derives the final payment_status from paid_amount vs grand_total.
  PaymentStatus _status = PaymentStatus.paid;
  bool _submitting = false;

  bool get _isDue => _status == PaymentStatus.due;

  /// Due needs no method; Partial/Paid need one chosen.
  bool get _canSubmit => !_submitting && (_isDue || _method != null);

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

              // Payment status drives whether a payment is taken now; the server
              // derives the final status from paid_amount vs grand_total.
              Text(
                'Payment status',
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              DropdownButtonFormField<PaymentStatus>(
                initialValue: _status,
                isExpanded: true,
                decoration: const InputDecoration(
                  isDense: true,
                  prefixIcon: Icon(Icons.fact_check_outlined, size: 20),
                ),
                items: const [
                  DropdownMenuItem(
                    value: PaymentStatus.due,
                    child: Text('Due (pay later)'),
                  ),
                  DropdownMenuItem(
                    value: PaymentStatus.partial,
                    child: Text('Partial'),
                  ),
                  DropdownMenuItem(
                    value: PaymentStatus.paid,
                    child: Text('Paid'),
                  ),
                ],
                onChanged: (s) {
                  if (s == null) return;
                  setState(() {
                    _status = s;
                    if (s == PaymentStatus.paid) {
                      _tendered.text = total.toStringAsFixed(2);
                    }
                  });
                },
              ),

              // Due = nothing paid now: no method, amount, or payment block.
              if (!_isDue) ...[
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
                  'Paid amount',
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
              ],
              const SizedBox(height: AppSpacing.lg),

              // Save just records the sale; Save & Print also prints the
              // receipt on success (a print failure never rolls back the sale).
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _canSubmit ? () => _submit(print: false) : null,
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('Save'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(
                          AppSpacing.minTouchTarget,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: SizedBox(
                      height: AppSpacing.minTouchTarget,
                      child: FilledButton.icon(
                        onPressed: _canSubmit
                            ? () => _submit(print: true)
                            : null,
                        icon: _submitting
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.print_outlined, size: 18),
                        label: Text(_submitting ? 'Saving…' : 'Save & Print'),
                      ),
                    ),
                  ),
                ],
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

  Future<void> _submit({required bool print}) async {
    final cart = ref.read(cartProvider);
    final total = cart.grandTotal;

    // Due: nothing paid now, no payment block. Otherwise the entered amount,
    // capped at the invoice (an overpaying cash tender is change, not paid).
    final applied = _isDue ? 0.0 : (_paid > total ? total : _paid);

    setState(() => _submitting = true);

    try {
      final sale = await ref.read(createSaleProvider)(
        saleStatus: SaleStatus.completed.value,
        // The server recomputes this for POS sales anyway; send our best
        // guess so a non-POS path still records it sensibly.
        paymentStatus: _status.value,
        paidAmount: applied,
        paymentMethodId: _isDue ? null : _method!.id,
        chequeNo: _isDue ? null : (_isCheque ? _chequeNo.text.trim() : null),
        chequeDate: _isDue ? null : (_isCheque ? _chequeDate : null),
        bankId: _isDue ? null : (_isDeposit ? _bankId : null),
      );

      // Save & Print: print the fresh sale before leaving. Best-effort so a
      // print failure warns but never rolls back the saved sale.
      String? printWarning;
      if (print) {
        try {
          await ref.read(printSaleReceiptProvider)(sale.id);
        } on PrintException catch (e) {
          printWarning = 'Saved, but printing failed: ${e.message} ${e.remedy}';
        } on ApiException catch (e) {
          printWarning = 'Saved, but printing failed: ${e.message}';
        }
      }

      ref.read(cartProvider.notifier).clearLines();

      if (!mounted) return;
      Navigator.pop(context);
      context.push('${Routes.sales}/${sale.id}');

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(printWarning ?? 'Sale ${sale.referenceNo} created.'),
            backgroundColor: printWarning != null ? AppColors.warning : null,
            duration: Duration(seconds: printWarning != null ? 6 : 4),
          ),
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
