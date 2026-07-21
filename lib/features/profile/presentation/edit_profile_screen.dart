import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_form.dart';
import '../../auth/providers/auth_providers.dart';

class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _company;

  bool _saving = false;

  /// Field errors returned by the server (422), shown inline beneath the
  /// matching input rather than as a generic snackbar.
  Map<String, List<String>>? _serverErrors;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider);
    _name = TextEditingController(text: user?.name ?? '');
    _email = TextEditingController(text: user?.email ?? '');
    _phone = TextEditingController(text: user?.phone ?? '');
    _company = TextEditingController(text: user?.companyName ?? '');
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _company.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit profile')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            FormSection(
              title: 'Your details',
              subtitle:
                  'Role, warehouse, and account status are managed by an '
                  'administrator and cannot be changed here.',
              children: [
                AppTextField(
                  label: 'Full name',
                  controller: _name,
                  required: true,
                  prefixIcon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  validator: (value) =>
                      _serverError('name') ?? Validate.name(value),
                ),
                AppTextField(
                  label: 'Email',
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  prefixIcon: Icons.email_outlined,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.email],
                  validator: (value) =>
                      _serverError('email') ?? Validate.optionalEmail(value),
                ),
                AppTextField(
                  label: 'Phone',
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  prefixIcon: Icons.phone_outlined,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.telephoneNumber],
                  validator: (value) =>
                      _serverError('phone') ?? Validate.optionalPhone(value),
                ),
                AppTextField(
                  label: 'Company',
                  controller: _company,
                  prefixIcon: Icons.business_outlined,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _save(),
                  validator: (value) =>
                      _serverError('company_name') ??
                      Validate.maxLength(value, 255, 'Company'),
                ),
              ],
            ),
            AppSubmitButton(
              label: 'Save changes',
              icon: Icons.check,
              busy: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
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
      await ref
          .read(authApiProvider)
          .updateProfile(
            name: _name.text.trim(),
            email: _nullIfBlank(_email.text),
            phone: _nullIfBlank(_phone.text),
            companyName: _nullIfBlank(_company.text),
          );

      // Refresh the cached user so the dashboard greeting and profile card
      // reflect the change immediately.
      await ref.read(authControllerProvider.notifier).refreshUser();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Profile updated.')));
    } on ApiException catch (e) {
      if (!mounted) return;

      if (e.isValidation && e.errors != null) {
        setState(() => _serverErrors = e.errors);
        _formKey.currentState?.validate();
        return;
      }

      _showError(
        e.code == ApiErrorCode.demoMode
            ? 'This server runs in demo mode, so profile changes are disabled.'
            : e.message,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// The server treats these as `nullable`; sending an empty string would
  /// store a blank rather than clearing the field.
  String? _nullIfBlank(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
