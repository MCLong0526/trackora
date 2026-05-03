import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/expense.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/month_filter_bar.dart';
import '../../widgets/section_card.dart';

/// Minimal statistics: just two cards.
/// 1. Weekly line chart (with prev/next nav).
/// 2. Monthly category breakdown (with month filter).
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  late DateTime _weekStart;
  // Toggle on the Weekly chart: include or exclude bills + installment-paid
  // entries. Excluding mirrors the Home/Budget rule so users can see what
  // they're really spending on day-to-day stuff.
  bool _includeBillsAndInstallments = true;

  @override
  void initState() {
    super.initState();
    _weekStart = _startOfWeek(DateTime.now());
  }

  DateTime _startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  /// True if [e] is a bill OR installment-paid entry (created via the
  /// installment "Mark paid" flow which tags the note with "(installment)").
  bool _isFixed(Expense e) =>
      e.category == 'Bills' || e.note.contains('(installment)');

  @override
  Widget build(BuildContext context) {
    final monthlyExpensesAsync = ref.watch(expensesProvider);
    final allExpensesAsync = ref.watch(allExpensesProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final month = ref.watch(selectedMonthProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          Text(
            context.t('stats.title'),
            style: Theme.of(context).textTheme.displayMedium,
          ),
          const SizedBox(height: 22),

          // ── Weekly line chart ──────────────────────────────
          allExpensesAsync.when(
            data: (allItems) {
              // Repository → service → screen. We start from all expenses,
              // then filter in-memory based on the toggle.
              final allExpenses = allItems
                  .where((e) => e.type == EntryType.expense)
                  .where((e) => _includeBillsAndInstallments || !_isFixed(e))
                  .toList();
              return _WeeklyLineCard(
                expenses: allExpenses,
                symbol: symbol,
                weekStart: _weekStart,
                includeFixed: _includeBillsAndInstallments,
                onToggleIncludeFixed: (v) =>
                    setState(() => _includeBillsAndInstallments = v),
                onPrevious: () => setState(
                  () =>
                      _weekStart = _weekStart.subtract(const Duration(days: 7)),
                ),
                onNext: () => setState(
                  () => _weekStart = _weekStart.add(const Duration(days: 7)),
                ),
              );
            },
            loading: () => const _LoadingCard(),
            error: (e, _) =>
                SectionCard(child: Text('${context.t('common.error')}: $e')),
          ),

          const SizedBox(height: 14),

          // ── Month filter for category chart ───────────────
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
            child: Text(
              DateFormat('MMMM yyyy').format(month),
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          MonthFilterBar(
            selectedMonth: month,
            onMonthSelected: (m) =>
                ref.read(selectedMonthProvider.notifier).state = m,
          ),
          const SizedBox(height: 14),

          // ── Monthly category breakdown ────────────────────
          monthlyExpensesAsync.when(
            data: (items) {
              final expenses = items
                  .where((e) => e.type == EntryType.expense)
                  .toList();
              return _CategoryCard(
                expenses: expenses,
                symbol: symbol,
                month: month,
              );
            },
            loading: () => const _LoadingCard(),
            error: (e, _) =>
                SectionCard(child: Text('${context.t('common.error')}: $e')),
          ),
        ],
      ),
    );
  }
}


class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      padding: const EdgeInsets.all(40),
      child: const Center(child: CupertinoActivityIndicator()),
    );
  }
}

// ── Weekly line ───────────────────────────────────────────────

class _WeeklyLineCard extends StatelessWidget {
  final List<Expense> expenses;
  final String symbol;
  final DateTime weekStart;
  final bool includeFixed;
  final ValueChanged<bool> onToggleIncludeFixed;
  final VoidCallback onPrevious;
  final VoidCallback onNext;

