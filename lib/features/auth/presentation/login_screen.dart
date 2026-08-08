import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/app_config.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/network/server_probe.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_message.dart';
import '../../branding/presentation/brand_logo.dart';
import '../../branding/presentation/developer_credit.dart';
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

                    // Only internal/test builds expose the server switch; it is
                    // stripped from the staff production build.
                    if (AppConfig.enableServerToggle)
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
    final current = ref.read(serverSettingsControllerProvider);

    final result = await showDialog<ServerSettings>(
      context: context,
      builder: (context) => _ServerSettingsDialog(initial: current),
    );
    if (result == null || !mounted) return;

    await ref
        .read(serverSettingsControllerProvider.notifier)
        .save(mode: result.mode, devBaseUrl: result.devBaseUrl);

    if (mounted) {
      showAppMessage(
        context,
        result.isDev
            ? 'Now using the DEV server. Please sign in again.'
            : 'Now using the PRODUCTION server. Please sign in again.',
        kind: AppMessageKind.success,
      );
    }
  }
}

/// The Dev/Production server picker shown from the login screen. Returns the
/// chosen [ServerSettings] on Save, or null on Cancel.
class _ServerSettingsDialog extends StatefulWidget {
  const _ServerSettingsDialog({required this.initial});

  final ServerSettings initial;

  @override
  State<_ServerSettingsDialog> createState() => _ServerSettingsDialogState();
}

class _ServerSettingsDialogState extends State<_ServerSettingsDialog> {
  late ServerMode _mode = widget.initial.mode;
  late final TextEditingController _devUrl = TextEditingController(
    text: widget.initial.devBaseUrl,
  );

  bool _testing = false;
  ServerProbeResult? _probe;

  @override
  void dispose() {
    _devUrl.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _probe = null;
    });
    final result = await probeServer(_devUrl.text.trim());
    if (!mounted) return;
    setState(() {
      _testing = false;
      _probe = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDev = _mode == ServerMode.dev;

    return AlertDialog(
      title: const Text('Server settings'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SegmentedButton<ServerMode>(
            segments: const [
              ButtonSegment(
                value: ServerMode.dev,
                label: Text('Dev'),
                icon: Icon(Icons.build_outlined),
              ),
              ButtonSegment(
                value: ServerMode.production,
                label: Text('Production'),
                icon: Icon(Icons.cloud_outlined),
              ),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _devUrl,
            enabled: isDev,
            keyboardType: TextInputType.url,
            autocorrect: false,
            onChanged: (_) {
              if (_probe != null) setState(() => _probe = null);
            },
            decoration: const InputDecoration(
              labelText: 'Dev server URL',
              hintText: 'http://localhost:8080/.../public/api/',
            ),
          ),
          if (isDev) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _testing ? null : _testConnection,
                icon: _testing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering, size: 18),
                label: Text(_testing ? 'Testing…' : 'Test connection'),
              ),
            ),
            if (_probe case final probe?) _ProbeStatus(result: probe),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            isDev
                ? 'All requests go to this dev server. It ends at /api/ — the app '
                      'adds v1/ itself. Over USB, run "adb reverse tcp:8080 '
                      'tcp:80" and keep localhost:8080; over Wi-Fi use the dev '
                      'machine\'s LAN IP.'
                : 'All requests will go to the live production server.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Switching servers signs you out — you\'ll need to log in again.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            ServerSettings(mode: _mode, devBaseUrl: _devUrl.text.trim()),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A compact pass/fail line under the "Test connection" button.
class _ProbeStatus extends StatelessWidget {
  const _ProbeStatus({required this.result});

  final ServerProbeResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (result.status) {
      ServerProbeStatus.reachableApi => AppColors.success,
      ServerProbeStatus.reachableNotApi => AppColors.warning,
      ServerProbeStatus.unreachable => theme.colorScheme.error,
    };
    final icon = result.ok ? Icons.check_circle_outline : Icons.error_outline;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              result.detail,
              style: theme.textTheme.bodySmall?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
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
          DeveloperCredit(name: brand?.developedBy ?? 'KAF Sols.'),
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
