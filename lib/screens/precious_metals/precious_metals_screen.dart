import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/account.dart';
import '../../models/precious_metal.dart';
import '../../repositories/firebase_precious_metal_repository.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Live price provider
// ─────────────────────────────────────────────────────────────────────────────

const _currencySymbolMap = {
  'RM': 'MYR', '\$': 'USD', 'US\$': 'USD', '€': 'EUR', '£': 'GBP',
  '¥': 'JPY', '₹': 'INR', 'S\$': 'SGD', 'A\$': 'AUD', 'C\$': 'CAD',
  'HK\$': 'HKD', '₩': 'KRW', 'CHF': 'CHF', 'kr': 'SEK', 'R': 'ZAR',
};

class _SpotData {
  final double goldPerGram;
  final double silverPerGram;
  final double usdToLocal;
  const _SpotData({
    required this.goldPerGram,
    required this.silverPerGram,
    required this.usdToLocal,
  });
  double forMetal(MetalType m) =>
      m == MetalType.gold ? goldPerGram : silverPerGram;
}

class _PricePoint {
  final DateTime time;
  final double priceUsdOzt;
  const _PricePoint({required this.time, required this.priceUsdOzt});
}

@immutable
class _ChartQuery {
  final String ticker;
  final String range;
  const _ChartQuery({required this.ticker, required this.range});
  @override
  bool operator ==(Object other) =>
      other is _ChartQuery && ticker == other.ticker && range == other.range;
  @override
  int get hashCode => Object.hash(ticker, range);
}

final _liveSpotProvider =
    FutureProvider.autoDispose.family<_SpotData, String>(
  (ref, currencySymbol) async {
    const ozt = 31.1034768;
    final rawCode = currencySymbol.trim();
    final isoCode = (_currencySymbolMap[rawCode] ?? rawCode).toUpperCase();

    final headers = <String, String>{'User-Agent': 'Mozilla/5.0'};
    final results = await Future.wait([
      http.get(
        Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/GC=F?interval=1d&range=1d',
        ),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
      http.get(
        Uri.parse(
          'https://query1.finance.yahoo.com/v8/finance/chart/SI=F?interval=1d&range=1d',
        ),
        headers: headers,
      ).timeout(const Duration(seconds: 15)),
    ]);

    if (results[0].statusCode != 200 || results[1].statusCode != 200) {
      throw Exception('Spot price unavailable');
    }

    final goldJson =
        jsonDecode(results[0].body) as Map<String, dynamic>;
    final silverJson =
        jsonDecode(results[1].body) as Map<String, dynamic>;

    final goldUsd =
        (goldJson['chart']['result'][0]['meta']['regularMarketPrice'] as num)
            .toDouble();
    final silverUsd =
        (silverJson['chart']['result'][0]['meta']['regularMarketPrice'] as num)
            .toDouble();

    double rate = 1.0;
    if (isoCode.isNotEmpty && isoCode != 'USD') {
      try {
        final fxResp = await http.get(
          Uri.parse(
            'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json',
          ),
        ).timeout(const Duration(seconds: 12));
        if (fxResp.statusCode == 200) {
          final fx = jsonDecode(fxResp.body) as Map<String, dynamic>;
          final rates = fx['usd'] as Map<String, dynamic>?;
          if (rates != null) {
            rate =
                (rates[isoCode.toLowerCase()] as num?)?.toDouble() ?? 1.0;
          }
        }
      } catch (_) {
        const fallback = {
          'MYR': 4.48, 'SGD': 1.35, 'EUR': 0.92,
          'GBP': 0.79, 'JPY': 149.0, 'INR': 83.5,
        };
        rate = (fallback[isoCode] ?? 1.0).toDouble();
      }
    }

    return _SpotData(
      goldPerGram: goldUsd / ozt * rate,
      silverPerGram: silverUsd / ozt * rate,
      usdToLocal: rate,
    );
  },
);

final _liveChartProvider =
    FutureProvider.autoDispose.family<List<_PricePoint>, _ChartQuery>(
  (ref, q) async {
    final (interval, range) = switch (q.range) {
      '1D' => ('5m', '1d'),
      '1W' => ('1h', '5d'),
      '3M' => ('1d', '3mo'),
      '1Y' => ('1wk', '1y'),
      'ALL' => ('1mo', 'max'),
      _ => ('1d', '1mo'),
    };
    final resp = await http.get(
      Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/${q.ticker}?interval=$interval&range=$range',
      ),
      headers: {'User-Agent': 'Mozilla/5.0'},
    ).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) throw Exception('Chart unavailable');
    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    final result =
        ((json['chart']['result'] as List?)?.firstOrNull) as Map<String, dynamic>?;
    if (result == null) throw Exception('No data');
    final timestamps = (result['timestamp'] as List?)?.cast<int>() ?? [];
    final closes =
        ((result['indicators']['quote'] as List?)?.firstOrNull
                as Map<String, dynamic>?)?['close'] as List? ??
            [];
    final pts = <_PricePoint>[];
    final len = math.min(timestamps.length, closes.length);
    for (var i = 0; i < len; i++) {
      final c = closes[i];
      if (c != null) {
        pts.add(_PricePoint(
          time: DateTime.fromMillisecondsSinceEpoch(timestamps[i] * 1000),
          priceUsdOzt: (c as num).toDouble(),
        ));
      }
    }
    return pts;
  },
);

IconData _iconForAccountType(AccountType type) {
  switch (type) {
    case AccountType.bank:
      return CupertinoIcons.building_2_fill;
    case AccountType.eWallet:
      return CupertinoIcons.device_phone_portrait;
    case AccountType.cash:
      return CupertinoIcons.money_dollar_circle_fill;
    case AccountType.creditCard:
      return CupertinoIcons.creditcard_fill;
    case AccountType.loan:
      return CupertinoIcons.doc_text_fill;
    case AccountType.mortgage:
      return CupertinoIcons.house_fill;
    case AccountType.bnpl:
      return CupertinoIcons.cart_fill;
    case AccountType.otherLiability:
      return CupertinoIcons.minus_circle_fill;
  }
}

