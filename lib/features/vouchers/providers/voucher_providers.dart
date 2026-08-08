import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/datasources/remote/ledger_payment_vouchers_api.dart';
import '../../../data/datasources/remote/vouchers_api.dart';
import '../../../data/models/voucher.dart';
import '../../auth/providers/auth_providers.dart';

final vouchersApiProvider = Provider<VouchersApi>((ref) {
  return VouchersApi(ref.watch(apiClientProvider));
});

final ledgerVouchersApiProvider = Provider<LedgerPaymentVouchersApi>((ref) {
  return LedgerPaymentVouchersApi(ref.watch(apiClientProvider));
});

/// Reference data for a CRV/CPV form. Keyed by voucher type — the "Bank"
/// payment-method value differs between them.
final voucherCreateFormProvider =
    FutureProvider.family<VoucherCreateForm, VoucherType>((ref, type) {
  return ref.watch(vouchersApiProvider).createForm(type);
});

/// Reference data for the Ledger Payment Voucher form.
final ledgerCreateFormProvider = FutureProvider<VoucherCreateForm>((ref) {
  return ref.watch(ledgerVouchersApiProvider).createForm();
});
