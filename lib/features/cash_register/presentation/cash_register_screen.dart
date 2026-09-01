import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_message.dart';
import '../../../data/models/cash_register.dart';
import '../../branding/providers/branding_providers.dart';
import '../../printing/printer_transport.dart';
import '../../printing/providers/printer_providers.dart';
import '../providers/cash_register_providers.dart';
import 'cash_register_paper.dart';

const _designWidth = 384.0;

/// The daily cash-register report. Scope (staff-own vs admin-full) and the
/// Opening/Closing balance display rule are driven entirely by the server
/// response's `user_id`.
class CashRegisterScreen extends ConsumerStatefulWidget {
  const CashRegisterScreen({super.key});

  @override
  ConsumerState<CashRegisterScreen> createState() =>
      _CashRegisterScreenState();
}

class _CashRegisterScreenState extends ConsumerState<CashRegisterScreen> {
  final _captureKey = GlobalKey();
  bool _printing = false;

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(cashRegisterReportProvider);
    final filters = ref.watch(cashRegisterFiltersProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cash Register'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range_outlined),
            tooltip: 'Date range',
            onPressed: _pickRange,
          ),
          IconButton(
            icon: _printing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.print_outlined),
            tooltip: 'Print',
            onPressed: async.hasValue && !_printing ? _print : null,
          ),
        ],
      ),
      body: Column(
        children: [
          _RangeBar(filters: filters),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _ErrorView(
                message: e is ApiException ? e.message : 'Could not load the register.',
                onRetry: () => ref.invalidate(cashRegisterReportProvider),
              ),
              data: (report) => _report(report),
            ),
          ),
        ],
      ),
    );
  }

  Widget _report(CashRegisterReport report) {
    if (report.isEmpty && !report.showBalances) {
      return const _EmptyView();
    }

    final company = ref.watch(brandingProvider)?.displayName;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            if (report.showBalances)
              _TotalRow(label: 'Opening Balance', value: report.openingBalance, bold: true),
            if (report.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: _EmptyView(),
              ),
            for (final activity in report.activities) ...[
              const SizedBox(height: AppSpacing.md),
              _SectionHeading(activity.activity),
              for (final group in activity.groups) _GroupCard(group: group),
            ],
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            _TotalRow(label: 'Grand Total (Debit)', value: report.totalDebit),
            _TotalRow(label: 'Grand Total (Credit)', value: report.totalCredit),
            _TotalRow(label: 'Total Cash In', value: report.totalCashIn),
            _TotalRow(label: 'Total Cash Out', value: report.totalCashOut),
            if (report.showBalances)
              _TotalRow(label: 'Closing Balance', value: report.closingBalance, bold: true),
          ],
        ),
        // Off-screen capture target for raster printing.
        Positioned(
          left: -100000,
          top: 0,
          child: RepaintBoundary(
            key: _captureKey,
            child: CashRegisterPaper(
              report: report,
              companyName: company,
              designWidth: _designWidth,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickRange() async {
    final filters = ref.read(cashRegisterFiltersProvider);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: DateTimeRange(
        start: filters.startDate,
        end: filters.endDate,
      ),
    );
    if (picked != null) {
      ref
          .read(cashRegisterFiltersProvider.notifier)
          .setRange(picked.start, picked.end);
    }
  }

  Future<void> _print() async {
    final controller = ref.read(printerControllerProvider);
    if (!controller.hasPrinter) {
      _toast('No printer paired. Set one up in Printer settings first.',
          isError: true);
      return;
    }
    setState(() => _printing = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final dotWidth = controller.saved!.charactersPerLine * 12;
      final pixelRatio = dotWidth / _designWidth;
      final boundary = _captureKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) {
        _toast('Could not render the register. Try again.', isError: true);
        return;
      }
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      await ref.read(printerControllerProvider.notifier).reconnect();
      await ref.read(receiptPrinterProvider).printImages([image]);
      if (mounted) _toast('Register sent to ${controller.saved!.name}.');
    } on PrintException catch (e) {
      if (mounted) _toast('${e.message} ${e.remedy}', isError: true);
    } on ApiException catch (e) {
      if (mounted) _toast(e.message, isError: true);
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  void _toast(String message, {bool isError = false}) {
    showAppMessage(
      context,
      message,
      kind: isError ? AppMessageKind.error : AppMessageKind.success,
    );
  }
}

class _RangeBar extends StatelessWidget {
  const _RangeBar({required this.filters});

  final CashRegisterFilters filters;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final same = filters.startDate == filters.endDate;
    final label = same
        ? CashRegisterFilters.format(filters.startDate)
        : '${CashRegisterFilters.format(filters.startDate)}  →  '
            '${CashRegisterFilters.format(filters.endDate)}';
    return Material(
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        child: Row(
          children: [
            const Icon(Icons.event_outlined, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Text(label, style: theme.textTheme.bodyMedium),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final CashRegisterGroup group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              group.type,
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const Divider(height: AppSpacing.md),
            for (final row in group.rows) _RowTile(row: row),
            const Divider(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: Text('Subtotal',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w800)),
                ),
                Text(
                  group.subtotalTotal.toStringAsFixed(2),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row});

  final CashRegisterRow row;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(row.reference, style: theme.textTheme.bodySmall),
                Text(
                  'by ${row.createdBy}  ·  Dr ${row.debit.toStringAsFixed(2)}'
                  '  ·  Cr ${row.credit.toStringAsFixed(2)}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            row.total.toStringAsFixed(2),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFamily: 'monospace',
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.label, required this.value, this.bold = false});

  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = (bold ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)
        ?.copyWith(fontWeight: bold ? FontWeight.w800 : FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(
            value.toStringAsFixed(2),
            style: style?.copyWith(fontFamily: 'monospace'),
          ),
        ],
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.point_of_sale_outlined,
                size: 48, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: AppSpacing.md),
            Text('No cash activity', style: theme.textTheme.titleSmall),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'There are no register entries in this date range.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 40, color: AppColors.error),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
