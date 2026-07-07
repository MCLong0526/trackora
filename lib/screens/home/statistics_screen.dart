import 'dart:io';
import 'dart:math' as math;
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
import '../../models/borrow_lending.dart'
    show BorrowLending, BorrowLendingStatus, BorrowLendingType;
import '../../models/expense.dart';
import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../models/installment.dart' show Installment, InstallmentStatus;
import '../../models/monthly_budget.dart';
import '../../models/split_bill.dart';
import '../../models/precious_metal.dart';
import '../../models/saving_plan.dart' show SavingPlan, SavingPlanStatus;
import '../../models/stock_investment.dart';
import '../../services/i18n.dart';
import '../../services/prefs_service.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_donut_chart.dart';
import '../../widgets/budget_segment_bar.dart';
import '../../widgets/exchange_rate_sheet.dart';
import '../../widgets/masked_amount.dart';
import '../../widgets/section_card.dart';
import '../../widgets/sticky_header_scaffold.dart';
import '../borrow_lending/borrow_lending_screen.dart';
import '../expenses/add_edit_expense_screen.dart';
import '../installments/installments_screen.dart';
import '../investments/investment_screen.dart';
import '../savings/saving_plans_screen.dart';

class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen>
    with SingleTickerProviderStateMixin {
  _StatsPeriod _period = _StatsPeriod.month;
  late DateTime _anchor;
  bool _isSharing = false;
  DateTime? _customStart;
  DateTime? _customEnd;
  final GlobalKey _budgetCardKey = GlobalKey();

  // Card rearrange mode: long-press a card to enter; cards jiggle (iOS style)
  // and can be dragged freely until the user taps Done.
  bool _reorderMode = false;
  late final AnimationController _jiggleCtrl;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _anchor = DateTime(now.year, now.month, 1);
    _jiggleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _jiggleCtrl.dispose();
    super.dispose();
  }

  void _exitReorderMode() {
    if (_reorderMode) setState(() => _reorderMode = false);
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
          final effectiveMonth = (isCurrentMonth && today.day < cycleDayStart)
              ? _anchor.month - 1
              : _anchor.month;
          final cycleStart = DateTime(
            _anchor.year,
            effectiveMonth,
            cycleDayStart,
          );
          final cycleEnd = DateTime(
            _anchor.year,
            effectiveMonth + 1,
            cycleDayStart,
          );
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
          return _StatsRange(
            start: null,
            endExclusive: null,
            label: context.t('stats.filterAll'),
          );
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

  /// Merges investment activity into the expense list so it shows in the
  /// breakdown:
  ///  • Normalizes the legacy precious-metal category ('Precious Metals') to
  ///    the styled key ('PreciousMetal').
  ///  • Adds stock buys/sells that were paid from an account — unlike precious
  ///    metals, stock transactions don't create a linked expense, so without
  ///    this they'd never appear in the stats by-category breakdown.
  List<Expense> _withInvestmentExpenses(List<Expense> base) {
    final normalized = [
      for (final e in base)
        e.category == 'Precious Metals'
            ? e.copyWith(category: 'PreciousMetal')
            : e,
    ];
    final stocks = ref.read(stockInvestmentsProvider).valueOrNull ?? const [];
    final metals = ref.read(preciousMetalsProvider).valueOrNull ?? const [];
    final converter = ref.read(currencyConverterProvider).valueOrNull;
    final baseCode = converter?.base;
    final pseudo = <Expense>[];
    for (final s in stocks) {
      for (final tx in s.transactions) {
        final accountId = tx['accountId'] as String?;
        if (accountId == null || accountId.isEmpty) continue;
        final qty = (tx['qty'] as num?)?.toDouble() ?? 0;
        final price = (tx['price'] as num?)?.toDouble() ?? 0;
        final amount = qty * price;
        if (amount <= 0) continue;
        final cur = tx['currency'] as String? ?? 'USD';
        final isSell = (tx['type'] as String?) == 'sell';
        final date =
            DateTime.tryParse(tx['date'] as String? ?? '') ?? s.createdAt;
        final foreign =
            converter != null && baseCode != null && cur != baseCode;
        pseudo.add(
          Expense(
            id: 'stock_${s.id}_${tx['date'] ?? date.toIso8601String()}',
            amount: amount,
            category: 'Stock',
            note: s.symbol,
            date: date,
            type: isSell ? EntryType.income : EntryType.expense,
            accountId: accountId,
            createdAt: date,
            updatedAt: date,
            originalCurrency: foreign ? cur : null,
            baseCurrencyAmount: foreign ? converter.toBase(amount, cur) : null,
          ),
        );
      }
    }

    // Precious metals only create a linked expense when an account was chosen
    // (see PreciousMetal.expenseId). Inject the account-less ones so they still
    // show in the by-category breakdown, without double-counting the rest.
    for (final m in metals) {
      if (m.expenseId != null && m.expenseId!.isNotEmpty) continue;
      if (m.totalAmount <= 0) continue;
      pseudo.add(
        Expense(
          id: 'metal_${m.id}',
          amount: m.totalAmount,
          category: 'PreciousMetal',
          note: m.metalType.label,
          date: m.date,
          type: m.action == MetalAction.buy
              ? EntryType.expense
              : EntryType.income,
          accountId: m.accountId ?? '',
          createdAt: m.date,
          updatedAt: m.date,
        ),
      );
    }

    if (pseudo.isEmpty) return normalized;
    return [...normalized, ...pseudo];
  }

  @override
  Widget build(BuildContext context) {
    final allExpensesAsync = ref.watch(allExpensesProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    // Keep these (autoDispose) providers alive across rebuilds so the
    // investment data merged in _withInvestmentExpenses stays available when
    // switching period tabs — otherwise stock entries vanish on tab change.
    ref.watch(stockInvestmentsProvider);
    ref.watch(currencyConverterProvider);
    // Watched here so the report rebuilds when the card order, budget config or
    // group list changes; `_buildReport` reads them (it also runs off-build for
    // the share snapshot, where watch isn't allowed).
    ref.watch(statsCardOrderProvider);
    ref.watch(budgetConfigProvider);
    ref.watch(myGroupsProvider);
    final hidden = ref.watch(statsHiddenCardsProvider);
    final hasHidden = _presentCardIds().any(hidden.contains);
    final range = _currentRange(context);

    // Home's budget tap routes here: switch to the Month tab and scroll the
    // Monthly Budget card into view, then clear the flag.
    ref.listen<bool>(statsFocusBudgetProvider, (_, focus) {
      if (!focus) return;
      final now = DateTime.now();
      setState(() {
        _period = _StatsPeriod.month;
        _anchor = DateTime(now.year, now.month, 1);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = _budgetCardKey.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOut,
            alignment: 0.1,
          );
        }
        ref.read(statsFocusBudgetProvider.notifier).state = false;
      });
    });

    return SafeArea(
      child: StickyHeaderScaffold(
        header: Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _TopActionBar(
                reorderMode: _reorderMode,
                hasHidden: hasHidden,
                onAdd: () => _showAddCardSheet(context),
                onDone: _exitReorderMode,
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
                showNav:
                    _period != _StatsPeriod.all &&
                    _period != _StatsPeriod.custom,
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
          data: (rawItems) {
            final allItems = _withInvestmentExpenses(rawItems);
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

            final accounts =
                ref.watch(accountsProvider).valueOrNull ?? const <Account>[];

            return SingleChildScrollView(
              controller: sc,
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 120),
              child: _buildReport(
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
            );
          },
        ),
      ),
    );
  }

  /// Card ids whose data is available right now (before applying the user's
  /// hidden set). Donut + Overview are always available; budget needs a
  /// by-category month, group spend needs at least one group.
  Set<String> _presentCardIds() {
    final cfg = ref.read(budgetConfigProvider).valueOrNull;
    final ids = <String>{'donutChart', 'importantData'};
    if (_period == _StatsPeriod.month &&
        (cfg?.isByCategory ?? false) &&
        (cfg?.categories.isNotEmpty ?? false)) {
      ids.add('monthlyBudget');
    }
    if ((ref.read(myGroupsProvider).valueOrNull ?? const []).isNotEmpty) {
      ids.add('groupSpend');
    }
    return ids;
  }

  String _cardTitle(BuildContext context, String id) => switch (id) {
    'donutChart' => context.t('stats.byCategory'),
    'monthlyBudget' => context.t('home.budget'),
    'importantData' => context.t('stats.section.importantData'),
    'groupSpend' => context.t('stats.groupSpending'),
    _ => id,
  };

  void _hideCard(String id) {
    HapticFeedback.selectionClick();
    ref.read(statsHiddenCardsProvider.notifier).hide(id);
  }

  void _showAddCardSheet(BuildContext context) {
    final hidden = ref.read(statsHiddenCardsProvider);
    final hiddenPresent = _presentCardIds()
        .where(hidden.contains)
        .toList(growable: false);
    if (hiddenPresent.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final brand = ctx.brand;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
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
                  context.t('stats.addCardTitle'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
                const SizedBox(height: 14),
                for (final id in hiddenPresent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref.read(statsHiddenCardsProvider.notifier).show(id);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: brand.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _cardTitle(context, id),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: brand.ink,
                                ),
                              ),
                            ),
                            Icon(
                              CupertinoIcons.add_circled_solid,
                              size: 22,
                              color: AppActionBlue.color,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildReport({
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

    // Build every available card; the user's hidden set is applied afterwards.
    final cfg = ref.read(budgetConfigProvider).valueOrNull;
    final showBudget =
        _period == _StatsPeriod.month &&
        (cfg?.isByCategory ?? false) &&
        (cfg?.categories.isNotEmpty ?? false);
    final hasGroups =
        (ref.read(myGroupsProvider).valueOrNull ?? const []).isNotEmpty;

    final cards = <String, Widget>{};
    {
      Widget donut = _ChartsCarousel(
        showLine: showLine,
        showDonut: true,
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
      );
      // The date-range button belongs to the "By category" chart, so it rides
      // along when the card is reordered instead of floating over the page.
      if (!forReport) {
        donut = Stack(
          clipBehavior: Clip.none,
          children: [
            donut,
            Positioned(top: 12, right: 12, child: _dateRangeButton(context)),
          ],
        );
      }
      cards['donutChart'] = donut;
    }
    if (showBudget) {
      cards['monthlyBudget'] = _BudgetByCategoryCard(
        // The shared-snapshot pass rebuilds this report off-screen; only the
        // live on-screen card carries the scroll key to avoid a duplicate.
        key: forReport ? null : _budgetCardKey,
        symbol: symbol,
        forReport: forReport,
      );
    }
    cards['importantData'] = const _FinancialSummaryCard();
    if (hasGroups) {
      cards['groupSpend'] = _GroupSpendCard(range: range, symbol: symbol);
    }

    final hidden = ref.read(statsHiddenCardsProvider);

    // Share snapshot: static column in default order, hidden cards excluded.
    if (forReport) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final id in PrefsService.defaultStatsCardOrder)
            if (cards[id] != null && !hidden.contains(id))
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: cards[id],
              ),
        ],
      );
    }

    final savedOrder = ref.read(statsCardOrderProvider);
    final order = <String>[
      ...savedOrder.where(
        (id) => cards.containsKey(id) && !hidden.contains(id),
      ),
      ...cards.keys.where(
        (id) => !savedOrder.contains(id) && !hidden.contains(id),
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Always-visible affordance so users know cards can be rearranged.
        if (order.length > 1) _reorderBanner(context),
        ReorderableListView(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          buildDefaultDragHandles: false,
          // Keep the lifted card looking like a card (rounded, soft shadow)
          // instead of the default sharp Material rectangle.
          proxyDecorator: (child, index, animation) {
            return AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                final t = Curves.easeInOut.transform(animation.value);
                return Transform.scale(
                  scale: 1 + 0.03 * t,
                  child: Material(
                    color: Colors.transparent,
                    elevation: 8 * t,
                    shadowColor: Colors.black.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    child: child,
                  ),
                );
              },
              child: child,
            );
          },
          onReorderStart: (_) {
            HapticFeedback.mediumImpact();
            if (!_reorderMode) setState(() => _reorderMode = true);
          },
          onReorder: (oldIndex, newIndex) {
            HapticFeedback.selectionClick();
            if (newIndex > oldIndex) newIndex -= 1;
            final next = [...order];
            next.insert(newIndex, next.removeAt(oldIndex));
            // Keep ids not currently visible so their relative order sticks.
            final full = <String>[
              ...next,
              ...savedOrder.where((id) => !next.contains(id)),
            ];
            ref.read(statsCardOrderProvider.notifier).setOrder(full);
          },
          children: [
            for (var i = 0; i < order.length; i++)
              _reorderableCard(i, order[i], cards[order[i]]!, order.length > 1),
          ],
        ),
      ],
    );
  }

  /// Wraps a report card with its reorder drag handle, and—while in reorder
  /// mode—an iOS-style jiggle (alternating phase per card, like Quick Add) plus
  /// a corner hide button. [canHide] is false for the last remaining card so at
  /// least one card always stays on the page.
  Widget _reorderableCard(int index, String id, Widget card, bool canHide) {
    Widget content = Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: AbsorbPointer(absorbing: _reorderMode, child: card),
    );
    if (_reorderMode) {
      content = AnimatedBuilder(
        animation: _jiggleCtrl,
        builder: (_, child) {
          final dir = index.isEven ? 1.0 : -1.0;
          final angle = 0.014 * dir * (_jiggleCtrl.value * 2 - 1);
          return Transform.rotate(angle: angle, child: child);
        },
        child: content,
      );
      // Static (non-jiggling) hide badge at the top-left corner, iOS style.
      if (canHide) {
        content = Stack(
          clipBehavior: Clip.none,
          children: [
            content,
            Positioned(
              top: -4,
              left: -4,
              child: GestureDetector(
                onTap: () => _hideCard(id),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: AppColors.expense,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    CupertinoIcons.minus,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        );
      }
    }
    return ReorderableDelayedDragStartListener(
      key: ValueKey(id),
      index: index,
      child: content,
    );
  }

  // Plain inline hint (Done lives in the header tick button).
  Widget _reorderBanner(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(left: 2, bottom: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.arrow_up_arrow_down,
            size: 12,
            color: brand.inkSoft,
          ),
          const SizedBox(width: 6),
          Text(
            context.t('budget.reorderHint'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: brand.inkSoft,
            ),
          ),
        ],
      ),
    );
  }

  Widget _dateRangeButton(BuildContext context) {
    final isCustom = _period == _StatsPeriod.custom;
    return GestureDetector(
      onTap: _showDateRangePicker,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: isCustom
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 7)
            : const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isCustom ? AppActionBlue.color : context.brand.background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: isCustom && _customStart != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    CupertinoIcons.calendar,
                    size: 13,
                    color: Colors.white,
                  ),
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

  // Compact branded header shown above the exported cards.
  Widget _exportHeader(
    BrandColors brand,
    String periodLabel,
    String rangeLabel,
  ) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppActionBlue.color,
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(
            CupertinoIcons.chart_pie_fill,
            size: 18,
            color: Colors.white,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Trackora',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                  letterSpacing: -0.3,
                ),
              ),
              Text(
                rangeLabel,
                style: TextStyle(fontSize: 12, color: brand.inkSoft),
              ),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
          decoration: BoxDecoration(
            color: AppActionBlue.color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            periodLabel,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppActionBlue.color,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _shareSnapshot(BuildContext context) async {
    final shareSubject = context.t('stats.shareSubject');
    setState(() => _isSharing = true);
    final brand = context.brand;
    final allItems = _withInvestmentExpenses(
      ref.read(allExpensesProvider).valueOrNull ?? const [],
    );
    final symbol = ref.read(currencySymbolProvider).valueOrNull ?? '\$';
    final range = _currentRange(context);
    final accounts =
        ref.read(accountsProvider).valueOrNull ?? const <Account>[];

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

    final periodKey = switch (_period) {
      _StatsPeriod.week => 'stats.filterWeek',
      _StatsPeriod.month => 'stats.filterMonth',
      _StatsPeriod.sixMonth => 'stats.filterSixMonth',
      _StatsPeriod.year => 'stats.filterYear',
      _StatsPeriod.all => 'stats.filterAll',
      _StatsPeriod.custom => 'stats.filterCustom',
    };

    // The exported "receipt": exactly the page's cards (stacked, default order,
    // hidden cards excluded) under a compact branded header + footer. Works with
    // or without data — the cards render their own empty states.
    final report = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _exportHeader(brand, context.t(periodKey), range.label),
        const SizedBox(height: 14),
        _buildReport(
          rangedExpenses: rangedExpenses,
          rangedIncome: rangedIncome,
          allExpenses: allExpenses,
          range: range,
          symbol: symbol,
          accounts: accounts,
          forReport: true,
          rangeLabel: range.label,
        ),
        const SizedBox(height: 18),
        Column(
          children: [
            Text(
              'Generated by Trackora',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: brand.inkSoft,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              DateFormat('yyyy-MM-dd  HH:mm').format(DateTime.now()),
              style: TextStyle(
                fontSize: 10.5,
                color: brand.inkSoft.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );

    // Present the receipt "printing" out of a machine; the preview captures the
    // on-screen boundary and shares (the proven, reliable capture path).
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _StatsReceiptScreen(
          receipt: report,
          title: context.t('stats.shareSnapshot'),
          shareSubject: shareSubject,
        ),
      ),
    );
    if (mounted) setState(() => _isSharing = false);
  }
}

/// Full-screen preview that animates the stats snapshot "printing" out of a
/// machine, then lets the user share it. Capturing an on-screen RepaintBoundary
/// (rather than an off-screen overlay) is the reliable path — the same one the
/// receipt screens use.
class _StatsReceiptScreen extends StatefulWidget {
  final Widget receipt;
  final String title;
  final String shareSubject;

  const _StatsReceiptScreen({
    required this.receipt,
    required this.title,
    required this.shareSubject,
  });

  @override
  State<_StatsReceiptScreen> createState() => _StatsReceiptScreenState();
}

class _StatsReceiptScreenState extends State<_StatsReceiptScreen>
    with TickerProviderStateMixin {
  final _captureKey = GlobalKey();
  final _shareBtnKey = GlobalKey();
  late final AnimationController _printCtrl;
  late final Animation<double> _reveal;
  // Repeating pulse for the status LED while the machine is "operating".
  late final AnimationController _blinkCtrl;
  bool _sharing = false;

  // Random torn-edge profile — a fresh irregular rip every time the preview is
  // generated. Fixed for this instance so it stays stable during the animation.
  late final List<double> _tearProfile = List.generate(
    64,
    (_) => math.Random().nextDouble(),
  );

  static const double _printerHeight = 48;

  @override
  void initState() {
    super.initState();
    _printCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    );
    // Decelerating feed — starts moving, eases to a gentle stop as it settles.
    _reveal = CurvedAnimation(parent: _printCtrl, curve: Curves.easeOutCubic);
    _blinkCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    // The LED blinks only while the paper is feeding; steady once done.
    _printCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _blinkCtrl.stop();
        if (mounted) setState(() {});
      }
    });
    // Start "printing" once the paper has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _printCtrl.forward();
      _blinkCtrl.repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    _printCtrl.dispose();
    _blinkCtrl.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    final messenger = ScaffoldMessenger.of(context);
    final failedMsg = context.t('stats.exportFailed');
    // iPad share-sheet anchor from the button (ignored on iPhone).
    final btnBox =
        _shareBtnKey.currentContext?.findRenderObject() as RenderBox?;
    final origin = (btnBox != null && btnBox.hasSize && !btnBox.size.isEmpty)
        ? btnBox.localToGlobal(Offset.zero) & btnBox.size
        : (Offset.zero & MediaQuery.sizeOf(context));

    ui.Image? img;
    try {
      // The boundary is laid out at full height inside the scroll view, so it
      // captures the whole receipt regardless of the print-reveal or scroll.
      final boundary =
          _captureKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('receipt not ready');
      img = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('png encoding returned null');
      final bytes = byteData.buffer.asUint8List();

      final dir = await getTemporaryDirectory();
      final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final file = File('${dir.path}/trackora_stats_$ts.png');
      await file.writeAsBytes(bytes, flush: true);

      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png', name: 'trackora_stats.png')],
        subject: widget.shareSubject,
        sharePositionOrigin: origin,
      );
    } catch (e, st) {
      debugPrint('[StatsReceipt] share failed: $e\n$st');
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(failedMsg)));
      }
    } finally {
      img?.dispose();
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Scaffold(
      backgroundColor: brand.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(CupertinoIcons.xmark, color: brand.ink),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 40),
                ],
              ),
            ),
            Expanded(child: _printerArea(brand)),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: _shareBtnKey,
                  onPressed: _sharing ? null : _share,
                  icon: _sharing
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(CupertinoIcons.share, size: 18),
                  label: Text(context.t('common.share')),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _printerArea(BrandColors brand) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return LayoutBuilder(
      builder: (ctx, constraints) {
        // Inset the paper so the (wider) machine body + overhanging caps always
        // fit within the area without clipping.
        final paperW = (constraints.maxWidth - 40).clamp(0.0, 360.0);
        return Stack(
          alignment: Alignment.topCenter,
          children: [
            // The paper feed (scrollable once printed).
            Positioned.fill(
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(
                  top: _printerHeight - 2,
                  bottom: 28,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: paperW,
                      // The paper slides DOWN inside this window, bottom-edge
                      // first, emerging from the machine slot. Only the top is
                      // clipped (behind the machine) so the sheet keeps its
                      // side/leading shadow as it feeds — it reads as real paper.
                      child: AnimatedBuilder(
                        animation: _reveal,
                        builder: (ctx, child) => ClipRect(
                          clipper: _TopOnlyClipper(),
                          child: FractionalTranslation(
                            translation: Offset(0, -(1 - _reveal.value)),
                            child: child,
                          ),
                        ),
                        child: DecoratedBox(
                          // Soft sheet shadow (display only — the captured
                          // RepaintBoundary sits inside it, so shares stay clean).
                          decoration: BoxDecoration(
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.4 : 0.13,
                                ),
                                blurRadius: 18,
                                offset: const Offset(0, 7),
                              ),
                            ],
                          ),
                          child: RepaintBoundary(
                            key: _captureKey,
                            child: _paper(brand),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Opaque mask over everything above the slot, so no paper/content
            // is ever visible above (or beside) the machine — the sheet only
            // appears once it clears the slot.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: _printerHeight + 4,
              child: IgnorePointer(child: ColoredBox(color: brand.background)),
            ),
            // Contact shadow the machine casts onto the paper as it appears.
            Positioned(
              top: _printerHeight + 4,
              child: IgnorePointer(
                child: Container(
                  width: paperW,
                  height: 16,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: isDark ? 0.3 : 0.13),
                        Colors.black.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            // The printer sitting over the slot, so paper emerges from under it.
            Positioned(top: 4, child: _printerBar(brand, paperW + 28)),
          ],
        );
      },
    );
  }

  Widget _paper(BrandColors brand) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: brand.background,
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
          child: widget.receipt,
        ),
        // Randomised torn bottom edge — part of the captured snapshot.
        SizedBox(
          height: 15,
          child: CustomPaint(
            painter: _TornEdgePainter(
              paper: brand.background,
              trace: brand.inkSoft.withValues(alpha: 0.35),
              profile: _tearProfile,
            ),
          ),
        ),
      ],
    );
  }

  Widget _printerBar(BrandColors brand, double width) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Slot tone derived from the surface so it matches the app palette.
    final slotColor = Color.alphaBlend(
      brand.ink.withValues(alpha: isDark ? 0.6 : 0.16),
      brand.surface,
    );
    final capColor = Color.alphaBlend(
      brand.ink.withValues(alpha: isDark ? 0.14 : 0.05),
      brand.surface,
    );

    return SizedBox(
      width: width,
      height: _printerHeight,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Rounded end-caps (behind the body), like feed rollers.
          Positioned(left: -2, child: _printerCap(brand, capColor, isDark)),
          Positioned(right: -2, child: _printerCap(brand, capColor, isDark)),
          // ── Machine body: a clean app-style surface card ────────────
          Container(
            width: width,
            height: _printerHeight,
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadius.card),
              border: Border.all(color: brand.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.10),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                // centre grip pill (device handle)
                Align(
                  alignment: const Alignment(0, -0.55),
                  child: Container(
                    width: 34,
                    height: 4,
                    decoration: BoxDecoration(
                      color: brand.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                // status dot (accent) on the left
                Positioned(left: 18, top: 13, child: _printerLed()),
                // small feed indicator lines on the right
                Positioned(
                  right: 16,
                  top: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: List.generate(
                      2,
                      (i) => Container(
                        margin: const EdgeInsets.only(bottom: 4),
                        width: 14 - i * 4.0,
                        height: 2,
                        decoration: BoxDecoration(
                          color: brand.inkSoft.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                // recessed exit slot near the bottom (the "hole")
                Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 7),
                    child: Container(
                      width: width - 24,
                      height: 7,
                      decoration: BoxDecoration(
                        color: slotColor,
                        borderRadius: BorderRadius.circular(4),
                        boxShadow: [
                          // inner-ish top shadow so the slot reads as recessed
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: isDark ? 0.5 : 0.25,
                            ),
                            blurRadius: 2,
                            spreadRadius: -1,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _printerCap(BrandColors brand, Color color, bool isDark) {
    return Container(
      width: 14,
      height: _printerHeight + 6,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: brand.divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.10),
            blurRadius: 10,
            offset: const Offset(0, 6),
          ),
        ],
      ),
    );
  }

  Widget _printerLed() {
    const green = Color(0xFF34C759);
    return AnimatedBuilder(
      animation: _blinkCtrl,
      builder: (context, _) {
        // Blink green while feeding (operating); steady accent blue when idle.
        final printing = _printCtrl.isAnimating;
        final color = printing ? green : AppActionBlue.color;
        final level = printing ? (0.3 + 0.7 * _blinkCtrl.value) : 1.0;
        return Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color.withValues(alpha: level),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.6 * level),
                blurRadius: 6,
                spreadRadius: 0.5,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Clips only above the box top (hiding the not-yet-fed paper behind the
/// machine) while leaving generous room on the sides and below so the sheet's
/// shadow still shows as it feeds out.
class _TopOnlyClipper extends CustomClipper<Rect> {
  @override
  Rect getClip(Size size) =>
      Rect.fromLTRB(-60, 0, size.width + 60, size.height + 60);

  @override
  bool shouldReclip(covariant CustomClipper<Rect> oldClipper) => false;
}

/// Ragged, randomly-torn bottom edge for the exported receipt. The paper fill
/// ends on an irregular jagged line (transparent below it, so the snapshot has
/// a genuinely torn silhouette), traced with a thin line + soft shadow so the
/// rip reads even against a same-colour background.
class _TornEdgePainter extends CustomPainter {
  final Color paper;
  final Color trace;
  final List<double> profile;

  const _TornEdgePainter({
    required this.paper,
    required this.trace,
    required this.profile,
  });

  double _yAt(int i, int teeth, double h) {
    final r = profile[i % profile.length];
    return h * (0.28 + 0.72 * r);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0) return;
    final teeth = (w / 7).round().clamp(12, profile.length);

    // Filled paper ending on the jagged line (right → left).
    final fill = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0);
    for (var i = teeth; i >= 0; i--) {
      fill.lineTo(w * (i / teeth), _yAt(i, teeth, h));
    }
    fill.close();
    canvas.drawPath(fill, Paint()..color = paper);

    // The rip line itself.
    final rip = Path();
    for (var i = teeth; i >= 0; i--) {
      final x = w * (i / teeth);
      final y = _yAt(i, teeth, h);
      i == teeth ? rip.moveTo(x, y) : rip.lineTo(x, y);
    }
    // soft shadow under the rip for depth
    canvas.drawPath(
      rip,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.07)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );
    // crisp trace on top
    canvas.drawPath(
      rip,
      Paint()
        ..color = trace
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _TornEdgePainter old) =>
      old.profile != profile || old.paper != paper || old.trace != trace;
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

// ── Financial summary card (Overview section) ────────────────────────────────
//
// A compact 2×2 snapshot of money commitments & holdings, independent of the
// selected period: amount borrowed, total monthly installment payments, amount
// saved in active plans, and portfolio value (stocks + precious metals).

class _FinancialSummaryCard extends ConsumerWidget {
  const _FinancialSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final visible = ref.watch(balanceVisibleProvider);
    final converter = ref.watch(currencyConverterProvider).valueOrNull;
    final mainCode = ref.watch(currencyCodeProvider).valueOrNull;

    final borrowLending =
        ref.watch(borrowLendingProvider).valueOrNull ?? const <BorrowLending>[];
    final installments =
        ref.watch(installmentsProvider).valueOrNull ?? const <Installment>[];
    final savingPlans =
        ref.watch(savingPlansProvider).valueOrNull ?? const <SavingPlan>[];
    final stocks =
        ref.watch(stockInvestmentsProvider).valueOrNull ??
        const <StockInvestment>[];
    final metals =
        ref.watch(preciousMetalsProvider).valueOrNull ??
        const <PreciousMetal>[];

    // Borrowed: outstanding amounts the user still owes others.
    final borrowed = borrowLending
        .where(
          (r) =>
              !r.cancelled &&
              r.status != BorrowLendingStatus.settled &&
              r.remaining > 0 &&
              r.type == BorrowLendingType.borrowed,
        )
        .fold<double>(0, (sum, r) => sum + r.remaining);

    // Installments: total monthly payment across active installments.
    final installmentMonthly = installments
        .where((i) => i.status == InstallmentStatus.active)
        .fold<double>(0, (sum, i) => sum + i.amount);

    // Saving: amount already put aside in active saving plans.
    final saving = savingPlans
        .where((p) => p.status == SavingPlanStatus.active)
        .fold<double>(0, (sum, p) => sum + p.currentAmount);

    // Portfolio: stock cost basis (converted to base) + precious-metal value.
    double portfolio = 0;
    for (final s in stocks) {
      final v = s.totalCost;
      final code = s.currency ?? mainCode;
      portfolio += (converter != null && code != null && code != mainCode)
          ? converter.toBase(v, code)
          : v;
    }
    for (final m in metals) {
      portfolio += m.weightGrams * (m.pricePerGram ?? 0);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.t('stats.section.importantData'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  ref.read(balanceVisibleProvider.notifier).toggle();
                },
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  visible ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  size: 18,
                  color: brand.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: context.t('asset.borrowedLabel'),
                  amount: borrowed,
                  symbol: symbol,
                  visible: visible,
                  tint: const Color(0xFFFF3B30),
                  onTap: () => _openPage(context, const BorrowLendingScreen()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  label: context.t('stats.summaryInstallmentMo'),
                  amount: installmentMonthly,
                  symbol: symbol,
                  visible: visible,
                  tint: const Color(0xFFF57C00),
                  onTap: () => _openPage(context, const InstallmentsScreen()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _SummaryTile(
                  label: context.t('asset.savings'),
                  amount: saving,
                  symbol: symbol,
                  visible: visible,
                  tint: const Color(0xFF34C759),
                  onTap: () => _openPage(context, const SavingPlansScreen()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SummaryTile(
                  label: context.t('budget.portfolio'),
                  amount: portfolio,
                  symbol: symbol,
                  visible: visible,
                  tint: const Color(0xFF1A6CFF),
                  onTap: () => _openPage(context, const InvestmentScreen()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static void _openPage(BuildContext context, Widget page) {
    Navigator.push(context, CupertinoPageRoute(builder: (_) => page));
  }
}

class _SummaryTile extends StatefulWidget {
  final String label;
  final double amount;
  final String symbol;
  final bool visible;
  final Color tint;
  final VoidCallback onTap;

  const _SummaryTile({
    required this.label,
    required this.amount,
    required this.symbol,
    required this.visible,
    required this.tint,
    required this.onTap,
  });

  @override
  State<_SummaryTile> createState() => _SummaryTileState();
}

class _SummaryTileState extends State<_SummaryTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 110),
  );
  late final Animation<double> _scale = Tween(
    begin: 1.0,
    end: 0.96,
  ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final tint = widget.tint;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
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
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
          decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: tint,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: brand.inkSoft,
                      ),
                    ),
                  ),
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 11,
                    color: tint.withValues(alpha: 0.7),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              MaskedAmount(
                visibleText: formatMoney(widget.symbol, widget.amount),
                visible: widget.visible,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
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
  final bool reorderMode;
  final bool hasHidden;
  final VoidCallback onAdd;
  final VoidCallback onDone;
  final VoidCallback? onShare;

  const _TopActionBar({
    required this.reorderMode,
    required this.hasHidden,
    required this.onAdd,
    required this.onDone,
    required this.onShare,
  });

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
        if (reorderMode) ...[
          // While rearranging: add hidden cards back, then finish.
          if (hasHidden) ...[
            GlassCircleButton(icon: CupertinoIcons.add, onTap: onAdd),
            const SizedBox(width: 8),
          ],
          GlassCircleButton(icon: CupertinoIcons.checkmark_alt, onTap: onDone),
        ] else ...[
          if (onShare != null) ...[
            GlassCircleButton(icon: CupertinoIcons.share, onTap: onShare!),
            const SizedBox(width: 8),
          ],
          const FxRateButton(),
        ],
      ],
    );
  }
}

// ── Sliding period tabs (replaces pills) ──────────────────────────────────────

class _SlidingPeriodTabs extends StatefulWidget {
  final _StatsPeriod period;
  final ValueChanged<_StatsPeriod> onChanged;

  const _SlidingPeriodTabs({required this.period, required this.onChanged});

  @override
  State<_SlidingPeriodTabs> createState() => _SlidingPeriodTabsState();
}

class _SlidingPeriodTabsState extends State<_SlidingPeriodTabs> {
  static const _tabs = [
    _StatsPeriod.week,
    _StatsPeriod.month,
    _StatsPeriod.sixMonth,
    _StatsPeriod.year,
  ];

  double _barWidth = 0;

  String _label(BuildContext context, _StatsPeriod p) => switch (p) {
    _StatsPeriod.week => context.t('stats.filterWeek'),
    _StatsPeriod.month => context.t('stats.filterMonth'),
    _StatsPeriod.sixMonth => context.t('stats.filterSixMonth'),
    _StatsPeriod.year => context.t('stats.filterYear'),
    _ => '',
  };

  void _onDragUpdate(DragUpdateDetails d) {
    if (_barWidth <= 0) return;
    final tabW = _barWidth / _tabs.length;
    final idx = (d.localPosition.dx / tabW).floor().clamp(0, _tabs.length - 1);
    final cur = _tabs.indexOf(widget.period).clamp(0, _tabs.length - 1);
    if (idx != cur) {
      HapticFeedback.selectionClick();
      widget.onChanged(_tabs[idx]);
    }
  }

  void _onDragEnd(DragEndDetails _) {}

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedIdx = _tabs.indexOf(widget.period).clamp(0, _tabs.length - 1);
    final trackColor = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.72);

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: () {},
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          _barWidth = constraints.maxWidth;
          final tabW = _barWidth / _tabs.length;
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
                            widget.onChanged(_tabs[i]);
                          },
                          behavior: HitTestBehavior.opaque,
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: widget.period == _tabs[i]
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
      ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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

  const _NavArrow({
    required this.icon,
    required this.onTap,
    required this.brand,
  });

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
    return _FloatCard(padding: EdgeInsets.zero, child: content);
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
            if (monthDiff >= 0 && monthDiff < 6)
              values[monthDiff] += e.convertedAmount;
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
    if (mounted)
      setState(() => _pageOffset = _controller.page ?? _page.toDouble());
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
        setState(() {
          _page = 0;
          _pageOffset = 0.0;
        });
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
                  _navBtn(
                    context,
                    CupertinoIcons.chevron_left,
                    widget.onPrev ?? () {},
                  ),
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
                  _navBtn(
                    context,
                    CupertinoIcons.chevron_right,
                    widget.onNext ?? () {},
                  ),
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
                final pillW =
                    (constraints.maxWidth - gap * (pages.length - 1)) /
                    pages.length;
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
                                  child: Builder(
                                    builder: (context) {
                                      final dist = (_pageOffset - i)
                                          .abs()
                                          .clamp(0.0, 1.0);
                                      final fg =
                                          brand.accentDark.computeLuminance() <
                                              0.5
                                          ? Colors.white
                                          : Colors.black;
                                      final color = Color.lerp(
                                        fg,
                                        brand.inkSoft,
                                        dist,
                                      )!;
                                      return Text(
                                        pages[i].label,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: color,
                                        ),
                                      );
                                    },
                                  ),
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
              onPageChanged: (i) => setState(() {
                _page = i;
                _pageOffset = i.toDouble();
              }),
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

// ── Category donut chart ────────────────────────────────────────

class _CategoryCard extends ConsumerStatefulWidget {
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
  ConsumerState<_CategoryCard> createState() => _CategoryCardState();
}

class _CategoryCardState extends ConsumerState<_CategoryCard> {
  @override
  Widget build(BuildContext context) {
    // Split bills charge the full amount to the category, but only the user's
    // net share (total minus what debtors have repaid) is really their spend —
    // net it out here so the donut matches the Monthly Budget figures.
    final bills = ref.watch(allSplitBillsProvider).valueOrNull ?? const [];
    final billByExpenseId = {for (final b in bills) b.expenseId: b};
    double net(Expense e) {
      final bill = billByExpenseId[e.id];
      if (bill == null || bill.totalAmount <= 0 || bill.collected <= 0) {
        return e.convertedAmount;
      }
      final collectedBase =
          bill.collected * (e.convertedAmount / bill.totalAmount);
      return (e.convertedAmount - collectedBase).clamp(0.0, double.infinity);
    }

    final Map<String, double> totals = {};
    for (final e in widget.expenses) {
      totals[e.category] = (totals[e.category] ?? 0) + net(e);
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final total = widget.expenses.fold<double>(0, (s, e) => s + net(e));
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
      return _FloatCard(padding: EdgeInsets.zero, child: emptyContent);
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
            // Snapshot export captures a static frame — draw it fully, not
            // mid-sweep.
            animate: !widget.forReport,
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

        final legendItems = sorted
            .take(6)
            .map(
              (entry) => _LegendRow(
                entry: entry,
                total: total,
                symbol: widget.symbol,
                onTap: () => _showCategoryRecords(context, entry),
              ),
            )
            .toList();

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
                      context.t('stats.byCategory'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
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
                context.t('stats.byCategory'),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
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

class _CategoryRecordsSheet extends ConsumerWidget {
  final String category;
  final List<Expense> records;
  final double total;
  final String symbol;
  final String rangeLabel;
  // The budget set for this category, when opened from the Monthly Budget card.
  final double? budget;

  const _CategoryRecordsSheet({
    required this.category,
    required this.records,
    required this.total,
    required this.symbol,
    required this.rangeLabel,
    this.budget,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final style = styleFor(category);
    // Map each record to its split bill (if any) so a shared expense can show
    // the user's real share and any amount still owed by others.
    final bills = ref.watch(allSplitBillsProvider).valueOrNull ?? const [];
    final billByExpenseId = {for (final b in bills) b.expenseId: b};
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
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
                if (budget != null && budget! > 0)
                  _budgetProgress(context, brand, style),
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
              itemBuilder: (context, index) => _RecordRow(
                expense: records[index],
                symbol: symbol,
                bill: billByExpenseId[records[index].id],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // "600 of 900 used" progress against this category's own monthly budget.
  Widget _budgetProgress(
    BuildContext context,
    BrandColors brand,
    CategoryStyle style,
  ) {
    final cap = budget!;
    final ratio = (total / cap).clamp(0.0, 1.0);
    final over = total > cap + 0.005;
    final barColor = over ? AppColors.expense : style.accent;
    final remaining = cap - total;
    final tail = over
        ? context.t('budget.overBudget')
        : '${formatMoney(symbol, remaining)} ${context.t('split.leftLc')}';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: brand.divider,
              valueColor: AlwaysStoppedAnimation<Color>(barColor),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatMoney(symbol, total)} '
                  '${context.t('budget.ofBudget').replaceAll('{budget}', formatMoney(symbol, cap))} '
                  '${context.t('home.used')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                tail,
                style: TextStyle(
                  fontSize: 12,
                  color: over ? AppColors.expense : brand.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  final Expense expense;
  final String symbol;
  // The split bill this record belongs to, when it's a shared expense.
  final SplitBill? bill;

  const _RecordRow({required this.expense, required this.symbol, this.bill});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final title = expense.note.trim().isEmpty
        ? context.categoryLabel(expense.category)
        : expense.note.trim();
    // For a split expense the full amount is charged to this category, but the
    // user's own share is smaller. Anything not yet repaid still counts as
    // their spend, so surface both the share used and what's still owed.
    final b = bill;
    String? youUsedLine;
    String? owedLine;
    if (b != null) {
      final billSymbol = b.currencySymbol;
      final ownShare = b.payer.amount;
      youUsedLine = context
          .t('split.youUsed')
          .replaceAll('{amount}', formatMoney(billSymbol, ownShare));
      // Debtors who still owe (their amount tracks the remaining balance).
      final owers = b.members
          .where(
            (m) =>
                !m.isPayer &&
                m.status != SplitMemberStatus.paid &&
                m.amount > 0.005,
          )
          .toList();
      if (owers.isNotEmpty) {
        final names = owers.map((m) => m.name).join(', ');
        final owedAmt = owers.fold<double>(0, (s, m) => s + m.amount);
        owedLine = context
            .t('split.owedToYouInline')
            .replaceAll('{name}', names)
            .replaceAll('{amount}', formatMoney(billSymbol, owedAmt));
      }
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        // Open the record for viewing / editing. Close the sheet first so
        // returning from the editor lands back on the report, not a stale sheet.
        final nav = Navigator.of(context);
        nav.pop();
        nav.push(
          CupertinoPageRoute(
            builder: (_) => AddEditExpenseScreen(expense: expense),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: brand.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (youUsedLine != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      youUsedLine,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (owedLine != null)
                      Text(
                        owedLine,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: brand.inkSoft,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ],
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
                          ? (kSupportedCurrencies[expense.originalCurrency!] ??
                                expense.originalCurrency!)
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

  List<String> get _weekdays => context.t('stats.weekdayInitials').split(',');

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
      if (_end == null)
        return '${DateFormat('d MMM yyyy').format(_start!)} — ?';
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
      final inRange =
          _start != null &&
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
                        horizontal: 14,
                        vertical: 8,
                      ),
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
                      child: Icon(
                        CupertinoIcons.chevron_left,
                        size: 14,
                        color: brand.ink,
                      ),
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
                    onTap:
                        _month.year == today.year && _month.month == today.month
                        ? null
                        : () => setState(() {
                            _month = DateTime(_month.year, _month.month + 1);
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
                        color:
                            _month.year == today.year &&
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

// ── Group Spend card ─────────────────────────────────────────────────────────

const _kMemberBgs = [
  Color(0xFFEAE3F8),
  Color(0xFFD7F4E5),
  Color(0xFFDBEAFE),
  Color(0xFFFEF3C7),
  Color(0xFFFFEDD5),
  Color(0xFFFCE7F3),
];
const _kMemberFgs = [
  Color(0xFF5A4AAB),
  Color(0xFF1FBE71),
  Color(0xFF2563EB),
  Color(0xFFD97706),
  Color(0xFFEA580C),
  Color(0xFFDB2777),
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
        result[entry.key] =
            (result[entry.key] ?? 0) + e.amount * (entry.value / 100.0);
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
    if (range.endExclusive != null && !d.isBefore(range.endExclusive!))
      return false;
    return true;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? [];
    if (groups.isEmpty) return const SizedBox.shrink();

    final groupData =
        <
          ({
            String id,
            String name,
            List<GroupMember> members,
            List<GroupExpenseItem> expenses,
            double total,
          })
        >[];

    for (final group in groups) {
      final expenses =
          ref.watch(groupExpensesProvider(group.id)).valueOrNull ?? [];
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
          final live =
              ref.watch(memberDisplayNameProvider(m.uid)).valueOrNull ?? '';
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
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: brand.inkSoft,
                  ),
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
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: brand.inkSoft,
                ),
              ),
              Text(
                formatMoney(symbol, overallTotal),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: brand.ink,
                ),
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

  List<({String uid, String displayName, double spend, int colorIndex})>
  get _memberRows {
    final memberUids = widget.members.map((m) => m.uid).toList();
    final shares = _memberShares(widget.expenses, memberUids);
    final rows =
        widget.members
            .asMap()
            .entries
            .map(
              (e) => (
                uid: e.value.uid,
                displayName:
                    widget.resolvedNames[e.value.uid] ?? e.value.displayName,
                spend: shares[e.value.uid] ?? 0,
                colorIndex: e.key,
              ),
            )
            .toList()
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
                child: const Icon(
                  CupertinoIcons.person_3_fill,
                  size: 12,
                  color: Color(0xFF1967D2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.groupName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
              ),
              Text(
                formatMoney(widget.symbol, widget.total),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                ),
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
                    ...rows.map(
                      (m) => _FilterPill(
                        label: m.displayName.split(' ').first,
                        selected: _selectedUid == m.uid,
                        color: _kMemberFgs[m.colorIndex % _kMemberFgs.length],
                        onTap: () => setState(
                          () => _selectedUid = _selectedUid == m.uid
                              ? null
                              : m.uid,
                        ),
                      ),
                    ),
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
  final List<({String uid, String displayName, double spend, int colorIndex})>
  rows;
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
        final initial = m.displayName.isNotEmpty
            ? m.displayName[0].toUpperCase()
            : '?';
        final pct = total > 0
            ? (m.spend / total * 100).toStringAsFixed(0)
            : '0';

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
                  style: TextStyle(
                    fontSize: 9,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
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
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: fg,
                      ),
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
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: brand.inkSoft,
                  ),
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
                .map(
                  (e) => DonutSegment(
                    value: e.value,
                    color: _donutColorFor(e.key),
                  ),
                )
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
                      decoration: BoxDecoration(
                        color: c,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        context.categoryLabel(e.key),
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
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: brand.inkSoft,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      formatMoney(symbol, e.value),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: brand.ink,
                      ),
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
    'PreciousMetal': Color(0xFFE0B33A), // premium gold
    'Stock': Color(0xFF6E72E0), // confident indigo
    'Others': Color(0xFFA0A0AA), // neutral slate
    'Transfer': Color(0xFF78AEDD), // muted blue-gray
  };
  return colors[category] ?? const Color(0xFFA0A0AA);
}

/// Per-category budget progress, shown on Statistics only when the user budgets
/// by category. One spent-vs-budget bar per budgeted category (green / amber /
/// red), using the same category icons + colours as expenses.
class _BudgetByCategoryCard extends ConsumerWidget {
  final String symbol;
  // Snapshot/share export: the image isn't clickable, so spell out each
  // category's spend inline instead of relying on the tappable legend.
  final bool forReport;
  const _BudgetByCategoryCard({
    super.key,
    required this.symbol,
    this.forReport = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg =
        ref.watch(budgetConfigProvider).valueOrNull ?? const MonthlyBudget();
    if (!cfg.isByCategory || cfg.categories.isEmpty) {
      return const SizedBox.shrink();
    }
    final brand = context.brand;
    final catSpend = ref.watch(categorySpendThisCycleProvider);

    final items =
        cfg.categories.entries
            .map((e) => _CatBudgetRow(e.key, catSpend[e.key] ?? 0, e.value))
            .toList()
          ..sort((a, b) => b.ratio.compareTo(a.ratio));

    // Total = the user's overall monthly cap (never below the sum allocated to
    // categories). The segmented bar (iOS-storage style) shows each category's
    // share of that cap, so any unallocated budget reads as free headroom.
    final totalBudget = cfg.effectiveTotal;
    final totalSpent = items.fold(0.0, (s, it) => s + it.spent);
    final totalOver = totalSpent > totalBudget + 0.005;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  context.t('home.budget'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${formatMoney(symbol, totalSpent)} ${context.t('budget.ofBudget').replaceAll('{budget}', formatMoney(symbol, totalBudget))} ${context.t('home.used')}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: totalOver ? AppColors.expense : brand.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          BudgetSegmentBar(
            segments: [
              for (final it in items)
                if (it.spent > 0)
                  BudgetSegment(
                    name: it.name,
                    amount: it.spent,
                    color: _segmentColor(it.name),
                  ),
            ],
            totalBudget: totalBudget,
            totalSpent: totalSpent,
            symbol: symbol,
            onSegmentTap: (name) => _showCategoryRecords(
              context,
              ref,
              name,
              catSpend[name] ?? 0,
              budget: cfg.categories[name],
            ),
          ),
          const SizedBox(height: 16),
          if (forReport)
            // Snapshot: not clickable, so show each category's spend inline.
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              _legendRow(context, items[i], brand),
            ]
          else
            // Live: compact legend; tap a category to open its detail popup.
            Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                for (final it in items) _legendItem(context, ref, it, brand),
              ],
            ),
        ],
      ),
    );
  }

  // Compact, tappable legend chip for the live card (dot + name).
  Widget _legendItem(
    BuildContext context,
    WidgetRef ref,
    _CatBudgetRow it,
    BrandColors brand,
  ) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showCategoryRecords(
        context,
        ref,
        it.name,
        it.spent,
        budget: it.budget,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              color: _segmentColor(it.name),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            context.categoryLabel(it.name),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: brand.ink,
            ),
          ),
        ],
      ),
    );
  }

  Color _segmentColor(String name) {
    final style = styleFor(name);
    return budgetSliceColor(style.accent, style.background);
  }

  // Detailed, non-interactive row for the snapshot: category, spent / budget,
  // and a spend bar (turns red when over budget).
  Widget _legendRow(BuildContext context, _CatBudgetRow it, BrandColors brand) {
    final color = _segmentColor(it.name);
    final over = it.spent > it.budget + 0.005;
    final ratio = it.budget > 0 ? (it.spent / it.budget).clamp(0.0, 1.0) : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                context.categoryLabel(it.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${formatMoney(symbol, it.spent)} / ${formatMoney(symbol, it.budget)}',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: over ? AppColors.expense : brand.ink,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 6,
            backgroundColor: brand.divider,
            valueColor: AlwaysStoppedAnimation<Color>(
              over ? AppColors.expense : color,
            ),
          ),
        ),
      ],
    );
  }

  void _showCategoryRecords(
    BuildContext context,
    WidgetRef ref,
    String category,
    double spent, {
    double? budget,
  }) {
    HapticFeedback.selectionClick();
    final records =
        (ref.read(expensesProvider).valueOrNull ?? const <Expense>[])
            .where((e) => e.type == EntryType.expense && e.category == category)
            .toList()
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
            category: category,
            records: records,
            total: spent,
            symbol: symbol,
            rangeLabel: DateFormat.yMMMM().format(DateTime.now()),
            budget: budget,
          ),
        ),
      ),
    );
  }
}

class _CatBudgetRow {
  final String name;
  final double spent;
  final double budget;
  const _CatBudgetRow(this.name, this.spent, this.budget);
  double get ratio => budget <= 0 ? 0 : spent / budget;
}
