import 'package:flutter/material.dart';

import '../../../../data/models/catalogue.dart' show NamedRef;
import '../../../../data/models/voucher.dart';

/// Small form controls shared by the CRV/CPV and Ledger voucher forms.
///
/// All of them render their content at [voucherFieldStyle] (the theme's
/// `bodyMedium`, in the app's Nunito family) and use dense decoration, so every
/// voucher field — dropdowns, pickers, text fields — is the same size and shape.

String voucherFormatDate(DateTime d) =>
    '${d.year}-${_two(d.month)}-${_two(d.day)}';
String _two(int n) => n.toString().padLeft(2, '0');

/// The single content text style every voucher field uses. Keeps the whole
/// module on one font size/family, inherited from the app theme.
TextStyle? voucherFieldStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodyMedium;

class VoucherDateField extends StatelessWidget {
  const VoucherDateField({
    required this.label,
    required this.value,
    required this.onChanged,
    super.key,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime(2020),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        isEmpty: value == null,
        decoration: const InputDecoration(
          isDense: true,
          suffixIcon: Icon(Icons.calendar_today, size: 18),
        ).copyWith(labelText: label),
        child: Text(
          value == null ? '' : voucherFormatDate(value!),
          style: voucherFieldStyle(context),
        ),
      ),
    );
  }
}

class VoucherDropdown<T> extends StatelessWidget {
  const VoucherDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
    super.key,
  });

  final String label;
  final T value;
  final List<T> items;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final style = voucherFieldStyle(context);
    return DropdownButtonFormField<T>(
      initialValue: items.contains(value) ? value : null,
      // Constrain to the field width so a long value ellipsizes inside the box
      // instead of overflowing past it.
      isExpanded: true,
      style: style,
      decoration: InputDecoration(labelText: label, isDense: true),
      items: items
          .map(
            (i) => DropdownMenuItem(
              value: i,
              child: Text(
                labelFor(i),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }
}

class VoucherRefDropdown extends StatelessWidget {
  const VoucherRefDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
    this.enabled = true,
    this.optional = false,
    super.key,
  });

  final String label;
  final NamedRef? value;
  final List<NamedRef> items;
  final ValueChanged<NamedRef?> onChanged;
  final bool enabled;
  final bool optional;

  @override
  Widget build(BuildContext context) {
    final style = voucherFieldStyle(context);
    final match = items.where((i) => i.id == value?.id).cast<NamedRef?>();
    return DropdownButtonFormField<NamedRef>(
      initialValue: match.isEmpty ? null : match.first,
      // Constrain to the field width so a long name (e.g. the full company
      // warehouse name) ellipsizes inside the box instead of overflowing.
      isExpanded: true,
      style: style,
      decoration: InputDecoration(
        labelText: optional ? '$label (optional)' : label,
        isDense: true,
      ),
      items: items
          .map(
            (i) => DropdownMenuItem(
              value: i,
              child: Text(
                i.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: style,
              ),
            ),
          )
          .toList(),
      onChanged: enabled ? onChanged : null,
    );
  }
}

class VoucherPersonField extends StatelessWidget {
  const VoucherPersonField({
    required this.label,
    required this.person,
    required this.onTap,
    this.enabled = true,
    super.key,
  });

  final String label;
  final VoucherPerson? person;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: enabled ? onTap : null,
      child: InputDecorator(
        isEmpty: person == null,
        decoration: const InputDecoration(
          isDense: true,
          suffixIcon: Icon(Icons.search, size: 18),
        ).copyWith(labelText: label),
        child: Text(
          person?.name ?? '',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: voucherFieldStyle(context),
        ),
      ),
    );
  }
}
