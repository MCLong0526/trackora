/// Synchronous currency converter backed by a pre-loaded rates map.
/// Use this for batch conversions (stats, totals) without async overhead.
class CurrencyConverter {
  /// Base currency code (e.g. 'MYR'). Rates are expressed as 1 base = X foreign.
  final String base;

  /// Rates map: foreign code → units of foreign per 1 base.
  final Map<String, double> rates;

  const CurrencyConverter(this.base, this.rates);

  /// Whether real rates are available (vs. identity fallback).
  bool get hasRates => rates.isNotEmpty && !(rates.length == 1 && rates.containsKey(base));

  /// Convert [amount] in [from] currency to [base].
  double toBase(double amount, String from) {
    if (from == base) return amount;
    final rate = rates[from];
    if (rate == null || rate == 0) return amount; // unknown — keep as-is
    return amount / rate; // from → base
  }

  /// Rate to convert 1 unit of [from] into [base].
  double rateToBase(String from) {
    if (from == base) return 1.0;
    final rate = rates[from];
    if (rate == null || rate == 0) return 1.0;
    return 1.0 / rate;
  }

  /// Rate to convert 1 unit of [base] into [to].
  double rateFromBase(String to) {
    if (to == base) return 1.0;
    return rates[to] ?? 1.0;
  }

  /// Rate to convert 1 unit of [from] into [to] (cross rate).
  double crossRate(String from, String to) {
    if (from == to) return 1.0;
    return rateToBase(from) * rateFromBase(to);
  }

  static const CurrencyConverter identity = CurrencyConverter('USD', {});
}
