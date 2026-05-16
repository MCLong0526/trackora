import 'dart:convert';

import 'package:http/http.dart' as http;

// ── Data classes ───────────────────────────────────────────────────────────────

class StockPoint {
  final DateTime time;
  final double close;

  const StockPoint({required this.time, required this.close});
}

class StockQuote {
  final String symbol;
  final String name;
  final double price;
  final double change;
  final double changePercent;
  final String currency;
  final List<StockPoint> chartPoints;

  const StockQuote({
    required this.symbol,
    required this.name,
    required this.price,
    required this.change,
    required this.changePercent,
    required this.currency,
    required this.chartPoints,
  });

  bool get isUp => changePercent >= 0;
}

class StockSearchResult {
  final String symbol;
  final String name;
  final String exchange;

  const StockSearchResult({
    required this.symbol,
    required this.name,
    required this.exchange,
  });
}

// ── Service ────────────────────────────────────────────────────────────────────

/// Fetches real stock data from Yahoo Finance (no API key required).
/// Uses the unofficial v8 chart API which works for mobile HTTP clients.
class StockService {
  static const _host = 'query1.finance.yahoo.com';
  static const _fallbackHost = 'query2.finance.yahoo.com';

  static const _headers = {
    'User-Agent':
        'Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15',
    'Accept': 'application/json',
  };

  // Range labels shown in the UI → Yahoo Finance params
  static const rangeOptions = ['1W', '1M', '3M', '6M', '1Y'];

  static String _toYahooRange(String range) {
    switch (range) {
      case '1W':
        return '5d';
      case '3M':
        return '3mo';
      case '6M':
        return '6mo';
      case '1Y':
        return '1y';
      default:
        return '1mo';
    }
  }

  static String _toYahooInterval(String range) {
    switch (range) {
      case '1W':
        return '1h';
      default:
        return '1d';
    }
  }

  /// Fetch quote + price history for [symbol] over [range] (e.g. '1M').
  Future<StockQuote?> getQuote(String symbol,
      {String range = '1M'}) async {
    final yahooRange = _toYahooRange(range);
    final interval = _toYahooInterval(range);
    final sym = symbol.trim().toUpperCase();

    for (final host in [_host, _fallbackHost]) {
      try {
        final uri = Uri.https(host, '/v8/finance/chart/$sym', {
          'interval': interval,
          'range': yahooRange,
          'includePrePost': 'false',
        });

        final response = await http
            .get(uri, headers: _headers)
            .timeout(const Duration(seconds: 12));

        if (response.statusCode != 200) continue;

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final chart = data['chart'] as Map<String, dynamic>?;
        final results = chart?['result'] as List?;
        if (results == null || results.isEmpty) continue;

        final result = results.first as Map<String, dynamic>;
        final meta = result['meta'] as Map<String, dynamic>? ?? {};

        final price =
            (meta['regularMarketPrice'] as num?)?.toDouble() ?? 0.0;
        final prevClose =
            (meta['chartPreviousClose'] as num?)?.toDouble() ??
                (meta['previousClose'] as num?)?.toDouble() ??
                price;
        final change = price - prevClose;
        final changePercent =
            prevClose > 0 ? (change / prevClose) * 100 : 0.0;
        final currency = meta['currency'] as String? ?? 'USD';
        final name = meta['longName'] as String? ??
            meta['shortName'] as String? ??
            sym;

        final timestamps =
            (result['timestamp'] as List?)?.cast<num>() ?? [];
        final quoteList =
            result['indicators']?['quote'] as List?;
        final closes = quoteList != null && quoteList.isNotEmpty
            ? (quoteList.first as Map<String, dynamic>)['close'] as List?
            : null;

        final points = <StockPoint>[];
        for (var i = 0; i < timestamps.length; i++) {
          final c = closes != null && i < closes.length
              ? (closes[i] as num?)?.toDouble()
              : null;
          if (c != null) {
            points.add(StockPoint(
              time: DateTime.fromMillisecondsSinceEpoch(
                  timestamps[i].toInt() * 1000),
              close: c,
            ));
          }
        }

        return StockQuote(
          symbol: sym,
          name: name,
          price: price,
          change: change,
          changePercent: changePercent,
          currency: currency,
          chartPoints: points,
        );
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// Search for stocks by symbol or company name.
  Future<List<StockSearchResult>> search(String query) async {
    if (query.trim().isEmpty) return [];
    try {
      final uri = Uri.https(_host, '/v1/finance/search', {
        'q': query.trim(),
        'quotesCount': '10',
        'newsCount': '0',
        'enableFuzzyQuery': 'false',
      });
      final response = await http
          .get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return [];
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final quotes = data['quotes'] as List? ?? [];

      return quotes
          .whereType<Map<String, dynamic>>()
          .where((q) => q['quoteType'] == 'EQUITY')
          .map((q) => StockSearchResult(
                symbol: q['symbol'] as String? ?? '',
                name: q['longname'] as String? ??
                    q['shortname'] as String? ??
                    '',
                exchange: q['exchange'] as String? ?? '',
              ))
          .where((r) => r.symbol.isNotEmpty)
          .toList();
    } catch (_) {
      return [];
    }
  }
}
