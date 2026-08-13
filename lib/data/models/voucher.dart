import 'catalogue.dart' show NamedRef;

/// Cash voucher kind. The same screen builds both, parameterised by this.
enum VoucherType {
  crv('CRV', 'Cash Received Voucher'),
  cpv('CPV', 'Cash Payment Voucher');

  const VoucherType(this.value, this.title);

  /// The `voucher_type` string the API uses, and the `type` list query param
  /// slug.
  final String value;
  final String title;

  /// The `?type=` list-endpoint slug.
  String get slug =>
      this == VoucherType.crv ? 'cash-received-voucher' : 'cash-payment-voucher';

  /// CRV receives from a customer; CPV pays a supplier. Locked in the UI.
  String get personType => this == VoucherType.crv ? 'Customer' : 'Supplier';
}

/// The Debit/Credit label shown for a Ledger Payment Voucher in the **list and
/// the view** — deliberately the opposite of the stored `transaction_type` (a
/// business display rule): a stored `credit` reads as "Debit", `debit` as
/// "Credit".
///
/// This is a post-hoc *display* swap and must NOT be reused for the edit form,
/// which relabels its dropdown options while keeping the submitted value
/// untouched (see Ledger_payment_voucher_issues.md §2).
String ledgerListViewTransactionLabel(String transactionType) {
  switch (transactionType.toLowerCase()) {
    case 'credit':
      return 'Debit';
    case 'debit':
      return 'Credit';
    default:
      return transactionType;
  }
}

/// The party a voucher is for — a Customer (CRV) or Supplier (CPV/LPV).
class VoucherPerson {
  const VoucherPerson({
    required this.id,
    required this.name,
    this.type,
    this.phoneNumber,
    this.companyName,
    this.address,
  });

  factory VoucherPerson.fromJson(Map<String, dynamic> json) {
    return VoucherPerson(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String? ?? '-',
      type: json['type'] as String?,
      phoneNumber: json['phone_number'] as String?,
      companyName: json['company_name'] as String?,
      address: json['address'] as String?,
    );
  }

  final int id;
  final String name;

  /// Present on a voucher's embedded `person` object ("Customer"/"Supplier");
  /// absent on a raw search result.
  final String? type;
  final String? phoneNumber;
  final String? companyName;
  final String? address;

