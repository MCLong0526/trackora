import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/borrow_lending.dart';
import '../../models/expense.dart';
import '../../models/installment.dart';
import '../../models/precious_metal.dart';
import '../../models/saving_plan.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/section_card.dart';
import '../borrow_lending/borrow_lending_screen.dart';
import '../installments/installments_screen.dart';
import '../people/people_screen.dart';
import '../precious_metals/precious_metals_screen.dart';
import '../savings/saving_plans_screen.dart';

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
              autofocus: true,
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
    final brand = context.brand;
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
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final month = ref.watch(selectedMonthProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final visibleModules = ref.watch(moneyHubVisibilityProvider);
    final metals =
        ref.watch(preciousMetalsProvider).valueOrNull ?? const <PreciousMetal>[];

    final discretionarySpent = expenses
        .where(_isDiscretionary)
        .fold<double>(0, (s, e) => s + e.amount);

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
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(20),
                        
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('MMM').format(month),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: brand.ink,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            CupertinoIcons.chevron_down,
                            size: 12,
                            color: brand.inkSoft,
                          ),
                        ],
                      ),
                    ),
                  ),
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
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - 12) / 2;
              final savingTarget = trackedPlans.fold<double>(
                0,
                (s, p) => s + p.targetAmount,
              );
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

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (visibleModules.contains('monthlyBudget'))
                    SizedBox(
                      width: cardWidth,
                      height: 186,
                      child: _PremiumManagementCard(
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
                        progressColor: budgetOverspent
                            ? AppColors.expense
                            : null,
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
                    ),
                  if (visibleModules.contains('savingPlans'))
                    SizedBox(
                      width: cardWidth,
                      height: 186,
                      child: _PremiumManagementCard(
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
                        progressLabel: savingTarget > 0
                            ? '$savingUsagePct% saved'
                            : null,
                        onTap: () => _push(context, const SavingPlansScreen()),
                      ),
                    ),
                  if (visibleModules.contains('borrowLending'))
                    SizedBox(
                      width: cardWidth,
                      height: 186,
                      child: _PremiumManagementCard(
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
                        footer:
                            '↑ ${formatMoney(symbol, lent)} · ↓ ${formatMoney(symbol, borrowed)}',
                        onTap: () =>
                            _push(context, const BorrowLendingScreen()),
                      ),
                    ),
                  if (visibleModules.contains('installments'))
                    SizedBox(
                      width: cardWidth,
                      height: 186,
                      child: _PremiumManagementCard(
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
                    ),
                  if (visibleModules.contains('people'))
                    SizedBox(
                      width: cardWidth,
                      height: 186,
                      child: _PremiumManagementCard(
                        badgeLabel: context.t('budget.badgePeople'),
                        badgeColor: AppColors.lilac,
                        badgeTextColor: kCategoryStyles['Shopping']!.accent,
                        icon: CupertinoIcons.person_2_fill,
                        iconBgColor: kCategoryStyles['Shopping']!.accent,
                        mainValue: people.isEmpty ? '—' : '${people.length}',
                        mainValueSub: people.isEmpty
                            ? null
                            : people.length == 1
                            ? context.t('budget.personSaved')
                            : context.t('budget.peopleSaved'),
                        footer: people.isEmpty
                            ? context.t('budget.tapToAddPeople')
                            : context.t('budget.peopleSubtitle'),
                        onTap: () => _push(context, const PeopleScreen()),
                      ),
                    ),
                ],
              );
            },
          ),
          // ── Precious Metals section ───────────────────────────
          const SizedBox(height: 20),
          _GroupHeader(label: 'Precious Metals'),
          const SizedBox(height: 10),
          _PreciousMetalsHubCard(
            metals: metals,
            symbol: symbol,
            onTap: () => _push(context, const PreciousMetalsScreen()),
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
          ];
          return _VisibilitySheet(
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

// ── Precious Metals hub card ───────────────────────────────────────────────────

class _PreciousMetalsHubCard extends StatelessWidget {
  final List<PreciousMetal> metals;
  final String symbol;
  final VoidCallback onTap;

  const _PreciousMetalsHubCard({
    required this.metals,
    required this.symbol,
    required this.onTap,
  });

  Map<MetalType, double> _computeHoldings() {
    final map = <MetalType, double>{};
    for (final m in metals) {
      final cur = map[m.metalType] ?? 0.0;
      map[m.metalType] = m.action == MetalAction.buy
          ? cur + m.weightGrams
          : cur - m.weightGrams;
    }
    return map;
  }

  double _computeTotalValue() {
    double total = 0;
    for (final m in metals) {
      total += m.action == MetalAction.buy ? m.totalAmount : -m.totalAmount;
    }
    return total < 0 ? 0 : total;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final holdings = _computeHoldings();
    final totalValue = _computeTotalValue();
    final hasMetals = metals.isNotEmpty;

    const goldColor = Color(0xFFD4AF37);
    const goldDark = Color(0xFF3A2E00);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.card),
          color: isDark ? const Color(0xFF1A1800) : const Color(0xFFFFFBF0),
          border: Border.all(
            color: goldColor.withValues(alpha: isDark ? 0.18 : 0.22),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Row(
          children: [
            // Left: icon container
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark
                    ? goldColor.withValues(alpha: 0.15)
                    : goldColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Center(
                child: Text(
                  '✦',
                  style: TextStyle(fontSize: 22, color: goldColor),
                ),
              ),
            ),
            const SizedBox(width: 16),
            // Middle: title + breakdown
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        'Precious Metals',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: isDark ? Colors.white : goldDark,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: goldColor.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          'METALS',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: goldColor,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  if (hasMetals) ...[
                    Text(
                      formatMoney(symbol, totalValue),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : goldDark,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      children: MetalType.values
                          .where((t) => (holdings[t] ?? 0) > 0)
                          .map((t) => _MetalChip(
                                metalType: t,
                                grams: holdings[t]!,
                                isDark: isDark,
                              ))
                          .toList(),
                    ),
                  ] else
                    Text(
                      'Track gold, silver & more',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.5)
                            : const Color(0xFF8B7A30),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            // Right: chevron
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: isDark
                  ? Colors.white.withValues(alpha: 0.4)
                  : const Color(0xFFB8961E),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetalChip extends StatelessWidget {
  final MetalType metalType;
  final double grams;
  final bool isDark;

  const _MetalChip({
    required this.metalType,
    required this.grams,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final color = metalType.primaryColor;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.13),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
          width: 0.5,
        ),
      ),
      child: Text(
        '${metalType.label}: ${grams.toStringAsFixed(1)}g',
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
