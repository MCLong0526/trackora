import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
import 'add_edit_metal_screen.dart';

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
  const _SpotData({required this.goldPerGram, required this.silverPerGram});
  double forMetal(MetalType m) =>
      m == MetalType.gold ? goldPerGram : silverPerGram;
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
    );
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

  static const _metals = [MetalType.gold, MetalType.silver];
  MetalType get _active => _metals[_tab];

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
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
      ),
    );
  }

  Future<void> _openEdit(PreciousMetal metal) async {
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
    await Navigator.push<dynamic>(
      context,
      CupertinoPageRoute(builder: (_) => AddEditMetalScreen(metal: metal)),
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
    final spotData = spotAsync.valueOrNull;

    final metricsMap = _calcMetrics(metals);
    final filtered = metals
        .where((m) => m.metalType == _active)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

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
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Hero cards (PageView — swipe Gold ↔ Silver) ───────────────
            SliverToBoxAdapter(
              child: SizedBox(
                height: 560,
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
                        livePrice: spotData?.forMetal(m),
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

class _HeroCard extends StatefulWidget {
  final MetalType metalType;
  final _Metrics metrics;
  final String symbol;
  final bool isDark;
  final List<PreciousMetal> allItems;
  final double? livePrice;

  const _HeroCard({
    super.key,
    required this.metalType,
    required this.metrics,
    required this.symbol,
    required this.isDark,
    required this.allItems,
    this.livePrice,
  });

  @override
  State<_HeroCard> createState() => _HeroCardState();
}

class _HeroCardState extends State<_HeroCard> {
  String _range = '1M';
  int? _touchedIndex;

  static const _ranges = ['1D', '1W', '1M', '3M', '1Y', 'ALL'];

  List<PreciousMetal> get _filtered {
    if (_range == 'ALL') return widget.allItems;
    final now = DateTime.now();
    final days = {'1D': 1, '1W': 7, '1M': 30, '3M': 90, '1Y': 365}[_range]!;
    final cutoff = now.subtract(Duration(days: days));
    return widget.allItems.where((m) => m.date.isAfter(cutoff)).toList();
  }

  List<_ChartPoint> get _chartPoints {
    final items = _filtered;
    final result = <_ChartPoint>[];
    for (int i = 0; i < items.length; i++) {
      final m = items[i];
      final price = m.pricePerGram ??
          (m.weightGrams > 0 ? m.totalAmount / m.weightGrams : null);
      if (price != null && price > 0) {
        result.add(_ChartPoint(i.toDouble(), price, m.action));
      }
    }
    return result;
  }

  Color get _cardBg => widget.isDark
      ? const Color(0xFF1B1B20)
      : Colors.white;

  Color get _ink => widget.isDark
      ? const Color(0xFFF2F2F4)
      : const Color(0xFF0F1020);

  Color get _soft => widget.isDark
      ? const Color(0xFFA1A1A6)
      : const Color(0xFF7A7A8E);

  Color get _divider => widget.isDark
      ? const Color(0xFF2A2A30)
      : const Color(0xFFEAEAEC);

  @override
  Widget build(BuildContext context) {
    final metalColor = widget.metalType.primaryColor;
    final metrics = widget.metrics;
    final displayPrice = widget.livePrice ?? metrics.latestPrice;
    final estValue = (metrics.holdGrams > 0 && displayPrice != null)
        ? metrics.holdGrams * displayPrice
        : null;
    final gainLoss = (estValue != null && metrics.buyAmount > 0)
        ? estValue - metrics.buyAmount
        : null;
    final gainPct = (gainLoss != null && metrics.buyAmount > 0)
        ? gainLoss / metrics.buyAmount * 100
        : null;
    final hasEst = estValue != null;
    final gainPositive = (gainLoss ?? 0) >= 0;
    final gainColor = gainPositive ? AppColors.income : AppColors.expense;
    final gainBg = gainPositive
        ? AppColors.income.withValues(alpha: 0.12)
        : AppColors.expense.withValues(alpha: 0.12);

    return SizedBox.expand(
      child: Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: widget.isDark ? 0.30 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [
            // ── Row 1: metal badge + last price ─────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _MetalBadge(metalType: widget.metalType),
                if (displayPrice != null)
                  _LastPriceChip(
                    price: displayPrice,
                    symbol: widget.symbol,
                    isLive: widget.livePrice != null,
                  ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Row 2: holdings (left) + est.value + gain (right) ────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Holdings
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Holdings',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _soft,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _grams(metrics.holdGrams),
                          style: TextStyle(
                            fontSize: 42,
                            fontWeight: FontWeight.w900,
                            color: _ink,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'g',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: _soft,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                // Est. value + gain badge
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (gainPct != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: gainBg,
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
                      hasEst
                          ? formatMoney(widget.symbol, estValue)
                          : '—',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    Text(
                      'est. value',
                      style: TextStyle(fontSize: 11, color: _soft),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Chart ────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: _buildChart(metalColor),
              ),
            ),
            const SizedBox(height: 8),

            // ── Legend + "Tap markers" hint ───────────────────────────────
            Row(
              children: [
                _LegendDot(
                  color: AppColors.income,
                  label: 'BUY',
                  soft: _soft,
                ),
                const SizedBox(width: 12),
                _LegendDot(
                  color: AppColors.expense,
                  label: 'SELL',
                  soft: _soft,
                ),
                const SizedBox(width: 12),
                _LegendDash(
                  color: _soft.withValues(alpha: 0.55),
                  label: 'AVG',
                  soft: _soft,
                ),
                const Spacer(),
                Text(
                  'Tap markers for details',
                  style: TextStyle(fontSize: 10, color: _soft),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // ── Time range selector ───────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: _ranges.map((r) {
                final active = r == _range;
                return GestureDetector(
                  onTap: () => setState(() => _range = r),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
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
            const SizedBox(height: 14),

            // ── Stats row ─────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.only(top: 12),
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
                      value: hasEst
                          ? formatMoney(widget.symbol, estValue)
                          : '—',
                      valueColor: _ink,
                      labelColor: _soft,
                    ),
                  ),
                  Container(
                    width: 0.5,
                    height: 36,
                    color: _divider,
                  ),
                  Expanded(
                    child: _StatCol(
                      label: 'AVG BUY',
                      value: metrics.avgBuy != null
                          ? '${formatMoney(widget.symbol, metrics.avgBuy!)}/g'
                          : '—',
                      valueColor: _ink,
                      labelColor: _soft,
                    ),
                  ),
                  Container(
                    width: 0.5,
                    height: 36,
                    color: _divider,
                  ),
                  Expanded(
                    child: _StatCol(
                      label: 'GAIN / LOSS',
                      value: gainLoss != null
                          ? '${gainPositive ? '+' : ''}${formatMoney(widget.symbol, gainLoss)}'
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

  Widget _buildChart(Color metalColor) {
    final points = _chartPoints;
    if (points.isEmpty) {
      return Center(
        child: Text(
          'No price data',
          style: TextStyle(fontSize: 12, color: _soft),
        ),
      );
    }

    final spots = points.map((p) => FlSpot(p.x, p.y)).toList();
    final avgBuy = widget.metrics.avgBuy;

    final minY = spots.map((s) => s.y).reduce((a, b) => a < b ? a : b);
    final maxY = spots.map((s) => s.y).reduce((a, b) => a > b ? a : b);
    final yPad = (maxY - minY) * 0.2 + 1;

    final priceBar = LineChartBarData(
      spots: spots,
      isCurved: spots.length > 2,
      color: metalColor,
      barWidth: 2,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        getDotPainter: (spot, _, __, index) {
          if (index >= points.length) {
            return FlDotCirclePainter(
              radius: 4,
              color: metalColor,
              strokeWidth: 0,
              strokeColor: Colors.transparent,
            );
          }
          final isBuy = points[index].action == MetalAction.buy;
          final isTouch = index == _touchedIndex;
          return FlDotCirclePainter(
            radius: isTouch ? 6 : 4.5,
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
    );

    final bars = <LineChartBarData>[priceBar];

    // Avg buy dashed line
    if (avgBuy != null && spots.length >= 1) {
      bars.add(
        LineChartBarData(
          spots: [FlSpot(spots.first.x, avgBuy), FlSpot(spots.last.x, avgBuy)],
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
      duration: const Duration(milliseconds: 250),
      LineChartData(
        minY: minY - yPad,
        maxY: maxY + yPad,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineBarsData: bars,
        lineTouchData: LineTouchData(
          touchCallback: (event, response) {
            setState(() {
              if (response?.lineBarSpots == null ||
                  !event.isInterestedForInteractions) {
                _touchedIndex = null;
              } else {
                _touchedIndex = response!.lineBarSpots!.first.spotIndex;
              }
            });
          },
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                widget.isDark ? const Color(0xFF2A2A30) : const Color(0xFF1A1A2E),
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 6,
            ),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => spots.map((s) {
              final i = s.spotIndex;
              if (i >= points.length) return null;
              final item = _filtered[i];
              final isBuy = item.action == MetalAction.buy;
              return LineTooltipItem(
                '${isBuy ? 'Buy' : 'Sell'} · ${DateFormat('d MMM').format(item.date)}\n',
                const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
                children: [
                  TextSpan(
                    text:
                        '${formatMoney(widget.symbol, s.y)}/g',
                    style: TextStyle(
                      color: isBuy ? AppColors.income : AppColors.expense,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero card supporting widgets
// ─────────────────────────────────────────────────────────────────────────────

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

  const _HistorySheet({
    required this.metalType,
    required this.items,
    required this.symbol,
    required this.onEdit,
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
                    itemBuilder: (_, i) => Container(
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: i == 0
                            ? const BorderRadius.vertical(
                                top: Radius.circular(16),
                              )
                            : i == items.length - 1
                            ? const BorderRadius.vertical(
                                bottom: Radius.circular(16),
                              )
                            : null,
                      ),
                      child: _TxRow(
                        metal: items[i],
                        symbol: symbol,
                        brand: brand,
                        onTap: () => onEdit(items[i]),
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

  const _AddMetalSheet({
    required this.initialMetal,
    required this.initialAction,
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

  @override
  void initState() {
    super.initState();
    _metalType = widget.initialMetal;
    _action = widget.initialAction;
    _date = DateTime.now();
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
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Save failed', type: AppToastType.error);
        setState(() => _saving = false);
      }
    }
  }

  void _bgSyncAdd(String uid, PreciousMetal m) {
    if (storageMode != StorageMode.firebase) return;
    FirebasePreciousMetalRepository().add(uid, m).catchError((_) {});
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
                  'New Transaction',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: brand.ink,
                  ),
                ),
                const Spacer(),
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
                        Row(
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
                            borderRadius: BorderRadius.circular(16),
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
                                      const SizedBox(height: 5),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _weightCtrl,
                                              focusNode: _weightFocus,
                                              autofocus: false,
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                decimal: true,
                                              ),
                                              textInputAction:
                                                  TextInputAction.next,
                                              onTap: () =>
                                                  _selectAll(_weightCtrl),
                                              onSubmitted: (_) =>
                                                  FocusScope.of(
                                                context,
                                              ).requestFocus(_priceFocus),
                                              style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                                color: isDark
                                                    ? metalColor
                                                    : _cardInk,
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
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                contentPadding: EdgeInsets.zero,
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                          Text(
                                            'g',
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: metalColor.withValues(
                                                alpha: 0.65,
                                              ),
                                            ),
                                          ),
                                        ],
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
                                      const SizedBox(height: 5),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.baseline,
                                        textBaseline: TextBaseline.alphabetic,
                                        children: [
                                          Text(
                                            symbol,
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: (isDark
                                                      ? metalColor
                                                      : _cardInk)
                                                  .withValues(alpha: 0.50),
                                            ),
                                          ),
                                          const SizedBox(width: 3),
                                          Expanded(
                                            child: TextField(
                                              controller: _priceCtrl,
                                              focusNode: _priceFocus,
                                              autofocus: false,
                                              keyboardType: const TextInputType
                                                  .numberWithOptions(
                                                decimal: true,
                                              ),
                                              textInputAction:
                                                  TextInputAction.done,
                                              onTap: () =>
                                                  _selectAll(_priceCtrl),
                                              style: TextStyle(
                                                fontSize: 17,
                                                fontWeight: FontWeight.w700,
                                                color: isDark
                                                    ? metalColor
                                                    : _cardInk,
                                              ),
                                              decoration: InputDecoration(
                                                hintText: 'Optional',
                                                hintStyle: TextStyle(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w400,
                                                  color: (isDark
                                                          ? metalColor
                                                          : _cardInk)
                                                      .withValues(alpha: 0.35),
                                                ),
                                                border: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                contentPadding: EdgeInsets.zero,
                                                isDense: true,
                                              ),
                                            ),
                                          ),
                                        ],
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
                // Buy / Sell toggle
                GestureDetector(
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
                const SizedBox(width: 12),

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
                                            _action == MetalAction.buy
                                                ? 'Record Purchase'
                                                : 'Record Sale',
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
