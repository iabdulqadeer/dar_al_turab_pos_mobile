import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../data/datasources/remote/catalogue_api.dart';
import '../../../data/datasources/remote/sale_payments_api.dart';
import '../../../data/datasources/remote/sales_api.dart';
import '../../../data/models/catalogue.dart';
import '../../../data/models/sale.dart';
import '../../auth/providers/auth_providers.dart';
import '../../branding/providers/branding_providers.dart';
import '../../dashboard/providers/dashboard_providers.dart';
import '../../sales/providers/sales_providers.dart';
import '../domain/cart.dart';

final catalogueApiProvider = Provider<CatalogueApi>((ref) {
  return CatalogueApi(ref.watch(apiClientProvider));
});

final salePaymentsApiProvider = Provider<SalePaymentsApi>((ref) {
  return SalePaymentsApi(ref.watch(apiClientProvider));
});

/// Reference data for the sale screen. Cached for the session — billers and
/// payment methods do not change mid-shift.
final saleFormMetadataProvider = FutureProvider<SaleFormMetadata>((ref) {
  return ref.watch(catalogueApiProvider).createForm();
});

/// Global sale tax rate (percent) from `GET /settings/general` `data.tax`,
/// applied to every cart line's net total. 0 when unset or branding not loaded.
final saleTaxRateProvider = Provider<double>((ref) {
  return ref.watch(brandingProvider)?.tax ?? 0;
});

/// A plain mutable string, used for the two search boxes.
///
/// Riverpod 3 removed StateProvider, so this is the minimal Notifier that
/// replaces it.
class SearchQuery extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

/// Current product search text.
final productSearchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

/// Product search results, debounced and scoped to the cart's customer so
/// discount-plan pricing resolves correctly.
final productSearchProvider =
    FutureProvider.autoDispose<List<CatalogueProduct>>((ref) async {
  final query = ref.watch(productSearchQueryProvider);
  final customerId = ref.watch(cartProvider).customer?.id;

  // Debounce: the search fires on every keystroke, and the endpoint does real
  // pricing work per row.
  final completer = Completer<void>();
  final timer = Timer(const Duration(milliseconds: 350), completer.complete);
  ref.onDispose(() {
    timer.cancel();
    if (!completer.isCompleted) completer.complete();
  });
  await completer.future;

  // Sent explicitly: without it the server resolves an admin's null
  // warehouse to 0 and returns an empty catalogue. See
  // SaleFormMetadata.effectiveWarehouseId.
  final warehouseId =
      ref.watch(saleFormMetadataProvider).value?.effectiveWarehouseId;

  final page = await ref.watch(catalogueApiProvider).searchProducts(
        query: query,
        customerId: customerId,
        warehouseId: warehouseId,
        perPage: 30,
      );

  return page.items;
});

/// Current customer search text.
final customerSearchQueryProvider = NotifierProvider<SearchQuery, String>(
  SearchQuery.new,
);

final customerSearchProvider =
    FutureProvider.autoDispose<List<CatalogueCustomer>>((ref) async {
  final query = ref.watch(customerSearchQueryProvider);

  final completer = Completer<void>();
  final timer = Timer(const Duration(milliseconds: 350), completer.complete);
  ref.onDispose(() {
    timer.cancel();
    if (!completer.isCompleted) completer.complete();
  });
  await completer.future;

  final warehouseId =
      ref.watch(saleFormMetadataProvider).value?.effectiveWarehouseId;

  final page = await ref.watch(catalogueApiProvider).searchCustomers(
        query: query,
        warehouseId: warehouseId,
        perPage: 30,
      );

  return page.items;
});

/// The live cart.
///
/// [Cart] and [CartLine] are mutable for ergonomic editing, so every mutation
/// here rebuilds the object to give Riverpod a new identity to notify on.
class CartController extends Notifier<Cart> {
  @override
  Cart build() {
    // Seed customer and biller from the form metadata as soon as it arrives,
    // so the cashier can sell without touching either picker.
    ref.listen(saleFormMetadataProvider, (previous, next) {
      final meta = next.value;
      if (meta == null) return;

      final cart = state;
      var changed = false;

      if (cart.customer == null && meta.defaultCustomer != null) {
        cart.customer = meta.defaultCustomer;
        changed = true;
      }
      if (cart.biller == null && meta.defaultBiller != null) {
        cart.biller = meta.defaultBiller;
        changed = true;
      }

      if (changed) _touch();
    });

    // The tax rate is global (from branding/settings) and loads asynchronously;
    // apply it to every line the moment it arrives or changes.
    ref.listen(saleTaxRateProvider, (previous, next) {
      if (previous == next || state.lines.isEmpty) return;
      for (final line in state.lines) {
        line.taxRate = next;
      }
      _touch();
    });

    return Cart(lines: []);
  }

  /// Rebuilds the state object so listeners fire on in-place mutation.
  void _touch() {
    state = Cart(
      lines: List.of(state.lines),
      customer: state.customer,
      biller: state.biller,
      orderDiscount: state.orderDiscount,
      shippingCost: state.shippingCost,
      removeDecimalAmount: state.removeDecimalAmount,
    );
  }

