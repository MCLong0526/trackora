import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/precious_metal.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import 'add_edit_metal_screen.dart';

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
  int _tab = 0; // 0 = gold, 1 = silver

  static const _metals = [MetalType.gold, MetalType.silver];
  MetalType get _active => _metals[_tab];

  Future<void> _openAdd(MetalAction action) async {
    await Navigator.push<dynamic>(
      context,
      CupertinoPageRoute(
        builder: (_) => AddEditMetalScreen(
          initialMetal: _active,
          initialAction: action,
        ),
      ),
    );
  }

  Future<void> _openEdit(PreciousMetal metal) async {
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

    final metrics = _calcMetrics(metals);
    final activeM = metrics[_active]!;
    final filtered = metals
        .where((m) => m.metalType == _active)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(title: const Text('Gold & Silver')),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Selector ──────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: _Selector(
                  selected: _tab,
                  onChanged: (i) => setState(() => _tab = i),
                  brand: brand,
                ),
              ),
            ),

            // ── Hero card ─────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  switchInCurve: Curves.easeOutCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.03, 0),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
                  ),
                  child: _HeroCard(
                    key: ValueKey(_active),
                    metalType: _active,
                    metrics: activeM,
                    symbol: symbol,
                    isDark: isDark,
                  ),
                ),
              ),
            ),

            // ── Buy / Sell ────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _Btn(
                        label: 'Buy ${_active.label}',
                        icon: CupertinoIcons.arrow_down_circle_fill,
                        color: AppColors.income,
                        onTap: () => _openAdd(MetalAction.buy),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _Btn(
                        label: 'Sell ${_active.label}',
                        icon: CupertinoIcons.arrow_up_circle_fill,
                        color: AppColors.expense,
                        onTap: () => _openAdd(MetalAction.sell),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Transactions header ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 26, 20, 10),
                child: Row(
                  children: [
                    Text(
                      'Transactions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                      ),
                    ),
                    if (filtered.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: _active.primaryColor.withValues(alpha: 0.13),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${filtered.length}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: _active.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            // ── List / Empty ──────────────────────────────────────────────
            if (filtered.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 60),
                  child: _Empty(
                    metalType: _active,
                    onBuy: () => _openAdd(MetalAction.buy),
                    brand: brand,
                  ),
                ),
              )
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 60),
                  child: _TxGroup(
                    items: filtered,
                    symbol: symbol,
                    brand: brand,
                    onTap: _openEdit,
                  ),
                ),
              ),
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

  double? get avgBuy => buyWeightGrams > 0 ? buyAmount / buyWeightGrams : null;
  double? get estValue =>
      holdGrams > 0 && latestPrice != null ? holdGrams * latestPrice! : null;
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
// Selector  — matches app segmented-pill style
// ─────────────────────────────────────────────────────────────────────────────

