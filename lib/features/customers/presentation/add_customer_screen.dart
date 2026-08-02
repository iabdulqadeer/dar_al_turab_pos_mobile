import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_form.dart';
import '../../../core/widgets/app_message.dart';
import '../../../data/models/catalogue.dart';
import '../../../data/models/customer_form.dart';
import '../providers/customer_providers.dart';

/// The fuller "Add Customer" screen, backed by `POST /v1/customers`. Distinct
/// from the sale screen's inline quick-create modal, which is untouched. On a
/// successful create the new [CatalogueCustomer] is returned to the caller via
/// `context.pop`, so the customer picker can pre-select it on the sale.
class AddCustomerScreen extends ConsumerStatefulWidget {
  const AddCustomerScreen({super.key});

  @override
  ConsumerState<AddCustomerScreen> createState() => _AddCustomerScreenState();
}

class _AddCustomerScreenState extends ConsumerState<AddCustomerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _city = TextEditingController();
  final _country = TextEditingController();
  final _trn = TextEditingController();
  final _manager = TextEditingController();

  int? _groupId;
  int? _areaId;
  bool _saving = false;

  /// Field errors from a 422, shown inline beneath the matching input.
  Map<String, List<String>>? _serverErrors;

  @override
  void dispose() {
    for (final c in [_name, _phone, _address, _city, _country, _trn, _manager]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final form = ref.watch(customerCreateFormProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Add customer')),
      body: form.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => _LoadError(
          error: error,
          onRetry: () => ref.invalidate(customerCreateFormProvider),
        ),
        data: (data) => _form(data),
      ),
    );
  }

  Widget _form(CustomerCreateForm data) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          FormSection(
            title: 'Customer',
            subtitle:
                'Group and area come from the back office. Warehouse is set '
                'automatically from your account.',
            children: [
              _Dropdown<int>(
                label: 'Customer group',
                required: true,
                value: _groupId,
                hint: 'Select a group',
                items: [
                  for (final g in data.customerGroups)
                    DropdownMenuItem(value: g.id, child: Text(g.name)),
                ],
                onChanged: (v) => setState(() => _groupId = v),
                errorText: _serverError('customer_group_id'),
                validator: (v) => v == null ? 'Choose a customer group.' : null,
              ),
              _Dropdown<int>(
                label: 'Area',
                required: true,
                value: _areaId,
                hint: 'Select an area',
                items: [
                  for (final a in data.areas)
                    DropdownMenuItem(value: a.id, child: Text(a.name)),
                ],
                onChanged: (v) => setState(() => _areaId = v),
                errorText: _serverError('area_id'),
                validator: (v) => v == null ? 'Choose an area.' : null,
              ),
              AppTextField(
                label: 'Name',
                controller: _name,
                required: true,
                prefixIcon: Icons.person_outline,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    _serverError('name') ?? Validate.notEmpty(v, 'Name'),
              ),
              AppTextField(
                label: 'Phone number',
                controller: _phone,
                required: true,
                keyboardType: TextInputType.phone,
                prefixIcon: Icons.phone_outlined,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    _serverError('phone_number') ??
                    Validate.notEmpty(v, 'Phone number'),
              ),
              AppTextField(
                label: 'Address',
                controller: _address,
                required: true,
                prefixIcon: Icons.location_on_outlined,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    _serverError('address') ?? Validate.notEmpty(v, 'Address'),
              ),
              AppTextField(
                label: 'City',
                controller: _city,
                required: true,
                prefixIcon: Icons.location_city_outlined,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    _serverError('city') ?? Validate.notEmpty(v, 'City'),
              ),
              AppTextField(
                label: 'Country',
                controller: _country,
                required: true,
                prefixIcon: Icons.public_outlined,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    _serverError('country') ?? Validate.notEmpty(v, 'Country'),
              ),
              AppTextField(
                label: 'TRN number',
                controller: _trn,
                prefixIcon: Icons.receipt_long_outlined,
                textInputAction: TextInputAction.next,
                validator: (v) =>
                    _serverError('trn_number') ??
                    Validate.maxLength(v, 191, 'TRN number'),
              ),
              AppTextField(
                label: 'Manager name',
                controller: _manager,
                prefixIcon: Icons.badge_outlined,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _save(),
                validator: (v) =>
                    _serverError('manager_name') ??
                    Validate.maxLength(v, 191, 'Manager name'),
              ),
            ],
          ),
          AppSubmitButton(
            label: 'Create customer',
            icon: Icons.check,
            busy: _saving,
            onPressed: _save,
          ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
    );
  }

  /// Consumes a server-side field error once, so it clears as soon as the user
  /// edits that field and re-validates.
  String? _serverError(String field) {
    final message = _serverErrors?[field]?.firstOrNull;
    if (message != null) {
      _serverErrors = {..._serverErrors!}..remove(field);
    }
    return message;
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      final created = await ref.read(customerApiProvider).create(
            customerGroupId: _groupId!,
            areaId: _areaId!,
            name: _name.text.trim(),
            phoneNumber: _phone.text.trim(),
            address: _address.text.trim(),
            city: _city.text.trim(),
            country: _country.text.trim(),
            trnNumber: _nullIfBlank(_trn.text),
            managerName: _nullIfBlank(_manager.text),
          );

      if (!mounted) return;
      context.pop(created);
    } on ApiException catch (e) {
      if (!mounted) return;

      if (e.isValidation && e.errors != null) {
        setState(() => _serverErrors = e.errors);
        _formKey.currentState?.validate();
        return;
      }

      _showError(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _showError(String message) {
    showAppMessage(context, message, kind: AppMessageKind.error);
  }
}

/// Labelled dropdown that matches [AppTextField]'s label + error styling, so
/// the two dropdowns sit consistently among the text fields.
class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.hint,
    this.required = false,
    this.errorText,
    this.validator,
  });

  final String label;
  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final String? hint;
  final bool required;
  final String? errorText;
  final String? Function(T?)? validator;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
          child: RichText(
            text: TextSpan(
              text: label,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface,
              ),
              children: [
                if (required)
                  const TextSpan(
                    text: ' *',
                    style: TextStyle(color: AppColors.error),
                  ),
              ],
            ),
          ),
        ),
        DropdownButtonFormField<T>(
          initialValue: value,
          items: items,
          onChanged: onChanged,
          validator: validator,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          isExpanded: true,
          hint: hint == null ? null : Text(hint!),
          decoration: InputDecoration(
            // A server-side error is surfaced the same way the validator's is.
            errorText: errorText,
          ),
        ),
      ],
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
              'Could not load the customer form',
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

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}