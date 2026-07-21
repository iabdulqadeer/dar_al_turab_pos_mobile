/// Typed representation of the API's error envelope.
///
/// The Laravel side always returns
/// `{success: false, message, errors, code}` for `api/*` requests
/// (see `app/Exceptions/Handler.php`), so every failure has a stable
/// machine-readable `code` we can branch on instead of parsing messages.
class ApiException implements Exception {
  const ApiException({
    required this.code,
    required this.message,
    this.statusCode,
    this.errors,
  });

  /// Server error code, e.g. `INSUFFICIENT_STOCK`. [ApiErrorCode] lists the
  /// known values; unknown codes pass through untouched.
  final String code;
  final String message;
  final int? statusCode;

  /// Laravel validation bag: field name -> list of messages.
  final Map<String, List<String>>? errors;

  /// First message for [field], if the server flagged it.
  String? errorFor(String field) => errors?[field]?.firstOrNull;

  bool get isUnauthenticated =>
      code == ApiErrorCode.unauthenticated || statusCode == 401;

  bool get isValidation => code == ApiErrorCode.validationError;

  /// True when the failure is transient and a retry could plausibly succeed.
  bool get isRetryable =>
      code == ApiErrorCode.networkError || code == ApiErrorCode.serverError;

  @override
  String toString() => 'ApiException($code, $statusCode): $message';
}

/// Error codes emitted by the Laravel v1 API, plus two client-only codes.
///
/// Kept as a flat set of constants rather than an enum so an unrecognised
/// server code never crashes deserialisation.
abstract final class ApiErrorCode {
  // Auth
  static const unauthenticated = 'UNAUTHENTICATED';
  static const invalidCredentials = 'INVALID_CREDENTIALS';
  static const accountInactive = 'ACCOUNT_INACTIVE';
  static const demoMode = 'DEMO_MODE';
  static const forbidden = 'FORBIDDEN';
  static const invalidCurrentPassword = 'INVALID_CURRENT_PASSWORD';

  // Routing
  static const notFound = 'NOT_FOUND';
  static const endpointNotFound = 'ENDPOINT_NOT_FOUND';
  static const draftNotFound = 'DRAFT_NOT_FOUND';

  // Sale writes
  static const validationError = 'VALIDATION_ERROR';
  static const insufficientStock = 'INSUFFICIENT_STOCK';
  static const pointsPaymentUnsupported = 'POINTS_PAYMENT_UNSUPPORTED';
  static const invalidUnitOperator = 'INVALID_UNIT_OPERATOR';
  static const unknownSaleUnit = 'UNKNOWN_SALE_UNIT';
  static const noWarehouseAssigned = 'NO_WAREHOUSE_ASSIGNED';
  static const warehouseRequired = 'WAREHOUSE_REQUIRED';
  static const invalidPaymentMethod = 'INVALID_PAYMENT_METHOD';
  static const serialNumberFailed = 'SERIAL_NUMBER_FAILED';

  // Throttling / server
  static const tooManyAttempts = 'TOO_MANY_ATTEMPTS';
  static const httpError = 'HTTP_ERROR';
  static const serverError = 'SERVER_ERROR';

  // Client-only (never sent by the server)
  static const networkError = 'NETWORK_ERROR';
  static const unexpectedResponse = 'UNEXPECTED_RESPONSE';
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