  String? get subtitle {
    final parts = [
      companyName,
      phoneNumber,
    ].where((p) => p != null && p.trim().isNotEmpty).cast<String>();
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

/// A `{value, name}` option — voucher payment methods and person types both use
/// this shape. The `value` is what the API expects; the `name` is the label.
class VoucherOption {
  const VoucherOption({required this.value, required this.name});

  factory VoucherOption.fromJson(Map<String, dynamic> json) {
    return VoucherOption(
      value: json['value'] as String,
      name: json['name'] as String? ?? json['value'] as String,
    );
  }

  final String value;
  final String name;
}

/// Reference data for a CRV/CPV or LPV form.
///
/// Shared shape across both create-form endpoints — the only documented
/// difference is the "Bank" payment method `value` (`deposit` for CRV/CPV,
/// `bank` for LPV), which is captured verbatim in [paymentMethods].
class VoucherCreateForm {
  const VoucherCreateForm({
    this.warehouseId,
    this.warehouses = const [],
    this.billers = const [],
    this.defaultBillerId,
    this.billerLocked = false,
    this.banks = const [],
    this.paymentMethods = const [],
    this.personTypes = const [],
  });

  factory VoucherCreateForm.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(dynamic v) => (v as List? ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    return VoucherCreateForm(
      warehouseId: (json['warehouse_id'] as num?)?.toInt(),
      warehouses: maps(json['warehouses']).map(NamedRef.fromJson).toList(),
      billers: maps(json['billers']).map(NamedRef.fromJson).toList(),
      defaultBillerId: (json['default_biller_id'] as num?)?.toInt(),
      billerLocked: json['biller_locked'] as bool? ?? false,
      banks: maps(json['banks']).map(NamedRef.fromJson).toList(),
      paymentMethods:
          maps(json['payment_methods']).map(VoucherOption.fromJson).toList(),
      personTypes:
          maps(json['person_types']).map(VoucherOption.fromJson).toList(),
    );
  }

  final int? warehouseId;
  final List<NamedRef> warehouses;
  final List<NamedRef> billers;
  final int? defaultBillerId;

  /// When true, the biller is the user's own and must be pre-filled + disabled.
  final bool billerLocked;
  final List<NamedRef> banks;
  final List<VoucherOption> paymentMethods;
  final List<VoucherOption> personTypes;

  NamedRef? get lockedBiller {
    if (defaultBillerId == null) return null;
    for (final b in billers) {
      if (b.id == defaultBillerId) return b;
    }
    return null;
  }
}

/// One invoice to allocate a payment against, from `GET /vouchers/unpaid-invoices`.
///
/// [payAmount] and [discountAmount] are user-editable working values; [due] is
/// read-only from the server.
class UnpaidInvoice {
  UnpaidInvoice({
    required this.invoiceId,
    required this.referenceNo,
    required this.date,
    required this.due,
    required this.payAmount,
    required this.discountAmount,
    this.note,
  });

  factory UnpaidInvoice.fromJson(Map<String, dynamic> json) {
    final due = _toDouble(json['due']);
    return UnpaidInvoice(
      invoiceId: (json['invoice_id'] as num).toInt(),
      referenceNo: json['reference_no'] as String? ?? '-',
      date: json['date'] as String? ?? '',
      due: due,
      // Pay amount starts at the full due; discount starts at 0.
      payAmount: _toDouble(json['pay_amount'], fallback: due),
      discountAmount: _toDouble(json['discount_amount']),
      note: json['note'] as String?,
    );
  }

  final int invoiceId;
  final String referenceNo;
  final String date;
  final double due;

  double payAmount;
  double discountAmount;
  String? note;

  /// Selected rows only are submitted; unchecked rows are dropped entirely.
  bool selected = false;

  /// Editing discount recalculates pay = due − discount (never below 0).
  void applyDiscount(double discount) {
    discountAmount = discount < 0 ? 0 : discount;
    final pay = due - discountAmount;
    payAmount = pay < 0 ? 0 : pay;
  }

  Map<String, dynamic> toJson() => {
        'invoice_id': invoiceId,
        'pay_amount': payAmount,
        'discount_amount': discountAmount,
        'note': note?.trim().isEmpty ?? true ? null : note!.trim(),
      };
}

/// One allocated invoice on a saved voucher's detail/list response.
class VoucherInvoice {
  const VoucherInvoice({
    required this.invoicePaymentId,
    required this.invoiceId,
    required this.referenceNumber,
    required this.paidAmount,
    required this.discountAmount,
    this.invoiceType,
    this.note,
    this.createdBy,
    this.date,
  });

  factory VoucherInvoice.fromJson(Map<String, dynamic> json) {
    return VoucherInvoice(
      invoicePaymentId: (json['invoice_payment_id'] as num).toInt(),
      invoiceId: (json['invoice_id'] as num).toInt(),
      referenceNumber: json['reference_number'] as String? ?? '-',
      paidAmount: _toDouble(json['paid_amount']),
      discountAmount: _toDouble(json['discount_amount']),
      invoiceType: json['invoice_type'] as String?,
      note: json['note'] as String?,
      // created_by is a {id, name} object on the invoice-payment line (distinct
      // from the voucher's own top-level created_by, which is a bare user id).
      createdBy: _ref(json['created_by']),
      date: json['date'] as String?,
    );
  }

  final int invoicePaymentId;
  final int invoiceId;
  final String referenceNumber;
  final double paidAmount;
  final double discountAmount;
  final String? invoiceType;
  final String? note;
  final NamedRef? createdBy;
  final String? date;
}

/// A saved Cash Received / Cash Payment voucher (list row and detail share it).
class Voucher {
  const Voucher({
    required this.id,
    required this.voucherNo,
    required this.voucherType,
    required this.date,
    required this.paymentMethod,
    required this.totalAmount,
    required this.totalDiscount,
    this.warehouse,
    this.biller,
    this.person,
    this.bank,
    this.chequeNo,
    this.chequeDate,
    this.createdBy,
    this.createdAt,
    this.invoices = const [],
  });

  factory Voucher.fromJson(Map<String, dynamic> json) {
    return Voucher(
      id: (json['id'] as num).toInt(),
      voucherNo: json['voucher_no'] as String? ?? '-',
      voucherType: json['voucher_type'] as String? ?? '',
      date: json['date'] as String? ?? '',
      warehouse: _ref(json['warehouse']),
      biller: _ref(json['biller']),
      person: json['person'] is Map
          ? VoucherPerson.fromJson(Map<String, dynamic>.from(json['person']))
          : null,
      paymentMethod: json['payment_method'] as String? ?? '',
      bank: _ref(json['bank']),
      chequeNo: json['cheque_no'] as String?,
      chequeDate: json['cheque_date'] as String?,
      totalAmount: _toDouble(json['total_amount']),
      totalDiscount: _toDouble(json['total_discount']),
      createdBy: (json['created_by'] as num?)?.toInt(),
      createdAt: json['created_at'] as String?,
      invoices: (json['invoices'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => VoucherInvoice.fromJson(Map<String, dynamic>.from(e)))
          .toList(),
    );
  }

  final int id;
  final String voucherNo;
  final String voucherType;
  final String date;
  final NamedRef? warehouse;
  final NamedRef? biller;
  final VoucherPerson? person;
  final String paymentMethod;
  final NamedRef? bank;
  final String? chequeNo;
  final String? chequeDate;
  final double totalAmount;
  final double totalDiscount;
  final int? createdBy;
  final String? createdAt;
  final List<VoucherInvoice> invoices;
}

/// A saved Ledger Payment Voucher — a standalone debit/credit entry, no invoice
/// allocation.
class LedgerPaymentVoucher {
  const LedgerPaymentVoucher({
    required this.id,
    required this.voucherNo,
    required this.date,
    required this.transactionType,
    required this.paymentMethod,
    required this.amount,
    this.warehouse,
    this.biller,
    this.person,
    this.bank,
    this.chequeNo,
    this.chequeDate,
    this.details,
    this.isActive = true,
    this.createdBy,
    this.createdAt,
  });

  factory LedgerPaymentVoucher.fromJson(Map<String, dynamic> json) {
    return LedgerPaymentVoucher(
      id: (json['id'] as num).toInt(),
      voucherNo: json['voucher_no'] as String? ?? '-',
      date: json['date'] as String? ?? '',
      warehouse: _ref(json['warehouse']),
      biller: _ref(json['biller']),
      person: json['person'] is Map
          ? VoucherPerson.fromJson(Map<String, dynamic>.from(json['person']))
          : null,
      transactionType: json['transaction_type'] as String? ?? '',
      paymentMethod: json['payment_method'] as String? ?? '',
      bank: _ref(json['bank']),
      chequeNo: json['cheque_no'] as String?,
      chequeDate: json['cheque_date'] as String?,
      amount: _toDouble(json['amount']),
      details: json['details'] as String?,
      isActive: json['is_active'] as bool? ?? true,
      createdBy: (json['created_by'] as num?)?.toInt(),
      createdAt: json['created_at'] as String?,
    );
  }

  final int id;
  final String voucherNo;
  final String date;
  final NamedRef? warehouse;
  final NamedRef? biller;
  final VoucherPerson? person;
  final String transactionType;
  final String paymentMethod;
  final NamedRef? bank;
  final String? chequeNo;
  final String? chequeDate;
  final double amount;
  final String? details;
  final bool isActive;
  final int? createdBy;
  final String? createdAt;
}

NamedRef? _ref(dynamic value) => value is Map
    ? NamedRef.fromJson(Map<String, dynamic>.from(value))
    : null;

double _toDouble(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? fallback;
  return fallback;
}
