import 'package:flutter/material.dart';

import '../../../data/models/receipt.dart';
import '../../../data/models/sale.dart';

/// A pixel-faithful Flutter rendering of `resources/views/backend/sale/invoice.blade.php`.
///
/// This is drawn on white, in pure black, and is meant to be rasterised to a
/// bitmap and printed on the thermal printer (so the paper looks exactly like
/// the web invoice — real borders, a bordered item table, the two-column info
/// grid, bold section titles and signature lines), and shown as an on-screen
/// preview of that same output.
///
/// It is laid out at [designWidth] logical pixels (a comfortable canvas that
/// mirrors the blade's ~mm proportions); the caller captures it at a high
/// pixelRatio so the printed dots stay crisp.
class InvoicePaper extends StatelessWidget {
  const InvoicePaper({
    required this.document,
    required this.copyLabel,
    this.designWidth = 384,
    super.key,
  });

  final InvoiceDocument document;

  /// "CUSTOMER COPY" / "COMPANY COPY".
  final String copyLabel;
  final double designWidth;

  static const _ink = Color(0xFF000000);
  static const _paper = Color(0xFFFFFFFF);
  static const _line = BorderSide(color: _ink);

  @override
  Widget build(BuildContext context) {
    final sale = document.sale;
    final totals = sale.totals;
    final ccy = document.currencyCode;

    return Container(
      width: designWidth,
      color: _paper,
      padding: const EdgeInsets.all(8),
      child: DefaultTextStyle(
        style: const TextStyle(
          color: _ink,
          fontSize: 11,
          height: 1.3,
          fontFamily: 'Arial',
          fontFamilyFallback: ['Roboto', 'sans-serif'],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            _title(),
            _copyLabel(),
            const SizedBox(height: 4),
            _infoGrid(sale),
            const SizedBox(height: 6),
            _itemsTable(sale),
            const SizedBox(height: 6),
            _sectionTitle('SUMMARY'),
            _summary(totals, ccy),
            const SizedBox(height: 4),
            _sectionTitle('IN WORDS'),
            _amountInWords(ccy),
            const SizedBox(height: 18),
            _signatures(),
            _footer(sale.referenceNo),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _header() {
    final company = document.company;
    final warehouse = document.sale.warehouse;
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: _line)),
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        children: [
          Text(
            (company.name ?? '').toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              height: 1.2,
            ),
          ),
          if ((company.vatRegistrationNumber ?? '').isNotEmpty)
            _muted('TRN: ${company.vatRegistrationNumber}'),
          if ((warehouse?.address ?? '').isNotEmpty) _muted(warehouse!.address!),
          if ((warehouse?.phone ?? '').isNotEmpty)
            _muted('Phone Number: ${warehouse!.phone}'),
        ],
      ),
    );
  }

  Widget _muted(String text) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      );

  // ── Title / copy label ────────────────────────────────────────────────────
  Widget _title() => Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 3),
        decoration: const BoxDecoration(border: Border(bottom: _line)),
        child: const Text(
          'TAX INVOICE',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      );

  Widget _copyLabel() => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          copyLabel.toUpperCase(),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
      );

  // ── Info grid (two columns, key/value pairs) ─────────────────────────────
  Widget _infoGrid(SaleDetail sale) {
    final salesPerson = sale.biller?.name ?? sale.createdBy?.name ?? '-';
    final pairs = <List<String>>[
      ['Date', _formatDate(sale.date), 'Invoice #', sale.referenceNo],
      [
        'Customer',
        sale.customer?.name ?? '-',
        'Mobile #',
        sale.customer?.phone ?? '-',
      ],
      [
        'Address',
        sale.customer?.address ?? '-',
        'TRN',
        sale.customer?.trnNumber ?? '-',
      ],
      ['Sales Person', salesPerson, 'Sale Status', sale.saleStatusText],
      ['Payment Status', sale.paymentStatusText, '', ''],
    ];

    return Column(
      children: [
        for (final row in pairs)
          Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: _kv(row[0], row[1])),
                const SizedBox(width: 8),
                Expanded(
                  child: row[2].isEmpty ? const SizedBox() : _kv(row[2], row[3]),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _kv(String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          Text(value),
        ],
      );

  // ── Item table ────────────────────────────────────────────────────────────
  Widget _itemsTable(SaleDetail sale) {
    // Column flex mirrors the blade's percentage widths.
    const widths = <int, TableColumnWidth>{
      0: FlexColumnWidth(4),
      1: FlexColumnWidth(20),
      2: FlexColumnWidth(9),
      3: FlexColumnWidth(9),
      4: FlexColumnWidth(9),
      5: FlexColumnWidth(9),
      6: FlexColumnWidth(7),
      7: FlexColumnWidth(11),
      8: FlexColumnWidth(9),
      9: FlexColumnWidth(11),
    };

    double totalPcs = 0, totalGross = 0, totalNet = 0, totalWaste = 0;
    double totalTax = 0, itemTotal = 0;
    for (final i in sale.items) {
      totalPcs += i.noOfPcs;
      totalGross += i.grossWeight;
      totalNet += i.qty;
      totalWaste += i.wasteQty;
      totalTax += i.tax;
      itemTotal += i.total;
    }

    return Table(
      border: TableBorder.all(color: _ink),
      columnWidths: widths,
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        _headRow(const [
          '#', 'Product', 'Pcs', 'G.Wt', 'N.Wt', 'Waste', 'Unit', 'Rate',
          'Tax', 'Total',
        ]),
        for (var i = 0; i < sale.items.length; i++)
          _itemRow(i + 1, sale.items[i]),
        _totalRow(totalPcs, totalGross, totalNet, totalWaste, totalTax,
            itemTotal),
      ],
    );
  }

  TableRow _headRow(List<String> cells) => TableRow(
        children: [
          for (final c in cells)
            _cell(
              c,
              align: TextAlign.center,
              bold: true,
              fontSize: 9,
            ),
        ],
      );

  TableRow _itemRow(int n, SaleItem item) => TableRow(
        children: [
          _cell('$n', align: TextAlign.center, fontSize: 9),
          _cell(item.displayName,
              align: TextAlign.left, bold: true, fontSize: 8),
          _cell(_n2(item.noOfPcs), align: TextAlign.center, fontSize: 9),
          _cell(_n2(item.grossWeight), align: TextAlign.center, fontSize: 9),
          _cell(_n2(item.qty), align: TextAlign.center, fontSize: 9),
          _cell(_n2(item.wasteQty), align: TextAlign.center, fontSize: 9),
          _cell(item.saleUnit ?? '-', align: TextAlign.center, fontSize: 9),
          _cell(_n2(item.netUnitPrice), align: TextAlign.center, fontSize: 9),
          _cell(_n2(item.tax), align: TextAlign.center, fontSize: 9),
          _cell(_n2(item.total), align: TextAlign.center, fontSize: 9),
        ],
      );

  TableRow _totalRow(double pcs, double gross, double net, double waste,
          double tax, double total) =>
      TableRow(
        children: [
          _cell('Total', align: TextAlign.left, bold: true, fontSize: 9),
          _cell('', fontSize: 9),
          _cell(_n2(pcs), align: TextAlign.center, bold: true, fontSize: 9),
          _cell(_n2(gross), align: TextAlign.center, bold: true, fontSize: 9),
          _cell(_n2(net), align: TextAlign.center, bold: true, fontSize: 9),
          _cell(_n2(waste), align: TextAlign.center, bold: true, fontSize: 9),
          _cell('', fontSize: 9),
          _cell('', fontSize: 9),
          _cell(_n2(tax), align: TextAlign.center, bold: true, fontSize: 9),
          _cell(_n2(total), align: TextAlign.center, bold: true, fontSize: 9),
        ],
      );

  Widget _cell(String text,
          {TextAlign align = TextAlign.center,
          bool bold = false,
          double fontSize = 9}) =>
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        child: Text(
          text,
          textAlign: align,
          style: TextStyle(
            fontSize: fontSize,
            height: 1.2,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      );

  // ── Summary ───────────────────────────────────────────────────────────────
  Widget _summary(SaleTotals t, String ccy) {
    Widget row(String label, String value, {bool grand = false}) => Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: _line,
              top: grand ? _line : BorderSide.none,
            ),
          ),
          padding: EdgeInsets.symmetric(vertical: grand ? 8 : 7),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: grand ? 14 : 11,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: grand ? 14 : 12,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        );

    return Column(
      children: [
        row('Sub Total', _n2(t.subTotal)),
        row('Total Tax', _n2(t.totalTax)),
        row('Discount', _n2(t.totalDiscount + t.orderDiscount)),
        row('Grand Total', '$ccy ${_n2(t.grandTotal)}', grand: true),
        row('Paid', _n2(t.paidAmount)),
        row('Due', _n2(t.due)),
      ],
    );
  }

  // ── In words / notes / signatures / footer ───────────────────────────────
  Widget _amountInWords(String ccy) {
    final words = document.amountInWords?.replaceAll('-', ' ') ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text('$ccy $words only'),
    );
  }

  Widget _sectionTitle(String text) => Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        padding: const EdgeInsets.symmetric(vertical: 4),
        decoration: const BoxDecoration(border: Border(bottom: _line)),
        child: Text(
          text,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
        ),
      );

  Widget _signatures() => Row(
        children: [
          Expanded(child: _sigLine('Sales Person Signature')),
          const SizedBox(width: 14),
          Expanded(child: _sigLine('Customer Signature')),
        ],
      );

  Widget _sigLine(String label) => Container(
        decoration: const BoxDecoration(border: Border(top: _line)),
        padding: const EdgeInsets.only(top: 8),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
      );

  Widget _footer(String reference) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.only(top: 8),
        decoration: const BoxDecoration(border: Border(top: _line)),
        child: Column(
          children: [
            const Text('Thank You',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
            Text('Invoice / $reference',
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 11)),
          ],
        ),
      );

  // ── helpers ───────────────────────────────────────────────────────────────
  static String _n2(double v) => v.toStringAsFixed(2);

  static String _formatDate(DateTime? date) {
    if (date == null) return '-';
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June', 'July',
      'August', 'September', 'October', 'November', 'December',
    ];
    final h = date.hour == 0 ? 12 : (date.hour > 12 ? date.hour - 12 : date.hour);
    final m = date.minute.toString().padLeft(2, '0');
    final ap = date.hour < 12 ? 'AM' : 'PM';
    return '${months[date.month - 1]} ${date.day}, ${date.year} $h:$m $ap';
  }
}
