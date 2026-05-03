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
import '../borrow_lending/borrow_lending_screen.dart';
import '../expenses/add_edit_expense_screen.dart';
import '../savings/saving_plans_screen.dart';
import 'budget_screen.dart' show showMonthlyBudgetEditor;

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
    final visibleCards = ref.watch(homeCardVisibilityProvider);
    final email = user?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';

    final budget = budgetAsync.valueOrNull ?? 0;
    final monthExpenses = expensesAsync.valueOrNull ?? const <Expense>[];
    final allExpenses = allExpensesAsync.valueOrNull ?? const <Expense>[];
    final savingPlans = savingPlansAsync.valueOrNull ?? const <SavingPlan>[];
    final borrowLending =
        borrowLendingAsync.valueOrNull ?? const <BorrowLending>[];

    final monthSpent = monthExpenses
        .where((e) => e.type == EntryType.expense)
        .fold<double>(0, (s, e) => s + e.amount);

    final budgetableSpent = monthExpenses
        .where(
          (e) =>
              e.type == EntryType.expense &&
              e.category != 'Bills' &&
              !e.note.contains('(installment)'),
        )
        .fold<double>(0, (s, e) => s + e.amount);

    final totalBalance = ref.watch(savingsProvider);

    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    double todaySpent = 0;
    double weekSpent = 0;
    for (final e in allExpenses) {
      if (e.type != EntryType.expense) continue;
      if (!e.date.isBefore(todayStart)) todaySpent += e.amount;
      if (!e.date.isBefore(weekStart)) weekSpent += e.amount;
    }

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
                  Row(
                    children: [
                      CircleIconButton(
                        icon: CupertinoIcons.slider_horizontal_3,
                        size: 40,
                        onTap: () => _showHomeCardsSheet(context, ref),
                      ),
                      const SizedBox(width: 10),
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
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              child: _HomeBalanceCarousel(
                balance: totalBalance,
                symbol: symbol,
                allExpenses: allExpenses,
                budget: budget,
                budgetSpent: budgetableSpent,
                savingPlans: savingPlans,
                borrowLending: borrowLending,
                userId: user?.uid,
                visibleCards: visibleCards,
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

          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.t('home.recent'),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                  if (monthExpenses.length > 5)
                    Text(
                      '+ ${monthExpenses.length - 5} ${context.t('home.more')}',
                      style: TextStyle(
                        fontSize: 12,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
          ),

          if (monthExpenses.isEmpty)
            SliverToBoxAdapter(child: _empty(context))
          else
            SliverList.builder(
              itemCount: monthExpenses.length > 5 ? 5 : monthExpenses.length,
              itemBuilder: (_, i) {
                final expense = monthExpenses[i];
                return ExpenseCard(
                  expense: expense,
                  currencySymbol: symbol,
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => AddEditExpenseScreen(expense: expense),
                    ),
                  ),
                  onDelete: () => ref
                      .read(expenseRepositoryProvider)
                      .deleteExpense(user!.uid, expense.id),
                );
              },
            ),

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

  void _showHomeCardsSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final visible = ref.watch(homeCardVisibilityProvider);
          final notifier = ref.read(homeCardVisibilityProvider.notifier);
          final items = [
            ('totalBalance', context.t('home.totalBalance')),
            ('monthlyBudget', context.t('home.budget')),
            ('savingPlans', context.t('tools.savingPlans')),
            ('borrowLending', context.t('tools.borrowLending')),
          ];
          return _VisibilitySheet(
            title: context.t('home.customizeCards'),
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
}

class _HomeBalanceCarousel extends ConsumerStatefulWidget {
  final double balance;
  final String symbol;
  final List<Expense> allExpenses;
  final double budget;
  final double budgetSpent;
  final List<SavingPlan> savingPlans;
  final List<BorrowLending> borrowLending;
  final String? userId;
  final Set<String> visibleCards;

  const _HomeBalanceCarousel({
    required this.balance,
    required this.symbol,
    required this.allExpenses,
    required this.budget,
    required this.budgetSpent,
    required this.savingPlans,
    required this.borrowLending,
    required this.userId,
    required this.visibleCards,
  });

  @override
  ConsumerState<_HomeBalanceCarousel> createState() =>
      _HomeBalanceCarouselState();
}

class _HomeBalanceCarouselState extends ConsumerState<_HomeBalanceCarousel> {
  late final PageController _controller;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cards = <(String, Widget)>[
      (
        'totalBalance',
        _TotalBalanceCard(
          balance: widget.balance,
          symbol: widget.symbol,
          allExpenses: widget.allExpenses,
        ),
      ),
      (
        'monthlyBudget',
        _MonthlyBudgetCarouselCard(
          budget: widget.budget,
          spent: widget.budgetSpent,
          symbol: widget.symbol,
          onTap: () => showMonthlyBudgetEditor(
            context,
            ref,
            widget.budget,
            widget.symbol,
            widget.userId,
          ),
        ),
      ),
      (
        'savingPlans',
        _SavingPlansCarouselCard(
          plans: widget.savingPlans,
          symbol: widget.symbol,
          onTap: () => Navigator.push(
            context,
            CupertinoPageRoute(builder: (_) => const SavingPlansScreen()),
          ),
        ),
      ),
      (
        'borrowLending',
        _BorrowLendingCarouselCard(
          records: widget.borrowLending,
          symbol: widget.symbol,
          onTap: () => Navigator.push(
            context,
            CupertinoPageRoute(builder: (_) => const BorrowLendingScreen()),
          ),
        ),
      ),
    ].where((entry) => widget.visibleCards.contains(entry.$1)).toList();
    if (_page >= cards.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _page = 0);
        if (_controller.hasClients) _controller.jumpToPage(0);
      });
    }

    return Column(
      children: [
        SizedBox(
          height: 236,
          child: PageView(
            controller: _controller,
            onPageChanged: (value) => setState(() => _page = value),
            children: [for (final card in cards) card.$2],
          ),
        ),
        const SizedBox(height: 10),
        _PageDots(count: cards.length, active: _page),
      ],
    );
  }
}

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

