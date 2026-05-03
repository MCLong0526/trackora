import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/saving_plan.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import 'add_edit_saving_plan_screen.dart';
import 'saving_plan_detail_screen.dart';

/// Saving Plans list screen.
///
/// Layout:
///  • Summary card: total saved across active plans, total target,
///    active count, completed count.
///  • Filter pill row: all / active / completed / cancelled.
///  • Plan cards. Each plan shows name, type, progress %,
///    current/target, and optional periods-left.
class SavingPlansScreen extends ConsumerStatefulWidget {
  const SavingPlansScreen({super.key});

  @override
  ConsumerState<SavingPlansScreen> createState() => _SavingPlansScreenState();
}

enum _Filter { all, active, completed, cancelled }

class _SavingPlansScreenState extends ConsumerState<SavingPlansScreen> {
  _Filter _filter = _Filter.all;

  bool _matches(SavingPlan p) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.active:
        return p.status == SavingPlanStatus.active;
      case _Filter.completed:
        return p.status == SavingPlanStatus.completed;
      case _Filter.cancelled:
        return p.status == SavingPlanStatus.cancelled;
    }
  }

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
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _Summary(plans: plans, symbol: symbol),
                const SizedBox(height: 14),
                _FilterChips(
                  selected: _filter,
                  onSelected: (f) => setState(() => _filter = f),
                ),
                const SizedBox(height: 14),
                if (plans.isEmpty)
                  _EmptyState(
                    onAdd: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        builder: (_) => const AddEditSavingPlanScreen(),
                      ),
                    ),
                  )
                else
                  for (final p in plans.where(_matches))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _SavingPlanSwipeActions(
                        plan: p,
                        symbol: symbol,
                        userId: user?.uid,
                        child: _PlanCard(plan: p, symbol: symbol),
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

class _Summary extends StatelessWidget {
  final List<SavingPlan> plans;
  final String symbol;
  const _Summary({required this.plans, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = plans
        .where((p) => p.status == SavingPlanStatus.active)
        .toList();
    final completed = plans
        .where((p) => p.status == SavingPlanStatus.completed)
        .length;
    final saved = active.fold<double>(0, (s, p) => s + p.currentAmount);
    final target = active.fold<double>(0, (s, p) => s + p.targetAmount);
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.mint, AppColors.sky],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('sp.summaryTitle'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: AppColors.ink,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            formatMoney(symbol, saved),
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
              color: AppColors.ink,
            ),
          ),
          Text(
            '${context.t('sp.ofTarget')} ${formatMoney(symbol, target)}',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: context.t('sp.activeCount'),
                  value: '${active.length}',
                ),
              ),
              Container(width: 1, height: 28, color: brand.divider),
              Expanded(
                child: _Stat(
                  label: context.t('sp.completedCount'),
                  value: '$completed',
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
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.ink,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: AppColors.ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final _Filter selected;
  final ValueChanged<_Filter> onSelected;
  const _FilterChips({required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final fg = foregroundOn(brand.accentDark);
    final filters = <(_Filter, String)>[
      (_Filter.all, context.t('sp.filterAll')),
      (_Filter.active, context.t('sp.filterActive')),
      (_Filter.completed, context.t('sp.filterCompleted')),
      (_Filter.cancelled, context.t('sp.filterCancelled')),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (f, label) in filters) ...[
            GestureDetector(
              onTap: () => onSelected(f),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: f == selected ? brand.accentDark : brand.surface,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: f == selected ? fg : brand.ink,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _PlanCard extends StatelessWidget {
  final SavingPlan plan;
  final String symbol;
  const _PlanCard({required this.plan, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final accent = _accentForType(plan.type);
    final tint = _tintForType(plan.type);
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (_) => SavingPlanDetailScreen(planId: plan.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
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
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _TypeChip(type: plan.type, tint: tint),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _subtitle(context, plan),
                            style: TextStyle(
                              fontSize: 12,
                              color: brand.inkSoft,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatMoney(symbol, plan.currentAmount),
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          '/ ${formatMoney(symbol, plan.targetAmount)}',
                          style: TextStyle(
                            fontSize: 11,
                            color: brand.inkSoft,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: plan.progress,
                    minHeight: 5,
                    backgroundColor: brand.divider,
                    valueColor: AlwaysStoppedAnimation(accent),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${(plan.progress * 100).toStringAsFixed(0)}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: brand.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _trailing(context, plan, symbol),
                      style: TextStyle(
                        fontSize: 11,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
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
            return context
                .t('sp.dayProgress')
                .replaceFirst('{done}', '${p.slotsCompleted}')
                .replaceFirst('{total}', '${p.totalDays}');
          case SavingPlanType.weeksChallenge:
            return context
                .t('sp.weekProgress')
                .replaceFirst('{done}', '${p.slotsCompleted}')
                .replaceFirst('{total}', '${p.totalWeeks}');
          case SavingPlanType.flexible:
            return context.t('sp.flexibleNote');
          case SavingPlanType.fixed:
            return _frequencyLabel(context, p.frequency);
        }
    }
  }

  String _trailing(BuildContext context, SavingPlan p, String symbol) {
    if (p.status != SavingPlanStatus.active) return '';
    final rem = p.remaining;
    final periods = p.periodsLeft;
    if (periods == null) {
      return '${formatMoney(symbol, rem)} ${context.t('sp.left').toLowerCase()}';
    }
    final unit = switch (p.type) {
      SavingPlanType.daysChallenge => context.t('sp.daysLeft'),
      SavingPlanType.weeksChallenge => context.t('sp.weeksLeft'),
      SavingPlanType.fixed => switch (p.frequency) {
        SavingFrequency.daily => context.t('sp.daysLeft'),
        SavingFrequency.weekly => context.t('sp.weeksLeft'),
        SavingFrequency.monthly => context.t('sp.monthsLeft'),
        null => context.t('sp.periodsLeft'),
      },
      SavingPlanType.flexible => context.t('sp.periodsLeft'),
    };
    return '$periods $unit';
  }

  String _frequencyLabel(BuildContext context, SavingFrequency? f) {
    return switch (f) {
      SavingFrequency.daily => context.t('sp.daily'),
      SavingFrequency.weekly => context.t('sp.weekly'),
      SavingFrequency.monthly => context.t('sp.monthly'),
      null => context.t('sp.fixed'),
    };
  }

  static Color _accentForType(SavingPlanType t) {
    switch (t) {
      case SavingPlanType.fixed:
        return AppColors.income;
      case SavingPlanType.flexible:
        return AppColors.accent;
      case SavingPlanType.daysChallenge:
        return AppColors.expense;
      case SavingPlanType.weeksChallenge:
        return AppColors.accentDark;
    }
  }

  static Color _tintForType(SavingPlanType t) {
    switch (t) {
      case SavingPlanType.fixed:
        return AppColors.mint;
      case SavingPlanType.flexible:
        return AppColors.sky;
      case SavingPlanType.daysChallenge:
        return AppColors.peach;
      case SavingPlanType.weeksChallenge:
        return AppColors.lilac;
    }
  }
}

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
      background: _SwipeActionBackground(
        icon: CupertinoIcons.pencil,
        label: context.t('common.edit'),
        alignment: Alignment.centerLeft,
        color: AppColors.mint,
      ),
      secondaryBackground: _SwipeActionBackground(
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
                await ref
                    .read(savingPlanServiceProvider)
                    .markCompleted(userId!, plan);
              },
              child: Text(context.t('inst.markCompleted')),
            ),
          if (plan.status == SavingPlanStatus.cancelled)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                if (userId == null) return;
                await ref
                    .read(savingPlanServiceProvider)
                    .setCancelled(userId!, plan, false);
              },
              child: Text(context.t('inst.reactivate')),
            )
          else if (plan.status != SavingPlanStatus.completed)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(ctx);
                if (userId == null) return;
                await ref
                    .read(savingPlanServiceProvider)
                    .setCancelled(userId!, plan, true);
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
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
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
    await ref
        .read(savingPlanServiceProvider)
        .addContribution(
          userId!,
          plan,
          SavingContribution(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            amount: amount,
            date: DateTime.now(),
          ),
        );
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
      await ref.read(savingPlanServiceProvider).delete(userId!, plan.id);
    }
  }
}

class _SwipeActionBackground extends StatelessWidget {
  final IconData icon;
  final String label;
  final Alignment alignment;
  final Color color;

  const _SwipeActionBackground({
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
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.ink, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

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
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              value: 1,
              strokeWidth: 4,
              valueColor: AlwaysStoppedAnimation(bg),
            ),
          ),
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 4,
              backgroundColor: Colors.transparent,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          Text(
            '${(progress * 100).toStringAsFixed(0)}%',
            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
      ),
    );
  }
}

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

// Public helpers exposed for the detail screen so it can match list
// styling without reaching into private state.
Color spAccent(SavingPlanType t) => _PlanCard._accentForType(t);
Color spTint(SavingPlanType t) => _PlanCard._tintForType(t);
