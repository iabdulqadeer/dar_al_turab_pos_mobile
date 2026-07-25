import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/extensions/formatting.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/catalogue.dart';
import '../../domain/cart.dart';

/// Edits one cart line.
///
/// For weight-based goods this is the screen that matters: entering a piece
/// count derives gross weight, waste, and net quantity using the product's
/// per-piece figures, exactly as the web sale form does. All three stay
/// editable afterwards, because the recorded per-piece weights are averages
/// and the physical scale is the authority.
class CartLineEditor extends StatefulWidget {
  const CartLineEditor({required this.line, super.key});

  final CartLine line;

  @override
  State<CartLineEditor> createState() => _CartLineEditorState();
}

class _CartLineEditorState extends State<CartLineEditor> {
  late final CartLine _line = widget.line;

  late final TextEditingController _price;
  late final TextEditingController _qty;
  late final TextEditingController _pcs;
  late final TextEditingController _gross;
  late final TextEditingController _waste;
  late final TextEditingController _discount;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(text: _fmt(_line.unitPrice));
    _qty = TextEditingController(text: _fmt(_line.qty));
    _pcs = TextEditingController(text: _fmt(_line.noOfPcs));
    _gross = TextEditingController(text: _fmt(_line.grossWeight));
    _waste = TextEditingController(text: _fmt(_line.wasteQty));
    _discount = TextEditingController(text: _fmt(_line.discount));
  }

  @override
  void dispose() {
    for (final c in [_price, _qty, _pcs, _gross, _waste, _discount]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Whether the piece-count shortcut can derive the weights automatically.
  /// Requires the product's per-piece masters, which `product-search` does
  /// not yet return.
  bool get _canDeriveFromPieces => _line.product.hasPerPieceWeights;

  /// Whether to show the gross/waste fields at all.
  ///
  /// POST /sales accepts these for any line, and this business trades by
  /// weight, so they are offered whenever the sale unit looks like a weight
  /// — or whenever the line already carries weight data.
  bool get _isWeightBased {
    if (_canDeriveFromPieces) return true;
    if (_line.grossWeight > 0 || _line.wasteQty > 0) return true;

    final unit = _line.unit?.name.toUpperCase() ?? '';
    return unit == 'KG' || unit == 'G' || unit == 'GRAM' || unit == 'GRAMS';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final units = _line.product.sellableUnits;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _line.product.name,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'In stock: ${Format.quantity(_line.product.stock)}'
                '${_line.unit == null ? '' : ' ${_line.unit!.name}'}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _line.exceedsStock
                      ? AppColors.error
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: _line.exceedsStock ? FontWeight.w700 : null,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              if (_isWeightBased) ...[
                if (_canDeriveFromPieces) ...[
                  _Label('Pieces'),
                  _NumberField(
                    controller: _pcs,
                    hint: 'Number of pieces',
                    onChanged: _onPiecesChanged,
                  ),
                  Text(
                    'Derives gross weight, waste, and net from the product\'s '
                    'per-piece figures. Edit any of them below to override.',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ] else ...[
                  _Label('Pieces'),
                  _NumberField(
                    controller: _pcs,
                    hint: 'Number of pieces',
                    // No per-piece masters available, so this is recorded on
                    // the sale but cannot derive the weights.
                    onChanged: (v) => setState(() => _line.noOfPcs = v),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],

                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Label('Gross weight'),
                          _NumberField(
                            controller: _gross,
                            onChanged: (v) => setState(() {
                              _line.grossWeight = v;
                              _line.syncWasteFromWeights();
                              _waste.text = _fmt(_line.wasteQty);
                            }),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _Label('Waste'),
                          _NumberField(
                            controller: _waste,
                            onChanged: (v) => setState(() => _line.wasteQty = v),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Label(_isWeightBased ? 'Net weight' : 'Quantity'),
                        _NumberField(
                          controller: _qty,
                          onChanged: (v) => setState(() {
                            _line.qty = v;
                            if (_isWeightBased) {
                              _line.syncWasteFromWeights();
                              _waste.text = _fmt(_line.wasteQty);
                            }
                          }),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Label('Unit price'),
                        _NumberField(
                          controller: _price,
                          onChanged: (v) => setState(() => _line.unitPrice = v),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),

              if (units.length > 1) ...[
                _Label('Unit'),
                DropdownButtonFormField<SaleUnit>(
                  initialValue: _line.unit,
                  isExpanded: true,
                  items: units
                      .map(
                        (u) => DropdownMenuItem(value: u, child: Text(u.name)),
                      )
                      .toList(),
                  onChanged: (u) => setState(() => _line.unit = u),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              _Label('Line discount'),
              _NumberField(
                controller: _discount,
                onChanged: (v) => setState(() => _line.discount = v),
              ),
              const SizedBox(height: AppSpacing.lg),

              _Totals(line: _line),
              const SizedBox(height: AppSpacing.lg),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: _line.qty > 0
                          ? () => Navigator.pop(context, _line)
                          : null,
                      child: const Text('Done'),
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

  void _onPiecesChanged(double pieces) {
    setState(() {
      _line.applyPieceCount(
        pieces,
        perPieceGrossWeightGrams: _line.product.perPieceGrossWeight,
        perPieceWasteGrams: _line.product.perPieceWaste,
      );
      _gross.text = _fmt(_line.grossWeight);
      _waste.text = _fmt(_line.wasteQty);
      _qty.text = _fmt(_line.qty);
    });
  }

  /// Trims trailing zeros so a field shows "3" rather than "3.00".
  static String _fmt(double v) {
    if (v == 0) return '';
    final s = v.toStringAsFixed(2);
    return s.endsWith('.00') ? s.substring(0, s.length - 3) : s;
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.onChanged,
    this.hint,
  });

  final TextEditingController controller;
  final ValueChanged<double> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
      ],
      // No isDense: these weight/price fields are the cashier's main tap
      // targets, so they keep the theme's full ~52px height for glove use.
      decoration: InputDecoration(hintText: hint),
      onChanged: (text) => onChanged(double.tryParse(text) ?? 0),
    );
  }
}

class _Totals extends StatelessWidget {
  const _Totals({required this.line});

  final CartLine line;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget row(String label, String value, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Text(
            value,
            style: bold
                ? theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  )
                : theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          row(
            'Tax'
            '${line.taxRate > 0 ? ' (${Format.quantity(line.taxRate)}%'
                  '${line.product.pricing.isTaxInclusive ? ', inclusive' : ''})' : ''}',
            Format.amount(line.tax),
          ),
          const Divider(height: AppSpacing.md),
          row('Line total', Format.amount(line.subtotal), bold: true),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}
