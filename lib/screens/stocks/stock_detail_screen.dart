import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/stock_investment.dart';
import '../../services/stock_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import 'stocks_screen.dart' show stockFxRateProvider, StockAvatarBadge;

// ── Design tokens ──────────────────────────────────────────────────────────────

const _blue = Color(0xFF0066CC);
const _green = Color(0xFF34C759);
const _red = Color(0xFFFF3B30);

// ── Stock Detail Screen ────────────────────────────────────────────────────────

class StockDetailScreen extends ConsumerStatefulWidget {
  final StockInvestment stock;

  const StockDetailScreen({super.key, required this.stock});

  @override
  ConsumerState<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends ConsumerState<StockDetailScreen> {
  String _range = '1M';
  StockQuote? _quote;
  bool _loading = true;
  String? _error;
  bool _bookmarked = false;

  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  Future<void> _loadQuote() async {
    setState(() { _loading = true; _error = null; });
    final svc = ref.read(stockServiceProvider);
    final q = await svc.getQuote(widget.stock.symbol, range: _range);
    if (!mounted) return;
    setState(() {
      _quote = q;
      _loading = false;
      if (q == null) _error = 'Could not load data';
    });
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stock = widget.stock;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? 'RM';
    const symToIso = {'RM': 'MYR', '\$': 'USD', 'S\$': 'SGD', '€': 'EUR'};
    final localIso = symToIso[symbol] ?? 'MYR';
    final fxAsync = ref.watch(stockFxRateProvider(localIso));
    final usdToLocal = fxAsync.valueOrNull ?? 4.48;

    final isUp = _quote?.isUp ?? true;
    final lineColor = isUp ? _green : _red;

    // Holdings calculations
    final isUsd = stock.currency == 'USD' || stock.currency == null;
    final currentPriceLocal = _quote != null
        ? (_quote!.price * (isUsd ? usdToLocal : 1.0))
        : null;
    final estValue = currentPriceLocal != null ? currentPriceLocal * stock.quantity : null;
    final costBasis = stock.totalCost * (isUsd ? usdToLocal : 1.0);
    final gain = estValue != null ? estValue - costBasis : null;
    final returnPct = costBasis > 0 && gain != null ? (gain / costBasis) * 100 : null;

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
                    const Spacer(),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        StockAvatarBadge(symbol: stock.symbol, size: 28),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(stock.symbol,
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: brand.ink)),
                            Text(stock.exchangeDisplay,
                              style: TextStyle(fontSize: 11, color: brand.inkSoft)),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => setState(() => _bookmarked = !_bookmarked),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: brand.surface, shape: BoxShape.circle),
                        child: Icon(
                          _bookmarked ? CupertinoIcons.bookmark_fill : CupertinoIcons.bookmark,
                          size: 16,
                          color: _bookmarked ? _blue : brand.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),

