import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ExchangeRateService {
  static const _kCachePrefix = 'fx_rates_';
  static const _freshTtl = Duration(hours: 12);
  static const _staleTtl = Duration(days: 7);

  /// Returns rates from [base] currency to all others.
  /// Key = currency code, value = rate (1 [base] = X [key]).
  Future<Map<String, double>> getRates(String base) async {
    final cached = await _loadCached(base);
    final now = DateTime.now();

    if (cached != null) {
      final fetchedAt = cached['fetchedAt'] as DateTime;
      final isFresh = now.difference(fetchedAt) < _freshTtl;
      if (isFresh) return Map<String, double>.from(cached['rates'] as Map);
      // Stale: attempt refresh, fall back to stale cache on error
      try {
        final fresh = await _fetchFromNetwork(base);
        await _saveCache(base, fresh);
        return fresh;
      } catch (_) {
        // Use stale cache if within staleTtl
        if (now.difference(fetchedAt) < _staleTtl) {
          return Map<String, double>.from(cached['rates'] as Map);
        }
        return {base: 1.0};
      }
    }

    // No cache: try network
    try {
      final rates = await _fetchFromNetwork(base);
      await _saveCache(base, rates);
      return rates;
    } catch (_) {
      return {base: 1.0};
    }
  }

  /// Convert [amount] from [from] to [to] currency using [base]-rooted rates.
  Future<double> convert({
    required double amount,
    required String from,
    required String to,
    required String base,
  }) async {
    if (from == to) return amount;
    final rates = await getRates(base);
    final rate = _crossRate(from: from, to: to, base: base, rates: rates);
    return amount * rate;
  }

  /// Rate to convert 1 unit of [from] into [to].
  Future<double?> getRate({
    required String from,
    required String to,
    required String base,
  }) async {
    if (from == to) return 1.0;
    final rates = await getRates(base);
    if (rates.isEmpty || (rates.length == 1 && rates.containsKey(base))) {
      return null; // no real data
    }
    return _crossRate(from: from, to: to, base: base, rates: rates);
  }

  Future<DateTime?> lastFetched(String base) async {
    final cached = await _loadCached(base);
    return cached?['fetchedAt'] as DateTime?;
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  double _crossRate({
    required String from,
    required String to,
    required String base,
    required Map<String, double> rates,
  }) {
    // rates: base→X
    if (from == base) return rates[to] ?? 1.0;
    if (to == base) return 1.0 / (rates[from] ?? 1.0);
    final fromRate = rates[from] ?? 1.0; // base→from
    final toRate = rates[to] ?? 1.0; // base→to
    return toRate / fromRate; // from→to
  }

  Future<Map<String, double>> _fetchFromNetwork(String base) async {
    final uri = Uri.parse('https://api.frankfurter.app/latest?base=$base');
    final response = await http.get(uri).timeout(const Duration(seconds: 8));
    if (response.statusCode != 200) {
      throw Exception('FX fetch failed: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final ratesRaw = json['rates'] as Map<String, dynamic>? ?? {};
    final rates = <String, double>{};
    for (final entry in ratesRaw.entries) {
      rates[entry.key] = (entry.value as num).toDouble();
    }
    rates[base] = 1.0;
    return rates;
  }

  Future<Map<String, dynamic>?> _loadCached(String base) async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return null;
    final raw = prefs.getString('$_kCachePrefix$base');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      final fetchedAt = DateTime.parse(json['fetchedAt'] as String);
      final rates = (json['rates'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, (v as num).toDouble()),
      );
      return {'fetchedAt': fetchedAt, 'rates': rates};
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveCache(String base, Map<String, double> rates) async {
    final prefs = await _prefsOrNull();
    if (prefs == null) return;
    final payload = jsonEncode({
      'fetchedAt': DateTime.now().toIso8601String(),
      'base': base,
      'rates': rates,
    });
    await prefs.setString('$_kCachePrefix$base', payload);
  }

  Future<SharedPreferences?> _prefsOrNull() async {
    try {
      return await SharedPreferences.getInstance();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on ArgumentError {
      return null;
    }
  }
}
