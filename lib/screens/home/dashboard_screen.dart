import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/expense.dart';
import '../../models/expense_group.dart';
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
import '../expenses/import_receipt_screen.dart';
import '../travel/travel_groups_screen.dart';
import '../../widgets/personal_group_toggle.dart';
import 'calendar_screen.dart';
import '../group/group_dashboard_screen.dart';

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
    final mode = ref.watch(homeModeProvider);
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const [];
    final hasGroups = groups.isNotEmpty;
    final activeGroupId = ref.watch(activeGroupIdProvider);
    final isGroupMode = mode == HomeMode.group && hasGroups;
    final activeGroup = groups.cast<ExpenseGroup?>().firstWhere(
      (g) => g?.id == activeGroupId,
      orElse: () => groups.isNotEmpty ? groups.first : null,
    );

    if (groups.isEmpty && mode == HomeMode.group) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeGroupIdProvider.notifier).state = null;
        ref.read(homeModeProvider.notifier).state = HomeMode.personal;
      });
    } else if (activeGroupId == null && groups.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeGroupIdProvider.notifier).state = groups.first.id;
      });
    } else if (activeGroupId != null &&
        groups.isNotEmpty &&
        activeGroup?.id != activeGroupId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeGroupIdProvider.notifier).state = activeGroup?.id;
      });
    }

    final cycleRange = ref.watch(cycleDateRangeProvider);
    final visible = ref.watch(balanceVisibleProvider);
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
        return !d.isBefore(cycleRange.start) &&
            d.isBefore(cycleRange.endExclusive);
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
            return !d.isBefore(cycleRange.start) &&
                d.isBefore(cycleRange.endExclusive);
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
    final cycleMonthDate =
        cycleRange?.start ?? DateTime(now.year, now.month, 1);
    final unpaidInstallments = allInstallments.where((inst) {
      if (inst.status != InstallmentStatus.active) return false;
      return !inst.isPaidIn(cycleMonthDate);
    }).toList();
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
                      GestureDetector(
                        onTap: () =>
                            ref.read(balanceVisibleProvider.notifier).toggle(),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: brand.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            visible
                                ? CupertinoIcons.eye
                                : CupertinoIcons.eye_slash,
                            size: 17,
                            color: brand.inkSoft,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const FxRateButton(),
                      const SizedBox(width: 10),
                      if (isGroupMode) ...[
                        GestureDetector(
                          onTap: () => showGroupMenu(
                            context,
                            ref,
                            activeGroup,
                            user?.uid,
                          ),
                          child: GroupAvatarPill(
                            group: activeGroup,
                            userId: user?.uid,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const ProfileAvatarButton(),
                      ] else
                        const ProfileAvatarButton(),
                    ],
                  ),
                ],
              ),
            ),
          ),

          if (hasGroups)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: PersonalGroupToggle(brand: brand),
              ),
            ),

          if (isGroupMode)
            SliverFillRemaining(
              hasScrollBody: true,
              child: GroupDashboardContent(
                brand: brand,
                group: activeGroup,
                symbol: symbol,
                userId: user?.uid,
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  10,
                  20,
                  cycleRange != null ? 4 : 12,
                ),
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
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
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
                                  hasSplitBill:
                                      user != null &&
                                      LocalSplitBillRepository.hasSplitBillSync(
                                        user.uid,
                                        expense.id,
                                      ),
                                  onTap: () => Navigator.push(
                                    context,
                                    CupertinoPageRoute(
                                      builder: (_) => AddEditExpenseScreen(
                                        expense: expense,
                                      ),
                                    ),
                                  ),
                                  onEdit: () => Navigator.push(
                                    context,
                                    CupertinoPageRoute(
                                      builder: (_) => AddEditExpenseScreen(
                                        expense: expense,
                                      ),
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

    final budgetProgress = budget > 0
        ? (budgetSpent / budget).clamp(0.0, 1.0)
        : 0.0;

    final topBg = isDark ? const Color(0xFF201E2C) : brand.surface;
    final topInk = brand.ink;
    final topSoft = brand.inkSoft;
    final statPillBg = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.62);

    const firstCardShadow = <BoxShadow>[];

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
        if (budget > 0) ...[
          const SizedBox(height: 8),
          _BudgetProgressLine(
            visible: visible,
            symbol: symbol,
            budget: budget,
            budgetSpent: budgetSpent,
            budgetProgress: budgetProgress,
            brand: brand,
          ),
        ],
        const SizedBox(height: 12),
        const _QuickAddCard(),
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

// ── Budget progress line (compact, below spending card) ───────

class _BudgetProgressLine extends StatelessWidget {
  final bool visible;
  final String symbol;
  final double budget;
  final double budgetSpent;
  final double budgetProgress;
  final BrandColors brand;

  const _BudgetProgressLine({
    required this.visible,
    required this.symbol,
    required this.budget,
    required this.budgetSpent,
    required this.budgetProgress,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    final budgetRemaining = budget - budgetSpent;
    final overspent = budgetRemaining < 0;
    final barColor = overspent ? AppColors.expense : AppColors.income;
    final pct = (budgetProgress * 100).clamp(0.0, 100.0);

    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: barColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                context.t('home.budget'),
                style: TextStyle(
                  fontSize: 13,
                  color: brand.ink,
                  fontWeight: FontWeight.w500,
                  height: 1.1,
                ),
              ),
              const Spacer(),
              Text(
                visible
                    ? '${pct.toStringAsFixed(1)}%  ·  ${formatMoney(symbol, budgetSpent)} / ${formatMoney(symbol, budget)}'
                    : '$symbol **** / ****',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: overspent ? AppColors.expense : brand.inkSoft,
                  height: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: budgetProgress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, animatedProgress, _) => ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(
                    height: 5,
                    width: double.infinity,
                    color: barColor.withValues(alpha: 0.15),
                  ),
                  FractionallySizedBox(
                    widthFactor: animatedProgress.clamp(0.0, 1.0),
                    child: Container(
                      height: 5,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
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

// ── Quick add card ──────────────────────────────────────────────

class _QuickAddCard extends StatelessWidget {
  const _QuickAddCard();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final items = [
      _QuickItem(
        icon: CupertinoIcons.minus,
        labelKey: 'expense.expense',
        iconBg: isDark ? const Color(0xFF7C3AED).withValues(alpha: 0.22) : const Color(0xFFEFEBFF),
        iconColor: const Color(0xFF7C3AED),
        onTap: () => Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => const AddEditExpenseScreen(initialType: EntryType.expense),
          ),
        ),
      ),
      _QuickItem(
        icon: CupertinoIcons.plus,
        labelKey: 'expense.income',
        iconBg: isDark ? const Color(0xFF22C55E).withValues(alpha: 0.20) : const Color(0xFFE8FBF0),
        iconColor: const Color(0xFF22C55E),
        onTap: () => Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => const AddEditExpenseScreen(initialType: EntryType.income),
          ),
        ),
      ),
      _QuickItem(
        icon: CupertinoIcons.arrow_right_arrow_left,
        labelKey: 'expense.transfer',
        iconBg: isDark ? const Color(0xFFEF4444).withValues(alpha: 0.18) : const Color(0xFFFFEEEE),
        iconColor: const Color(0xFFEF4444),
        onTap: () => Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => const AddEditExpenseScreen(initialType: EntryType.transfer),
          ),
        ),
      ),
      _QuickItem(
        icon: CupertinoIcons.arrow_down_circle,
        labelKey: 'expense.receive',
        iconBg: isDark ? const Color(0xFF7C3AED).withValues(alpha: 0.22) : const Color(0xFFEFEBFF),
        iconColor: const Color(0xFF7C3AED),
        onTap: () => Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => const AddEditExpenseScreen(initialType: EntryType.receive),
          ),
        ),
      ),
      _QuickItem(
        icon: CupertinoIcons.viewfinder,
        labelKey: 'home.scanReceipt',
        iconBg: isDark ? const Color(0xFFF97316).withValues(alpha: 0.18) : const Color(0xFFFFF3E8),
        iconColor: const Color(0xFFF97316),
        onTap: () => Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => const ImportReceiptScreen(openCamera: true),
          ),
        ),
      ),
      _QuickItem(
        icon: CupertinoIcons.person_2,
        labelKey: 'travel.groupTrip',
        iconBg: isDark ? const Color(0xFFE86E2C).withValues(alpha: 0.18) : const Color(0xFFFFF0E8),
        iconColor: const Color(0xFFE86E2C),
        onTap: () => Navigator.push(
          context,
          CupertinoPageRoute(builder: (_) => const TravelGroupsScreen()),
        ),
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.t('quickAdd.title'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
                  letterSpacing: -0.2,
                ),
              ),
              Text(
                context.t('quickAdd.tapToStart'),
                style: TextStyle(
                  fontSize: 12,
                  color: brand.inkSoft,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.05,
            children: items.map((item) => _QuickAddButton(item: item)).toList(),
          ),
        ],
      ),
    );
  }
}

class _QuickItem {
  final IconData icon;
  final String labelKey;
  final Color iconBg;
  final Color iconColor;
  final VoidCallback onTap;

  const _QuickItem({
    required this.icon,
    required this.labelKey,
    required this.iconBg,
    required this.iconColor,
    required this.onTap,
  });
}

class _QuickAddButton extends StatefulWidget {
  final _QuickItem item;

  const _QuickAddButton({required this.item});

  @override
  State<_QuickAddButton> createState() => _QuickAddButtonState();
}

class _QuickAddButtonState extends State<_QuickAddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTapDown: (_) => _press.reverse(),
      onTapUp: (_) {
        _press.forward();
        widget.item.onTap();
      },
      onTapCancel: () => _press.forward(),
      child: ScaleTransition(
        scale: _press,
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? brand.background : const Color(0xFFF7F7FA),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.item.iconBg,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(widget.item.icon, color: widget.item.iconColor, size: 20),
              ),
              const SizedBox(height: 7),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  context.t(widget.item.labelKey),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
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
