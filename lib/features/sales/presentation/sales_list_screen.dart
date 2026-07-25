import 'package:flutter/material.dart';
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
import '../../../data/models/sale_status.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/sales_providers.dart';
import 'widgets/status_chip.dart';

class SalesListScreen extends ConsumerStatefulWidget {
  const SalesListScreen({super.key});

  @override
  ConsumerState<SalesListScreen> createState() => _SalesListScreenState();
}

class _SalesListScreenState extends ConsumerState<SalesListScreen> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Prefetch before the user hits the bottom so scrolling stays smooth.
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(salesListProvider.notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(salesListProvider);
    final filters = ref.watch(saleFiltersProvider);
    final canCreateSale =
        ref.watch(currentUserProvider)?.can(Permissions.salesAdd) ?? false;

    return Scaffold(
      // FAB declared here (not on the shell) so it shows on the Sales list only,
      // never on a sale's detail page pushed over it.
      floatingActionButton: canCreateSale
          ? FloatingActionButton.extended(
              onPressed: () => context.push(Routes.pos),
              icon: const Icon(Icons.add_shopping_cart),
              label: const Text('New sale'),
            )
          : null,
      appBar: AppBar(
        title: const Text('Sales'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: filters.hasActiveFilters,
              label: Text('${filters.activeFilterCount}'),
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'Filters',
            onPressed: _openFilters,
          ),
          const AppOverflowMenu(),
        ],
        // Only the search stays pinned; the summary moved into the scrolling
        // list so it gives its vertical space back as you scroll results.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _SearchField(
            controller: _searchController,
            onSubmitted: (value) =>
                ref.read(saleFiltersProvider.notifier).setSearch(value),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(salesListProvider.notifier).refresh(),
        child: _buildBody(state, filters),
      ),
    );
  }

  Widget _buildBody(SalesListState state, SaleFilters filters) {
    if (state.isLoading && state.items.isEmpty) {
      return const _LoadingList();
    }

    if (state.error != null && state.items.isEmpty) {
      return _ErrorView(
        error: state.error!,
        onRetry: () => ref.read(salesListProvider.notifier).refresh(),
      );
    }

    if (state.isEmpty) {
      return const _EmptyView();
    }

    // Index 0 is the summary header (scrolls away with the list); the rest are
    // sale cards, then an optional load-more spinner.
    const headerCount = 1;

    return ListView.separated(
      controller: _scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount:
          headerCount + state.items.length + (state.isLoadingMore ? 1 : 0),
      separatorBuilder: (_, index) =>
          SizedBox(height: index == 0 ? AppSpacing.md : AppSpacing.sm),
      itemBuilder: (context, index) {
        if (index == 0) {
          return _SummaryBar(state: state, filters: filters);
        }

        final itemIndex = index - headerCount;
        if (itemIndex >= state.items.length) {
          return const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Center(child: CircularProgressIndicator()),
          );
        }

        final sale = state.items[itemIndex];
        return _SaleCard(
          sale: sale,
          onTap: () => context.push('${Routes.sales}/${sale.id}'),
        );
      },
    );
  }

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<SaleFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _FilterSheet(initial: ref.read(saleFiltersProvider)),
    );

    if (result != null) {
      ref.read(saleFiltersProvider.notifier).update(result);
      _searchController.text = result.search ?? '';
    }
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller, required this.onSubmitted});

  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: TextField(
        controller: controller,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Invoice no, customer name or phone',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: ValueListenableBuilder(
            valueListenable: controller,
            builder: (context, value, _) => value.text.isEmpty
                ? const SizedBox.shrink()
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    tooltip: 'Clear search',
                    onPressed: () {
                      controller.clear();
                      onSubmitted('');
                    },
                  ),
          ),
        ),
      ),
    );
  }
}

/// Whole-result-set totals from `meta.summary`. Worth its own row because it
/// covers every matching sale, not just the pages loaded so far.
class _SummaryBar extends StatelessWidget {
  const _SummaryBar({required this.state, required this.filters});

  final SalesListState state;
  final SaleFilters filters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Format.dateRange(filters.startDate, filters.endDate),
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '${state.meta?.total ?? 0} sales',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          _SummaryFigure(
            label: 'Total',
            value: state.summaryGrandTotal,
            color: theme.colorScheme.onSurface,
          ),
          const SizedBox(width: AppSpacing.md),
          _SummaryFigure(
            label: 'Due',
            value: state.summaryDue,
            color: state.summaryDue > 0.004
                ? AppColors.error
                : theme.colorScheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }
}