class _PageDots extends StatelessWidget {
  final int count;
  final int active;

  const _PageDots({required this.count, required this.active});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (index) {
        final selected = index == active;
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
    );
  }
}

class _TotalBalanceCard extends ConsumerWidget {
  final double balance;
  final String symbol;
  final List<Expense> allExpenses;

  const _TotalBalanceCard({
    required this.balance,
    required this.symbol,
    required this.allExpenses,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final positive = balance >= 0;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visible = ref.watch(balanceVisibleProvider);
    final lifetimeIncome = allExpenses
        .where((e) => e.type == EntryType.income)
        .fold<double>(0, (s, e) => s + e.amount);
    final lifetimeSpent = allExpenses
        .where((e) => e.type == EntryType.expense)
        .fold<double>(0, (s, e) => s + e.amount);

    final heroBg = isDark ? const Color(0xFF24242A) : const Color(0xFF111111);
    return SectionCard(
      color: heroBg,
      pastel: false,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _CardIcon(
                icon: CupertinoIcons.money_dollar_circle_fill,
                background: AppColors.accent,
                foreground: AppColors.ink,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  context.t('home.totalBalance'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ),
              GestureDetector(
                onTap: () => ref.read(balanceVisibleProvider.notifier).toggle(),
                behavior: HitTestBehavior.opaque,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Icon(
                    visible
                        ? CupertinoIcons.eye_fill
                        : CupertinoIcons.eye_slash_fill,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: MaskedAmount(
              visibleText: formatMoney(symbol, balance),
              visible: visible,
              currencyPrefix: symbol,
              style: TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.w900,
                color: positive ? Colors.white : AppColors.blush,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.t('home.balanceFormula'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 12,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _DarkMetricPill(
                  label: context.t('home.lifetimeIn'),
                  value: visible
                      ? formatMoney(symbol, lifetimeIncome)
                      : '$symbol ****',
                  color: AppColors.income,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DarkMetricPill(
                  label: context.t('home.lifetimeOut'),
                  value: visible
                      ? formatMoney(symbol, lifetimeSpent)
                      : '$symbol ****',
                  color: AppColors.expense,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MonthlyBudgetCarouselCard extends StatelessWidget {
  final double budget;
  final double spent;
  final String symbol;
  final VoidCallback onTap;

  const _MonthlyBudgetCarouselCard({
    required this.budget,
    required this.spent,
    required this.symbol,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasBudget = budget > 0;
    final remaining = budget - spent;
    final overspent = remaining < 0;

    return SectionCard(
      color: AppColors.lilac,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: CupertinoIcons.chart_pie_fill,
            iconColor: Colors.white.withValues(alpha: 0.65),
            title: context.t('home.budget'),
            chevron: true,
          ),
          const SizedBox(height: 18),
          if (!hasBudget) ...[
            Text(
              context.t('home.budgetNoBudget'),
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.t('home.budgetNoBudgetHint'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
            const Spacer(),
            _MiniAction(label: context.t('budget.setAction')),
          ] else ...[
            FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                formatMoney(symbol, budget),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w900,
                  color: AppColors.ink,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.t('home.budgetLimit'),
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.inkSoft,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: _LightMetricPill(
                    label: context.t('home.budgetSpent'),
                    value: formatMoney(symbol, spent),
                    color: AppColors.expense,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _LightMetricPill(
                    label: overspent
                        ? context.t('home.overBy')
                        : context.t('home.budgetRemaining'),
                    value: formatMoney(symbol, remaining.abs()),
                    color: overspent ? AppColors.expense : AppColors.income,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _SavingPlansCarouselCard extends StatelessWidget {
  final List<SavingPlan> plans;
  final String symbol;
  final VoidCallback onTap;

  const _SavingPlansCarouselCard({
    required this.plans,
    required this.symbol,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tracked = plans
        .where((p) => p.status != SavingPlanStatus.cancelled)
        .toList();
    final active = tracked
        .where((p) => p.status == SavingPlanStatus.active)
        .length;
    final saved = tracked.fold<double>(0, (s, p) => s + p.currentAmount);
    final target = tracked.fold<double>(0, (s, p) => s + p.targetAmount);

    return SectionCard(
      color: AppColors.mint,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: CupertinoIcons.flag_fill,
            iconColor: Colors.white.withValues(alpha: 0.7),
            title: context.t('tools.savingPlans'),
            chevron: true,
          ),
          const SizedBox(height: 18),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              formatMoney(symbol, saved),
              style: const TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.t('home.totalSaved'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _LightMetricPill(
                  label: context.t('home.totalTarget'),
                  value: formatMoney(symbol, target),
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LightMetricPill(
                  label: context.t('home.activePlans'),
                  value: '$active',
                  color: AppColors.income,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BorrowLendingCarouselCard extends StatelessWidget {
  final List<BorrowLending> records;
  final String symbol;
  final VoidCallback onTap;

  const _BorrowLendingCarouselCard({
    required this.records,
    required this.symbol,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final active = records
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
    final net = lent - borrowed;

    return SectionCard(
      color: AppColors.sky,
      padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(
            icon: CupertinoIcons.arrow_up_arrow_down,
            iconColor: Colors.white.withValues(alpha: 0.7),
            title: context.t('tools.borrowLending'),
            chevron: true,
          ),
          const SizedBox(height: 18),
          FittedBox(
            alignment: Alignment.centerLeft,
            fit: BoxFit.scaleDown,
            child: Text(
              formatMoney(symbol, net, forceSign: net > 0),
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.w900,
                color: net < 0 ? AppColors.expense : AppColors.ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.t('home.netPosition'),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.inkSoft,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Expanded(
                child: _LightMetricPill(
                  label: context.t('home.borrowed'),
                  value: formatMoney(symbol, borrowed),
                  color: AppColors.expense,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LightMetricPill(
                  label: context.t('home.lent'),
                  value: formatMoney(symbol, lent),
                  color: AppColors.income,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final bool chevron;

  const _CardHeader({
    required this.icon,
    required this.iconColor,
    required this.title,
    this.chevron = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _CardIcon(icon: icon, background: iconColor, foreground: AppColors.ink),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
            ),
          ),
        ),
        if (chevron)
          const Icon(
            CupertinoIcons.chevron_right,
            size: 15,
            color: AppColors.inkSoft,
          ),
      ],
    );
  }
}

class _CardIcon extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;

  const _CardIcon({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 17, color: foreground),
    );
  }
}

class _DarkMetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _DarkMetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: _MetricText(
        label: label,
        value: value,
        valueColor: color,
        labelColor: Colors.white.withValues(alpha: 0.62),
      ),
    );
  }
}

class _LightMetricPill extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _LightMetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
      ),
      child: _MetricText(
        label: label,
        value: value,
        valueColor: color,
        labelColor: AppColors.inkSoft,
      ),
    );
  }
}

class _MetricText extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final Color labelColor;

  const _MetricText({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 10,
            color: labelColor,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          alignment: Alignment.centerLeft,
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _MiniAction extends StatelessWidget {
  final String label;

  const _MiniAction({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
