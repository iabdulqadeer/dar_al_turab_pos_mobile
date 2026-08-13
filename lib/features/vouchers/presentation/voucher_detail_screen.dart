import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/app_message.dart';
import '../../../data/models/voucher.dart';
import '../providers/voucher_providers.dart';
import 'widgets/voucher_detail_widgets.dart';

/// Read-only view of a Cash Received / Cash Payment voucher: its header fields
/// plus the Invoice Payments allocated on it. Each payment line can be deleted
/// (when [canModify]) via the invoice-payment delete endpoint, which returns the
/// recomputed voucher.
class VoucherDetailScreen extends ConsumerStatefulWidget {
  const VoucherDetailScreen({
    required this.voucher,
    required this.canModify,
    super.key,
  });

  final Voucher voucher;
  final bool canModify;

  @override
  ConsumerState<VoucherDetailScreen> createState() =>
      _VoucherDetailScreenState();
}

class _VoucherDetailScreenState extends ConsumerState<VoucherDetailScreen> {
  late Voucher _voucher = widget.voucher;
  bool _changed = false;

  @override
  Widget build(BuildContext context) {
    final v = _voucher;
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(v.voucherNo)),
        body: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            VoucherDetailCard(
              title: 'Voucher',
              rows: [
                VoucherDetailRow('Voucher No', v.voucherNo),
                VoucherDetailRow('Voucher Type', v.voucherType),
                VoucherDetailRow('Date', v.date),
                VoucherDetailRow('Warehouse', v.warehouse?.name),
                VoucherDetailRow('Person Type', v.person?.type),
                VoucherDetailRow('Person', v.person?.name),
                VoucherDetailRow('Sale Person', v.biller?.name),
                VoucherDetailRow('Payment Method', v.paymentMethod),
                if (v.bank != null) VoucherDetailRow('Bank', v.bank?.name),
                if (v.chequeNo != null)
                  VoucherDetailRow('Cheque No', v.chequeNo),
                if (v.chequeDate != null)
                  VoucherDetailRow('Cheque Date', v.chequeDate),
                VoucherDetailRow(
                  'Created By',
                  v.createdBy == null ? null : 'User #${v.createdBy}',
                ),
                VoucherDetailRow('Total Amount', v.totalAmount.toStringAsFixed(2)),
                VoucherDetailRow(
                  'Total Discount',
                  v.totalDiscount.toStringAsFixed(2),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),

            Text(
              'Invoice Payments',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),

            if (v.invoices.isEmpty)
              Text(
                'No invoice payments on this voucher.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ...v.invoices.map(
                (ip) => _InvoicePaymentCard(
                  payment: ip,
                  canDelete: widget.canModify,
                  onDelete: () => _deletePayment(ip),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePayment(VoucherInvoice ip) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove payment?'),
        content: Text(
          'Remove the payment on ${ip.referenceNumber} from this voucher?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    try {
      final updated = await ref
          .read(vouchersApiProvider)
          .deleteInvoicePayment(_voucher.id, ip.invoicePaymentId);
      if (!mounted) return;
      setState(() {
        _voucher = updated;
        _changed = true;
      });
      showAppMessage(context, 'Payment removed.', kind: AppMessageKind.success);
    } on ApiException catch (e) {
      if (!mounted) return;
      showAppMessage(context, e.message, kind: AppMessageKind.error);
    }
  }
}

class _InvoicePaymentCard extends StatelessWidget {
  const _InvoicePaymentCard({
    required this.payment,
    required this.canDelete,
    required this.onDelete,
  });

  final VoucherInvoice payment;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    payment.referenceNumber,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  payment.paidAmount.toStringAsFixed(2),
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                if (canDelete)
                  IconButton(
                    icon: const Icon(Icons.delete_outline,
                        size: 20, color: AppColors.error),
                    tooltip: 'Remove payment',
                    onPressed: onDelete,
                  ),
              ],
            ),
            VoucherDetailRow('Discount', payment.discountAmount.toStringAsFixed(2)),
            VoucherDetailRow('Created by', payment.createdBy?.name),
            VoucherDetailRow('Date', payment.date),
            if (payment.note != null && payment.note!.trim().isNotEmpty)
              VoucherDetailRow('Note', payment.note),
          ],
        ),
      ),
    );
  }
}
