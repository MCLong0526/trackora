import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/saving_plan.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import 'add_edit_saving_plan_screen.dart';
import 'saving_plans_screen.dart' show spAccent, spTint;

/// Saving plan detail screen.
///
/// Shows progress hero, contribution history, and (for challenge plans
/// only) a slot grid where each cell represents day N or week N. Tap a
/// slot to deposit / un-deposit.
class SavingPlanDetailScreen extends ConsumerWidget {
  final String planId;
  const SavingPlanDetailScreen({super.key, required this.planId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final async = ref.watch(savingPlansProvider);
    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.t('sp.detailTitle')),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('${context.t('common.error')}: $e')),
          data: (plans) {
            final plan = plans.firstWhere(
              (p) => p.id == planId,
              orElse: () => _missingPlan,
            );
            if (identical(plan, _missingPlan)) {
              return Center(child: Text(context.t('sp.planGone')));
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _Hero(plan: plan, symbol: symbol),
                const SizedBox(height: 14),
                _DetailsCard(plan: plan, symbol: symbol),
                const SizedBox(height: 14),
                if (plan.type == SavingPlanType.daysChallenge ||
                    plan.type == SavingPlanType.weeksChallenge)
                  _SlotGrid(plan: plan, symbol: symbol),
                if (plan.type != SavingPlanType.daysChallenge &&
                    plan.type != SavingPlanType.weeksChallenge)
                  _ContributionHistory(plan: plan, symbol: symbol),
                const SizedBox(height: 16),
                _ActionRow(plan: plan, symbol: symbol),
              ],
            );
          },
        ),
      ),
      floatingActionButton: ref.watch(savingPlansProvider).valueOrNull == null
          ? null
          : Builder(
              builder: (ctx) {
                final plans = ref.watch(savingPlansProvider).value!;
                final plan = plans.firstWhere(
                  (p) => p.id == planId,
                  orElse: () => _missingPlan,
                );
                if (identical(plan, _missingPlan) ||
                    plan.status != SavingPlanStatus.active ||
                    plan.type == SavingPlanType.daysChallenge ||
                    plan.type == SavingPlanType.weeksChallenge) {
                  return const SizedBox.shrink();
                }
                return FloatingActionButton.extended(
                  onPressed: () => _showAddContributionSheet(ctx, ref, plan),
                  icon: const Icon(CupertinoIcons.plus),
                  label: Text(context.t('sp.addContribution')),
                );
              },
            ),
    );
  }

  static final _missingPlan = SavingPlan(
    id: '',
    name: '',
    type: SavingPlanType.flexible,
    targetAmount: 0,
    startDate: DateTime.fromMillisecondsSinceEpoch(0),
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

Future<void> _showAddContributionSheet(
  BuildContext context,
  WidgetRef ref,
  SavingPlan plan,
) async {
  final user = ref.read(authStateProvider).valueOrNull;
  if (user == null) return;
  final symbol = ref.read(currencySymbolProvider).valueOrNull ?? '\$';
  final ctrl = TextEditingController(
    text: (plan.contributionAmount ?? 0) > 0
        ? plan.contributionAmount!.toStringAsFixed(2)
        : '',
  );
  final amount = await showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.brand.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) {
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
              context.t('sp.addContribution'),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(prefixText: '$symbol  '),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text);
                Navigator.pop(ctx, v);
              },
              child: Text(context.t('common.save')),
            ),
          ],
        ),
      );
    },
  );
  if (amount == null || amount <= 0) return;
  await ref.read(savingPlanServiceProvider).addContribution(
        user.uid,
        plan,
        SavingContribution(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          amount: amount,
          date: DateTime.now(),
        ),
      );
}

