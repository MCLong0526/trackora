import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/borrow_lending.dart';
import '../../models/expense.dart';
import '../../models/saving_plan.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/expense_card.dart';
import '../../widgets/masked_amount.dart';
import '../../widgets/month_filter_bar.dart';
import '../../widgets/section_card.dart';
import '../expenses/add_edit_expense_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final selectedMonth = ref.watch(selectedMonthProvider);
    final expensesAsync = ref.watch(expensesProvider);
    final allExpensesAsync = ref.watch(allExpensesProvider);
    final budgetAsync = ref.watch(budgetProvider);
    final savingPlansAsync = ref.watch(savingPlansProvider);
    final borrowLendingAsync = ref.watch(borrowLendingProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final appLocale = ref.watch(localeProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final email = user?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    final budget = budgetAsync.valueOrNull ?? 0;
    final monthExpenses = expensesAsync.valueOrNull ?? const <Expense>[];
    final allExpenses = allExpensesAsync.valueOrNull ?? const <Expense>[];
    final savingPlans = savingPlansAsync.valueOrNull ?? const <SavingPlan>[];
    final borrowLending =
        borrowLendingAsync.valueOrNull ?? const <BorrowLending>[];

    final monthSpent = monthExpenses
        .where((e) => e.type.isOutflow)
        .fold<double>(0, (s, e) => s + e.amount);

    final budgetableSpent = monthExpenses
        .where(
          (e) =>
              e.type == EntryType.expense &&
              e.category != 'Bills' &&
              !e.note.contains('(installment)'),
        )
        .fold<double>(0, (s, e) => s + e.amount);

    final totalBalance = ref.watch(totalAccountBalanceProvider);

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    double todaySpent = 0;
    double weekSpent = 0;
    for (final e in allExpenses) {
      if (!e.type.isOutflow) continue;
      if (!e.date.isBefore(todayStart)) todaySpent += e.amount;
      if (!e.date.isBefore(weekStart)) weekSpent += e.amount;
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
          upcomingInstallments: 0,
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
                          fontWeight: FontWeight.w800,
                          color: brand.ink,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: const BoxDecoration(
                      color: AppColors.lilac,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initial,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: _HomeOverviewCard(
                balance: totalBalance,
                symbol: symbol,
                todaySpent: todaySpent,
                weekSpent: weekSpent,
                budget: budget,
                budgetSpent: budgetableSpent,
                borrowLending: borrowLending,
                savingPlans: savingPlans,
                userId: user?.uid,
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
                    'Activity',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => _showAllBillsSheet(
                      context,
                      monthExpenses,
                      symbol,
                      selectedMonth,
                    ),
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      'See All',
                      style: TextStyle(
                        fontSize: 13,
                        color: brand.accentDark,
                        fontWeight: FontWeight.w800,
                      ),
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
                        for (var i = 0; i < monthExpenses.length.clamp(0, 5); i++) ...[
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
                                onTap: () => Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (_) =>
                                        AddEditExpenseScreen(expense: expense),
                                  ),
                                ),
                                onDelete: () => ref
                                    .read(expenseRepositoryProvider)
                                    .deleteExpense(user!.uid, expense.id),
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
                        'View all ${monthExpenses.length} entries',
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

  void _showAllBillsSheet(
    BuildContext context,
    List<Expense> expenses,
    String symbol,
    DateTime month,
  ) {
    final sorted = [...expenses]..sort((a, b) => b.date.compareTo(a.date));
    final total = sorted
        .where((e) => e.type == EntryType.expense)
        .fold<double>(0, (s, e) => s + e.amount);
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
  final double todaySpent;
  final double weekSpent;
  final double budget;
  final double budgetSpent;
  final List<BorrowLending> borrowLending;
  final List<SavingPlan> savingPlans;
  final String? userId;

  const _HomeOverviewCard({
    required this.balance,
    required this.symbol,
    required this.todaySpent,
    required this.weekSpent,
    required this.budget,
    required this.budgetSpent,
    required this.borrowLending,
    required this.savingPlans,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(balanceVisibleProvider);
    final brand = context.brand;

    final budgetRemaining = budget - budgetSpent;
    final budgetProgress = budget > 0
        ? (budgetSpent / budget).clamp(0.0, 1.0)
        : 0.0;

    final active = borrowLending
        .where(
          (r) =>
              r.status != BorrowLendingStatus.cancelled &&
              r.status != BorrowLendingStatus.settled,
        )
        .toList();
    final borrowed = active
        .where((r) => r.type == BorrowLendingType.borrowed)
        .fold<double>(0, (s, r) => s + r.remaining);
    final lent = active
        .where((r) => r.type == BorrowLendingType.lent)
        .fold<double>(0, (s, r) => s + r.remaining);
    final lendingNet = lent - borrowed;

    final activePlans = savingPlans
        .where((p) => p.status != SavingPlanStatus.cancelled)
        .toList();
    final totalSaved =
        activePlans.fold<double>(0, (s, p) => s + p.currentAmount);
    final totalTarget =
        activePlans.fold<double>(0, (s, p) => s + p.targetAmount);
    final savingsProgress = totalTarget > 0
        ? (totalSaved / totalTarget).clamp(0.0, 1.0)
        : 0.0;

    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: TOTAL BALANCE + eye toggle
          Row(
            children: [
              Text(
                context.t('home.totalBalance').toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: brand.inkSoft,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    ref.read(balanceVisibleProvider.notifier).toggle(),
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  visible ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  size: 20,
                  color: brand.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Balance
          MaskedAmount(
            visibleText: formatMoney(symbol, balance),
            visible: visible,
            currencyPrefix: symbol,
            style: TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: balance >= 0 ? brand.ink : AppColors.expense,
            ),
          ),
          const SizedBox(height: 4),
          // Today / This week
          _TodayWeekRow(
            symbol: symbol,
            todaySpent: todaySpent,
            weekSpent: weekSpent,
            visible: visible,
          ),
          const SizedBox(height: 16),
          // 3 mini-cards
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _MiniBudgetCard(
                    symbol: symbol,
                    budget: budget,
                    remaining: budgetRemaining,
                    progress: budgetProgress,
                    visible: visible,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniLendingCard(
                    symbol: symbol,
                    net: lendingNet,
                    visible: visible,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniSavingsCard(
                    symbol: symbol,
                    saved: totalSaved,
                    target: totalTarget,
                    progress: savingsProgress,
                    visible: visible,
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

class _TodayWeekRow extends StatelessWidget {
  final String symbol;
  final double todaySpent;
  final double weekSpent;
  final bool visible;

  const _TodayWeekRow({
    required this.symbol,
    required this.todaySpent,
    required this.weekSpent,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final todayStr = visible ? formatMoney(symbol, todaySpent) : '$symbol ****';
    final weekStr = visible ? formatMoney(symbol, weekSpent) : '$symbol ****';
    final weekNegative = weekSpent > 0;
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '${context.t('home.today')} $todayStr',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: brand.ink,
            ),
          ),
          TextSpan(
            text: '  ·  ',
            style: TextStyle(fontSize: 12, color: brand.inkSoft),
          ),
          TextSpan(
            text: '${context.t('home.thisWeek')} ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: brand.ink,
            ),
          ),
          TextSpan(
            text: weekNegative ? '–$weekStr' : weekStr,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color:
                  weekNegative ? AppColors.expense : brand.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mini summary cards ─────────────────────────────────────────

class _MiniBudgetCard extends StatelessWidget {
  final String symbol;
  final double budget;
  final double remaining;
  final double progress;
  final bool visible;

  const _MiniBudgetCard({
    required this.symbol,
    required this.budget,
    required this.remaining,
    required this.progress,
    required this.visible,
  });

  static const _dotColor = Color(0xFF5B8AF4);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hasBudget = budget > 0;
    final overspent = remaining < 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'BUDGET',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: brand.inkSoft,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              visible
                  ? (hasBudget
                        ? formatMoney(symbol, remaining.abs())
                        : '—')
                  : '$symbol ****',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: overspent && hasBudget
                    ? AppColors.expense
                    : brand.ink,
              ),
            ),
          ),
          if (hasBudget) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: brand.divider,
                valueColor: const AlwaysStoppedAnimation(_dotColor),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'left',
            style: TextStyle(
              fontSize: 10,
              color: brand.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniLendingCard extends StatelessWidget {
  final String symbol;
  final double net;
  final bool visible;

  const _MiniLendingCard({
    required this.symbol,
    required this.net,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isPositive = net >= 0;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(16),
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
                  color: AppColors.income,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'LENDING',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: brand.inkSoft,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              visible
                  ? formatMoney(symbol, net, forceSign: net > 0)
                  : '$symbol ****',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: isPositive ? brand.ink : AppColors.expense,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'net',
            style: TextStyle(
              fontSize: 10,
              color: brand.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniSavingsCard extends StatelessWidget {
  final String symbol;
  final double saved;
  final double target;
  final double progress;
  final bool visible;

  const _MiniSavingsCard({
    required this.symbol,
    required this.saved,
    required this.target,
    required this.progress,
    required this.visible,
  });

  static const _savingsDotColor = Color(0xFF8B5CF6);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  color: _savingsDotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                'SAVINGS',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: brand.inkSoft,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              visible ? formatMoney(symbol, saved) : '$symbol ****',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: brand.ink,
              ),
            ),
          ),
          if (target > 0) ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 3,
                backgroundColor: brand.divider,
                valueColor: const AlwaysStoppedAnimation(_savingsDotColor),
              ),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            target > 0
                ? 'of ${target.toStringAsFixed(target.truncateToDouble() == target ? 0 : 2)}'
                : 'saved',
            style: TextStyle(
              fontSize: 10,
              color: brand.inkSoft,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// ── All Activity bottom sheet ──────────────────────────────────

class _AllBillsSheet extends StatelessWidget {
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
                    const Text(
                      'Activity',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
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
                      fontWeight: FontWeight.w900,
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
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: expenses.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: brand.divider),
              itemBuilder: (ctx, i) =>
                  _BillRow(expense: expenses[i], symbol: symbol),
            ),
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final Expense expense;
  final String symbol;

  const _BillRow({required this.expense, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final title = expense.note.trim().isEmpty
        ? context.categoryLabel(expense.category)
        : expense.note.trim();
    final isIncome = expense.type == EntryType.income;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
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
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${DateFormat('MMM d').format(expense.date)} · ${context.categoryLabel(expense.category)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            (isIncome ? '+' : '') + formatMoney(symbol, expense.amount),
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: isIncome ? AppColors.income : AppColors.expense,
            ),
          ),
        ],
      ),
    );
  }
}
