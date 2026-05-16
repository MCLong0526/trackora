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
import '../../services/prefs_service.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_donut_chart.dart';
import '../../widgets/exchange_rate_sheet.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/section_card.dart';

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  _StatsPeriod _period = _StatsPeriod.month;
  bool _excludeFixed = true;
  late DateTime _anchor;
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchor = DateTime(now.year, now.month, 1);
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
      case _StatsPeriod.sixMonth:
        final end = DateTime(_anchor.year, _anchor.month + 1, 1);
        final start = DateTime(_anchor.year, _anchor.month - 5, 1);
        return _StatsRange(
          start: start,
          endExclusive: end,
          label:
              '${DateFormat('MMM').format(start)} – '
              '${DateFormat('MMM yyyy').format(DateTime(_anchor.year, _anchor.month))}',
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

  _StatsRange? _prevRange() {
    switch (_period) {
      case _StatsPeriod.week:
        final start = _startOfWeek(_anchor).subtract(const Duration(days: 7));
        return _StatsRange(
          start: start,
          endExclusive: start.add(const Duration(days: 7)),
          label: DateFormat('MMM d').format(start),
        );
      case _StatsPeriod.month:
        final start = DateTime(_anchor.year, _anchor.month - 1, 1);
        final end = DateTime(_anchor.year, _anchor.month, 1);
        return _StatsRange(
          start: start,
          endExclusive: end,
          label: DateFormat('MMM').format(start),
        );
      case _StatsPeriod.sixMonth:
        final anchorStart = DateTime(_anchor.year, _anchor.month - 5, 1);
        final prevEnd = anchorStart;
        final prevStart = DateTime(prevEnd.year, prevEnd.month - 6, 1);
        return _StatsRange(
          start: prevStart,
          endExclusive: prevEnd,
          label: DateFormat('MMM').format(prevStart),
        );
      case _StatsPeriod.year:
        final start = DateTime(_anchor.year - 1, 1, 1);
        return _StatsRange(
          start: start,
          endExclusive: DateTime(_anchor.year, 1, 1),
          label: DateFormat('yyyy').format(start),
        );
      case _StatsPeriod.all:
        return null;
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
        case _StatsPeriod.sixMonth:
          _anchor = DateTime(_anchor.year, _anchor.month + (6 * dir), 1);
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

          final prevRange = _prevRange();
          final prevExpenses = prevRange != null
              ? allExpenses.where((e) => _inRange(e, prevRange)).toList()
              : <Expense>[];
          final prevTotal = prevExpenses.fold<double>(
            0,
            (s, e) => s + e.convertedAmount,
          );
          final prevLabel = prevRange?.label ?? '';

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 120),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── 1. Top action bar
                _TopActionBar(
                  onManage: () => _showVisibilitySheet(context),
                  onShare: _isSharing ? null : () => _shareSnapshot(context),
                ),
                const SizedBox(height: 20),

                // ── 2. Period pills (W M 6M Y All)
                _PeriodPills(
                  period: _period,
                  onChanged: (p) {
                    setState(() {
                      _period = p;
                      final now = DateTime.now();
                      switch (p) {
                        case _StatsPeriod.week:
                          _anchor = _startOfWeek(now);
                          break;
                        case _StatsPeriod.month:
                        case _StatsPeriod.sixMonth:
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
                ),
                const SizedBox(height: 14),

                // ── 3. Spending header with comparison + exclude toggle
                _SpendingHeader(
                  period: _period,
                  anchor: _anchor,
                  rangeLabel: range.label,
                  currentTotal: rangedExpenses.fold(0, (s, e) => s + e.convertedAmount),
                  prevTotal: prevTotal,
                  prevLabel: prevLabel,
                  symbol: symbol,
                  showNav: _period != _StatsPeriod.all,
                  onPrev: () => _step(-1),
                  onNext: () => _step(1),
                  excludeFixed: _excludeFixed,
                  onExcludeChanged: (v) => setState(() => _excludeFixed = v),
                ),
                const SizedBox(height: 14),

                // ── 4. Charts carousel (By Category + Trend)
                _buildReport(
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

  Widget _buildReport({
    required Set<String> visibleSections,
    required List<Expense> rangedExpenses,
    required List<Expense> rangedIncome,
    required List<Expense> allExpenses,
    required _StatsRange range,
    required String symbol,
    bool forReport = false,
  }) {
    final showLine =
        visibleSections.contains('lineChart') && _period != _StatsPeriod.all;
    final showDonut = visibleSections.contains('donutChart');

    if (!showLine && !showDonut) return const SizedBox.shrink();

    return _ChartsCarousel(
      showLine: showLine,
      showDonut: showDonut,
      allExpenses: allExpenses,
      rangedExpenses: rangedExpenses,
      range: range,
      period: _period,
      symbol: symbol,
      stacked: forReport,
    );
  }

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
    final prevRange = _prevRange();

    final allExpenses = allItems
        .where((e) => e.type == EntryType.expense)
        .where((e) => !_isFixed(e))
        .toList();
    final allIncome = allItems
        .where((e) => e.type == EntryType.income)
        .toList();
    final rangedExpenses = allExpenses
        .where((e) => _inRange(e, range))
        .toList();
    final rangedIncome = allIncome.where((e) => _inRange(e, range)).toList();
    final prevExpenses = prevRange != null
        ? allExpenses.where((e) => _inRange(e, prevRange)).toList()
        : <Expense>[];
    final prevTotal = prevExpenses.fold<double>(0, (s, e) => s + e.convertedAmount);
    final currentTotal = rangedExpenses.fold<double>(0, (s, e) => s + e.convertedAmount);
    final prevLabel = prevRange?.label ?? '';

    final report = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ReportHeader(rangeLabel: range.label, period: _period),
        const SizedBox(height: 14),
        _SpendingHeader(
          period: _period,
          anchor: _anchor,
          rangeLabel: range.label,
          currentTotal: currentTotal,
          prevTotal: prevTotal,
          prevLabel: prevLabel,
          symbol: symbol,
          showNav: false,
          onPrev: () {},
          onNext: () {},
        ),
        const SizedBox(height: 14),
        _buildReport(
          visibleSections: visibleSections,
          rangedExpenses: rangedExpenses,
          rangedIncome: rangedIncome,
          allExpenses: allExpenses,
          range: range,
          symbol: symbol,
          forReport: true,
        ),
      ],
    );

    final entry = OverlayEntry(
      builder: (ctx) => Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            width: mediaSize.width,
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
          Positioned.fill(
            child: IgnorePointer(child: Container(color: brand.background)),
          ),
        ],
      ),
    );

    overlay.insert(entry);
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await WidgetsBinding.instance.endOfFrame;
      await WidgetsBinding.instance.endOfFrame;

      final boundary =
          captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null)
        throw StateError('Could not locate capture boundary.');
      final image = await boundary.toImage(pixelRatio: 2.5);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null)
        throw StateError('Snapshot encoding returned null.');
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/trackora_stats_$ts.png');
      await file.writeAsBytes(bytes, flush: true);
      await Share.shareXFiles([
        XFile(file.path, mimeType: 'image/png', name: 'trackora_stats.png'),
      ], subject: 'Trackora — Statistics');
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

enum _StatsPeriod { week, month, sixMonth, year, all }

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

// ── Floating card with shadow ───────────────────────────────────

class _FloatCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const _FloatCard({
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: context.brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        
      ),
      child: child,
    );
  }
}