  const _WeeklyLineCard({
    required this.expenses,
    required this.symbol,
    required this.weekStart,
    required this.includeFixed,
    required this.onToggleIncludeFixed,
    required this.onPrevious,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chartAccent = isDark ? brand.accent : brand.accentDark;
    final weekEnd = weekStart.add(const Duration(days: 7));
    final dailyTotals = List<double>.filled(7, 0);
    for (final e in expenses) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      if (!d.isBefore(weekStart) && d.isBefore(weekEnd)) {
        final i = d.difference(weekStart).inDays;
        if (i >= 0 && i < 7) dailyTotals[i] += e.amount;
      }
    }
    final total = dailyTotals.fold<double>(0, (s, v) => s + v);
    final maxV = dailyTotals.fold<double>(0, (m, v) => v > m ? v : m);
    final chartMax = maxV == 0 ? 1.0 : maxV * 1.25;
    // Build the bar once so `showingTooltipIndicators` below can refer to
    // the same instance fl_chart matches against.
    final spots = List<FlSpot>.generate(
      7,
      (i) => FlSpot(i.toDouble(), dailyTotals[i]),
    );
    final lineBar = LineChartBarData(
      spots: spots,
      isCurved: true,
      color: chartAccent,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, _) => spot.y > 0,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
          radius: 3.5,
          color: chartAccent,
          strokeWidth: 2,
          strokeColor: brand.surface,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: chartAccent.withValues(alpha: isDark ? 0.20 : 0.10),
      ),
    );
    final entriesThisWeek = expenses.where((e) {
      final d = DateTime(e.date.year, e.date.month, e.date.day);
      return !d.isBefore(weekStart) && d.isBefore(weekEnd);
    }).length;
    final summary = total == 0
        ? context.t('stats.noWeeklySpend')
        : context
              .t('stats.weeklySummary')
              .replaceFirst('{amount}', formatMoney(symbol, total))
              .replaceFirst('{count}', '$entriesThisWeek')
              .replaceFirst(
                '{entries}',
                entriesThisWeek == 1
                    ? context.t('common.entry')
                    : context.t('common.entries'),
              );

    final dateLabel =
        '${DateFormat('MMM d').format(weekStart)} – '
        '${DateFormat('MMM d').format(weekEnd.subtract(const Duration(days: 1)))}';

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.mint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.chart_bar,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('stats.weeklySpend'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      dateLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              _navButton(context, CupertinoIcons.chevron_left, onPrevious),
              const SizedBox(width: 6),
              _navButton(context, CupertinoIcons.chevron_right, onNext),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            formatMoney(symbol, total),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 4),
          Text(summary, style: TextStyle(color: brand.inkSoft, fontSize: 12)),
          const SizedBox(height: 12),
          // ── Include / Exclude bills + installments toggle ─
          _IncludeFixedToggle(
            includeFixed: includeFixed,
            onChanged: onToggleIncludeFixed,
          ),
          const SizedBox(height: 14),
          SizedBox(
            // A bit taller so the inline value labels above each dot have
            // room to breathe.
            height: 200,
            child: LineChart(
              LineChartData(
                minX: 0,
                maxX: 6,
                minY: 0,
                // Slightly higher headroom so the topmost value label
                // doesn't clip against the card edge.
                maxY: chartMax * 1.05,
                gridData: FlGridData(
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) =>
                      FlLine(color: brand.divider, strokeWidth: 1),
                ),
                borderData: FlBorderData(show: false),
                // Persistent inline labels do the heavy lifting now; we
                // still render a tooltip on tap (re-using the same style)
                // so users who do tap get a clean confirmation.
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => AppColors.ink,
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    tooltipMargin: 8,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    getTooltipItems: (spots) => spots
                        .map(
                          (spot) => LineTooltipItem(
                            formatMoney(symbol, spot.y),
                            const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 11,
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      // Force one tick per day; without this fl_chart can call
                      // the builder at half-step values and we end up rendering
                      // labels twice per day.
                      interval: 1,
                      getTitlesWidget: (v, _) {
                        // Skip non-integer ticks the chart asks us to draw.
                        if (v != v.roundToDouble()) return const SizedBox();
                        final i = v.toInt();
                        if (i < 0 || i >= 7) return const SizedBox();
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            DateFormat(
                              'E',
                            ).format(weekStart.add(Duration(days: i))),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: brand.inkSoft,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                lineBarsData: [lineBar],
                // Persistent labels on every non-zero day so the user can
                // read amounts without tapping. fl_chart matches by
                // reference, so we re-use `lineBar` and `spots` from above.
                showingTooltipIndicators: [
                  for (int i = 0; i < 7; i++)
                    if (dailyTotals[i] > 0)
                      ShowingTooltipIndicators([
                        LineBarSpot(lineBar, 0, spots[i]),
                      ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _navButton(BuildContext context, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: context.brand.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 17, color: context.brand.ink),
      ),
    );
  }
}

// ── Toggle: include/exclude bills & installments ──────────────

class _IncludeFixedToggle extends StatelessWidget {
  final bool includeFixed;
  final ValueChanged<bool> onChanged;

  const _IncludeFixedToggle({
    required this.includeFixed,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final selectedBg = brand.accentDark;
    final selectedFg = foregroundOn(selectedBg);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          _segment(
            label: context.t('stats.includeFixed'),
            selected: includeFixed,
            selectedBg: selectedBg,
            selectedFg: selectedFg,
            unselectedFg: brand.ink,
            onTap: () => onChanged(true),
          ),
          _segment(
            label: context.t('stats.excludeFixed'),
            selected: !includeFixed,
            selectedBg: selectedBg,
            selectedFg: selectedFg,
            unselectedFg: brand.ink,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required bool selected,
    required Color selectedBg,
    required Color selectedFg,
    required Color unselectedFg,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? selectedBg : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: selected ? selectedFg : unselectedFg,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Monthly category breakdown ────────────────────────────────

// ── Category card (interactive) ──────────────────────────────
//
// Tap or drag a slice → that slice grows + the centre label shows that
// category's name, amount, and percentage. Tapping a legend row does
// the same. Tapping the chart again (or a background area) returns to
// the overview centre label.
class _CategoryCard extends StatefulWidget {
  final List<Expense> expenses;
  final String symbol;
  final DateTime month;
  const _CategoryCard({
    required this.expenses,
    required this.symbol,
    required this.month,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  /// Index into the sorted-by-amount list that's currently focused.
  /// Null = no selection (centre shows the grand total).
  int? _touchedIndex;

  @override
  Widget build(BuildContext context) {
    if (widget.expenses.isEmpty) {
      final brand = context.brand;
      return SectionCard(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            context.t('stats.noCategorySpend'),
            style: TextStyle(color: brand.inkSoft),
          ),
        ),
      );
    }

    final Map<String, double> totals = {};
    for (final e in widget.expenses) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = widget.expenses.fold<double>(0, (s, e) => s + e.amount);

    // Clamp the touched index in case the data shrinks (e.g. a category
    // got deleted while a slice was selected).
    final touched =
        (_touchedIndex != null && _touchedIndex! < sorted.length)
            ? _touchedIndex
            : null;

    final brand = context.brand;
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.lilac,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.chart_pie_fill,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('stats.byCategory'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      DateFormat('MMMM yyyy').format(widget.month),
                      style: TextStyle(
                        fontSize: 11,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (touched != null)
                GestureDetector(
                  onTap: () => setState(() => _touchedIndex = null),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      CupertinoIcons.xmark_circle_fill,
                      size: 18,
                      color: brand.inkSoft,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 18),
          // Donut + centre label.
          Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      sectionsSpace: 3,
                      centerSpaceRadius: 60,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, response) {
                          if (!event.isInterestedForInteractions ||
                              response == null ||
                              response.touchedSection == null) {
                            return;
                          }
                          final idx =
                              response.touchedSection!.touchedSectionIndex;
                          if (idx < 0) {
                            setState(() => _touchedIndex = null);
                          } else {
                            setState(() => _touchedIndex = idx);
                          }
                        },
                      ),
                      sections: List.generate(sorted.length, (i) {
                        final entry = sorted[i];
                        final s = styleFor(entry.key);
                        final isTouched = i == touched;
                        return PieChartSectionData(
                          value: entry.value,
                          color: s.accent,
                          radius: isTouched ? 26 : 20,
                          title: '',
                          borderSide: isTouched
                              ? BorderSide(color: brand.surface, width: 3)
                              : BorderSide.none,
                        );
                      }),
                    ),
                  ),
                  _CenterLabel(
                    sorted: sorted,
                    touched: touched,
                    total: total,
                    symbol: widget.symbol,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              touched == null
                  ? context.t('stats.tapSliceHint')
                  : context.categoryLabel(sorted[touched].key),
              style: TextStyle(
                fontSize: 11,
                color: brand.inkSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: brand.divider),
          const SizedBox(height: 12),
          // Interactive legend — tap a row to focus its slice.
          for (int i = 0; i < sorted.length; i++)
            _LegendRow(
              index: i,
              entry: sorted[i],
              total: total,
              symbol: widget.symbol,
              focused: touched == i,
              onTap: () => setState(
                () => _touchedIndex = touched == i ? null : i,
              ),
            ),
        ],
      ),
    );
  }
}

class _CenterLabel extends StatelessWidget {
  final List<MapEntry<String, double>> sorted;
  final int? touched;
  final double total;
  final String symbol;

  const _CenterLabel({
    required this.sorted,
    required this.touched,
    required this.total,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    if (touched == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            formatMoney(symbol, total),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            context.t('common.total'),
            style: TextStyle(fontSize: 10, color: brand.inkSoft),
          ),
        ],
      );
    }
    final entry = sorted[touched!];
    final pct = total == 0 ? 0 : (entry.value / total * 100);
    return SizedBox(
      width: 110,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.categoryLabel(entry.key),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatMoney(symbol, entry.value),
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            '${pct.toStringAsFixed(1)}%',
            style: TextStyle(
              fontSize: 11,
              color: brand.inkSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  final int index;
  final MapEntry<String, double> entry;
  final double total;
  final String symbol;
  final bool focused;
  final VoidCallback onTap;

  const _LegendRow({
    required this.index,
    required this.entry,
    required this.total,
    required this.symbol,
    required this.focused,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final s = styleFor(entry.key);
    final pct = total == 0 ? 0.0 : entry.value / total;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: focused ? brand.background : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: brand.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(s.icon, size: 15, color: s.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.categoryLabel(entry.key),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        '${(pct * 100).toStringAsFixed(0)}%',
                        style: TextStyle(
                          fontSize: 11,
                          color: brand.inkSoft,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        formatMoney(symbol, entry.value),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 5,
                      backgroundColor: brand.divider,
                      valueColor: AlwaysStoppedAnimation(s.accent),
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