class _SummaryFigure extends StatelessWidget {
  const _SummaryFigure({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          Format.amount(value),
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _SaleCard extends StatelessWidget {
  const _SaleCard({required this.sale, required this.onTap});

  final SaleListItem sale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    height: 34,
                    width: 34,
                    margin: const EdgeInsets.only(right: AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(
                      Icons.receipt_long_outlined,
                      size: 18,
                      color: AppColors.primary,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      sale.referenceNo,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    Format.amount(sale.grandTotal),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 14,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      sale.customer?.name ?? '-',
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    Format.dateTime(sale.date),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  StatusChip.sale(sale.saleStatus, sale.saleStatusText),
                  StatusChip.payment(
                    sale.paymentStatus,
                    sale.paymentStatusText,
                  ),
                  Text(
                    '${sale.itemCount} item${sale.itemCount == 1 ? '' : 's'}',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
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
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList();

  @override
  Widget build(BuildContext context) {
    // Skeletons rather than a spinner: the list's shape stays stable, so the
    // content does not jump when it arrives.
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: 6,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, _) => const _SkeletonCard(),
    );
  }
}

class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard();

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.outline;

    Widget bar(double widthFactor, double height) => FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(AppRadius.sm),
        ),
      ),
    );

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(0.5, 14),
            const SizedBox(height: AppSpacing.sm),
            bar(0.7, 10),
            const SizedBox(height: AppSpacing.sm),
            bar(0.35, 10),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: AppSpacing.xxl * 2),
        Icon(
          Icons.receipt_long_outlined,
          size: 56,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text(
            'No sales in this period',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: Text(
            'Try widening the date range or clearing filters.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry});

  final ApiException error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // A permissions failure is not retryable, so do not offer a retry that
    // will simply fail the same way.
    final canRetry = error.code != ApiErrorCode.forbidden;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Icon(Icons.error_outline, size: 56, color: theme.colorScheme.error),
        const SizedBox(height: AppSpacing.md),
        Text(
          error.code == ApiErrorCode.forbidden
              ? 'You do not have access to these sales'
              : 'Could not load sales',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          error.message,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (canRetry) ...[
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ],
    );
  }
}

class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final SaleFilters initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late SaleFilters _filters = widget.initial;

  late final _minTotal = TextEditingController(
    text: widget.initial.minTotal?.toStringAsFixed(2) ?? '',
  );
  late final _maxTotal = TextEditingController(
    text: widget.initial.maxTotal?.toStringAsFixed(2) ?? '',
  );

  String? _amountError;

  @override
  void dispose() {
    _minTotal.dispose();
    _maxTotal.dispose();
    super.dispose();
  }

  /// The server rejects a max below a min, so catch it here rather than
  /// bouncing the user off a 422.
  bool _applyAmountRange() {
    final min = double.tryParse(_minTotal.text.trim());
    final max = double.tryParse(_maxTotal.text.trim());

    if (min != null && max != null && max < min) {
      setState(() => _amountError = 'Maximum must be at least the minimum.');
      return false;
    }

    setState(() {
      _amountError = null;
      _filters = min == null && max == null
          ? _filters.copyWith(clearAmountRange: true)
          : _filters.copyWith(minTotal: min, maxTotal: max);
    });
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Filters',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            _Label('Date range'),
            OutlinedButton.icon(
              onPressed: _pickDateRange,
              icon: const Icon(Icons.date_range_outlined, size: 18),
              label: Text(
                Format.dateRange(_filters.startDate, _filters.endDate),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),

            _Label('Sale status'),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final status in SaleStatus.values)
                  FilterChip(
                    label: Text(status.label),
                    selected: _filters.saleStatus == status,
                    onSelected: (selected) => setState(() {
                      _filters = selected
                          ? _filters.copyWith(saleStatus: status)
                          : _filters.copyWith(clearSaleStatus: true);
                    }),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            _Label('Payment status'),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final status in PaymentStatus.values)
                  FilterChip(
                    label: Text(status.label),
                    selected: _filters.paymentStatus == status,
                    onSelected: (selected) => setState(() {
                      _filters = selected
                          ? _filters.copyWith(paymentStatus: status)
                          : _filters.copyWith(clearPaymentStatus: true);
                    }),
                  ),
              ],
            ),
            _Label('Amount range'),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _minTotal,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Min',
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: _maxTotal,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      labelText: 'Max',
                    ),
                  ),
                ),
              ],
            ),
            if (_amountError != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text(
                  _amountError!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: AppColors.error,
                  ),
                ),
              ),
            const SizedBox(height: AppSpacing.lg),

            _Label('Sort by'),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                for (final option in SaleSort.values)
                  ChoiceChip(
                    label: Text(option.label),
                    selected: _filters.sort == option,
                    onSelected: (_) =>
                        setState(() => _filters = _filters.copyWith(sort: option)),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                _filters.descending ? 'Newest / highest first' : 'Oldest / lowest first',
                style: theme.textTheme.bodyMedium,
              ),
              value: _filters.descending,
              onChanged: (v) =>
                  setState(() => _filters = _filters.copyWith(descending: v)),
            ),
            const SizedBox(height: AppSpacing.xl),

            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pop(context, SaleFilters.recent()),
                    child: const Text('Reset'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      // Fold the amount fields in before returning; they are
                      // free text rather than chips.
                      if (_applyAmountRange()) {
                        Navigator.pop(context, _filters);
                      }
                    },
                    child: const Text('Apply'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(
        start: _filters.startDate,
        end: _filters.endDate,
      ),
    );

    if (picked != null) {
      setState(() {
        _filters = _filters.copyWith(
          startDate: picked.start,
          endDate: picked.end,
        );
      });
    }
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
