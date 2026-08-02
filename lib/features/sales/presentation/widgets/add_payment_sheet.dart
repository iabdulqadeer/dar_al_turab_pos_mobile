import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/extensions/formatting.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_form.dart';
import '../../../../core/widgets/app_message.dart';
import '../../../../data/models/catalogue.dart';
import '../../../../data/models/sale.dart';
import '../../../pos/providers/pos_providers.dart';

/// Records a payment against an existing sale, or edits one already recorded.
///
/// This is the only way to settle a due invoice: `PUT /sales/{id}` accepts no
/// payment block, so money added after the sale goes through the payments
/// sub-resource, which writes the `invoice_payments` ledger that
/// `totals.paid_amount` is derived from.
class AddPaymentSheet extends ConsumerStatefulWidget {
  const AddPaymentSheet({
    required this.saleId,
    required this.outstanding,
    this.existing,
    super.key,
  });

  final int saleId;

  /// Balance still owed. Seeds the amount and caps validation.
  final double outstanding;

  /// When set, the sheet edits this payment rather than adding a new one.
  final SalePayment? existing;

  @override
  ConsumerState<AddPaymentSheet> createState() => _AddPaymentSheetState();
}

class _AddPaymentSheetState extends ConsumerState<AddPaymentSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _amount;
  late final TextEditingController _note;
  final _chequeNo = TextEditingController();

  PaymentMethodOption? _method;
  DateTime? _chequeDate;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  /// The most this payment may be.
  ///
  /// Adding: the outstanding balance. Editing: the balance plus whatever this
  /// payment already contributed, since raising it by that much still lands
  /// exactly on the total.
  double get _maxAmount =>
      widget.outstanding + (widget.existing?.paidAmount ?? 0);

  @override
  void initState() {
    super.initState();
    final seed = _isEdit ? widget.existing!.paidAmount : widget.outstanding;
    _amount = TextEditingController(text: seed.toStringAsFixed(2));
    _note = TextEditingController(text: widget.existing?.paymentNote ?? '');
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    _chequeNo.dispose();
    super.dispose();
  }

  bool get _isCheque => _method?.id == 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final meta = ref.watch(saleFormMetadataProvider).value;
    final methods = meta?.usablePaymentMethods ?? const <PaymentMethodOption>[];
    _method ??= methods.isEmpty ? null : methods.first;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _isEdit ? 'Edit payment' : 'Add payment',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Outstanding ${Format.amount(widget.outstanding)}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: widget.outstanding > 0.004
                        ? AppColors.error
                        : theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                if (methods.isEmpty)
                  const _NoMethodsNotice()
                else ...[
                  Text(
                    'Method',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
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
                ],

                AppTextField(
                  label: 'Amount',
                  controller: _amount,
                  required: true,
                  prefixIcon: Icons.payments_outlined,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  validator: _validateAmount,
                ),

                if (_isCheque) ...[
                  AppTextField(
                    label: 'Cheque number',
                    controller: _chequeNo,
                    prefixIcon: Icons.receipt_outlined,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  OutlinedButton.icon(
                    onPressed: _pickChequeDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      _chequeDate == null
                          ? 'Cheque date'
                          : Format.date(_chequeDate),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                AppTextField(
                  label: 'Note',
                  controller: _note,
                  prefixIcon: Icons.notes_outlined,
                ),
                const SizedBox(height: AppSpacing.lg),

                AppSubmitButton(
                  label: _isEdit ? 'Save payment' : 'Record payment',
                  icon: Icons.check,
                  busy: _saving,
                  onPressed: _method == null ? null : _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String? _validateAmount(String? value) {
    final amount = double.tryParse(value?.trim() ?? '');
    if (amount == null) return 'Enter an amount.';
    if (amount <= 0) return 'Amount must be more than zero.';

    // Overpaying is not a rounding nicety: the server marks any sale whose
    // paid amount differs from its total as unpaid, so an overpayment would
    // leave the invoice showing as due.
    if (amount > _maxAmount + 0.005) {
      return 'Cannot exceed ${Format.amount(_maxAmount)}.';
    }
    return null;
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

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    final api = ref.read(salePaymentsApiProvider);
    final amount = double.parse(_amount.text.trim());

    try {
      if (_isEdit) {
        await api.update(
          widget.saleId,
          widget.existing!.id!,
          paidById: _method!.id,
          amount: amount,
          chequeNo: _isCheque ? _chequeNo.text.trim() : null,
          chequeDate: _isCheque ? _chequeDate : null,
          note: _note.text.trim(),
        );
      } else {
        await api.add(
          widget.saleId,
          paidById: _method!.id,
          amount: amount,
          chequeNo: _isCheque ? _chequeNo.text.trim() : null,
          chequeDate: _isCheque ? _chequeDate : null,
          note: _note.text.trim(),
        );
      }

      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppMessage(context, e.message, kind: AppMessageKind.error);
    }
  }
}

class _NoMethodsNotice extends StatelessWidget {
  const _NoMethodsNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined,
              size: 18, color: AppColors.warning),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              'No payment methods are enabled on the server.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

/// Digits-and-one-decimal-point input, shared by money fields.
class MoneyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) return newValue;
    return RegExp(r'^\d*\.?\d{0,2}$').hasMatch(newValue.text)
        ? newValue
        : oldValue;
  }
}
