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

/// Create/edit a Cash Received (CRV) or Cash Payment (CPV) voucher — one screen
/// for both, parameterised by [type]. Allocates a payment across the person's
/// unpaid invoices.
class VoucherFormScreen extends ConsumerStatefulWidget {
  const VoucherFormScreen({required this.type, this.existing, super.key});

  final VoucherType type;
  final Voucher? existing;

  bool get isEdit => existing != null;

  @override
  ConsumerState<VoucherFormScreen> createState() => _VoucherFormScreenState();
}

class _VoucherFormScreenState extends ConsumerState<VoucherFormScreen> {
  DateTime _date = DateTime.now();
  VoucherPerson? _person;
  NamedRef? _warehouse;
  NamedRef? _biller;
  String _paymentMethod = 'cash';
  NamedRef? _bank;
  final _chequeNumber = TextEditingController();
  DateTime? _chequeDate;

  final List<UnpaidInvoice> _invoices = [];
  final Map<int, TextEditingController> _payCtrls = {};
  final Map<int, String?> _rowErrors = {};
  bool _loadingInvoices = false;
  bool _submitting = false;

  VoucherType get _type => widget.type;
  bool get _isCrv => _type == VoucherType.crv;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _date = DateTime.tryParse(e.date) ?? DateTime.now();
      _person = e.person;
      _biller = e.biller;
      _bank = e.bank;
      _paymentMethod = e.paymentMethod.isEmpty ? 'cash' : e.paymentMethod;
      _chequeNumber.text = e.chequeNo ?? '';
      _chequeDate = e.chequeDate == null ? null : DateTime.tryParse(e.chequeDate!);
      if (_person != null) _loadInvoices();
    }
  }

  @override
  void dispose() {
    _chequeNumber.dispose();
    for (final c in _payCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formAsync = ref.watch(voucherCreateFormProvider(_type));
    final isAdmin = ref.watch(currentUserProvider)?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.isEdit ? 'Edit' : 'New'} ${_type.title}'),
      ),
      body: formAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Text('Could not load form.\n$e', textAlign: TextAlign.center),
          ),
        ),
        data: (form) => _body(form, isAdmin),
      ),
    );
  }

  Widget _body(VoucherCreateForm form, bool isAdmin) {
    _biller ??= form.lockedBiller;
    _warehouse ??= _warehouseFor(form);
    final showBank = _paymentMethod == 'deposit';
    final showCheque = _paymentMethod == 'cheque';

    return ListView(
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

        // Person type is locked by voucher type (CRV=Customer, CPV=Supplier).
        VoucherPersonField(
          label: _type.personType,
          person: _person,
          onTap: () => _pickPerson(),
        ),
        const SizedBox(height: AppSpacing.md),

        // Biller / Sale Person: only for CRV (Customer). Hidden for CPV.
        if (_isCrv) ...[
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
            controller: _chequeNumber,
            decoration: const InputDecoration(labelText: 'Cheque Number'),
          ),
          const SizedBox(height: AppSpacing.md),
          VoucherDateField(
            label: 'Cheque Date',
            value: _chequeDate,
            onChanged: (d) => setState(() => _chequeDate = d),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        const Divider(),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Text(
            'Unpaid Invoices',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
        _invoiceSection(),
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
    );
  }

  Widget _invoiceSection() {
    if (_person == null) {
      return Text(
        'Select a ${_type.personType.toLowerCase()} to load their unpaid '
        'invoices.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    if (_loadingInvoices) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_invoices.isEmpty) {
      return Text(
        'No unpaid invoices for this ${_type.personType.toLowerCase()}.',
        style: Theme.of(context).textTheme.bodySmall,
      );
    }
    return Column(
      children: _invoices.map(_invoiceCard).toList(),
    );
  }

  Widget _invoiceCard(UnpaidInvoice inv) {
    final theme = Theme.of(context);
    final error = _rowErrors[inv.invoiceId];

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: error != null
            ? BorderSide(color: theme.colorScheme.error)
            : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Checkbox(
                  value: inv.selected,
                  onChanged: (v) =>
                      setState(() => inv.selected = v ?? false),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(inv.referenceNo,
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                      Text('${inv.date} · Due ${inv.due.toStringAsFixed(2)}',
                          style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ],
            ),
            if (inv.selected) ...[
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _payCtrls[inv.invoiceId],
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Pay Amount', isDense: true),
                      onChanged: (v) =>
                          inv.payAmount = double.tryParse(v.trim()) ?? 0,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      initialValue: _trimZeros(inv.discountAmount),
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                          labelText: 'Discount', isDense: true),
                      onChanged: (v) {
                        // Editing discount recalculates pay = due − discount.
                        inv.applyDiscount(double.tryParse(v.trim()) ?? 0);
                        _payCtrls[inv.invoiceId]?.text =
                            _trimZeros(inv.payAmount);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                initialValue: inv.note,
                decoration: const InputDecoration(
                    labelText: 'Note', isDense: true),
                onChanged: (v) => inv.note = v,
              ),
            ],
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(error,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error)),
              ),
          ],
        ),
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
    final api = ref.read(vouchersApiProvider);
    final person = await showModalBottomSheet<VoucherPerson>(
      context: context,
      isScrollControlled: true,
      builder: (_) => VoucherPersonPicker(
        title: 'Select ${_type.personType}',
        search: (q) => api.searchPeople(_type, q),
      ),
    );
    if (person == null) return;
    setState(() => _person = person);
    // Selecting/changing the person immediately reloads their unpaid invoices.
    _loadInvoices();
  }

  Future<void> _loadInvoices() async {
    final person = _person;
    if (person == null) return;
    setState(() {
      _loadingInvoices = true;
      _rowErrors.clear();
    });
    try {
      final invoices = await ref.read(vouchersApiProvider).unpaidInvoices(
            personType: _type.personType,
            personId: person.id,
          );
      if (!mounted) return;
      for (final c in _payCtrls.values) {
        c.dispose();
      }
      _payCtrls.clear();
      for (final inv in invoices) {
        _payCtrls[inv.invoiceId] =
            TextEditingController(text: _trimZeros(inv.payAmount));
      }
      setState(() {
        _invoices
          ..clear()
          ..addAll(invoices);
        _loadingInvoices = false;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _loadingInvoices = false);
      showAppMessage(context, e.message, kind: AppMessageKind.error);
    }
  }

  Future<void> _submit(bool isAdmin) async {
    final person = _person;
    if (person == null) {
      _toast('Select a ${_type.personType.toLowerCase()}.', isError: true);
      return;
    }
    final selected = _invoices.where((i) => i.selected).toList();
    if (selected.isEmpty) {
      _toast('Select at least one invoice.', isError: true);
      return;
    }
    if (_paymentMethod == 'deposit' && _bank == null) {
      _toast('Select a bank.', isError: true);
      return;
    }

    final body = <String, dynamic>{
      'date': voucherFormatDate(_date),
      'voucher_type': _type.value,
      'person_type': _type.personType,
      if (_isCrv) 'customer_id': person.id else 'supplier_id': person.id,
      if (_isCrv && _biller != null) 'biller_id': _biller!.id,
      'payment_method': _paymentMethod,
      if (isAdmin && _warehouse != null) 'warehouse_id': _warehouse!.id,
      if (_paymentMethod == 'deposit' && _bank != null) 'bank_id': _bank!.id,
      // CRV/CPV cheque field is cheque_number (LPV uses cheque_no).
      if (_paymentMethod == 'cheque') 'cheque_number': _chequeNumber.text.trim(),
      if (_paymentMethod == 'cheque' && _chequeDate != null)
        'cheque_date': voucherFormatDate(_chequeDate!),
      'invoices': selected.map((i) => i.toJson()).toList(),
    };

    setState(() {
      _submitting = true;
      _rowErrors.clear();
    });
    final api = ref.read(vouchersApiProvider);
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
      _handleSubmitError(e, selected);
    }
  }

  /// Overpayment (INVOICE_OVERPAID) names the offending invoice in its message —
  /// pin the error to that row rather than a generic toast.
  void _handleSubmitError(ApiException e, List<UnpaidInvoice> selected) {
    if (e.code == 'INVOICE_OVERPAID') {
      UnpaidInvoice? offender;
      for (final inv in selected) {
        if (e.message.contains(inv.referenceNo)) {
          offender = inv;
          break;
        }
      }
      if (offender != null) {
        setState(() => _rowErrors[offender!.invoiceId] = e.message);
        return;
      }
    }
    showAppMessage(context, e.message, kind: AppMessageKind.error);
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
