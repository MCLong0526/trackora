import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/precious_metal.dart';
import '../../models/stock_investment.dart';
import '../../services/money_format.dart';
import '../../services/stock_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../precious_metals/precious_metals_screen.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────

const _blue = Color(0xFF0066CC);
const _green = Color(0xFF34C759);
const _red = Color(0xFFFF3B30);
const _goldColor = Color(0xFFD4AF37);
const _stockAccent = Color(0xFF5856D6); // purple for stocks

// ── Investment Screen ──────────────────────────────────────────────────────────

class InvestmentScreen extends ConsumerStatefulWidget {
  const InvestmentScreen({super.key});

  @override
  ConsumerState<InvestmentScreen> createState() => _InvestmentScreenState();
}

class _InvestmentScreenState extends ConsumerState<InvestmentScreen> {
  // Tab: 0 = Precious Metals, 1 = Stocks
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final metals =
        ref.watch(preciousMetalsProvider).valueOrNull ?? const <PreciousMetal>[];
    final stocks =
        ref.watch(stockInvestmentsProvider).valueOrNull ?? const <StockInvestment>[];
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';

    return Scaffold(
      backgroundColor: brand.background,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ─────────────────────────────────────────────────────
            Padding(
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
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Investments',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.5,
                        color: brand.ink,
                      ),
                    ),
                  ),
                  if (_tab == 1)
                    GestureDetector(
                      onTap: () => _showAddStockSheet(context, ref),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: const BoxDecoration(
                          color: _blue,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.add,
                          size: 18,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ── Tab bar ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _TabBar(
                selected: _tab,
                onChanged: (i) => setState(() => _tab = i),
                isDark: isDark,
              ),
            ),

            const SizedBox(height: 16),

            // ── Content ────────────────────────────────────────────────────
            Expanded(
              child: IndexedStack(
                index: _tab,
                children: [
                  _PreciousMetalsTab(
                    metals: metals,
                    symbol: symbol,
                    isDark: isDark,
                    onManage: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const PreciousMetalsScreen(),
                      ),
                    ),
                  ),
                  _StocksTab(
                    stocks: stocks,
                    isDark: isDark,
                    onAdd: () => _showAddStockSheet(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddStockSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _AddEditStockSheet(onSave: (investment) async {
        final user = ref.read(authStateProvider).valueOrNull;
        if (user == null) return;
        try {
          await ref
              .read(stockInvestmentRepositoryProvider)
              .add(user.uid, investment);
          if (context.mounted) {
            AppToast.show(context, 'Stock added');
          }
        } catch (_) {
          if (context.mounted) {
            AppToast.show(context, 'Failed to save', type: AppToastType.error);
          }
        }
      }),
    );
  }
}

// ── Tab bar ────────────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  final bool isDark;

  const _TabBar({
    required this.selected,
    required this.onChanged,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final tabs = ['Precious Metals', 'Stocks'];
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(tabs.length, (i) {
          final isSelected = selected == i;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(i);
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: isSelected ? (isDark ? const Color(0xFF3A3A3C) : Colors.white) : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  tabs[i],
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? brand.ink : brand.inkSoft,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ── Precious Metals Tab ────────────────────────────────────────────────────────

class _PreciousMetalsTab extends StatelessWidget {
  final List<PreciousMetal> metals;
  final String symbol;
  final bool isDark;
  final VoidCallback onManage;

  const _PreciousMetalsTab({
    required this.metals,
    required this.symbol,
    required this.isDark,
    required this.onManage,
  });

  Map<MetalType, double> _computeHoldings() {
    final map = <MetalType, double>{};
    for (final m in metals) {
      final cur = map[m.metalType] ?? 0.0;
      map[m.metalType] = m.action == MetalAction.buy
          ? cur + m.weightGrams
          : cur - m.weightGrams;
    }
    return map;
  }

  double _computeTotalValue() {
    double total = 0;
    for (final m in metals) {
      total += m.action == MetalAction.buy ? m.totalAmount : -m.totalAmount;
    }
    return total < 0 ? 0 : total;
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final holdings = _computeHoldings();
    final totalValue = _computeTotalValue();

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        // ── Summary card ─────────────────────────────────────────────────
        Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1A1800) : const Color(0xFFFFFBF0),
            borderRadius: BorderRadius.circular(AppRadius.card),
            border: Border.all(
              color: _goldColor.withValues(alpha: isDark ? 0.18 : 0.22),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: _goldColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Center(
                      child: Text('✦', style: TextStyle(fontSize: 18, color: _goldColor)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Precious Metals',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : const Color(0xFF3A2E00),
                          ),
                        ),
                        Text(
                          metals.isEmpty ? 'No holdings yet' : '${metals.length} transaction${metals.length == 1 ? '' : 's'}',
                          style: TextStyle(
                            fontSize: 12,
                            color: brand.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (metals.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  formatMoney(symbol, totalValue),
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                    color: isDark ? Colors.white : const Color(0xFF3A2E00),
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: MetalType.values
                      .where((t) => (holdings[t] ?? 0) > 0)
                      .map((t) => _MetalPill(metalType: t, grams: holdings[t]!))
                      .toList(),
                ),
              ],
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  onManage();
                },
                child: Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: _goldColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        metals.isEmpty ? CupertinoIcons.add : CupertinoIcons.chart_bar_alt_fill,
                        size: 15,
                        color: isDark ? _goldColor : const Color(0xFF8B7A30),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        metals.isEmpty ? 'Add Metals' : 'Manage Holdings',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: isDark ? _goldColor : const Color(0xFF8B7A30),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Breakdown ────────────────────────────────────────────────────
        if (metals.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'HOLDINGS BREAKDOWN',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: brand.inkSoft,
                letterSpacing: 0.8,
              ),
            ),
          ),
          ...MetalType.values
              .where((t) => (holdings[t] ?? 0) > 0)
              .map((t) => _MetalBreakdownRow(
                    metalType: t,
                    grams: holdings[t]!,
                    isDark: isDark,
                  )),
        ] else
          _EmptyState(
            icon: '✦',
            title: 'No Precious Metal Holdings',
            subtitle: 'Tap "Add Metals" above to record your gold, silver, and other precious metal investments.',
          ),
      ],
    );
  }
}

