import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_message.dart';
import '../../../data/datasources/remote/ledger_payment_vouchers_api.dart';
import '../../../data/models/voucher.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/voucher_providers.dart';
import 'ledger_voucher_detail_screen.dart';
import 'ledger_voucher_form_screen.dart';
import 'widgets/paged_list_view.dart';
import 'widgets/voucher_icon.dart';

/// List of Ledger Payment Vouchers. Any user can create; only an admin sees
/// Edit/Delete (the server rejects both for non-admins, even on their own row).
class LedgerVoucherListScreen extends ConsumerStatefulWidget {
  const LedgerVoucherListScreen({super.key});

  @override
  ConsumerState<LedgerVoucherListScreen> createState() =>
      _LedgerVoucherListScreenState();
}

class _LedgerVoucherListScreenState
    extends ConsumerState<LedgerVoucherListScreen> {
  int _reload = 0;

  void _bump() => setState(() => _reload++);

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(ledgerVouchersApiProvider);
    final isAdmin = ref.watch(currentUserProvider)?.isAdmin ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Ledger Payment Vouchers')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: PagedListView<LedgerPaymentVoucher>(
        reloadToken: _reload,
        emptyMessage: 'No ledger vouchers yet',
        emptyIcon: Icons.account_balance_wallet_outlined,
        fetch: (page) =>
            api.list(const LedgerVoucherListQuery(), page: page),
        itemBuilder: (context, v) => _LedgerRow(
          voucher: v,
          isAdmin: isAdmin,
          onView: () => _view(v),
          onEdit: () => _edit(v),
          onDelete: () => _delete(api, v),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const LedgerVoucherFormScreen()),
    );
    if (ok == true && mounted) _bump();
  }

  Future<void> _view(LedgerPaymentVoucher v) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LedgerVoucherDetailScreen(voucher: v)),
    );
  }

  Future<void> _edit(LedgerPaymentVoucher v) async {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => LedgerVoucherFormScreen(existing: v),
      ),
    );
    if (ok == true && mounted) _bump();
  }

  Future<void> _delete(LedgerPaymentVouchersApi api, LedgerPaymentVoucher v) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete voucher?'),
        content: Text('Delete ${v.voucherNo}? This cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await api.destroy(v.id);
      if (!mounted) return;
      showAppMessage(context, 'Voucher deleted.', kind: AppMessageKind.success);
      _bump();
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppMessage(context, e.message, kind: AppMessageKind.error);
    }
  }
}

class _LedgerRow extends StatelessWidget {
  const _LedgerRow({
    required this.voucher,
    required this.isAdmin,
    required this.onView,
    required this.onEdit,
    required this.onDelete,
  });

  final LedgerPaymentVoucher voucher;
  final bool isAdmin;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // List shows the swapped label (stored credit -> Debit, debit -> Credit),
    // shared with View. The colour follows the label shown here; the form is
    // untouched.
    final displayLabel =
        ledgerListViewTransactionLabel(voucher.transactionType);
    final displayIsDebit = displayLabel == 'Debit';
    final personType = voucher.person?.type;

    return ListTile(
      // Tap opens View; Edit/Delete live in the ⋮ menu (admin only).
      onTap: onView,
      leading: VoucherLeadingIcon(
        icon: ledgerVoucherIcon,
        color: AppColors.primary,
      ),
      title: Text(
        voucher.voucherNo,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${voucher.person?.name ?? '-'} · ${voucher.date}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // Issue 4: label the party as Customer or Supplier.
          if (personType != null && personType.isNotEmpty)
            Text(
              personType,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                voucher.amount.toStringAsFixed(2),
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: displayIsDebit
                      ? AppColors.success
                      : theme.colorScheme.error,
                ),
              ),
              Text(
                '$displayLabel · ${voucher.paymentMethod}',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'view' => onView(),
              'edit' => onEdit(),
              _ => onDelete(),
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'view', child: Text('View')),
              // LPV Edit/Delete never appear for non-admins, even on own row.
              if (isAdmin) ...[
                const PopupMenuItem(value: 'edit', child: Text('Edit')),
                const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
