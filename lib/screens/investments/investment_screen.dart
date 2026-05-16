import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/precious_metal.dart';
import '../../models/stock_investment.dart';
import '../../services/stock_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../precious_metals/precious_metals_screen.dart';
import '../stocks/stocks_screen.dart';

final _investQuoteProvider = FutureProvider.autoDispose.family<StockQuote?, String>(
  (ref, symbol) async {
    final svc = ref.read(stockServiceProvider);
    return svc.getQuote(symbol, range: '1M');
  },
);

// ── Design tokens ──────────────────────────────────────────────────────────────

const _blue = Color(0xFF0066CC);
const _green = Color(0xFF34C759);
const _goldColor = Color(0xFFD4AF37);
const _silverColor = Color(0xFF9BA5B0);

// ── Investment Overview Screen ─────────────────────────────────────────────────

class InvestmentScreen extends ConsumerStatefulWidget {
  const InvestmentScreen({super.key});

  @override
  ConsumerState<InvestmentScreen> createState() => _InvestmentScreenState();
}

class _InvestmentScreenState extends ConsumerState<InvestmentScreen> {
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metals = ref.watch(preciousMetalsProvider).valueOrNull ?? <PreciousMetal>[];
    final stocks = ref.watch(stockInvestmentsProvider).valueOrNull ?? <StockInvestment>[];
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? 'RM';

    const symToIso = {'RM': 'MYR', '\$': 'USD', 'S\$': 'SGD', '€': 'EUR'};
    final localIso = symToIso[symbol] ?? 'MYR';
    final fxAsync = ref.watch(stockFxRateProvider(localIso));
    final usdToLocal = fxAsync.valueOrNull ?? 4.48;

    // ── Compute totals ────────────────────────────────────────────────────
    double stocksCost = 0;
    for (final s in stocks) {
      if (!s.watchOnly) {
        stocksCost += s.currency == 'MYR' ? s.totalCost : s.totalCost * usdToLocal;
      }
    }

    // Live values from quotes
    double stocksLive = 0;
    bool anyQuoteLoaded = false;
    for (final s in stocks) {
      if (!s.watchOnly) {
        final q = ref.watch(_investQuoteProvider(s.symbol)).valueOrNull;
        if (q != null) {
          anyQuoteLoaded = true;
          final fx = s.currency == 'MYR' ? 1.0 : usdToLocal;
          stocksLive += q.price * s.quantity * fx;
        } else {
          stocksLive += s.currency == 'MYR' ? s.totalCost : s.totalCost * usdToLocal;
        }
      }
    }
    if (!anyQuoteLoaded) stocksLive = stocksCost;

    // Metals: sum of purchase amounts
    double metalsCost = 0;
    for (final m in metals) {
      metalsCost += m.action == MetalAction.buy ? m.totalAmount : -m.totalAmount;
    }
    if (metalsCost < 0) metalsCost = 0;

    final total = stocksCost + metalsCost;
    final liveTotal = stocksLive + metalsCost;
    final allTimeGain = liveTotal - total;
    final allTimeGainPct = total > 0 ? (allTimeGain / total) * 100 : 0.0;

    final stocksPct = liveTotal > 0 ? (stocksLive / liveTotal) : 0.0;
    final metalsPct = liveTotal > 0 ? (metalsCost / liveTotal) : 0.0;

    // Holdings breakdown
    final metalHoldings = _computeMetalHoldings(metals);

    // Asset class count
    final assetClasses = [if (stocks.isNotEmpty) 1, if (metals.isNotEmpty) 1].length;

