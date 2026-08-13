import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_message.dart';
import '../../../data/models/catalogue.dart' show NamedRef;
import '../../../data/models/voucher.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/voucher_providers.dart';
import 'widgets/voucher_form_fields.dart';
import 'widgets/voucher_person_picker.dart';

/// Create (or, for admins, edit) a Ledger Payment Voucher — a standalone
/// debit/credit ledger entry with no invoice allocation.
class LedgerVoucherFormScreen extends ConsumerStatefulWidget {
  const LedgerVoucherFormScreen({this.existing, super.key});

  final LedgerPaymentVoucher? existing;

  bool get isEdit => existing != null;

  @override
  ConsumerState<LedgerVoucherFormScreen> createState() =>
      _LedgerVoucherFormScreenState();
}

class _LedgerVoucherFormScreenState
    extends ConsumerState<LedgerVoucherFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController();
  final _details = TextEditingController();
  final _chequeNo = TextEditingController();

  DateTime _date = DateTime.now();
  String _personType = 'Customer';
  VoucherPerson? _person;
  NamedRef? _warehouse;
  NamedRef? _biller;
  String _transactionType = 'debit';
  String _paymentMethod = 'cash';
  NamedRef? _bank;
  DateTime? _chequeDate;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _amount.text = e.amount == 0 ? '' : _trimZeros(e.amount);
      _details.text = e.details ?? '';
      _chequeNo.text = e.chequeNo ?? '';
      _date = DateTime.tryParse(e.date) ?? DateTime.now();
      _personType = e.person?.type ?? 'Customer';
      _person = e.person;
      _biller = e.biller;
      _bank = e.bank;
      _transactionType = e.transactionType.isEmpty ? 'debit' : e.transactionType;
      _paymentMethod = e.paymentMethod.isEmpty ? 'cash' : e.paymentMethod;
      _chequeDate = e.chequeDate == null ? null : DateTime.tryParse(e.chequeDate!);
    }
  }

  @override
  void dispose() {
    _amount.dispose();
    _details.dispose();
    _chequeNo.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formAsync = ref.watch(ledgerCreateFormProvider);
    final isAdmin = ref.watch(currentUserProvider)?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isEdit
            ? 'Edit Ledger Voucher'
            : 'New Ledger Voucher'),
      ),
      body: formAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text('Could not load form.\n$e', textAlign: TextAlign.center),
          ),
        ),
        data: (form) => _form(form, isAdmin),
      ),
    );
  }

  Widget _form(VoucherCreateForm form, bool isAdmin) {
    // Pre-fill the locked biller (the user's own) once form data is available.
    _biller ??= form.lockedBiller;
    _warehouse ??= _warehouseFor(form);

    final showBank = _paymentMethod == 'bank';
    final showCheque = _paymentMethod == 'cheque';

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          VoucherDateField(
            label: 'Date',
            value: _date,
            onChanged: (d) => setState(() => _date = d),
          ),
          const SizedBox(height: AppSpacing.md),

          if (isAdmin && form.warehouses.isNotEmpty) ...[
            VoucherRefDropdown(
              label: 'Warehouse',
              value: _warehouse,
              items: form.warehouses,
              onChanged: (w) => setState(() => _warehouse = w),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          VoucherDropdown<String>(
            label: 'Person Type',
            value: _personType,
            items: const ['Customer', 'Supplier'],
            labelFor: (v) => v,
            onChanged: (v) => setState(() {
              _personType = v;
              _person = null; // a customer isn't a supplier — reset
            }),
          ),
          const SizedBox(height: AppSpacing.md),

          VoucherPersonField(
            label: _personType,
            person: _person,
            onTap: _pickPerson,
          ),
          const SizedBox(height: AppSpacing.md),

          // Sale Person: shown and required for a Customer, hidden entirely for
          // a Supplier (Issue 2, aug 13). Locked + pre-filled when the server
          // says so (a non-admin with their own biller).
          if (_personType == 'Customer') ...[
            VoucherRefDropdown(
              label: 'Sale Person',
              value: _biller,
              items: form.billers,
              enabled: !form.billerLocked,
              onChanged: (b) => setState(() => _biller = b),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          VoucherDropdown<String>(
            label: 'Transaction Type',
            value: _transactionType,
            items: const ['debit', 'credit'],
            labelFor: (v) => v[0].toUpperCase() + v.substring(1),
            onChanged: (v) => setState(() => _transactionType = v),
          ),
          const SizedBox(height: AppSpacing.md),

          VoucherDropdown<String>(
            label: 'Payment Method',
            value: _paymentMethod,
            items: form.paymentMethods.map((m) => m.value).toList(),
            labelFor: (v) => form.paymentMethods
                .firstWhere((m) => m.value == v,
                    orElse: () => VoucherOption(value: v, name: v))
                .name,
            onChanged: (v) => setState(() => _paymentMethod = v),
          ),
          const SizedBox(height: AppSpacing.md),

          if (showBank) ...[
            VoucherRefDropdown(
              label: 'Bank',
              value: _bank,
              items: form.banks,
              onChanged: (b) => setState(() => _bank = b),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          if (showCheque) ...[
            TextFormField(
              controller: _chequeNo,
              style: voucherFieldStyle(context),
              decoration: const InputDecoration(
                labelText: 'Cheque Number',
                isDense: true,
              ),
              validator: (v) => (v == null || v.trim().isEmpty)
                  ? 'Enter the cheque number'
                  : null,
            ),
            const SizedBox(height: AppSpacing.md),
            VoucherDateField(
              label: 'Cheque Date',
              value: _chequeDate,
              onChanged: (d) => setState(() => _chequeDate = d),
            ),
            const SizedBox(height: AppSpacing.md),
          ],

          TextFormField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: voucherFieldStyle(context),
            decoration: const InputDecoration(
              labelText: 'Amount',
              isDense: true,
            ),
            validator: (v) {
              final amount = double.tryParse(v?.trim() ?? '');
              if (amount == null || amount < 0.01) {
                return 'Enter an amount of at least 0.01';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),

          TextFormField(
            controller: _details,
            maxLines: 2,
            style: voucherFieldStyle(context),
            decoration: const InputDecoration(
              labelText: 'Details',
              hintText: 'Optional',
              isDense: true,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),

          FilledButton(
            onPressed: _submitting ? null : () => _submit(isAdmin),
            child: _submitting
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Text(widget.isEdit ? 'Save changes' : 'Create voucher'),
          ),
        ],
      ),
    );
  }

  NamedRef? _warehouseFor(VoucherCreateForm form) {
    if (form.warehouses.isEmpty) return null;
    final id = widget.existing?.warehouse?.id ?? form.warehouseId;
    for (final w in form.warehouses) {
      if (w.id == id) return w;
    }
    return form.warehouses.first;
  }

  Future<void> _pickPerson() async {
    final api = ref.read(ledgerVouchersApiProvider);
    final person = await showModalBottomSheet<VoucherPerson>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VoucherPersonPicker(
        title: 'Select $_personType',
        search: (q) => api.searchPeople(_personType, q),
      ),
    );
    if (person != null) setState(() => _person = person);
  }

  Future<void> _submit(bool isAdmin) async {
    if (!_formKey.currentState!.validate()) return;
    if (_person == null) {
      _toast('Select a $_personType.', isError: true);
      return;
    }
    if (_paymentMethod == 'bank' && _bank == null) {
      _toast('Select a bank.', isError: true);
      return;
    }
    if (_paymentMethod == 'cheque' && _chequeDate == null) {
      _toast('Select the cheque date.', isError: true);
      return;
    }
    // Sale Person is required when the party is a Customer (Issue 2).
    if (_personType == 'Customer' && _biller == null) {
      _toast('Select a Sale Person.', isError: true);
      return;
    }

    final body = <String, dynamic>{
      'voucher_date': voucherFormatDate(_date),
      'person_type': _personType,
      if (_personType == 'Customer') 'customer_id': _person!.id,
      if (_personType == 'Supplier') 'supplier_id': _person!.id,
      // Only a Customer voucher carries a Sale Person; a Supplier one omits it.
      if (_personType == 'Customer' && _biller != null) 'biller_id': _biller!.id,
      'transaction_type': _transactionType,
      'payment_method': _paymentMethod,
      if (isAdmin && _warehouse != null) 'warehouse_id': _warehouse!.id,
      if (_paymentMethod == 'bank' && _bank != null) 'bank_id': _bank!.id,
      // LPV cheque field is cheque_no (CRV/CPV uses cheque_number).
      if (_paymentMethod == 'cheque') 'cheque_no': _chequeNo.text.trim(),
      if (_paymentMethod == 'cheque' && _chequeDate != null)
        'cheque_date': voucherFormatDate(_chequeDate!),
      'amount': double.parse(_amount.text.trim()),
      if (_details.text.trim().isNotEmpty) 'details': _details.text.trim(),
    };

    setState(() => _submitting = true);
    final api = ref.read(ledgerVouchersApiProvider);
    try {
      if (widget.isEdit) {
        await api.update(widget.existing!.id, body);
      } else {
        await api.create(body);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      _toast(e.message, isError: true);
    }
  }

  void _toast(String message, {bool isError = false}) {
    showAppMessage(
      context,
      message,
      kind: isError ? AppMessageKind.error : AppMessageKind.success,
    );
  }

  static String _trimZeros(double v) {
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }
}

