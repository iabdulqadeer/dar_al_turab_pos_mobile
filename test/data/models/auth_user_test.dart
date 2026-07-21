import 'package:dar_al_turab_pos/data/models/auth_user.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuthUser parsing', () {
    test('parses a UserResource payload', () {
      final user = AuthUser.fromJson({
        'id': 12,
        'name': 'Hamza Ali',
        'email': 'hamza@example.com',
        'phone': '0501234567',
        'company_name': null,
        'role_id': 9,
        'role_name': 'Sales Person',
        'warehouse_id': 2,
        'warehouse_name': 'Main Store',
        'biller_id': null,
        'is_active': true,
        'permissions': ['sales-index', 'sales-add'],
      });

      expect(user.id, 12);
      expect(user.name, 'Hamza Ali');
      expect(user.roleName, 'Sales Person');
      expect(user.warehouseName, 'Main Store');
      expect(user.hasWarehouse, isTrue);
      expect(user.permissions, containsAll(['sales-index', 'sales-add']));
    });

    test('tolerates missing optional fields', () {
      final user = AuthUser.fromJson({'id': 1, 'name': 'Admin'});

      expect(user.email, isNull);
      expect(user.permissions, isEmpty);
      expect(user.isActive, isTrue);
      expect(user.hasWarehouse, isFalse);
    });
  });

  group('Permission gating', () {
    AuthUser userWith({required int roleId, Set<String> permissions = const {}}) {
      return AuthUser(
        id: 1,
        name: 'Test',
        roleId: roleId,
        permissions: permissions,
      );
    }

    test('grants a permission the role explicitly holds', () {
      final user = userWith(roleId: 9, permissions: {Permissions.salesAdd});

      expect(user.can(Permissions.salesAdd), isTrue);
      expect(user.can(Permissions.salesDelete), isFalse);
    });

    test('treats role_id <= 2 as the admin band with full access', () {
      // ScopeService uses `role_id <= 2` (Admin, Owner) as the admin band, so
      // the client must agree or it will hide controls admins should have.
      expect(userWith(roleId: 1).can(Permissions.salesDelete), isTrue);
      expect(userWith(roleId: 2).can(Permissions.salesDelete), isTrue);
      expect(userWith(roleId: 3).can(Permissions.salesDelete), isFalse);
    });

    test('reports admin status from the role band', () {
      expect(userWith(roleId: 1).isAdmin, isTrue);
      expect(userWith(roleId: 2).isAdmin, isTrue);
      expect(userWith(roleId: 9).isAdmin, isFalse);
    });

    test('treats an unknown role as non-admin', () {
      final user = AuthUser(id: 1, name: 'Test', permissions: const {});

      expect(user.isAdmin, isFalse);
      expect(user.can(Permissions.salesIndex), isFalse);
    });

    test('canAny passes when at least one permission is held', () {
      final user = userWith(roleId: 9, permissions: {Permissions.salesIndex});

      expect(
        user.canAny([Permissions.salesIndex, Permissions.salesDelete]),
        isTrue,
      );
      expect(
        user.canAny([Permissions.salesEdit, Permissions.salesDelete]),
        isFalse,
      );
    });
  });

  group('Initials', () {
    AuthUser named(String name) =>
        AuthUser(id: 1, name: name, permissions: const {});

    test('uses first and last name', () {
      expect(named('Hamza Ali').initials, 'HA');
      expect(named('Abdul Rahman Khan').initials, 'AK');
    });

    test('falls back for single and empty names', () {
      expect(named('Hamza').initials, 'H');
      expect(named('').initials, '?');
      expect(named('   ').initials, '?');
    });
  });
}