// ── Top action bar ─────────────────────────────────────────────

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
        _ActionBtn(
          icon: CupertinoIcons.slider_horizontal_3,
          onTap: onManage,
        ),
        const SizedBox(width: 8),
        const FxRateButton(),
        const SizedBox(width: 8),
        const ProfileAvatarButton(),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ActionBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: brand.surface,
          shape: BoxShape.circle,
          
        ),
        child: Icon(icon, size: 18, color: brand.ink),
      ),
    );
  }
}

// ── Period pills (W M 6M Y All) ────────────────────────────────

class _PeriodPills extends StatelessWidget {
  final _StatsPeriod period;
  final ValueChanged<_StatsPeriod> onChanged;

  const _PeriodPills({required this.period, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (int i = 0; i < _StatsPeriod.values.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: _PeriodPill(
              label: _label(_StatsPeriod.values[i]),
              selected: period == _StatsPeriod.values[i],
              onTap: () {
                HapticFeedback.selectionClick();
                onChanged(_StatsPeriod.values[i]);
              },
            ),
          ),
        ],
      ],
    );
  }

  String _label(_StatsPeriod p) => switch (p) {
    _StatsPeriod.week => 'W',
    _StatsPeriod.month => 'M',
    _StatsPeriod.sixMonth => '6M',
    _StatsPeriod.year => 'Y',
    _StatsPeriod.all => 'All',
  };
}

