import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/expense.dart';
import '../../models/installment.dart';
import '../../repositories/local_expense_repository.dart';
import '../../repositories/local_split_bill_repository.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../services/sync_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/expense_card.dart';
import '../../widgets/month_filter_bar.dart';
import '../../widgets/exchange_rate_sheet.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/section_card.dart';
import '../expenses/add_edit_expense_screen.dart';
import 'calendar_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final selectedMonth = ref.watch(selectedMonthProvider);
    final expensesAsync = ref.watch(expensesProvider);
    final allExpensesAsync = ref.watch(allExpensesProvider);
    final budgetAsync = ref.watch(budgetProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final appLocale = ref.watch(localeProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];

    final cycleRange = ref.watch(cycleDateRangeProvider);

    final budget = budgetAsync.valueOrNull ?? 0;
    final monthExpenses = expensesAsync.valueOrNull ?? const <Expense>[];
    final allExpenses = allExpensesAsync.valueOrNull ?? const <Expense>[];
    final monthExpenseOnly = monthExpenses
        .where((e) => e.type == EntryType.expense)
        .toList();

    // If custom cycle is active, filter allExpenses by cycle range for totals.
    final List<Expense> cycleExpenseOnly;
    if (cycleRange != null) {
      cycleExpenseOnly = allExpenses.where((e) {
        if (e.type != EntryType.expense) return false;
        final d = DateTime(e.date.year, e.date.month, e.date.day);
        return !d.isBefore(cycleRange.start) && d.isBefore(cycleRange.endExclusive);
      }).toList();
    } else {
      cycleExpenseOnly = monthExpenseOnly;
    }

    final monthSpent = cycleExpenseOnly.fold<double>(
      0,
      (s, e) => s + e.convertedAmount,
    );
    final hasForeignExpense = cycleExpenseOnly.any(
      (e) => e.baseCurrencyAmount != null,
    );

    final List<Expense> cycleAll = cycleRange != null
        ? allExpenses.where((e) {
            final d = DateTime(e.date.year, e.date.month, e.date.day);
            return !d.isBefore(cycleRange.start) && d.isBefore(cycleRange.endExclusive);
          }).toList()
        : monthExpenses;

    final monthIncome = cycleAll
        .where((e) => e.type.isInflow)
        .fold<double>(0, (s, e) => s + e.convertedAmount);

    final budgetableSpent = cycleAll
        .where(
          (e) =>
              e.type == EntryType.expense &&
              e.category != 'Bills' &&
              !e.note.contains('(installment)'),
        )
        .fold<double>(0, (s, e) => s + e.convertedAmount);

    final totalBalance = ref.watch(totalAccountBalanceProvider);

    // Unpaid installments for current cycle month
    final allInstallments = ref.watch(installmentsProvider).valueOrNull ?? [];
    final now = DateTime.now();
    final cycleMonthDate = cycleRange?.start ?? DateTime(now.year, now.month, 1);
    final unpaidInstallments = allInstallments.where((inst) {
      if (inst.status != InstallmentStatus.active) return false;
      return !inst.isPaidIn(cycleMonthDate);
    }).toList();
    final unpaidTotal = unpaidInstallments.fold<double>(0, (s, e) => s + e.amount);
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    double todaySpent = 0;
    double weekSpent = 0;
    for (final e in allExpenses) {
      if (e.type != EntryType.expense) continue;
      if (!e.date.isBefore(todayStart)) todaySpent += e.convertedAmount;
      if (!e.date.isBefore(weekStart)) weekSpent += e.convertedAmount;
    }

    final sortedRecent = [...allExpenses]
      ..sort((a, b) => b.date.compareTo(a.date));
    ref
        .read(widgetSyncServiceProvider)
        .push(
          currencySymbol: symbol,
          monthSpent: monthSpent,
          monthBudget: budget,
          savings: totalBalance,
          upcomingInstallments: unpaidInstallments.length.toDouble(),
          budgetableSpent: budgetableSpent,
          localeCode: appLocale.encode(),
          todaySpent: todaySpent,
          weekSpent: weekSpent,
          accounts: accounts,
          recentExpenses: sortedRecent.take(5).toList(),
        );

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE').format(DateTime.now()),
                        style: TextStyle(
                          color: brand.inkSoft,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Trackora',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: brand.ink,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const FxRateButton(),
                      const SizedBox(width: 10),
                      const ProfileAvatarButton(),
                    ],
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(20, 10, 20, cycleRange != null ? 4 : 12),
              child: _HomeOverviewCard(
                balance: totalBalance,
                symbol: symbol,
                monthSpent: monthSpent,
                monthIncome: monthIncome,
                budget: budget,
                budgetSpent: budgetableSpent,
                selectedMonth: selectedMonth,
                hasForeignExpense: hasForeignExpense,
              ),
            ),
          ),

          if (cycleRange != null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Cycle: ${DateFormat('d MMM').format(cycleRange.start)} – ${DateFormat('d MMM').format(cycleRange.endExclusive.subtract(const Duration(days: 1)))}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: brand.inkSoft,
                      ),
                    ),
                  ),
                ),
              ),
            ),

          if (unpaidInstallments.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.expense.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          CupertinoIcons.creditcard,
                          size: 17,
                          color: AppColors.expense,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${unpaidInstallments.length} unpaid this month',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: brand.ink,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${unpaidInstallments.length == 1 ? 'installment' : 'installments'} due',
                              style: TextStyle(
                                fontSize: 11,
                                color: brand.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        formatMoney(symbol, unpaidTotal),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.expense,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.t('home.activity'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => CalendarDialog.show(context),
                    behavior: HitTestBehavior.opaque,
                    child: Row(
                      children: [
                        Icon(
                          CupertinoIcons.calendar,
                          size: 14,
                          color: brand.accentDark,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          context.t('stats.calendar'),
                          style: TextStyle(
                            fontSize: 13,
                            color: brand.accentDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: MonthFilterBar(
              selectedMonth: selectedMonth,
              onMonthSelected: (m) =>
                  ref.read(selectedMonthProvider.notifier).state = m,
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          if (monthExpenses.isEmpty)
            SliverToBoxAdapter(child: _empty(context))
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Column(
                      children: [
                        for (
                          var i = 0;
                          i < monthExpenses.length.clamp(0, 5);
                          i++
                        ) ...[
                          if (i > 0)
                            Padding(
                              padding: const EdgeInsets.only(left: 70),
                              child: Container(
                                height: 0.5,
                                color: brand.divider,
                              ),
                            ),
                          Builder(
                            builder: (ctx) {
                              final expense = monthExpenses[i];
                              final acct = accounts
                                  .where((a) => a.id == expense.accountId)
                                  .firstOrNull;
                              return ExpenseCard(
                                key: ValueKey(expense.id),
                                expense: expense,
                                currencySymbol: symbol,
                                account: acct,
                                flat: true,
                                hasSplitBill: user != null &&
                                    LocalSplitBillRepository.hasSplitBillSync(
                                        user.uid, expense.id),
                                onTap: () => Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (_) =>
                                        AddEditExpenseScreen(expense: expense),
                                  ),
                                ),
                                onEdit: () => Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (_) =>
                                        AddEditExpenseScreen(expense: expense),
                                  ),
                                ),
                                onDelete: () async {
                                  if (user == null) return;
                                  final uid = user.uid;
                                  try {
                                    if (storageMode == StorageMode.firebase) {
                                      final isOnline = ref.read(
                                        isOnlineProvider,
                                      );
                                      await SyncService().deleteExpense(
                                        userId: uid,
                                        expenseId: expense.id,
                                        isOnline: isOnline,
                                      );
                                    } else {
                                      await LocalExpenseRepository()
                                          .deleteExpense(uid, expense.id);
                                    }
                                    if (!context.mounted) return;
                                    AppToast.show(
                                      context,
                                      context.t('expense.entryDeleted'),
                                      type: AppToastType.info,
                                      icon: CupertinoIcons.trash,
                                    );
                                  } catch (_) {
                                    if (!context.mounted) return;
                                    AppToast.show(
                                      context,
                                      context.t('common.error'),
                                      type: AppToastType.error,
                                      icon: CupertinoIcons
                                          .exclamationmark_circle_fill,
                                    );
                                  }
                                },
                                onCopy: () => _copyRecord(context, expense),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (monthExpenses.length > 5)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                  child: GestureDetector(
                    onTap: () => _showAllBillsSheet(
                      context,
                      monthExpenses,
                      symbol,
                      selectedMonth,
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '${context.t('home.allBills')} · ${monthExpenses.length} ${context.t('common.entries')}',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: brand.accentDark,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: SectionCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.sand,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(CupertinoIcons.tray, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 12),
            Text(
              context.t('home.noEntriesThisMonth'),
              style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink),
            ),
            const SizedBox(height: 4),
            Text(
              context.t('home.addFirstExpense'),
              style: TextStyle(color: brand.inkSoft, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  void _copyRecord(BuildContext context, Expense original) {
    AppToast.show(
      context,
      'Record has been copied',
      type: AppToastType.info,
      icon: CupertinoIcons.doc_on_doc,
    );
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => AddEditExpenseScreen(copyFrom: original),
      ),
    );
  }

  void _showAllBillsSheet(
    BuildContext context,
    List<Expense> expenses,
    String symbol,
    DateTime month,
  ) {
    final sorted = [...expenses]..sort((a, b) => b.date.compareTo(a.date));
    final total = sorted
        .where((e) => e.type == EntryType.expense)
        .fold<double>(0, (s, e) => s + e.convertedAmount);
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
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: _AllBillsSheet(
            expenses: sorted,
            total: total,
            symbol: symbol,
            month: month,
          ),
        ),
      ),
    );
  }
}

// ── Home overview card ─────────────────────────────────────────

class _HomeOverviewCard extends ConsumerWidget {
  final double balance;
  final String symbol;
  final double monthSpent;
  final double monthIncome;
  final double budget;
  final double budgetSpent;
  final DateTime selectedMonth;
  final bool hasForeignExpense;

  const _HomeOverviewCard({
    required this.balance,
    required this.symbol,
    required this.monthSpent,
    required this.monthIncome,
    required this.budget,
    required this.budgetSpent,
    required this.selectedMonth,
    required this.hasForeignExpense,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(balanceVisibleProvider);
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final now = DateTime.now();
    final isCurrentMonth =
        selectedMonth.year == now.year && selectedMonth.month == now.month;
    final daysInMonth = DateTime(
      selectedMonth.year,
      selectedMonth.month + 1,
      0,
    ).day;
    final daysPassed = isCurrentMonth ? now.day : daysInMonth;
    final daysRemaining = isCurrentMonth ? (daysInMonth - now.day) : 0;

    final avgDaily = daysPassed > 0 ? monthSpent / daysPassed : 0.0;
    final budgetRemaining = budget - budgetSpent;
    final remainingDaily = (budget > 0 && daysRemaining > 0)
        ? budgetRemaining / daysRemaining
        : 0.0;
    final budgetProgress = budget > 0
        ? (budgetSpent / budget).clamp(0.0, 1.0)
        : 0.0;
    final pct = budgetProgress * 100;
    final overspent = budgetRemaining < 0;

    final topBg = isDark ? const Color(0xFF201E2C) : brand.surface;
    final topInk = brand.ink;
    final topSoft = brand.inkSoft;
    final statPillBg = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.62);

    const firstCardShadow = <BoxShadow>[];
    const cardShadow = <BoxShadow>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SpendingOverviewCard(
          visible: visible,
          onToggleVisibility: () =>
              ref.read(balanceVisibleProvider.notifier).toggle(),
          selectedMonth: selectedMonth,
          symbol: symbol,
          monthSpent: monthSpent,
          monthIncome: monthIncome,
          balance: balance,
          background: topBg,
          ink: topInk,
          soft: topSoft,
          statPillBg: statPillBg,
          shadows: firstCardShadow,
          isDark: isDark,
          hasForeignExpense: hasForeignExpense,
        ),
        const SizedBox(height: 12),
        _BudgetOverviewCard(
          visible: visible,
          symbol: symbol,
          budget: budget,
          budgetSpent: budgetSpent,
          budgetRemaining: budgetRemaining,
          budgetProgress: budgetProgress,
          pct: pct,
          overspent: overspent,
          avgDaily: avgDaily,
          remainingDaily: remainingDaily,
          daysRemaining: daysRemaining,
          brand: brand,
          shadows: cardShadow,
          isDark: isDark,
        ),
      ],
    );
  }
}

class _SpendingOverviewCard extends StatelessWidget {
  final bool visible;
  final VoidCallback onToggleVisibility;
  final DateTime selectedMonth;
  final String symbol;
  final double monthSpent;
  final double monthIncome;
  final double balance;
  final Color background;
  final Color ink;
  final Color soft;
  final Color statPillBg;
  final List<BoxShadow> shadows;
  final bool isDark;
  final bool hasForeignExpense;

  const _SpendingOverviewCard({
    required this.visible,
    required this.onToggleVisibility,
    required this.selectedMonth,
    required this.symbol,
    required this.monthSpent,
    required this.monthIncome,
    required this.balance,
    required this.background,
    required this.ink,
    required this.soft,
    required this.statPillBg,
    required this.shadows,
    required this.isDark,
    required this.hasForeignExpense,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      height: 215,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        boxShadow: shadows,
      ),
      child: Stack(
        children: [
          Positioned(
            right: 56,
            top: 12,
            child: Transform.rotate(
              angle: 0.34,
              child: Container(
                width: 98,
                height: 120,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : brand.inkSoft.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
            ),
          ),
          Positioned(
            right: -2,
            top: 54,
            child: Transform.rotate(
              angle: -0.16,
              child: Container(
                width: 86,
                height: 88,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.40),
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            top: 23,
            child: _MonthChip(month: selectedMonth, ink: ink, isDark: isDark),
          ),
          Positioned(
            right: 24,
            top: 28,
            child: Semantics(
              button: true,
              label: visible ? 'Hide balance amounts' : 'Show balance amounts',
              child: GestureDetector(
                onTap: onToggleVisibility,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 2,
                    vertical: 4,
                  ),
                  child: Text(
                    context.t('home.spent'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: soft,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            top: 70,
            child: _HeroAmount(
              visible: visible,
              symbol: symbol,
              amount: monthSpent,
              ink: ink,
              soft: soft,
              hasForeign: hasForeignExpense,
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 22,
            child: _TopStatsPill(
              background: statPillBg,
              divider: soft.withValues(alpha: isDark ? 0.22 : 0.14),
              ink: ink,
              soft: soft,
              visible: visible,
              symbol: symbol,
              income: monthIncome,
              balance: balance,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  final DateTime month;
  final Color ink;
  final bool isDark;

  const _MonthChip({
    required this.month,
    required this.ink,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.78),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.calendar, size: 12, color: ink),
          const SizedBox(width: 6),
          Text(
            DateFormat('MMM yyyy').format(month),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroAmount extends StatelessWidget {
  final bool visible;
  final String symbol;
  final double amount;
  final Color ink;
  final Color soft;
  final bool hasForeign;

  const _HeroAmount({
    required this.visible,
    required this.symbol,
    required this.amount,
    required this.ink,
    required this.soft,
    this.hasForeign = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return Text(
        '$symbol ****',
        style: TextStyle(
          fontSize: 42,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (hasForeign) ...[
          Text(
            'est.',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: soft,
              letterSpacing: -0.12,
              height: 1,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Text(
          symbol,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: soft,
            height: 1,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            formatMoney('', amount).trim(),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w700,
              color: ink,
              height: 0.96,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ],
    );
  }
}

class _TopStatsPill extends StatelessWidget {
  final Color background;
  final Color divider;
  final Color ink;
  final Color soft;
  final bool visible;
  final String symbol;
  final double income;
  final double balance;

  const _TopStatsPill({
    required this.background,
    required this.divider,
    required this.ink,
    required this.soft,
    required this.visible,
    required this.symbol,
    required this.income,
    required this.balance,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 62,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TopStat(
              dotColor: AppColors.income,
              label: context.t('home.income').toUpperCase(),
              value: visible ? formatMoney(symbol, income) : '$symbol ****',
              ink: ink,
              soft: soft,
            ),
          ),
          Container(width: 1, height: 34, color: divider),
          const SizedBox(width: 14),
          Expanded(
            child: _TopStat(
              dotColor: AppActionBlue.color,
              label: context.t('account.balance'),
              value: visible ? formatMoney(symbol, balance) : '$symbol ****',
              ink: ink,
              soft: soft,
            ),
          ),
        ],
      ),
    );
  }
}

class _BudgetOverviewCard extends StatelessWidget {
  final bool visible;
  final String symbol;
  final double budget;
  final double budgetSpent;
  final double budgetRemaining;
  final double budgetProgress;
  final double pct;
  final bool overspent;
  final double avgDaily;
  final double remainingDaily;
  final int daysRemaining;
  final BrandColors brand;
  final List<BoxShadow> shadows;
  final bool isDark;

  const _BudgetOverviewCard({
    required this.visible,
    required this.symbol,
    required this.budget,
    required this.budgetSpent,
    required this.budgetRemaining,
    required this.budgetProgress,
    required this.pct,
    required this.overspent,
    required this.avgDaily,
    required this.remainingDaily,
    required this.daysRemaining,
    required this.brand,
    required this.shadows,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 300),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: shadows,
      ),
      padding: const EdgeInsets.fromLTRB(24, 21, 24, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.t('home.budget'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
                ),
              ),
              const Spacer(),
              Text(
                budget > 0 ? formatMoney(symbol, budget) : '—',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: brand.inkSoft,
                ),
              ),
            ],
          ),
          if (budget > 0) ...[
            const SizedBox(height: 18),
            Center(
              child: SizedBox(
                width: 154,
                height: 82,
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: budgetProgress),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.easeOutCubic,
                  builder: (context, animatedProgress, child) => CustomPaint(
                    painter: _ArcGaugePainter(
                      progress: animatedProgress,
                      bgColor: overspent
                          ? AppColors.blush.withValues(alpha: 0.55)
                          : AppColors.income.withValues(
                              alpha: isDark ? 0.18 : 0.14,
                            ),
                      fgColor: overspent ? AppColors.expense : AppColors.income,
                      strokeWidth: 14,
                    ),
                    child: child,
                  ),
                  child: Align(
                    alignment: const Alignment(0, 0.55),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${pct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                            height: 1,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          '${context.t('home.of')} ${context.t('home.budget')}',
                          style: TextStyle(
                            fontSize: 11,
                            color: brand.inkSoft,
                            fontWeight: FontWeight.w700,
                            height: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Container(height: 1, color: brand.divider),
            const SizedBox(height: 13),
            Row(
              children: [
                Expanded(
                  child: _BudgetAmountMetric(
                    value: visible
                        ? formatMoney('', budgetSpent).trim()
                        : '****',
                    label: context.t('home.budgetSpent'),
                    valueColor: brand.ink,
                  ),
                ),
                Container(width: 1, height: 42, color: brand.divider),
                Expanded(
                  child: _BudgetAmountMetric(
                    value: visible
                        ? formatMoney('', budgetRemaining.abs()).trim()
                        : '****',
                    label: overspent
                        ? context.t('home.overBy')
                        : context.t('home.budgetRemaining'),
                    valueColor: overspent
                        ? AppColors.expense
                        : AppColors.income,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            _DottedDivider(color: brand.divider),
            const SizedBox(height: 12),
            _DailyStat(
              label: 'Averaged daily spending',
              value: visible ? formatMoney('', avgDaily).trim() : '****',
              brand: brand,
              dotColor: const Color(0xFFE89A14),
            ),
            const SizedBox(height: 8),
            _DailyStat(
              label: 'Remaining daily',
              value: visible
                  ? (daysRemaining > 0
                        ? formatMoney('', remainingDaily).trim()
                        : '—')
                  : '****',
              brand: brand,
              dotColor: AppActionBlue.color,
              valueColor: daysRemaining > 0 && !overspent
                  ? AppColors.income
                  : null,
            ),
          ] else
            SizedBox(
              height: 219,
              child: Center(
                child: Text(
                  context.t('home.budgetNoBudget'),
                  style: TextStyle(
                    fontSize: 13,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TopStat extends StatelessWidget {
  final Color dotColor;
  final String label;
  final String value;
  final Color ink;
  final Color soft;

  const _TopStat({
    required this.dotColor,
    required this.label,
    required this.value,
    required this.ink,
    required this.soft,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: soft,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _BudgetAmountMetric extends StatelessWidget {
  final String value;
  final String label;
  final Color valueColor;

  const _BudgetAmountMetric({
    required this.value,
    required this.label,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: valueColor,
            height: 1.05,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: brand.inkSoft,
            height: 1,
          ),
        ),
      ],
    );
  }
}

class _DailyStat extends StatelessWidget {
  final String label;
  final String value;
  final BrandColors brand;
  final Color dotColor;
  final Color? valueColor;

  const _DailyStat({
    required this.label,
    required this.value,
    required this.brand,
    required this.dotColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: brand.ink,
              fontWeight: FontWeight.w500,
              height: 1.1,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: valueColor ?? brand.ink,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

class _ArcGaugePainter extends CustomPainter {
  final double progress;
  final Color bgColor;
  final Color fgColor;
  final double strokeWidth;

  const _ArcGaugePainter({
    required this.progress,
    required this.bgColor,
    required this.fgColor,
    this.strokeWidth = 10,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.height - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..color = fgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, math.pi, math.pi, false, bgPaint);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        math.pi,
        math.pi * progress.clamp(0.0, 1.0),
        false,
        fgPaint,
      );
    }
  }

  @override
  bool shouldRepaint(_ArcGaugePainter old) =>
      old.progress != progress ||
      old.bgColor != bgColor ||
      old.fgColor != fgColor ||
      old.strokeWidth != strokeWidth;
}

class _DottedDivider extends StatelessWidget {
  final Color color;

  const _DottedDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 1,
      width: double.infinity,
      child: CustomPaint(painter: _DottedDividerPainter(color)),
    );
  }
}

class _DottedDividerPainter extends CustomPainter {
  final Color color;

  const _DottedDividerPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    const dashWidth = 2.0;
    const gap = 6.0;
    var x = 0.0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + dashWidth, size.width), size.height / 2),
        paint,
      );
      x += dashWidth + gap;
    }
  }

  @override
  bool shouldRepaint(_DottedDividerPainter old) => old.color != color;
}

// ── All Activity bottom sheet ──────────────────────────────────

class _AllBillsSheet extends ConsumerWidget {
  final List<Expense> expenses;
  final double total;
  final String symbol;
  final DateTime month;

  const _AllBillsSheet({
    required this.expenses,
    required this.total,
    required this.symbol,
    required this.month,
  });

  Future<void> _deleteExpense(
    BuildContext context,
    WidgetRef ref,
    Expense expense,
  ) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final uid = user.uid;
    try {
      if (storageMode == StorageMode.firebase) {
        final isOnline = ref.read(isOnlineProvider);
        await SyncService().deleteExpense(
          userId: uid,
          expenseId: expense.id,
          isOnline: isOnline,
        );
      } else {
        await LocalExpenseRepository().deleteExpense(uid, expense.id);
      }
      if (!context.mounted) return;
      AppToast.show(
        context,
        context.t('expense.entryDeleted'),
        type: AppToastType.info,
        icon: CupertinoIcons.trash,
      );
    } catch (_) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        context.t('common.error'),
        type: AppToastType.error,
        icon: CupertinoIcons.exclamationmark_circle_fill,
      );
    }
  }

  void _copyRecord(BuildContext context, Expense original) {
    AppToast.show(
      context,
      'Record has been copied',
      type: AppToastType.info,
      icon: CupertinoIcons.doc_on_doc,
    );
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => AddEditExpenseScreen(copyFrom: original),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
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
                    const Text(
                      'Activity',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMMM yyyy').format(month),
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
          const SizedBox(height: 14),
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
                  '${expenses.length} ${expenses.length == 1 ? context.t('common.entry') : context.t('common.entries')}',
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
            child: Container(
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(18),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: expenses.length,
                  separatorBuilder: (_, _) => Padding(
                    padding: const EdgeInsets.only(left: 70),
                    child: Container(height: 0.5, color: brand.divider),
                  ),
                  itemBuilder: (ctx, i) {
                    final expense = expenses[i];
                    final acct = accounts
                        .where((a) => a.id == expense.accountId)
                        .firstOrNull;
                    return ExpenseCard(
                      key: ValueKey(expense.id),
                      expense: expense,
                      currencySymbol: symbol,
                      account: acct,
                      flat: true,
                      onTap: () => Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) =>
                              AddEditExpenseScreen(expense: expense),
                        ),
                      ),
                      onEdit: () => Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) =>
                              AddEditExpenseScreen(expense: expense),
                        ),
                      ),
                      onDelete: () => _deleteExpense(context, ref, expense),
                      onCopy: () => _copyRecord(context, expense),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