    return Scaffold(
      backgroundColor: brand.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── App bar ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: brand.surface, shape: BoxShape.circle),
                        child: Icon(CupertinoIcons.chevron_left, size: 16, color: brand.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Hero section ───────────────────────────────────────────────
            if (stocks.isNotEmpty || metals.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // INVESTMENTS · N ASSET CLASSES
                    Text(
                      'INVESTMENTS${assetClasses > 0 ? ' · $assetClasses ASSET CLASS${assetClasses == 1 ? '' : 'ES'}' : ''}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _blue,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Everything you\nown, in one view.',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 20),
                    // Total value (live when quotes available, else cost basis)
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: '$symbol ',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: brand.ink,
                            ),
                          ),
                          TextSpan(
                            text: NumberFormat('#,##0.00').format(liveTotal),
                            style: TextStyle(
                              fontSize: 40,
                              fontWeight: FontWeight.w800,
                              color: brand.ink,
                              letterSpacing: -1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // All-time gain/loss
                    if (anyQuoteLoaded && allTimeGain != 0)
                      Text(
                        '${allTimeGain >= 0 ? '+' : '-'}$symbol ${NumberFormat('#,##0').format(allTimeGain.abs())} (${allTimeGain >= 0 ? '+' : ''}${allTimeGainPct.toStringAsFixed(2)}%) · all-time',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: allTimeGain >= 0 ? _green : const Color(0xFFFF3B30),
                        ),
                      )
                    else
                      Text(
                        'Est. total cost basis · all-time',
                        style: TextStyle(fontSize: 13, color: brand.inkSoft),
                      ),
                  ],
                ),
              ),
            ),

            if (stocks.isNotEmpty || metals.isNotEmpty)
              const SliverToBoxAdapter(child: SizedBox(height: 28)),

            // ── Allocation section ─────────────────────────────────────────
            if (total > 0) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ALLOCATION',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: brand.inkSoft,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Allocation bar
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          height: 8,
                          child: Row(
                            children: [
                              Expanded(
                                flex: (stocksPct * 100).round(),
                                child: Container(color: isDark ? Colors.white : Colors.black),
                              ),
                              Expanded(
                                flex: (metalsPct * 100).round().clamp(1, 100),
                                child: Container(
                                  color: isDark ? const Color(0xFF48484A) : const Color(0xFF8E8E93),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      // Legend
                      Row(
                        children: [
                          if (stocks.isNotEmpty) ...[
                            Container(
                              width: 10, height: 10,
                              decoration: BoxDecoration(
                                color: isDark ? Colors.white : Colors.black,
                                shape: BoxShape.rectangle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Stocks ${(stocksPct * 100).round()}%',
                              style: TextStyle(fontSize: 13, color: brand.ink),
                            ),
                            const SizedBox(width: 20),
                          ],
                          if (metals.isNotEmpty) ...[
                            Container(
                              width: 10, height: 10,
                              decoration: BoxDecoration(
                                color: isDark ? const Color(0xFF48484A) : const Color(0xFF8E8E93),
                                shape: BoxShape.rectangle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Precious metals ${(metalsPct * 100).round()}%',
                              style: TextStyle(fontSize: 13, color: brand.ink),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
            ],

            // ── Asset class cards ──────────────────────────────────────────
            if (stocks.isEmpty && metals.isEmpty)
              SliverFillRemaining(
                child: _EmptyInvestments(
                  onAddStocks: () => Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const StocksScreen()),
                  ),
                  onAddMetals: () => Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const PreciousMetalsScreen()),
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    if (stocks.isNotEmpty)
                      _AssetCard(
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(builder: (_) => const StocksScreen()),
                        ),
                        leading: _StockAvatarRow(stocks: stocks.take(3).toList()),
                        title: 'Stocks',
                        subtitle: '${stocks.length} holding${stocks.length == 1 ? '' : 's'} · ${_marketsLabel(stocks)}',
                        valueLabel: 'VALUE',
                        value: '$symbol ${NumberFormat('#,##0').format(stocksLive)}',
                        brand: brand,
                        isDark: isDark,
                      ),

                    if (stocks.isNotEmpty && metals.isNotEmpty)
                      const SizedBox(height: 12),

                    if (metals.isNotEmpty)
                      _AssetCard(
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(builder: (_) => const PreciousMetalsScreen()),
                        ),
                        leading: _MetalAvatarRow(),
                        title: 'Precious metals',
                        subtitle: _metalSubtitle(metalHoldings),
                        valueLabel: 'VALUE',
                        value: '$symbol ${NumberFormat('#,##0').format(metalsCost)}',
                        brand: brand,
                        isDark: isDark,
                      ),
                  ]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Map<MetalType, double> _computeMetalHoldings(List<PreciousMetal> metals) {
    final map = <MetalType, double>{};
    for (final m in metals) {
      final cur = map[m.metalType] ?? 0.0;
      map[m.metalType] = m.action == MetalAction.buy ? cur + m.weightGrams : cur - m.weightGrams;
    }
    return map;
  }

  String _marketsLabel(List<StockInvestment> stocks) {
    final markets = stocks.map((s) => s.exchangeDisplay).toSet().toList();
    if (markets.isEmpty) return '';
    if (markets.length == 1) return markets.first;
    return markets.take(2).join(' + ');
  }

  String _metalSubtitle(Map<MetalType, double> holdings) {
    final parts = <String>[];
    for (final type in MetalType.values) {
      final g = holdings[type] ?? 0;
      if (g > 0) parts.add('${type.label} ${g.toStringAsFixed(2)}g');
    }
    return parts.join(' · ');
  }
}

// ── Asset card ─────────────────────────────────────────────────────────────────

class _AssetCard extends StatefulWidget {
  final VoidCallback onTap;
  final Widget leading;
  final String title;
  final String subtitle;
  final String valueLabel;
  final String value;
  final BrandColors brand;
  final bool isDark;

  const _AssetCard({
    required this.onTap,
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.valueLabel,
    required this.value,
    required this.brand,
    required this.isDark,
  });

  @override
  State<_AssetCard> createState() => _AssetCardState();
}

class _AssetCardState extends State<_AssetCard> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween<double>(begin: 1.0, end: 0.96)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = widget.brand;
    final isDark = widget.isDark;
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  widget.leading,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                            letterSpacing: -0.3,
                          )),
                        const SizedBox(height: 2),
                        Text(widget.subtitle,
                          style: TextStyle(fontSize: 12, color: brand.inkSoft),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  Icon(CupertinoIcons.chevron_right, size: 14, color: brand.inkSoft),
                ],
              ),
            ),
            Divider(height: 1, color: brand.divider, indent: 16, endIndent: 16),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.valueLabel,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: brand.inkSoft,
                            letterSpacing: 0.5,
                          )),
                        const SizedBox(height: 4),
                        Text(widget.value,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            color: brand.ink,
                            letterSpacing: -0.8,
                          )),
                      ],
                    ),
                  ),
                  // Mini sparkline placeholder
                  SizedBox(
                    width: 80,
                    height: 40,
                    child: _StaticSparkline(isDark: isDark),
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
}

