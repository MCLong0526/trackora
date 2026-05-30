import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../models/expense.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/account_carousel_section.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/exchange_rate_sheet.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/section_card.dart';
import '../../widgets/sticky_header_scaffold.dart';
import '../borrow_lending/borrow_lending_screen.dart';
import '../installments/installments_screen.dart';
import '../investments/investment_screen.dart';
import '../people/people_screen.dart';
import '../savings/saving_plans_screen.dart';
import '../travel/travel_groups_screen.dart';
import '../group/create_group_screen.dart';
import '../group/group_dashboard_screen.dart';

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
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final month = ref.watch(selectedMonthProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final visibleModules = ref.watch(moneyHubVisibilityProvider);
    // Accounts for carousel
    final accounts =
        ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final allExpenses =
        ref.watch(allExpensesProvider).valueOrNull ?? const <Expense>[];
    final visible = ref.watch(balanceVisibleProvider);
    final accountBalances = _computeBalances(accounts, allExpenses);
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const [];

    final discretionarySpent = expenses
        .where(_isDiscretionary)
        .fold<double>(0, (s, e) => s + e.convertedAmount);

    // ── Quick-style button items — standard modules first, tools at end ─────────
    final quickItems = <_BudgetQuickItem>[
      if (visibleModules.contains('monthlyBudget'))
        _BudgetQuickItem(
          icon: CupertinoIcons.chart_pie_fill,
          iconBg: AppColors.lilac,
          iconColor: kCategoryStyles['Shopping']!.accent,
          label: context.t('budget.badgeBudget'),
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
        _BudgetQuickItem(
          icon: CupertinoIcons.flag_fill,
          iconBg: AppColors.mint,
          iconColor: kCategoryStyles['Groceries']!.accent,
          label: context.t('budget.badgeSavings'),
          onTap: () => _push(context, const SavingPlansScreen()),
        ),
      if (visibleModules.contains('borrowLending'))
        _BudgetQuickItem(
          icon: CupertinoIcons.arrow_up_arrow_down,
          iconBg: AppColors.sky,
          iconColor: kCategoryStyles['Transport']!.accent,
          label: context.t('budget.badgeLending'),
          onTap: () => _push(context, const BorrowLendingScreen()),
        ),
      if (visibleModules.contains('installments'))
        _BudgetQuickItem(
          icon: CupertinoIcons.calendar_today,
          iconBg: AppColors.peach,
          iconColor: kCategoryStyles['Food']!.accent,
          label: context.t('budget.badgeInstallments'),
          onTap: () => _push(context, const InstallmentsScreen()),
        ),
      if (visibleModules.contains('people'))
        _BudgetQuickItem(
          icon: CupertinoIcons.person_2_fill,
          iconBg: AppColors.lilac,
          iconColor: kCategoryStyles['Shopping']!.accent,
          label: context.t('budget.badgePeople'),
          onTap: () => _push(context, const PeopleScreen()),
        ),
      if (visibleModules.contains('travelGroups'))
        _BudgetQuickItem(
          icon: CupertinoIcons.airplane,
          iconBg: AppColors.sky,
          iconColor: const Color(0xFF3478F6),
          label: context.t('travel.title'),
          onTap: () => _push(context, const TravelGroupsScreen()),
        ),
      if (visibleModules.contains('investments'))
        _BudgetQuickItem(
          icon: CupertinoIcons.chart_bar_square_fill,
          iconBg: const Color(0xFFEBEAFF),
          iconColor: const Color(0xFF5856D6),
          label: 'Portfolio',
          onTap: () => _push(context, const InvestmentScreen()),
        ),
      // ── Always-visible tools ──────────────────────────────
      _BudgetQuickItem(
        icon: CupertinoIcons.calendar_badge_plus,
        iconBg: AppColors.butter,
        iconColor: AppColors.ink,
        label: 'Expense Cycle',
        onTap: () => _showCycleSheet(context),
      ),
      _BudgetQuickItem(
        icon: CupertinoIcons.person_2_fill,
        iconBg: const Color(0xFFEAE3F8),
        iconColor: const Color(0xFF5A4AAB),
        label: 'Groups',
        onTap: () {
          HapticFeedback.selectionClick();
          if (groups.isEmpty) {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (_) => const CreateGroupScreen()),
            );
          } else {
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (_) => const GroupDashboardScreen()),
            );
          }
        },
      ),
    ];

    return SafeArea(
      child: StickyHeaderScaffold(
        header: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
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
        ),
        bodyBuilder: (sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
          const SizedBox(height: 16),

          // ── Accounts carousel (top section) ──────────────
          _GroupHeader(label: context.t('asset.title')),
          const SizedBox(height: 10),
          AccountCarouselSection(
            accounts: accounts,
            balances: accountBalances,
            allExpenses: allExpenses,
            symbol: symbol,
            visible: visible,
          ),

          const SizedBox(height: 24),

          // ── Management quick-icon grid ────────────────────
          _GroupHeader(label: context.t('budget.management')),
          const SizedBox(height: 10),
          if (quickItems.isNotEmpty)
            for (int row = 0; row * 3 < quickItems.length; row++) ...[
              if (row > 0) const SizedBox(height: 4),
              Row(
                children: [
                  for (int col = 0; col < 3; col++)
                    Expanded(
                      child: (row * 3 + col) < quickItems.length
                          ? _BudgetQuickButton(item: quickItems[row * 3 + col])
                          : const SizedBox(),
                    ),
                ],
              ),
            ],
          ],  // end ListView children
        ),   // end ListView
      ),     // end StickyHeaderScaffold
    );
  }

  static void _push(BuildContext context, Widget screen) {
    HapticFeedback.selectionClick();
    Navigator.push(context, CupertinoPageRoute(builder: (_) => screen));
  }

  static void _showCycleSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      isScrollControlled: true,
      builder: (_) => const _CycleSheetContent(),
    );
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

