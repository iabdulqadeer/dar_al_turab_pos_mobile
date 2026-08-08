import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/voucher.dart';

/// The per-type glyph: cash received points in (down), cash paid points out
/// (up), a ledger entry is a wallet.
IconData voucherIcon(VoucherType type) =>
    type == VoucherType.crv ? Icons.arrow_downward : Icons.arrow_upward;

Color voucherColor(VoucherType type) =>
    type == VoucherType.crv ? AppColors.success : AppColors.error;

const IconData ledgerVoucherIcon = Icons.account_balance_wallet_outlined;

/// A rounded-square tinted icon, matching the sales-list row leading icon.
class VoucherLeadingIcon extends StatelessWidget {
  const VoucherLeadingIcon({
    required this.icon,
    required this.color,
    this.size = 34,
    super.key,
  });

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: size,
      width: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, size: size * 0.53, color: color),
    );
  }
}
