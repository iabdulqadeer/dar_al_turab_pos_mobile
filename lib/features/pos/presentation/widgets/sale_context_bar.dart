import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/catalogue.dart';

/// Warehouse + biller selection for the sale create/edit screens.
///
/// Role rules (decided by the caller via [editable]):
/// - Admin: both editable, full lists.
/// - Non-admin with a fixed biller: both locked (shown read-only).
/// - Non-admin without a fixed biller: both editable.
///
/// Note: for a non-admin the server always forces the sale to the account's own
/// warehouse, so an editable warehouse here does not actually move the sale —
/// the field is offered per the product spec, not as a guarantee.
class SaleContextBar extends StatelessWidget {
  const SaleContextBar({
    required this.warehouses,
    required this.billers,
    required this.warehouse,
    required this.biller,
    required this.editable,
    required this.onWarehouseChanged,
    required this.onBillerChanged,
    super.key,
  });

  final List<NamedRef> warehouses;
  final List<NamedRef> billers;
  final NamedRef? warehouse;
  final NamedRef? biller;
  final bool editable;
  final ValueChanged<NamedRef?> onWarehouseChanged;
  final ValueChanged<NamedRef?> onBillerChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Row(
        children: [
          Expanded(
            child: _Field(
              label: 'Warehouse',
              icon: Icons.warehouse_outlined,
              value: warehouse?.id,
              options: warehouses,
              editable: editable,
              onChanged: (id) => onWarehouseChanged(_byId(warehouses, id)),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _Field(
              label: 'Biller',
              icon: Icons.badge_outlined,
              value: biller?.id,
              options: billers,
              editable: editable,
              onChanged: (id) => onBillerChanged(_byId(billers, id)),
            ),
          ),
        ],
      ),
    );
  }

  static NamedRef? _byId(List<NamedRef> options, int? id) {
    for (final o in options) {
      if (o.id == id) return o;
    }
    return null;
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.icon,
    required this.value,
    required this.options,
    required this.editable,
    required this.onChanged,
  });

  final String label;
  final IconData icon;
  final int? value;
  final List<NamedRef> options;
  final bool editable;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            if (!editable) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.lock_outline,
                size: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
        DropdownButtonFormField<int>(
          initialValue: value,
          isExpanded: true,
          isDense: true,
          // A null onChanged renders the field disabled/greyed for locked roles.
          onChanged: editable ? onChanged : null,
          disabledHint: _selectedText(theme),
          items: [
            for (final o in options)
              DropdownMenuItem(value: o.id, child: Text(o.name)),
          ],
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: Icon(icon, size: 18),
          ),
        ),
      ],
    );
  }

  /// Shown when the dropdown is disabled (locked), so the value stays visible.
  Widget? _selectedText(ThemeData theme) {
    final selected = options.where((o) => o.id == value);
    if (selected.isEmpty) return null;
    return Text(
      selected.first.name,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.bodyMedium?.copyWith(color: AppColors.primary),
    );
  }
}