  /// Adds a product, or bumps quantity if the same product is already on a
  /// line — scanning the same barcode twice should not create two lines.
  void addProduct(CatalogueProduct product) {
    final existing = state.lines
        .where((l) => l.product.id == product.id)
        .cast<CartLine?>()
        .firstWhere((_) => true, orElse: () => null);

    if (existing != null) {
      existing.qty = ((existing.qty + 1) * 100).roundToDouble() / 100;
    } else {
      state.lines.add(
        CartLine.fromProduct(product)..taxRate = ref.read(saleTaxRateProvider),
      );
    }
    _touch();
  }

  void removeLine(int index) {
    if (index < 0 || index >= state.lines.length) return;
    state.lines.removeAt(index);
    _touch();
  }

  /// Applies an edited copy back onto the cart.
  void replaceLine(int index, CartLine line) {
    if (index < 0 || index >= state.lines.length) return;
    state.lines[index] = line;
    _touch();
  }

  void setCustomer(CatalogueCustomer? customer) {
    state.customer = customer;
    _touch();
  }

  void setBiller(NamedRef? biller) {
    state.biller = biller;
    _touch();
  }

  void setOrderDiscount(double value) {
    state.orderDiscount = value < 0 ? 0 : value;
    _touch();
  }

  void setShippingCost(double value) {
    state.shippingCost = value < 0 ? 0 : value;
    _touch();
  }

  void setRemoveDecimalAmount(bool value) {
    state.removeDecimalAmount = value;
    _touch();
  }

  /// Clears the basket but keeps customer and biller, since the next sale is
  /// usually to the same walk-in customer at the same till.
  void clearLines() {
    state.lines.clear();
    state.orderDiscount = 0;
    state.shippingCost = 0;
    _touch();
  }

  void reset() {
    state = Cart(lines: [], biller: state.biller);
  }
}

final cartProvider = NotifierProvider<CartController, Cart>(
  CartController.new,
);

/// Submits the cart.
///
/// Returns the created sale so the caller can go straight to printing.
final createSaleProvider = Provider<Future<SaleDetail> Function({
  required int saleStatus,
  required int paymentStatus,
  double paidAmount,
  int? paymentMethodId,
  String? paymentNote,
  String? chequeNo,
  DateTime? chequeDate,
  int? bankId,
  String? saleNote,
})>((ref) {
  return ({
    required int saleStatus,
    required int paymentStatus,
    double paidAmount = 0,
    int? paymentMethodId,
    String? paymentNote,
    String? chequeNo,
    DateTime? chequeDate,
    int? bankId,
    String? saleNote,
  }) async {
    final cart = ref.read(cartProvider);

    final body = cart.toCreateJson(
      saleStatus: saleStatus,
      paymentStatus: paymentStatus,
      paidAmount: paidAmount,
      paymentMethodId: paymentMethodId,
      paymentNote: paymentNote,
      chequeNo: chequeNo,
      chequeDate: chequeDate,
      bankId: bankId,
      saleNote: saleNote,
    );

    // Captured before the attempt so a timeout can look the sale up by the
    // number the server said it was about to use.
    final referencePreview =
        ref.read(saleFormMetadataProvider).value?.nextReferenceNoPreview;

    SaleDetail sale;
    try {
      sale = await ref.read(salesApiProvider).create(body);
    } on ApiException catch (e) {
      // POST /sales is explicitly NOT idempotent (API docs §2.6): a request
      // that timed out may well have committed, and resubmitting would bill
      // the customer twice. So never retry — look instead.
      if (!_isInconclusive(e)) rethrow;

      final existing = await _findSaleByReference(ref, referencePreview);
      if (existing == null) {
        throw ApiException(
          code: ApiErrorCode.networkError,
          message:
              'The connection dropped and we could not confirm whether this '
              'sale saved. Check Sales history before charging again.',
          statusCode: e.statusCode,
        );
      }
      sale = existing;
    }

    // The sales list and dashboard totals are now stale.
    ref.invalidate(salesListProvider);
    ref.invalidate(dashboardRecentProvider);

    return sale;
  };
});

/// Whether a failure leaves it genuinely unknown if the sale was created.
///
/// A validation error or a 403 means the server rejected the request outright,
/// so nothing was written. A timeout or dropped connection means the request
/// may have been processed and only the response was lost.
bool _isInconclusive(ApiException e) {
  return e.code == ApiErrorCode.networkError ||
      e.code == ApiErrorCode.serverError;
}

/// Looks for a sale created under [reference].
///
/// The reference is only a preview, not a reservation (API docs §7.8) — it can
/// drift if another till creates a sale in between — so a miss is treated as
/// inconclusive by the caller rather than as proof nothing was written.
Future<SaleDetail?> _findSaleByReference(Ref ref, String? reference) async {
  if (reference == null || reference.isEmpty) return null;

  try {
    final now = DateTime.now();
    final page = await ref.read(salesApiProvider).list(
          SaleFilters(
            startDate: DateTime(now.year, now.month, now.day),
            endDate: DateTime(now.year, now.month, now.day),
            search: reference,
            perPage: 5,
          ),
        );

    for (final row in page.items) {
      if (row.referenceNo == reference) {
        return ref.read(salesApiProvider).show(row.id);
      }
    }
  } on Object {
    // The lookup is best-effort; if it also fails the caller reports the
    // outcome as unconfirmed, which is the honest answer.
  }

  return null;
}
