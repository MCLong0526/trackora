import 'dart:io';
import 'dart:ui' as ui;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/expense.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';

/// Stats screen, rebuilt around a single global filter (Week / Month /
/// Year / All) plus a "Exclude bills + installments" toggle. Three
/// optional sections stack below the filter: line chart, important-data
/// summary, and donut chart. Each section can be individually hidden
/// from the "Manage visibility" sheet — and hidden sections are also
/// excluded from the share/screenshot capture.
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  // Default landing view is Weekly Spend, per spec.
  _StatsPeriod _period = _StatsPeriod.week;
  bool _excludeFixed = true;
  // Anchor used to step through periods. Interpreted relative to
  // [_period]: start of week / start of month / Jan 1 of year. Ignored
  // for "All".
  late DateTime _anchor;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _anchor = _startOfWeek(DateTime.now());
  }

  bool _isFixed(Expense e) =>
      e.category == 'Bills' || e.note.contains('(installment)');

  _StatsRange _currentRange(BuildContext context) {
    switch (_period) {
      case _StatsPeriod.week:
        final start = _startOfWeek(_anchor);
        final end = start.add(const Duration(days: 7));
        return _StatsRange(
          start: start,
          endExclusive: end,
          label:
              '${DateFormat('MMM d').format(start)} – '
              '${DateFormat('MMM d').format(end.subtract(const Duration(days: 1)))}',
        );
      case _StatsPeriod.month:
        final start = DateTime(_anchor.year, _anchor.month, 1);
        return _StatsRange(
          start: start,
          endExclusive: DateTime(_anchor.year, _anchor.month + 1, 1),
          label: DateFormat('MMMM yyyy').format(start),
        );
      case _StatsPeriod.year:
        final start = DateTime(_anchor.year, 1, 1);
        return _StatsRange(
          start: start,
          endExclusive: DateTime(_anchor.year + 1, 1, 1),
          label: DateFormat('yyyy').format(start),
        );
      case _StatsPeriod.all:
        return _StatsRange(
          start: null,
          endExclusive: null,
          label: context.t('stats.filterAll'),
        );
    }
  }

  static DateTime _startOfWeek(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - DateTime.monday));
  }

  bool _inRange(Expense e, _StatsRange r) {
    final d = DateTime(e.date.year, e.date.month, e.date.day);
    if (r.start != null && d.isBefore(r.start!)) return false;
    if (r.endExclusive != null && !d.isBefore(r.endExclusive!)) return false;
    return true;
  }

  void _step(int dir) {
    setState(() {
      switch (_period) {
        case _StatsPeriod.week:
          _anchor = _startOfWeek(_anchor).add(Duration(days: 7 * dir));
          break;
        case _StatsPeriod.month:
          _anchor = DateTime(_anchor.year, _anchor.month + dir, 1);
          break;
        case _StatsPeriod.year:
          _anchor = DateTime(_anchor.year + dir, 1, 1);
          break;
        case _StatsPeriod.all:
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final allExpensesAsync = ref.watch(allExpensesProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final visibleSections = ref.watch(statsSectionsVisibilityProvider);
    final range = _currentRange(context);

    return SafeArea(
      child: allExpensesAsync.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('${context.t('common.error')}: $e'),
          ),
        ),
        data: (allItems) {
          // Apply the exclude-fixed toggle once for expense aggregations,
          // then narrow by range in each section.
          final allExpenses = allItems
              .where((e) => e.type == EntryType.expense)
              .where((e) => !_excludeFixed || !_isFixed(e))
              .toList();
          final allIncome = allItems
              .where((e) => e.type == EntryType.income)
              .toList();

          final rangedExpenses = allExpenses
              .where((e) => _inRange(e, range))
              .toList();
          final rangedIncome = allIncome
              .where((e) => _inRange(e, range))
              .toList();

          // Filter card is always rendered as part of the report — the
          // user wants the snapshot to include the active filter so the
          // numbers are interpretable on their own.
          final filterCard = _FilterCard(
            period: _period,
            excludeFixed: _excludeFixed,
            rangeLabel: range.label,
            showNav: _period != _StatsPeriod.all,
            onPeriodChanged: (p) {
              setState(() {
                _period = p;
                // Reset the anchor when the user switches periods so they
                // always land on the *current* slice (today's week / month
                // / year) — otherwise stepping through one period leaves
                // a stale anchor when the user flips to another.
                final now = DateTime.now();
                switch (p) {
                  case _StatsPeriod.week:
                    _anchor = _startOfWeek(now);
                    break;
                  case _StatsPeriod.month:
                    _anchor = DateTime(now.year, now.month, 1);
                    break;
                  case _StatsPeriod.year:
                    _anchor = DateTime(now.year, 1, 1);
                    break;
                  case _StatsPeriod.all:
                    break;
                }
              });
            },
            onExcludeChanged: (v) => setState(() => _excludeFixed = v),
            onPrev: () => _step(-1),
            onNext: () => _step(1),
          );

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 1. Top action bar ────────────────────────
                _TopActionBar(
                  onManage: () => _showVisibilitySheet(context),
                  onShare: _isSharing ? null : () => _shareSnapshot(context),
                ),
                const SizedBox(height: 14),

                // ── 2..5. Report (everything that goes into the
                // exported snapshot). The capture path renders a
                // separate Overlay copy of this same column; this
                // RepaintBoundary is left in place so callers (e.g.
                // future widget tests) can still snapshot what's on
                // screen if they want to.
                _buildReport(
                  filterCard: filterCard,
                  visibleSections: visibleSections,
                  rangedExpenses: rangedExpenses,
                  rangedIncome: rangedIncome,
                  allExpenses: allExpenses,
                  range: range,
                  symbol: symbol,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Manage-visibility sheet ──────────────────────────────────
  void _showVisibilitySheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, ref, _) {
          final visible = ref.watch(statsSectionsVisibilityProvider);
          final notifier = ref.read(statsSectionsVisibilityProvider.notifier);
          final items = [
            ('lineChart', context.t('stats.section.lineChart')),
            ('importantData', context.t('stats.section.importantData')),
            ('donutChart', context.t('stats.section.donutChart')),
          ];
          return _VisibilitySheet(
            title: context.t('stats.customizeSections'),
            footnote: context.t('customize.keepOneVisible'),
            children: [
              for (final (id, label) in items)
                _VisibilitySwitchRow(
                  label: label,
                  visible: visible.contains(id),
                  canHide: visible.length > 1 || !visible.contains(id),
                  onChanged: (value) => notifier.setVisible(id, value),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Builds the report column shown on screen *and* used to render the
  /// off-screen snapshot. Order:
  ///   1. (Optional) Report header — only when `forReport: true`.
  ///   2. Filter card
  ///   3. Overview / insights
  ///   4. Single swipeable charts card containing line + donut.
  Widget _buildReport({
    required Widget filterCard,
    required Set<String> visibleSections,
    required List<Expense> rangedExpenses,
    required List<Expense> rangedIncome,
    required List<Expense> allExpenses,
    required _StatsRange range,
    required String symbol,
    bool forReport = false,
  }) {
    final children = <Widget>[];

    if (forReport) {
      children.add(
        _ReportHeader(
          rangeLabel: range.label,
          period: _period,
          excludeFixed: _excludeFixed,
        ),
      );
      children.add(const SizedBox(height: 14));
    }

    children.add(filterCard);
    children.add(const SizedBox(height: 14));

    if (visibleSections.contains('importantData')) {
      children.add(
        _OverviewCard(
          expenses: rangedExpenses,
          income: rangedIncome,
          symbol: symbol,
          rangeLabel: range.label,
          // Tile taps don't make sense in the static report capture.
          onTapExpenses: forReport || rangedExpenses.isEmpty
              ? null
              : () => _showRecordsSheet(
                  title: context.t('stats.expenseRecords'),
                  records: rangedExpenses,
                  symbol: symbol,
                  rangeLabel: range.label,
                ),
          onTapIncome: forReport || rangedIncome.isEmpty
              ? null
              : () => _showRecordsSheet(
                  title: context.t('stats.incomeRecords'),
                  records: rangedIncome,
                  symbol: symbol,
                  rangeLabel: range.label,
                ),
        ),
      );
      children.add(const SizedBox(height: 14));
    }

    // Combined swipeable charts card. The line-chart page is dropped
    // when the user picks "All" since the line chart has no meaningful
    // representation across all-time data.
    final showLine = visibleSections.contains('lineChart') &&
        _period != _StatsPeriod.all;
    final showDonut = visibleSections.contains('donutChart');
    if (showLine || showDonut) {
      children.add(
        _ChartsCarousel(
          showLine: showLine,
          showDonut: showDonut,
          allExpenses: allExpenses,
          rangedExpenses: rangedExpenses,
          range: range,
          period: _period,
          symbol: symbol,
          // The PageView gestures fight with the share-rendering pass —
          // disable swiping in the report capture and lay both charts out
          // stacked instead.
          stacked: forReport,
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }

  void _showRecordsSheet({
    required String title,
    required List<Expense> records,
    required String symbol,
    required String rangeLabel,
  }) {
    HapticFeedback.selectionClick();
    final sorted = [...records]..sort((a, b) => b.date.compareTo(a.date));
    final total = sorted.fold<double>(0, (s, e) => s + e.amount);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
          ),
          child: _GenericRecordsSheet(
            title: title,
            records: sorted,
            total: total,
            symbol: symbol,
            rangeLabel: rangeLabel,
          ),
        ),
      ),
    );
  }

  // ── Screenshot / share ───────────────────────────────────────
  //
  // The on-screen tree lives inside a SingleChildScrollView, so a
  // RepaintBoundary placed there only ever paints the visible viewport.
  // To capture the *whole* report we render a fresh, full-height copy
  // off-screen via an OverlayEntry, wait for layout, snapshot it from a
  // dedicated boundary key, and tear down the overlay.
  Future<void> _shareSnapshot(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final failedMsg = context.t('stats.exportFailed');
    setState(() => _isSharing = true);
    final overlay = Overlay.of(context, rootOverlay: true);
    final captureKey = GlobalKey();
    final mediaSize = MediaQuery.sizeOf(context);
    final brand = context.brand;
    final allItems = ref.read(allExpensesProvider).valueOrNull ?? const [];
    final symbol = ref.read(currencySymbolProvider).valueOrNull ?? '\$';
    final visibleSections = ref.read(statsSectionsVisibilityProvider);
    final range = _currentRange(context);

    final allExpenses = allItems
        .where((e) => e.type == EntryType.expense)
        .where((e) => !_excludeFixed || !_isFixed(e))
        .toList();
    final allIncome = allItems
        .where((e) => e.type == EntryType.income)
        .toList();
    final rangedExpenses = allExpenses
        .where((e) => _inRange(e, range))
        .toList();
    final rangedIncome = allIncome.where((e) => _inRange(e, range)).toList();

    final filterCard = _FilterCard(
      period: _period,
      excludeFixed: _excludeFixed,
      rangeLabel: range.label,
      showNav: false, // arrows are interactive; useless in a snapshot
      onPeriodChanged: (_) {},
      onExcludeChanged: (_) {},
      onPrev: () {},
      onNext: () {},
    );

    final report = _buildReport(
      filterCard: filterCard,
      visibleSections: visibleSections,
      rangedExpenses: rangedExpenses,
      rangedIncome: rangedIncome,
      allExpenses: allExpenses,
      range: range,
      symbol: symbol,
      forReport: true,
    );

    // The overlay is laid out via a `Stack` with `Clip.hardEdge`, so any
    // child positioned outside the visible bounds (e.g. left: -screen)
    // is clipped — toImage then returns a blank/empty layer because
    // RepaintBoundary's child never paints. Instead, render the report
    // at (0, 0) AT FULL NATURAL HEIGHT and stack a brand-colored cover
    // on top to hide it from the user during the brief capture window
    // (~150 ms). The RepaintBoundary still paints into its own layer
    // even when visually obscured, so the snapshot is complete.
    final entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: mediaSize.width,
            // No explicit height — let the Material take its natural
            // intrinsic height so fl_chart receives proper constraints.
            child: Material(
              color: brand.background,
              child: MediaQuery(
                data: MediaQuery.of(context),
                child: Theme(
                  data: Theme.of(context),
                  child: RepaintBoundary(
                    key: captureKey,
                    child: IntrinsicHeight(
                      child: Container(
                        color: brand.background,
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                        child: report,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Opaque cover hides the rendered report from the user. It
          // does NOT prevent paint of the report below — Stack still
          // paints all children, RepaintBoundary captures regardless of
          // overdraw.
          Positioned.fill(
            child: IgnorePointer(
              child: Container(color: brand.background),
            ),
          ),
        ],
      ),
    );

    overlay.insert(entry);
    try {
      // Three frames + a small delay gives fl_chart's LineChart and
      // PieChart enough time to lay out their internal painters and
      // finish the first paint of the curves/sections.
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
          captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) {
        throw StateError('Could not locate capture boundary.');
      }
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw StateError('Snapshot encoding returned null.');
      }
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/trackora_stats_$ts.png');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: 'trackora_stats.png')],
        subject: 'Trackora — Statistics',
      );
    } catch (_) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failedMsg)));
      }
    } finally {
      entry.remove();
      if (mounted) setState(() => _isSharing = false);
    }
  }
}

enum _StatsPeriod { week, month, year, all }

class _StatsRange {
  final DateTime? start;
  final DateTime? endExclusive;
  final String label;

  const _StatsRange({
    required this.start,
    required this.endExclusive,
    required this.label,
  });
}

// ── Top action bar ──────────────────────────────────────────────

class _TopActionBar extends StatelessWidget {
  final VoidCallback onManage;
  final VoidCallback? onShare;

  const _TopActionBar({required this.onManage, required this.onShare});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Text(
            context.t('stats.title'),
            style: Theme.of(context).textTheme.displayMedium,
          ),
        ),
        CircleIconButton(
          icon: CupertinoIcons.slider_horizontal_3,
          size: 40,
          onTap: onManage,
        ),
        const SizedBox(width: 10),
        Opacity(
          opacity: onShare == null ? 0.5 : 1,
          child: CircleIconButton(
            icon: CupertinoIcons.share,
            size: 40,
            onTap: onShare ?? () {},
          ),
        ),
      ],
    );
  }
}

