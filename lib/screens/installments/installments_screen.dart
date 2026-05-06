import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/installment.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import 'add_edit_installment_screen.dart';
import 'installment_detail_screen.dart';

class InstallmentsScreen extends ConsumerWidget {
  const InstallmentsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final installmentsAsync = ref.watch(installmentsProvider);
    final user = ref.watch(authStateProvider).valueOrNull;

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.t('inst.title')),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.add),
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => const AddEditInstallmentScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: installmentsAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) =>
              Center(child: Text('${context.t('common.error')}: $e')),
          data: (items) {
            if (items.isEmpty) return _Empty();
            final sorted = [...items]
              ..sort((a, b) {
                final aRank = _statusRank(a.status);
                final bRank = _statusRank(b.status);
                if (aRank != bRank) return aRank.compareTo(bRank);
                return a.dayOfMonth.compareTo(b.dayOfMonth);
              });

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _SummaryCard(items: items, symbol: symbol),
                const SizedBox(height: 20),
                // Section header
                Row(
                  children: [
                    Text(
                      context.t('inst.all').toUpperCase(),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF8E8E93),
                        letterSpacing: 0.8,
                      ),
                    ),
                    const Spacer(),
                    GestureDetector(
                      onTap: () {},
                      child: const Text(
                        'Filter',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF6366F1),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Grouped card with all installments
                Container(
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
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      children: [
                        for (int i = 0; i < sorted.length; i++) ...[
                          _InstallmentSwipeActions(
                            installment: sorted[i],
                            userId: user?.uid,
                            child: _InstallmentRow(
                              installment: sorted[i],
                              symbol: symbol,
                              onTap: () => Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  builder: (_) => InstallmentDetailScreen(
                                    installmentId: sorted[i].id,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (i < sorted.length - 1)
                            Divider(
                              height: 1,
                              color: brand.divider,
                              indent: 16,
                              endIndent: 0,
                            ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static int _statusRank(InstallmentStatus s) => switch (s) {
        InstallmentStatus.active => 0,
        InstallmentStatus.completed => 1,
        InstallmentStatus.cancelled => 2,
      };
}

// ── Summary card ──────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final List<Installment> items;
  final String symbol;
  const _SummaryCard({required this.items, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = items.where((i) => i.status == InstallmentStatus.active).toList();
    final monthlyTotal = active.fold<double>(0, (s, i) => s + i.amount);
    final remainingTotal =
        active.fold<double>(0, (s, i) => s + (i.totalRemaining ?? 0));

    // Find next batch date (earliest upcoming due across all active)
    DateTime? nextBatch;
    for (final i in active) {
      final next = i.nextDueDate();
      if (next != null && (nextBatch == null || next.isBefore(nextBatch))) {
        nextBatch = next;
      }
    }
    String? nextBatchLine;
    if (nextBatch != null) {
      final today = DateTime.now();
      final daysAway = nextBatch
          .difference(DateTime(today.year, today.month, today.day))
          .inDays;
      final dateStr = DateFormat('MMM d').format(nextBatch);
      nextBatchLine = daysAway == 0
          ? 'Next batch today'
          : 'Next batch on $dateStr · $daysAway days away';
    }

    // Split amount for display
    final raw = formatMoney(symbol, monthlyTotal);
    final dotIdx = raw.indexOf('.');
    final mainPart = dotIdx >= 0 ? raw.substring(0, dotIdx) : raw;
    final decPart = dotIdx >= 0 ? raw.substring(dotIdx) : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
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
          Text(
            context.t('inst.summaryTitle').toUpperCase(),
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
                  fontWeight: FontWeight.w900,
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
          if (nextBatchLine != null) ...[
            const SizedBox(height: 4),
            Text(
              nextBatchLine,
              style: TextStyle(
                fontSize: 12,
                color: brand.inkSoft,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Divider(height: 1, color: brand.divider),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SummaryStat(
                  label: context.t('inst.summaryActive'),
                  value: '${active.length}',
                ),
              ),
              Container(width: 1, height: 32, color: brand.divider),
              Expanded(
                child: _SummaryStat(
                  label: context.t('inst.summaryRemaining'),
                  value: formatMoney(symbol, remainingTotal),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryStat extends StatelessWidget {
  final String label;
  final String value;
  const _SummaryStat({required this.label, required this.value});

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
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: brand.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────

class _Empty extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SectionCard(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.butter,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  CupertinoIcons.calendar_today,
                  color: AppColors.ink,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.t('inst.none'),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.t('inst.emptyHint'),
                textAlign: TextAlign.center,
                style: TextStyle(color: brand.inkSoft),
              ),
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => const AddEditInstallmentScreen(),
                  ),
                ),
                child: Text(context.t('inst.add')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Installment Row ───────────────────────────────────────────

class _InstallmentRow extends StatelessWidget {
  final Installment installment;
  final String symbol;
  final VoidCallback onTap;

  const _InstallmentRow({
    required this.installment,
    required this.symbol,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final i = installment;
    final style = styleFor(i.category);
    final isActive = i.status == InstallmentStatus.active;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Subtle gray icon
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: brand.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(style.icon, color: brand.inkSoft, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                i.name,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: brand.ink,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _StatusBadge(installment: i),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _subtitle(context, i),
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
                        formatMoney(symbol, i.amount),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: brand.ink,
                        ),
                      ),
                      Text(
                        context.t('inst.perMonth'),
                        style: TextStyle(
                          fontSize: 10,
                          color: brand.inkSoft,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              // Progress bar for fixed-term active plans
              if (!i.isLifetime && isActive) ...[
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: i.progress,
                    minHeight: 4,
                    backgroundColor: brand.divider,
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF22C55E)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(BuildContext context, Installment i) {
    switch (i.status) {
      case InstallmentStatus.cancelled:
        return context.t('inst.cancelledLine');
      case InstallmentStatus.completed:
        return context.t('inst.completedLine');
      case InstallmentStatus.active:
        if (i.isLifetime) {
          final next = i.nextDueDate();
          if (next != null) {
            return '${context.t('inst.nextDue').replaceFirst('{date}', DateFormat('MMM d').format(next))}';
          }
          return context.t('inst.statusLifetime');
        }
        final paid = i.paidCount;
        final total = i.totalMonths ?? 0;
        final rem = i.totalRemaining ?? 0;
        return '$paid/$total paid · ${formatMoney(symbol, rem)} left';
    }
  }
}

// ── Swipe actions (unchanged functionality) ───────────────────

class _InstallmentSwipeActions extends ConsumerWidget {
  final Installment installment;
  final String? userId;
  final Widget child;

  const _InstallmentSwipeActions({
    required this.installment,
    required this.userId,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('installment-swipe-${installment.id}'),
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
        HapticFeedback.selectionClick();
        if (direction == DismissDirection.startToEnd) {
          Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (_) =>
                  AddEditInstallmentScreen(installment: installment),
            ),
          );
        } else {
          await _showMoreActions(context, ref);
        }
        return false;
      },
      child: child,
    );
  }

  Future<void> _showMoreActions(BuildContext context, WidgetRef ref) async {
    final svc = ref.read(installmentServiceProvider);
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(installment.name),
        actions: [
          if (installment.status == InstallmentStatus.active)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                if (userId == null) return;
                await svc.markCompleted(userId!, installment);
              },
              child: Text(context.t('inst.markCompleted')),
            ),
          if (installment.status == InstallmentStatus.cancelled)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                if (userId == null) return;
                await svc.reactivate(userId!, installment);
              },
              child: Text(context.t('inst.reactivate')),
            )
          else
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(ctx);
                await _confirmCancel(context, ref);
              },
              child: Text(context.t('inst.cancel')),
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

  Future<void> _confirmCancel(BuildContext context, WidgetRef ref) async {
    if (userId == null) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (dctx) => CupertinoAlertDialog(
        title: Text(context.t('inst.cancelTitle')),
        content: Text(context.t('inst.cancelMessage')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(dctx, false),
            child: Text(context.t('inst.keep')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(dctx, true),
            child: Text(context.t('inst.cancelIt')),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref
          .read(installmentServiceProvider)
          .setCancelled(userId!, installment, true);
    }
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    if (userId == null) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (dctx) => CupertinoAlertDialog(
        title: Text(context.t('inst.deleteTitle')),
        content: Text(context.t('inst.deleteMessage')),
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
    if (ok == true) {
      await ref.read(installmentServiceProvider).delete(userId!, installment.id);
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
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Status badge ──────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final Installment installment;
  const _StatusBadge({required this.installment});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (installment.status) {
      InstallmentStatus.active when installment.isLifetime => (
        context.t('inst.statusLifetime'),
        AppColors.butter,
        const Color(0xFFB36A1F),
      ),
      InstallmentStatus.active => (
        context.t('inst.statusActive'),
        AppColors.mint,
        AppColors.income,
      ),
      InstallmentStatus.completed => (
        context.t('inst.statusCompleted'),
        AppColors.sky,
        const Color(0xFF2A6FB5),
      ),
      InstallmentStatus.cancelled => (
        context.t('inst.statusCancelled'),
        AppColors.divider,
        AppColors.inkSoft,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: fg),
      ),
    );
  }
}
