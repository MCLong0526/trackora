import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/saving_plan.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/fading_edge_list.dart';
import 'add_edit_saving_plan_screen.dart';
import 'saving_plans_screen.dart' show spAccent, spTint;

class SavingPlanDetailScreen extends ConsumerWidget {
  final String planId;
  const SavingPlanDetailScreen({super.key, required this.planId});

  static final _missingPlan = SavingPlan(
    id: '',
    name: '',
    type: SavingPlanType.flexible,
    targetAmount: 0,
    startDate: DateTime.fromMillisecondsSinceEpoch(0),
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );

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
        actions: [
          if (async.valueOrNull != null)
            Builder(
              builder: (ctx) {
                final plan = async.valueOrNull!.firstWhere(
                  (p) => p.id == planId,
                  orElse: () => _missingPlan,
                );
                if (identical(plan, _missingPlan)) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(CupertinoIcons.ellipsis_circle, size: 22),
                  onPressed: () => _showActionsSheet(ctx, ref, plan),
                );
              },
            ),
        ],
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
                Text(
                  context.t('sp.detailTitle').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
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
              ],
            );
          },
        ),
      ),
    );
  }

  void _showActionsSheet(BuildContext context, WidgetRef ref, SavingPlan plan) {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final isActive = plan.status == SavingPlanStatus.active;
    final isCancelled = plan.status == SavingPlanStatus.cancelled;

    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => AddEditSavingPlanScreen(plan: plan),
                ),
              );
            },
            child: Text(context.t('sp.edit')),
          ),
          if (isActive)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(savingPlanServiceProvider).markCompleted(user.uid, plan);
                  if (context.mounted) {
                    AppToast.show(context, context.t('sp.planCompleted'),
                        type: AppToastType.success);
                    Navigator.pop(context);
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(context, context.t('sp.failComplete'),
                        type: AppToastType.error);
                  }
                }
              },
              child: Text(context.t('inst.markCompleted')),
            ),
          if (isCancelled)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(savingPlanServiceProvider).setCancelled(user.uid, plan, false);
                  if (context.mounted) {
                    AppToast.show(context, context.t('sp.planReactivated'),
                        type: AppToastType.success);
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(context, context.t('sp.failReactivate'),
                        type: AppToastType.error);
                  }
                }
              },
              child: Text(context.t('inst.reactivate')),
            ),
          if (!isCancelled && plan.status != SavingPlanStatus.completed)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref.read(savingPlanServiceProvider).setCancelled(user.uid, plan, true);
                  if (context.mounted) {
                    AppToast.show(context, context.t('sp.planCancelled'),
                        type: AppToastType.success);
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(context, context.t('sp.failCancel'),
                        type: AppToastType.error);
                  }
                }
              },
              child: Text(context.t('sp.cancelPlan')),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              final ok = await showCupertinoDialog<bool>(
                context: context,
                builder: (dctx) => CupertinoAlertDialog(
                  title: Text(context.t('sp.deleteTitle')),
                  content: Text(context.t('sp.deleteMessage')),
                  actions: [
                    CupertinoDialogAction(
                      onPressed: () => Navigator.pop(dctx, false),
                      child: Text(context.t('common.cancel')),
                    ),
                    CupertinoDialogAction(
                      isDestructiveAction: true,
                      onPressed: () => Navigator.pop(dctx, true),
                      child: Text(context.t('common.delete')),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                try {
                  await ref.read(savingPlanServiceProvider).delete(user.uid, plan.id);
                  if (context.mounted) {
                    AppToast.show(context, context.t('sp.planDeleted'),
                        type: AppToastType.success);
                    Navigator.pop(context);
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(context, context.t('sp.failDelete'),
                        type: AppToastType.error);
                  }
                }
              }
            },
            child: Text(context.t('common.delete')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(context.t('common.cancel')),
        ),
      ),
    );
  }
}

