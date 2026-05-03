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

/// Manage installments — redesigned for clarity.
///
/// Layout:
///   1. Header summary card — total monthly outflow, active count,
///      total remaining across all active fixed-term plans.
///   2. List of installments. Each tile is **collapsed by default**:
///      name, monthly amount, status badge, and one secondary line
///      (months left / remaining for fixed-term, "Ongoing" for
///      lifetime). A progress bar appears under fixed-term tiles.
///   3. Tap a tile to expand it inline — start date, total months,
///      months paid, next payment date, plus iOS-style action buttons
///      (Edit / Mark completed / Cancel / Delete with confirmation).
///
/// The expand-in-place pattern keeps everything on one screen so users
/// can scan all their plans at a glance without losing context.
class InstallmentsScreen extends ConsumerStatefulWidget {
  const InstallmentsScreen({super.key});

  @override
  ConsumerState<InstallmentsScreen> createState() => _InstallmentsScreenState();
}

class _InstallmentsScreenState extends ConsumerState<InstallmentsScreen> {
  String? _expandedId;

  void _toggleExpanded(String id) {
    setState(() => _expandedId = _expandedId == id ? null : id);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final month = ref.watch(selectedMonthProvider);
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
            // Sort: active first, then completed, then cancelled. Inside
            // each group, due-day ascending.
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
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    context.t('inst.all'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                for (final i in sorted)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _InstallmentSwipeActions(
                      installment: i,
                      userId: user?.uid,
                      child: _InstallmentTile(
                        installment: i,
                        month: month,
                        symbol: symbol,
                        userId: user?.uid,
                        expanded: _expandedId == i.id,
                        onToggle: () => _toggleExpanded(i.id),
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

  static int _statusRank(InstallmentStatus s) {
    switch (s) {
      case InstallmentStatus.active:
        return 0;
      case InstallmentStatus.completed:
        return 1;
      case InstallmentStatus.cancelled:
        return 2;
    }
  }
}

// ── Summary card ──────────────────────────────────────────────

class _SummaryCard extends StatelessWidget {
  final List<Installment> items;
  final String symbol;
  const _SummaryCard({required this.items, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final active = items
        .where((i) => i.status == InstallmentStatus.active)
        .toList();
    final monthlyTotal = active.fold<double>(0, (s, i) => s + i.amount);
    final remainingTotal = active.fold<double>(
      0,
      (s, i) => s + (i.totalRemaining ?? 0),
    );

    return SectionCard(
      color: brand.surface,
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('inst.summaryTitle'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: brand.inkSoft,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            formatMoney(symbol, monthlyTotal),
            style: const TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          Text(
            context.t('inst.summaryMonthly'),
            style: TextStyle(
              fontSize: 12,
              color: brand.inkSoft,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 14),
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
                  flexible: true,
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
  final bool flexible;
  const _SummaryStat({
    required this.label,
    required this.value,
    this.flexible = false,
  });

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
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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

// ── Tile (collapsed + expandable) ─────────────────────────────

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
      await ref
          .read(installmentServiceProvider)
          .delete(userId!, installment.id);
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

class _InstallmentTile extends ConsumerWidget {
  final Installment installment;
  final DateTime month;
  final String symbol;
  final String? userId;
  final bool expanded;
  final VoidCallback onToggle;

  const _InstallmentTile({
    required this.installment,
    required this.month,
    required this.symbol,
    required this.userId,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final i = installment;
    final s = styleFor(i.category);
    final status = i.status;
    final isActive = status == InstallmentStatus.active;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onToggle();
          },
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header row ─────────────────────────────────
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: s.background,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(s.icon, color: s.accent, size: 20),
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
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusBadge(installment: i),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _primaryLine(context, i),
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
                          formatMoney(symbol, i.amount),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.t('inst.perMonth'),
                          style: TextStyle(
                            fontSize: 10,
                            color: brand.inkSoft,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (!i.isLifetime) ...[
                  const SizedBox(height: 12),
                  _ProgressRow(installment: i, symbol: symbol),
                ],
                if (expanded)
                  _ExpandedDetails(
                    installment: i,
                    symbol: symbol,
                    userId: userId,
                    monthSelected: month,
                    isActive: isActive,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Single most-useful line under the name. Fixed-term active plans
  /// surface "N months left · remaining $X". Lifetime → "Ongoing ·
  /// next due Mmm d". Completed / cancelled → status text.
  String _primaryLine(BuildContext context, Installment i) {
    switch (i.status) {
      case InstallmentStatus.cancelled:
        return context.t('inst.cancelledLine');
      case InstallmentStatus.completed:
        return context.t('inst.completedLine');
      case InstallmentStatus.active:
        if (i.isLifetime) {
          final next = i.nextDueDate();
          if (next != null) {
            return '${context.t('inst.statusLifetime')} · '
                '${context.t('inst.nextDue').replaceFirst('{date}', DateFormat('MMM d').format(next))}';
          }
          return context.t('inst.statusLifetime');
        }
        final left = i.monthsLeft ?? 0;
        final rem = i.totalRemaining ?? 0;
        return '${context.t('inst.monthsLeft')}: $left · '
            '${formatMoney(symbol, rem)}';
    }
  }
}

// ── Expanded panel ────────────────────────────────────────────

class _ExpandedDetails extends ConsumerWidget {
  final Installment installment;
  final String symbol;
  final String? userId;
  final DateTime monthSelected;
  final bool isActive;

  const _ExpandedDetails({
    required this.installment,
    required this.symbol,
    required this.userId,
    required this.monthSelected,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final i = installment;
    final next = i.nextDueDate();
    final paid = i.isPaidIn(monthSelected);
    final activeNow = i.isActiveIn(monthSelected);

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(height: 1, color: brand.divider),
          const SizedBox(height: 12),
          // Detail rows.
          _DetailRow(
            label: context.t('inst.detailStartDate'),
            value: DateFormat('MMM d, yyyy').format(i.startDate),
          ),
          if (!i.isLifetime)
            _DetailRow(
              label: context.t('inst.detailTotalMonths'),
              value: '${i.totalMonths}',
            ),
          _DetailRow(
            label: context.t('inst.detailMonthsPaid'),
            value: i.isLifetime ? '${i.paidInApp}' : '${i.paidCount}',
          ),
          if (next != null)
            _DetailRow(
              label: context.t('inst.detailNextPayment'),
              value: DateFormat('MMM d, yyyy').format(next),
            ),
          _DetailRow(
            label: context.t('inst.detailDueDay'),
            value: '${i.dayOfMonth}',
          ),
          if (i.originalPrincipal != null)
            _DetailRow(
              label: context.t('inst.detailOriginalAmount'),
              value: formatMoney(symbol, i.originalPrincipal!),
            ),
          // Inline mark-paid for the selected month, if active now.
          if (isActive && activeNow) ...[
            const SizedBox(height: 8),
            _MarkPaidRow(
              installment: i,
              month: monthSelected,
              userId: userId,
              paid: paid,
            ),
          ],
          const SizedBox(height: 14),
          // Action buttons (iOS-style).
          _ActionButtons(installment: i, userId: userId, isActive: isActive),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: brand.inkSoft,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _MarkPaidRow extends ConsumerWidget {
  final Installment installment;
  final DateTime month;
  final String? userId;
  final bool paid;

  const _MarkPaidRow({
    required this.installment,
    required this.month,
    required this.userId,
    required this.paid,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monthLabel = DateFormat('MMM').format(month);
    return SizedBox(
      width: double.infinity,
      child: GestureDetector(
        onTap: () async {
          if (userId == null) return;
          HapticFeedback.selectionClick();
          final svc = ref.read(installmentServiceProvider);
          if (paid) {
            await svc.markUnpaid(userId!, installment, month);
          } else {
            await svc.markPaid(userId!, installment, month);
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: paid ? AppColors.mint : AppColors.sand,
            borderRadius: BorderRadius.circular(14),
          ),
          alignment: Alignment.center,
          child: Text(
            paid
                ? '${context.t('inst.paidFor').replaceFirst('{month}', monthLabel)} ✓'
                : context
                      .t('inst.markPaid')
                      .replaceFirst('{month}', monthLabel),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: paid ? AppColors.income : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButtons extends ConsumerWidget {
  final Installment installment;
  final String? userId;
  final bool isActive;

  const _ActionButtons({
    required this.installment,
    required this.userId,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = installment;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionChip(
          icon: CupertinoIcons.pencil,
          label: context.t('common.edit'),
          onTap: () => Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (_) => AddEditInstallmentScreen(installment: i),
            ),
          ),
        ),
        if (isActive)
          _ActionChip(
            icon: CupertinoIcons.check_mark_circled,
            label: context.t('inst.markCompleted'),
            onTap: () async {
              if (userId == null) return;
              await ref
                  .read(installmentServiceProvider)
                  .markCompleted(userId!, i);
            },
          ),
        if (i.status == InstallmentStatus.cancelled)
          _ActionChip(
            icon: CupertinoIcons.refresh,
            label: context.t('inst.reactivate'),
            onTap: () async {
              if (userId == null) return;
              await ref.read(installmentServiceProvider).reactivate(userId!, i);
            },
          )
        else
          _ActionChip(
            icon: CupertinoIcons.xmark_circle,
            label: context.t('inst.cancel'),
            destructive: true,
            onTap: () => _confirmCancel(context, ref, i),
          ),
        _ActionChip(
          icon: CupertinoIcons.trash,
          label: context.t('common.delete'),
          destructive: true,
          onTap: () => _confirmDelete(context, ref, i),
        ),
      ],
    );
  }

  Future<void> _confirmCancel(
    BuildContext context,
    WidgetRef ref,
    Installment i,
  ) async {
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
      await ref.read(installmentServiceProvider).setCancelled(userId!, i, true);
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Installment i,
  ) async {
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
      await ref.read(installmentServiceProvider).delete(userId!, i.id);
    }
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final fg = destructive ? AppColors.expense : brand.ink;
    final bg = destructive
        ? AppColors.blush.withValues(alpha: 0.55)
        : brand.background;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
}

class _ProgressRow extends StatelessWidget {
  final Installment installment;
  final String symbol;
  const _ProgressRow({required this.installment, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final i = installment;
    final total = i.totalMonths!;
    final paid = i.paidCount;
    final pct = i.progress;
    final completed = i.status == InstallmentStatus.completed;
    final cancelled = i.status == InstallmentStatus.cancelled;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            minHeight: 5,
            backgroundColor: brand.divider,
            valueColor: AlwaysStoppedAnimation<Color>(
              cancelled
                  ? brand.inkSoft
                  : completed
                  ? AppColors.income
                  : brand.ink,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '$paid / $total ${context.t('inst.monthsPaid').toLowerCase()}',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: brand.inkSoft,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final Installment installment;
  const _StatusBadge({required this.installment});

  @override
  Widget build(BuildContext context) {
    final status = installment.status;
    final (label, bg, fg) = switch (status) {
      InstallmentStatus.active when installment.isLifetime => (
        context.t('inst.statusLifetime'),
        AppColors.butter,
        AppColors.ink,
      ),
      InstallmentStatus.active => (
        context.t('inst.statusActive'),
        AppColors.mint,
        AppColors.income,
      ),
      InstallmentStatus.completed => (
        context.t('inst.statusCompleted'),
        AppColors.sky,
        AppColors.ink,
      ),
      InstallmentStatus.cancelled => (
        context.t('inst.statusCancelled'),
        AppColors.divider,
        AppColors.inkSoft,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
