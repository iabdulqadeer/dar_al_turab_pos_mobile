import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../data/models/catalogue.dart';
import '../../providers/pos_providers.dart';

/// Customer search + inline create, for the sale screen.
///
/// By default the picked customer is written to the global New-Sale cart. Pass
/// [onSelected] to route the choice somewhere else instead — the Edit Sale
/// screen drives a local cart, so it supplies its own handler.
class CustomerPicker extends ConsumerStatefulWidget {
  const CustomerPicker({this.onSelected, super.key});

  final void Function(CatalogueCustomer customer)? onSelected;

  @override
  ConsumerState<CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends ConsumerState<CustomerPicker> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Applies the choice: to the caller's handler when given, otherwise to the
  /// global cart. Either way the sheet closes.
  void _pick(CatalogueCustomer customer) {
    final onSelected = widget.onSelected;
    if (onSelected != null) {
      onSelected(customer);
    } else {
      ref.read(cartProvider.notifier).setCustomer(customer);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(customerSearchProvider);
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Customer',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _fullCreate,
                    icon: const Icon(Icons.person_add_alt, size: 18),
                    label: const Text('Add Customer'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (v) =>
                    ref.read(customerSearchQueryProvider.notifier).set(v),
                decoration: const InputDecoration(
                  isDense: true,
                  hintText: 'Search by name, phone or company',
                  prefixIcon: Icon(Icons.search, size: 20),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: results.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Text(
                      error is ApiException
                          ? error.message
                          : 'Could not load customers.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
                data: (customers) => customers.isEmpty
                    ? Center(
                        child: Text(
                          'No customers found',
                          style: theme.textTheme.bodySmall,
                        ),
                      )
                    : ListView.separated(
                        itemCount: customers.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final c = customers[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  AppColors.primary.withValues(alpha: 0.12),
                              child: Icon(
                                c.isDefault
                                    ? Icons.storefront_outlined
                                    : Icons.person_outline,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ),
                            title: Text(c.name),
                            subtitle: c.subtitle == null
                                ? null
                                : Text(
                                    c.subtitle!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => _pick(c),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the "Add Customer" screen. It returns the created customer on pop,
  /// which we then apply to the sale just like a picked one.
  Future<void> _fullCreate() async {
    final created = await context.push<CatalogueCustomer>(Routes.addCustomer);
    if (created != null && mounted) {
      _pick(created);
    }
  }
}
