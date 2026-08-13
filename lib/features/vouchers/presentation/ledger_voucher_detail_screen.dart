import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../data/models/voucher.dart';
import 'widgets/voucher_detail_widgets.dart';

/// Read-only view of a Ledger Payment Voucher. LPV isn't tied to invoices, so
/// this is just the voucher's own fields (no Invoice Payments section).
///
/// Per Ledger_payment_voucher_issues.md §1, View shows the same swapped
/// Debit/Credit label as the list (stored credit -> Debit, debit -> Credit).
class LedgerVoucherDetailScreen extends StatelessWidget {
  const LedgerVoucherDetailScreen({required this.voucher, super.key});

  final LedgerPaymentVoucher voucher;

  @override
  Widget build(BuildContext context) {
    final v = voucher;
    final txn = v.transactionType.isEmpty
        ? '—'
        : ledgerListViewTransactionLabel(v.transactionType);

    return Scaffold(
      appBar: AppBar(title: Text(v.voucherNo)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          VoucherDetailCard(
            title: 'Ledger Payment Voucher',
            rows: [
              VoucherDetailRow('Voucher No', v.voucherNo),
              VoucherDetailRow('Date', v.date),
              VoucherDetailRow('Warehouse', v.warehouse?.name),
              VoucherDetailRow('Person Type', v.person?.type),
              VoucherDetailRow('Person', v.person?.name),
              VoucherDetailRow('Sale Person', v.biller?.name),
              VoucherDetailRow('Transaction Type', txn),
              VoucherDetailRow('Payment Method', v.paymentMethod),
              if (v.bank != null) VoucherDetailRow('Bank', v.bank?.name),
              if (v.chequeNo != null) VoucherDetailRow('Cheque No', v.chequeNo),
              if (v.chequeDate != null)
                VoucherDetailRow('Cheque Date', v.chequeDate),
              VoucherDetailRow('Amount', v.amount.toStringAsFixed(2)),
              VoucherDetailRow('Details', v.details),
              VoucherDetailRow(
                'Created By',
                v.createdBy == null ? null : 'User #${v.createdBy}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