// ── Filter card ────────────────────────────────────────────────

class _FilterCard extends StatelessWidget {
  final _StatsPeriod period;
  final bool excludeFixed;
  final String rangeLabel;
  final bool showNav;
  final ValueChanged<_StatsPeriod> onPeriodChanged;
  final ValueChanged<bool> onExcludeChanged;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  const _FilterCard({
    required this.period,
    required this.excludeFixed,
    required this.rangeLabel,
    required this.showNav,
    required this.onPeriodChanged,
    required this.onExcludeChanged,
    required this.onPrev,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Single-line segmented control: 4 equal-width chips wrapped
          // in a pill-shaped track so nothing wraps awkwardly.
          _SegmentedFilter(
            period: period,
            onChanged: onPeriodChanged,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Text(
                  rangeLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (showNav) ...[
                _navButton(context, CupertinoIcons.chevron_left, onPrev),
                const SizedBox(width: 6),
                _navButton(context, CupertinoIcons.chevron_right, onNext),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
            decoration: BoxDecoration(
              color: brand.background,
              borderRadius: BorderRadius.circular(AppRadius.field),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.t('stats.excludeFixed'),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: brand.ink,
                    ),
                  ),
                ),
                CupertinoSwitch(
                  value: excludeFixed,
                  onChanged: onExcludeChanged,
                ),
              ],
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

/// Tidy 4-up segmented control. Uses `Expanded` so each chip is the
/// same width — fixing the previous Wrap layout where `All` would
/// occasionally drop to a second line on narrow phones.
class _SegmentedFilter extends StatelessWidget {
  final _StatsPeriod period;
  final ValueChanged<_StatsPeriod> onChanged;

  const _SegmentedFilter({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final selectedBg = brand.accentDark;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          for (final p in _StatsPeriod.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  HapticFeedback.selectionClick();
                  onChanged(p);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: period == p ? selectedBg : Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    _label(context, p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: period == p
                          ? foregroundOn(selectedBg)
                          : brand.ink,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _label(BuildContext context, _StatsPeriod p) {
    return switch (p) {
      _StatsPeriod.week => context.t('stats.filterWeek'),
      _StatsPeriod.month => context.t('stats.filterMonth'),
      _StatsPeriod.year => context.t('stats.filterYear'),
      _StatsPeriod.all => context.t('stats.filterAll'),
    };
  }
}

// ── Line chart ─────────────────────────────────────────────────

class _LineChartCard extends StatelessWidget {
  final List<Expense> expenses;
  final _StatsRange range;
  final _StatsPeriod period;
  final String symbol;

  const _LineChartCard({
    required this.expenses,
    required this.range,
    required this.period,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chartAccent = isDark ? brand.accent : brand.accentDark;

    // The line chart only makes sense for Week / Month / Year — see
    // _LineChartCard handling of `_StatsPeriod.all` below for the
    // friendly empty state.
    final isAll = period == _StatsPeriod.all;
    final series = isAll ? _emptySeries : _buildSeries();
    final values = series.values;
    final total = values.fold<double>(0, (s, v) => s + v);
    final maxV = values.fold<double>(0, (m, v) => v > m ? v : m);
    final chartMax = maxV == 0 ? 1.0 : maxV * 1.25;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('stats.lineChart.title'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _subtitle(context),
                      style: TextStyle(
                        fontSize: 11,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            formatMoney(symbol, total),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 14),
          if (isAll)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  context.t('stats.lineChart.notForAll'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: brand.inkSoft, fontSize: 12),
                ),
              ),
            )
          else if (series.isEmpty || total == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  context.t('stats.lineChart.empty'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: brand.inkSoft, fontSize: 12),
                ),
              ),
            )
          else
            SizedBox(
              // Daily-resolution months need extra room under the chart
              // so the rotated date labels don't get clipped.
              height: period == _StatsPeriod.month ? 230 : 200,
              child: _buildChart(
                series: series,
                chartMax: chartMax,
                accent: chartAccent,
                brand: brand,
                isDark: isDark,
              ),
            ),
        ],
      ),
    );
  }

  String _subtitle(BuildContext context) {
    return switch (period) {
      _StatsPeriod.week => context.t('stats.lineChart.weekSubtitle'),
      _StatsPeriod.month => context.t('stats.lineChart.monthSubtitle'),
      _StatsPeriod.year => context.t('stats.lineChart.yearSubtitle'),
      _StatsPeriod.all => context.t('stats.lineChart.allSubtitle'),
    };
  }

  static const _LineSeries _emptySeries = _LineSeries(
    values: [],
    labels: [],
    denseLabels: true,
  );

  /// Bucketize expenses into the right resolution for the period.
  /// Returns labels parallel to values; index 0..n-1.
  _LineSeries _buildSeries() {
    switch (period) {
      case _StatsPeriod.week:
        final start = range.start!;
        final values = List<double>.filled(7, 0);
        for (final e in expenses) {
          final d = DateTime(e.date.year, e.date.month, e.date.day);
          if (!d.isBefore(range.start!) && d.isBefore(range.endExclusive!)) {
            values[d.difference(start).inDays] += e.amount;
          }
        }
        final labels = [
          for (int i = 0; i < 7; i++)
            DateFormat('E').format(start.add(Duration(days: i))),
        ];
        return _LineSeries(values: values, labels: labels, denseLabels: true);
      case _StatsPeriod.month:
        final start = range.start!;
        final daysInMonth = DateTime(start.year, start.month + 1, 0).day;
        final values = List<double>.filled(daysInMonth, 0);
        for (final e in expenses) {
          if (e.date.year == start.year && e.date.month == start.month) {
            values[e.date.day - 1] += e.amount;
          }
        }
        final labels = [
          for (int i = 0; i < daysInMonth; i++) '${i + 1}',
        ];
        return _LineSeries(values: values, labels: labels, denseLabels: false);
      case _StatsPeriod.year:
        final values = List<double>.filled(12, 0);
        for (final e in expenses) {
          if (e.date.year == range.start!.year) {
            values[e.date.month - 1] += e.amount;
          }
        }
        final labels = [
          for (int i = 0; i < 12; i++)
            DateFormat('MMM').format(DateTime(2000, i + 1, 1)),
        ];
        return _LineSeries(values: values, labels: labels, denseLabels: true);
      case _StatsPeriod.all:
        if (expenses.isEmpty) {
          return const _LineSeries(values: [], labels: [], denseLabels: true);
        }
        var minYear = expenses.first.date.year;
        var maxYear = expenses.first.date.year;
        for (final e in expenses) {
          if (e.date.year < minYear) minYear = e.date.year;
          if (e.date.year > maxYear) maxYear = e.date.year;
        }
        final n = maxYear - minYear + 1;
        final values = List<double>.filled(n, 0);
        for (final e in expenses) {
          values[e.date.year - minYear] += e.amount;
        }
        final labels = [for (int i = 0; i < n; i++) '${minYear + i}'];
        return _LineSeries(
          values: values,
          labels: labels,
          denseLabels: n <= 8,
        );
    }
  }

  Widget _buildChart({
    required _LineSeries series,
    required double chartMax,
    required Color accent,
    required BrandColors brand,
    required bool isDark,
  }) {
    final spots = [
      for (int i = 0; i < series.values.length; i++)
        FlSpot(i.toDouble(), series.values[i]),
    ];
    final lineBar = LineChartBarData(
      spots: spots,
      isCurved: true,
      color: accent,
      barWidth: 3,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, _) => spot.y > 0,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
          radius: 3.5,
          color: accent,
          strokeWidth: 2,
          strokeColor: brand.surface,
        ),
      ),
      belowBarData: BarAreaData(
        show: true,
        color: accent.withValues(alpha: isDark ? 0.20 : 0.10),
      ),
    );

    // We render *every* label per spec, but rotate when the series is
    // dense (>12 points, e.g. days-in-month) so they don't overlap.
    final n = series.values.length;
    final shouldRotate = n > 12;
    final labelFontSize = n > 20 ? 8.5 : (n > 12 ? 9.5 : 10.0);
    final reservedBottom = shouldRotate ? 48.0 : 28.0;

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (n - 1).toDouble().clamp(0.0, double.infinity),
        minY: 0,
        maxY: chartMax * 1.05,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: brand.divider, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          enabled: true,
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
              reservedSize: reservedBottom,
              interval: 1,
              getTitlesWidget: (v, _) {
                if (v != v.roundToDouble()) return const SizedBox();
                final i = v.toInt();
                if (i < 0 || i >= series.labels.length) return const SizedBox();
                final label = Text(
                  series.labels[i],
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: labelFontSize,
                    fontWeight: FontWeight.w700,
                    color: brand.inkSoft,
                  ),
                );
                if (!shouldRotate) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: label,
                  );
                }
                // Anchored top-right rotation keeps the label's
                // right-edge near the tick so the chart still reads
                // "label belongs to this point."
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Transform.rotate(
                    angle: -0.9, // ~ -52°
                    alignment: Alignment.topCenter,
                    child: label,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [lineBar],
        // Only show inline value bubbles when the series is sparse —
        // otherwise they overlap.
        showingTooltipIndicators: series.denseLabels && n <= 12
            ? [
                for (int i = 0; i < n; i++)
                  if (series.values[i] > 0)
                    ShowingTooltipIndicators([
                      LineBarSpot(lineBar, 0, spots[i]),
                    ]),
              ]
            : const [],
      ),
    );
  }
}

