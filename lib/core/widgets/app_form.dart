import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Labelled text field used across every form, so spacing, label weight, and
/// error presentation stay identical everywhere.
class AppTextField extends StatelessWidget {
  const AppTextField({
    required this.label,
    required this.controller,
    this.hint,
    this.helper,
    this.keyboardType,
    this.textInputAction,
    this.obscureText = false,
    this.enabled = true,
    this.autofillHints,
    this.prefixIcon,
    this.suffix,
    this.maxLength,
    this.validator,
    this.onSubmitted,
    this.required = false,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? helper;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscureText;
  final bool enabled;
  final Iterable<String>? autofillHints;
  final IconData? prefixIcon;
  final Widget? suffix;
  final int? maxLength;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;

  /// Adds a visual required marker. Enforcement still comes from [validator].
  final bool required;

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
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          textInputAction: textInputAction,
          obscureText: obscureText,
          enabled: enabled,
          autofillHints: autofillHints,
          maxLength: maxLength,
          validator: validator,
          onFieldSubmitted: onSubmitted,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          decoration: InputDecoration(
            hintText: hint,
            helperText: helper,
            counterText: '',
            prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 20),
            suffixIcon: suffix,
          ),
        ),
      ],
    );
  }
}

/// Password field with a show/hide toggle.
class AppPasswordField extends StatefulWidget {
  const AppPasswordField({
    required this.label,
    required this.controller,
    this.helper,
    this.textInputAction,
    this.validator,
    this.onSubmitted,
    this.autofillHints,
    super.key,
  });

  final String label;
  final TextEditingController controller;
  final String? helper;
  final TextInputAction? textInputAction;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final Iterable<String>? autofillHints;

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _obscured = true;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      label: widget.label,
      controller: widget.controller,
      helper: widget.helper,
      obscureText: _obscured,
      required: true,
      textInputAction: widget.textInputAction,
      validator: widget.validator,
      onSubmitted: widget.onSubmitted,
      autofillHints: widget.autofillHints,
      prefixIcon: Icons.lock_outline,
      suffix: IconButton(
        icon: Icon(
          _obscured ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          size: 20,
        ),
        tooltip: _obscured ? 'Show password' : 'Hide password',
        onPressed: () => setState(() => _obscured = !_obscured),
      ),
    );
  }
}

/// Primary submit button that shows progress in place, so the form cannot be
/// submitted twice while a request is in flight.
class AppSubmitButton extends StatelessWidget {
  const AppSubmitButton({
    required this.label,
    required this.onPressed,
    this.busy = false,
    this.icon,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: AppSpacing.minTouchTarget,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: AppSpacing.sm),
                  ],
                  Text(label),
                ],
              ),
      ),
    );
  }
}

/// Groups related fields under a heading.
class FormSection extends StatelessWidget {
  const FormSection({
    required this.title,
    required this.children,
    this.subtitle,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        for (final child in children) ...[
          child,
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

/// Field validators matching the server's rules, so the user is not bounced by
/// a 422 for something we could have caught locally.
abstract final class Validate {
  /// `required|string|max:255` on the profile name.
  static String? name(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return 'Name is required.';
    if (text.length > 255) return 'Name must be 255 characters or fewer.';
    return null;
  }

  /// `nullable|email|max:255`. Blank is valid — the server allows a null email.
  static String? optionalEmail(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (text.length > 255) return 'Email must be 255 characters or fewer.';
    // Deliberately loose: the server is the authority, and an over-strict
    // client regex rejects addresses that are actually valid.
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(text)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  /// `nullable|string|max:50`.
  static String? optionalPhone(String? value) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    if (text.length > 50) return 'Phone must be 50 characters or fewer.';
    return null;
  }

  static String? maxLength(String? value, int max, String field) {
    final text = value?.trim() ?? '';
    if (text.length > max) return '$field must be $max characters or fewer.';
    return null;
  }

  static String? notEmpty(String? value, String field) {
    if ((value?.trim() ?? '').isEmpty) return '$field is required.';
    return null;
  }

  /// `required|string|min:8|confirmed` on the new password.
  static String? newPassword(String? value) {
    final text = value ?? '';
    if (text.isEmpty) return 'New password is required.';
    if (text.length < 8) return 'Must be at least 8 characters.';
    return null;
  }
}
