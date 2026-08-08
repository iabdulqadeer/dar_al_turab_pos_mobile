import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/auth_user.dart';
import '../../../data/models/voucher.dart';
import '../../auth/providers/auth_providers.dart';
import 'ledger_voucher_list_screen.dart';
import 'voucher_list_screen.dart';

/// The Vouchers tab: a hub listing the voucher types the user may access.
/// Submenu visibility follows the role rules in the vouchers doc §4.
class VouchersHubScreen extends ConsumerWidget {
  const VouchersHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final isAdmin = user?.isAdmin ?? false;

    final showCrv = isAdmin || (user?.can(Permissions.cashReceivedVoucher) ?? false);
    final showCpv = isAdmin || (user?.can(Permissions.cashPaymentVoucher) ?? false);
    // Ledger Payment Voucher is never gated by a permission.

    return Scaffold(
      appBar: AppBar(title: const Text('Vouchers')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: [
          if (showCrv)
            _VoucherTypeTile(
              icon: Icons.south_west,
              color: AppColors.success,
              title: VoucherType.crv.title,
              subtitle: 'Receive cash from a customer',
              onTap: () => _push(
                context,
                VoucherListScreen(type: VoucherType.crv),
              ),
            ),
          if (showCpv)
            _VoucherTypeTile(
              icon: Icons.north_east,
              color: AppColors.warning,
              title: VoucherType.cpv.title,
              subtitle: 'Pay cash to a supplier',
              onTap: () => _push(
                context,
                VoucherListScreen(type: VoucherType.cpv),
              ),
            ),
          _VoucherTypeTile(
            icon: Icons.account_balance_wallet_outlined,
            color: AppColors.primary,
            title: 'Ledger Payment Voucher',
            subtitle: 'Standalone debit / credit entry',
            onTap: () =>
                _push(context, const LedgerVoucherListScreen()),
          ),
          if (!showCrv && !showCpv) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              'You don\'t have access to cash vouchers.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  void _push(BuildContext context, Widget screen) {
    Navigator.of(context, rootNavigator: true)
        .push(MaterialPageRoute(builder: (_) => screen));
  }
}

class _VoucherTypeTile extends StatelessWidget {
  const _VoucherTypeTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color),
        ),
        title: Text(title,
            style: theme.textTheme.bodyLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
      ),
    );
  }
}