class _MetalPill extends StatelessWidget {
  final MetalType metalType;
  final double grams;

  const _MetalPill({required this.metalType, required this.grams});

  @override
  Widget build(BuildContext context) {
    final color = metalType.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.5),
      ),
      child: Text(
        '${metalType.label}: ${grams.toStringAsFixed(2)}g',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _MetalBreakdownRow extends StatelessWidget {
  final MetalType metalType;
  final double grams;
  final bool isDark;

  const _MetalBreakdownRow({
    required this.metalType,
    required this.grams,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = metalType.primaryColor;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              CupertinoIcons.circle_filled,
              size: 18,
              color: color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metalType.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                  ),
                ),
                Text(
                  '${grams.toStringAsFixed(3)} grams',
                  style: TextStyle(fontSize: 12, color: brand.inkSoft),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stocks Tab ─────────────────────────────────────────────────────────────────

class _StocksTab extends ConsumerStatefulWidget {
  final List<StockInvestment> stocks;
  final bool isDark;
  final VoidCallback onAdd;

  const _StocksTab({
    required this.stocks,
    required this.isDark,
    required this.onAdd,
  });

  @override
  ConsumerState<_StocksTab> createState() => _StocksTabState();
}

class _StocksTabState extends ConsumerState<_StocksTab> {
  String? _selectedSymbol;
  String _range = '1M';
  StockQuote? _quote;
  bool _loadingQuote = false;
  String? _quoteError;

  @override
  void didUpdateWidget(_StocksTab old) {
    super.didUpdateWidget(old);
    // If stocks list changes, auto-select first
    if (widget.stocks != old.stocks) {
      _autoSelect();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _autoSelect());
  }

  void _autoSelect() {
    if (widget.stocks.isEmpty) {
      setState(() {
        _selectedSymbol = null;
        _quote = null;
      });
      return;
    }
    final sym = _selectedSymbol ?? widget.stocks.first.symbol;
    if (widget.stocks.any((s) => s.symbol == sym)) {
      _loadQuote(sym);
    } else {
      _loadQuote(widget.stocks.first.symbol);
    }
  }

  Future<void> _loadQuote(String symbol) async {
    if (!mounted) return;
    setState(() {
      _selectedSymbol = symbol;
      _loadingQuote = true;
      _quoteError = null;
    });
    final svc = ref.read(stockServiceProvider);
    final q = await svc.getQuote(symbol, range: _range);
    if (!mounted) return;
    setState(() {
      _quote = q;
      _loadingQuote = false;
      if (q == null) _quoteError = 'Could not load data for $symbol';
    });
  }

  Future<void> _changeRange(String range) async {
    setState(() => _range = range);
    if (_selectedSymbol != null) await _loadQuote(_selectedSymbol!);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    if (widget.stocks.isEmpty) {
      return _EmptyState(
        icon: '📈',
        title: 'No Stock Investments',
        subtitle: 'Tap the + button to track your first stock holding.',
        action: ElevatedButton.icon(
          onPressed: widget.onAdd,
          icon: const Icon(CupertinoIcons.add, size: 16),
          label: const Text('Add Stock'),
          style: ElevatedButton.styleFrom(
            backgroundColor: _blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      children: [
        // ── Chart card ──────────────────────────────────────────────────
        _StockChartCard(
          quote: _quote,
          loading: _loadingQuote,
          error: _quoteError,
          range: _range,
          isDark: widget.isDark,
          onRangeChanged: _changeRange,
        ),
        const SizedBox(height: 16),

        // ── Portfolio header ─────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 10),
          child: Text(
            'YOUR PORTFOLIO',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: brand.inkSoft,
              letterSpacing: 0.8,
            ),
          ),
        ),

        // ── Stock list ───────────────────────────────────────────────────
        ...widget.stocks.map((stock) {
          final isSelected = _selectedSymbol == stock.symbol;
          final currentPrice = (_quote?.symbol == stock.symbol)
              ? _quote!.price
              : null;
          return _StockRow(
            stock: stock,
            currentPrice: currentPrice,
            isSelected: isSelected,
            isDark: widget.isDark,
            onTap: () => _loadQuote(stock.symbol),
            onEdit: () => _showEditSheet(stock),
            onDelete: () => _confirmDelete(stock),
          );
        }),
      ],
    );
  }

  void _showEditSheet(StockInvestment stock) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => _AddEditStockSheet(
        existing: stock,
        onSave: (updated) async {
          final user = ref.read(authStateProvider).valueOrNull;
          if (user == null) return;
          try {
            await ref
                .read(stockInvestmentRepositoryProvider)
                .update(user.uid, updated.copyWith(id: stock.id));
            if (mounted) AppToast.show(context, 'Stock updated');
          } catch (_) {
            if (mounted) AppToast.show(context, 'Failed to update', type: AppToastType.error);
          }
        },
      ),
    );
  }

  void _confirmDelete(StockInvestment stock) {
    showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Stock'),
        content: Text('Remove ${stock.symbol} from your portfolio?'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              final user = ref.read(authStateProvider).valueOrNull;
              if (user == null) return;
              try {
                await ref
                    .read(stockInvestmentRepositoryProvider)
                    .delete(user.uid, stock.id);
                if (mounted) AppToast.show(context, 'Stock removed');
              } catch (_) {
                if (mounted) AppToast.show(context, 'Failed to delete', type: AppToastType.error);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}

// ── Stock chart card ───────────────────────────────────────────────────────────

class _StockChartCard extends StatelessWidget {
  final StockQuote? quote;
  final bool loading;
  final String? error;
  final String range;
  final bool isDark;
  final ValueChanged<String> onRangeChanged;

  const _StockChartCard({
    required this.quote,
    required this.loading,
    required this.error,
    required this.range,
    required this.isDark,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isUp = quote?.isUp ?? true;
    final lineColor = isUp ? _green : _red;

    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stock info row
          if (quote != null) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote!.symbol,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.3,
                          color: brand.ink,
                        ),
                      ),
                      Text(
                        quote!.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: brand.inkSoft,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${quote!.currency} ${quote!.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: brand.ink,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: lineColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${isUp ? '+' : ''}${quote!.changePercent.toStringAsFixed(2)}%',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: lineColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
          ] else if (!loading) ...[
            Text(
              'Select a stock below',
              style: TextStyle(fontSize: 14, color: brand.inkSoft),
            ),
            const SizedBox(height: 16),
          ],

          // Chart area
          SizedBox(
            height: 140,
            child: loading
                ? const Center(child: CupertinoActivityIndicator())
                : error != null
                    ? Center(
                        child: Text(
                          error!,
                          style: TextStyle(fontSize: 12, color: brand.inkSoft),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : quote != null && quote!.chartPoints.isNotEmpty
                        ? _LineChart(
                            points: quote!.chartPoints,
                            color: lineColor,
                            isDark: isDark,
                          )
                        : Center(
                            child: Text(
                              'No chart data',
                              style: TextStyle(fontSize: 12, color: brand.inkSoft),
                            ),
                          ),
          ),

          const SizedBox(height: 14),

          // Range selector
          Row(
            children: StockService.rangeOptions.map((r) {
              final selected = r == range;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onRangeChanged(r),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    height: 28,
                    decoration: BoxDecoration(
                      color: selected
                          ? _blue.withValues(alpha: 0.12)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      r,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                        color: selected ? _blue : brand.inkSoft,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
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
    final padding = (maxY - minY) * 0.1;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minY: minY - padding,
        maxY: maxY + padding,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) =>
                isDark ? const Color(0xFF2C2C2E) : Colors.white,
            tooltipRoundedRadius: 10,
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      s.y.toStringAsFixed(2),
                      TextStyle(
                        color: color,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ))
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
            dotData: const FlDotData(show: false),
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

// ── Stock row ──────────────────────────────────────────────────────────────────

class _StockRow extends StatelessWidget {
  final StockInvestment stock;
  final double? currentPrice;
  final bool isSelected;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _StockRow({
    required this.stock,
    required this.currentPrice,
    required this.isSelected,
    required this.isDark,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final gainLossPct = currentPrice != null
        ? stock.gainLossPercent(currentPrice!)
        : null;
    final isUp = gainLossPct == null || gainLossPct >= 0;
    final trendColor = isUp ? _green : _red;
    final fmt = NumberFormat('#,##0.##');

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        _showActions(context);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? _stockAccent.withValues(alpha: isDark ? 0.12 : 0.07)
              : brand.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: isSelected
              ? Border.all(color: _stockAccent.withValues(alpha: 0.4), width: 1)
              : null,
        ),
        child: Row(
          children: [
            // Symbol badge
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _stockAccent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: Text(
                stock.symbol.length > 4
                    ? stock.symbol.substring(0, 4)
                    : stock.symbol,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _stockAccent,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Name + qty
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    stock.name ?? stock.symbol,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: brand.ink,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${fmt.format(stock.quantity)} shares @ ${stock.buyPrice.toStringAsFixed(2)}',
                    style: TextStyle(fontSize: 11, color: brand.inkSoft),
                  ),
                ],
              ),
            ),

            // Value + gain/loss
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (currentPrice != null) ...[
                  Text(
                    currentPrice!.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  if (gainLossPct != null)
                    Text(
                      '${isUp ? '+' : ''}${gainLossPct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: trendColor,
                      ),
                    ),
                ] else ...[
                  Text(
                    stock.buyPrice.toStringAsFixed(2),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: brand.inkSoft,
                      letterSpacing: -0.3,
                    ),
                  ),
                  Text(
                    'buy price',
                    style: TextStyle(fontSize: 11, color: brand.inkSoft),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showActions(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(stock.symbol),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              onEdit();
            },
            child: const Text('Edit'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            child: const Text('Delete'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

// ── Add / Edit Stock sheet ─────────────────────────────────────────────────────

class _AddEditStockSheet extends ConsumerStatefulWidget {
  final StockInvestment? existing;
  final Future<void> Function(StockInvestment) onSave;

  const _AddEditStockSheet({this.existing, required this.onSave});

  @override
  ConsumerState<_AddEditStockSheet> createState() => _AddEditStockSheetState();
}

class _AddEditStockSheetState extends ConsumerState<_AddEditStockSheet> {
  final _symbolCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _symbolFocus = FocusNode();

  bool _saving = false;
  bool _validating = false;
  StockQuote? _validatedQuote;
  String? _symbolError;

  // Symbol search
  List<StockSearchResult> _searchResults = [];

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final e = widget.existing!;
      _symbolCtrl.text = e.symbol;
      _qtyCtrl.text = e.quantity.toStringAsFixed(e.quantity == e.quantity.floorToDouble() ? 0 : 4);
      _priceCtrl.text = e.buyPrice.toStringAsFixed(2);
      _notesCtrl.text = e.notes ?? '';
    }
  }

  @override
  void dispose() {
    _symbolCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    _symbolFocus.dispose();
    super.dispose();
  }

  Future<void> _validateSymbol() async {
    final sym = _symbolCtrl.text.trim().toUpperCase();
    if (sym.isEmpty) return;
    setState(() {
      _validating = true;
      _symbolError = null;
      _validatedQuote = null;
    });
    final svc = ref.read(stockServiceProvider);
    final q = await svc.getQuote(sym, range: '1M');
    if (!mounted) return;
    setState(() {
      _validating = false;
      if (q != null) {
        _validatedQuote = q;
        _symbolCtrl.text = q.symbol;
        if (_priceCtrl.text.isEmpty) {
          _priceCtrl.text = q.price.toStringAsFixed(2);
        }
      } else {
        _symbolError = 'Symbol not found. Check the ticker and try again.';
      }
    });
  }

  Future<void> _searchSymbol(String query) async {
    if (query.trim().length < 2) {
      setState(() => _searchResults = []);
      return;
    }
    final svc = ref.read(stockServiceProvider);
    final results = await svc.search(query);
    if (!mounted) return;
    setState(() => _searchResults = results);
  }

  Future<void> _save() async {
    final sym = _symbolCtrl.text.trim().toUpperCase();
    final qty = double.tryParse(_qtyCtrl.text.replaceAll(',', ''));
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', ''));

    if (sym.isEmpty || qty == null || qty <= 0 || price == null || price < 0) {
      AppToast.show(context, 'Please fill in all required fields', type: AppToastType.error);
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final investment = StockInvestment(
      id: widget.existing?.id ?? '',
      symbol: sym,
      name: _validatedQuote?.name ?? widget.existing?.name,
      quantity: qty,
      buyPrice: price,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      createdAt: widget.existing?.createdAt ?? now,
      updatedAt: now,
    );

    await widget.onSave(investment);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.existing != null;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  decoration: BoxDecoration(
                    color: brand.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                child: Text(
                  isEditing ? 'Edit Stock' : 'Add Stock',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
              ),

              const SizedBox(height: 20),

              // Scrollable form
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Symbol field
                      _FieldLabel(label: 'Stock Symbol *'),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            child: _TextField(
                              controller: _symbolCtrl,
                              focusNode: _symbolFocus,
                              hint: 'e.g. AAPL, MSFT, TSLA',
                              textCapitalization: TextCapitalization.characters,
                              onChanged: (v) {
                                setState(() {
                                  _validatedQuote = null;
                                  _symbolError = null;
                                });
                                _searchSymbol(v);
                              },
                              error: _symbolError,
                              isDark: isDark,
                            ),
                          ),
                          const SizedBox(width: 10),
                          GestureDetector(
                            onTap: _validating ? null : _validateSymbol,
                            child: Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: _blue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              alignment: Alignment.center,
                              child: _validating
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: _blue,
                                      ),
                                    )
                                  : const Text(
                                      'Verify',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: _blue,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),

                      // Validated quote display
                      if (_validatedQuote != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: _green.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            children: [
                              const Icon(CupertinoIcons.checkmark_circle_fill,
                                  size: 14, color: _green),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${_validatedQuote!.name} · ${_validatedQuote!.currency} ${_validatedQuote!.price.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: _green,
                                      fontWeight: FontWeight.w500),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Search results
                      if (_searchResults.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: brand.surface,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            children: _searchResults.take(5).map((r) {
                              return GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _symbolCtrl.text = r.symbol;
                                    _searchResults = [];
                                    _validatedQuote = null;
                                  });
                                  _validateSymbol();
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 10),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 36,
                                        height: 36,
                                        decoration: BoxDecoration(
                                          color: _stockAccent.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(8),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          r.symbol.length > 4
                                              ? r.symbol.substring(0, 4)
                                              : r.symbol,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: _stockAccent,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              r.symbol,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: brand.ink,
                                              ),
                                            ),
                                            Text(
                                              r.name,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: brand.inkSoft,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        r.exchange,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: brand.inkSoft,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }).toList(),
                          ),
                        ),
                      ],

                      const SizedBox(height: 16),

                      // Quantity
                      _FieldLabel(label: 'Shares / Quantity *'),
                      const SizedBox(height: 6),
                      _TextField(
                        controller: _qtyCtrl,
                        hint: '0',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        isDark: isDark,
                      ),

                      const SizedBox(height: 16),

                      // Buy price
                      _FieldLabel(label: 'Buy Price per Share *'),
                      const SizedBox(height: 6),
                      _TextField(
                        controller: _priceCtrl,
                        hint: '0.00',
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        isDark: isDark,
                      ),

                      const SizedBox(height: 16),

                      // Notes
                      _FieldLabel(label: 'Notes (optional)'),
                      const SizedBox(height: 6),
                      _TextField(
                        controller: _notesCtrl,
                        hint: 'e.g. Bought during dip',
                        isDark: isDark,
                      ),

                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),

              // Save button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: GestureDetector(
                  onTap: _saving ? null : _save,
                  child: Container(
                    height: 52,
                    decoration: BoxDecoration(
                      color: _blue,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    alignment: Alignment.center,
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            isEditing ? 'Save Changes' : 'Add to Portfolio',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                              letterSpacing: -0.2,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String icon;
  final String title;
  final String subtitle;
  final Widget? action;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(icon, style: const TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: brand.ink,
                letterSpacing: -0.3,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(fontSize: 14, color: brand.inkSoft, height: 1.47),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 24),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

// ── Shared form components ─────────────────────────────────────────────────────

class _FieldLabel extends StatelessWidget {
  final String label;
  const _FieldLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: brand.inkSoft,
        letterSpacing: -0.1,
      ),
    );
  }
}

class _TextField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode? focusNode;
  final String hint;
  final TextInputType keyboardType;
  final TextCapitalization textCapitalization;
  final ValueChanged<String>? onChanged;
  final String? error;
  final bool isDark;

  const _TextField({
    required this.controller,
    this.focusNode,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.textCapitalization = TextCapitalization.none,
    this.onChanged,
    this.error,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(12),
            border: error != null
                ? Border.all(color: _red.withValues(alpha: 0.6), width: 1)
                : null,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            textCapitalization: textCapitalization,
            onChanged: onChanged,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: brand.ink,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              hintText: hint,
              hintStyle: TextStyle(
                fontSize: 15,
                color: brand.inkSoft.withValues(alpha: 0.6),
              ),
              isDense: true,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 4),
          Text(
            error!,
            style: const TextStyle(fontSize: 12, color: _red),
          ),
        ],
      ],
    );
  }
}