class _Selector extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onChanged;
  final BrandColors brand;

  const _Selector({
    required this.selected,
    required this.onChanged,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    final metals = MetalType.values;
    return Container(
      height: 42,
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(3),
      child: Row(
        children: List.generate(metals.length, (i) {
          final m = metals[i];
          final isActive = i == selected;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeInOut,
                decoration: BoxDecoration(
                  color: isActive
                      ? m.primaryColor.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  border: isActive
                      ? Border.all(
                          color: m.primaryColor.withValues(alpha: 0.30),
                        )
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SmallIngot(metal: m),
                    const SizedBox(width: 6),
                    Text(
                      m.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        color: isActive ? m.primaryColor : brand.inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero Card — same Stack layout pattern as the dashboard spending card
// ─────────────────────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final MetalType metalType;
  final _Metrics metrics;
  final String symbol;
  final bool isDark;

  const _HeroCard({
    super.key,
    required this.metalType,
    required this.metrics,
    required this.symbol,
    required this.isDark,
  });

  Color get _bg => isDark ? _bgDark : _bgLight;

  Color get _bgLight =>
      metalType == MetalType.gold
          ? const Color(0xFFFFF8E1)
          : const Color(0xFFEEF1F5);

  Color get _bgDark =>
      metalType == MetalType.gold
          ? const Color(0xFF1E1A06)
          : const Color(0xFF10131A);

  Color get _ink =>
      isDark
          ? (metalType == MetalType.gold
              ? const Color(0xFFF5E6C0)
              : const Color(0xFFD0D8E4))
          : (metalType == MetalType.gold
              ? const Color(0xFF2E1A00)
              : const Color(0xFF18202A));

  Color get _soft =>
      isDark
          ? (metalType == MetalType.gold
              ? const Color(0xFFB89050)
              : const Color(0xFF7888A0))
          : (metalType == MetalType.gold
              ? const Color(0xFF9B7035)
              : const Color(0xFF5A6878));

  Color get _shapeColor =>
      metalType.primaryColor.withValues(alpha: isDark ? 0.18 : 0.14);

  Color get _pillBg =>
      isDark
          ? Colors.white.withValues(alpha: 0.09)
          : Colors.white.withValues(alpha: 0.65);

  @override
  Widget build(BuildContext context) {
    final hasHoldings = metrics.holdGrams > 0;
    final estValue = metrics.estValue;
    final avgBuy = metrics.avgBuy;

    return Container(
      height: 200,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: metalType.primaryColor.withValues(
              alpha: isDark ? 0.18 : 0.10,
            ),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.07),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Decorative shape 1
          Positioned(
            right: 52,
            top: 8,
            child: Transform.rotate(
              angle: 0.34,
              child: Container(
                width: 90,
                height: 110,
                decoration: BoxDecoration(
                  color: _shapeColor,
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
            ),
          ),
          // Decorative shape 2
          Positioned(
            right: -4,
            top: 50,
            child: Transform.rotate(
              angle: -0.18,
              child: Container(
                width: 78,
                height: 82,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.05)
                      : Colors.white.withValues(alpha: 0.42),
                  borderRadius: BorderRadius.circular(22),
                ),
              ),
            ),
          ),
          // Ingot bar (right)
          Positioned(
            right: 18,
            top: 0,
            bottom: 0,
            child: Center(
              child: _LargeIngot(metalType: metalType, isDark: isDark),
            ),
          ),
          // Metal chip (top-left)
          Positioned(
            left: 22,
            top: 20,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: _pillBg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _SmallIngot(metal: metalType),
                  const SizedBox(width: 6),
                  Text(
                    metalType.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Weight — large number
          Positioned(
            left: 22,
            right: 130,
            top: 60,
            child: Column(
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
                    Flexible(
                      child: Text(
                        _grams(metrics.holdGrams),
                        style: TextStyle(
                          fontSize: 44,
                          fontWeight: FontWeight.w900,
                          color: _ink,
                          height: 1.0,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'g',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: _soft,
                        height: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Bottom stats pill
          Positioned(
            left: 22,
            right: 22,
            bottom: 18,
            child: Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: _pillBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.18),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _StatItem(
                      label: 'Est. Value',
                      value: estValue != null
                          ? formatMoney(symbol, estValue)
                          : hasHoldings
                          ? 'No price'
                          : '—',
                      ink: _ink,
                      soft: _soft,
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 28,
                    color: _soft.withValues(alpha: 0.20),
                  ),
                  Expanded(
                    child: _StatItem(
                      label: 'Avg Buy',
                      value: avgBuy != null
                          ? '${formatMoney(symbol, avgBuy)}/g'
                          : '—',
                      ink: _ink,
                      soft: _soft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color ink;
  final Color soft;

  const _StatItem({
    required this.label,
    required this.value,
    required this.ink,
    required this.soft,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: soft,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: ink,
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
// Buy / Sell button
// ─────────────────────────────────────────────────────────────────────────────

class _Btn extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _Btn({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  State<_Btn> createState() => _BtnState();
}

class _BtnState extends State<_Btn> with SingleTickerProviderStateMixin {
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
    final brand = context.brand;
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
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.field),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.14),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, color: widget.color, size: 16),
              ),
              const SizedBox(width: 9),
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

// ─────────────────────────────────────────────────────────────────────────────
// Grouped transaction list — mirrors the dashboard expense list
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
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
            // Icon
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
            // Info
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
            // Amount
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${isBuy ? '-' : '+'}${formatMoney(symbol, metal.totalAmount)}',
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
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
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
// Large ingot bar (right side of hero card)
// ─────────────────────────────────────────────────────────────────────────────

class _LargeIngot extends StatelessWidget {
  final MetalType metalType;
  final bool isDark;

  const _LargeIngot({required this.metalType, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.18, // subtle tilt
      child: Container(
        decoration: BoxDecoration(
          boxShadow: [
            BoxShadow(
              color: metalType.primaryColor.withValues(alpha: isDark ? 0.40 : 0.32),
              blurRadius: 24,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: CustomPaint(
          size: const Size(90, 54),
          painter: _LargeIngotPainter(metal: metalType, isDark: isDark),
        ),
      ),
    );
  }
}

class _LargeIngotPainter extends CustomPainter {
  final MetalType metal;
  final bool isDark;

  const _LargeIngotPainter({required this.metal, required this.isDark});

  bool get _gold => metal == MetalType.gold;

  @override
  void paint(Canvas canvas, Size size) {
    final light  = _gold ? const Color(0xFFFFEE88) : const Color(0xFFEDF4FA);
    final mid    = _gold ? const Color(0xFFD4AF37) : const Color(0xFFB8C8D8);
    final dark   = _gold ? const Color(0xFF9A7020) : const Color(0xFF7A8A98);
    final depth  = _gold ? const Color(0xFF6A4E10) : const Color(0xFF4A5A68);
    final r = Radius.circular(size.height * 0.18);

    // Depth layer — shifted to simulate 3-D thickness
    final depthRect = Rect.fromLTWH(5, 7, size.width, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(depthRect, r),
      Paint()..color = depth.withValues(alpha: 0.65),
    );

    // Main face
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rr = RRect.fromRectAndRadius(rect, r);
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, mid, dark],
          stops: const [0.0, 0.48, 1.0],
        ).createShader(rect),
    );

    // Outer bevel edge
    canvas.drawRRect(
      rr,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    // Inner raised border (hallmark channel)
    final bevel = 6.0;
    final innerRect = Rect.fromLTWH(bevel, bevel, size.width - bevel * 2, size.height - bevel * 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(innerRect, Radius.circular(size.height * 0.10)),
      Paint()
        ..color = depth.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0,
    );

    // Primary highlight shine
    canvas.drawLine(
      Offset(size.width * 0.13, size.height * 0.27),
      Offset(size.width * 0.68, size.height * 0.27),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.60)
        ..strokeWidth = size.height * 0.075
        ..strokeCap = StrokeCap.round,
    );

    // Secondary soft highlight
    canvas.drawLine(
      Offset(size.width * 0.13, size.height * 0.44),
      Offset(size.width * 0.42, size.height * 0.44),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..strokeWidth = size.height * 0.05
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_LargeIngotPainter o) => o.metal != metal || o.isDark != isDark;
}

// ─────────────────────────────────────────────────────────────────────────────
// Small ingot badge (used in selector + hero chip)
// ─────────────────────────────────────────────────────────────────────────────

class _SmallIngot extends StatelessWidget {
  final MetalType metal;
  const _SmallIngot({required this.metal});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(18, 11),
      painter: _IngotPainter(metal: metal),
    );
  }
}

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
