import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/borrow_lending.dart';
import '../../models/person.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/fading_edge_list.dart';
import '../../widgets/person_avatar.dart';
import 'add_edit_borrow_lending_screen.dart';
import 'borrow_lending_detail_screen.dart';

// Coordinates open/close state across all swipe rows.
class _BlCoordinator extends ValueNotifier<String?> {
  _BlCoordinator() : super(null);
  void openRow(String id) => value = id;
  void closeAll() => value = null;
}

/// Borrow & Lending list screen.
///
/// Layout:
///  • Summary cards: total borrowed, total lent, net position, active count.
///  • Search bar by person name.
///  • Filter chips: all / borrowed / lent / active / settled.
///  • List of cards, each showing person, amount + remaining,
///    status badge, date.
class BorrowLendingScreen extends ConsumerStatefulWidget {
  const BorrowLendingScreen({super.key});

  @override
  ConsumerState<BorrowLendingScreen> createState() =>
      _BorrowLendingScreenState();
}

enum _Filter { all, borrowed, lent, active, settled }

class _BorrowLendingScreenState extends ConsumerState<BorrowLendingScreen> {
  _Filter _filter = _Filter.all;
  final _searchCtrl = TextEditingController();
  final _coordinator = _BlCoordinator();

  @override
  void dispose() {
    _searchCtrl.dispose();
    _coordinator.dispose();
    super.dispose();
  }

