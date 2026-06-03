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

import '../../models/account.dart';
import '../../models/expense.dart';
import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../services/i18n.dart';
import '../../services/prefs_service.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_donut_chart.dart';
import '../../widgets/exchange_rate_sheet.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/section_card.dart';
import '../../widgets/sticky_header_scaffold.dart';

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  _StatsPeriod _period = _StatsPeriod.month;
  late DateTime _anchor;
  bool _isSharing = false;
  DateTime? _customStart;
  DateTime? _customEnd;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchor = DateTime(now.year, now.month, 1);
  }

  _StatsRange _currentRange(BuildContext context) {
    final useCustomCycle = ref.watch(useCustomCycleProvider);
    final cycleDayStart = ref.watch(cycleDayStartProvider);

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
        if (useCustomCycle && cycleDayStart > 1 && cycleDayStart <= 28) {
          // If the anchor is the current calendar month and today is before the
          // cycle start day, the active cycle started in the previous month.
          final today = DateTime.now();
          final isCurrentMonth =
              _anchor.year == today.year && _anchor.month == today.month;
          final effectiveMonth =
              (isCurrentMonth && today.day < cycleDayStart)
                  ? _anchor.month - 1
                  : _anchor.month;
          final cycleStart = DateTime(_anchor.year, effectiveMonth, cycleDayStart);
          final cycleEnd = DateTime(_anchor.year, effectiveMonth + 1, cycleDayStart);
          return _StatsRange(
            start: cycleStart,
            endExclusive: cycleEnd,
            label:
                '${DateFormat('d MMM').format(cycleStart)} – '
                '${DateFormat('d MMM').format(cycleEnd.subtract(const Duration(days: 1)))}',
          );
        }
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
      case _StatsPeriod.custom:
        if (_customStart == null || _customEnd == null) {
          return _StatsRange(start: null, endExclusive: null, label: context.t('stats.filterAll'));
        }
        return _StatsRange(
          start: _customStart,
          endExclusive: _customEnd!.add(const Duration(days: 1)),
          label:
              '${DateFormat('d MMM').format(_customStart!)} – '
              '${DateFormat('d MMM').format(_customEnd!)}',
        );
    }
  }

  _StatsRange? _prevRange() {
    final useCustomCycle = ref.watch(useCustomCycleProvider);
    final cycleDayStart = ref.watch(cycleDayStartProvider);

    switch (_period) {
      case _StatsPeriod.week:
        final start = _startOfWeek(_anchor).subtract(const Duration(days: 7));
        return _StatsRange(
          start: start,
          endExclusive: start.add(const Duration(days: 7)),
          label: DateFormat('MMM d').format(start),
        );
      case _StatsPeriod.month:
        if (useCustomCycle && cycleDayStart > 1 && cycleDayStart <= 28) {
          final today = DateTime.now();
          final isCurrentMonth =
              _anchor.year == today.year && _anchor.month == today.month;
          final effectiveMonth =
              (isCurrentMonth && today.day < cycleDayStart)
                  ? _anchor.month - 1
                  : _anchor.month;
          final prevCycleStart = DateTime(_anchor.year, effectiveMonth - 1, cycleDayStart);
          final prevCycleEnd = DateTime(_anchor.year, effectiveMonth, cycleDayStart);
          return _StatsRange(
            start: prevCycleStart,
            endExclusive: prevCycleEnd,
            label: DateFormat('d MMM').format(prevCycleStart),
          );
        }
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
      case _StatsPeriod.custom:
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
        case _StatsPeriod.custom:
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
      child: StickyHeaderScaffold(
        header: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopActionBar(
                onManage: () => _showVisibilitySheet(context),
                onShare: _isSharing ? null : () => _shareSnapshot(context),
              ),
              const SizedBox(height: 16),
              _SlidingPeriodTabs(
                period: _period,
                onChanged: (p) {
                  if (p == _StatsPeriod.custom) {
                    _showDateRangePicker();
                    return;
                  }
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
                      case _StatsPeriod.custom:
                        break;
                    }
                  });
                },
              ),
              const SizedBox(height: 10),
              _PeriodNavRow(
                label: range.label,
                showNav: _period != _StatsPeriod.all && _period != _StatsPeriod.custom,
                showCustom: _period == _StatsPeriod.custom,
                customStart: _customStart,
                customEnd: _customEnd,
                onPrev: () => _step(-1),
                onNext: () => _step(1),
                onDateRange: _showDateRangePicker,
              ),
            ],
          ),
        ),
        bodyBuilder: (sc) => allExpensesAsync.when(
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

            final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];

            return SingleChildScrollView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 120),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildReport(
                    visibleSections: visibleSections,
                    rangedExpenses: rangedExpenses,
                    rangedIncome: rangedIncome,
                    allExpenses: allExpenses,
                    range: range,
                    symbol: symbol,
                    accounts: accounts,
                    rangeLabel: range.label,
                    showNav: false,
                    onPrev: () => _step(-1),
                    onNext: () => _step(1),
                  ),
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: _showDateRangePicker,
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        padding: _period == _StatsPeriod.custom
                            ? const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 7)
                            : const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _period == _StatsPeriod.custom
                              ? AppActionBlue.color
                              : context.brand.background,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: _period == _StatsPeriod.custom &&
                                _customStart != null
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(CupertinoIcons.calendar,
                                      size: 13, color: Colors.white),
                                  const SizedBox(width: 5),
                                  Text(
                                    '${DateFormat('d/M').format(_customStart!)}–${DateFormat('d/M').format(_customEnd!)}',
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            : Icon(
                                CupertinoIcons.calendar,
                                size: 16,
                                color: context.brand.inkSoft,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
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
    List<Account> accounts = const [],
    bool forReport = false,
    String rangeLabel = '',
    bool showNav = false,
    VoidCallback? onPrev,
    VoidCallback? onNext,
  }) {
    const showLine = false;
    final showDonut = visibleSections.contains('donutChart');

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showDonut || showLine)
          _ChartsCarousel(
            showLine: showLine,
            showDonut: showDonut,
            allExpenses: allExpenses,
            rangedExpenses: rangedExpenses,
            range: range,
            period: _period,
            symbol: symbol,
            stacked: forReport,
            rangeLabel: rangeLabel,
            showNav: showNav,
            onPrev: onPrev,
            onNext: onNext,
          ),
        const SizedBox(height: 14),
        _GroupSpendCard(range: range, symbol: symbol),
      ],
    );
  }

  void _showDateRangePicker() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      builder: (_) => _DateRangeSheet(
        initialStart: _customStart,
        initialEnd: _customEnd,
        onConfirm: (start, end) {
          if (mounted) {
            setState(() {
              _customStart = start;
              _customEnd = end;
              _period = _StatsPeriod.custom;
            });
          }
        },
      ),
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

