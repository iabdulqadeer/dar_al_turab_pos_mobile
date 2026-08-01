import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/app_form.dart';
import '../../../../data/models/catalogue.dart';
import '../../providers/pos_providers.dart';

/// Customer search + inline create, for the sale screen.
///
/// By default the picked customer is written to the global New-Sale cart. Pass
/// [onSelected] to route the choice somewhere else instead — the Edit Sale
/// screen drives a local cart, so it supplies its own handler.
class CustomerPicker extends ConsumerStatefulWidget {
  const CustomerPicker({this.onSelected, super.key});

  final void Function(CatalogueCustomer customer)? onSelected;

  @override
  ConsumerState<CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<CustomerPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Applies the choice: to the caller's handler when given, otherwise to the
  /// global cart. Either way the sheet closes.
  void _pick(CatalogueCustomer customer) {
    final onSelected = widget.onSelected;
    if (onSelected != null) {
      onSelected(customer);
    } else {
      ref.read(cartProvider.notifier).setCustomer(customer);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(customerSearchProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Customer',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _createCustomer,
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Quick'),
                  ),
                  TextButton.icon(
                    onPressed: _fullCreate,
                    icon: const Icon(Icons.assignment_ind_outlined, size: 18),
                    label: const Text('Full'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (v) =>
                    ref.read(customerSearchQueryProvider.notifier).set(v),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search by name, phone or company',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: results.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      error is ApiException
                          ? error.message
                          : 'Could not load customers.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                data: (customers) => customers.isEmpty
                    ? Center(
                        child: Text(
                          'No customers found',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : ListView.separated(
                        itemCount: customers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final c = customers[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.12),
                              child: Icon(
                                c.isDefault
                                    ? Icons.storefront_outlined
                                    : Icons.person_outline,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ),
                            title: Text(c.name),
                            subtitle: c.subtitle == null
                                ? null
                                : Text(
                                    c.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => _pick(c),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _createCustomer() async {
    final created = await showModalBottomSheet<CatalogueCustomer>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _QuickCreateCustomerSheet(),
    );

    if (created != null && mounted) {
      _pick(created);
    }
  }

  /// Opens the fuller "Add Customer" screen. It returns the created customer on
  /// pop, which we then apply to the sale just like a picked one.
  Future<void> _fullCreate() async {
    final created = await context.push<CatalogueCustomer>(Routes.addCustomer);
    if (created != null && mounted) {
      _pick(created);
    }
  }
}

class _QuickCreateCustomerSheet extends ConsumerStatefulWidget {
  const _QuickCreateCustomerSheet();

  @override
  ConsumerState<_QuickCreateCustomerSheet> createState() =>
      _QuickCreateCustomerSheetState();
}

class _QuickCreateCustomerSheetState
    extends ConsumerState<_QuickCreateCustomerSheet> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();

  bool _saving = false;

  @override
  void dispose() {
    for (final c in [_name, _phone, _email, _address]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              mainAxisSize: MainAxisSize.min,
              children: [
                FormSection(
                  title: 'New customer',
                  subtitle:
                      'Quick create for this sale. Groups and discount plans '
                      'are managed in the back office.',
                  children: [
                    AppTextField(
                      label: 'Name',
                      controller: _name,
                      required: true,
                      prefixIcon: Icons.person_outline,
                      textInputAction: TextInputAction.next,
                      validator: (v) => Validate.notEmpty(v, 'Name'),
                    ),
                    AppTextField(
                      label: 'Phone',
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      prefixIcon: Icons.phone_outlined,
                      textInputAction: TextInputAction.next,
                      validator: Validate.optionalPhone,
                    ),
                    AppTextField(
                      label: 'Email',
                      controller: _email,
                      keyboardType: TextInputType.emailAddress,
                      prefixIcon: Icons.email_outlined,
                      textInputAction: TextInputAction.next,
                      validator: Validate.optionalEmail,
                    ),
                    AppTextField(
                      label: 'Address',
                      controller: _address,
                      prefixIcon: Icons.location_on_outlined,
                      textInputAction: TextInputAction.done,
                      validator: (v) =>
                          Validate.maxLength(v, 191, 'Address'),
                    ),
                  ],
                ),
                AppSubmitButton(
                  label: 'Create customer',
                  icon: Icons.check,
                  busy: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      final created = await ref
          .read(catalogueApiProvider)
          .quickCreateCustomer(
            name: _name.text.trim(),
            phoneNumber: _blankToNull(_phone.text),
            email: _blankToNull(_email.text),
            address: _blankToNull(_address.text),
          );

      if (mounted) Navigator.pop(context, created);
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _blankToNull(String v) {
    final t = v.trim();
    return t.isEmpty ? null : t;
  }
}
