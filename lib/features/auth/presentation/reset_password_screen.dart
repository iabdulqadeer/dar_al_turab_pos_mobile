import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_form.dart';
import '../../../core/widgets/app_message.dart';
import '../providers/auth_providers.dart';

/// Step 2 of the reset flow: set a new password using the token from the
/// emailed link. The token is pasted manually — the email is a web URL, not an
/// app deep link.
class ResetPasswordScreen extends ConsumerStatefulWidget {
  const ResetPasswordScreen({this.initialEmail, super.key});

  final String? initialEmail;

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _token = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  bool _saving = false;
  String? _emailError;
  String? _tokenError;
  String? _passwordError;

  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail ?? '');
  }

  @override
  void dispose() {
    _email.dispose();
    _token.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Reset password')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            FormSection(
              title: 'New password',
              subtitle:
                  'Paste the reset code from the email we sent you, then '
                  'choose a new password.',
              children: [
                AppTextField(
                  label: 'Email',
                  controller: _email,
                  required: true,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  prefixIcon: Icons.email_outlined,
                  validator: (value) {
                    final serverError = _emailError;
                    if (serverError != null) {
                      _emailError = null;
                      return serverError;
                    }
                    return Validate.notEmpty(value, 'Email') ??
                        Validate.optionalEmail(value);
                  },
                ),
                AppTextField(
                  label: 'Reset code',
                  controller: _token,
                  required: true,
                  hint: 'From the reset email',
                  textInputAction: TextInputAction.next,
                  prefixIcon: Icons.vpn_key_outlined,
                  validator: (value) {
                    final serverError = _tokenError;
                    if (serverError != null) {
                      _tokenError = null;
                      return serverError;
                    }
                    return Validate.notEmpty(value, 'Reset code');
                  },
                ),
                AppPasswordField(
                  label: 'New password',
                  controller: _password,
                  helper: 'At least 8 characters.',
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newPassword],
                  validator: (value) {
                    final serverError = _passwordError;
                    if (serverError != null) {
                      _passwordError = null;
                      return serverError;
                    }
                    return Validate.newPassword(value);
                  },
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
                    if (value != _password.text) {
                      return 'Passwords do not match.';
                    }
                    return null;
                  },
                ),
              ],
            ),
            AppSubmitButton(
              label: 'Reset password',
              icon: Icons.lock_reset_outlined,
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
      await ref.read(authApiProvider).resetPassword(
            email: _email.text.trim(),
            token: _token.text.trim(),
            password: _password.text,
          );

      if (!mounted) return;
      // Show before navigating away so the message uses the still-mounted
      // context; the root-overlay toast persists onto the login screen.
      showAppMessage(
        context,
        'Password updated. Sign in with your new password.',
        kind: AppMessageKind.success,
      );
      context.go(Routes.login);
    } on ApiException catch (e) {
      if (!mounted) return;

      // A stale/expired/reused link, or an email the token doesn't belong to:
      // both mean "get a fresh link" — never expose "no such account".
      if (e.code == ApiErrorCode.invalidToken ||
          e.code == ApiErrorCode.invalidUser) {
        _expiredLinkDialog();
        return;
      }

      if (e.isValidation) {
        // Anchor each server field error to its input, then re-validate.
        _emailError = e.errorFor('email');
        _tokenError = e.errorFor('token');
        _passwordError = e.errorFor('password');
        if (_emailError != null ||
            _tokenError != null ||
            _passwordError != null) {
          _formKey.currentState?.validate();
          return;
        }
      }

      _showError(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _expiredLinkDialog() async {
    final restart = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Link expired'),
        content: const Text(
          'This reset link is invalid or has expired. Reset links are valid '
          'for 60 minutes — request a new one to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Request new link'),
          ),
        ],
      ),
    );

    if ((restart ?? false) && mounted) {
      context.pushReplacement(Routes.forgotPassword);
    }
  }

  void _showError(String message) {
    showAppMessage(context, message, kind: AppMessageKind.error);
  }
}
