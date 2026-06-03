import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/stock_investment.dart';
import '../../services/i18n.dart';
import '../../services/stock_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'stocks_screen.dart' show stockFxRateProvider, StockAvatarBadge;

// ── Design tokens ──────────────────────────────────────────────────────────────

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
  @override
  void initState() {
    super.initState();
    _loadQuote();
  }

  Future<void> _loadQuote() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final svc = ref.read(stockServiceProvider);
    final q = await svc.getQuote(widget.stock.symbol, range: _range);
    if (!mounted) return;
    setState(() {
      _quote = q;
      _loading = false;
      if (q == null) _error = 'Could not load data';
    });
  }

  /// Resolve the freshest copy of this stock from the live provider so the
  /// detail view (and the history sheet it opens) reflects edits/deletes made
  /// in a previous history session. Falls back to the passed-in snapshot.
  StockInvestment _liveStock() {
    final all = ref.read(stockInvestmentsProvider).valueOrNull;
    if (all != null) {
      for (final s in all) {
        if (s.id == widget.stock.id) return s;
      }
    }
    return widget.stock;
  }

  void _showHistory(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PurchaseHistorySheet(stock: _liveStock()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Watch the live list so deletes/edits made inside the history sheet are
    // reflected here without relying on the stale widget.stock snapshot.
    final stock = ref
            .watch(stockInvestmentsProvider)
            .valueOrNull
            ?.where((s) => s.id == widget.stock.id)
            .firstOrNull ??
        widget.stock;
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
    final estValue = currentPriceLocal != null
        ? currentPriceLocal * stock.quantity
        : null;
    final costBasis = stock.totalCost * (isUsd ? usdToLocal : 1.0);
    final gain = estValue != null ? estValue - costBasis : null;
    final returnPct = costBasis > 0 && gain != null
        ? (gain / costBasis) * 100
        : null;

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
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: brand.surface,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.chevron_left,
                          size: 16,
                          color: brand.ink,
                        ),
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
                            Text(
                              stock.symbol,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: brand.ink,
                              ),
                            ),
                            Text(
                              stock.exchangeDisplay,
                              style: TextStyle(
                                fontSize: 11,
                                color: brand.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _showHistory(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: brand.surface,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(CupertinoIcons.clock,
                                size: 14, color: brand.ink),
                            const SizedBox(width: 6),
                            Text(
                              'History Record',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: brand.ink,
                              ),
                            ),
                          ],
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
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w500,
                              color: brand.inkSoft,
                            ),
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
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                              color: brand.inkSoft,
                            ),
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
                          Text(
                            'Today',
                            style: TextStyle(
                              fontSize: 14,
                              color: brand.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ] else if (_loading)
                      const SizedBox(
                        height: 60,
                        child: Center(child: CupertinoActivityIndicator()),
                      ),
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
                            ? Center(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: brand.inkSoft,
                                    fontSize: 13,
                                  ),
                                ),
                              )
                            : _quote != null && _quote!.chartPoints.isNotEmpty
                            ? _LineChart(
                                points: _quote!.chartPoints,
                                color: lineColor,
                                isDark: isDark,
                              )
                            : Center(
                                child: Text(
                                  'No data',
                                  style: TextStyle(
                                    color: brand.inkSoft,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                      ),
                      const SizedBox(height: 12),
                      // Range selector
                      Row(
                        children: StockService.rangeOptions.map((r) {
                          final sel = r == _range;
                          return Expanded(
                            child: _RangeBtn(
                              label: r,
                              selected: sel,
                              onTap: () async {
                                HapticFeedback.selectionClick();
                                setState(() => _range = r);
                                await _loadQuote();
                              },
                              brand: brand,
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
                        // Row 1: UNITS | EST. VALUE — large numbers
                        IntrinsicHeight(
                          child: Row(
                            children: [
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'UNITS',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: brand.inkSoft,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      RichText(
                                        text: TextSpan(
                                          children: [
                                            TextSpan(
                                              text: _fmtQty(stock.quantity),
                                              style: TextStyle(
                                                fontSize: 28,
                                                fontWeight: FontWeight.w800,
                                                color: brand.ink,
                                                letterSpacing: -0.8,
                                              ),
                                            ),
                                            TextSpan(
                                              text: ' sh',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w500,
                                                color: brand.inkSoft,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              VerticalDivider(width: 1, color: brand.divider),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'EST. VALUE',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: brand.inkSoft,
                                          letterSpacing: 0.8,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      if (estValue != null)
                                        RichText(
                                          text: TextSpan(
                                            children: [
                                              TextSpan(
                                                text: '$symbol ',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                  color: brand.inkSoft,
                                                ),
                                              ),
                                              TextSpan(
                                                text: NumberFormat(
                                                  '#,##0',
                                                ).format(estValue),
                                                style: TextStyle(
                                                  fontSize: 28,
                                                  fontWeight: FontWeight.w800,
                                                  color: brand.ink,
                                                  letterSpacing: -0.8,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        Text(
                                          '–',
                                          style: TextStyle(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w800,
                                            color: brand.ink,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Divider(
                          height: 1,
                          color: brand.divider,
                          indent: 16,
                          endIndent: 16,
                        ),
                        // Bottom: 2-column — AVG BUY/GAIN | COST BASIS/RETURN
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'AVG BUY',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: brand.inkSoft,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '\$${stock.buyPrice.toStringAsFixed(2)}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: brand.ink,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'GAIN',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: brand.inkSoft,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      gain != null
                                          ? '${gain >= 0 ? '+' : '-'}$symbol ${NumberFormat('#,##0').format(gain.abs())}'
                                          : '–',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.3,
                                        color: gain != null
                                            ? (gain >= 0 ? _green : _red)
                                            : brand.inkSoft,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'COST BASIS',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: brand.inkSoft,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '$symbol ${NumberFormat('#,##0').format(costBasis)}',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: brand.ink,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'RETURN',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: brand.inkSoft,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      returnPct != null
                                          ? '${returnPct >= 0 ? '+' : ''}${returnPct.toStringAsFixed(2)}%'
                                          : '–',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.3,
                                        color: returnPct != null
                                            ? (returnPct >= 0 ? _green : _red)
                                            : brand.inkSoft,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
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

// ── Range button with press animation ─────────────────────────────────────────

class _RangeBtn extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final BrandColors brand;

  const _RangeBtn({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.brand,
  });

  @override
  State<_RangeBtn> createState() => _RangeBtnState();
}

class _RangeBtnState extends State<_RangeBtn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 80),
    );
    _scale = Tween<double>(
      begin: 1.0,
      end: 0.88,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 30,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: widget.selected ? widget.brand.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: widget.selected ? FontWeight.w700 : FontWeight.w500,
              color: widget.selected
                  ? widget.brand.background
                  : widget.brand.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Line chart ─────────────────────────────────────────────────────────────────

class _LineChart extends StatelessWidget {
  final List<StockPoint> points;
  final Color color;
  final bool isDark;

  const _LineChart({
    required this.points,
    required this.color,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final spots = points
        .asMap()
        .entries
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
            getTooltipItems: (spots) => spots
                .map(
                  (s) => LineTooltipItem(
                    '\$${s.y.toStringAsFixed(2)}',
                    TextStyle(
                      color: color,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                )
                .toList(),
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
                colors: [
                  color.withValues(alpha: 0.18),
                  color.withValues(alpha: 0.0),
                ],
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

// ── Purchase history sheet ─────────────────────────────────────────────────────

class _TxCoordinator extends ValueNotifier<int?> {
  _TxCoordinator() : super(null);
  void openRow(int index) => value = index;
  void closeAll() => value = null;
}

class _PurchaseHistorySheet extends ConsumerStatefulWidget {
  final StockInvestment stock;
  const _PurchaseHistorySheet({required this.stock});

  @override
  ConsumerState<_PurchaseHistorySheet> createState() =>
      _PurchaseHistorySheetState();
}

class _PurchaseHistorySheetState
    extends ConsumerState<_PurchaseHistorySheet> {
  late StockInvestment _stock;
  late List<Map<String, dynamic>> _txns;
  final _coordinator = _TxCoordinator();

  @override
  void initState() {
    super.initState();
    _stock = widget.stock;
    _txns = _stock.transactions.reversed.toList();
  }

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  StockInvestment _recalc(
      StockInvestment base, List<Map<String, dynamic>> txns) {
    double buyQty = 0, buyCost = 0, sellQty = 0;
    for (final tx in txns) {
      final q = (tx['qty'] as num?)?.toDouble() ?? 0;
      final p = (tx['price'] as num?)?.toDouble() ?? 0;
      if ((tx['type'] as String?) == 'sell') {
        sellQty += q;
      } else {
        buyQty += q;
        buyCost += q * p;
      }
    }
    return base.copyWith(
      quantity: buyQty - sellQty,
      buyPrice: buyQty > 0 ? buyCost / buyQty : base.buyPrice,
      transactions: txns,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _save(StockInvestment updated) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    // NOTE: Stocks are Firebase-only (no local Hive repository / offline queue).
    // When offline the Firestore write throws after a timeout; handle it
    // gracefully with a toast instead of letting the error surface/crash.
    try {
      await ref
          .read(stockInvestmentRepositoryProvider)
          .update(user.uid, updated);
    } catch (_) {
      if (!mounted) return;
      AppToast.show(
        context,
        context.t('common.error'),
        type: AppToastType.error,
        icon: CupertinoIcons.exclamationmark_circle_fill,
      );
      return;
    }
    if (!mounted) return;
    setState(() {
      _stock = updated;
      _txns = updated.transactions.reversed.toList();
    });
  }

  Future<void> _deleteTx(int idx) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Transaction?'),
        content: const Text(
            'This transaction will be permanently removed.'),
        actions: [
          CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final origIdx = _stock.transactions.length - 1 - idx;
    final newTxns = List<Map<String, dynamic>>.from(_stock.transactions)
      ..removeAt(origIdx);
    await _save(_recalc(_stock, newTxns));
  }

  Future<void> _editTx(int idx, Map<String, dynamic> tx) async {
    final result = await showModalBottomSheet<Map<String, dynamic>?>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditTxSheet(tx: tx),
    );
    if (result == null || !mounted) return;
    final origIdx = _stock.transactions.length - 1 - idx;
    final newTxns = List<Map<String, dynamic>>.from(_stock.transactions);
    newTxns[origIdx] = result;
    await _save(_recalc(_stock, newTxns));
  }

  Future<void> _copyTx(Map<String, dynamic> tx) async {
    final copy = Map<String, dynamic>.from(tx)
      ..['date'] = DateTime.now().toIso8601String();
    final newTxns = List<Map<String, dynamic>>.from(_stock.transactions)
      ..add(copy);
    await _save(_recalc(_stock, newTxns));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Transaction copied')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.75,
      ),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _coordinator.closeAll,
        child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              decoration: BoxDecoration(
                color: brand.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Text(
                  '${_stock.symbol} History Record',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                    letterSpacing: -0.3,
                  ),
                ),
                const Spacer(),
                Text(
                  '${_txns.length} record${_txns.length == 1 ? '' : 's'}',
                  style: TextStyle(fontSize: 13, color: brand.inkSoft),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: brand.divider),
          if (_txns.isEmpty)
            Padding(
              padding: const EdgeInsets.all(40),
              child: Text(
                'No transaction history yet.',
                style: TextStyle(fontSize: 15, color: brand.inkSoft),
                textAlign: TextAlign.center,
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 32),
                itemCount: _txns.length,
                separatorBuilder: (context, index) =>
                    Divider(height: 1, color: brand.divider),
                itemBuilder: (_, i) {
                  final tx = _txns[i];
                  return _TxSlidable(
                    index: i,
                    coordinator: _coordinator,
                    onEdit: () => _editTx(i, tx),
                    onDelete: () => _deleteTx(i),
                    onCopy: () => _copyTx(tx),
                    child: _TxRow(tx: tx, brand: brand),
                  );
                },
              ),
            ),
        ],
        ),
      ),
    );
  }
}

// ── Transaction row ────────────────────────────────────────────────────────────

class _TxRow extends StatelessWidget {
  final Map<String, dynamic> tx;
  final BrandColors brand;

  const _TxRow({required this.tx, required this.brand});

  @override
  Widget build(BuildContext context) {
    final isBuy = (tx['type'] as String?) != 'sell';
    final qty = (tx['qty'] as num?)?.toDouble() ?? 0;
    final price = (tx['price'] as num?)?.toDouble() ?? 0;
    final realized = (tx['realizedGainLoss'] as num?)?.toDouble();
    final currency = tx['currency'] as String? ?? 'USD';
    final currSym = currency == 'MYR' ? 'RM' : '\$';
    final date =
        DateTime.tryParse(tx['date'] as String? ?? '') ?? DateTime.now();
    final dateStr = DateFormat('MMM d, y · h:mm a').format(date);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: isBuy
                  ? const Color(0xFF0066CC).withValues(alpha: 0.1)
                  : const Color(0xFFFF3B30).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isBuy
                  ? CupertinoIcons.arrow_up_right
                  : CupertinoIcons.arrow_down_left,
              size: 16,
              color:
                  isBuy ? const Color(0xFF0066CC) : const Color(0xFFFF3B30),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isBuy ? 'Bought' : 'Sold',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  dateStr,
                  style: TextStyle(fontSize: 12, color: brand.inkSoft),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${qty == qty.floorToDouble() ? qty.toInt() : qty.toStringAsFixed(2)} sh',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                !isBuy && realized != null
                    ? '$currSym${price.toStringAsFixed(2)}/sh · ${realized >= 0 ? '+' : '-'}$currSym${realized.abs().toStringAsFixed(2)}'
                    : '$currSym${price.toStringAsFixed(2)}/sh',
                style: TextStyle(fontSize: 12, color: brand.inkSoft),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Swipeable transaction wrapper ─────────────────────────────────────────────

class _TxSlidable extends StatefulWidget {
  final Widget child;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCopy;
  final int index;
  final _TxCoordinator coordinator;

  const _TxSlidable({
    required this.child,
    required this.onEdit,
    required this.onDelete,
    required this.onCopy,
    required this.index,
    required this.coordinator,
  });

  @override
  State<_TxSlidable> createState() => _TxSlidableState();
}

class _TxSlidableState extends State<_TxSlidable>
    with SingleTickerProviderStateMixin {
  static const double _rightPanelW = 160.0; // Edit + Delete (2 × 80)
  static const double _leftPanelW = 80.0;   // Copy

  late final AnimationController _ctrl;
  late final CurvedAnimation _curve;
  double _offset = 0;
  double _dragStartOffset = 0;
  double _animStart = 0;
  double _animTarget = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    _ctrl.addListener(_onTick);
    widget.coordinator.addListener(_onCoordinatorChange);
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_onCoordinatorChange);
    _ctrl.dispose();
    _curve.dispose();
    super.dispose();
  }

  void _onCoordinatorChange() {
    final open = widget.coordinator.value;
    if (open != widget.index && _offset != 0) {
      _springAnimate(0);
    }
  }

  void _onTick() {
    setState(
      () => _offset = _animStart + (_animTarget - _animStart) * _curve.value,
    );
  }

  void _springAnimate(double target) {
    _ctrl.stop();
    _animStart = _offset;
    _animTarget = target;
    _ctrl
      ..reset()
      ..forward();
  }

  void _close() => _springAnimate(0);

  void _onDragStart(DragStartDetails _) {
    _ctrl.stop();
    _dragStartOffset = _offset;
    widget.coordinator.openRow(widget.index);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(-_rightPanelW, _leftPanelW);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final rightInvolved = _dragStartOffset < 0 || (_dragStartOffset == 0 && _offset < 0);
    if (rightInvolved) {
      (_offset < -_rightPanelW * 0.35 || v < -500)
          ? _springAnimate(-_rightPanelW)
          : _springAnimate(0);
    } else {
      (_offset > _leftPanelW * 0.35 || v > 500)
          ? _springAnimate(_leftPanelW)
          : _springAnimate(0);
    }
  }

  Future<void> _handleCopySwipe() async {
    HapticFeedback.selectionClick();
    _close();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    widget.onCopy();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final revealRight = (-_offset / _rightPanelW).clamp(0.0, 1.0);
    final revealLeft = (_offset / _leftPanelW).clamp(0.0, 1.0);
    final isOpen = _offset != 0;

    return ClipRect(
      child: GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Stack(
          children: [
            // Right panel (swipe left): Edit + Delete
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _rightPanelW,
              child: Row(
                children: [
                  Expanded(
                    child: _TxSwipeAction(
                      label: 'Edit',
                      icon: CupertinoIcons.pencil,
                      color: const Color.fromARGB(200, 0, 122, 255),
                      reveal: (revealRight * 2).clamp(0.0, 1.0),
                      onTap: () {
                        _close();
                        widget.onEdit();
                      },
                    ),
                  ),
                  Expanded(
                    child: _TxSwipeAction(
                      label: 'Delete',
                      icon: CupertinoIcons.trash_fill,
                      color: const Color.fromARGB(200, 255, 69, 58),
                      reveal: (revealRight * 2 - 0.25).clamp(0.0, 1.0),
                      onTap: () {
                        _close();
                        widget.onDelete();
                      },
                    ),
                  ),
                ],
              ),
            ),
            // Left panel (swipe right): Copy
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _leftPanelW,
              child: _TxSwipeAction(
                label: 'Copy',
                icon: CupertinoIcons.doc_on_doc,
                color: const Color.fromARGB(200, 90, 200, 250),
                reveal: revealLeft,
                onTap: _handleCopySwipe,
              ),
            ),
            // Main content
            Transform.translate(
              offset: Offset(_offset, 0),
              child: isOpen
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _close,
                      child: AbsorbPointer(
                        child: Container(
                          color: brand.background,
                          child: widget.child,
                        ),
                      ),
                    )
                  : Container(color: brand.background, child: widget.child),
            ),
          ],
        ),
      ),
    );
  }
}

class _TxSwipeAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final double reveal;
  final VoidCallback onTap;

  const _TxSwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.reveal,
    required this.onTap,
  });

  @override
  State<_TxSwipeAction> createState() => _TxSwipeActionState();
}

class _TxSwipeActionState extends State<_TxSwipeAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: double.infinity,
        height: double.infinity,
        color: _pressed
            ? widget.color.withValues(alpha: widget.color.a * 0.72)
            : widget.color,
        child: Transform.scale(
          scale: 0.7 + 0.3 * widget.reveal,
          child: Opacity(
            opacity: widget.reveal.clamp(0.0, 1.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: Colors.white, size: 22),
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Edit transaction sheet ─────────────────────────────────────────────────────

class _EditTxSheet extends StatefulWidget {
  final Map<String, dynamic> tx;
  const _EditTxSheet({required this.tx});

  @override
  State<_EditTxSheet> createState() => _EditTxSheetState();
}

class _EditTxSheetState extends State<_EditTxSheet> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  late DateTime _date;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final qty = (widget.tx['qty'] as num?)?.toDouble() ?? 0;
    final price = (widget.tx['price'] as num?)?.toDouble() ?? 0;
    _qtyCtrl = TextEditingController(
        text: qty == qty.floorToDouble()
            ? qty.toInt().toString()
            : qty.toStringAsFixed(4));
    _priceCtrl = TextEditingController(text: price.toStringAsFixed(2));
    _date =
        DateTime.tryParse(widget.tx['date'] as String? ?? '') ?? DateTime.now();
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final qty = double.tryParse(_qtyCtrl.text);
    final price = double.tryParse(_priceCtrl.text);
    if (qty == null || qty <= 0 || price == null || price <= 0) return;
    setState(() => _saving = true);
    final updated = Map<String, dynamic>.from(widget.tx)
      ..['qty'] = qty
      ..['price'] = price
      ..['date'] = _date.toIso8601String();
    Navigator.pop(context, updated);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isBuy = (widget.tx['type'] as String?) != 'sell';
    final currency = widget.tx['currency'] as String? ?? 'USD';
    final currSym = currency == 'MYR' ? 'RM' : '\$';

    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: brand.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Edit ${isBuy ? 'Buy' : 'Sell'} Transaction',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: brand.ink,
              ),
            ),
            const SizedBox(height: 20),
            _field('Shares', _qtyCtrl, 'qty', brand),
            const SizedBox(height: 12),
            _field('Price/sh ($currSym)', _priceCtrl, 'price', brand),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date,
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (picked != null) setState(() => _date = picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.calendar,
                        size: 16, color: brand.inkSoft),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat('MMM d, y').format(_date),
                      style: TextStyle(
                          fontSize: 15,
                          color: brand.ink,
                          fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton(
                onPressed: _saving ? null : _submit,
                style: FilledButton.styleFrom(
                  backgroundColor: isBuy
                      ? const Color(0xFF0066CC)
                      : const Color(0xFFFF3B30),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('Save',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
      String label, TextEditingController ctrl, String key, BrandColors brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: TextStyle(
                fontSize: 13,
                color: brand.inkSoft,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 6),
        TextField(
          controller: ctrl,
          keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            filled: true,
            fillColor: brand.surface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
          style: TextStyle(
              fontSize: 15, color: brand.ink, fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}