class _PeriodPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? brand.accentDark
              : (isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.white.withValues(alpha: 0.72)),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected
                ? brand.accentDark.withValues(alpha: 0.45)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.13)
                    : Colors.white.withValues(alpha: 0.85)),
            width: 0.8,
          ),
          
        ),
        child: Center(
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 180),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: selected ? foregroundOn(brand.accentDark) : brand.inkSoft,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
  }
}

// ── Shared glass tab pill ──────────────────────────────────────

class _GlassTab extends StatelessWidget {
  final String label;
  final bool selected;
  final Color accentDark;

  const _GlassTab({
    required this.label,
    required this.selected,
    required this.accentDark,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected
            ? accentDark
            : (isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.white.withValues(alpha: 0.72)),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: selected
              ? accentDark.withValues(alpha: 0.45)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.13)
                  : Colors.white.withValues(alpha: 0.85)),
          width: 0.8,
        ),
        
      ),
      child: Center(
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: selected ? foregroundOn(accentDark) : brand.inkSoft,
          ),
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ),
    );
  }
}

// ── Spending header ────────────────────────────────────────────

class _SpendingHeader extends StatelessWidget {
  final _StatsPeriod period;
  final DateTime anchor;
  final String rangeLabel;
  final double currentTotal;
  final double prevTotal;
  final String prevLabel;
  final String symbol;
  final bool showNav;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final bool? excludeFixed;
  final ValueChanged<bool>? onExcludeChanged;

  const _SpendingHeader({
    required this.period,
    required this.anchor,
    required this.rangeLabel,
    required this.currentTotal,
    required this.prevTotal,
    required this.prevLabel,
    required this.symbol,
    required this.showNav,
    required this.onPrev,
    required this.onNext,
    this.excludeFixed,
    this.onExcludeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hasComparison = prevTotal > 0;
    final pctChange = hasComparison
        ? ((currentTotal - prevTotal) / prevTotal * 100)
        : 0.0;
    final isIncrease = pctChange > 0;
    final periodHeader = _buildPeriodHeader();

    return _FloatCard(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  periodHeader,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: brand.inkSoft,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              if (showNav) ...[
                _navBtn(context, CupertinoIcons.chevron_left, onPrev),
                const SizedBox(width: 6),
                _navBtn(context, CupertinoIcons.chevron_right, onNext),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Flexible(
                child: FittedBox(
                  alignment: Alignment.centerLeft,
                  fit: BoxFit.scaleDown,
                  child: Text(
                    formatMoney(symbol, currentTotal),
                    style: TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1.5,
                      color: brand.ink,
                    ),
                  ),
                ),
              ),
              if (hasComparison) ...[
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: (isIncrease
                              ? AppColors.expense
                              : AppColors.income)
                          .withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${isIncrease ? '↑' : '↓'}${pctChange.abs().toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: isIncrease ? AppColors.expense : AppColors.income,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (hasComparison) ...[
            const SizedBox(height: 6),
            Text(
              'vs $prevLabel · ${formatMoney(symbol, prevTotal)}',
              style: TextStyle(
                fontSize: 12,
                color: brand.inkSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (onExcludeChanged != null) ...[
            const SizedBox(height: 14),
            Container(height: 1, color: brand.divider),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Exclude bills + installments',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: brand.inkSoft,
                    ),
                  ),
                ),
                CupertinoSwitch(
                  value: excludeFixed ?? true,
                  onChanged: onExcludeChanged,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _buildPeriodHeader() {
    switch (period) {
      case _StatsPeriod.week:
        return '${DateFormat('MMM d').format(anchor).toUpperCase()} · TOTAL SPENDING';
      case _StatsPeriod.month:
        return '${DateFormat('MMMM').format(anchor).toUpperCase()} · TOTAL SPENDING';
      case _StatsPeriod.sixMonth:
        return 'LAST 6 MONTHS · TOTAL SPENDING';
      case _StatsPeriod.year:
        return '${DateFormat('yyyy').format(anchor)} · TOTAL SPENDING';
      case _StatsPeriod.all:
        return 'ALL TIME · TOTAL SPENDING';
    }
  }

  Widget _navBtn(BuildContext context, IconData icon, VoidCallback onTap) {
    final brand = context.brand;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 17, color: brand.ink),
      ),
    );
  }
}

// ── Line chart ─────────────────────────────────────────────────

class _LineChartCard extends StatefulWidget {
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
  State<_LineChartCard> createState() => _LineChartCardState();
}

class _LineChartCardState extends State<_LineChartCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _animCtrl;
  late Animation<double> _animProgress;
  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _animProgress = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _animCtrl.forward();
    });
  }

