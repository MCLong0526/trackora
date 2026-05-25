import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/borrow_lending.dart';
import '../../models/expense.dart';
import '../../models/installment.dart';
import '../../models/person.dart';
import '../../models/precious_metal.dart';
import '../../models/saving_plan.dart';
import '../../models/stock_investment.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/exchange_rate_sheet.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/section_card.dart';
import '../borrow_lending/borrow_lending_screen.dart';
import '../installments/installments_screen.dart';
import '../investments/investment_screen.dart';
import '../people/people_screen.dart';
import '../savings/saving_plans_screen.dart';
import '../travel/travel_groups_screen.dart';

bool _isDiscretionary(Expense e) =>
    e.type == EntryType.expense &&
    e.category != 'Bills' &&
    !e.note.contains('(installment)');

Future<void> showMonthlyBudgetEditor(
  BuildContext context,
  WidgetRef ref,
  double current,
  String symbol,
  String? userId,
) async {
  if (userId == null) return;
  final controller = TextEditingController(
    text: current > 0 ? current.toStringAsFixed(2) : '',
  );
  final result = await showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.brand.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      final brand = ctx.brand;
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.t('budget.setMonthlyBudget'),
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              context.t('budget.sheetSubtitle'),
              style: TextStyle(color: brand.inkSoft, fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              autofocus: false,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                prefixText: '$symbol  ',
                hintText: '0.00',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(controller.text) ?? 0;
                Navigator.pop(ctx, v);
              },
              child: Text(context.t('common.save')),
            ),
          ],
        ),
      );
    },
  );
  if (result != null) {
    try {
      await ref.read(expenseRepositoryProvider).setMonthlyBudget(userId, result);
      if (context.mounted) {
        AppToast.show(context, 'Budget updated', type: AppToastType.success);
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.show(context, 'Failed to save budget', type: AppToastType.error);
      }
    }
  }
}

