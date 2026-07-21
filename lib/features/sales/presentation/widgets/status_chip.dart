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
        null => AppColors.lightTextSecondary,
      },
    );
  }

  factory StatusChip.sale(SaleStatus? status, String label) {
    return StatusChip(
      label: label,
      color: switch (status) {
        SaleStatus.completed => AppColors.success,
        SaleStatus.pending => AppColors.warning,
        SaleStatus.draft => AppColors.lightTextSecondary,
        null => AppColors.lightTextSecondary,
      },
    );
  }

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
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