  @override
  void didUpdateWidget(covariant _LineChartCard old) {
    super.didUpdateWidget(old);
    // Replay animation when period or data changes
    if (old.period != widget.period ||
        old.range.label != widget.range.label ||
        old.expenses.length != widget.expenses.length) {
      _animCtrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chartAccent = isDark ? brand.accent : brand.accentDark;

    final isAll = widget.period == _StatsPeriod.all;
    final series = isAll ? _emptySeries : _buildSeries();
    final values = series.values;
    final total = values.fold<double>(0, (s, v) => s + v);
    final maxV = values.fold<double>(0, (m, v) => v > m ? v : m);
    final chartMax = maxV == 0 ? 1.0 : maxV * 1.25;

    return _FloatCard(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('stats.lineChart.title'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: brand.inkSoft,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(context),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: brand.inkSoft.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            formatMoney(widget.symbol, total),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
              color: brand.ink,
            ),
          ),
          const SizedBox(height: 16),
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
              height: widget.period == _StatsPeriod.month ? 230 : 200,
              child: AnimatedBuilder(
                animation: _animProgress,
                builder: (ctx, _) => _buildChart(
                  series: series,
                  chartMax: chartMax,
                  accent: chartAccent,
                  brand: brand,
                  isDark: isDark,
                  animProgress: _animProgress.value,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _subtitle(BuildContext context) {
    return switch (widget.period) {
      _StatsPeriod.week => context.t('stats.lineChart.weekSubtitle'),
      _StatsPeriod.month => context.t('stats.lineChart.monthSubtitle'),
      _StatsPeriod.sixMonth => context.t('stats.lineChart.monthSubtitle'),
      _StatsPeriod.year => context.t('stats.lineChart.yearSubtitle'),
      _StatsPeriod.all => context.t('stats.lineChart.allSubtitle'),
    };
  }

  static const _LineSeries _emptySeries = _LineSeries(
    values: [],
    labels: [],
    denseLabels: true,
  );

  _LineSeries _buildSeries() {
    final expenses = widget.expenses;
    final range = widget.range;
    switch (widget.period) {
      case _StatsPeriod.week:
        final start = range.start!;
        final values = List<double>.filled(7, 0);
        for (final e in expenses) {
          final d = DateTime(e.date.year, e.date.month, e.date.day);
          if (!d.isBefore(range.start!) && d.isBefore(range.endExclusive!)) {
            values[d.difference(start).inDays] += e.convertedAmount;
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
            values[e.date.day - 1] += e.convertedAmount;
          }
        }
        final labels = [for (int i = 0; i < daysInMonth; i++) '${i + 1}'];
        return _LineSeries(values: values, labels: labels, denseLabels: false);
      case _StatsPeriod.sixMonth:
        final start = range.start!;
        final values = List<double>.filled(6, 0);
        for (final e in expenses) {
          if (!e.date.isBefore(range.start!) &&
              e.date.isBefore(range.endExclusive!)) {
            final monthDiff =
                (e.date.year - start.year) * 12 + (e.date.month - start.month);
            if (monthDiff >= 0 && monthDiff < 6) values[monthDiff] += e.convertedAmount;
          }
        }
        final labels = [
          for (int i = 0; i < 6; i++)
            DateFormat('MMM').format(DateTime(start.year, start.month + i, 1)),
        ];
        return _LineSeries(values: values, labels: labels, denseLabels: true);
      case _StatsPeriod.year:
        final values = List<double>.filled(12, 0);
        for (final e in expenses) {
          if (e.date.year == range.start!.year) {
            values[e.date.month - 1] += e.convertedAmount;
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
          values[e.date.year - minYear] += e.convertedAmount;
        }
        final labels = [for (int i = 0; i < n; i++) '${minYear + i}'];
        return _LineSeries(values: values, labels: labels, denseLabels: n <= 8);
    }
  }

  Widget _buildChart({
    required _LineSeries series,
    required double chartMax,
    required Color accent,
    required BrandColors brand,
    required bool isDark,
    required double animProgress,
  }) {
    // Animate Y values from 0 → real value
    final animatedValues = series.values.map((v) => v * animProgress).toList();

    final spots = [
      for (int i = 0; i < animatedValues.length; i++)
        FlSpot(i.toDouble(), animatedValues[i]),
    ];
    final lineColor = brand.ink;
    final lineBar = LineChartBarData(
      spots: spots,
      isCurved: true,
      color: lineColor,
      barWidth: 2.5,
      isStrokeCapRound: true,
      dotData: FlDotData(
        show: true,
        checkToShowDot: (spot, _) => spot.y > 0,
        getDotPainter: (spot, percent, bar, index) => FlDotCirclePainter(
          radius: 3.5,
          color: lineColor,
          strokeWidth: 2,
          strokeColor: brand.surface,
        ),
      ),
      belowBarData: BarAreaData(show: false),
    );

    final n = series.values.length;
    final shouldRotate = n > 12;
    final labelFontSize = n > 20 ? 8.5 : (n > 12 ? 9.5 : 10.0);
    final reservedBottom = shouldRotate ? 48.0 : 28.0;

    return LineChart(
      duration: Duration.zero,
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
          enabled: animProgress >= 0.99,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => AppColors.ink,
            tooltipPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 5,
            ),
            tooltipMargin: 8,
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => spots.map((spot) {
              final i = spot.x.toInt();
              final label = i < series.labels.length ? series.labels[i] : '';
              final displayLabel = widget.period == _StatsPeriod.month
                  ? 'Day $label'
                  : label;
              return LineTooltipItem(
                '$displayLabel\n',
                const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 10,
                ),
                children: [
                  TextSpan(
                    text: formatMoney(widget.symbol, spot.y),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              );
            }).toList(),
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
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Transform.rotate(
                    angle: -0.9,
                    alignment: Alignment.topCenter,
                    child: label,
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [lineBar],
        showingTooltipIndicators:
            series.denseLabels && n <= 12 && animProgress >= 0.99
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

// ── Charts carousel (By Category + Trend) ─────────────────────

class _ChartsCarousel extends StatefulWidget {
  final bool showLine;
  final bool showDonut;
  final List<Expense> allExpenses;
  final List<Expense> rangedExpenses;
  final _StatsRange range;
  final _StatsPeriod period;
  final String symbol;
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
      if (widget.showDonut)
        _ChartPage(
          id: 'donut',
          label: 'By Category',
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
          label: 'Trend',
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
        // "By Category" / "Trend" — individual floating glass tabs
        Row(
          children: [
            for (var i = 0; i < pages.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _controller.animateToPage(
                      i,
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                    );
                  },
                  child: _GlassTab(
                    label: pages[i].label,
                    selected: _page == i,
                    accentDark: brand.accentDark,
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 540,
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: [
              for (final page in pages)
                // Donut card manages its own internal scroll; trend uses SingleChildScrollView
                if (page.id == 'donut')
                  page.builder(context)
                else
                  SingleChildScrollView(child: page.builder(context)),
            ],
          ),
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

// ── Report header (snapshot only) ─────────────────────────────

class _ReportHeader extends StatelessWidget {
  final String rangeLabel;
  final _StatsPeriod period;

  const _ReportHeader({required this.rangeLabel, required this.period});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final periodKey = switch (period) {
      _StatsPeriod.week => 'stats.filterWeek',
      _StatsPeriod.month => 'stats.filterMonth',
      _StatsPeriod.sixMonth => '6M',
      _StatsPeriod.year => 'stats.filterYear',
      _StatsPeriod.all => 'stats.filterAll',
    };
    final generated = DateFormat('MMM d, yyyy · HH:mm').format(DateTime.now());
    return _FloatCard(
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
                        fontWeight: FontWeight.w700,
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
                label: periodKey.startsWith('stats.')
                    ? context.t(periodKey)
                    : periodKey,
              ),
              _ReportTag(icon: CupertinoIcons.time, label: rangeLabel),
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
              fontWeight: FontWeight.w600,
              color: brand.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Category donut chart ────────────────────────────────────────

class _CategoryCard extends StatefulWidget {
  final List<Expense> expenses;
  final String symbol;
  final String rangeLabel;
  final bool forReport;

  const _CategoryCard({
    required this.expenses,
    required this.symbol,
    required this.rangeLabel,
    this.forReport = false,
  });

  @override
  State<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends State<_CategoryCard> {
  @override
  Widget build(BuildContext context) {
    final Map<String, double> totals = {};
    for (final e in widget.expenses) {
      totals[e.category] = (totals[e.category] ?? 0) + e.convertedAmount;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = widget.expenses.fold<double>(0, (s, e) => s + e.convertedAmount);
    final brand = context.brand;

    if (widget.expenses.isEmpty) {
      return _FloatCard(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32),
          child: Center(
            child: Text(
              context.t('stats.noCategorySpend'),
              textAlign: TextAlign.center,
              style: TextStyle(color: brand.inkSoft),
            ),
          ),
        ),
      );
    }

    // Use LayoutBuilder to detect if height is bounded (in PageView) vs unbounded (stacked/report)
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final bounded = constraints.hasBoundedHeight;

        final chart = Center(
          child: AnimatedDonutChart(
            key: ValueKey('${widget.rangeLabel}_${widget.expenses.length}'),
            size: 190,
            strokeWidth: 34,
            showLabels: true,
            segments: sorted
                .map(
                  (entry) => DonutSegment(
                    value: entry.value,
                    color: _donutColorFor(entry.key),
                  ),
                )
                .toList(),
            centerChild: _CenterTotalLabel(total: total, symbol: widget.symbol),
            onSegmentTap: (idx) {
              if (idx < sorted.length) {
                _showCategoryRecords(context, sorted[idx]);
              }
            },
          ),
        );

        final legendItems = sorted.take(6).map((entry) => _LegendRow(
          entry: entry,
          total: total,
          symbol: widget.symbol,
          onTap: () => _showCategoryRecords(context, entry),
        )).toList();

        if (bounded) {
          // Bounded height (in PageView): chart stays fixed, only legend scrolls
          return Container(
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 20, 18, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        'BY CATEGORY',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: brand.inkSoft,
                          letterSpacing: 0.8,
                        ),
                      ),
                      const SizedBox(height: 16),
                      chart,
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                    children: legendItems,
                  ),
                ),
              ],
            ),
          );
        }

        // Unbounded height (stacked/report mode): inline layout
        return _FloatCard(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'BY CATEGORY',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: brand.inkSoft,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 16),
              chart,
              const SizedBox(height: 22),
              ...legendItems,
            ],
          ),
        );
      },
    );
  }

  void _showCategoryRecords(
    BuildContext context,
    MapEntry<String, double> entry,
  ) {
    HapticFeedback.selectionClick();
    final records =
        widget.expenses.where((e) => e.category == entry.key).toList()
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
            symbol: widget.symbol,
            rangeLabel: widget.rangeLabel,
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
      width: 90,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'SPENT',
            style: TextStyle(
              fontSize: 9,
              color: brand.inkSoft,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              formatMoney(symbol, total),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
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
    final c = _donutColorFor(entry.key);
    final pct = total == 0 ? 0.0 : entry.value / total;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(color: c, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.categoryLabel(entry.key),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                ),
                Text(
                  '${(pct * 100).toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: brand.inkSoft,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  formatMoney(symbol, entry.value),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 4,
                backgroundColor: brand.background,
                valueColor: AlwaysStoppedAnimation<Color>(c),
              ),
            ),
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
                        fontWeight: FontWeight.w700,
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
                      fontWeight: FontWeight.w700,
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

  const _RecordRow({required this.expense, required this.symbol});

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
                fontWeight: FontWeight.w600,
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
                  formatMoney(
                    expense.originalCurrency != null
                        ? (kSupportedCurrencies[expense.originalCurrency!] ?? expense.originalCurrency!)
                        : symbol,
                    expense.amount,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppColors.expense,
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

// ── Manage-visibility sheet ────────────────────────────────────

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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
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

// ── Donut chart color palette ───────────────────────────────────
// Soft, premium mid-tone colors tuned for chart rendering — inspired
// by the welcome screen donut illustration. Intentionally separate
// from kCategoryStyles.accent which is designed for ink-on-pastel.

Color _donutColorFor(String category) {
  const colors = <String, Color>{
    'Food': Color(0xFFE8925A), // warm peach-amber
    'Transport': Color(0xFF5FABF5), // calm sky blue
    'Shopping': Color(0xFF9B8BE8), // soft lavender
    'Entertainment': Color(0xFFE87878), // soft coral-rose
    'Health': Color(0xFF5DC98A), // fresh mint green
    'Bills': Color(0xFFD4A845), // warm gold
    'Groceries': Color(0xFF4BC4A8), // bright teal
    'Salary': Color(0xFF5DC98A), // fresh mint green
    'Others': Color(0xFFA0A0AA), // neutral slate
    'Transfer': Color(0xFF78AEDD), // muted blue-gray
  };
  return colors[category] ?? const Color(0xFFA0A0AA);
}
