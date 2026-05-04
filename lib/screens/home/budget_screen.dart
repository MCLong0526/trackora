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
                            fontWeight: FontWeight.w800,
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
          const SizedBox(height: 4),
          LayoutBuilder(
            builder: (context, constraints) {
              final cardWidth = (constraints.maxWidth - 12) / 2;
              final savingTarget = trackedPlans.fold<double>(
                0,
                (s, p) => s + p.targetAmount,
              );
              final budgetProgress =
                  budget > 0
                      ? (discretionarySpent / budget).clamp(0.0, 1.0)
                      : null;
              final savingProgress =
                  savingTarget > 0
                      ? (saved / savingTarget).clamp(0.0, 1.0)
                      : null;
              final budgetUsagePct =
                  budget > 0
                      ? (discretionarySpent / budget * 100).clamp(0, 999).round()
                      : 0;

              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  if (visibleModules.contains('installments'))
                    SizedBox(
                      width: cardWidth,
                      height: 170,
                      child: _ManagementCard(
                        icon: CupertinoIcons.calendar_today,
                        background: AppColors.butter,
                        title: context.t('budget.manageInstallments'),
                        value:
                            activeInstallments.isEmpty
                                ? '—'
                                : formatMoney(symbol, installmentsMonthly),
                        valueSubtext:
                            activeInstallments.isEmpty
                                ? null
                                : context.t('budget.perMonth'),
                        footer:
                            activeInstallments.isEmpty
                                ? context.t('budget.noneActive')
                                : context
                                      .t('budget.activeCount')
                                      .replaceFirst(
                                        '{count}',
                                        '${activeInstallments.length}',
                                      ),
                        onTap: () => _push(context, const InstallmentsScreen()),
                      ),
                    ),
                  if (visibleModules.contains('borrowLending'))
                    SizedBox(
                      width: cardWidth,
                      height: 170,
                      child: _ManagementCard(
                        icon: CupertinoIcons.arrow_up_arrow_down,
                        background: AppColors.sky,
                        title: context.t('tools.borrowLending'),
                        value: formatMoney(symbol, net.abs()),
                        valueColor:
                            net < 0
                                ? AppColors.expense
                                : net > 0
                                ? AppColors.income
                                : null,
                        footer:
                            '${formatMoney(symbol, borrowed)} ↑ · ${formatMoney(symbol, lent)} ↓',
                        onTap: () =>
                            _push(context, const BorrowLendingScreen()),
                      ),
                    ),
                  if (visibleModules.contains('savingPlans'))
                    SizedBox(
                      width: cardWidth,
                      height: 170,
                      child: _ManagementCard(
                        icon: CupertinoIcons.flag_fill,
                        background: AppColors.mint,
                        title: context.t('tools.savingPlans'),
                        value: formatMoney(symbol, saved),
                        progress: savingProgress,
                        footer:
                            savingTarget > 0
                                ? context
                                      .t('budget.savingPlansSummary')
                                      .replaceFirst(
                                        '{amount}',
                                        formatMoney(symbol, savingTarget),
                                      )
                                : context
                                      .t('budget.activeCount')
                                      .replaceFirst(
                                        '{count}',
                                        '${trackedPlans.length}',
                                      ),
                        onTap: () => _push(context, const SavingPlansScreen()),
                      ),
                    ),
                  if (visibleModules.contains('monthlyBudget'))
                    SizedBox(
                      width: cardWidth,
                      height: 170,
                      child: _ManagementCard(
                        icon: CupertinoIcons.creditcard_fill,
                        background: AppColors.lilac,
                        title: context.t('home.budget'),
                        value:
                            budget <= 0
                                ? context.t('budget.monthlyNotSet')
                                : formatMoney(symbol, discretionarySpent),
                        progress: budgetProgress,
                        progressColor:
                            budget > 0 && discretionarySpent > budget
                                ? AppColors.expense
                                : null,
                        footer:
                            budget <= 0
                                ? context.t('budget.setAction')
                                : context
                                      .t('budget.percentUsed')
                                      .replaceFirst(
                                        '{percent}',
                                        '$budgetUsagePct',
                                      ),
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
                ],
              );
            },
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
              fontWeight: FontWeight.w900,
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
          fontWeight: FontWeight.w800,
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

// ── Management Grid Card ───────────────────────────────────────

class _ManagementCard extends StatelessWidget {
  final IconData icon;
  final Color background;
  final String title;
  final String value;
  final String? valueSubtext;
  final Color? valueColor;
  final double? progress;
  final Color? progressColor;
  final String footer;
  final VoidCallback onTap;

  const _ManagementCard({
    required this.icon,
    required this.background,
    required this.title,
    required this.value,
    this.valueSubtext,
    this.valueColor,
    this.progress,
    this.progressColor,
    required this.footer,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: background.withValues(alpha: 0.55),
            blurRadius: 18,
            spreadRadius: -4,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: SectionCard(
        color: background,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon + chevron header
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 16, color: AppColors.ink),
                ),
                const Spacer(),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 13,
                  color: AppColors.inkSoft,
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Title
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppColors.inkSoft,
              ),
            ),
            const SizedBox(height: 4),
            // Primary value
            FittedBox(
              alignment: Alignment.centerLeft,
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: valueColor ?? AppColors.ink,
                ),
              ),
            ),
            if (valueSubtext != null) ...[
              const SizedBox(height: 1),
              Text(
                valueSubtext!,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
            if (progress != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress!,
                  minHeight: 5,
                  backgroundColor: Colors.white.withValues(alpha: 0.55),
                  valueColor: AlwaysStoppedAnimation(
                    progressColor ?? AppColors.ink,
                  ),
                ),
              ),
            ],
            const Spacer(),
            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.42),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                footer,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