Color _accentForAccountType(AccountType type) {
  switch (type) {
    case AccountType.bank:
      return const Color(0xFF2A6FB5);
    case AccountType.eWallet:
      return const Color(0xFF1F7A60);
    case AccountType.cash:
      return const Color(0xFFA0801C);
    case AccountType.creditCard:
      return const Color(0xFFB03060);
    case AccountType.loan:
      return const Color(0xFF9C4A1A);
    case AccountType.mortgage:
      return const Color(0xFF6B4D2A);
    case AccountType.bnpl:
      return const Color(0xFF5C3A9E);
    case AccountType.otherLiability:
      return const Color(0xFF7A4040);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Screen
// ─────────────────────────────────────────────────────────────────────────────

class PreciousMetalsScreen extends ConsumerStatefulWidget {
  const PreciousMetalsScreen({super.key});

  @override
  ConsumerState<PreciousMetalsScreen> createState() =>
      _PreciousMetalsScreenState();
}

class _PreciousMetalsScreenState extends ConsumerState<PreciousMetalsScreen>
    with SingleTickerProviderStateMixin {
  int _tab = 0;
  late final PageController _pageCtrl;
  Timer? _refreshTimer;

  static const _metals = [MetalType.gold, MetalType.silver];
  MetalType get _active => _metals[_tab];

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted) return;
      final symbol = ref.read(currencySymbolProvider).valueOrNull ?? '\$';
      ref.invalidate(_liveSpotProvider(symbol));
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _openAdd(MetalAction action) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMetalSheet(
        initialMetal: _active,
        initialAction: action,
      ),
    );
  }

  Future<void> _openHistory() async {
    final metals =
        ref.read(preciousMetalsProvider).valueOrNull ?? const <PreciousMetal>[];
    final symbol = ref.read(currencySymbolProvider).valueOrNull ?? '\$';
    final filtered = metals
        .where((m) => m.metalType == _active)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _HistorySheet(
        metalType: _active,
        items: filtered,
        symbol: symbol,
        onEdit: _openEdit,
        onDelete: _deleteMetal,
        onCopy: _copyMetal,
      ),
    );
  }

  Future<void> _deleteMetal(PreciousMetal metal) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    await ref.read(preciousMetalRepositoryProvider).delete(user.uid, metal.id);
    if (storageMode == StorageMode.firebase) {
      FirebasePreciousMetalRepository().delete(user.uid, metal.id).catchError((_) {});
    }
    if (mounted) {
      AppToast.show(context, 'Record deleted', type: AppToastType.info,
          icon: CupertinoIcons.trash);
    }
  }

  void _copyMetal(PreciousMetal metal) {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    AppToast.show(context, 'Record copied', type: AppToastType.info,
        icon: CupertinoIcons.doc_on_doc);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMetalSheet(
        initialMetal: metal.metalType,
        initialAction: metal.action,
        copyFrom: metal,
      ),
    );
  }

  Future<void> _openEdit(PreciousMetal metal) async {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddMetalSheet(
        initialMetal: metal.metalType,
        initialAction: metal.action,
        editMetal: metal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metals =
        ref.watch(preciousMetalsProvider).valueOrNull ?? const <PreciousMetal>[];
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final spotAsync = ref.watch(_liveSpotProvider(symbol));

    final metricsMap = _calcMetrics(metals);

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        title: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Text(
            _active.label,
            key: ValueKey(_active),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        actions: [
          if (spotAsync.isLoading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: Icon(
                CupertinoIcons.arrow_clockwise,
                color: spotAsync.hasError ? AppColors.expense : brand.ink,
                size: 20,
              ),
              onPressed: () => ref.invalidate(_liveSpotProvider(symbol)),
            ),
        ],
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Hero cards (PageView — swipe Gold ↔ Silver) ───────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 620,
                child: PageView.builder(
                  controller: _pageCtrl,
                  onPageChanged: (i) => setState(() => _tab = i),
                  itemCount: _metals.length,
                  itemBuilder: (_, i) {
                    final m = _metals[i];
                    final allForMetal = metals
                        .where((x) => x.metalType == m)
                        .toList()
                      ..sort((a, b) => a.date.compareTo(b.date));
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
                      child: _HeroCard(
                        key: ValueKey(m),
                        metalType: m,
                        metrics: metricsMap[m]!,
                        symbol: symbol,
                        isDark: isDark,
                        allItems: allForMetal,
                      ),
                    );
                  },
                ),
              ),
            ),

            // ── Page dots ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.only(top: 10),
                child: _PageDots(count: _metals.length, current: _tab),
              ),
            ),

            // ── History / Sell / Buy buttons ───────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    // History
                    _IconActionBtn(
                      icon: CupertinoIcons.list_bullet,
                      onTap: _openHistory,
                      brand: brand,
                    ),
                    const SizedBox(width: 10),
                    // Buy (primary)
                    Expanded(
                      child: _FilledBtn(
                        label: 'Buy ${_active.label}',
                        icon: CupertinoIcons.plus,
                        onTap: () => _openAdd(MetalAction.buy),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // bottom padding
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
      ),
    );
  }

  Map<MetalType, _Metrics> _calcMetrics(List<PreciousMetal> metals) {
    final acc = {for (final t in MetalType.values) t: _Acc()};
    for (final m in metals) {
      acc[m.metalType]!.add(m);
    }
    return {for (final t in MetalType.values) t: acc[t]!.build()};
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metrics
// ─────────────────────────────────────────────────────────────────────────────

class _Metrics {
  final double holdGrams;
  final double buyWeightGrams;
  final double buyAmount;
  final double? latestPrice;

  const _Metrics({
    required this.holdGrams,
    required this.buyWeightGrams,
    required this.buyAmount,
    required this.latestPrice,
  });

  double? get avgBuy =>
      buyWeightGrams > 0 ? buyAmount / buyWeightGrams : null;
  double? get estValue =>
      holdGrams > 0 && latestPrice != null ? holdGrams * latestPrice! : null;
  double? get gainLoss =>
      estValue != null && buyAmount > 0 ? estValue! - buyAmount : null;
  double? get gainPct =>
      gainLoss != null && buyAmount > 0 ? gainLoss! / buyAmount * 100 : null;
}

class _Acc {
  double _hold = 0, _buyW = 0, _buyAmt = 0;
  double? _price;
  DateTime? _priceDate;

  void add(PreciousMetal m) {
    if (m.action == MetalAction.buy) {
      _hold += m.weightGrams;
      _buyW += m.weightGrams;
      _buyAmt += m.totalAmount;
    } else {
      _hold -= m.weightGrams;
    }
    final p = m.pricePerGram ??
        (m.weightGrams > 0 ? m.totalAmount / m.weightGrams : null);
    if (p != null && p > 0) {
      if (_priceDate == null || m.date.isAfter(_priceDate!)) {
        _price = p;
        _priceDate = m.date;
      }
    }
  }

  _Metrics build() => _Metrics(
        holdGrams: _hold < 0 ? 0 : _hold,
        buyWeightGrams: _buyW,
        buyAmount: _buyAmt,
        latestPrice: _price,
      );
}

String _grams(double v) {
  final s = v < 0.005 ? 0.0 : v;
  return s.toStringAsFixed(s >= 100 ? 1 : 2);
}

// ─────────────────────────────────────────────────────────────────────────────
// Page dots
// ─────────────────────────────────────────────────────────────────────────────

class _PageDots extends StatelessWidget {
  final int count;
  final int current;

  const _PageDots({required this.count, required this.current});

  @override
  Widget build(BuildContext context) {
    final metals = MetalType.values;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final isActive = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeInOut,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 20 : 6,
          height: 6,
          decoration: BoxDecoration(
            color: isActive
                ? metals[i].primaryColor
                : metals[i].primaryColor.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(3),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Card — white card with chart, matches screenshot design
// ─────────────────────────────────────────────────────────────────────────────

class _ChartPoint {
  final double x;
  final double y;
  final MetalAction action;
  const _ChartPoint(this.x, this.y, this.action);
}

class _HeroCard extends ConsumerStatefulWidget {
  final MetalType metalType;
  final _Metrics metrics;
  final String symbol;
  final bool isDark;
  final List<PreciousMetal> allItems;

  const _HeroCard({
    super.key,
    required this.metalType,
    required this.metrics,
    required this.symbol,
    required this.isDark,
    required this.allItems,
  });

  @override
  ConsumerState<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends ConsumerState<_HeroCard> {
  String _range = '1M';
  final _calcCtrl = TextEditingController();
  double? _calcGrams;

  static const _ranges = ['1D', '1W', '1M', '3M', '1Y', 'ALL'];

  String get _ticker =>
      widget.metalType == MetalType.gold ? 'GC=F' : 'SI=F';

  @override
  void dispose() {
    _calcCtrl.dispose();
    super.dispose();
  }

  Color get _cardBg =>
      widget.isDark ? const Color(0xFF1B1B20) : Colors.white;
  Color get _ink =>
      widget.isDark ? const Color(0xFFF2F2F4) : const Color(0xFF0F1020);
  Color get _soft =>
      widget.isDark ? const Color(0xFFA1A1A6) : const Color(0xFF7A7A8E);
  Color get _divider =>
      widget.isDark ? const Color(0xFF2A2A30) : const Color(0xFFEAEAEC);
  Color get _fieldBg =>
      widget.isDark ? const Color(0xFF252530) : const Color(0xFFF5F5F8);

  @override
  Widget build(BuildContext context) {
    final metalColor = widget.metalType.primaryColor;
    final metrics = widget.metrics;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? widget.symbol;
    final spotAsync = ref.watch(_liveSpotProvider(symbol));
    final spotData = spotAsync.valueOrNull;
    final livePrice = spotData?.forMetal(widget.metalType);
    final usdToLocal = spotData?.usdToLocal ?? 1.0;
    final isLive = livePrice != null;

    final displayPrice = livePrice ?? metrics.latestPrice;
    final estValue = (metrics.holdGrams > 0 && displayPrice != null)
        ? metrics.holdGrams * displayPrice
        : null;
    final gainLoss = (estValue != null && metrics.buyAmount > 0)
        ? estValue - metrics.buyAmount
        : null;
    final gainPct = (gainLoss != null && metrics.buyAmount > 0)
        ? gainLoss / metrics.buyAmount * 100
        : null;
    final gainPositive = (gainLoss ?? 0) >= 0;
    final gainColor = gainPositive ? AppColors.income : AppColors.expense;

    // Gram calculator computed value
    final calcValue = (_calcGrams != null && displayPrice != null && _calcGrams! > 0)
        ? _calcGrams! * displayPrice
        : null;

    // Historical chart
    final chartAsync = ref.watch(
      _liveChartProvider(_ChartQuery(ticker: _ticker, range: _range)),
    );

    const ozt = 31.1034768;

    return SizedBox.expand(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: _cardBg,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color:
                  Colors.black.withValues(alpha: widget.isDark ? 0.30 : 0.08),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Row 1: badge + live price ──────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _MetalBadge(metalType: widget.metalType),
                  const Spacer(),
                  // Live price section
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isLive)
                            _LivePulseDot(color: AppColors.income)
                          else
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _soft.withValues(alpha: 0.5),
                              ),
                            ),
                          const SizedBox(width: 5),
                          Text(
                            isLive ? 'LIVE' : 'LAST',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: isLive ? AppColors.income : _soft,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      displayPrice != null
                          ? Text(
                              '${formatMoney(symbol, displayPrice)}/g',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                                color: _ink,
                                height: 1.0,
                              ),
                            )
                          : spotAsync.isLoading
                              ? SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: metalColor,
                                  ),
                                )
                              : Text('—',
                                  style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      color: _soft)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // ── Holdings + gain row ────────────────────────────────────
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Holdings',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _soft,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _grams(metrics.holdGrams),
                            style: TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w900,
                              color: _ink,
                              height: 1.0,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'g',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _soft,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Spacer(),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (gainPct != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: gainPositive
                                ? AppColors.income.withValues(alpha: 0.12)
                                : AppColors.expense.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                gainPositive
                                    ? Icons.arrow_upward_rounded
                                    : Icons.arrow_downward_rounded,
                                size: 11,
                                color: gainColor,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                '${gainPositive ? '+' : ''}${gainPct.toStringAsFixed(2)}%',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: gainColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(height: 4),
                      Text(
                        estValue != null
                            ? formatMoney(symbol, estValue)
                            : '—',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                        ),
                      ),
                      Text(
                        'est. value',
                        style: TextStyle(fontSize: 10, color: _soft),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // ── Gram calculator ────────────────────────────────────────
              Container(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                decoration: BoxDecoration(
                  color: _fieldBg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: metalColor.withValues(alpha: 0.18),
                    width: 1,
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: metalColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Icon(
                          CupertinoIcons.cube_box_fill,
                          size: 16,
                          color: metalColor,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'GRAM CALCULATOR',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: _soft,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 2),
                          TextField(
                            controller: _calcCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            cursorHeight: 18.0,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _ink,
                              height: 1.2,
                            ),
                            strutStyle: const StrutStyle(
                              forceStrutHeight: true,
                              height: 1.2,
                              fontSize: 15,
                            ),
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(vertical: 2),
                              border: InputBorder.none,
                              hintText: '0.00 g',
                              hintStyle: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w400,
                                color: _soft.withValues(alpha: 0.45),
                              ),
                            ),
                            onChanged: (v) {
                              setState(() {
                                _calcGrams = double.tryParse(v);
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 220),
                      switchInCurve: Curves.easeOutBack,
                      switchOutCurve: Curves.easeIn,
                      transitionBuilder: (child, anim) => FadeTransition(
                        opacity: anim,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: 0.85, end: 1.0)
                              .animate(anim),
                          child: child,
                        ),
                      ),
                      child: calcValue != null
                          ? _CalcResult(
                              key: ValueKey(
                                  (calcValue / 10).round()),
                              value: formatMoney(symbol, calcValue),
                              color: metalColor,
                              soft: _soft,
                            )
                          : const SizedBox.shrink(key: ValueKey('empty')),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // ── Historical price chart ─────────────────────────────────
              Expanded(
                child: ClipRect(
                  child: _buildHistoricalChart(
                    chartAsync,
                    metalColor,
                    ozt,
                    usdToLocal,
                  ),
                ),
              ),
              const SizedBox(height: 6),

              // ── Legend ────────────────────────────────────────────────
              Row(
                children: [
                  _LegendDot(color: AppColors.income, label: 'BUY', soft: _soft),
                  const SizedBox(width: 10),
                  _LegendDot(color: AppColors.expense, label: 'SELL', soft: _soft),
                  const SizedBox(width: 10),
                  _LegendDash(
                    color: _soft.withValues(alpha: 0.55),
                    label: 'AVG BUY',
                    soft: _soft,
                  ),
                  const Spacer(),
                  if (chartAsync.isLoading)
                    SizedBox(
                      width: 10,
                      height: 10,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.2,
                        color: _soft,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // ── Range tabs ─────────────────────────────────────────────
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: _ranges.map((r) {
                  final active = r == _range;
                  return GestureDetector(
                    onTap: () => setState(() => _range = r),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 5),
                      decoration: BoxDecoration(
                        color: active
                            ? widget.metalType.bgColor
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        r,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight:
                              active ? FontWeight.w800 : FontWeight.w500,
                          color: active ? metalColor : _soft,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              // ── Stats row ──────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.only(top: 10),
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: _divider, width: 0.5),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: _StatCol(
                        label: 'EST. VALUE',
                        value: estValue != null
                            ? formatMoney(symbol, estValue)
                            : '—',
                        valueColor: _ink,
                        labelColor: _soft,
                      ),
                    ),
                    Container(width: 0.5, height: 36, color: _divider),
                    Expanded(
                      child: _StatCol(
                        label: 'AVG BUY',
                        value: metrics.avgBuy != null
                            ? '${formatMoney(symbol, metrics.avgBuy!)}/g'
                            : '—',
                        valueColor: _ink,
                        labelColor: _soft,
                      ),
                    ),
                    Container(width: 0.5, height: 36, color: _divider),
                    Expanded(
                      child: _StatCol(
                        label: 'GAIN / LOSS',
                        value: gainLoss != null
                            ? '${gainPositive ? '+' : ''}${formatMoney(symbol, gainLoss)}'
                            : '—',
                        valueColor: gainLoss != null ? gainColor : _ink,
                        labelColor: _soft,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHistoricalChart(
    AsyncValue<List<_PricePoint>> chartAsync,
    Color metalColor,
    double ozt,
    double usdToLocal,
  ) {
    return chartAsync.when(
      loading: () => Center(
        child: CircularProgressIndicator(strokeWidth: 2, color: metalColor),
      ),
      error: (_, __) => _buildFallbackChart(metalColor),
      data: (pts) {
        if (pts.isEmpty) return _buildFallbackChart(metalColor);

        // Convert USD/ozt → local/g
        final spots = pts
            .asMap()
            .entries
            .map((e) =>
                FlSpot(e.key.toDouble(), e.value.priceUsdOzt / ozt * usdToLocal))
            .toList();

        final minY =
            spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
        final maxY =
            spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
        final yPad = (maxY - minY) * 0.15 + 0.01;

        // Map transaction buy/sell onto nearest chart time index
        final buyMarkers = <FlSpot>[];
        final sellMarkers = <FlSpot>[];
        for (final item in widget.allItems) {
          int closest = 0;
          int minDiff = 999999999;
          for (int i = 0; i < pts.length; i++) {
            final diff =
                (pts[i].time.millisecondsSinceEpoch -
                        item.date.millisecondsSinceEpoch)
                    .abs();
            if (diff < minDiff) {
              minDiff = diff;
              closest = i;
            }
          }
          final priceLocal = pts[closest].priceUsdOzt / ozt * usdToLocal;
          if (item.action == MetalAction.buy) {
            buyMarkers.add(FlSpot(closest.toDouble(), priceLocal));
          } else {
            sellMarkers.add(FlSpot(closest.toDouble(), priceLocal));
          }
        }

        final bars = <LineChartBarData>[
          // Main price line
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: metalColor,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  metalColor.withValues(alpha: 0.18),
                  metalColor.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
          // Buy markers (green dots)
          if (buyMarkers.isNotEmpty)
            LineChartBarData(
              spots: buyMarkers,
              isCurved: false,
              color: Colors.transparent,
              barWidth: 0,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 5,
                  color: AppColors.income,
                  strokeWidth: 2,
                  strokeColor: _cardBg,
                ),
              ),
              belowBarData: BarAreaData(show: false),
            ),
          // Sell markers (red dots)
          if (sellMarkers.isNotEmpty)
            LineChartBarData(
              spots: sellMarkers,
              isCurved: false,
              color: Colors.transparent,
              barWidth: 0,
              dotData: FlDotData(
                show: true,
                getDotPainter: (_, __, ___, ____) => FlDotCirclePainter(
                  radius: 5,
                  color: AppColors.expense,
                  strokeWidth: 2,
                  strokeColor: _cardBg,
                ),
              ),
              belowBarData: BarAreaData(show: false),
            ),
        ];

        // Avg buy dashed line
        if (widget.metrics.avgBuy != null) {
          bars.insert(
            1,
            LineChartBarData(
              spots: [
                FlSpot(spots.first.x, widget.metrics.avgBuy!),
                FlSpot(spots.last.x, widget.metrics.avgBuy!),
              ],
              isCurved: false,
              color: _soft.withValues(alpha: 0.55),
              barWidth: 1.2,
              dashArray: [6, 4],
              dotData: const FlDotData(show: false),
              belowBarData: BarAreaData(show: false),
            ),
          );
        }

        return LineChart(
          duration: const Duration(milliseconds: 300),
          LineChartData(
            minY: minY - yPad,
            maxY: maxY + yPad,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            titlesData: const FlTitlesData(show: false),
            lineBarsData: bars,
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => widget.isDark
                    ? const Color(0xFF2A2A30)
                    : const Color(0xFF1A1A2E),
                tooltipPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipItems: (touchedSpots) {
                  return touchedSpots.map((s) {
                    if (s.barIndex != 0) return null;
                    final idx = s.spotIndex.clamp(0, pts.length - 1);
                    final t = pts[idx].time;
                    return LineTooltipItem(
                      '${DateFormat('d MMM').format(t)}\n',
                      const TextStyle(
                        color: Colors.white70,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                      children: [
                        TextSpan(
                          text: formatMoney(widget.symbol, s.y),
                          style: TextStyle(
                            color: metalColor,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const TextSpan(
                          text: '/g',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    );
                  }).toList();
                },
              ),
            ),
          ),
        );
      },
    );
  }

  // Fallback: transaction-based chart when live data unavailable
  Widget _buildFallbackChart(Color metalColor) {
    final items = widget.allItems;
    if (items.isEmpty) {
      return Center(
        child: Text('No price data',
            style: TextStyle(fontSize: 12, color: _soft)),
      );
    }
    final pts = <_ChartPoint>[];
    for (int i = 0; i < items.length; i++) {
      final m = items[i];
      final price = m.pricePerGram ??
          (m.weightGrams > 0 ? m.totalAmount / m.weightGrams : null);
      if (price != null && price > 0) {
        pts.add(_ChartPoint(i.toDouble(), price, m.action));
      }
    }
    if (pts.isEmpty) {
      return Center(
          child: Text('No price data',
              style: TextStyle(fontSize: 12, color: _soft)));
    }
    final spots = pts.map((p) => FlSpot(p.x, p.y)).toList();
    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY) * 0.2 + 1;
    return LineChart(
      duration: const Duration(milliseconds: 250),
      LineChartData(
        minY: minY - yPad,
        maxY: maxY + yPad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: spots.length > 2,
            color: metalColor,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, _, __, index) {
                if (index >= pts.length) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: metalColor,
                    strokeWidth: 0,
                    strokeColor: Colors.transparent,
                  );
                }
                final isBuy = pts[index].action == MetalAction.buy;
                return FlDotCirclePainter(
                  radius: 4.5,
                  color: isBuy ? AppColors.income : AppColors.expense,
                  strokeWidth: 1.5,
                  strokeColor: _cardBg,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              color: metalColor.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero card supporting widgets
// ─────────────────────────────────────────────────────────────────────────────

class _LivePulseDot extends StatefulWidget {
  final Color color;
  const _LivePulseDot({required this.color});

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: false);
    _scale = Tween<double>(begin: 1.0, end: 2.2).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _opacity = Tween<double>(begin: 0.7, end: 0.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _ctrl,
            builder: (_, __) => Transform.scale(
              scale: _scale.value,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.color.withValues(alpha: _opacity.value),
                ),
              ),
            ),
          ),
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.color,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetalBadge extends StatelessWidget {
  final MetalType metalType;
  const _MetalBadge({required this.metalType});

  String get _symbol =>
      metalType == MetalType.gold ? 'Au' : 'Ag';

  @override
  Widget build(BuildContext context) {
    final c = metalType.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: metalType == MetalType.gold
                    ? [const Color(0xFFFFE97A), const Color(0xFFD4AF37)]
                    : [const Color(0xFFECF2F8), const Color(0xFF9BA5B0)],
              ),
            ),
            child: Center(
              child: Text(
                _symbol,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w900,
                  color: metalType == MetalType.gold
                      ? const Color(0xFF6A4E10)
                      : const Color(0xFF2A3A4A),
                ),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            metalType.label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: c,
            ),
          ),
        ],
      ),
    );
  }
}

class _LastPriceChip extends StatelessWidget {
  final double price;
  final String symbol;
  final bool isLive;
  const _LastPriceChip({
    required this.price,
    required this.symbol,
    this.isLive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isLive ? AppColors.income : const Color(0xFF9BA5B0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 5),
        Text(
          '${isLive ? 'LIVE' : 'LAST'} · ${formatMoney(symbol, price)}/g',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final Color soft;
  const _LegendDot({required this.color, required this.label, required this.soft});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: soft,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _LegendDash extends StatelessWidget {
  final Color color;
  final String label;
  final Color soft;
  const _LegendDash({required this.color, required this.label, required this.soft});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 14,
          child: CustomPaint(
            size: const Size(14, 2),
            painter: _DashPainter(color: color),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: soft,
            letterSpacing: 0.4,
          ),
        ),
      ],
    );
  }
}

class _DashPainter extends CustomPainter {
  final Color color;
  const _DashPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, size.height / 2), Offset(x + 4, size.height / 2), paint);
      x += 7;
    }
  }

  @override
  bool shouldRepaint(_DashPainter o) => o.color != color;
}

