import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_form.dart';
import '../providers/auth_providers.dart';

/// Step 1 of the unauthenticated reset flow: request a reset link by email.
///
/// The response is deliberately enumeration-safe — a success never reveals
/// whether the address is registered, so the UI shows the same confirmation
/// either way.
class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();

  bool _submitting = false;
  bool _sent = false;
  String? _emailError;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Forgot password')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [_sent ? _confirmation(context) : _form(context)],
        ),
      ),
    );
  }

  Widget _form(BuildContext context) {
    final theme = Theme.of(context);

    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Reset your password',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Enter the email on your account and we\'ll send a reset link.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            label: 'Email',
            controller: _email,
            required: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.done,
            autofillHints: const [AutofillHints.email],
            prefixIcon: Icons.email_outlined,
            onSubmitted: (_) => _submit(),
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
          const SizedBox(height: AppSpacing.lg),
          AppSubmitButton(
            label: 'Send reset link',
            icon: Icons.send_outlined,
            busy: _submitting,
            onPressed: _submit,
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: TextButton(
              onPressed: () => context.push(
                Routes.resetPassword,
                extra: _email.text.trim().isEmpty ? null : _email.text.trim(),
              ),
              child: const Text('Already have a reset code?'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _confirmation(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Icon(
          Icons.mark_email_read_outlined,
          size: 56,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Check your email',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'If ${_email.text.trim()} is registered, we\'ve sent a password '
          'reset link. Open it, copy the reset code, then continue below. '
          'The link expires in 60 minutes.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        AppSubmitButton(
          label: 'Enter reset code',
          icon: Icons.password_outlined,
          onPressed: () => context.push(
            Routes.resetPassword,
            extra: _email.text.trim(),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: TextButton(
            onPressed: _submitting ? null : _submit,
            child: const Text('Resend link'),
          ),
        ),
      ],
    );
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _submitting = true);
    try {
      await ref
          .read(authApiProvider)
          .forgotPassword(email: _email.text.trim());
      if (mounted) setState(() => _sent = true);
    } on ApiException catch (e) {
      if (!mounted) return;

      if (e.isValidation) {
        final fieldError = e.errorFor('email');
        if (fieldError != null) {
          setState(() => _emailError = fieldError);
          _formKey.currentState?.validate();
          return;
        }
      }

      _showError(switch (e.code) {
        ApiErrorCode.emailNotConfigured =>
          'Password reset is temporarily unavailable. Please contact support.',
        // 429 carries a human "try again in N seconds" message.
        ApiErrorCode.tooManyAttempts => e.message,
        _ => e.message,
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
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
