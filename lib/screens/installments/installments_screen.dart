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
import '../../widgets/app_toast.dart';
import '../../widgets/section_card.dart';
import 'add_edit_installment_screen.dart';
import 'installment_detail_screen.dart';

// Coordinates open/close state across all swipe rows so only one can be open at a time.
class _SwipeCoordinator extends ValueNotifier<String?> {
  _SwipeCoordinator() : super(null);

  void openRow(String id) => value = id;
  void closeAll() => value = null;
}

class InstallmentsScreen extends ConsumerStatefulWidget {
  const InstallmentsScreen({super.key});

  @override
  ConsumerState<InstallmentsScreen> createState() => _InstallmentsScreenState();
}

class _InstallmentsScreenState extends ConsumerState<InstallmentsScreen> {
  final _coordinator = _SwipeCoordinator();

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  static int _statusRank(InstallmentStatus s) => switch (s) {
        InstallmentStatus.active => 0,
        InstallmentStatus.completed => 1,
        InstallmentStatus.cancelled => 2,
      };

  @override
  Widget build(BuildContext context) {
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
      body: GestureDetector(
        onTap: _coordinator.closeAll,
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
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
                          fontWeight: FontWeight.w600,
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
                            color: AppActionBlue.color,
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
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Column(
                        children: [
                          for (int i = 0; i < sorted.length; i++) ...[
                            _InstallmentSwipeActions(
                              installment: sorted[i],
                              userId: user?.uid,
                              coordinator: _coordinator,
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
      ),
    );
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
                fontWeight: FontWeight.w600,
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
                          fontWeight: FontWeight.w600,
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
            return context.t('inst.nextDue').replaceFirst('{date}', DateFormat('MMM d').format(next));
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

// ── Swipe actions ─────────────────────────────────────────────

class _InstallmentSwipeActions extends ConsumerStatefulWidget {
  final Installment installment;
  final String? userId;
  final Widget child;
  final _SwipeCoordinator coordinator;

  const _InstallmentSwipeActions({
    required this.installment,
    required this.userId,
    required this.child,
    required this.coordinator,
  });

  @override
  ConsumerState<_InstallmentSwipeActions> createState() =>
      _InstallmentSwipeActionsState();
}

class _InstallmentSwipeActionsState
    extends ConsumerState<_InstallmentSwipeActions>
    with SingleTickerProviderStateMixin {
  static const double _rightPanelW = 240.0; // 3 × 80
  static const double _leftPanelW = 88.0;

  late final AnimationController _ctrl;
  late final CurvedAnimation _curve;
  double _offset = 0;
  double _animStart = 0;
  double _animTarget = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _curve = CurvedAnimation(parent: _ctrl, curve: Curves.elasticOut);
    _ctrl.addListener(_onTick);
    widget.coordinator.addListener(_onCoordinatorChange);
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_onCoordinatorChange);
    _ctrl.dispose();
    _curve.dispose();
    super.dispose();
  }

  void _onCoordinatorChange() {
    final openId = widget.coordinator.value;
    if (openId != widget.installment.id && _offset != 0) {
      _springAnimate(0);
    }
  }

  void _onTick() {
    setState(
      () => _offset = _animStart + (_animTarget - _animStart) * _curve.value,
    );
  }

  void _springAnimate(double target) {
    _ctrl.stop();
    _animStart = _offset;
    _animTarget = target;
    _ctrl
      ..reset()
      ..forward();
  }

  void _close() => _springAnimate(0);

  void _onDragStart(DragStartDetails _) {
    _ctrl.stop();
    widget.coordinator.openRow(widget.installment.id);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(-_rightPanelW, _leftPanelW);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    if (_offset < 0) {
      (_offset < -_rightPanelW * 0.35 || v < -500)
          ? _springAnimate(-_rightPanelW)
          : _springAnimate(0);
    } else {
      (_offset > _leftPanelW * 0.35 || v > 500)
          ? _handleEditSwipe()
          : _springAnimate(0);
    }
  }

  Future<void> _handleEditSwipe() async {
    HapticFeedback.selectionClick();
    _springAnimate(_leftPanelW);
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    _springAnimate(0);
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) =>
            AddEditInstallmentScreen(installment: widget.installment),
      ),
    );
  }