class _StatCol extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color labelColor;

  const _StatCol({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: labelColor,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CalcResult extends StatelessWidget {
  final String value;
  final Color color;
  final Color soft;

  const _CalcResult({
    super.key,
    required this.value,
    required this.color,
    required this.soft,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '≈',
          style: TextStyle(
            fontSize: 10,
            color: soft,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom action buttons
// ─────────────────────────────────────────────────────────────────────────────

class _IconActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final BrandColors brand;

  const _IconActionBtn({
    required this.icon,
    required this.onTap,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(16),
          boxShadow: AppShadows.soft,
        ),
        child: Icon(icon, size: 20, color: brand.ink),
      ),
    );
  }
}

class _OutlineBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final BrandColors brand;

  const _OutlineBtn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    required this.brand,
  });

  @override
  State<_OutlineBtn> createState() => _OutlineBtnState();
}

class _OutlineBtnState extends State<_OutlineBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sc;

  @override
  void initState() {
    super.initState();
    _sc = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _sc.reverse(),
      onTapUp: (_) {
        _sc.forward();
        widget.onTap();
      },
      onTapCancel: () => _sc.forward(),
      child: ScaleTransition(
        scale: _sc,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: widget.brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.field),
            boxShadow: AppShadows.soft,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 15, color: widget.color),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: widget.color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FilledBtn extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _FilledBtn({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  State<_FilledBtn> createState() => _FilledBtnState();
}

class _FilledBtnState extends State<_FilledBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _sc;

  @override
  void initState() {
    super.initState();
    _sc = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.95,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _sc.reverse(),
      onTapUp: (_) {
        _sc.forward();
        widget.onTap();
      },
      onTapCancel: () => _sc.forward(),
      child: ScaleTransition(
        scale: _sc,
        child: Container(
          height: 52,
          decoration: BoxDecoration(
            color: const Color(0xFF1D6AE5),
            borderRadius: BorderRadius.circular(AppRadius.field),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1D6AE5).withValues(alpha: 0.32),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(widget.icon, size: 16, color: Colors.white),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction list
// ─────────────────────────────────────────────────────────────────────────────

class _TxGroup extends StatelessWidget {
  final List<PreciousMetal> items;
  final String symbol;
  final BrandColors brand;
  final ValueChanged<PreciousMetal> onTap;

  const _TxGroup({
    required this.items,
    required this.symbol,
    required this.brand,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.soft,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Column(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.only(left: 70),
                  child: Container(height: 0.5, color: brand.divider),
                ),
              _TxRow(
                metal: items[i],
                symbol: symbol,
                brand: brand,
                onTap: () => onTap(items[i]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TxRow extends StatelessWidget {
  final PreciousMetal metal;
  final String symbol;
  final BrandColors brand;
  final VoidCallback onTap;

  const _TxRow({
    required this.metal,
    required this.symbol,
    required this.brand,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isBuy = metal.action == MetalAction.buy;
    final ac = isBuy ? AppColors.income : AppColors.expense;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: ac.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Center(
                child: Icon(
                  isBuy
                      ? CupertinoIcons.arrow_down_circle_fill
                      : CupertinoIcons.arrow_up_circle_fill,
                  color: ac,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isBuy ? 'Bought' : 'Sold',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: brand.ink,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: ac.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${metal.weightGrams.toStringAsFixed(2)} g',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ac,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      DateFormat('d MMM yyyy').format(metal.date),
                      if (metal.pricePerGram != null)
                        '${formatMoney(symbol, metal.pricePerGram!)}/g',
                      if (metal.notes != null && metal.notes!.isNotEmpty)
                        metal.notes!,
                    ].join('  ·  '),
                    style: TextStyle(fontSize: 12, color: brand.inkSoft),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isBuy ? '−' : '+'}${formatMoney(symbol, metal.totalAmount)}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: ac,
                  ),
                ),
                const SizedBox(height: 3),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 12,
                  color: brand.inkSoft.withValues(alpha: 0.40),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Swipeable transaction row (used in history sheet)
// ─────────────────────────────────────────────────────────────────────────────

class _SwipeTxRow extends StatefulWidget {
  final PreciousMetal metal;
  final String symbol;
  final BrandColors brand;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final Future<void> Function()? onDelete;
  final VoidCallback? onCopy;

  const _SwipeTxRow({
    required this.metal,
    required this.symbol,
    required this.brand,
    required this.onTap,
    this.onEdit,
    this.onDelete,
    this.onCopy,
  });

  @override
  State<_SwipeTxRow> createState() => _SwipeTxRowState();
}

class _SwipeTxRowState extends State<_SwipeTxRow>
    with SingleTickerProviderStateMixin {
  static const double _rightActionWidth = 140.0;
  static const double _leftActionWidth = 80.0;
  static const double _snapThreshold = 60.0;

  late AnimationController _controller;
  late Animation<double> _offsetAnimation;
  double _dragOffset = 0.0;
  int _direction = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _offsetAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragStart(DragStartDetails _) {
    _controller.stop();
    _dragOffset = _offsetAnimation.value;
    _direction = 0;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    if (_direction == 0) {
      if (d.delta.dx < 0) _direction = -1;
      if (d.delta.dx > 0) _direction = 1;
    }
    setState(() {
      _dragOffset += d.delta.dx;
      if (_direction == -1) {
        _dragOffset = _dragOffset.clamp(-_rightActionWidth, 0.0);
      } else {
        _dragOffset = _dragOffset.clamp(0.0, _leftActionWidth);
      }
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    final shouldOpen = _dragOffset.abs() > _snapThreshold || velocity.abs() > 300;
    if (_direction == -1) {
      if (shouldOpen && (widget.onDelete != null || widget.onEdit != null)) {
        _animateTo(-_rightActionWidth);
      } else {
        _animateTo(0);
      }
    } else if (_direction == 1) {
      if (shouldOpen && widget.onCopy != null) {
        _animateTo(0);
        HapticFeedback.mediumImpact();
        widget.onCopy!();
      } else {
        _animateTo(0);
      }
    } else {
      _animateTo(0);
    }
  }

  void _animateTo(double target) {
    _offsetAnimation = Tween<double>(begin: _dragOffset, end: target).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward(from: 0);
    setState(() => _dragOffset = target);
  }

  void _close() => _animateTo(0);

  Future<void> _confirmDelete() async {
    HapticFeedback.mediumImpact();
    _close();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    final isBuy = widget.metal.action == MetalAction.buy;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Record'),
        content: Text(
          'Delete this ${isBuy ? 'purchase' : 'sale'} record permanently?',
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      HapticFeedback.heavyImpact();
      await widget.onDelete!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSwipeLeft = widget.onDelete != null || widget.onEdit != null;
    final canSwipeRight = widget.onCopy != null;

    final content = _TxRow(
      metal: widget.metal,
      symbol: widget.symbol,
      brand: widget.brand,
      onTap: () {
        if (_dragOffset != 0) {
          _close();
          return;
        }
        HapticFeedback.selectionClick();
        widget.onTap();
      },
    );

    if (!canSwipeLeft && !canSwipeRight) return content;

    return GestureDetector(
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (ctx, _) {
          final offset =
              _controller.isAnimating ? _offsetAnimation.value : _dragOffset;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (canSwipeRight)
                Positioned(
                  left: 8,
                  top: 0,
                  bottom: 0,
                  width: _leftActionWidth - 8,
                  child: Opacity(
                    opacity: (offset / _leftActionWidth).clamp(0.0, 1.0),
                    child: _ActionButton(
                      color: AppColors.income,
                      icon: CupertinoIcons.doc_on_doc,
                      label: 'Copy',
                      onTap: () {
                        _close();
                        widget.onCopy!();
                      },
                    ),
                  ),
                ),
              if (canSwipeLeft)
                Positioned(
                  right: 8,
                  top: 0,
                  bottom: 0,
                  width: _rightActionWidth - 8,
                  child: Opacity(
                    opacity: (-offset / _rightActionWidth).clamp(0.0, 1.0),
                    child: Row(
                      children: [
                        if (widget.onEdit != null)
                          Expanded(
                            child: _ActionButton(
                              color: const Color(0xFF5B8AF4),
                              icon: CupertinoIcons.pencil,
                              label: 'Edit',
                              onTap: () {
                                _close();
                                widget.onEdit!();
                              },
                            ),
                          ),
                        if (widget.onEdit != null && widget.onDelete != null)
                          const SizedBox(width: 6),
                        if (widget.onDelete != null)
                          Expanded(
                            child: _ActionButton(
                              color: AppColors.expense,
                              icon: CupertinoIcons.delete,
                              label: 'Delete',
                              onTap: _confirmDelete,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              Transform.translate(
                offset: Offset(offset, 0),
                child: content,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionButton({
    required this.color,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 20),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  final MetalType metalType;
  final VoidCallback onBuy;
  final BrandColors brand;

  const _Empty({
    required this.metalType,
    required this.onBuy,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    final c = metalType.primaryColor;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: AppShadows.soft,
      ),
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Center(
              child: CustomPaint(
                size: const Size(34, 20),
                painter: _IngotPainter(metal: metalType),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No ${metalType.label} transactions',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: brand.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Record your first purchase to start\ntracking your ${metalType.label.toLowerCase()} holdings.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: brand.inkSoft,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 20),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
            color: c,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            onPressed: onBuy,
            child: Text(
              'Buy ${metalType.label}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: metalType == MetalType.gold
                    ? const Color(0xFF4A2E00)
                    : Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// History sheet
// ─────────────────────────────────────────────────────────────────────────────

class _HistorySheet extends StatelessWidget {
  final MetalType metalType;
  final List<PreciousMetal> items;
  final String symbol;
  final ValueChanged<PreciousMetal> onEdit;
  final Future<void> Function(PreciousMetal)? onDelete;
  final ValueChanged<PreciousMetal>? onCopy;

  const _HistorySheet({
    required this.metalType,
    required this.items,
    required this.symbol,
    required this.onEdit,
    this.onDelete,
    this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final c = metalType.primaryColor;

    return Container(
      height: MediaQuery.of(context).size.height * 0.80,
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: brand.inkSoft.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 16, 0),
            child: Row(
              children: [
                _MetalBadge(metalType: metalType),
                const SizedBox(width: 10),
                Text(
                  'History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: brand.ink,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: c.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${items.length}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // List
          Expanded(
            child: items.isEmpty
                ? Center(
                    child: Text(
                      'No transactions yet.',
                      style: TextStyle(fontSize: 14, color: brand.inkSoft),
                    ),
                  )
                : ListView.separated(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + bottomPad),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => Padding(
                      padding: const EdgeInsets.only(left: 70),
                      child: Container(height: 0.5, color: brand.divider),
                    ),
                    itemBuilder: (_, i) => ClipRRect(
                      borderRadius: i == 0
                          ? const BorderRadius.vertical(
                              top: Radius.circular(16),
                            )
                          : i == items.length - 1
                          ? const BorderRadius.vertical(
                              bottom: Radius.circular(16),
                            )
                          : BorderRadius.zero,
                      child: ColoredBox(
                        color: brand.surface,
                        child: _SwipeTxRow(
                          metal: items[i],
                          symbol: symbol,
                          brand: brand,
                          onTap: () => onEdit(items[i]),
                          onEdit: onDelete != null || onCopy != null
                              ? () => onEdit(items[i])
                              : null,
                          onDelete: onDelete != null
                              ? () => onDelete!(items[i])
                              : null,
                          onCopy: onCopy != null
                              ? () => onCopy!(items[i])
                              : null,
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ingot painter (small, used in _Empty + _AddMetalSheet)
// ─────────────────────────────────────────────────────────────────────────────

class _IngotPainter extends CustomPainter {
  final MetalType metal;
  const _IngotPainter({required this.metal});

  bool get _gold => metal == MetalType.gold;

  @override
  void paint(Canvas canvas, Size size) {
    final light = _gold ? const Color(0xFFFFE97A) : const Color(0xFFECF2F8);
    final mid = _gold ? const Color(0xFFD4AF37) : const Color(0xFFB8C8D8);
    final dark = _gold ? const Color(0xFF9A7020) : const Color(0xFF7A8A98);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height * 0.28)),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, mid, dark],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );
    canvas.drawLine(
      Offset(size.width * 0.18, size.height * 0.32),
      Offset(size.width * 0.72, size.height * 0.32),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 0.9
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_IngotPainter o) => o.metal != metal;
}

// ─────────────────────────────────────────────────────────────────────────────
// Add Metal Sheet — modal bottom sheet, new-entry style
// ─────────────────────────────────────────────────────────────────────────────

class _AddMetalSheet extends ConsumerStatefulWidget {
  final MetalType initialMetal;
  final MetalAction initialAction;
  final PreciousMetal? editMetal;
  final PreciousMetal? copyFrom;

  const _AddMetalSheet({
    required this.initialMetal,
    required this.initialAction,
    this.editMetal,
    this.copyFrom,
  });

  @override
  ConsumerState<_AddMetalSheet> createState() => _AddMetalSheetState();
}

class _AddMetalSheetState extends ConsumerState<_AddMetalSheet> {
  late MetalType _metalType;
  late MetalAction _action;
  late DateTime _date;
  String? _accountId;
  bool _saving = false;
  bool _saveSuccess = false;
  bool _manualTotal = false;
  bool _togglePressed = false;

  final _weightCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final _weightFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _totalFocus = FocusNode();

  bool get _isEdit => widget.editMetal != null;

  static String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    final s = v.toStringAsFixed(6);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  @override
  void initState() {
    super.initState();
    _metalType = widget.initialMetal;
    _action = widget.initialAction;
    _date = widget.editMetal?.date ?? DateTime.now();
    _accountId = widget.editMetal?.accountId;

    final m = widget.editMetal ?? widget.copyFrom;
    if (m != null) {
      if (m.weightGrams > 0) _weightCtrl.text = _fmt(m.weightGrams);
      if (m.pricePerGram != null) _priceCtrl.text = _fmt(m.pricePerGram!);
      if (m.totalAmount > 0) _totalCtrl.text = _fmt(m.totalAmount);
      if (widget.editMetal != null) _notesCtrl.text = m.notes ?? '';
    }
    _weightCtrl.addListener(_autoCalc);
    _priceCtrl.addListener(_autoCalc);
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _priceCtrl.dispose();
    _totalCtrl.dispose();
    _notesCtrl.dispose();
    _weightFocus.dispose();
    _priceFocus.dispose();
    _totalFocus.dispose();
    super.dispose();
  }

  void _selectAll(TextEditingController c) {
    if (c.text.isEmpty) return;
    c.selection = TextSelection(
      baseOffset: 0,
      extentOffset: c.text.length,
    );
  }

  void _autoCalc() {
    if (_manualTotal) return;
    final w = double.tryParse(_weightCtrl.text);
    final p = double.tryParse(_priceCtrl.text);
    if (w != null && p != null) {
      _totalCtrl.text = (w * p).toStringAsFixed(2);
    } else if (_weightCtrl.text.isEmpty || _priceCtrl.text.isEmpty) {
      _totalCtrl.text = '';
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final weight = double.tryParse(_weightCtrl.text);
    final total = double.tryParse(_totalCtrl.text);
    if (weight == null || weight <= 0) {
      AppToast.show(context, 'Enter a valid weight', type: AppToastType.error);
      return;
    }
    if (total == null || total <= 0) {
      AppToast.show(context, 'Enter a valid amount', type: AppToastType.error);
      return;
    }
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(preciousMetalRepositoryProvider);
      final now = DateTime.now();
      final pricePerGram = double.tryParse(_priceCtrl.text);
      final notes =
          _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

      if (_isEdit) {
        final updated = widget.editMetal!.copyWith(
          metalType: _metalType,
          action: _action,
          weightGrams: weight,
          pricePerGram: pricePerGram,
          totalAmount: total,
          date: _date,
          notes: notes,
          accountId: _accountId,
        );
        await repo.update(user.uid, updated);
        _bgSyncUpdate(user.uid, updated);
        if (mounted) {
          setState(() { _saving = false; _saveSuccess = true; });
          await Future.delayed(const Duration(milliseconds: 450));
          if (mounted) Navigator.pop(context);
        }
      } else {
        final newM = PreciousMetal(
          id: now.microsecondsSinceEpoch.toString(),
          metalType: _metalType,
          action: _action,
          weightGrams: weight,
          pricePerGram: pricePerGram,
          totalAmount: total,
          date: _date,
          notes: notes,
          accountId: _accountId,
          createdAt: now,
        );
        await repo.add(user.uid, newM);
        _bgSyncAdd(user.uid, newM);
        if (mounted) {
          setState(() { _saving = false; _saveSuccess = true; });
          await Future.delayed(const Duration(milliseconds: 650));
          if (mounted) Navigator.pop(context);
        }
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, _isEdit ? 'Update failed' : 'Save failed', type: AppToastType.error);
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Record'),
        content: const Text('This record will be permanently deleted.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final id = widget.editMetal!.id;
      await ref.read(preciousMetalRepositoryProvider).delete(user.uid, id);
      _bgSyncDelete(user.uid, id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Delete failed', type: AppToastType.error);
        setState(() => _saving = false);
      }
    }
  }

  void _bgSyncAdd(String uid, PreciousMetal m) {
    if (storageMode != StorageMode.firebase) return;
    FirebasePreciousMetalRepository().add(uid, m).catchError((_) {});
  }

  void _bgSyncUpdate(String uid, PreciousMetal m) {
    if (storageMode != StorageMode.firebase) return;
    FirebasePreciousMetalRepository().update(uid, m).catchError((_) {});
  }

  void _bgSyncDelete(String uid, String id) {
    if (storageMode != StorageMode.firebase) return;
    FirebasePreciousMetalRepository().delete(uid, id).catchError((_) {});
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    DateTime temp = _date;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) {
        final brand = ctx.brand;
        return Container(
          height: 300,
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(20),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: brand.inkSoft.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: temp,
                  maximumDate: DateTime.now().add(const Duration(days: 1)),
                  minimumDate: DateTime(2000),
                  onDateTimeChanged: (d) => temp = d,
                ),
              ),
              CupertinoButton(
                child: Text(
                  'Done',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _metalType.primaryColor,
                  ),
                ),
                onPressed: () {
                  setState(() => _date = temp);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Color get _cardInk =>
      _metalType == MetalType.gold
          ? const Color(0xFF4A2E00)
          : const Color(0xFF1C2B3A);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accounts =
        ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final bottomPad = MediaQuery.of(context).padding.bottom;
    final metalColor = _metalType.primaryColor;
    final cardBg = isDark
        ? metalColor.withValues(alpha: 0.12)
        : _metalType.bgColor;
    final textInk = isDark ? metalColor : _cardInk;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.92,
        ),
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: brand.inkSoft.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 12, 0),
            child: Row(
              children: [
                Text(
                  _isEdit ? 'Edit Record' : 'New Transaction',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: brand.ink,
                  ),
                ),
                const Spacer(),
                if (_isEdit)
                  GestureDetector(
                    onTap: _saving ? null : _delete,
                    child: Container(
                      width: 32,
                      height: 32,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: AppColors.blush,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        CupertinoIcons.delete,
                        size: 15,
                        color: AppColors.expense,
                      ),
                    ),
                  ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: brand.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      CupertinoIcons.xmark,
                      size: 15,
                      color: brand.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable form
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                children: [
                  // ── Colored top card ─────────────────────────────────
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Icon + title row
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: metalColor.withValues(
                                  alpha: isDark ? 0.22 : 0.18,
                                ),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Center(
                                child: CustomPaint(
                                  size: const Size(28, 17),
                                  painter: _IngotPainter(metal: _metalType),
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _action == MetalAction.buy
                                        ? 'Buy ${_metalType.label}'
                                        : 'Sell ${_metalType.label}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      color: textInk,
                                    ),
                                  ),
                                  Text(
                                    _action == MetalAction.buy
                                        ? 'Record a purchase'
                                        : 'Record a sale',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: metalColor.withValues(
                                        alpha: 0.75,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),

                        // Large total amount
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.07)
                                : Colors.white.withValues(alpha: 0.60),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              symbol,
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: textInk.withValues(alpha: 0.45),
                              ),
                            ),
                            const SizedBox(width: 3),
                            Expanded(
                              child: TextField(
                                controller: _totalCtrl,
                                focusNode: _totalFocus,
                                autofocus: false,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                  decimal: true,
                                ),
                                onTap: () {
                                  _selectAll(_totalCtrl);
                                  setState(() => _manualTotal = true);
                                },
                                onChanged: (_) =>
                                    setState(() => _manualTotal = true),
                                style: TextStyle(
                                  fontSize: 44,
                                  fontWeight: FontWeight.w900,
                                  color: textInk.withValues(alpha: 0.80),
                                  height: 1.0,
                                ),
                                decoration: InputDecoration(
                                  hintText: '0.00',
                                  hintStyle: TextStyle(
                                    fontSize: 44,
                                    fontWeight: FontWeight.w900,
                                    color: textInk.withValues(alpha: 0.22),
                                    height: 1.0,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(vertical: 4),
                                  isDense: true,
                                ),
                              ),
                            ),
                          ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        Text(
                          'WEIGHT & PRICE',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: metalColor.withValues(alpha: 0.65),
                            letterSpacing: 0.7,
                          ),
                        ),
                        const SizedBox(height: 8),

                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            color: metalColor.withValues(
                              alpha: isDark ? 0.20 : 0.16,
                            ),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: IntrinsicHeight(
                            child: Row(
                              children: [
                                // Weight
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Weight',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: metalColor.withValues(
                                            alpha: 0.70,
                                          ),
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: _weightCtrl,
                                        focusNode: _weightFocus,
                                        autofocus: false,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        textInputAction: TextInputAction.next,
                                        onTap: () => _selectAll(_weightCtrl),
                                        onSubmitted: (_) => FocusScope.of(
                                          context,
                                        ).requestFocus(_priceFocus),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? metalColor : _cardInk,
                                        ),
                                        decoration: InputDecoration(
                                          hintText: '0.00',
                                          hintStyle: TextStyle(
                                            fontSize: 16,
                                            color: (isDark
                                                    ? metalColor
                                                    : _cardInk)
                                                .withValues(alpha: 0.35),
                                          ),
                                          suffixText: 'g',
                                          suffixStyle: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: metalColor.withValues(
                                                alpha: 0.65),
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          isDense: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // Vertical divider
                                Container(
                                  width: 0.5,
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                  ),
                                  color: metalColor.withValues(alpha: 0.35),
                                ),
                                // Price / g
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Price / g',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: metalColor.withValues(
                                            alpha: 0.70,
                                          ),
                                          letterSpacing: 0.3,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      TextField(
                                        controller: _priceCtrl,
                                        focusNode: _priceFocus,
                                        autofocus: false,
                                        keyboardType: const TextInputType
                                            .numberWithOptions(decimal: true),
                                        textInputAction: TextInputAction.done,
                                        onTap: () => _selectAll(_priceCtrl),
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: isDark ? metalColor : _cardInk,
                                        ),
                                        decoration: InputDecoration(
                                          prefixText: '$symbol ',
                                          prefixStyle: TextStyle(
                                            fontSize: 14,
                                            color: (isDark
                                                    ? metalColor
                                                    : _cardInk)
                                                .withValues(alpha: 0.50),
                                          ),
                                          hintText: 'Optional',
                                          hintStyle: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w400,
                                            color: (isDark
                                                    ? metalColor
                                                    : _cardInk)
                                                .withValues(alpha: 0.35),
                                          ),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          enabledBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          focusedBorder: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12),
                                            borderSide: BorderSide.none,
                                          ),
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          isDense: true,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),

                        // Metal dot label
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: metalColor,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              _metalType.label,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: textInk,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Details card ─────────────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: AppShadows.soft,
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Column(
                        children: [
                          if (accounts.isNotEmpty) ...[
                            _SheetAccountRow(
                              accounts: accounts,
                              selectedId: _accountId,
                              brand: brand,
                              onChanged: (id) =>
                                  setState(() => _accountId = id),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(left: 52),
                              child: Container(
                                height: 0.5,
                                color: brand.divider,
                              ),
                            ),
                          ],
                          _SheetDateRow(
                            date: _date,
                            brand: brand,
                            metalColor: metalColor,
                            onTap: _pickDate,
                          ),
                          Padding(
                            padding: const EdgeInsets.only(left: 52),
                            child: Container(
                              height: 0.5,
                              color: brand.divider,
                            ),
                          ),
                          _SheetNoteRow(
                            controller: _notesCtrl,
                            brand: brand,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),

          // ── Bottom bar ────────────────────────────────────────────────
          Container(
            color: brand.background,
            padding:
                EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomPad),
            child: Row(
              children: [
                // Buy / Sell toggle (add mode only)
                if (!_isEdit) GestureDetector(
                  onTapDown: (_) => setState(() => _togglePressed = true),
                  onTapUp: (_) {
                    setState(() {
                      _togglePressed = false;
                      _action = _action == MetalAction.buy
                          ? MetalAction.sell
                          : MetalAction.buy;
                    });
                  },
                  onTapCancel: () => setState(() => _togglePressed = false),
                  child: AnimatedScale(
                    scale: _togglePressed ? 0.90 : 1.0,
                    duration: const Duration(milliseconds: 100),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: (_action == MetalAction.buy
                                ? AppColors.income
                                : AppColors.expense)
                            .withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: (_action == MetalAction.buy
                                  ? AppColors.income
                                  : AppColors.expense)
                              .withValues(alpha: 0.25),
                        ),
                      ),
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, anim) => ScaleTransition(
                            scale: anim,
                            child: child,
                          ),
                          child: Icon(
                            key: ValueKey(_action),
                            _action == MetalAction.buy
                                ? CupertinoIcons.arrow_down_circle_fill
                                : CupertinoIcons.arrow_up_circle_fill,
                            size: 24,
                            color: _action == MetalAction.buy
                                ? AppColors.income
                                : AppColors.expense,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (!_isEdit) const SizedBox(width: 12),

                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 52,
                    decoration: BoxDecoration(
                      color: _saveSuccess
                          ? AppColors.income
                          : (_saving
                              ? metalColor.withValues(alpha: 0.6)
                              : metalColor),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: (_saveSuccess ? AppColors.income : metalColor)
                              .withValues(alpha: 0.30),
                          blurRadius: 14,
                          offset: const Offset(0, 5),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: (_saving || _saveSuccess) ? null : _save,
                        child: Center(
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (child, anim) => ScaleTransition(
                              scale: anim,
                              child: FadeTransition(opacity: anim, child: child),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    key: ValueKey('loading'),
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : _saveSuccess
                                    ? const Icon(
                                        key: ValueKey('success'),
                                        CupertinoIcons.checkmark_alt,
                                        size: 26,
                                        color: Colors.white,
                                      )
                                    : Row(
                                        key: const ValueKey('idle'),
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            CupertinoIcons.checkmark_circle_fill,
                                            size: 18,
                                            color: Colors.white,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            _isEdit
                                                ? 'Save Changes'
                                                : (_action == MetalAction.buy
                                                    ? 'Record Purchase'
                                                    : 'Record Sale'),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Input pill (inside colored add card)
// ─────────────────────────────────────────────────────────────────────────────

class _InputPill extends StatelessWidget {
  final String label;
  final String? prefix;
  final String? suffix;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Color metalColor;
  final bool isDark;
  final Color cardInk;
  final String hint;
  final VoidCallback? onTap;
  final FocusNode? nextFocus;

  const _InputPill({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.metalColor,
    required this.isDark,
    required this.cardInk,
    required this.hint,
    this.prefix,
    this.suffix,
    this.onTap,
    this.nextFocus,
  });

  @override
  Widget build(BuildContext context) {
    final ink = isDark ? metalColor : cardInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: metalColor.withValues(alpha: isDark ? 0.14 : 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: metalColor.withValues(alpha: isDark ? 0.26 : 0.18),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: metalColor.withValues(alpha: 0.70),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              if (prefix != null) ...[
                Text(
                  prefix!,
                  style: TextStyle(
                    fontSize: 14,
                    color: ink.withValues(alpha: 0.50),
                  ),
                ),
                const SizedBox(width: 2),
              ],
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  textInputAction: nextFocus != null
                      ? TextInputAction.next
                      : TextInputAction.done,
                  onTap: onTap,
                  onSubmitted: (_) {
                    if (nextFocus != null) {
                      FocusScope.of(context).requestFocus(nextFocus);
                    }
                  },
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: ink,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: ink.withValues(alpha: 0.32),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: EdgeInsets.zero,
                    isDense: true,
                    suffixText: suffix,
                    suffixStyle: TextStyle(
                      fontSize: 13,
                      color: metalColor.withValues(alpha: 0.65),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet detail rows
// ─────────────────────────────────────────────────────────────────────────────

class _SheetDateRow extends StatelessWidget {
  final DateTime date;
  final BrandColors brand;
  final Color metalColor;
  final VoidCallback onTap;

  const _SheetDateRow({
    required this.date,
    required this.brand,
    required this.metalColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(CupertinoIcons.calendar, size: 18, color: brand.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Date',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  color: brand.ink,
                ),
              ),
            ),
            Text(
              DateFormat('MMM d, yyyy').format(date),
              style: TextStyle(color: brand.inkSoft, fontSize: 15),
            ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_right,
              size: 13,
              color: brand.inkSoft.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetAccountRow extends StatelessWidget {
  final List<Account> accounts;
  final String? selectedId;
  final BrandColors brand;
  final ValueChanged<String?> onChanged;

  const _SheetAccountRow({
    required this.accounts,
    required this.selectedId,
    required this.brand,
    required this.onChanged,
  });

  void _showPicker(BuildContext context) {
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: brand.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Text(
                    'Select Account',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      ListTile(
                        leading: Icon(
                          CupertinoIcons.xmark_circle,
                          color: brand.inkSoft,
                        ),
                        title: Text(
                          'None',
                          style: TextStyle(color: brand.inkSoft),
                        ),
                        trailing: selectedId == null
                            ? Icon(
                                CupertinoIcons.checkmark_alt,
                                color: brand.accentDark,
                              )
                            : null,
                        onTap: () {
                          onChanged(null);
                          Navigator.pop(ctx);
                        },
                      ),
                      ...accounts.map((a) {
                        final isSelected = selectedId == a.id;
                        return ListTile(
                          leading: Icon(
                            _iconForAccountType(a.type),
                            color: _accentForAccountType(a.type),
                          ),
                          title: Text(
                            a.name,
                            style: TextStyle(
                              color: brand.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            a.type.label,
                            style: TextStyle(color: brand.inkSoft),
                          ),
                          trailing: isSelected
                              ? Icon(
                                  CupertinoIcons.checkmark_alt,
                                  color: brand.accentDark,
                                )
                              : null,
                          onTap: () {
                            onChanged(a.id);
                            Navigator.pop(ctx);
                          },
                        );
                      }),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = accounts.where((a) => a.id == selectedId).firstOrNull;
    return InkWell(
      onTap: () => _showPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              selected != null
                  ? _iconForAccountType(selected.type)
                  : CupertinoIcons.creditcard,
              size: 18,
              color: selected != null
                  ? _accentForAccountType(selected.type)
                  : brand.inkSoft,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Account',
                style: TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                  color: brand.ink,
                ),
              ),
            ),
            Text(
              selected?.name ?? 'None',
              style: TextStyle(color: brand.inkSoft, fontSize: 15),
            ),
            const SizedBox(width: 4),
            Icon(
              CupertinoIcons.chevron_right,
              size: 13,
              color: brand.inkSoft.withValues(alpha: 0.55),
            ),
          ],
        ),
      ),
    );
  }
}

class _SheetNoteRow extends StatelessWidget {
  final TextEditingController controller;
  final BrandColors brand;

  const _SheetNoteRow({required this.controller, required this.brand});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Icon(
              CupertinoIcons.doc_text,
              size: 18,
              color: brand.inkSoft,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              style: TextStyle(fontSize: 15, color: brand.ink),
              decoration: InputDecoration(
                hintText: 'Note (optional)',
                hintStyle: TextStyle(
                  fontSize: 15,
                  color: brand.inkSoft.withValues(alpha: 0.45),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
