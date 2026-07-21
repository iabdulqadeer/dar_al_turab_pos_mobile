import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/extensions/formatting.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_colors.dart';
import '../../../data/datasources/remote/sales_api.dart';
import '../../../data/models/auth_user.dart';
import '../../../data/models/sale.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/dashboard_providers.dart';
import 'widgets/stat_card.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(dashboardProvider),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(child: _Greeting(user: user)),
              ...switch (dashboard) {
                AsyncData(:final value) => _content(context, ref, value),
                AsyncError(:final error) => [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _DashboardError(
                      error: error,
                      onRetry: () => ref.invalidate(dashboardProvider),
                    ),
                  ),
                ],
                _ => const [
                  SliverToBoxAdapter(child: _DashboardSkeleton()),
                ],
              },
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(
    BuildContext context,
    WidgetRef ref,
    DashboardData data,
  ) {
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          0,
          AppSpacing.md,
          AppSpacing.md,
        ),
        sliver: SliverGrid.count(
          crossAxisCount: 2,
          crossAxisSpacing: AppSpacing.md,
          mainAxisSpacing: AppSpacing.md,
          childAspectRatio: 1.45,
          children: [
            StatCard(
              label: 'Sales today',
              value: Format.amount(data.today.totalGrand),
              caption: '${data.today.totalCount} invoice'
                  '${data.today.totalCount == 1 ? '' : 's'}',
              icon: Icons.today_outlined,
              accent: AppColors.primary,
              onTap: () => context.go(Routes.sales),
            ),
            StatCard(
              label: 'Sales this month',
              value: Format.amount(data.month.totalGrand),
              caption: '${data.month.totalCount} invoice'
                  '${data.month.totalCount == 1 ? '' : 's'}',
              icon: Icons.calendar_month_outlined,
              accent: AppColors.secondary,
              onTap: () => context.go(Routes.sales),
            ),
            StatCard(
              label: 'Collected this month',
              value: Format.amount(data.month.totalPaid),
              icon: Icons.check_circle_outline,
              accent: AppColors.success,
            ),
            StatCard(
              label: 'Outstanding',
              value: Format.amount(data.month.totalDue),
              caption: data.outstanding.totalCount > 0
                  ? '${data.outstanding.totalCount} unpaid'
                  : 'All settled',
              icon: Icons.error_outline,
              accent: data.month.totalDue > 0.004
                  ? AppColors.error
                  : AppColors.success,
              onTap: () => context.go(Routes.sales),
            ),
          ],
        ),
      ),

      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        sliver: SliverToBoxAdapter(
          child: CollectionCard(
            title: 'This month',
            billed: Format.amount(data.month.totalGrand),
            collected: Format.amount(data.month.totalPaid),
            outstanding: Format.amount(data.month.totalDue),
            rate: data.month.collectionRate,
          ),
        ),
      ),

      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.sm,
        ),
        sliver: SliverToBoxAdapter(
          child: Row(
            children: [
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
        ),
      ),

      if (data.recent.isEmpty)
        const SliverToBoxAdapter(child: _NoRecentSales())
      else
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            0,
            AppSpacing.md,
            AppSpacing.xl,
          ),
          sliver: SliverList.separated(
            itemCount: data.recent.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) =>
                _RecentSaleTile(sale: data.recent[index]),
          ),
        ),
    ];
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
        trailing: Column(
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

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.outline;

    Widget block(double height) => Container(
      height: height,
      decoration: BoxDecoration(
        color: base,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
    );

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: block(104)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: block(104)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(child: block(104)),
              const SizedBox(width: AppSpacing.md),
              Expanded(child: block(104)),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          block(120),
        ],
      ),
    );
  }
}

class _DashboardError extends StatelessWidget {
  const _DashboardError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final apiError = error is ApiException ? error as ApiException : null;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.cloud_off, size: 48, color: theme.colorScheme.error),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Could not load your dashboard',
            style: theme.textTheme.titleMedium?.copyWith(
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
          const SizedBox(height: AppSpacing.lg),
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
