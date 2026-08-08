import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_message.dart';
import '../../../data/datasources/remote/vouchers_api.dart';
import '../../../data/models/auth_user.dart';
import '../../../data/models/voucher.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/voucher_providers.dart';
import 'voucher_form_screen.dart';
import 'widgets/paged_list_view.dart';

/// List of Cash Received (CRV) or Cash Payment (CPV) vouchers, parameterised by
/// [type]. Add/Edit/Delete are gated per the role rules in the vouchers doc §4.
class VoucherListScreen extends ConsumerStatefulWidget {
  const VoucherListScreen({required this.type, super.key});

  final VoucherType type;

  @override
  ConsumerState<VoucherListScreen> createState() => _VoucherListScreenState();
}

class _VoucherListScreenState extends ConsumerState<VoucherListScreen> {
  int _reload = 0;

  void _bump() => setState(() => _reload++);

  VoucherType get _type => widget.type;

  @override
  Widget build(BuildContext context) {
    final api = ref.watch(vouchersApiProvider);
    final user = ref.watch(currentUserProvider);
    final canAdd =
        user?.isAdmin == true || user?.can(Permissions.addCashVoucher) == true;

    return Scaffold(
      appBar: AppBar(title: Text(_type.title)),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: const Text('New'),
            )
          : null,
      body: PagedListView<Voucher>(
        reloadToken: _reload,
        emptyMessage: 'No ${_type.title.toLowerCase()}s yet',
        emptyIcon: Icons.receipt_long_outlined,
        fetch: (page) => api.list(VoucherListQuery(type: _type), page: page),
        itemBuilder: (context, v) => _VoucherRow(
          voucher: v,
          canEdit: _canModify(user, Permissions.editCashVoucher, v),
          canDelete: _canModify(user, Permissions.deleteCashVoucher, v),
          onEdit: () => _edit(v),
          onDelete: () => _delete(api, v),
        ),
      ),
    );
  }

  /// Admin can modify any; a non-admin only their own row, and only with the
  /// permission. The server enforces the same, so this just hides doomed
  /// actions.
  bool _canModify(AuthUser? user, String permission, Voucher v) {
    if (user == null) return false;
    if (user.isAdmin) return true;
    return user.can(permission) && v.createdBy == user.id;
  }

  Future<void> _create() async {
    final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(builder: (_) => VoucherFormScreen(type: _type)),
    );
    if (ok == true && mounted) _bump();
  }

  Future<void> _edit(Voucher v) async {
    final ok = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        builder: (_) => VoucherFormScreen(type: _type, existing: v),
      ),
    );
    if (ok == true && mounted) _bump();
  }

  Future<void> _delete(VouchersApi api, Voucher v) async {
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

class _VoucherRow extends StatelessWidget {
  const _VoucherRow({
    required this.voucher,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final Voucher voucher;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasMenu = canEdit || canDelete;

    return ListTile(
      onTap: canEdit ? onEdit : null,
      title: Text(
        voucher.voucherNo,
        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${voucher.person?.name ?? '-'} · ${voucher.date}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                voucher.totalAmount.toStringAsFixed(2),
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              Text(
                voucher.paymentMethod,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          if (hasMenu)
            PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => [
                if (canEdit)
                  const PopupMenuItem(value: 'edit', child: Text('Edit')),
                if (canDelete)
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
        ],
      ),
    );
  }
}
