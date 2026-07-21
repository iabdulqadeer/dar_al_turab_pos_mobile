/// Sale lifecycle status. Integer values are the server's contract
/// (`SaleAssembler::saleStatusLabel`) and must not be reordered.
enum SaleStatus {
  completed(1, 'Completed'),
  pending(2, 'Pending'),
  draft(3, 'Draft');

  const SaleStatus(this.value, this.label);

  final int value;
  final String label;

  static SaleStatus? fromValue(int? value) {
    if (value == null) return null;
    for (final status in values) {
      if (status.value == value) return status;
    }
    return null;
  }
}

/// Payment status. Note the server's POS path recomputes this on create as
/// `abs(grand_total - paid) >= 0.005 ? due : paid`, so an *overpayment* is
/// still reported as [due] — a ported quirk the UI should not try to correct.
enum PaymentStatus {
  pending(1, 'Pending'),
  due(2, 'Due'),
  partial(3, 'Partial'),
  paid(4, 'Paid');

  const PaymentStatus(this.value, this.label);

  final int value;
  final String label;

  static PaymentStatus? fromValue(int? value) {
    if (value == null) return null;
    for (final status in values) {
      if (status.value == value) return status;
    }
    return null;
  }
}

/// Payment methods accepted by `CreateSaleRequest.payment.paid_by_id`.
///
/// `7` (points) is deliberately absent: the server rejects it with
/// `POINTS_PAYMENT_UNSUPPORTED`, so it must never be offered in the UI.
enum PaymentMethod {
  cash(1, 'Cash'),
  giftCard(2, 'Gift Card'),
  creditCard(3, 'Credit Card'),
  cheque(4, 'Cheque'),
  paypal(5, 'PayPal'),
  deposit(6, 'Deposit');

  const PaymentMethod(this.value, this.label);

  final int value;
  final String label;

  static PaymentMethod? fromValue(int? value) {
    if (value == null) return null;
    for (final method in values) {
      if (method.value == value) return method;
    }
    return null;
  }
}