Future<void> _showAddContributionSheet(
  BuildContext context,
  WidgetRef ref,
  SavingPlan plan,
) async {
  final user = ref.read(authStateProvider).valueOrNull;
  if (user == null) return;
  final symbol = ref.read(currencySymbolProvider).valueOrNull ?? '\$';
  // The amount still needed to reach the target. A contribution can never
  // exceed this (e.g. only 100 left ⇒ the max contribution is 100).
  final remaining = plan.remaining > 0 ? plan.remaining : 0.0;
  final defaultContribution = plan.contributionAmount ?? 0;
  // Pre-fill with the usual per-period contribution, but capped to whatever
  // is left so the field never suggests overshooting the goal.
  final prefill = defaultContribution > 0 && defaultContribution <= remaining
      ? defaultContribution
      : remaining;
  final ctrl = TextEditingController(
    text: prefill > 0 ? prefill.toStringAsFixed(2) : '',
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
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: false,
              textInputAction: TextInputAction.done,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                prefixText: '$symbol  ',
                helperText: remaining > 0
                    ? '${formatMoney(symbol, remaining)} left to reach goal'
                    : null,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text);
                if (v == null) {
                  Navigator.pop(ctx);
                  return;
                }
                // Never let a contribution exceed the remaining amount.
                final capped =
                    remaining > 0 && v > remaining ? remaining : v;
                Navigator.pop(ctx, capped);
              },
              child: Text(context.t('common.save')),
            ),
          ],
        ),
      );
    },
  );
  if (amount == null || amount <= 0) return;
  try {
    await ref.read(savingPlanServiceProvider).addContribution(
          user.uid,
          plan,
          SavingContribution(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            amount: amount,
            date: DateTime.now(),
          ),
        );
    if (context.mounted) {
      AppToast.show(context, context.t('sp.contribAdded'),
            type: AppToastType.success);
    }
  } catch (_) {
    if (context.mounted) {
      AppToast.show(context, context.t('sp.failAddContrib'),
            type: AppToastType.error);
    }
  }
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
                    fontWeight: FontWeight.w600,
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
                  fontWeight: FontWeight.w700,
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
                fontWeight: FontWeight.w600,
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
                color: AppActionBlue.color,
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
        color: AppActionBlue.color,
        width: 1.5,
        strokeAlign: BorderSide.strokeAlignInside,
      );
      numColor = AppActionBlue.color;
    } else {
      bgColor = brand.background;
      numColor = brand.inkSoft;
    }

    return GestureDetector(
      onTap: () => _toggle(ref, context),
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
                fontWeight: FontWeight.w600,
                color: numColor,
              ),
            ),
            const SizedBox(height: 2),
            if (done)
              Icon(CupertinoIcons.checkmark_alt, size: 12, color: AppColors.income)
            else if (isCurrent)
              Text(
                context.t('sp.now'),
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w600,
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

  Future<void> _toggle(WidgetRef ref, BuildContext context) async {
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
        try {
          await svc.removeContribution(user.uid, plan, targetId);
          if (context.mounted) {
            AppToast.show(context, context.t('sp.contribRemoved'),
            type: AppToastType.success);
          }
        } catch (_) {
          if (context.mounted) {
            AppToast.show(context, context.t('sp.failRemoveContrib'),
            type: AppToastType.error);
          }
        }
      }
    } else {
      try {
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
        if (context.mounted) {
          AppToast.show(context, context.t('sp.contribAdded'),
            type: AppToastType.success);
        }
      } catch (_) {
        if (context.mounted) {
          AppToast.show(context, context.t('sp.failAddContrib'),
            type: AppToastType.error);
        }
      }
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
    final canAdd = plan.status == SavingPlanStatus.active;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.t('sp.history'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (canAdd)
                GestureDetector(
                  onTap: () => _showAddContributionSheet(context, ref, plan),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppActionBlue.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.plus, size: 12, color: AppActionBlue.color),
                        const SizedBox(width: 4),
                        Text(
                          context.t('sp.addContribution'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppActionBlue.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
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
            _buildContributionList(context, ref, brand),
        ],
      ),
    );
  }

  Widget _buildContributionList(
    BuildContext context,
    WidgetRef ref,
    BrandColors brand,
  ) {
    // Latest contribution first.
    final items = [...plan.contributions]
      ..sort((a, b) => b.date.compareTo(a.date));
    final rows = [
      for (final c in items) _contributionRow(context, ref, brand, c),
    ];
    // Short lists render inline; once there are many, cap the height and let
    // only this section scroll so the page doesn't stretch endlessly.
    if (rows.length <= 5) {
      return Column(children: rows);
    }
    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 320),
      child: FadingEdgeList(
        fadeColor: brand.surface,
        topHeight: 16,
        bottomHeight: 24,
        child: ListView(
          padding: EdgeInsets.zero,
          children: rows,
        ),
      ),
    );
  }

  Widget _contributionRow(
    BuildContext context,
    WidgetRef ref,
    BrandColors brand,
    SavingContribution c,
  ) {
    return Padding(
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
              try {
                await ref
                    .read(savingPlanServiceProvider)
                    .removeContribution(user.uid, plan, c.id);
                if (context.mounted) {
                  AppToast.show(context, context.t('sp.contribRemoved'),
            type: AppToastType.success);
                }
              } catch (_) {
                if (context.mounted) {
                  AppToast.show(context, context.t('sp.failRemoveContrib'),
            type: AppToastType.error);
                }
              }
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
    );
  }
}

