import 'package:flutter/material.dart';

import '../../../data/models/cash_register.dart';

/// A black-on-white rendering of the daily cash-register report, laid out to be
/// rasterised and printed (same section order and `showBalances` rule as the
/// on-screen view and the web print view).
class CashRegisterPaper extends StatelessWidget {
  const CashRegisterPaper({
    required this.report,
    this.companyName,
    this.designWidth = 384,
    super.key,
  });

  final CashRegisterReport report;
  final String? companyName;
  final double designWidth;

  static const _ink = Color(0xFF000000);
  static const _line = BorderSide(color: _ink);

  String _n(double v) => v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: designWidth,
      color: Colors.white,
      padding: const EdgeInsets.all(8),
      child: DefaultTextStyle(
        style: const TextStyle(color: _ink, fontSize: 10, height: 1.3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((companyName ?? '').isNotEmpty)
              Text(
                companyName!.toUpperCase(),
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 2),
            const Text(
              'DAILY CASH REGISTER',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              '${report.startDate}  to  ${report.endDate}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10),
            ),
            const SizedBox(height: 4),
            const Divider(color: _ink, height: 8),

            if (report.showBalances)
              _totalLine('Opening Balance', report.openingBalance, bold: true),

            for (final activity in report.activities) ...[
              const SizedBox(height: 4),
              _sectionHeading(activity.activity),
              for (final group in activity.groups) _group(group),
            ],

            const Divider(color: _ink, height: 10),
            _totalLine('Grand Total (Debit)', report.totalDebit),
            _totalLine('Grand Total (Credit)', report.totalCredit),
            _totalLine('Total Cash In', report.totalCashIn),
            _totalLine('Total Cash Out', report.totalCashOut),
            if (report.showBalances)
              _totalLine('Closing Balance', report.closingBalance, bold: true),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeading(String text) => Container(
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: const BoxDecoration(border: Border(bottom: _line)),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        ),
      );

  Widget _group(CashRegisterGroup group) {
    const widths = <int, TableColumnWidth>{
      0: FlexColumnWidth(18),
      1: FlexColumnWidth(34),
      2: FlexColumnWidth(16),
      3: FlexColumnWidth(16),
      4: FlexColumnWidth(16),
    };

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              group.type,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
            ),
          ),
          Table(
            border: TableBorder.all(color: _ink),
            columnWidths: widths,
            children: [
              _row(['Created By', 'Reference', 'Debit', 'Credit', 'Total'],
                  bold: true),
              for (final r in group.rows)
                _row([
                  r.createdBy,
                  r.reference,
                  _n(r.debit),
                  _n(r.credit),
                  _n(r.total),
                ]),
              _row(['', 'Subtotal', _n(group.subtotalDebit),
                  _n(group.subtotalCredit), _n(group.subtotalTotal)],
                  bold: true),
            ],
          ),
        ],
      ),
    );
  }

  TableRow _row(List<String> cells, {bool bold = false}) => TableRow(
        children: [
          for (var i = 0; i < cells.length; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
              child: Text(
                cells[i],
                textAlign: i >= 2 ? TextAlign.right : TextAlign.left,
                style: TextStyle(
                  fontSize: 8,
                  height: 1.15,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
        ],
      );

  Widget _totalLine(String label, double value, {bool bold = false}) =>
      Container(
        decoration: const BoxDecoration(border: Border(bottom: _line)),
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: bold ? 12 : 10,
                  fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ),
            Text(
              _n(value),
              style: TextStyle(
                fontSize: bold ? 12 : 10,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
      );
}