            // ── Hero price section ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Sector · Exchange
                    Text(
                      '${_sectorFor(stock)} · ${stock.exchangeDisplay}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: brand.inkSoft,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Company name
                    Text(
                      _quote?.name ?? stock.name ?? stock.symbol,
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: brand.ink,
                        letterSpacing: -0.8,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Price
                    if (_quote != null) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '\$',
                            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: brand.inkSoft),
                          ),
                          const SizedBox(width: 2),
                          Text(
                            NumberFormat('#,##0.00').format(_quote!.price),
                            style: TextStyle(
                              fontSize: 44,
                              fontWeight: FontWeight.w800,
                              color: brand.ink,
                              letterSpacing: -1.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _quote!.currency,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: brand.inkSoft),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Text(
                            '${isUp ? '+' : ''}\$${_quote!.change.abs().toStringAsFixed(2)} (${isUp ? '+' : ''}${_quote!.changePercent.toStringAsFixed(2)}%)',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: lineColor,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text('Today', style: TextStyle(fontSize: 14, color: brand.inkSoft)),
                        ],
                      ),
                    ] else if (_loading)
                      const SizedBox(height: 60, child: Center(child: CupertinoActivityIndicator())),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),

            // ── Price chart ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
                  child: Column(
                    children: [
                      // Chart
                      SizedBox(
                        height: 180,
                        child: _loading
                            ? const Center(child: CupertinoActivityIndicator())
                            : _error != null
                                ? Center(child: Text(_error!, style: TextStyle(color: brand.inkSoft, fontSize: 13)))
                                : _quote != null && _quote!.chartPoints.isNotEmpty
                                    ? _LineChart(points: _quote!.chartPoints, color: lineColor, isDark: isDark)
                                    : Center(child: Text('No data', style: TextStyle(color: brand.inkSoft, fontSize: 13))),
                      ),
                      const SizedBox(height: 12),
                      // Range selector
                      Row(
                        children: StockService.rangeOptions.map((r) {
                          final sel = r == _range;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () async {
                                setState(() => _range = r);
                                await _loadQuote();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                height: 30,
                                margin: const EdgeInsets.symmetric(horizontal: 2),
                                decoration: BoxDecoration(
                                  color: sel ? brand.ink : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  r,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                                    color: sel ? brand.background : brand.inkSoft,
                                  ),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // ── YOUR HOLDING ───────────────────────────────────────────────
            if (!stock.watchOnly) ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    'YOUR HOLDING',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: brand.inkSoft,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 10)),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Container(
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        // Row 1: UNITS | EST. VALUE
                        _HoldingRow(
                          left: _HoldingCell(
                            label: 'UNITS',
                            value: '${_fmtQty(stock.quantity)} sh',
                            brand: brand,
                          ),
                          right: _HoldingCell(
                            label: 'EST. VALUE',
                            value: estValue != null
                                ? '${symbol} ${NumberFormat('#,##0').format(estValue)}'
                                : '–',
                            brand: brand,
                          ),
                          brand: brand,
                        ),
                        Divider(height: 1, color: brand.divider, indent: 16, endIndent: 16),
                        // Row 2: AVG BUY | COST BASIS
                        _HoldingRow(
                          left: _HoldingCell(
                            label: 'AVG BUY',
                            value: '\$${stock.buyPrice.toStringAsFixed(2)}',
                            brand: brand,
                          ),
                          right: _HoldingCell(
                            label: 'COST BASIS',
                            value: '$symbol ${NumberFormat('#,##0').format(costBasis)}',
                            brand: brand,
                          ),
                          brand: brand,
                        ),
                        Divider(height: 1, color: brand.divider, indent: 16, endIndent: 16),
                        // Row 3: GAIN | RETURN
                        _HoldingRow(
                          left: _HoldingCell(
                            label: 'GAIN',
                            value: gain != null
                                ? '${gain >= 0 ? '+' : ''}$symbol ${NumberFormat('#,##0').format(gain.abs())}'
                                : '–',
                            valueColor: gain != null ? (gain >= 0 ? _green : _red) : null,
                            brand: brand,
                          ),
                          right: _HoldingCell(
                            label: 'RETURN',
                            value: returnPct != null
                                ? '${returnPct >= 0 ? '+' : ''}${returnPct.toStringAsFixed(2)}%'
                                : '–',
                            valueColor: returnPct != null ? (returnPct >= 0 ? _green : _red) : null,
                            brand: brand,
                          ),
                          brand: brand,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  String _sectorFor(StockInvestment stock) {
    final ex = stock.exchangeDisplay;
    if (ex == 'KLSE') return 'BANKING';
    return 'TECHNOLOGY';
  }

  String _fmtQty(double qty) {
    return qty == qty.floorToDouble()
        ? NumberFormat('#,##0').format(qty)
        : qty.toStringAsFixed(2);
  }
}

// ── Holding layout ─────────────────────────────────────────────────────────────

class _HoldingRow extends StatelessWidget {
  final _HoldingCell left;
  final _HoldingCell right;
  final BrandColors brand;

  const _HoldingRow({required this.left, required this.right, required this.brand});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        children: [
          Expanded(child: left),
          VerticalDivider(width: 1, color: brand.divider),
          Expanded(child: right),
        ],
      ),
    );
  }
}

class _HoldingCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final BrandColors brand;

  const _HoldingCell({
    required this.label,
    required this.value,
    this.valueColor,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: brand.inkSoft,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: valueColor ?? brand.ink,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Line chart ─────────────────────────────────────────────────────────────────

class _LineChart extends StatelessWidget {
  final List<StockPoint> points;
  final Color color;
  final bool isDark;

  const _LineChart({required this.points, required this.color, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final spots = points.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.close))
        .toList();
    final minY = points.map((p) => p.close).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.close).reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) * 0.1;

    // Find last point for end dot
    final lastIdx = (spots.length - 1).toDouble();

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minY: minY - pad,
        maxY: maxY + pad,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                isDark ? const Color(0xFF2C2C2E) : Colors.white,
            tooltipRoundedRadius: 10,
            getTooltipItems: (spots) => spots.map((s) => LineTooltipItem(
              '\$${s.y.toStringAsFixed(2)}',
              TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12),
            )).toList(),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.3,
            color: color,
            barWidth: 2.5,
            dotData: FlDotData(
              show: true,
              checkToShowDot: (spot, _) => spot.x == lastIdx,
              getDotPainter: (spot, p, barData, idx) => FlDotCirclePainter(
                radius: 5,
                color: color,
                strokeWidth: 2,
                strokeColor: Colors.white,
              ),
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.18), color.withValues(alpha: 0.0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }
}