  bool _matches(BorrowLending r) {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty && !r.person.toLowerCase().contains(query)) {
      return false;
    }
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.borrowed:
        return r.type == BorrowLendingType.borrowed;
      case _Filter.lent:
        return r.type == BorrowLendingType.lent;
      case _Filter.active:
        return r.status != BorrowLendingStatus.settled &&
            r.status != BorrowLendingStatus.cancelled;
      case _Filter.settled:
        return r.status == BorrowLendingStatus.settled;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final async = ref.watch(borrowLendingProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final people = ref.watch(peopleProvider).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.t('bl.title')),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.add),
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => const AddEditBorrowLendingScreen(),
              ),
            ),
          ),
        ],
      ),
      body: GestureDetector(
        onTap: _coordinator.closeAll,
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
        child: async.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) =>
              Center(child: Text('${context.t('common.error')}: $e')),
          data: (records) {
            final filtered = records.where(_matches).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Fixed header (summary + search + filter) — does not scroll
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SummaryRow(records: records, symbol: symbol),
                      const SizedBox(height: 14),
                      _SearchBar(
                        controller: _searchCtrl,
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      _FilterChips(
                        selected: _filter,
                        onSelected: (f) => setState(() => _filter = f),
                      ),
                      const SizedBox(height: 14),
                    ],
                  ),
                ),
                // Scrollable list only, with fade edges
                Expanded(
                  child: FadingEdgeList(
                    fadeColor: brand.background,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                      children: [
                        if (records.isEmpty)
                          _EmptyState(onAdd: () => _openAdd(context))
                        else if (filtered.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                context.t('bl.noMatch'),
                                style: TextStyle(color: brand.inkSoft),
                              ),
                            ),
                          )
                        else
                          Column(
                            children: [
                              for (int i = 0; i < filtered.length; i++)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: _EntranceItem(
                                    key: ValueKey(filtered[i].id),
                                    delay: Duration(milliseconds: i * 45),
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: brand.surface,
                                        borderRadius: BorderRadius.circular(AppRadius.card),
                                      ),
                                      child: ClipRRect(
                                        borderRadius: BorderRadius.circular(AppRadius.card),
                                        child: _BorrowSwipeActions(
                                          record: filtered[i],
                                          userId: user?.uid,
                                          coordinator: _coordinator,
                                          child: _RecordTile(
                                            record: filtered[i],
                                            symbol: symbol,
                                            matchedPerson: people
                                                .where((p) =>
                                                    p.name.toLowerCase() ==
                                                    filtered[i].person.toLowerCase())
                                                .firstOrNull,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
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

  void _openAdd(BuildContext context) {
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => const AddEditBorrowLendingScreen()),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final List<BorrowLending> records;
  final String symbol;
  const _SummaryRow({required this.records, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final active = records
        .where(
          (r) =>
              r.status != BorrowLendingStatus.cancelled &&
              r.status != BorrowLendingStatus.settled,
        )
        .toList();
    final borrowed = active
        .where((r) => r.type == BorrowLendingType.borrowed)
        .fold<double>(0, (s, r) => s + r.remaining);
    final lent = active
        .where((r) => r.type == BorrowLendingType.lent)
        .fold<double>(0, (s, r) => s + r.remaining);
    final net = lent - borrowed;
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _SumStat(
                  label: context.t('bl.totalBorrowed'),
                  value: formatMoney(symbol, borrowed),
                  color: AppColors.expense,
                ),
              ),
              Container(width: 1, height: 30, color: brand.divider),
              Expanded(
                child: _SumStat(
                  label: context.t('bl.totalLent'),
                  value: formatMoney(symbol, lent),
                  color: AppColors.income,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 0.5, color: brand.divider),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SumStat(
                  label: context.t('bl.netPosition'),
                  value:
                      '${net >= 0 ? '+' : '−'}${formatMoney(symbol, net.abs())}',
                  color: net >= 0 ? AppColors.income : AppColors.expense,
                ),
              ),
              Container(width: 1, height: 30, color: brand.divider),
              Expanded(
                child: _SumStat(
                  label: context.t('bl.activeCount'),
                  value: '${active.length}',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SumStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _SumStat({required this.label, required this.value, this.color});

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
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color ?? brand.ink,
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  const _SearchBar({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Row(
        children: [
          Icon(CupertinoIcons.search, size: 16, color: brand.inkSoft),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              decoration: InputDecoration(
                hintText: context.t('bl.searchHint'),
                border: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged('');
              },
              child: Icon(
                CupertinoIcons.clear_circled_solid,
                size: 16,
                color: brand.inkSoft,
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
    final filters = <(_Filter, String)>[
      (_Filter.all, context.t('bl.filterAll')),
      (_Filter.borrowed, context.t('bl.filterBorrowed')),
      (_Filter.lent, context.t('bl.filterLent')),
      (_Filter.active, context.t('bl.filterActive')),
      (_Filter.settled, context.t('bl.filterSettled')),
    ];
    final selectedIdx = filters.indexWhere((f) => f.$1 == selected);
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final pillW = (constraints.maxWidth - 8) / filters.length;
        return GestureDetector(
          onHorizontalDragUpdate: (details) {
            const padding = 4.0;
            final newIdx = ((details.localPosition.dx - padding) / pillW)
                .floor()
                .clamp(0, filters.length - 1);
            final newFilter = filters[newIdx].$1;
            if (newFilter == selected) return;
            HapticFeedback.selectionClick();
            onSelected(newFilter);
          },
          behavior: HitTestBehavior.translucent,
          child: Container(
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
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelected(f);
                        },
                        child: Container(
                          alignment: Alignment.center,
                          color: Colors.transparent,
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: f == selected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color:
                                  f == selected ? brand.ink : brand.inkSoft,
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
          ),
        );
      },
    );
  }
}

class _RecordTile extends StatelessWidget {
  final BorrowLending record;
  final String symbol;
  final Person? matchedPerson;
  const _RecordTile({
    required this.record,
    required this.symbol,
    this.matchedPerson,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isBorrow = record.type == BorrowLendingType.borrowed;
    final accent = isBorrow ? AppColors.expense : AppColors.income;
    final tint = isBorrow ? AppColors.blush : AppColors.mint;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.card),
          onTap: () => Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (_) => BorrowLendingDetailScreen(recordId: record.id),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        PersonAvatar(
                          name: record.person.isEmpty ? '?' : record.person,
                          emoji: matchedPerson?.emoji,
                          colorIndex: matchedPerson?.colorIndex,
                          size: 44,
                        ),
                        Positioned(
                          bottom: -2,
                          right: -4,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: tint,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: brand.surface,
                                width: 1.5,
                              ),
                            ),
                            child: Icon(
                              isBorrow
                                  ? CupertinoIcons.arrow_down_left
                                  : CupertinoIcons.arrow_up_right,
                              color: accent,
                              size: 10,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record.person.isEmpty
                                ? context.t('bl.unknownPerson')
                                : record.person,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              _StatusPill(record: record),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('MMM d, yyyy').format(record.date),
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
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          formatMoney(symbol, record.amount),
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isBorrow
                              ? context.t('bl.borrowedLabel')
                              : context.t('bl.lentLabel'),
                          style: TextStyle(
                            fontSize: 10,
                            color: brand.inkSoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                if (record.amount > 0 && record.repaid > 0) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: record.progress,
                      minHeight: 5,
                      backgroundColor: brand.divider,
                      valueColor: AlwaysStoppedAnimation(accent),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    context
                        .t('bl.remainingLine')
                        .replaceFirst(
                          '{amount}',
                          formatMoney(symbol, record.remaining),
                        ),
                    style: TextStyle(
                      fontSize: 11,
                      color: brand.inkSoft,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
    );
  }
}

// ── Swipe actions (matches installment / saving-plan pattern) ─────────────────

class _BorrowSwipeActions extends ConsumerStatefulWidget {
  final BorrowLending record;
  final String? userId;
  final Widget child;
  final _BlCoordinator coordinator;

  const _BorrowSwipeActions({
    required this.record,
    required this.userId,
    required this.child,
    required this.coordinator,
  });

  @override
  ConsumerState<_BorrowSwipeActions> createState() =>
      _BorrowSwipeActionsState();
}

class _BorrowSwipeActionsState extends ConsumerState<_BorrowSwipeActions>
    with SingleTickerProviderStateMixin {
  // Right panel: settle + delete = 2 × 88 = 176; left panel: 88.
  static const double _rightPanelW = 176.0;
  static const double _leftPanelW = 88.0;

  late final AnimationController _ctrl;
  late final CurvedAnimation _curve;
  double _offset = 0;
  double _dragStartOffset = 0;
  double _animStart = 0;
  double _animTarget = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _curve = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
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
    if (widget.coordinator.value != widget.record.id && _offset != 0) {
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
    _dragStartOffset = _offset;
    widget.coordinator.openRow(widget.record.id);
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() {
      _offset = (_offset + d.delta.dx).clamp(-_rightPanelW, _leftPanelW);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final v = d.primaryVelocity ?? 0;
    final rightInvolved = _dragStartOffset < 0 || (_dragStartOffset == 0 && _offset < 0);
    if (rightInvolved) {
      (_offset < -_rightPanelW * 0.35 || v < -500)
          ? _springAnimate(-_rightPanelW)
          : _springAnimate(0);
    } else {
      (_offset > _leftPanelW * 0.35 || v > 500)
          ? _springAnimate(_leftPanelW)
          : _springAnimate(0);
    }
  }

  Future<void> _handleEditSwipe() async {
    HapticFeedback.selectionClick();
    _close();
    await Future.delayed(const Duration(milliseconds: 200));
    if (!mounted) return;
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => AddEditBorrowLendingScreen(record: widget.record),
      ),
    );
  }

  Future<void> _settleRecord() async {
    _close();
    HapticFeedback.selectionClick();
    final userId = widget.userId;
    if (userId == null) return;
    if (widget.record.status == BorrowLendingStatus.settled ||
        widget.record.status == BorrowLendingStatus.cancelled) {
      if (mounted) {
        AppToast.show(context, 'Already settled or cancelled',
            type: AppToastType.error);
      }
      return;
    }
    try {
      await ref
          .read(borrowLendingServiceProvider)
          .markSettled(userId, widget.record);
      if (mounted) {
        AppToast.show(context, 'Marked as settled', type: AppToastType.success);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Failed to settle', type: AppToastType.error);
      }
    }
  }

  Future<void> _deleteRecord() async {
    _close();
    HapticFeedback.selectionClick();
    final userId = widget.userId;
    if (userId == null) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('bl.deleteTitle')),
        content: Text(context.t('bl.deleteMessage')),
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
            .read(borrowLendingServiceProvider)
            .delete(userId, widget.record.id);
        if (mounted) {
          AppToast.show(context, 'Record deleted', type: AppToastType.success);
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
    final canSettle = widget.record.status != BorrowLendingStatus.settled &&
        widget.record.status != BorrowLendingStatus.cancelled;

    return ClipRect(
      child: GestureDetector(
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        child: Stack(
          children: [
            // Right panel (swipe left): Settle / Delete
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              width: _rightPanelW,
              child: Row(
                children: [
                  if (canSettle)
                    Expanded(
                      child: _BlSwipeAction(
                        label: context.t('bl.markSettled'),
                        icon: CupertinoIcons.checkmark_circle_fill,
                        color: const Color.fromARGB(200, 52, 199, 89),
                        reveal: canSettle
                            ? (revealRight * 2).clamp(0.0, 1.0)
                            : revealRight,
                        onTap: _settleRecord,
                      ),
                    ),
                  Expanded(
                    child: _BlSwipeAction(
                      label: context.t('common.delete'),
                      icon: CupertinoIcons.trash_fill,
                      color: const Color.fromARGB(200, 255, 69, 58),
                      reveal: canSettle
                          ? (revealRight * 2 - 0.3).clamp(0.0, 1.0)
                          : revealRight,
                      onTap: _deleteRecord,
                    ),
                  ),
                ],
              ),
            ),
            // Left panel (swipe right): Edit
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: _leftPanelW,
              child: _BlSwipeAction(
                label: context.t('common.edit'),
                icon: CupertinoIcons.pencil,
                color: const Color.fromARGB(200, 0, 122, 255),
                reveal: revealLeft,
                onTap: _handleEditSwipe,
              ),
            ),
            // Main content
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

class _BlSwipeAction extends StatefulWidget {
  final String label;
  final IconData icon;
  final Color color;
  final double reveal;
  final VoidCallback onTap;

  const _BlSwipeAction({
    required this.label,
    required this.icon,
    required this.color,
    required this.reveal,
    required this.onTap,
  });

  @override
  State<_BlSwipeAction> createState() => _BlSwipeActionState();
}

class _BlSwipeActionState extends State<_BlSwipeAction> {
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
            ? widget.color.withValues(alpha: widget.color.a * 0.7)
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
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final BorrowLending record;
  const _StatusPill({required this.record});

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg) = switch (record.status) {
      BorrowLendingStatus.active => (
        context.t('bl.statusActive'),
        AppColors.sky,
        AppColors.ink,
      ),
      BorrowLendingStatus.partial => (
        context.t('bl.statusPartial'),
        AppColors.butter,
        AppColors.ink,
      ),
      BorrowLendingStatus.settled => (
        context.t('bl.statusSettled'),
        AppColors.mint,
        AppColors.income,
      ),
      BorrowLendingStatus.cancelled => (
        context.t('bl.statusCancelled'),
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
        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }
}

class _EntranceItem extends StatefulWidget {
  final Widget child;
  final Duration delay;
  const _EntranceItem({required this.child, required this.delay, super.key});

  @override
  State<_EntranceItem> createState() => _EntranceItemState();
}

class _EntranceItemState extends State<_EntranceItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    Future.delayed(widget.delay, () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _ctrl,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.12),
          end: Offset.zero,
        ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic)),
        child: widget.child,
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
              color: AppColors.lilac,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              CupertinoIcons.arrow_up_arrow_down,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.t('bl.emptyTitle'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            context.t('bl.emptyHint'),
            textAlign: TextAlign.center,
            style: TextStyle(color: brand.inkSoft, fontSize: 12),
          ),
          const SizedBox(height: 18),
          FilledButton(onPressed: onAdd, child: Text(context.t('bl.add'))),
        ],
      ),
    );
  }
}
