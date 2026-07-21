import 'package:intl/intl.dart';

/// Shared formatters. Instantiating a [NumberFormat] is not free, so these are
/// created once rather than per build.
abstract final class Format {
  static final _money = NumberFormat('#,##0.00');
  static final _quantity = NumberFormat('#,##0.##');
  static final _dateTime = DateFormat('d MMM yyyy, h:mm a');
  static final _date = DateFormat('d MMM yyyy');
  static final _shortDate = DateFormat('d MMM');

  /// Money without a currency symbol, e.g. `1,234.50`.
  static String amount(num value) => _money.format(value);

  /// Money with the currency code, e.g. `AED 1,234.50`.
  static String money(num value, {String currency = 'AED'}) =>
      '$currency ${_money.format(value)}';

  /// Quantities and weights, trimming trailing zeros: `12.5`, `3`.
  static String quantity(num value) => _quantity.format(value);

  static String dateTime(DateTime? value) =>
      value == null ? '-' : _dateTime.format(value.toLocal());

  static String date(DateTime? value) =>
      value == null ? '-' : _date.format(value.toLocal());

  static String shortDate(DateTime? value) =>
      value == null ? '-' : _shortDate.format(value.toLocal());

  /// Compact range label for the filter bar, e.g. `1 Jul - 20 Jul 2026`.
  static String dateRange(DateTime start, DateTime end) {
    if (start.year == end.year && start.month == end.month &&
        start.day == end.day) {
      return _date.format(start);
    }
    return start.year == end.year
        ? '${_shortDate.format(start)} - ${_date.format(end)}'
        : '${_date.format(start)} - ${_date.format(end)}';
  }
}