Future<void> showMonthlyBudgetDetails(
  BuildContext context,
  WidgetRef ref, {
  required double budget,
  required double spent,
  required String symbol,
  required String? userId,
  required DateTime month,
}) async {
  final remaining = budget - spent;
  final usage = budget <= 0 ? 0.0 : spent / budget;
  final usagePercent = budget <= 0 ? 0 : (usage * 100).round();
  final editRequested = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.brand.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
      final brand = ctx.brand;
      final progress = usage.clamp(0.0, 1.0).toDouble();
      final remainingColor = budget <= 0
          ? brand.inkSoft
          : remaining < 0
          ? AppColors.expense
          : AppColors.income;
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
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('budget.detailsTitle'),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
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
                    onTap: () => Navigator.pop(ctx, false),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              SectionCard(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _BudgetDetailMetric(
                            label: context.t('budget.budgetAmount'),
                            value: budget <= 0
                                ? context.t('budget.monthlyNotSet')
                                : formatMoney(symbol, budget),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BudgetDetailMetric(
                            label: context.t('budget.amountSpentThisMonth'),
                            value: formatMoney(symbol, spent),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: progress,
                        minHeight: 8,
                        backgroundColor: brand.divider,
                        valueColor: AlwaysStoppedAnimation(
                          usage > 1 ? AppColors.expense : AppColors.income,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: _BudgetDetailMetric(
                            label: context.t('budget.remainingBudget'),
                            value: budget <= 0
                                ? context.t('budget.setAction')
                                : formatMoney(symbol, remaining.abs()),
                            valueColor: remainingColor,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BudgetDetailMetric(
                            label: context.t('budget.usage'),
                            value: budget <= 0
                                ? '0%'
                                : context
                                      .t('budget.percentUsed')
                                      .replaceFirst(
                                        '{percent}',
                                        '$usagePercent',
                                      ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Text(
                context.t('budget.detailsSubtitle'),
                style: TextStyle(
                  fontSize: 12,
                  color: brand.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(context.t('budget.editMonthlyBudget')),
              ),
            ],
          ),
        ),
      );
    },
  );

  if (editRequested == true && context.mounted) {
    await showMonthlyBudgetEditor(context, ref, budget, symbol, userId);
  }
}

class BudgetScreen extends ConsumerWidget {
  const BudgetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expenses =
        ref.watch(expensesProvider).valueOrNull ?? const <Expense>[];
    final budget = ref.watch(budgetProvider).valueOrNull ?? 0.0;
    final installments =
        ref.watch(installmentsProvider).valueOrNull ?? const <Installment>[];
    final borrowLending =
        ref.watch(borrowLendingProvider).valueOrNull ?? const <BorrowLending>[];
    final savingPlans =
        ref.watch(savingPlansProvider).valueOrNull ?? const <SavingPlan>[];
    final people = ref.watch(peopleProvider).valueOrNull ?? const [];
    final travelGroups =
        ref.watch(travelGroupsProvider).valueOrNull ?? const [];
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final month = ref.watch(selectedMonthProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final visibleModules = ref.watch(moneyHubVisibilityProvider);
    final metals =
        ref.watch(preciousMetalsProvider).valueOrNull ?? const <PreciousMetal>[];
    final stocks =
        ref.watch(stockInvestmentsProvider).valueOrNull ?? const <StockInvestment>[];

    final discretionarySpent = expenses
        .where(_isDiscretionary)
        .fold<double>(0, (s, e) => s + e.convertedAmount);

    final activeInstallments = installments
        .where((i) => i.isActiveIn(month))
        .toList();
    final installmentsMonthly = activeInstallments.fold<double>(
      0,
      (s, i) => s + i.amount,
    );

    final activeBorrowLending = borrowLending
        .where(
          (r) =>
              r.status != BorrowLendingStatus.cancelled &&
              r.status != BorrowLendingStatus.settled,
        )
        .toList();
    final borrowed = activeBorrowLending
        .where((r) => r.type == BorrowLendingType.borrowed)
        .fold<double>(0, (s, r) => s + r.remaining);
    final lent = activeBorrowLending
        .where((r) => r.type == BorrowLendingType.lent)
        .fold<double>(0, (s, r) => s + r.remaining);
    final net = lent - borrowed;

    final trackedPlans = savingPlans
        .where((p) => p.status != SavingPlanStatus.cancelled)
        .toList();
    final saved = trackedPlans.fold<double>(0, (s, p) => s + p.currentAmount);

    final budgetLeft = budget - discretionarySpent;
    final budgetOverspent = budgetLeft < 0;

    final savingTarget = trackedPlans.fold<double>(0, (s, p) => s + p.targetAmount);
    final budgetProgress = budget > 0
        ? (discretionarySpent / budget).clamp(0.0, 1.0)
        : null;
    final savingProgress = savingTarget > 0
        ? (saved / savingTarget).clamp(0.0, 1.0)
        : null;
    final budgetUsagePct = budget > 0
        ? (discretionarySpent / budget * 100).clamp(0, 999).round()
        : 0;
    final savingUsagePct = savingTarget > 0
        ? (saved / savingTarget * 100).clamp(0, 100).round()
        : 0;

    // ── People breakdown ──────────────────────────────────────────────────────
    final friendCount =
        people.where((p) => p.type == PersonType.friend).length;
    final familyCount =
        people.where((p) => p.type == PersonType.family).length;
    final coworkerCount =
        people.where((p) => p.type == PersonType.coworker).length;
    final peopleParts = <String>[
      if (friendCount > 0)
        '$friendCount friend${friendCount > 1 ? 's' : ''}',
      if (familyCount > 0) '$familyCount family',
      if (coworkerCount > 0) '$coworkerCount work',
    ];
    final peopleSubInfo = peopleParts.take(2).join(' · ');

    // ── Travel breakdown ──────────────────────────────────────────────────────
    final now = DateTime.now();
    final activeTrips = travelGroups
        .where((t) => t.endDate == null || t.endDate!.isAfter(now))
        .length;
    final totalTripMembers =
        travelGroups.fold<int>(0, (s, t) => s + t.memberIds.length);

    // ── Investment totals ─────────────────────────────────────────────────────
    double metalsTotalValue = 0;
    for (final m in metals) {
      metalsTotalValue +=
          m.action == MetalAction.buy ? m.totalAmount : -m.totalAmount;
    }
    if (metalsTotalValue < 0) metalsTotalValue = 0;
    final stocksCostBasis =
        stocks.fold<double>(0, (s, e) => s + e.totalCost);
    final portfolioTotal = metalsTotalValue + stocksCostBasis;
    final hasAnyInvestment = metals.isNotEmpty || stocks.isNotEmpty;

    final cardOrder = ref.watch(moneyHubOrderProvider);

    final cardWidgets = <String, Widget>{
      if (visibleModules.contains('monthlyBudget'))
        'monthlyBudget': _PremiumManagementCard(
          badgeLabel: context.t('budget.badgeBudget'),
          badgeColor: AppColors.lilac,
          badgeTextColor: kCategoryStyles['Shopping']!.accent,
          icon: CupertinoIcons.chart_pie_fill,
          iconBgColor: kCategoryStyles['Shopping']!.accent,
          mainValue: budget <= 0
              ? context.t('budget.monthlyNotSet')
              : formatMoney(symbol, budgetLeft.abs()),
          mainValueSub: budget <= 0
              ? null
              : budgetOverspent
              ? context.t('budget.overBudget')
              : context.t('budget.leftThisMonth'),
          progress: budgetProgress,
          progressLabel: budget <= 0
              ? context.t('budget.setAction')
              : '$budgetUsagePct% used',
          progressColor: budgetOverspent ? AppColors.expense : null,
          onTap: () => showMonthlyBudgetDetails(
            context,
            ref,
            budget: budget,
            spent: discretionarySpent,
            symbol: symbol,
            userId: user?.uid,
            month: month,
          ),
        ),
      if (visibleModules.contains('savingPlans'))
        'savingPlans': _PremiumManagementCard(
          badgeLabel: context.t('budget.badgeSavings'),
          badgeColor: AppColors.mint,
          badgeTextColor: kCategoryStyles['Groceries']!.accent,
          icon: CupertinoIcons.flag_fill,
          iconBgColor: kCategoryStyles['Groceries']!.accent,
          mainValue: formatMoney(symbol, saved),
          mainValueSub: savingTarget > 0
              ? 'of ${formatMoney(symbol, savingTarget)} goal'
              : '${trackedPlans.length} plans',
          progress: savingProgress,
          progressLabel: savingTarget > 0 ? '$savingUsagePct% saved' : null,
          onTap: () => _push(context, const SavingPlansScreen()),
        ),
      if (visibleModules.contains('borrowLending'))
        'borrowLending': _PremiumManagementCard(
          badgeLabel: context.t('budget.badgeLending'),
          badgeColor: AppColors.sky,
          badgeTextColor: kCategoryStyles['Transport']!.accent,
          icon: CupertinoIcons.arrow_up_arrow_down,
          iconBgColor: kCategoryStyles['Transport']!.accent,
          mainValue: net == 0
              ? formatMoney(symbol, 0)
              : '${net > 0 ? '+' : '-'}${formatMoney(symbol, net.abs())}',
          mainValueSub: context.t('budget.netPosition'),
          mainValueColor: net < 0
              ? AppColors.expense
              : net > 0
              ? AppColors.income
              : null,
          footer: '↑ ${formatMoney(symbol, lent)} · ↓ ${formatMoney(symbol, borrowed)}',
          onTap: () => _push(context, const BorrowLendingScreen()),
        ),
      if (visibleModules.contains('installments'))
        'installments': _PremiumManagementCard(
          badgeLabel: context.t('budget.badgeInstallments'),
          badgeColor: AppColors.peach,
          badgeTextColor: kCategoryStyles['Food']!.accent,
          icon: CupertinoIcons.calendar_today,
          iconBgColor: kCategoryStyles['Food']!.accent,
          mainValue: activeInstallments.isEmpty
              ? '—'
              : formatMoney(symbol, installmentsMonthly),
          mainValueSub: activeInstallments.isEmpty
              ? null
              : context.t('budget.dueThisMonth'),
          footer: activeInstallments.isEmpty
              ? context.t('budget.noneActive')
              : context.t('budget.activePlans').replaceAll('{count}', '${activeInstallments.length}'),
          onTap: () => _push(context, const InstallmentsScreen()),
        ),
      if (visibleModules.contains('people'))
        'people': _PremiumManagementCard(
          badgeLabel: context.t('budget.badgePeople'),
          badgeColor: AppColors.lilac,
          badgeTextColor: kCategoryStyles['Shopping']!.accent,
          icon: CupertinoIcons.person_2_fill,
          iconBgColor: kCategoryStyles['Shopping']!.accent,
          mainValue: people.isEmpty ? '—' : '${people.length}',
          mainValueSub: people.isEmpty
              ? null
              : people.length == 1
              ? 'contact'
              : 'contacts',
          footer: people.isEmpty
              ? context.t('budget.tapToAddPeople')
              : peopleSubInfo.isNotEmpty
                  ? peopleSubInfo
                  : '${activeBorrowLending.length} record${activeBorrowLending.length == 1 ? '' : 's'}',
          onTap: () => _push(context, const PeopleScreen()),
        ),
      if (visibleModules.contains('travelGroups'))
        'travelGroups': _PremiumManagementCard(
          badgeLabel: context.t('travel.title'),
          badgeColor: AppColors.sky,
          badgeTextColor: const Color(0xFF3478F6),
          icon: CupertinoIcons.airplane,
          iconBgColor: const Color(0xFF3478F6),
          mainValue: travelGroups.isEmpty ? '—' : '${travelGroups.length}',
          mainValueSub: travelGroups.isEmpty
              ? null
              : activeTrips == travelGroups.length
              ? 'all active'
              : '$activeTrips active',
          footer: travelGroups.isEmpty
              ? context.t('travel.empty')
              : totalTripMembers > 0
                  ? '$totalTripMembers member${totalTripMembers == 1 ? '' : 's'} total'
                  : context.t('travel.title'),
          onTap: () => _push(context, const TravelGroupsScreen()),
        ),
      if (visibleModules.contains('investments'))
        'investments': _PremiumManagementCard(
          badgeLabel: 'PORTFOLIO',
          badgeColor: const Color(0xFFEBEAFF),
          badgeTextColor: const Color(0xFF5856D6),
          icon: CupertinoIcons.chart_bar_square_fill,
          iconBgColor: const Color(0xFF5856D6),
          mainValue: hasAnyInvestment ? formatMoney(symbol, portfolioTotal) : '—',
          mainValueSub: hasAnyInvestment
              ? [
                  if (metals.isNotEmpty)
                    '${metals.length} metal${metals.length == 1 ? '' : 's'}',
                  if (stocks.isNotEmpty)
                    '${stocks.length} stock${stocks.length == 1 ? '' : 's'}',
                ].join(' · ')
              : null,
          footer: hasAnyInvestment ? 'cost basis' : 'Gold, silver & stocks',
          onTap: () => _push(context, const InvestmentScreen()),
        ),
    };

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
          // ── Title row ────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('money.title'),
                  style: Theme.of(context).textTheme.displayMedium,
                ),
              ),
              Row(
                children: [
                  CircleIconButton(
                    icon: CupertinoIcons.slider_horizontal_3,
                    size: 40,
                    onTap: () => _showMoneyHubSheet(context, ref),
                  ),
                  const SizedBox(width: 8),
                  const FxRateButton(),
                  const SizedBox(width: 8),
                  const ProfileAvatarButton(),
                ],
              ),
            ],
          ),

          const SizedBox(height: 24),

          // ── Management cards ──────────────────────────────
          _GroupHeader(label: context.t('budget.management')),
          const SizedBox(height: 10),
          _DragReorderGrid(
            order: cardOrder,
            cards: cardWidgets,
            onReorder: (order) =>
                ref.read(moneyHubOrderProvider.notifier).setOrder(order),
          ),
        ],
      ),
    );
  }

  static void _push(BuildContext context, Widget screen) {
    HapticFeedback.selectionClick();
    Navigator.push(context, CupertinoPageRoute(builder: (_) => screen));
  }

  void _showMoneyHubSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.brand.background,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => Consumer(
        builder: (context, ref, _) {
          final visible = ref.watch(moneyHubVisibilityProvider);
          final notifier = ref.read(moneyHubVisibilityProvider.notifier);
          final items = [
            ('installments', context.t('budget.manageInstallments')),
            ('borrowLending', context.t('tools.borrowLending')),
            ('savingPlans', context.t('tools.savingPlans')),
            ('monthlyBudget', context.t('home.budget')),
            ('people', 'People'),
            ('travelGroups', context.t('travel.title')),
            ('investments', 'Investments'),
          ];
          return SingleChildScrollView(
            child: _VisibilitySheet(
              title: context.t('money.customizeHub'),
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
            ),
          );
        },
      ),
    );
  }
}

