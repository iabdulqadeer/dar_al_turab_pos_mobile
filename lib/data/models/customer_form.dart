/// Reference data for the dedicated "Add Customer" screen, from
/// `GET /v1/customers/create-form`. Distinct from the sale screen's inline
/// quick-create, which needs no reference data.
class CustomerCreateForm {
  const CustomerCreateForm({
    required this.customerGroups,
    required this.areas,
    this.warehouseId,
  });

  factory CustomerCreateForm.fromJson(Map<String, dynamic> json) {
    List<T> list<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
      if (raw is! List) return const [];
      return raw
          .whereType<Map>()
          .map((e) => parse(Map<String, dynamic>.from(e)))
          .toList();
    }

    return CustomerCreateForm(
      warehouseId: (json['warehouse_id'] as num?)?.toInt(),
      customerGroups: list(json['customer_groups'], CustomerGroupOption.fromJson),
      areas: list(json['areas'], AreaOption.fromJson),
    );
  }

  /// Informational only — resolved server-side from the caller and never sent
  /// back on create.
  final int? warehouseId;
  final List<CustomerGroupOption> customerGroups;
  final List<AreaOption> areas;
}

/// A selectable customer group. `id` is submitted as `customer_group_id`.
class CustomerGroupOption {
  const CustomerGroupOption({
    required this.id,
    required this.name,
    this.percentage = 0,
  });

  factory CustomerGroupOption.fromJson(Map<String, dynamic> json) {
    return CustomerGroupOption(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '-',
      percentage: (json['percentage'] as num?)?.toDouble() ?? 0,
    );
  }

  final int id;
  final String name;
  final double percentage;
}

/// A selectable delivery/billing area. `id` is submitted as `area_id`.
class AreaOption {
  const AreaOption({required this.id, required this.name, this.code});

  factory AreaOption.fromJson(Map<String, dynamic> json) {
    return AreaOption(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '-',
      code: json['code'] as String?,
    );
  }

  final int id;
  final String name;
  final String? code;
}