  Future<void> _markPaid() async {
    _close();
    HapticFeedback.selectionClick();
    final userId = widget.userId;
    if (userId == null) return;
    if (widget.installment.isPaidIn(DateTime.now())) {
      if (mounted) {
        AppToast.show(
          context,
          'Already paid this month',
          type: AppToastType.success,
        );
      }
      return;
    }
    try {
      await ref
          .read(installmentServiceProvider)
          .markPaid(userId, widget.installment, DateTime.now());
      if (mounted) {
        AppToast.show(context, 'Marked as paid', type: AppToastType.success);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Failed', type: AppToastType.error);
      }
    }
  }

  Future<void> _cancelInstallment() async {
    _close();
    HapticFeedback.selectionClick();
    final userId = widget.userId;
    if (userId == null) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('inst.cancelTitle')),
        content: Text(context.t('inst.cancelMessage')),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('inst.keep')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('inst.cancelIt')),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      try {
        await ref
            .read(installmentServiceProvider)
            .setCancelled(userId, widget.installment, true);
        if (mounted) {
          AppToast.show(
            context,
            'Installment cancelled',
            type: AppToastType.success,
          );
        }
      } catch (_) {
        if (mounted) {
          AppToast.show(context, 'Failed to cancel', type: AppToastType.error);
        }
      }
    }
  }

  Future<void> _deleteInstallment() async {
    _close();
    HapticFeedback.selectionClick();
    final userId = widget.userId;
    if (userId == null) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('inst.deleteTitle')),
        content: Text(context.t('inst.deleteMessage')),
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
    if (ok == true && mounted) {
      try {
        await ref
            .read(installmentServiceProvider)
            .delete(userId, widget.installment.id);
        if (mounted) {
          AppToast.show(
            context,
            'Installment deleted',
            type: AppToastType.success,
          );
        }
      } catch (_) {
        if (mounted) {
          AppToast.show(context, 'Failed to delete', type: AppToastType.error);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final revealRight = (-_offset / _rightPanelW).clamp(0.0, 1.0);
    final revealLeft = (_offset / _leftPanelW).clamp(0.0, 1.0);
    final isOpen = _offset != 0;

    return ClipRect(
      child: GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Stack(
          children: [
            // Right panel (swipe left): Paid / Cancel / Delete — full height via Positioned
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _rightPanelW,
              child: Row(
                children: [
                  Expanded(
                    child: _SwipeAction(
                      label: 'Paid',
                      icon: CupertinoIcons.checkmark_circle_fill,
                      color: const Color(0xFF34C759),
                      reveal: (revealRight * 3).clamp(0.0, 1.0),
                      onTap: _markPaid,
                    ),
                  ),
                  Expanded(
                    child: _SwipeAction(
                      label: 'Cancel',
                      icon: CupertinoIcons.xmark_circle_fill,
                      color: const Color(0xFFFF9500),
                      reveal: (revealRight * 3 - 0.25).clamp(0.0, 1.0),
                      onTap: _cancelInstallment,
                    ),
                  ),
                  Expanded(
                    child: _SwipeAction(
                      label: 'Delete',
                      icon: CupertinoIcons.trash_fill,
                      color: const Color(0xFFFF3B30),
                      reveal: (revealRight * 3 - 0.5).clamp(0.0, 1.0),
                      onTap: _deleteInstallment,
                    ),
                  ),
                ],
              ),
            ),
            // Left panel (swipe right): Edit — full height via Positioned
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _leftPanelW,
              child: _SwipeAction(
                label: 'Edit',
                icon: CupertinoIcons.pencil,
                color: const Color(0xFF007AFF),
                reveal: revealLeft,
                onTap: _handleEditSwipe,
              ),
            ),
            // Main content (translates with drag); absorbs taps when open to close row
            Transform.translate(
              offset: Offset(_offset, 0),
              child: isOpen
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _close,
                      child: AbsorbPointer(
                        child: Container(
                          color: brand.surface,
                          child: widget.child,
                        ),
                      ),
                    )
                  : Container(color: brand.surface, child: widget.child),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final double reveal; // 0 = hidden, 1 = fully visible
  final VoidCallback onTap;

  const _SwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.reveal,
    required this.onTap,
  });

  @override
  State<_SwipeAction> createState() => _SwipeActionState();
}

class _SwipeActionState extends State<_SwipeAction> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        width: double.infinity,
        height: double.infinity,
        color: _pressed
            ? widget.color.withValues(alpha: 0.72)
            : widget.color,
        child: Transform.scale(
          scale: 0.7 + 0.3 * widget.reveal,
          child: Opacity(
            opacity: widget.reveal.clamp(0.0, 1.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, color: Colors.white, size: 22),
                const SizedBox(height: 4),
                Text(
                  widget.label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
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
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}
