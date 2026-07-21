import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_form.dart';
import '../../auth/providers/auth_providers.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();

  bool _saving = false;
  String? _currentPasswordError;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Change password')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: AppColors.primary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Changing your password signs out your other devices. '
                      'This device stays signed in.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            FormSection(
              title: 'New password',
              children: [
                AppPasswordField(
                  label: 'Current password',
                  controller: _current,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  validator: (value) {
                    // Surface the server's rejection inline, then clear it so
                    // the next attempt is judged on its own.
                    final serverError = _currentPasswordError;
                    if (serverError != null) {
                      _currentPasswordError = null;
                      return serverError;
                    }
                    return Validate.notEmpty(value, 'Current password');
                  },
                ),
                AppPasswordField(
                  label: 'New password',
                  controller: _next,
                  helper: 'At least 8 characters.',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: Validate.newPassword,
                ),
                AppPasswordField(
                  label: 'Confirm new password',
                  controller: _confirm,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  onSubmitted: (_) => _save(),
                  validator: (value) {
                    if ((value ?? '').isEmpty) {
                      return 'Please re-enter the new password.';
                    }
                    if (value != _next.text) return 'Passwords do not match.';
                    return null;
                  },
                ),
              ],
            ),

            AppSubmitButton(
              label: 'Update password',
              icon: Icons.lock_outline,
              busy: _saving,
              onPressed: _save,
            ),
            const SizedBox(height: AppSpacing.xl),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _saving = true);

    try {
      await ref
          .read(authApiProvider)
          .changePassword(
            currentPassword: _current.text,
            newPassword: _next.text,
          );

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('Password updated. Other devices signed out.'),
          ),
        );
    } on ApiException catch (e) {
      if (!mounted) return;

      // The server reports a wrong current password as a 422 carrying a
      // current_password field error; anchor it to that input.
      if (e.code == ApiErrorCode.invalidCurrentPassword || e.isValidation) {
        final fieldError =
            e.errorFor('current_password') ??
            (e.code == ApiErrorCode.invalidCurrentPassword ? e.message : null);

        if (fieldError != null) {
          setState(() => _currentPasswordError = fieldError);
          _formKey.currentState?.validate();
          return;
        }
      }

      _showError(
        e.code == ApiErrorCode.demoMode
            ? 'This server runs in demo mode, so the password cannot be changed.'
            : e.message,
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
