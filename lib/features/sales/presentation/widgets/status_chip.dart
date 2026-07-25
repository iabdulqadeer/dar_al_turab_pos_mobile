import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/sale_status.dart';

/// Small coloured status label used in lists and detail headers.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.color,
    this.icon,
    super.key,
  });

  /// Colour-codes payment state: paid reads as settled, due as needing action.
  factory StatusChip.payment(PaymentStatus? status, String label) {
    return StatusChip(
      label: label,
      color: switch (status) {
        PaymentStatus.paid => AppColors.success,
        PaymentStatus.partial => AppColors.warning,
        PaymentStatus.due || PaymentStatus.pending => AppColors.error,
        // Neutral: resolved from the theme in build() so it adapts to dark mode.
        null => null,
      },
      // Icon + colour + label so payment state reads without relying on colour
      // alone (colour-blind accessibility).
      icon: switch (status) {
        PaymentStatus.paid => Icons.check_circle,
        PaymentStatus.partial => Icons.hourglass_bottom,
        PaymentStatus.due || PaymentStatus.pending => Icons.error_outline,
        null => Icons.help_outline,
      },
    );
  }

  factory StatusChip.sale(SaleStatus? status, String label) {
    return StatusChip(
      label: label,
      color: switch (status) {
        SaleStatus.completed => AppColors.success,
        SaleStatus.pending => AppColors.warning,
        // Neutral: resolved from the theme in build() so it adapts to dark mode.
        SaleStatus.draft => null,
        null => null,
      },
      icon: switch (status) {
        SaleStatus.completed => Icons.check_circle_outline,
        SaleStatus.pending => Icons.schedule,
        SaleStatus.draft => Icons.edit_note,
        null => Icons.help_outline,
      },
    );
  }

  final String label;

  /// Semantic colour, or null for a neutral state that follows the theme.
  final Color? color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    // Neutral states (draft, unknown) take the theme's muted colour so they
    // stay legible in both light and dark mode.
    final color = this.color ?? Theme.of(context).colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
