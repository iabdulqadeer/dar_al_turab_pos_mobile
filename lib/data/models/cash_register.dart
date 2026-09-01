/// The daily cash-register report from `GET /v1/cash-register/daily`.
///
/// Shapes mirror the API's `data` object exactly (see
/// docs/flutter_app_issues_aug_29_2026.md). Every figure is computed
/// server-side — the client only displays it, never re-derives totals.
class CashRegisterReport {
  const CashRegisterReport({
    required this.warehouseId,
    required this.userId,
    required this.startDate,
    required this.endDate,
    required this.openingBalance,
    required this.closingBalance,
    required this.totalCashIn,
    required this.totalCashOut,
    required this.totalDebit,
    required this.totalCredit,
    required this.activities,
  });

  factory CashRegisterReport.fromJson(Map<String, dynamic> json) {
    return CashRegisterReport(
      warehouseId: (json['warehouse_id'] as num?)?.toInt(),
      userId: (json['user_id'] as num?)?.toInt(),
      startDate: json['start_date']?.toString() ?? '',
      endDate: json['end_date']?.toString() ?? '',
      openingBalance: _d(json['opening_balance']),
      closingBalance: _d(json['closing_balance']),
      totalCashIn: _d(json['total_cash_in']),
      totalCashOut: _d(json['total_cash_out']),
      totalDebit: _d(json['total_debit']),
      totalCredit: _d(json['total_credit']),
      activities: (json['activities'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => CashRegisterActivity.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }

  final int? warehouseId;

  /// Null on the admin unfiltered view; set to the staff id otherwise. Drives
  /// whether Opening/Closing balance rows are shown (shown only when null).
  final int? userId;
  final String startDate;
  final String endDate;
  final double openingBalance;
  final double closingBalance;
  final double totalCashIn;
  final double totalCashOut;
  final double totalDebit;
  final double totalCredit;
  final List<CashRegisterActivity> activities;

  /// The web app shows Opening/Closing balance only on the admin unfiltered
  /// view (`user_id == null`), even though the figures always exist.
  bool get showBalances => userId == null;

  bool get isEmpty => activities.isEmpty;
}

class CashRegisterActivity {
  const CashRegisterActivity({required this.activity, required this.groups});

  factory CashRegisterActivity.fromJson(Map<String, dynamic> json) {
    return CashRegisterActivity(
      activity: json['activity']?.toString() ?? '',
      groups: (json['groups'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => CashRegisterGroup.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
    );
  }

  /// e.g. "Operating Activities", "Financing Activities".
  final String activity;
  final List<CashRegisterGroup> groups;
}

class CashRegisterGroup {
  const CashRegisterGroup({
    required this.type,
    required this.rows,
    required this.subtotalDebit,
    required this.subtotalCredit,
    required this.subtotalTotal,
  });

  factory CashRegisterGroup.fromJson(Map<String, dynamic> json) {
    return CashRegisterGroup(
      type: json['type']?.toString() ?? '',
      rows: (json['rows'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => CashRegisterRow.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false),
      subtotalDebit: _d(json['subtotal_debit']),
      subtotalCredit: _d(json['subtotal_credit']),
      subtotalTotal: _d(json['subtotal_total']),
    );
  }

  /// e.g. "Cash Received Voucher".
  final String type;
  final List<CashRegisterRow> rows;
  final double subtotalDebit;
  final double subtotalCredit;
  final double subtotalTotal;
}

class CashRegisterRow {
  const CashRegisterRow({
    required this.createdBy,
    required this.reference,
    required this.debit,
    required this.credit,
    required this.total,
  });

  factory CashRegisterRow.fromJson(Map<String, dynamic> json) {
    return CashRegisterRow(
      createdBy: json['created_by']?.toString() ?? '',
      // Already fully formatted server-side — display as-is.
      reference: json['reference']?.toString() ?? '',
      debit: _d(json['debit']),
      credit: _d(json['credit']),
      total: _d(json['total']),
    );
  }

  final String createdBy;
  final String reference;
  final double debit;
  final double credit;

  /// `debit + credit`, pre-computed server-side (the web table's Total column).
  final double total;
}

double _d(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}
