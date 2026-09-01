import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/formatting.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_overflow_menu.dart';
import '../../../data/datasources/remote/sales_api.dart';
import '../../../data/models/auth_user.dart';
import '../../../data/models/sale.dart';
import '../../auth/providers/auth_providers.dart';
import '../../branding/providers/branding_providers.dart';
import '../../cash_register/presentation/cash_register_screen.dart';
import '../../printing/providers/printer_providers.dart';
import '../../sales/presentation/widgets/sale_row_menu.dart';
import '../providers/dashboard_providers.dart';

/// Whether the "printer not connected" dashboard alert has been dismissed for
/// this session. Resets on relaunch so a still-disconnected printer is flagged
/// again next time the app opens.
final printerAlertDismissedProvider =
    NotifierProvider<PrinterAlertDismissed, bool>(PrinterAlertDismissed.new);

class PrinterAlertDismissed extends Notifier<bool> {
  @override
  bool build() => false;

  void dismiss() => state = true;
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final recent = ref.watch(dashboardRecentProvider);
    final brand = ref.watch(brandingProvider);
    final canCreateSale = user?.can(Permissions.salesAdd) ?? false;
    final canViewCashRegister =
        user?.can(Permissions.dailyCashRegister) ?? false;

    // Flag a missing printer: printing is supported on this platform but no
    // printer is connected. The banner is dismissible for the session.
    final printerConnected = ref.watch(printerControllerProvider).isConnected;
    final printingSupported = ref.watch(printingSupportedProvider);
    final showPrinterAlert = printingSupported &&
        !printerConnected &&
        !ref.watch(printerAlertDismissedProvider);

    return Scaffold(
      // Sticky top bar: the brand name and the shared overflow menu, matching
      // the other tabs so every screen has a fixed header.
      appBar: AppBar(
        title: Text(brand?.systemTitle ?? 'Dar Al Turab'),
        actions: const [AppOverflowMenu()],
      ),
      // The FAB lives here rather than on the shell so it appears on this
      // screen only, never on pages pushed over it.
      floatingActionButton: canCreateSale
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.pos),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('New sale'),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardRecentProvider),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: AppSpacing.xl),
            children: [
              _Greeting(user: user),
              if (showPrinterAlert)
                _PrinterAlert(
                  onDismiss: () =>
                      ref.read(printerAlertDismissedProvider.notifier).dismiss(),
                ),
              _QuickMenu(
                canCreateSale: canCreateSale,
                canViewCashRegister: canViewCashRegister,
                printerConnected: printerConnected || !printingSupported,
              ),
              _RecentHeader(),
              ...switch (recent) {
                AsyncData(:final value) => [
                  if (value.isEmpty)
                    const _NoRecentSales()
                  else
                    for (final sale in value)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.md,
                          0,
                          AppSpacing.md,
                          AppSpacing.sm,
                        ),
                        child: _RecentSaleTile(sale: sale),
                      ),
                ],
                AsyncError(:final error) => [
                  _RecentError(
                    error: error,
                    onRetry: () => ref.invalidate(dashboardRecentProvider),
                  ),
                ],
                _ => const [_RecentSkeleton()],
              },
            ],
          ),
        ),
      ),
    );
  }
}

class _Greeting extends StatelessWidget {
  const _Greeting({required this.user});

