import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A consistent header for full-height modal bottom sheets: a back arrow that
/// dismisses the sheet, a title, and an optional trailing action. Gives every
/// sheet a clear, uniform way back — matching the app-bar back arrow on pushed
/// screens.
class SheetHeader extends StatelessWidget {
  const SheetHeader({
    required this.title,
    this.onBack,
    this.trailing,
    super.key,
  });

  final String title;

  /// Defaults to dismissing the sheet.
  final VoidCallback? onBack;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