enum _StatsPeriod { week, month, sixMonth, year, all, custom }

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

// ── Sliding period tabs (replaces pills) ──────────────────────────────────────

class _SlidingPeriodTabs extends StatelessWidget {
  final _StatsPeriod period;
  final ValueChanged<_StatsPeriod> onChanged;

  const _SlidingPeriodTabs({required this.period, required this.onChanged});

  static const _tabs = [
    _StatsPeriod.week,
    _StatsPeriod.month,
    _StatsPeriod.sixMonth,
    _StatsPeriod.year,
  ];

  String _label(BuildContext context, _StatsPeriod p) => switch (p) {
    _StatsPeriod.week => context.t('stats.filterWeek'),
    _StatsPeriod.month => context.t('stats.filterMonth'),
    _StatsPeriod.sixMonth => context.t('stats.filterSixMonth'),
    _StatsPeriod.year => context.t('stats.filterYear'),
    _ => '',
  };

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedIdx = _tabs.indexOf(period).clamp(0, _tabs.length - 1);
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.72);

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final tabW = constraints.maxWidth / _tabs.length;
        return Container(
          height: 40,
          decoration: BoxDecoration(
            color: trackColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : Colors.black.withValues(alpha: 0.06),
              width: 0.8,
            ),
          ),
          child: Stack(
            children: [
              // Animated thumb
              AnimatedPositioned(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                left: selectedIdx * tabW + 3,
                top: 3,
                bottom: 3,
                width: tabW - 6,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: brand.accentDark,
                    borderRadius: BorderRadius.circular(17),
                    boxShadow: [
                      BoxShadow(
                        color: brand.accentDark.withValues(alpha: 0.30),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              // Tab labels (on top of thumb)
              Row(
                children: [
                  for (int i = 0; i < _tabs.length; i++)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onChanged(_tabs[i]);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Center(
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: period == _tabs[i]
                                  ? foregroundOn(brand.accentDark)
                                  : brand.inkSoft,
                            ),
                            child: Text(_label(context, _tabs[i])),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Period navigation row (< label >) ───────────────────────────────────────

class _PeriodNavRow extends StatelessWidget {
  final String label;
  final bool showNav;
  final bool showCustom;
  final DateTime? customStart;
  final DateTime? customEnd;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onDateRange;

  const _PeriodNavRow({
    required this.label,
    required this.showNav,
    required this.showCustom,
    required this.customStart,
    required this.customEnd,
    required this.onPrev,
    required this.onNext,
    required this.onDateRange,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        // Previous button
        if (showNav)
          _NavArrow(
            icon: CupertinoIcons.chevron_left,
            onTap: onPrev,
            brand: brand,
          )
        else
          const SizedBox(width: 34),
        // Period label (center)
        Expanded(
          child: GestureDetector(
            onTap: showCustom ? onDateRange : null,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 0.15),
                    end: Offset.zero,
                  ).animate(anim),
                  child: child,
                ),
              ),
              child: Container(
                key: ValueKey(label),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: showCustom
                    ? BoxDecoration(
                        color: AppActionBlue.color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                      )
                    : null,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showCustom) ...[
                      Icon(
                        CupertinoIcons.calendar,
                        size: 13,
                        color: AppActionBlue.color,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: showCustom
                            ? AppActionBlue.color
                            : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Next button
        if (showNav)
          _NavArrow(
            icon: CupertinoIcons.chevron_right,
            onTap: onNext,
            brand: brand,
          )
        else
          const SizedBox(width: 34),
      ],
    );
  }
}

class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final BrandColors brand;

  const _NavArrow({required this.icon, required this.onTap, required this.brand});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 16, color: brand.ink),
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
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hasComparison = prevTotal > 0;
    final pctChange = hasComparison
        ? ((currentTotal - prevTotal) / prevTotal * 100)
        : 0.0;
    final isIncrease = pctChange > 0;
    final periodHeader = _buildPeriodHeader(context);

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
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        formatMoney(symbol, currentTotal),
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -1.5,
                          color: brand.ink,
                        ),
                      ),
                    ],
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
              context
                  .t('stats.vsPrevious')
                  .replaceAll('{label}', prevLabel)
                  .replaceAll('{amount}', formatMoney(symbol, prevTotal)),
              style: TextStyle(
                fontSize: 12,
                color: brand.inkSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _buildPeriodHeader(BuildContext context) {
    switch (period) {
      case _StatsPeriod.week:
        return context.t('stats.periodHeader.week').replaceAll(
            '{date}', DateFormat('MMM d').format(anchor).toUpperCase());
      case _StatsPeriod.month:
        return context.t('stats.periodHeader.month').replaceAll(
            '{month}', DateFormat('MMMM').format(anchor).toUpperCase());
      case _StatsPeriod.sixMonth:
        return context.t('stats.periodHeader.sixMonth');
      case _StatsPeriod.year:
        return context.t('stats.periodHeader.year').replaceAll(
            '{year}', DateFormat('yyyy').format(anchor));
      case _StatsPeriod.all:
        return context.t('stats.periodHeader.all');
      case _StatsPeriod.custom:
        return context.t('stats.periodHeader.custom');
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
  final bool bare;

  const _LineChartCard({
    required this.expenses,
    required this.range,
    required this.period,
    required this.symbol,
    this.bare = false,
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

    final content = Padding(
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
                  context: ctx,
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

    if (widget.bare) return content;
    return _FloatCard(
      padding: EdgeInsets.zero,
      child: content,
    );
  }

  String _subtitle(BuildContext context) {
    return switch (widget.period) {
      _StatsPeriod.week => context.t('stats.lineChart.weekSubtitle'),
      _StatsPeriod.month => context.t('stats.lineChart.monthSubtitle'),
      _StatsPeriod.sixMonth => context.t('stats.lineChart.monthSubtitle'),
      _StatsPeriod.year => context.t('stats.lineChart.yearSubtitle'),
      _StatsPeriod.all => context.t('stats.lineChart.allSubtitle'),
      _StatsPeriod.custom => context.t('stats.lineChart.allSubtitle'),
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
        final end = range.endExclusive!;
        final totalDays = end.difference(start).inDays;
        final values = List<double>.filled(totalDays, 0);
        for (final e in expenses) {
          final d = DateTime(e.date.year, e.date.month, e.date.day);
          if (!d.isBefore(start) && d.isBefore(end)) {
            final idx = d.difference(start).inDays;
            if (idx >= 0 && idx < totalDays) values[idx] += e.convertedAmount;
          }
        }
        final labels = [
          for (int i = 0; i < totalDays; i++)
            '${start.add(Duration(days: i)).day}',
        ];
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
      case _StatsPeriod.custom:
        return _emptySeries;
    }
  }

  Widget _buildChart({
    required BuildContext context,
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
                  ? context.t('stats.day').replaceAll('{label}', label)
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
  final String rangeLabel;
  final bool showNav;
  final VoidCallback? onPrev;
  final VoidCallback? onNext;

  const _ChartsCarousel({
    required this.showLine,
    required this.showDonut,
    required this.allExpenses,
    required this.rangedExpenses,
    required this.range,
    required this.period,
    required this.symbol,
    required this.stacked,
    this.rangeLabel = '',
    this.showNav = false,
    this.onPrev,
    this.onNext,
  });

  @override
  State<_ChartsCarousel> createState() => _ChartsCarouselState();
}

class _ChartsCarouselState extends State<_ChartsCarousel> {
  late PageController _controller;
  int _page = 0;
  double _pageOffset = 0.0;

  void _onControllerUpdate() {
    if (mounted) setState(() => _pageOffset = _controller.page ?? _page.toDouble());
  }

  @override
  void initState() {
    super.initState();
    _controller = PageController();
    _controller.addListener(_onControllerUpdate);
  }

  @override
  void didUpdateWidget(covariant _ChartsCarousel old) {
    super.didUpdateWidget(old);
    final pageCount = _pages().length;
    if (_page >= pageCount && pageCount > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() { _page = 0; _pageOffset = 0.0; });
        if (_controller.hasClients) _controller.jumpToPage(0);
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerUpdate);
    _controller.dispose();
    super.dispose();
  }

  List<_ChartPage> _pages() {
    return [
      if (widget.showDonut)
        _ChartPage(
          id: 'donut',
          label: context.t('stats.byCategory'),
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
          label: context.t('stats.trend'),
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

    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Controls row: < period > — inside the card
          if (widget.showNav) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 14, 12),
              child: Row(
                children: [
                  _navBtn(context, CupertinoIcons.chevron_left, widget.onPrev ?? () {}),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.rangeLabel.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: brand.inkSoft,
                        letterSpacing: 0.8,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 6),
                  _navBtn(context, CupertinoIcons.chevron_right, widget.onNext ?? () {}),
                ],
              ),
            ),
            Container(height: 0.5, color: brand.divider),
            const SizedBox(height: 12),
          ],
          // "By Category" / "Trend" — sliding pill tabs
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: LayoutBuilder(
              builder: (context, constraints) {
                const gap = 8.0;
                final pillW = (constraints.maxWidth - gap * (pages.length - 1)) / pages.length;
                final pillLeft = _pageOffset * (pillW + gap);
                return SizedBox(
                  height: 40,
                  child: Stack(
                    children: [
                      // Sliding selected pill
                      Positioned(
                        left: pillLeft,
                        top: 0,
                        bottom: 0,
                        width: pillW,
                        child: Container(
                          decoration: BoxDecoration(
                            color: brand.accentDark,
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      // Labels row — tappable to switch page
                      Row(
                        children: [
                          for (var i = 0; i < pages.length; i++) ...[
                            if (i > 0) const SizedBox(width: gap),
                            Expanded(
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () {
                                  HapticFeedback.selectionClick();
                                  _controller.animateToPage(
                                    i,
                                    duration: const Duration(milliseconds: 300),
                                    curve: Curves.easeOutCubic,
                                  );
                                },
                                child: Center(
                                  child: Builder(builder: (context) {
                                    final dist = (_pageOffset - i).abs().clamp(0.0, 1.0);
                                    final fg = brand.accentDark.computeLuminance() < 0.5
                                        ? Colors.white
                                        : Colors.black;
                                    final color = Color.lerp(fg, brand.inkSoft, dist)!;
                                    return Text(
                                      pages[i].label,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: color,
                                      ),
                                    );
                                  }),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          // Chart content — chart pages render bare (no own card background)
          SizedBox(
            height: 540,
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() { _page = i; _pageOffset = i.toDouble(); }),
              children: [
                for (final page in pages)
                  if (page.id == 'donut')
                    _CategoryCard(
                      expenses: widget.rangedExpenses,
                      symbol: widget.symbol,
                      rangeLabel: widget.range.label,
                      forReport: widget.stacked,
                      bare: true,
                    )
                  else
                    SingleChildScrollView(
                      child: _LineChartCard(
                        expenses: widget.allExpenses,
                        range: widget.range,
                        period: widget.period,
                        symbol: widget.symbol,
                        bare: true,
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navBtn(BuildContext context, IconData icon, VoidCallback onTap) {
    final brand = context.brand;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 16, color: brand.ink),
      ),
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
      _StatsPeriod.sixMonth => 'stats.filterSixMonth',
      _StatsPeriod.year => 'stats.filterYear',
      _StatsPeriod.all => 'stats.filterAll',
      _StatsPeriod.custom => 'stats.filterCustom',
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
  final bool bare;

  const _CategoryCard({
    required this.expenses,
    required this.symbol,
    required this.rangeLabel,
    this.forReport = false,
    this.bare = false,
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
      final emptyContent = Padding(
        padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: brand.background,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                CupertinoIcons.chart_pie_fill,
                size: 28,
                color: brand.inkSoft.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              context.t('stats.noDataTitle'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: brand.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.t('stats.noCategorySpend'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: brand.inkSoft,
                height: 1.45,
              ),
            ),
          ],
        ),
      );
      if (widget.bare) return emptyContent;
      return _FloatCard(
        padding: EdgeInsets.zero,
        child: emptyContent,
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
          final inner = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      context.t('stats.byCategoryHeader'),
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
          );
          if (widget.bare) return inner;
          return Container(
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
            ),
            child: inner,
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
                context.t('stats.byCategoryHeader'),
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
            context.t('stats.spent'),
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

// ── iOS-style date range picker sheet ─────────────────────────

class _DateRangeSheet extends StatefulWidget {
  final DateTime? initialStart;
  final DateTime? initialEnd;
  final void Function(DateTime start, DateTime end) onConfirm;

  const _DateRangeSheet({
    required this.onConfirm,
    this.initialStart,
    this.initialEnd,
  });

  @override
  State<_DateRangeSheet> createState() => _DateRangeSheetState();
}

class _DateRangeSheetState extends State<_DateRangeSheet> {
  DateTime? _start;
  DateTime? _end;
  late DateTime _month;

  static const _weekdays = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];

  @override
  void initState() {
    super.initState();
    _start = widget.initialStart;
    _end = widget.initialEnd;
    final ref = widget.initialEnd ?? widget.initialStart ?? DateTime.now();
    _month = DateTime(ref.year, ref.month);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  void _onDayTap(DateTime day) {
    setState(() {
      if (_start == null || (_start != null && _end != null)) {
        _start = day;
        _end = null;
      } else {
        if (day.isBefore(_start!)) {
          _end = _start;
          _start = day;
        } else {
          _end = day;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppActionBlue.color;
    final rangeColor = accent.withValues(alpha: isDark ? 0.22 : 0.12);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    String rangeLabel() {
      if (_start == null) return context.t('stats.selectStartDate');
      if (_end == null) return '${DateFormat('d MMM yyyy').format(_start!)} — ?';
      return '${DateFormat('d MMM').format(_start!)} – ${DateFormat('d MMM yyyy').format(_end!)}';
    }

    final firstOfMonth = _month;
    final startWeekday = firstOfMonth.weekday % 7;
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);

    Widget dayCell(int day) {
      final date = DateTime(_month.year, _month.month, day);
      final isStart = _start != null && _isSameDay(date, _start!);
      final isEnd = _end != null && _isSameDay(date, _end!);
      final isSelected = isStart || isEnd;
      final inRange = _start != null &&
          _end != null &&
          !date.isBefore(_start!) &&
          !date.isAfter(_end!);
      final isToday = _isSameDay(date, today);
      final isFuture = date.isAfter(today);

      final textColor = isFuture
          ? brand.inkSoft.withValues(alpha: 0.35)
          : isSelected
              ? Colors.white
              : brand.ink;

      // Range strip: full-width background for interior days, half-width for edges
      Widget cell = Container(
        decoration: inRange && !isStart && !isEnd
            ? BoxDecoration(color: rangeColor)
            : (isStart && _end != null
                ? BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.transparent, rangeColor],
                    ),
                  )
                : isEnd && _start != null
                    ? BoxDecoration(
                        gradient: LinearGradient(
                          colors: [rangeColor, Colors.transparent],
                        ),
                      )
                    : null),
        child: Center(
          child: Container(
            width: 36,
            height: 36,
            decoration: isSelected
                ? BoxDecoration(color: accent, shape: BoxShape.circle)
                : isToday
                    ? BoxDecoration(
                        border: Border.all(color: accent, width: 1.5),
                        shape: BoxShape.circle,
                      )
                    : null,
            child: Center(
              child: Text(
                '$day',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: textColor,
                ),
              ),
            ),
          ),
        ),
      );

      if (isFuture) return cell;
      return GestureDetector(onTap: () => _onDayTap(date), child: cell);
    }

    final cells = <Widget>[
      for (var i = 0; i < startWeekday; i++) const SizedBox(),
      for (var d = 1; d <= daysInMonth; d++) dayCell(d),
    ];

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 60, 0, 0),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: brand.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // ── Sheet header ─────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('stats.selectRange'),
                          style: TextStyle(
                            fontSize: 13,
                            color: brand.inkSoft,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          rangeLabel(),
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: brand.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_start != null && _end != null)
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      color: accent,
                      borderRadius: BorderRadius.circular(20),
                      minimumSize: Size.zero,
                      onPressed: () {
                        widget.onConfirm(_start!, _end!);
                        Navigator.pop(context);
                      },
                      child: Text(
                        context.t('budget.done'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(height: 0.5, color: brand.divider),
            const SizedBox(height: 12),
            // ── Month navigation ─────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() {
                      _month = DateTime(_month.year, _month.month - 1);
                    }),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: brand.background,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(CupertinoIcons.chevron_left,
                          size: 14, color: brand.ink),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      DateFormat('MMMM yyyy').format(_month),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: brand.ink,
                        letterSpacing: -0.2,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _month.year == today.year &&
                            _month.month == today.month
                        ? null
                        : () => setState(() {
                              _month =
                                  DateTime(_month.year, _month.month + 1);
                            }),
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: brand.background,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.chevron_right,
                        size: 14,
                        color: _month.year == today.year &&
                                _month.month == today.month
                            ? brand.inkSoft.withValues(alpha: 0.3)
                            : brand.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // ── Weekday headers ──────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  for (final d in _weekdays)
                    Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: brand.inkSoft,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // ── Calendar grid ────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: GridView.count(
                crossAxisCount: 7,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.0,
                children: cells,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
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

// ── Group Spend card ─────────────────────────────────────────────────────────

const _kMemberBgs = [
  Color(0xFFEAE3F8), Color(0xFFD7F4E5), Color(0xFFDBEAFE),
  Color(0xFFFEF3C7), Color(0xFFFFEDD5), Color(0xFFFCE7F3),
];
const _kMemberFgs = [
  Color(0xFF5A4AAB), Color(0xFF1FBE71), Color(0xFF2563EB),
  Color(0xFFD97706), Color(0xFFEA580C), Color(0xFFDB2777),
];

// Returns each member's consumed share for the given expenses.
Map<String, double> _memberShares(
  List<GroupExpenseItem> expenses,
  List<String> memberUids,
) {
  final result = <String, double>{for (final uid in memberUids) uid: 0};
  for (final e in expenses) {
    if (e.splitPercents != null && e.splitPercents!.isNotEmpty) {
      for (final entry in e.splitPercents!.entries) {
        result[entry.key] = (result[entry.key] ?? 0) + e.amount * (entry.value / 100.0);
      }
    } else if (e.splitBetween.isNotEmpty) {
      final share = e.amount / e.splitBetween.length;
      for (final uid in e.splitBetween) {
        result[uid] = (result[uid] ?? 0) + share;
      }
    }
  }
  return result;
}

// Returns a specific member's consumed share per category.
Map<String, double> _memberCategoryShares(
  List<GroupExpenseItem> expenses,
  String uid,
) {
  final result = <String, double>{};
  for (final e in expenses) {
    double share;
    if (e.splitPercents != null && e.splitPercents!.containsKey(uid)) {
      share = e.amount * (e.splitPercents![uid]! / 100.0);
    } else if (e.splitBetween.contains(uid)) {
      share = e.amount / e.splitBetween.length;
    } else {
      continue;
    }
    result[e.category] = (result[e.category] ?? 0) + share;
  }
  return result;
}

class _GroupSpendCard extends ConsumerWidget {
  final _StatsRange range;
  final String symbol;

  const _GroupSpendCard({required this.range, required this.symbol});

  bool _inRange(GroupExpenseItem e) {
    final d = DateTime(e.date.year, e.date.month, e.date.day);
    if (range.start != null && d.isBefore(range.start!)) return false;
    if (range.endExclusive != null && !d.isBefore(range.endExclusive!)) return false;
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? [];
    if (groups.isEmpty) return const SizedBox.shrink();

    final groupData = <({
      String id,
      String name,
      List<GroupMember> members,
      List<GroupExpenseItem> expenses,
      double total,
    })>[];

    for (final group in groups) {
      final expenses = ref.watch(groupExpensesProvider(group.id)).valueOrNull ?? [];
      final ranged = expenses.where(_inRange).toList();
      final total = ranged.fold(0.0, (s, e) => s + e.amount);
      if (total == 0) continue;
      groupData.add((
        id: group.id,
        name: group.name,
        members: group.members,
        expenses: ranged,
        total: total,
      ));
    }

    if (groupData.isEmpty) return const SizedBox.shrink();

    // Resolve live display names for every member across all groups.
    final resolvedNames = <String, String>{};
    final currentUid = ref.watch(authStateProvider).valueOrNull?.uid;
    final myLiveName = ref.watch(userNameProvider);
    for (final g in groupData) {
      for (final m in g.members) {
        if (m.uid == currentUid && myLiveName.isNotEmpty) {
          resolvedNames[m.uid] = myLiveName;
        } else {
          final live = ref.watch(memberDisplayNameProvider(m.uid)).valueOrNull ?? '';
          resolvedNames[m.uid] = live.isNotEmpty ? live : m.displayName;
        }
      }
    }

    final overallTotal = groupData.fold(0.0, (s, g) => s + g.total);

    return _FloatCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.t('stats.groupSpending'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: brand.inkSoft,
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: brand.background,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${groupData.length}',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: brand.inkSoft),
                ),
              ),
            ],
          ),

          for (int gi = 0; gi < groupData.length; gi++) ...[
            const SizedBox(height: 16),
            _GroupSectionView(
              groupId: groupData[gi].id,
              groupName: groupData.length > 1 ? groupData[gi].name : null,
              members: groupData[gi].members,
              expenses: groupData[gi].expenses,
              total: groupData[gi].total,
              symbol: symbol,
              resolvedNames: resolvedNames,
            ),
            if (gi < groupData.length - 1) ...[
              const SizedBox(height: 14),
              Divider(height: 2, color: brand.divider),
            ],
          ],

          const SizedBox(height: 14),
          Divider(height: 1, color: brand.divider),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.t('stats.totalGroupSpend'),
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: brand.inkSoft),
              ),
              Text(
                formatMoney(symbol, overallTotal),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: brand.ink),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Per-group section with vertical bar chart + filterable donut ──────────────

class _GroupSectionView extends StatefulWidget {
  final String groupId;
  final String? groupName;
  final List<GroupMember> members;
  final List<GroupExpenseItem> expenses;
  final double total;
  final String symbol;
  final Map<String, String> resolvedNames;

  const _GroupSectionView({
    required this.groupId,
    this.groupName,
    required this.members,
    required this.expenses,
    required this.total,
    required this.symbol,
    required this.resolvedNames,
  });

  @override
  State<_GroupSectionView> createState() => _GroupSectionViewState();
}

class _GroupSectionViewState extends State<_GroupSectionView> {
  String? _selectedUid; // null = All

  List<({String uid, String displayName, double spend, int colorIndex})> get _memberRows {
    final memberUids = widget.members.map((m) => m.uid).toList();
    final shares = _memberShares(widget.expenses, memberUids);
    final rows = widget.members.asMap().entries.map((e) => (
      uid: e.value.uid,
      displayName: widget.resolvedNames[e.value.uid] ?? e.value.displayName,
      spend: shares[e.value.uid] ?? 0,
      colorIndex: e.key,
    )).toList()
      ..sort((a, b) => b.spend.compareTo(a.spend));
    return rows;
  }

  Map<String, double> get _categoryData {
    if (_selectedUid != null) {
      return _memberCategoryShares(widget.expenses, _selectedUid!);
    }
    // All: total per category
    final result = <String, double>{};
    for (final e in widget.expenses) {
      result[e.category] = (result[e.category] ?? 0) + e.amount;
    }
    return result;
  }

  double get _categoryTotal {
    if (_selectedUid != null) {
      return _categoryData.values.fold(0.0, (s, v) => s + v);
    }
    return widget.total;
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final rows = _memberRows;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Optional group sub-header
        if (widget.groupName != null) ...[
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(CupertinoIcons.person_3_fill, size: 12, color: Color(0xFF1967D2)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.groupName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: brand.ink),
                ),
              ),
              Text(
                formatMoney(widget.symbol, widget.total),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: brand.ink),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],

        // Vertical bar chart
        _GroupVerticalBars(
          rows: rows,
          total: widget.total,
          symbol: widget.symbol,
        ),

        const SizedBox(height: 16),
        Divider(height: 1, color: brand.divider),
        const SizedBox(height: 14),

        // Category section header + member filter pills
        Row(
          children: [
            Text(
              context.t('stats.byCategoryHeader'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: brand.inkSoft,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _FilterPill(
                      label: context.t('stats.filterAllPeople'),
                      selected: _selectedUid == null,
                      color: const Color(0xFF1967D2),
                      onTap: () => setState(() => _selectedUid = null),
                    ),
                    ...rows.map((m) => _FilterPill(
                      label: m.displayName.split(' ').first,
                      selected: _selectedUid == m.uid,
                      color: _kMemberFgs[m.colorIndex % _kMemberFgs.length],
                      onTap: () => setState(() =>
                          _selectedUid = _selectedUid == m.uid ? null : m.uid),
                    )),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        // Donut chart
        _GroupCategoryDonut(
          key: ValueKey('${widget.groupId}_${_selectedUid ?? 'all'}'),
          byCategory: _categoryData,
          total: _categoryTotal,
          symbol: widget.symbol,
        ),
      ],
    );
  }
}

// ── Vertical bar chart ────────────────────────────────────────────────────────

class _GroupVerticalBars extends StatelessWidget {
  final List<({String uid, String displayName, double spend, int colorIndex})> rows;
  final double total;
  final String symbol;

  const _GroupVerticalBars({
    required this.rows,
    required this.total,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    const maxBarHeight = 90.0;
    final maxSpend = rows.fold(0.0, (m, r) => r.spend > m ? r.spend : m);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: rows.map((m) {
        final ratio = maxSpend > 0 ? (m.spend / maxSpend).clamp(0.0, 1.0) : 0.0;
        final fg = _kMemberFgs[m.colorIndex % _kMemberFgs.length];
        final bg = _kMemberBgs[m.colorIndex % _kMemberBgs.length];
        final initial = m.displayName.isNotEmpty ? m.displayName[0].toUpperCase() : '?';
        final pct = total > 0 ? (m.spend / total * 100).toStringAsFixed(0) : '0';

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Amount label above bar
                Text(
                  formatMoney(symbol, m.spend),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
                const SizedBox(height: 3),
                // % label
                Text(
                  '$pct%',
                  style: TextStyle(fontSize: 9, color: brand.inkSoft, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                // Animated bar
                TweenAnimationBuilder<double>(
                  duration: const Duration(milliseconds: 700),
                  curve: Curves.easeOutCubic,
                  tween: Tween(begin: 0.0, end: ratio),
                  builder: (_, v, child) => SizedBox(
                    height: maxBarHeight,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            width: double.infinity,
                            height: (v * maxBarHeight).clamp(6.0, maxBarHeight),
                            color: fg,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Avatar circle
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Center(
                    child: Text(
                      initial,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                // Name label
                Text(
                  m.displayName.split(' ').first,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: brand.inkSoft),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

// ── Member filter pill ────────────────────────────────────────────────────────

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : color,
          ),
        ),
      ),
    );
  }
}

// ── Category donut (group) ────────────────────────────────────────────────────

class _GroupCategoryDonut extends StatelessWidget {
  final Map<String, double> byCategory;
  final double total;
  final String symbol;

  const _GroupCategoryDonut({
    super.key,
    required this.byCategory,
    required this.total,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final sorted = byCategory.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    if (sorted.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            context.t('stats.noExpensesPeriod'),
            style: TextStyle(fontSize: 13, color: brand.inkSoft),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child: AnimatedDonutChart(
            size: 160,
            strokeWidth: 28,
            segments: sorted
                .map((e) => DonutSegment(value: e.value, color: _donutColorFor(e.key)))
                .toList(),
            centerChild: _GroupDonutCenter(total: total, symbol: symbol),
          ),
        ),
        const SizedBox(height: 14),
        ...sorted.take(6).map((e) {
          final c = _donutColorFor(e.key);
          final pct = total > 0 ? e.value / total : 0.0;
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
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
                        context.categoryLabel(e.key),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: brand.ink),
                      ),
                    ),
                    Text(
                      '${(pct * 100).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: brand.inkSoft),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatMoney(symbol, e.value),
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: brand.ink),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: pct.clamp(0.0, 1.0),
                    minHeight: 3,
                    backgroundColor: brand.background,
                    valueColor: AlwaysStoppedAnimation<Color>(c),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }
}

class _GroupDonutCenter extends StatelessWidget {
  final double total;
  final String symbol;

  const _GroupDonutCenter({required this.total, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SizedBox(
      width: 80,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.t('stats.total'),
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
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
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
