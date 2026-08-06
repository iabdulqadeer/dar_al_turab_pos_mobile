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

  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _price;
  late final TextEditingController _qty;
  late final TextEditingController _pcs;
  late final TextEditingController _gross;
  late final TextEditingController _waste;

  @override
  void initState() {
    super.initState();
    _price = TextEditingController(text: _fmt(_line.unitPrice));
    _qty = TextEditingController(text: _fmt(_line.qty));
    _pcs = TextEditingController(text: _fmt(_line.noOfPcs));
    _gross = TextEditingController(text: _fmt(_line.grossWeight));
    _waste = TextEditingController(text: _fmt(_line.wasteQty));
  }

  @override
  void dispose() {
    for (final c in [_price, _qty, _pcs, _gross, _waste]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Whether the piece-count shortcut can derive the weights automatically.
  /// Requires the product's per-piece masters, which `product-search` does
  /// not yet return.
  bool get _canDeriveFromPieces => _line.product.hasPerPieceWeights;

  /// Whether to show the gross/waste fields at all — centralised on [CartLine]
  /// so the editor and the checkout validation agree.
  bool get _isWeightBased => _line.isWeightBased;

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
          child: Form(
            key: _formKey,
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
              const SizedBox(height: AppSpacing.lg),

              if (_isWeightBased) ...[
                if (_canDeriveFromPieces) ...[
                  _Label('Pieces'),
                  _NumberField(
                    controller: _pcs,
                    hint: 'Number of pieces',
                    onChanged: _onPiecesChanged,
                    validator: (v) => _positive(v, 'Pieces'),
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
                    validator: (v) => _positive(v, 'Pieces'),
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
                          // Cashier enters Gross and Waste; Net is derived.
                          _NumberField(
                            controller: _gross,
                            onChanged: (v) => setState(() {
                              _line.grossWeight = v;
                              _line.syncNetFromWeights();
                              _qty.text = _fmt(_line.qty);
                            }),
                            validator: (v) => _positive(v, 'Gross weight'),
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
                            onChanged: (v) => setState(() {
                              _line.wasteQty = v;
                              _line.syncNetFromWeights();
                              _qty.text = _fmt(_line.qty);
                            }),
                            validator: _wasteValidator,
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
                          // Weight-based: Net is computed from Gross − Waste and
                          // is read-only; otherwise it's the editable quantity.
                          enabled: !_isWeightBased,
                          onChanged: (v) => setState(() => _line.qty = v),
                          // The weight-based Net is derived and read-only, so it
                          // is validated via Gross/Waste, not here.
                          validator: _isWeightBased
                              ? null
                              : (v) => _positive(v, 'Quantity'),
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
                          validator: (v) => _positive(v, 'Unit price'),
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
                      onPressed: _onDone,
                      child: const Text('Done'),
                    ),
                  ),
                ],
              ),
            ],
          ),
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

  /// Accepts "Done" only when every required field is valid, showing the error
  /// against the specific field that is wrong (flutter_app_issues_august_06 #3).
  void _onDone() {
    if (_formKey.currentState?.validate() ?? false) {
      Navigator.pop(context, _line);
    }
  }

  /// Required, must parse to a number greater than zero.
  static String? _positive(String? value, String field) {
    final n = double.tryParse(value?.trim() ?? '');
    if (n == null) return 'Enter $field.';
    if (n <= 0) return '$field must be greater than 0.';
    return null;
  }

  /// Waste is required and may be 0, but must leave a net weight above zero
  /// (net = gross − waste), so it cannot meet or exceed the gross weight.
  String? _wasteValidator(String? value) {
    final n = double.tryParse(value?.trim() ?? '');
    if (n == null) return 'Enter waste (0 if none).';
    if (n < 0) return 'Waste cannot be negative.';
    final gross = double.tryParse(_gross.text.trim()) ?? 0;
    if (gross > 0 && n >= gross) return 'Waste must be less than gross weight.';
    return null;
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
    this.enabled = true,
    this.validator,
  });

  final TextEditingController controller;
  final ValueChanged<double> onChanged;
  final String? hint;

  /// A disabled field is read-only — used for the computed Net weight.
  final bool enabled;

  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,3}')),
      ],
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: validator,
      // No isDense: these weight/price fields are the cashier's main tap
      // targets, so they keep the theme's full ~52px height for glove use.
      decoration: InputDecoration(
        hintText: hint,
        helperText: enabled ? null : 'Gross − Waste',
      ),
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
            line.taxRate > 0
                ? 'Tax (${Format.quantity(line.taxRate)})%'
                : 'Tax',
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