// ── Expense Cycle sheet (accessible from Management grid) ─────────────────────

class _CycleSheetContent extends ConsumerWidget {
  const _CycleSheetContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final useCustom = ref.watch(useCustomCycleProvider);
    final cycleDay = ref.watch(cycleDayStartProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                context.t('settings.customExpenseCycle'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.butter,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      CupertinoIcons.calendar_badge_plus,
                      size: 16,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      context.t('settings.customExpenseCycleSub'),
                      style: TextStyle(fontSize: 14, color: brand.inkSoft),
                    ),
                  ),
                  CupertinoSwitch(
                    value: useCustom,
                    activeTrackColor: AppColors.income,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      ref.read(useCustomCycleProvider.notifier).set(v);
                    },
                  ),
                ],
              ),
            ),
            if (useCustom) ...[
              Container(height: 0.5, color: brand.divider, margin: const EdgeInsets.symmetric(horizontal: 14)),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _pickCycleDay(context, ref, cycleDay, brand),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.mint,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(CupertinoIcons.number, size: 16, color: AppColors.ink),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            context.t('settings.cycleStartsOnDay'),
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: brand.ink),
                          ),
                        ),
                        Text('$cycleDay', style: TextStyle(fontSize: 15, color: brand.inkSoft)),
                        const SizedBox(width: 6),
                        Icon(CupertinoIcons.chevron_right, size: 14, color: brand.inkSoft),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCycleDay(BuildContext context, WidgetRef ref, int current, BrandColors brand) async {
    int selected = current;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(color: brand.surface, borderRadius: BorderRadius.circular(20)),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(width: 36, height: 4, decoration: BoxDecoration(color: brand.divider, borderRadius: BorderRadius.circular(2))),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.t('settings.cycleStartsOnDay'),
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: brand.ink),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: const Text('Done', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF0066CC))),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 200,
                child: StatefulBuilder(
                  builder: (context, setLocal) => CupertinoPicker(
                    scrollController: FixedExtentScrollController(initialItem: selected - 1),
                    itemExtent: 40,
                    onSelectedItemChanged: (i) {
                      selected = i + 1;
                      ref.read(cycleDayStartProvider.notifier).set(selected);
                    },
                    children: List.generate(28, (i) => Center(child: Text('${i + 1}', style: TextStyle(fontSize: 18, color: brand.ink)))),
                  ),
                ),
              ),
            ],
          ),
        ),
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

// ── Budget quick-icon button ───────────────────────────────────

class _BudgetQuickItem {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _BudgetQuickItem({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });
}

class _BudgetQuickButton extends StatefulWidget {
  final _BudgetQuickItem item;
  const _BudgetQuickButton({required this.item});

  @override
  State<_BudgetQuickButton> createState() => _BudgetQuickButtonState();
}

class _BudgetQuickButtonState extends State<_BudgetQuickButton>
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
    return GestureDetector(
      onTapDown: (_) => _press.reverse(),
      onTapUp: (_) {
        _press.forward();
        HapticFeedback.selectionClick();
        widget.item.onTap();
      },
      onTapCancel: () => _press.forward(),
      child: ScaleTransition(
        scale: _press,
        child: SizedBox(
          height: 84,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.item.iconBg,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: widget.item.iconBg.withValues(alpha: 0.55),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Icon(
                  widget.item.icon,
                  color: widget.item.iconColor,
                  size: 22,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
                  letterSpacing: -0.1,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Account balance helpers (mirrors assets_screen logic) ──────

double _effectiveAmountForAccount(
  Expense expense,
  String? accountCurrencyCode,
) {
  if (expense.originalCurrency == accountCurrencyCode) return expense.amount;
  return expense.convertedAmount;
}

Map<String, double> _computeBalances(
  List<Account> accounts,
  List<Expense> expenses,
) {
  final currencyCodes = <String, String?>{
    for (final a in accounts) a.id: a.currencyCode,
  };
  final balances = <String, double>{
    for (final a in accounts) a.id: a.openingBalance,
  };
  for (final expense in expenses) {
    final from = expense.accountId;
    if (from != null && balances.containsKey(from)) {
      final amt = _effectiveAmountForAccount(expense, currencyCodes[from]);
      if (expense.type.isInflow) {
        balances[from] = (balances[from] ?? 0) + amt;
      } else {
        balances[from] = (balances[from] ?? 0) - amt;
      }
    }
    final to = expense.toAccountId;
    if (to != null && balances.containsKey(to)) {
      balances[to] = (balances[to] ?? 0) +
          _effectiveAmountForAccount(expense, currencyCodes[to]);
    }
  }
  return balances;
}