class _Hero extends StatelessWidget {
  final SavingPlan plan;
  final String symbol;
  const _Hero({required this.plan, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final accent = spAccent(plan.type);
    final tint = spTint(plan.type);
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [tint, brand.surface],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            plan.name,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _typeLabel(context, plan.type),
            style: TextStyle(
              fontSize: 11,
              color: brand.inkSoft,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            formatMoney(symbol, plan.currentAmount),
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          Text(
            '${context.t('sp.ofTarget')} ${formatMoney(symbol, plan.targetAmount)}',
            style: TextStyle(
              fontSize: 12,
              color: brand.inkSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: plan.progress,
              minHeight: 6,
              backgroundColor: brand.divider,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(
                '${(plan.progress * 100).toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              Text(
                context
                    .t('sp.remainingLine')
                    .replaceFirst('{amount}', formatMoney(symbol, plan.remaining)),
                style: TextStyle(
                  fontSize: 12,
                  color: brand.inkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _typeLabel(BuildContext context, SavingPlanType t) {
    switch (t) {
      case SavingPlanType.fixed:
        return context.t('sp.typeFixed').toUpperCase();
      case SavingPlanType.flexible:
        return context.t('sp.typeFlexible').toUpperCase();
      case SavingPlanType.daysChallenge:
        return context.t('sp.typeDays').toUpperCase();
      case SavingPlanType.weeksChallenge:
        return context.t('sp.typeWeeks').toUpperCase();
    }
  }
}

class _DetailsCard extends StatelessWidget {
  final SavingPlan plan;
  final String symbol;
  const _DetailsCard({required this.plan, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final rows = <(String, String)>[
      (
        context.t('sp.fieldStartDate'),
        DateFormat('MMM d, yyyy').format(plan.startDate),
      ),
      if (plan.endDate != null)
        (
          context.t('sp.fieldEndDate'),
          DateFormat('MMM d, yyyy').format(plan.endDate!),
        ),
      if (plan.contributionAmount != null)
        (
          context.t('sp.fieldContribution'),
          formatMoney(symbol, plan.contributionAmount!),
        ),
      if (plan.totalDays != null)
        (
          context.t('sp.fieldDays'),
          '${plan.totalDays}',
        ),
      if (plan.totalWeeks != null)
        (
          context.t('sp.fieldWeeks'),
          '${plan.totalWeeks}',
        ),
      if (plan.note.isNotEmpty) (context.t('sp.fieldNote'), plan.note),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 12,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontWeight: FontWeight.w700),
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

class _SlotGrid extends ConsumerWidget {
  final SavingPlan plan;
  final String symbol;
  const _SlotGrid({required this.plan, required this.symbol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final isDays = plan.type == SavingPlanType.daysChallenge;
    final total = (isDays ? plan.totalDays : plan.totalWeeks) ?? 0;
    final perSlot = plan.contributionAmount ?? 0;
    final filled = <int>{};
    for (final c in plan.contributions) {
      if (c.slotIndex != null) filled.add(c.slotIndex!);
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('sp.depositGrid'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: total,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 8,
              crossAxisSpacing: 8,
              childAspectRatio: 2.6,
            ),
            itemBuilder: (_, idx) {
              final slot = idx + 1;
              final done = filled.contains(slot);
              return _SlotCell(
                plan: plan,
                slot: slot,
                amount: perSlot,
                symbol: symbol,
                done: done,
                isDays: isDays,
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SlotCell extends ConsumerWidget {
  final SavingPlan plan;
  final int slot;
  final double amount;
  final String symbol;
  final bool done;
  final bool isDays;
  const _SlotCell({
    required this.plan,
    required this.slot,
    required this.amount,
    required this.symbol,
    required this.done,
    required this.isDays,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final dateLabel = _slotDate(context);
    return GestureDetector(
      onTap: () => _toggle(ref),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: done ? AppColors.mint : brand.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: done ? AppColors.income : brand.divider,
            width: done ? 1.4 : 1,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    formatMoney(symbol, amount),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    dateLabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: brand.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              done
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              size: 22,
              color: done ? AppColors.income : brand.inkSoft,
            ),
          ],
        ),
      ),
    );
  }

  String _slotDate(BuildContext context) {
    if (isDays) {
      final d = plan.startDate.add(Duration(days: slot - 1));
      return DateFormat.MMMd().format(d);
    }
    final d = plan.startDate.add(Duration(days: (slot - 1) * 7));
    return '${context.t('sp.weekShort')} $slot · ${DateFormat.MMMd().format(d)}';
  }

  Future<void> _toggle(WidgetRef ref) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final svc = ref.read(savingPlanServiceProvider);
    if (done) {
      // remove the matching contribution
      // Find the matching contribution by slot. Iterate explicitly so
      // we can return null when nothing matches (firstWhere with a const
      // sentinel doesn't compose with a non-const DateTime).
      String? targetId;
      for (final c in plan.contributions) {
        if (c.slotIndex == slot) {
          targetId = c.id;
          break;
        }
      }
      if (targetId != null) {
        await svc.removeContribution(user.uid, plan, targetId);
      }
    } else {
      await svc.addContribution(
        user.uid,
        plan,
        SavingContribution(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          amount: amount,
          date: DateTime.now(),
          slotIndex: slot,
        ),
      );
    }
  }
}

class _ContributionHistory extends ConsumerWidget {
  final SavingPlan plan;
  final String symbol;
  const _ContributionHistory({required this.plan, required this.symbol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('sp.history'),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 8),
          if (plan.contributions.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                context.t('sp.noContributions'),
                style: TextStyle(color: brand.inkSoft, fontSize: 13),
              ),
            )
          else
            for (final c in plan.contributions.reversed)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.mint,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        CupertinoIcons.arrow_down,
                        size: 14,
                        color: AppColors.income,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            formatMoney(symbol, c.amount),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            DateFormat('MMM d, yyyy').format(c.date),
                            style: TextStyle(
                              fontSize: 11,
                              color: brand.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () async {
                        final user = ref.read(authStateProvider).valueOrNull;
                        if (user == null) return;
                        await ref
                            .read(savingPlanServiceProvider)
                            .removeContribution(user.uid, plan, c.id);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          CupertinoIcons.minus_circle,
                          size: 18,
                          color: brand.inkSoft,
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
}

class _ActionRow extends ConsumerWidget {
  final SavingPlan plan;
  final String symbol;
  const _ActionRow({required this.plan, required this.symbol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _btn(
          context,
          icon: CupertinoIcons.pencil,
          label: context.t('common.edit'),
          onTap: () => Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (_) => AddEditSavingPlanScreen(plan: plan),
            ),
          ),
        ),
        if (plan.status == SavingPlanStatus.active)
          _btn(
            context,
            icon: CupertinoIcons.check_mark_circled,
            label: context.t('inst.markCompleted'),
            onTap: () async {
              final user = ref.read(authStateProvider).valueOrNull;
              if (user == null) return;
              await ref
                  .read(savingPlanServiceProvider)
                  .markCompleted(user.uid, plan);
            },
          ),
        if (plan.status == SavingPlanStatus.cancelled)
          _btn(
            context,
            icon: CupertinoIcons.refresh,
            label: context.t('inst.reactivate'),
            onTap: () async {
              final user = ref.read(authStateProvider).valueOrNull;
              if (user == null) return;
              await ref
                  .read(savingPlanServiceProvider)
                  .setCancelled(user.uid, plan, false);
            },
          )
        else if (plan.status != SavingPlanStatus.completed)
          _btn(
            context,
            icon: CupertinoIcons.xmark_circle,
            label: context.t('common.cancel'),
            destructive: true,
            onTap: () async {
              final user = ref.read(authStateProvider).valueOrNull;
              if (user == null) return;
              await ref
                  .read(savingPlanServiceProvider)
                  .setCancelled(user.uid, plan, true);
            },
          ),
        _btn(
          context,
          icon: CupertinoIcons.trash,
          label: context.t('common.delete'),
          destructive: true,
          onTap: () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  Widget _btn(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final brand = context.brand;
    final fg = destructive ? AppColors.expense : brand.ink;
    final bg = destructive
        ? AppColors.blush.withValues(alpha: 0.55)
        : brand.surface;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('sp.deleteTitle')),
        content: Text(context.t('sp.deleteMessage')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('common.cancel')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('common.delete')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(savingPlanServiceProvider).delete(user.uid, plan.id);
      if (context.mounted) Navigator.pop(context);
    }
  }
}
