import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/saving_plan.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'add_edit_saving_plan_screen.dart';
import 'saving_plan_detail_screen.dart';

class SavingPlansScreen extends ConsumerStatefulWidget {
  const SavingPlansScreen({super.key});

  @override
  ConsumerState<SavingPlansScreen> createState() => _SavingPlansScreenState();
}

enum _Filter { all, active, completed, cancelled }

class _SavingPlansScreenState extends ConsumerState<SavingPlansScreen> {
  _Filter _filter = _Filter.all;

  bool _matches(SavingPlan p) => switch (_filter) {
        _Filter.all => true,
        _Filter.active => p.status == SavingPlanStatus.active,
        _Filter.completed => p.status == SavingPlanStatus.completed,
        _Filter.cancelled => p.status == SavingPlanStatus.cancelled,
      };

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final async = ref.watch(savingPlansProvider);
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.t('sp.title')),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.add),
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => const AddEditSavingPlanScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) =>
              Center(child: Text('${context.t('common.error')}: $e')),
          data: (plans) {
            final filtered = plans.where(_matches).toList();
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _Summary(plans: plans, symbol: symbol),
                const SizedBox(height: 14),
                _FilterSegment(
                  selected: _filter,
                  onSelected: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 18),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, anim) => FadeTransition(
                    opacity: anim,
                    child: child,
                  ),
                  child: plans.isEmpty
                      ? _EmptyState(
                          onAdd: () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              builder: (_) => const AddEditSavingPlanScreen(),
                            ),
                          ),
                        )
                      : Column(
                          key: ValueKey(_filter),
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(bottom: 10),
                              child: Text(
                                'PLANS',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF8E8E93),
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ),
                            Container(
                              decoration: BoxDecoration(
                                color: context.brand.surface,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(20),
                                child: Column(
                                  children: [
                                    for (int i = 0; i < filtered.length; i++) ...[
                                      _SavingPlanSwipeActions(
                                        plan: filtered[i],
                                        symbol: symbol,
                                        userId: user?.uid,
                                        child: _PlanRow(
                                          plan: filtered[i],
                                          symbol: symbol,
                                        ),
                                      ),
                                      if (i < filtered.length - 1)
                                        Divider(
                                          height: 1,
                                          color: context.brand.divider,
                                          indent: 16,
                                          endIndent: 0,
                                        ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Summary card ──────────────────────────────────────────────

class _Summary extends StatelessWidget {
  final List<SavingPlan> plans;
  final String symbol;
  const _Summary({required this.plans, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = plans.where((p) => p.status == SavingPlanStatus.active).toList();
    final completed =
        plans.where((p) => p.status == SavingPlanStatus.completed).length;
    final saved = active.fold<double>(0, (s, p) => s + p.currentAmount);
    final target = active.fold<double>(0, (s, p) => s + p.targetAmount);
    final progress = target > 0 ? (saved / target).clamp(0.0, 1.0) : 0.0;

    // This week contributions
    final now = DateTime.now();
    final weekAgo = now.subtract(const Duration(days: 7));
    double thisWeek = 0;
    for (final p in active) {
      for (final c in p.contributions) {
        if (c.date.isAfter(weekAgo)) thisWeek += c.amount;
      }
    }

    // Split amount
    final raw = formatMoney(symbol, saved);
    final dotIdx = raw.indexOf('.');
    final mainPart = dotIdx >= 0 ? raw.substring(0, dotIdx) : raw;
    final decPart = dotIdx >= 0 ? raw.substring(dotIdx) : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
        ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('sp.summaryTitle').toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: brand.inkSoft,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                mainPart,
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                  letterSpacing: -1,
                ),
              ),
              if (decPart.isNotEmpty)
                Text(
                  decPart,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: brand.inkSoft,
                  ),
                ),
            ],
          ),
          Text(
            '${context.t('sp.ofTarget')} ${formatMoney(symbol, target)} across ${active.length} plans',
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
              value: progress,
              minHeight: 5,
              backgroundColor: brand.divider,
              valueColor: const AlwaysStoppedAnimation(AppActionBlue.color),
            ),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: brand.divider),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: context.t('sp.activeCount'),
                  value: '${active.length}',
                ),
              ),
              Container(width: 1, height: 32, color: brand.divider),
              Expanded(
                child: _Stat(
                  label: context.t('sp.completedCount'),
                  value: '$completed',
                ),
              ),
              Container(width: 1, height: 32, color: brand.divider),
              Expanded(
                child: _Stat(
                  label: 'This week',
                  value: '+${formatMoney(symbol, thisWeek)}',
                  valueColor: AppColors.income,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _Stat({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: brand.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: valueColor ?? brand.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Filter segmented control ──────────────────────────────────

class _FilterSegment extends StatelessWidget {
  final _Filter selected;
  final ValueChanged<_Filter> onSelected;
  const _FilterSegment({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final filters = <(_Filter, String)>[
      (_Filter.all, context.t('sp.filterAll')),
      (_Filter.active, context.t('sp.filterActive')),
      (_Filter.completed, context.t('sp.filterCompleted')),
      (_Filter.cancelled, context.t('sp.filterCancelled')),
    ];
    final selectedIdx = filters.indexWhere((f) => f.$1 == selected);
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final pillW = (constraints.maxWidth - 8) / 4;
        return Container(
          height: 40,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: brand.divider,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: selectedIdx * pillW,
                top: 0,
                bottom: 0,
                width: pillW,
                child: Container(
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 4,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final (f, label) in filters)
                    Expanded(
                      child: GestureDetector(
                        onTap: () => onSelected(f),
                        child: Container(
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: f == selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: f == selected ? brand.ink : brand.inkSoft,
                            ),
                            child: Text(label),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Plan row (flat, inside grouped card) ──────────────────────

class _PlanRow extends StatelessWidget {
  final SavingPlan plan;
  final String symbol;
  const _PlanRow({required this.plan, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final accent = _accentForType(plan.type);
    final tint = _tintForType(plan.type);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => SavingPlanDetailScreen(planId: plan.id),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          child: Row(
            children: [
              _ProgressRing(
                progress: plan.progress,
                color: accent,
                bg: brand.divider,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            plan.name,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: brand.ink,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _TypeChip(type: plan.type, tint: tint),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _subtitle(context, plan),
                      style: TextStyle(
                        fontSize: 12,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatMoney(symbol, plan.currentAmount),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: brand.ink,
                    ),
                  ),
                  Text(
                    '/ ${formatMoney(symbol, plan.targetAmount)}',
                    style: TextStyle(
                      fontSize: 11,
                      color: brand.inkSoft,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(BuildContext context, SavingPlan p) {
    switch (p.status) {
      case SavingPlanStatus.cancelled:
        return context.t('sp.statusCancelled');
      case SavingPlanStatus.completed:
        return context.t('sp.statusCompleted');
      case SavingPlanStatus.active:
        switch (p.type) {
          case SavingPlanType.daysChallenge:
            final done = p.slotsCompleted;
            final total = p.totalDays ?? 0;
            final left = total - done;
            return 'Day $done of $total · $left days left';
          case SavingPlanType.weeksChallenge:
            final done = p.slotsCompleted;
            final total = p.totalWeeks ?? 0;
            final left = total - done;
            return 'Week $done of $total · $left weeks left';
          case SavingPlanType.flexible:
            return context.t('sp.flexibleNote');
          case SavingPlanType.fixed:
            return _frequencyLabel(context, p.frequency);
        }
    }
  }

  String _frequencyLabel(BuildContext context, SavingFrequency? f) =>
      switch (f) {
        SavingFrequency.daily => context.t('sp.daily'),
        SavingFrequency.weekly => context.t('sp.weekly'),
        SavingFrequency.monthly => context.t('sp.monthly'),
        null => context.t('sp.fixed'),
      };

  static Color _accentForType(SavingPlanType t) => switch (t) {
        SavingPlanType.fixed => AppColors.income,
        SavingPlanType.flexible => AppActionBlue.color,
        SavingPlanType.daysChallenge => AppColors.income,
        SavingPlanType.weeksChallenge => AppActionBlue.color,
      };

  static Color _tintForType(SavingPlanType t) => switch (t) {
        SavingPlanType.fixed => AppColors.mint,
        SavingPlanType.flexible => AppColors.lilac,
        SavingPlanType.daysChallenge => AppColors.mint,
        SavingPlanType.weeksChallenge => AppColors.sky,
      };
}

// ── Swipe actions ─────────────────────────────────────────────

class _SavingPlanSwipeActions extends ConsumerWidget {
  final SavingPlan plan;
  final String symbol;
  final String? userId;
  final Widget child;

  const _SavingPlanSwipeActions({
    required this.plan,
    required this.symbol,
    required this.userId,
    required this.child,
  });

  bool get _canAddContribution =>
      plan.status == SavingPlanStatus.active &&
      plan.type != SavingPlanType.daysChallenge &&
      plan.type != SavingPlanType.weeksChallenge;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('saving-plan-swipe-${plan.id}'),
      direction: DismissDirection.horizontal,
      background: _SwipeBg(
        icon: CupertinoIcons.pencil,
        label: context.t('common.edit'),
        alignment: Alignment.centerLeft,
        color: AppColors.mint,
      ),
      secondaryBackground: _SwipeBg(
        icon: CupertinoIcons.ellipsis,
        label: context.t('common.actions'),
        alignment: Alignment.centerRight,
        color: AppColors.blush,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          if (_canAddContribution) {
            await _showEditActions(context, ref);
          } else {
            Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => AddEditSavingPlanScreen(plan: plan),
              ),
            );
          }
        } else {
          await _showMoreActions(context, ref);
        }
        return false;
      },
      child: child,
    );
  }

  Future<void> _showEditActions(BuildContext context, WidgetRef ref) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(plan.name),
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
            child: Text(context.t('common.edit')),
          ),
          CupertinoActionSheetAction(
            onPressed: () async {
              Navigator.pop(ctx);
              await _showAddContributionSheet(context, ref);
            },
            child: Text(context.t('sp.addContribution')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(context.t('common.cancel')),
        ),
      ),
    );
  }

  Future<void> _showMoreActions(BuildContext context, WidgetRef ref) async {
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(plan.name),
        actions: [
          if (plan.status == SavingPlanStatus.active)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                if (userId == null) return;
                try {
                  await ref
                      .read(savingPlanServiceProvider)
                      .markCompleted(userId!, plan);
                  if (context.mounted) {
                    AppToast.show(context, 'Plan completed', type: AppToastType.success);
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(context, 'Failed to complete plan', type: AppToastType.error);
                  }
                }
              },
              child: Text(context.t('inst.markCompleted')),
            ),
          if (plan.status == SavingPlanStatus.cancelled)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                if (userId == null) return;
                try {
                  await ref
                      .read(savingPlanServiceProvider)
                      .setCancelled(userId!, plan, false);
                  if (context.mounted) {
                    AppToast.show(context, 'Plan reactivated', type: AppToastType.success);
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(context, 'Failed to reactivate', type: AppToastType.error);
                  }
                }
              },
              child: Text(context.t('inst.reactivate')),
            )
          else if (plan.status != SavingPlanStatus.completed)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(ctx);
                if (userId == null) return;
                try {
                  await ref
                      .read(savingPlanServiceProvider)
                      .setCancelled(userId!, plan, true);
                  if (context.mounted) {
                    AppToast.show(context, 'Plan cancelled', type: AppToastType.success);
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(context, 'Failed to cancel', type: AppToastType.error);
                  }
                }
              },
              child: Text(context.t('common.cancel')),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              await _confirmDelete(context, ref);
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

  Future<void> _showAddContributionSheet(
    BuildContext context,
    WidgetRef ref,
  ) async {
    if (userId == null) return;
    final controller = TextEditingController(
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
      builder: (ctx) => Padding(
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
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
                final value = double.tryParse(controller.text) ?? 0;
                Navigator.pop(ctx, value);
              },
              child: Text(context.t('common.save')),
            ),
          ],
        ),
      ),
    );
    controller.dispose();
    if (amount == null || amount <= 0) return;
    try {
      await ref.read(savingPlanServiceProvider).addContribution(
            userId!,
            plan,
            SavingContribution(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              amount: amount,
              date: DateTime.now(),
            ),
          );
      if (context.mounted) {
        AppToast.show(context, 'Contribution added', type: AppToastType.success);
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.show(context, 'Failed to add contribution', type: AppToastType.error);
      }
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    if (userId == null) return;
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
      try {
        await ref.read(savingPlanServiceProvider).delete(userId!, plan.id);
        if (context.mounted) {
          AppToast.show(context, 'Plan deleted', type: AppToastType.success);
        }
      } catch (_) {
        if (context.mounted) {
          AppToast.show(context, 'Failed to delete', type: AppToastType.error);
        }
      }
    }
  }
}

class _SwipeBg extends StatelessWidget {
  final IconData icon;
  final String label;
  final Alignment alignment;
  final Color color;

  const _SwipeBg({
    required this.icon,
    required this.label,
    required this.alignment,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      color: color,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.ink, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Progress ring ─────────────────────────────────────────────

class _ProgressRing extends StatelessWidget {
  final double progress;
  final Color color;
  final Color bg;
  const _ProgressRing({
    required this.progress,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 4.5,
              valueColor: AlwaysStoppedAnimation(bg),
            ),
          ),
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 4.5,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Type chip ─────────────────────────────────────────────────

class _TypeChip extends StatelessWidget {
  final SavingPlanType type;
  final Color tint;
  const _TypeChip({required this.type, required this.tint});

  @override
  Widget build(BuildContext context) {
    final label = switch (type) {
      SavingPlanType.fixed => context.t('sp.typeFixed'),
      SavingPlanType.flexible => context.t('sp.typeFlexible'),
      SavingPlanType.daysChallenge => context.t('sp.typeDays'),
      SavingPlanType.weeksChallenge => context.t('sp.typeWeeks'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              CupertinoIcons.flag_fill,
              color: AppColors.income,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.t('sp.emptyTitle'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            context.t('sp.emptyHint'),
            textAlign: TextAlign.center,
            style: TextStyle(color: brand.inkSoft, fontSize: 12),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: onAdd, child: Text(context.t('sp.add'))),
        ],
      ),
    );
  }
}

// Public helpers for detail screen
Color spAccent(SavingPlanType t) => _PlanRow._accentForType(t);
Color spTint(SavingPlanType t) => _PlanRow._tintForType(t);