class _BudgetDetailMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _BudgetDetailMetric({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 11,
            color: brand.inkSoft,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              fontSize: 17,
              color: valueColor ?? brand.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;

  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: brand.inkSoft,
          letterSpacing: 0.8,
        ),
      ),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
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
          const SizedBox(height: 14),
          SectionCard(
            padding: EdgeInsets.zero,
            child: Column(children: children),
          ),
          const SizedBox(height: 12),
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
      padding: const EdgeInsets.fromLTRB(18, 12, 16, 12),
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

// ── Premium management card ────────────────────────────────────

class _PremiumManagementCard extends StatelessWidget {
  final String badgeLabel;
  final Color badgeColor;
  final Color badgeTextColor;
  final IconData icon;
  final Color iconBgColor;
  final String mainValue;
  final String? mainValueSub;
  final Color? mainValueColor;
  final double? progress;
  final String? progressLabel;
  final Color? progressColor;
  final String? footer;
  final VoidCallback onTap;

  const _PremiumManagementCard({
    required this.badgeLabel,
    required this.badgeColor,
    required this.badgeTextColor,
    required this.icon,
    required this.iconBgColor,
    required this.mainValue,
    this.mainValueSub,
    this.mainValueColor,
    this.progress,
    this.progressLabel,
    this.progressColor,
    this.footer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge + chevron
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 10, color: badgeTextColor),
                      const SizedBox(width: 4),
                      Text(
                        badgeLabel,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: badgeTextColor,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 12,
                  color: brand.inkSoft,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Donut / circle progress or icon
            if (progress != null) ...[
              _CircleProgress(
                progress: progress!,
                color: progressColor ?? iconBgColor,
                size: 48,
                strokeWidth: 5,
              ),
              const SizedBox(height: 8),
            ] else ...[
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: badgeColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: badgeTextColor),
              ),
              const SizedBox(height: 8),
            ],
            // Main value
            FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                mainValue,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: mainValueColor ?? brand.ink,
                ),
              ),
            ),
            if (mainValueSub != null) ...[
              const SizedBox(height: 2),
              Text(
                mainValueSub!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: brand.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            if (footer != null || progressLabel != null) ...[
              const Spacer(),
              Text(
                footer ?? progressLabel ?? '',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10,
                  color: brand.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Circle progress indicator ──────────────────────────────────

class _CircleProgress extends StatelessWidget {
  final double progress;
  final Color color;
  final double size;
  final double strokeWidth;

  const _CircleProgress({
    required this.progress,
    required this.color,
    required this.size,
    required this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress.clamp(0.0, 1.0),
            strokeWidth: strokeWidth,
            backgroundColor: brand.divider,
            valueColor: AlwaysStoppedAnimation(color),
            strokeCap: StrokeCap.round,
          ),
          Text(
            '${(progress * 100).round()}%',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: brand.ink,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Drag-reorder grid ──────────────────────────────────────────────────────────

class _DragReorderGrid extends StatefulWidget {
  final List<String> order;
  final Map<String, Widget> cards;
  final void Function(List<String>) onReorder;

  const _DragReorderGrid({
    required this.order,
    required this.cards,
    required this.onReorder,
  });

  @override
  State<_DragReorderGrid> createState() => _DragReorderGridState();
}

class _DragReorderGridState extends State<_DragReorderGrid> {
  late List<String> _order;
  String? _dragging;
  String? _hoverTarget;

  @override
  void initState() {
    super.initState();
    _order = List.from(widget.order);
  }

  @override
  void didUpdateWidget(_DragReorderGrid old) {
    super.didUpdateWidget(old);
    if (_dragging == null) {
      _order = List.from(widget.order);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return LayoutBuilder(
      builder: (ctx, constraints) {
        const h = 186.0;
        const gap = 12.0;
        final w = (constraints.maxWidth - gap) / 2;
        final visible =
            _order.where((id) => widget.cards.containsKey(id)).toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        final rows = (visible.length / 2).ceil();
        final height = rows * h + (rows - 1) * gap;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: height,
              child: Stack(
                children: [
                  for (int i = 0; i < visible.length; i++)
                    _buildCell(i, visible[i], w, h, gap),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    CupertinoIcons.hand_draw,
                    size: 13,
                    color: brand.inkSoft.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'Hold & drag to reorder',
                    style: TextStyle(
                      fontSize: 12,
                      color: brand.inkSoft.withValues(alpha: 0.55),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildCell(int idx, String id, double w, double h, double gap) {
    final card = widget.cards[id]!;
    final left = (idx % 2) * (w + gap);
    final top = (idx ~/ 2) * (h + gap);
    final isDragging = _dragging == id;

    return AnimatedPositioned(
      key: ValueKey(id),
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: w,
      height: h,
      child: LongPressDraggable<String>(
        data: id,
        delay: const Duration(milliseconds: 350),
        onDragStarted: () {
          HapticFeedback.mediumImpact();
          setState(() {
            _dragging = id;
            _hoverTarget = null;
          });
        },
        onDragEnd: (_) {
          final newOrder = _order.toList();
          widget.onReorder(newOrder);
          setState(() {
            _dragging = null;
            _hoverTarget = null;
          });
        },
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: w,
            height: h,
            child: Transform.scale(scale: 1.06, child: card),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.0, child: card),
        child: DragTarget<String>(
          onWillAcceptWithDetails: (details) {
            if (details.data == id || _hoverTarget == id) return false;
            final fromIdx = _order.indexOf(details.data);
            final toIdx = _order.indexOf(id);
            if (fromIdx == -1 || toIdx == -1 || fromIdx == toIdx) return false;
            HapticFeedback.selectionClick();
            setState(() {
              _hoverTarget = id;
              final item = _order.removeAt(fromIdx);
              _order.insert(toIdx, item);
            });
            return false;
          },
          builder: (ctx, candidateData, rejectedData) => AnimatedScale(
            scale: isDragging ? 1.0 : (_dragging != null ? 0.96 : 1.0),
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            child: card,
          ),
        ),
      ),
    );
  }
}
