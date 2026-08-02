/// Reference data for the dedicated "Add Customer" screen, from
/// `GET /v1/customers/create-form`. Distinct from the sale screen's inline
/// quick-create, which needs no reference data.
class CustomerCreateForm {
  const CustomerCreateForm({
    required this.warehouses,
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
      warehouses: list(json['warehouses'], WarehouseOption.fromJson),
      customerGroups: list(json['customer_groups'], CustomerGroupOption.fromJson),
      areas: list(json['areas'], AreaOption.fromJson),
    );
  }

  /// The preview warehouse the areas/customer_groups below are scoped to. The
  /// user must still pick one explicitly — it is a required field on create.
  final int? warehouseId;

  /// Full active warehouse list, the same for every caller (admin or staff).
  final List<WarehouseOption> warehouses;

  /// Scoped to [warehouseId]; re-fetch the form with a different warehouse to
  /// refresh these.
  final List<CustomerGroupOption> customerGroups;
  final List<AreaOption> areas;
}

/// A selectable warehouse. `id` is submitted as `warehouse_id`.
class WarehouseOption {
  const WarehouseOption({required this.id, required this.name});

  factory WarehouseOption.fromJson(Map<String, dynamic> json) {
    return WarehouseOption(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '-',
    );
  }

  final int id;
  final String name;
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