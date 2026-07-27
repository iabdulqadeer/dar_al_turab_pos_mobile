import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/auth_user.dart';
import '../../../../data/models/sale.dart';
import '../../../auth/providers/auth_providers.dart';
import '../../../dashboard/providers/dashboard_providers.dart';
import '../../../printing/printer_transport.dart';
import '../../../printing/providers/print_job_providers.dart';
import '../../providers/sales_providers.dart';

/// The per-row overflow menu shared by the Sales list and the Dashboard's
/// Recent Sales. Print is always available; Edit/Delete appear only when the
/// signed-in user holds the matching permission.
class SaleRowMenu extends ConsumerWidget {
  const SaleRowMenu({required this.sale, super.key});

  final SaleListItem sale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final canEdit = user?.can(Permissions.salesEdit) ?? false;
    final canDelete = user?.can(Permissions.salesDelete) ?? false;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert),
      tooltip: 'Sale actions',
      onSelected: (value) {
        switch (value) {
          case 'print':
            _print(context, ref);
          case 'edit':
            context.push('${Routes.sales}/${sale.id}/edit');
          case 'delete':
            _delete(context, ref);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(
          value: 'print',
          child: ListTile(
            leading: Icon(Icons.print_outlined),
            title: Text('Print'),
            contentPadding: EdgeInsets.zero,
          ),
        ),
        if (canEdit)
          const PopupMenuItem(
            value: 'edit',
            child: ListTile(
              leading: Icon(Icons.edit_outlined),
              title: Text('Edit'),
              contentPadding: EdgeInsets.zero,
            ),
          ),
        if (canDelete)
          const PopupMenuItem(
            value: 'delete',
            child: ListTile(
              leading: Icon(Icons.delete_outline, color: AppColors.error),
              title: Text('Delete', style: TextStyle(color: AppColors.error)),
              contentPadding: EdgeInsets.zero,
            ),
          ),
      ],
    );
  }

  Future<void> _print(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Printing…')));
    try {
      await ref.read(printSaleReceiptProvider)(sale.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Receipt sent.')));
    } on PrintException catch (e) {
      _error(messenger, '${e.message} ${e.remedy}');
    } on ApiException catch (e) {
      _error(messenger, e.message);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this sale?'),
        content: Text(
          'Sale ${sale.referenceNo} will be removed and its stock returned. '
          'This cannot be undone.',
        ),
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
      await ref.read(salesApiProvider).destroy(sale.id);
      ref.invalidate(salesListProvider);
      ref.invalidate(dashboardRecentProvider);
      ref.invalidate(saleDetailProvider(sale.id));
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Sale ${sale.referenceNo} deleted.')),
        );
    } on ApiException catch (e) {
      _error(messenger, e.message);
    }
  }

  void _error(ScaffoldMessengerState messenger, String message) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: AppColors.error,
          duration: const Duration(seconds: 5),
        ),
      );
  }
}