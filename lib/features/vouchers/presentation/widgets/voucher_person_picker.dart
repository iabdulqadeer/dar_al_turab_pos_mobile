import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/sheet_header.dart';
import '../../../../data/models/voucher.dart';

/// A search-as-you-type picker for a customer or supplier, shown as a
/// full-height modal sheet. Returns the chosen [VoucherPerson] on tap.
class VoucherPersonPicker extends StatefulWidget {
  const VoucherPersonPicker({
    required this.title,
    required this.search,
    super.key,
  });

  final String title;
  final Future<List<VoucherPerson>> Function(String query) search;

  @override
  State<VoucherPersonPicker> createState() => _VoucherPersonPickerState();
}

class _VoucherPersonPickerState extends State<VoucherPersonPicker> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<VoucherPerson> _results = const [];
  bool _loading = false;
  Object? _error;
  int _requestId = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _run(value));
  }

  Future<void> _run(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    final id = ++_requestId;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final people = await widget.search(query.trim());
      if (!mounted || id != _requestId) return;
      setState(() {
        _results = people;
        _loading = false;
      });
    } on Object catch (e) {
      if (!mounted || id != _requestId) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            SheetHeader(
              title: widget.title,
              onBack: () => Navigator.pop(context),
            ),
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: _onChanged,
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Search by name or phone',
                  prefixIcon: const Icon(Icons.search, size: 20),
                ),
              ),
            ),
            Expanded(child: _body(theme)),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            'Could not search.\n$_error',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      final searching = _controller.text.trim().isNotEmpty;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Text(
            searching ? 'No matches found' : 'Type to search',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final person = _results[index];
        return ListTile(
          title: Text(person.name),
          subtitle: person.subtitle == null ? null : Text(person.subtitle!),
          onTap: () => Navigator.pop(context, person),
        );
      },
    );
  }
}