  final AuthUser? user;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 17
        ? 'Good afternoon'
        : 'Good evening';

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
            child: Text(
              user?.initials ?? '?',
              style: theme.textTheme.titleMedium?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  user?.name ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (user?.warehouseName != null)
                  Text(
                    user!.warehouseName!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Vertical shortcut list — the salesman's primary actions, one tap each.
class _QuickMenu extends StatelessWidget {
  const _QuickMenu({
    required this.canCreateSale,
    required this.canViewCashRegister,
    required this.printerConnected,
  });

  final bool canCreateSale;
  final bool canViewCashRegister;
  final bool printerConnected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: [
          if (canCreateSale)
            _QuickTile(
              icon: Icons.point_of_sale,
              accent: AppColors.primary,
              title: 'New Sale',
              subtitle: 'Start ringing up an order',
              onTap: () {
                HapticFeedback.selectionClick();
                context.push(Routes.pos);
              },
            ),
          _QuickTile(
            icon: Icons.receipt_long,
            accent: AppColors.secondary,
            title: 'Sales History',
            subtitle: 'Browse and search past sales',
            onTap: () => context.go(Routes.sales),
          ),
          if (canViewCashRegister)
            _QuickTile(
              icon: Icons.point_of_sale,
              accent: AppColors.secondary,
              title: 'Cash Register',
              subtitle: 'Daily cash-in / cash-out report',
              // Push on the branch navigator so the bottom nav stays visible.
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const CashRegisterScreen(),
                ),
              ),
            ),
          _QuickTile(
            icon: Icons.print,
            accent: AppColors.success,
            title: 'Printer Setup',
            subtitle: 'Connect and test the receipt printer',
            onTap: () => context.go(Routes.printer),
            badge: printerConnected ? null : const _NotConnectedBadge(),
          ),
          _QuickTile(
            icon: Icons.person,
            accent: AppColors.warning,
            title: 'My Profile',
            subtitle: 'Account details and sign out',
            onTap: () => context.go(Routes.profile),
          ),
        ],
      ),
    );
  }
}

/// Small red "Not connected" pill shown on the Printer Setup tile.
class _NotConnectedBadge extends StatelessWidget {
  const _NotConnectedBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 13, color: AppColors.error),
          const SizedBox(width: 4),
          Text(
            'Not connected',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColors.error,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// A professional, dismissible alert card shown on the dashboard when no
/// receipt printer is connected.
class _PrinterAlert extends StatelessWidget {
  const _PrinterAlert({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: AppColors.error.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 38,
                  width: 38,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: const Icon(
                    Icons.print_disabled_outlined,
                    color: AppColors.error,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Printer not connected',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColors.error,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Receipts cannot be printed on this device or account '
                        'until a receipt printer is connected.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: onDismiss,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: () => context.go(Routes.printer),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Set up printer'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.error,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// Optional status chip shown before the chevron (e.g. "Not connected").
  final Widget? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null) ...[
                badge!,
                const SizedBox(width: AppSpacing.xs),
              ],
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RecentHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(
            Icons.history,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              'Recent sales',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: () => context.go(Routes.sales),
            child: const Text('View all'),
          ),
        ],
      ),
    );
  }
}

class _RecentSaleTile extends StatelessWidget {
  const _RecentSaleTile({required this.sale});

  final SaleListItem sale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        onTap: () => context.push('${Routes.sales}/${sale.id}'),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        // Same 44x44 rounded-square as the quick-menu tiles, so the leading
        // icon column lines up between the two sections.
        leading: Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: const Icon(
            Icons.receipt_long_outlined,
            color: AppColors.primary,
          ),
        ),
        title: Text(
          sale.referenceNo,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Text(
          '${sale.customer?.name ?? '-'}  ·  ${Format.shortDate(sale.date)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Format.amount(sale.grandTotal),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (sale.hasDue)
                  Text(
                    'Due ${Format.amount(sale.due)}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: AppColors.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
              ],
            ),
            SaleRowMenu(sale: sale),
          ],
        ),
      ),
    );
  }
}

class _NoRecentSales extends StatelessWidget {
  const _NoRecentSales();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Icon(
            Icons.receipt_long_outlined,
            size: 40,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No sales in the last '
            '${SaleFilters.defaultLookbackDays} days',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _RecentSkeleton extends StatelessWidget {
  const _RecentSkeleton();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.outline;

    Widget block(double height) => Container(
      height: height,
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Column(
        children: [block(64), block(64), block(64)],
      ),
    );
  }
}

class _RecentError extends StatelessWidget {
  const _RecentError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apiError = error is ApiException ? error as ApiException : null;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 40, color: theme.colorScheme.error),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Could not load recent sales',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            apiError?.message ?? 'Check your connection and try again.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}
