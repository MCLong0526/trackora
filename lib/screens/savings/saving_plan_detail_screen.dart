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
                const SizedBox(height: 20),
                const Text(
                  'PLAN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF8E8E93),
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 8),
                _DetailsCard(plan: plan, symbol: symbol),
                const SizedBox(height: 20),
                if (plan.type == SavingPlanType.daysChallenge ||
                    plan.type == SavingPlanType.weeksChallenge)
                  _SlotGrid(plan: plan, symbol: symbol),
                if (plan.type != SavingPlanType.daysChallenge &&
                    plan.type != SavingPlanType.weeksChallenge)
                  _ContributionHistory(plan: plan, symbol: symbol),
                const SizedBox(height: 24),
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

    final raw = formatMoney(symbol, plan.currentAmount);
    final dotIdx = raw.indexOf('.');
    final mainPart = dotIdx >= 0 ? raw.substring(0, dotIdx) : raw;
    final decPart = dotIdx >= 0 ? raw.substring(dotIdx) : '';
    final pct = (plan.progress * 100).toStringAsFixed(0);
    final remaining = formatMoney(symbol, plan.remaining);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${plan.name} ${_typeLabel(context, plan.type)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: brand.inkSoft,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _typeLabel(context, plan.type),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                mainPart,
                style: TextStyle(
                  fontSize: 36,
                  fontWeight: FontWeight.w900,
                  color: brand.ink,
                  letterSpacing: -1,
                ),
              ),
              if (decPart.isNotEmpty)
                Text(
                  decPart,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: brand.inkSoft,
                  ),
                ),
            ],
          ),
          Text(
            '${context.t('sp.ofTarget')} ${formatMoney(symbol, plan.targetAmount)}',
            style: TextStyle(
              fontSize: 13,
              color: brand.inkSoft,
              fontWeight: FontWeight.w500,
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
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$pct% saved',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: brand.inkSoft,
                ),
              ),
              const Spacer(),
              Text(
                '$remaining to go',
                style: TextStyle(
                  fontSize: 12,
                  color: brand.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _typeLabel(BuildContext context, SavingPlanType t) => switch (t) {
        SavingPlanType.fixed => context.t('sp.typeFixed').toUpperCase(),
        SavingPlanType.flexible => context.t('sp.typeFlexible').toUpperCase(),
        SavingPlanType.daysChallenge => context.t('sp.typeDays').toUpperCase(),
        SavingPlanType.weeksChallenge =>
          context.t('sp.typeWeeks').toUpperCase(),
      };
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
      if (plan.totalDays != null) (context.t('sp.fieldDays'), '${plan.totalDays}'),
      if (plan.totalWeeks != null) (context.t('sp.fieldWeeks'), '${plan.totalWeeks}'),
      if (plan.note.isNotEmpty) (context.t('sp.fieldNote'), plan.note),
    ];
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Text(
                    rows[i].$1,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: brand.ink,
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Text(
                      rows[i].$2,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 15,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (i < rows.length - 1)
              Divider(
                height: 1,
                color: brand.divider,
                indent: 16,
                endIndent: 16,
              ),
          ],
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
    // Current slot = next to be deposited
    final currentSlot = plan.slotsCompleted + 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              context.t('sp.depositGrid').toUpperCase(),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12,
                color: Color(0xFF8E8E93),
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            Text(
              '${plan.slotsCompleted} / $total',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6366F1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: total,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 5,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 0.88,
            ),
            itemBuilder: (_, idx) {
              final slot = idx + 1;
              final done = filled.contains(slot);
              final isCurrent =
                  slot == currentSlot && plan.status == SavingPlanStatus.active;
              return _SlotCell(
                plan: plan,
                slot: slot,
                amount: perSlot,
                symbol: symbol,
                done: done,
                isDays: isDays,
                isCurrent: isCurrent,
              );
            },
          ),
        ),
      ],
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
  final bool isCurrent;
  const _SlotCell({
    required this.plan,
    required this.slot,
    required this.amount,
    required this.symbol,
    required this.done,
    required this.isDays,
    this.isCurrent = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final dateLabel = _slotDateShort(context);

    Color bgColor;
    Border? border;
    Color numColor;
    if (done) {
      bgColor = AppColors.mint;
      numColor = AppColors.income;
    } else if (isCurrent) {
      bgColor = brand.surface;
      border = Border.all(
        color: const Color(0xFF6366F1),
        width: 1.5,
        strokeAlign: BorderSide.strokeAlignInside,
      );
      numColor = const Color(0xFF6366F1);
    } else {
      bgColor = brand.background;
      numColor = brand.inkSoft;
    }

    return GestureDetector(
      onTap: () => _toggle(ref),
      child: Container(
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: border,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$slot',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: numColor,
              ),
            ),
            const SizedBox(height: 2),
            if (done)
              Icon(CupertinoIcons.checkmark_alt, size: 12, color: AppColors.income)
            else if (isCurrent)
              Text(
                'NOW',
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                  color: numColor,
                ),
              )
            else
              Text(
                dateLabel,
                style: TextStyle(
                  fontSize: 9,
                  color: brand.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _slotDateShort(BuildContext context) {
    if (isDays) {
      final d = plan.startDate.add(Duration(days: slot - 1));
      return DateFormat('MMM').format(d);
    }
    final d = plan.startDate.add(Duration(days: (slot - 1) * 7));
    return DateFormat('MMM').format(d);
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
    final isActive = plan.status == SavingPlanStatus.active;
    final isCancelled = plan.status == SavingPlanStatus.cancelled;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _OutlineBtn(
                label: context.t('common.edit'),
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => AddEditSavingPlanScreen(plan: plan),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FilledBtn(
                label: isActive
                    ? context.t('inst.markCompleted')
                    : isCancelled
                    ? context.t('inst.reactivate')
                    : 'Completed',
                color: const Color(0xFF6366F1),
                textColor: Colors.white,
                onTap: isActive
                    ? () async {
                        final user = ref.read(authStateProvider).valueOrNull;
                        if (user == null) return;
                        await ref
                            .read(savingPlanServiceProvider)
                            .markCompleted(user.uid, plan);
                      }
                    : isCancelled
                    ? () async {
                        final user = ref.read(authStateProvider).valueOrNull;
                        if (user == null) return;
                        await ref
                            .read(savingPlanServiceProvider)
                            .setCancelled(user.uid, plan, false);
                      }
                    : () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            if (!isCancelled && plan.status != SavingPlanStatus.completed)
              Expanded(
                child: _FilledBtn(
                  label: 'Cancel plan',
                  color: const Color(0xFFFEE2E2),
                  textColor: AppColors.expense,
                  onTap: () async {
                    final user = ref.read(authStateProvider).valueOrNull;
                    if (user == null) return;
                    await ref
                        .read(savingPlanServiceProvider)
                        .setCancelled(user.uid, plan, true);
                  },
                ),
              )
            else
              const Expanded(child: SizedBox.shrink()),
            const SizedBox(width: 12),
            Expanded(
              child: _FilledBtn(
                label: context.t('common.delete'),
                color: const Color(0xFFFEE2E2),
                textColor: AppColors.expense,
                onTap: () => _confirmDelete(context, ref),
              ),
            ),
          ],
        ),
      ],
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

// ── Button helpers ────────────────────────────────────────────

class _OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: brand.divider, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: brand.ink,
          ),
        ),
      ),
    );
  }
}

class _FilledBtn extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;
  final VoidCallback onTap;
  const _FilledBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? foregroundOn(color);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
    );
  }
}
