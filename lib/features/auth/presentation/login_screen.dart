import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../branding/presentation/brand_logo.dart';
import '../../branding/providers/branding_providers.dart';
import '../providers/auth_providers.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _loginController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _loginController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await ref
          .read(authControllerProvider.notifier)
          .signIn(
            login: _loginController.text.trim(),
            password: _passwordController.text,
          );
      // On success the router redirect takes over; no manual navigation.
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = _messageFor(e));
    } on Object {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Turns server error codes into text a cashier can act on.
  String _messageFor(ApiException e) {
    return switch (e.code) {
      ApiErrorCode.invalidCredentials =>
        'Incorrect username or password. Please try again.',
      ApiErrorCode.accountInactive =>
        'This account is inactive. Contact your administrator.',
      ApiErrorCode.tooManyAttempts =>
        'Too many sign-in attempts. Please wait a minute and try again.',
      ApiErrorCode.networkError => e.message,
      ApiErrorCode.unexpectedResponse => e.message,
      ApiErrorCode.validationError =>
        e.errorFor('login') ?? e.errorFor('password') ?? e.message,
      _ => e.message,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Surface an involuntary sign-out (token revoked) as an inline banner.
    final authState = ref.watch(authControllerProvider);
    final sessionMessage = authState is AuthSignedOut ? authState.message : null;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 420),
                    child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Brand(),
                    const SizedBox(height: AppSpacing.xl),

                    if (sessionMessage != null) ...[
                      _Banner(
                        message: sessionMessage,
                        color: theme.colorScheme.error,
                        icon: Icons.info_outline,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    if (_error != null) ...[
                      _Banner(
                        message: _error!,
                        color: theme.colorScheme.error,
                        icon: Icons.error_outline,
                      ),
                      const SizedBox(height: AppSpacing.md),
                    ],

                    TextFormField(
                      controller: _loginController,
                      enabled: !_submitting,
                      textInputAction: TextInputAction.next,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.username],
                      decoration: const InputDecoration(
                        labelText: 'Username or email',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                      validator: (value) =>
                          (value == null || value.trim().isEmpty)
                          ? 'Enter your username or email'
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.md),

                    TextFormField(
                      controller: _passwordController,
                      enabled: !_submitting,
                      obscureText: _obscure,
                      textInputAction: TextInputAction.done,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => _submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscure
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          tooltip: _obscure ? 'Show password' : 'Hide password',
                          onPressed: () =>
                              setState(() => _obscure = !_obscure),
                        ),
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? 'Enter your password'
                          : null,
                    ),

                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _submitting
                            ? null
                            : () => context.push(Routes.forgotPassword),
                        child: const Text('Forgot password?'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),

                    FilledButton(
                      onPressed: _submitting ? null : _submit,
                      child: _submitting
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('Sign in'),
                    ),
                    const SizedBox(height: AppSpacing.md),

                    TextButton.icon(
                      onPressed: _submitting ? null : _showServerSettings,
                      icon: const Icon(Icons.dns_outlined, size: 18),
                      label: const Text('Server settings'),
                    ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            ),
            const _Footer(),
          ],
        ),
      ),
    );
  }

  Future<void> _showServerSettings() async {
    final store = ref.read(sessionStoreProvider);
    final current = await store.readBaseUrl() ?? AppConfig.apiBaseUrl;
    if (!mounted) return;

    final controller = TextEditingController(text: current);
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API base URL'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.url,
              autocorrect: false,
              decoration: const InputDecoration(
                hintText: 'http://192.168.1.10/dar_al_turab_pos_1/public/api/',
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Point this at the Laravel /api endpoint. Use the server\'s LAN '
              'IP when running on a physical device.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();

    if (saved ?? false) {
      await ref
          .read(authControllerProvider.notifier)
          .setBaseUrl(controller.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Server address updated.')),
        );
      }
    }
  }
}

class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // The emblem carries the company name already, so repeating it as a
    // headline underneath would say the same thing twice.
    final onDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        BrandLogo(width: 190, onDark: onDark),
        const SizedBox(height: AppSpacing.md),
        Text(
          'Sign in to continue',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

/// Pinned to the bottom of the login screen: the About link and the credit
/// line, both from the cached branding (available even before the first login).
class _Footer extends ConsumerWidget {
  const _Footer();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final brand = ref.watch(brandingProvider);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextButton.icon(
            onPressed: () => context.push(Routes.about),
            icon: const Icon(Icons.info_outline, size: 18),
            label: const Text('About'),
          ),
          Text(
            'Developed by ${brand?.developedBy ?? 'KAF Sols.'}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.color,
    required this.icon,
  });

  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}
