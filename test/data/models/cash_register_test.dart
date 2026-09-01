import 'package:dar_al_turab_pos/data/models/cash_register.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CashRegisterReport.fromJson', () {
    // The exact live-captured example from the aug-29 doc (staff, user_id 56).
    final staff = CashRegisterReport.fromJson({
      'warehouse_id': 3,
      'user_id': 56,
      'start_date': '2026-08-27',
      'end_date': '2026-08-27',
      'opening_balance': 990194.45,
      'closing_balance': 993370.75,
      'total_cash_in': 3176.30,
      'total_cash_out': 0,
      'total_debit': 3176.30,
      'total_credit': 0,
      'activities': [
        {
          'activity': 'Operating Activities',
          'groups': [
            {
              'type': 'Cash Received Voucher',
              'rows': [
                {
                  'created_by': 'admin',
                  'reference':
                      'SV-003824 - Walk in (CRV - 1787826855-dc77 (Cash))',
                  'debit': 3176.30,
                  'credit': 0,
                  'total': 3176.30,
                },
              ],
              'subtotal_debit': 3176.30,
              'subtotal_credit': 0,
              'subtotal_total': 3176.30,
            },
          ],
        },
      ],
    });

    test('parses activities, groups and rows', () {
      expect(staff.activities, hasLength(1));
      final group = staff.activities.single.groups.single;
      expect(group.type, 'Cash Received Voucher');
      expect(group.rows.single.reference,
          'SV-003824 - Walk in (CRV - 1787826855-dc77 (Cash))');
      expect(group.rows.single.total, 3176.30);
      expect(group.subtotalTotal, 3176.30);
    });

    test('hides balances when user_id is set (staff / filtered admin)', () {
      expect(staff.userId, 56);
      expect(staff.showBalances, isFalse);
    });

    test('shows balances on the admin unfiltered view (user_id null)', () {
      final admin = CashRegisterReport.fromJson({
        'warehouse_id': 3,
        'user_id': null,
        'opening_balance': 100,
        'closing_balance': 150,
        'total_cash_in': 50,
        'total_cash_out': 0,
        'total_debit': 50,
        'total_credit': 0,
        'activities': [],
      });
      expect(admin.showBalances, isTrue);
      expect(admin.isEmpty, isTrue);
    });
  });
}