// ── Static sparkline (decorative) ─────────────────────────────────────────────

class _StaticSparkline extends StatelessWidget {
  final bool isDark;
  const _StaticSparkline({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final color = _green;
    const pts = [FlSpot(0, 1), FlSpot(1, 1.4), FlSpot(2, 1.2), FlSpot(3, 1.8), FlSpot(4, 2.1), FlSpot(5, 1.9), FlSpot(6, 2.3)];
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: pts,
            isCurved: true,
            color: color,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0.0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

// ── Stock avatar row ───────────────────────────────────────────────────────────

class _StockAvatarRow extends StatelessWidget {
  final List<StockInvestment> stocks;
  const _StockAvatarRow({required this.stocks});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      width: stocks.length * 26.0 + 10,
      height: 36,
      child: Stack(
        children: stocks.asMap().entries.map((e) {
          final initials = e.value.symbol.length >= 2
              ? e.value.symbol.substring(0, 2)
              : e.value.symbol;
          return Positioned(
            left: e.key * 22.0,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE8E8EA),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(initials,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : Colors.black,
                  letterSpacing: -0.5,
                )),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Metal avatar row ───────────────────────────────────────────────────────────

class _MetalAvatarRow extends StatelessWidget {
  const _MetalAvatarRow();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = [('Au', _goldColor), ('Ag', _silverColor)];
    return SizedBox(
      width: items.length * 26.0 + 10,
      height: 36,
      child: Stack(
        children: items.asMap().entries.map((e) {
          return Positioned(
            left: e.key * 22.0,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: e.value.$2.withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  width: 2,
                ),
              ),
              alignment: Alignment.center,
              child: Text(e.value.$1,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: e.value.$2,
                )),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyInvestments extends StatelessWidget {
  final VoidCallback onAddStocks;
  final VoidCallback onAddMetals;

  const _EmptyInvestments({required this.onAddStocks, required this.onAddMetals});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          const Text('📊', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text('Start tracking your investments',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: brand.ink),
            textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('Add stocks or precious metals to see your full portfolio here.',
            style: TextStyle(fontSize: 14, color: brand.inkSoft, height: 1.4),
            textAlign: TextAlign.center),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: onAddStocks,
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: _blue,
                    borderRadius: BorderRadius.circular(23),
                  ),
                  alignment: Alignment.center,
                  child: const Text('Add Stocks',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: onAddMetals,
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: _goldColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(23),
                  ),
                  alignment: Alignment.center,
                  child: const Text('Add Metals',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _goldColor)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
