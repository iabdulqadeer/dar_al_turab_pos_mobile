/// Authenticated user, mirroring `UserResource`
/// (`app/Http/Resources/Api/V1/UserResource.php`).
class AuthUser {
  const AuthUser({
    required this.id,
    required this.name,
    required this.permissions,
    this.email,
    this.phone,
    this.companyName,
    this.roleId,
    this.roleName,
    this.warehouseId,
    this.warehouseName,
    this.billerId,
    this.isActive = true,
  });

  factory AuthUser.fromJson(Map<String, dynamic> json) {
    return AuthUser(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      companyName: json['company_name'] as String?,
      roleId: (json['role_id'] as num?)?.toInt(),
      roleName: json['role_name'] as String?,
      warehouseId: (json['warehouse_id'] as num?)?.toInt(),
      warehouseName: json['warehouse_name'] as String?,
      billerId: (json['biller_id'] as num?)?.toInt(),
      isActive: json['is_active'] as bool? ?? true,
      permissions: (json['permissions'] as List?)?.cast<String>().toSet() ??
          const <String>{},
    );
  }

  final int id;
  final String name;
  final String? email;
  final String? phone;
  final String? companyName;
  final int? roleId;
  final String? roleName;
  final int? warehouseId;
  final String? warehouseName;
  final int? billerId;
  final bool isActive;

  /// Server-computed permission names (`PermissionService::permissionNamesFor`).
  /// Admins receive every permission row; other roles receive their role's set.
  final Set<String> permissions;

  /// The server treats `role_id <= 2` (Admin, Owner) as the admin band.
  /// Non-admins are always scoped to their own warehouse and own records
  /// (`ScopeService::appliesOwnRecordsOnly`), so the UI should not offer
  /// warehouse switching to them.
  bool get isAdmin => (roleId ?? 99) <= 2;

  bool get hasWarehouse => warehouseId != null;

  bool can(String permission) => isAdmin || permissions.contains(permission);

  bool canAny(Iterable<String> required) => required.any(can);

  String get initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters1();
    return '${parts.first.characters1()}${parts.last.characters1()}';
  }
}

extension on String {
  String characters1() => isEmpty ? '' : this[0].toUpperCase();
}

/// Permission names used by the v1 sale endpoints. Gate UI affordances on
/// these so we never render a control the server will answer with 403.
abstract final class Permissions {
  static const salesIndex = 'sales-index';
  static const salesAdd = 'sales-add';
  static const salesEdit = 'sales-edit';
  static const salesDelete = 'sales-delete';

  // Cash Received / Cash Payment vouchers. Ledger Payment Vouchers are gated
  // by role only (any user creates; admin-only edit/delete), no permission
  // string — see the vouchers module doc §4.
  static const cashReceivedVoucher = 'cash-received-voucher';
  static const cashPaymentVoucher = 'cash-payment-voucher';
  static const addCashVoucher = 'add-cash-voucher';
  static const editCashVoucher = 'edit-cash-voucher';
  static const deleteCashVoucher = 'delete-cash-voucher';
}