class _LineSeries {
  final List<double> values;
  final List<String> labels;
  final bool denseLabels;

  const _LineSeries({
    required this.values,
    required this.labels,
    required this.denseLabels,
  });

  bool get isEmpty => values.isEmpty;
}

// ── Swipeable charts (line + donut in one card) ────────────────

class _ChartsCarousel extends StatefulWidget {
  final bool showLine;
  final bool showDonut;
  final List<Expense> allExpenses;
  final List<Expense> rangedExpenses;
  final _StatsRange range;
  final _StatsPeriod period;
  final String symbol;
  // For the screenshot we want both charts visible at once instead of
  // a swipeable card — fl_chart doesn't paint off-screen PageView
  // children reliably.
  final bool stacked;

  const _ChartsCarousel({
    required this.showLine,
    required this.showDonut,
    required this.allExpenses,
    required this.rangedExpenses,
    required this.range,
    required this.period,
    required this.symbol,
    required this.stacked,
  });

  @override
  State<_ChartsCarousel> createState() => _ChartsCarouselState();
}

class _ChartsCarouselState extends State<_ChartsCarousel> {
  late PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void didUpdateWidget(covariant _ChartsCarousel old) {
    super.didUpdateWidget(old);
    final pageCount = _pages().length;
    if (_page >= pageCount && pageCount > 0) {
      // The user disabled the page we were on (e.g. switched to "All",
      // dropping the line page). Snap back to page 0 on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _page = 0);
        if (_controller.hasClients) _controller.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<_ChartPage> _pages() {
    return [
      // Donut chart is primary — shown first.
      if (widget.showDonut)
        _ChartPage(
          id: 'donut',
          label: 'stats.byCategory',
          icon: CupertinoIcons.chart_pie_fill,
          builder: (_) => _CategoryCard(
            expenses: widget.rangedExpenses,
            symbol: widget.symbol,
            rangeLabel: widget.range.label,
            forReport: widget.stacked,
          ),
        ),
      if (widget.showLine)
        _ChartPage(
          id: 'line',
          label: 'stats.section.lineChart',
          icon: CupertinoIcons.chart_bar,
          builder: (_) => _LineChartCard(
            expenses: widget.allExpenses,
            range: widget.range,
            period: widget.period,
            symbol: widget.symbol,
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final pages = _pages();
    if (pages.isEmpty) return const SizedBox.shrink();

    if (widget.stacked || pages.length == 1) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < pages.length; i++) ...[
            if (i > 0) const SizedBox(height: 14),
            pages[i].builder(context),
          ],
        ],
      );
    }

    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tab-style header so the user knows which chart is on screen
        // and can switch with a tap as well as a swipe.
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Row(
            children: [
              for (var i = 0; i < pages.length; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _controller.animateToPage(
                        i,
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                      );
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(vertical: 9),
                      decoration: BoxDecoration(
                        color: _page == i
                            ? brand.accentDark
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(AppRadius.chip),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            pages[i].icon,
                            size: 14,
                            color: _page == i
                                ? foregroundOn(brand.accentDark)
                                : brand.ink,
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              context.t(pages[i].label),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: _page == i
                                    ? foregroundOn(brand.accentDark)
                                    : brand.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Fixed-height viewport — donut & line cards each render
        // comfortably inside this height. Tall enough to fit Month
        // view's rotated labels and the donut's legend.
        SizedBox(
          height: 560,
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              for (final page in pages)
                SingleChildScrollView(
                  // Each page can be scrolled independently if its
                  // content exceeds 560px (donut legend on long lists).
                  child: page.builder(context),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // iOS-style page dots.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(pages.length, (i) {
            final selected = i == _page;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: selected ? 18 : 6,
              height: 6,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: selected ? brand.ink : brand.divider,
                borderRadius: BorderRadius.circular(10),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _ChartPage {
  final String id;
  final String label;
  final IconData icon;
  final WidgetBuilder builder;

  const _ChartPage({
    required this.id,
    required this.label,
    required this.icon,
    required this.builder,
  });
}

// ── Report header (snapshot only) ──────────────────────────────

class _ReportHeader extends StatelessWidget {
  final String rangeLabel;
  final _StatsPeriod period;
  final bool excludeFixed;

  const _ReportHeader({
    required this.rangeLabel,
    required this.period,
    required this.excludeFixed,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final periodKey = switch (period) {
      _StatsPeriod.week => 'stats.filterWeek',
      _StatsPeriod.month => 'stats.filterMonth',
      _StatsPeriod.year => 'stats.filterYear',
      _StatsPeriod.all => 'stats.filterAll',
    };
    final generated = DateFormat('MMM d, yyyy · HH:mm').format(DateTime.now());
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.mint,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.doc_chart,
                  size: 20,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('stats.report.title'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      generated,
                      style: TextStyle(
                        fontSize: 11,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _ReportTag(
                icon: CupertinoIcons.calendar,
                label: context.t(periodKey),
              ),
              _ReportTag(
                icon: CupertinoIcons.time,
                label: rangeLabel,
              ),
              _ReportTag(
                icon: excludeFixed
                    ? CupertinoIcons.minus_circle
                    : CupertinoIcons.plus_circle,
                label: excludeFixed
                    ? context.t('stats.excludeFixed')
                    : context.t('stats.includeFixed'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReportTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ReportTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: brand.inkSoft),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: brand.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Important data summary ─────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  final List<Expense> expenses;
  final List<Expense> income;
  final String symbol;
  final String rangeLabel;
  final VoidCallback? onTapExpenses;
  final VoidCallback? onTapIncome;

  const _OverviewCard({
    required this.expenses,
    required this.income,
    required this.symbol,
    required this.rangeLabel,
    this.onTapExpenses,
    this.onTapIncome,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final totalExpense = expenses.fold<double>(0, (s, e) => s + e.amount);
    final totalIncome = income.fold<double>(0, (s, e) => s + e.amount);
    final highestExpense = expenses.isEmpty
        ? 0.0
        : expenses
              .map((e) => e.amount)
              .reduce((a, b) => a > b ? a : b);
    final highestIncome = income.isEmpty
        ? 0.0
        : income.map((e) => e.amount).reduce((a, b) => a > b ? a : b);
    final avgExpense = expenses.isEmpty ? 0.0 : totalExpense / expenses.length;
    final txCount = expenses.length + income.length;
    String? topCategory;
    if (expenses.isNotEmpty) {
      final totals = <String, double>{};
      for (final e in expenses) {
        totals[e.category] = (totals[e.category] ?? 0) + e.amount;
      }
      final entry = totals.entries.reduce(
        (a, b) => a.value >= b.value ? a : b,
      );
      topCategory = entry.key;
    }

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: AppColors.sand,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  CupertinoIcons.square_grid_2x2,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('stats.summary.title'),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      rangeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (txCount == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  context.t('stats.summary.empty'),
                  style: TextStyle(color: brand.inkSoft),
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final tileWidth = (constraints.maxWidth - 12) / 2;
                final tiles = <_SummaryTileData>[
                  _SummaryTileData(
                    label: context.t('stats.summary.totalExpenses'),
                    value: formatMoney(symbol, totalExpense),
                    valueColor: AppColors.expense,
                    onTap: onTapExpenses,
                  ),
                  _SummaryTileData(
                    label: context.t('stats.summary.totalIncome'),
                    value: formatMoney(symbol, totalIncome),
                    valueColor: AppColors.income,
                    onTap: onTapIncome,
                  ),
                  _SummaryTileData(
                    label: context.t('stats.summary.netBalance'),
                    value: formatMoney(symbol, totalIncome - totalExpense),
                    valueColor: (totalIncome - totalExpense) >= 0
                        ? AppColors.income
                        : AppColors.expense,
                  ),
                  _SummaryTileData(
                    label: context.t('stats.summary.transactions'),
                    value: '$txCount',
                  ),
                  if (highestExpense > 0)
                    _SummaryTileData(
                      label: context.t('stats.summary.highestExpense'),
                      value: formatMoney(symbol, highestExpense),
                    ),
                  if (highestIncome > 0)
                    _SummaryTileData(
                      label: context.t('stats.summary.highestIncome'),
                      value: formatMoney(symbol, highestIncome),
                    ),
                  if (expenses.isNotEmpty)
                    _SummaryTileData(
                      label: context.t('stats.summary.avgExpense'),
                      value: formatMoney(symbol, avgExpense),
                    ),
                  if (topCategory != null)
                    _SummaryTileData(
                      label: context.t('stats.summary.topCategory'),
                      value: context.categoryLabel(topCategory),
                    ),
                ];
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (final t in tiles)
                      SizedBox(width: tileWidth, child: _SummaryTile(data: t)),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _SummaryTileData {
  final String label;
  final String value;
  final Color? valueColor;
  final VoidCallback? onTap;

  const _SummaryTileData({
    required this.label,
    required this.value,
    this.valueColor,
    this.onTap,
  });
}

class _SummaryTile extends StatelessWidget {
  final _SummaryTileData data;

  const _SummaryTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final tappable = data.onTap != null;
    final body = Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (tappable)
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 12,
                  color: brand.inkSoft,
                ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              data.value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
                color: data.valueColor ?? brand.ink,
              ),
            ),
          ),
        ],
      ),
    );
    if (!tappable) return body;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        data.onTap!();
      },
      behavior: HitTestBehavior.opaque,
      child: body,
    );
  }
}

// ── Donut chart (kept close to the original implementation) ────

class _CategoryCard extends StatelessWidget {
  final List<Expense> expenses;
  final String symbol;
  final String rangeLabel;
  // When true (report/screenshot capture), all legend rows are shown in a
  // plain Column so nothing is clipped. When false (interactive), the legend
  // is constrained to a fixed-height scrollable list so the donut chart stays
  // fixed at the top.
  final bool forReport;

  const _CategoryCard({
    required this.expenses,
    required this.symbol,
    required this.rangeLabel,
    this.forReport = false,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, double> totals = {};
    for (final e in expenses) {
      totals[e.category] = (totals[e.category] ?? 0) + e.amount;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = expenses.fold<double>(0, (s, e) => s + e.amount);
    final brand = context.brand;

    // ── Fixed top portion ──────────────────────────────────────
    final topPortion = Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
                child: const Icon(
                  CupertinoIcons.chart_pie_fill,
                  size: 18,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
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
                      rangeLabel,
                      style: TextStyle(
                        fontSize: 11,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (expenses.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 24, 0, 24),
              child: Center(
                child: Text(
                  context.t('stats.noCategorySpend'),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: brand.inkSoft),
                ),
              ),
            )
          else ...[
            Center(
              child: SizedBox(
                width: 210,
                height: 210,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PieChart(
                      PieChartData(
                        sectionsSpace: 4,
                        centerSpaceRadius: 68,
                        pieTouchData: PieTouchData(
                          touchCallback: (event, response) {
                            if (event is! FlTapUpEvent ||
                                response == null ||
                                response.touchedSection == null) {
                              return;
                            }
                            final idx =
                                response.touchedSection!.touchedSectionIndex;
                            if (idx >= 0 && idx < sorted.length) {
                              _showCategoryRecords(context, sorted[idx]);
                            }
                          },
                        ),
                        sections: List.generate(sorted.length, (i) {
                          final entry = sorted[i];
                          final s = styleFor(entry.key);
                          final pct = total == 0 ? 0.0 : entry.value / total;
                          return PieChartSectionData(
                            value: entry.value,
                            color: s.accent,
                            radius: 28,
                            title: pct >= 0.08 ? '${(pct * 100).round()}%' : '',
                            titleStyle: TextStyle(
                              color: foregroundOn(s.accent),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          );
                        }),
                      ),
                    ),
                    _CenterTotalLabel(total: total, symbol: symbol),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Center(
              child: Text(
                context.t('stats.tapSliceHint'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 11,
                  color: brand.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
        ],
      ),
    );

    if (expenses.isEmpty) {
      return SectionCard(
        padding: EdgeInsets.zero,
        child: topPortion,
      );
    }

    // ── Scrollable legend portion ──────────────────────────────
    // In report mode all rows are visible; in interactive mode the list is
    // constrained so only the legend scrolls, not the entire chart card.
    final legend = forReport
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in sorted)
                _LegendRow(
                  entry: entry,
                  total: total,
                  symbol: symbol,
                  onTap: () => _showCategoryRecords(context, entry),
                ),
              const SizedBox(height: 2),
            ],
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 210),
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: sorted.length,
              itemBuilder: (_, i) => _LegendRow(
                entry: sorted[i],
                total: total,
                symbol: symbol,
                onTap: () => _showCategoryRecords(context, sorted[i]),
              ),
            ),
          );

    return SectionCard(
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          topPortion,
          Divider(height: 1, color: brand.divider),
          legend,
        ],
      ),
    );
  }

  void _showCategoryRecords(
    BuildContext context,
    MapEntry<String, double> entry,
  ) {
    HapticFeedback.selectionClick();
    final records = expenses.where((e) => e.category == entry.key).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.78,
          ),
          child: _CategoryRecordsSheet(
            category: entry.key,
            records: records,
            total: entry.value,
            symbol: symbol,
            rangeLabel: rangeLabel,
          ),
        ),
      ),
    );
  }
}

class _CenterTotalLabel extends StatelessWidget {
  final double total;
  final String symbol;

  const _CenterTotalLabel({required this.total, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SizedBox(
      width: 118,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatMoney(symbol, total),
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            context.t('common.total'),
            style: TextStyle(
              fontSize: 10,
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
  final MapEntry<String, double> entry;
  final double total;
  final String symbol;
  final VoidCallback onTap;

  const _LegendRow({
    required this.entry,
    required this.total,
    required this.symbol,
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
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(12)),
        child: Row(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: s.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.categoryLabel(entry.key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
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
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${(pct * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 11,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatMoney(symbol, entry.value),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 8),
            Icon(CupertinoIcons.chevron_right, size: 14, color: brand.inkSoft),
          ],
        ),
      ),
    );
  }
}

class _CategoryRecordsSheet extends StatelessWidget {
  final String category;
  final List<Expense> records;
  final double total;
  final String symbol;
  final String rangeLabel;

  const _CategoryRecordsSheet({
    required this.category,
    required this.records,
    required this.total,
    required this.symbol,
    required this.rangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final style = styleFor(category);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: brand.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: style.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(style.icon, size: 18, color: style.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.categoryLabel(category),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      rangeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              CircleIconButton(
                icon: CupertinoIcons.xmark,
                size: 34,
                background: brand.surface,
                foreground: brand.ink,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    formatMoney(symbol, total),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${records.length} ${records.length == 1 ? context.t('common.entry') : context.t('common.entries')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: records.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: brand.divider),
              itemBuilder: (context, index) =>
                  _RecordRow(expense: records[index], symbol: symbol),
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  final Expense expense;
  final String symbol;
  final Color? amountColor;

  const _RecordRow({
    required this.expense,
    required this.symbol,
    this.amountColor,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final title = expense.note.trim().isEmpty
        ? context.categoryLabel(expense.category)
        : expense.note.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                color: brand.ink,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.48,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatMoney(symbol, expense.amount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: amountColor ?? AppColors.expense,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${DateFormat('MMM d, yyyy').format(expense.date)} · ${context.categoryLabel(expense.category)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 11,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Generic records sheet (Total expenses / Total income tap) ──

class _GenericRecordsSheet extends StatelessWidget {
  final String title;
  final List<Expense> records;
  final double total;
  final String symbol;
  final String rangeLabel;

  const _GenericRecordsSheet({
    required this.title,
    required this.records,
    required this.total,
    required this.symbol,
    required this.rangeLabel,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: brand.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      rangeLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              CircleIconButton(
                icon: CupertinoIcons.xmark,
                size: 34,
                background: brand.surface,
                foreground: brand.ink,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    formatMoney(symbol, total),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '${records.length} ${records.length == 1 ? context.t('common.entry') : context.t('common.entries')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: records.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        context.t('stats.summary.empty'),
                        style: TextStyle(color: brand.inkSoft),
                      ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: records.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: brand.divider),
                    itemBuilder: (context, index) {
                      final rec = records[index];
                      return _RecordRow(
                        expense: rec,
                        symbol: symbol,
                        amountColor: rec.type == EntryType.income
                            ? AppColors.income
                            : AppColors.expense,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Manage-visibility sheet (lifted from dashboard pattern) ────

class _VisibilitySheet extends StatelessWidget {
  final String title;
  final String footnote;
  final List<Widget> children;

  const _VisibilitySheet({
    required this.title,
    required this.footnote,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: brand.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            SectionCard(
              padding: EdgeInsets.zero,
              child: Column(children: children),
            ),
            const SizedBox(height: 10),
            Text(
              footnote,
              style: TextStyle(
                fontSize: 12,
                color: brand.inkSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibilitySwitchRow extends StatelessWidget {
  final String label;
  final bool visible;
  final bool canHide;
  final ValueChanged<bool> onChanged;

  const _VisibilitySwitchRow({
    required this.label,
    required this.visible,
    required this.canHide,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: brand.ink,
              ),
            ),
          ),
          CupertinoSwitch(
            value: visible,
            onChanged: canHide ? onChanged : null,
          ),
        ],
      ),
    );
  }
}

