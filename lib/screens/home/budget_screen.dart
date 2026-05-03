import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/borrow_lending.dart';
import '../../models/expense.dart';
import '../../models/installment.dart';
import '../../models/saving_plan.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../borrow_lending/borrow_lending_screen.dart';
import '../installments/installments_screen.dart';
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
    await ref.read(expenseRepositoryProvider).setMonthlyBudget(userId, result);
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
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final month = ref.watch(selectedMonthProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final visibleModules = ref.watch(moneyHubVisibilityProvider);

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

    final remaining = budget - discretionarySpent;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
        children: [
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
                  const SizedBox(width: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      DateFormat('MMM yyyy').format(month),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: brand.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              context.t('money.subtitle'),
              style: TextStyle(color: brand.inkSoft, fontSize: 13),
            ),
          ),
          const SizedBox(height: 22),
          _GroupHeader(label: context.t('budget.management')),
          for (final module in [
            if (visibleModules.contains('installments'))
              _MoneyToolCard(
                icon: CupertinoIcons.calendar_today,
                iconColor: AppColors.butter,
                title: context.t('budget.manageInstallments'),
                description: context.t('budget.manageInstallmentsDesc'),
                summary: activeInstallments.isEmpty
                    ? context.t('budget.noneActive')
                    : context
                          .t('budget.installmentsSummary')
                          .replaceFirst(
                            '{amount}',
                            formatMoney(symbol, installmentsMonthly),
                          )
                          .replaceFirst(
                            '{count}',
                            '${activeInstallments.length}',
                          ),
                onTap: () => _push(context, const InstallmentsScreen()),
              ),
            if (visibleModules.contains('borrowLending'))
              _MoneyToolCard(
                icon: CupertinoIcons.arrow_up_arrow_down,
                iconColor: AppColors.lilac,
                title: context.t('tools.borrowLending'),
                description: context.t('budget.borrowLendingDesc'),
                summary: context
                    .t('budget.borrowNetSummary')
                    .replaceFirst(
                      '{amount}',
                      formatMoney(symbol, net, forceSign: net > 0),
                    ),
                summaryColor: net < 0 ? AppColors.expense : AppColors.income,
                onTap: () => _push(context, const BorrowLendingScreen()),
              ),
            if (visibleModules.contains('savingPlans'))
              _MoneyToolCard(
                icon: CupertinoIcons.flag_fill,
                iconColor: AppColors.mint,
                title: context.t('tools.savingPlans'),
                description: context.t('budget.savingPlansDesc'),
                summary: context
                    .t('budget.savingPlansSummary')
                    .replaceFirst('{amount}', formatMoney(symbol, saved)),
                summaryColor: AppColors.income,
                onTap: () => _push(context, const SavingPlansScreen()),
              ),
            if (visibleModules.contains('monthlyBudget'))
              _MoneyToolCard(
                icon: CupertinoIcons.creditcard_fill,
                iconColor: AppColors.sky,
                title: context.t('home.budget'),
                description: context.t('budget.monthlyBudgetDesc'),
                summary: _budgetSummary(
                  context,
                  symbol: symbol,
                  budget: budget,
                  remaining: remaining,
                ),
                summaryColor: budget <= 0
                    ? brand.inkSoft
                    : remaining < 0
                    ? AppColors.expense
                    : AppColors.income,
                onTap: () => showMonthlyBudgetEditor(
                  context,
                  ref,
                  budget,
                  symbol,
                  user?.uid,
                ),
              ),
          ]) ...[module, const SizedBox(height: 12)],
        ],
      ),
    );
  }

  static void _push(BuildContext context, Widget screen) {
    HapticFeedback.selectionClick();
    Navigator.push(context, CupertinoPageRoute(builder: (_) => screen));
  }

  String _budgetSummary(
    BuildContext context, {
    required String symbol,
    required double budget,
    required double remaining,
  }) {
    if (budget <= 0) return context.t('budget.monthlyNotSet');
    final key = remaining < 0
        ? 'budget.monthlyOver'
        : 'budget.monthlyRemaining';
    return context
        .t(key)
        .replaceFirst('{amount}', formatMoney(symbol, remaining.abs()));
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
          fontWeight: FontWeight.w800,
          color: brand.inkSoft,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _MoneyToolCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final String summary;
  final Color? summaryColor;
  final VoidCallback onTap;

  const _MoneyToolCard({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    required this.summary,
    this.summaryColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(16, 16, 14, 16),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, size: 20, color: AppColors.ink),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: brand.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: brand.inkSoft,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  summary,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: summaryColor ?? brand.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(CupertinoIcons.chevron_right, size: 16, color: brand.inkSoft),
        ],
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
