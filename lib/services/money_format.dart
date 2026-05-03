import 'package:intl/intl.dart';

final NumberFormat _moneyNumberFormat = NumberFormat('#,##0.00');

String formatMoney(String symbol, double value, {bool forceSign = false}) {
  final isNegative = value < 0;
  final sign = isNegative
      ? '−'
      : forceSign
      ? '+'
      : '';
  final separator = symbol.length > 1 ? ' ' : '';
  return '$sign$symbol$separator${_moneyNumberFormat.format(value.abs())}';
}

String formatMoneyPerMonth(String symbol, double value) {
  return '${formatMoney(symbol, value)}/month';
}
