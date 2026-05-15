import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/borrow_lending.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'add_edit_borrow_lending_screen.dart';
import 'borrow_lending_detail_screen.dart';

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

  @override
  void dispose() {
    _searchCtrl.dispose();
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
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) =>
              Center(child: Text('${context.t('common.error')}: $e')),
          data: (records) {
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
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
                if (records.isEmpty)
                  _EmptyState(onAdd: () => _openAdd(context))
                else ...[
                  for (final r in records.where(_matches))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _BorrowSwipeActions(
                        record: r,
                        userId: user?.uid,
                        child: _RecordTile(record: r, symbol: symbol),
                      ),
                    ),
                  if (records.where(_matches).isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text(
                          context.t('bl.noMatch'),
                          style: TextStyle(color: brand.inkSoft),
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
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
    final fg = foregroundOn(brand.accentDark);
    final filters = <(_Filter, String)>[
      (_Filter.all, context.t('bl.filterAll')),
      (_Filter.borrowed, context.t('bl.filterBorrowed')),
      (_Filter.lent, context.t('bl.filterLent')),
      (_Filter.active, context.t('bl.filterActive')),
      (_Filter.settled, context.t('bl.filterSettled')),
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

class _RecordTile extends StatelessWidget {
  final BorrowLending record;
  final String symbol;
  const _RecordTile({required this.record, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isBorrow = record.type == BorrowLendingType.borrowed;
    final accent = isBorrow ? AppColors.expense : AppColors.income;
    final tint = isBorrow ? AppColors.blush : AppColors.mint;
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      child: Material(
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
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: tint,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(
                        isBorrow
                            ? CupertinoIcons.arrow_down_left
                            : CupertinoIcons.arrow_up_right,
                        color: accent,
                        size: 22,
                      ),
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
                                  record.person.isEmpty
                                      ? context.t('bl.unknownPerson')
                                      : record.person,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              _StatusPill(record: record),
                            ],
                          ),
                          const SizedBox(height: 4),
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
      ),
    );
  }
}

class _BorrowSwipeActions extends ConsumerWidget {
  final BorrowLending record;
  final String? userId;
  final Widget child;

  const _BorrowSwipeActions({
    required this.record,
    required this.userId,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: ValueKey('borrow-swipe-${record.id}'),
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
          Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (_) => AddEditBorrowLendingScreen(record: record),
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
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(
          record.person.isEmpty ? context.t('bl.unknownPerson') : record.person,
        ),
        actions: [
          if (record.status != BorrowLendingStatus.settled &&
              record.status != BorrowLendingStatus.cancelled)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                if (userId == null) return;
                try {
                  await ref
                      .read(borrowLendingServiceProvider)
                      .markSettled(userId!, record);
                  if (context.mounted) {
                    AppToast.show(context, 'Marked as settled', type: AppToastType.success);
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(context, 'Failed to settle', type: AppToastType.error);
                  }
                }
              },
              child: Text(context.t('bl.markSettled')),
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

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
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
    if (ok == true) {
      try {
        await ref.read(borrowLendingServiceProvider).delete(userId!, record.id);
        if (context.mounted) {
          AppToast.show(context, 'Record deleted', type: AppToastType.success);
        }
      } catch (_) {
        if (context.mounted) {
          AppToast.show(context, 'Failed to delete', type: AppToastType.error);
        }
      }
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
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
