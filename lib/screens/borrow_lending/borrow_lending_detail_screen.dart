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
import '../../widgets/receipt_preview.dart';
import 'add_edit_borrow_lending_screen.dart';

/// Detail screen for a single borrow / lending record.
///
/// Subscribes to the live records list and re-resolves the record by
/// id on each rebuild — so partial repayments / status changes
/// reflect immediately, and the screen pops itself if the record was
/// deleted from elsewhere.
class BorrowLendingDetailScreen extends ConsumerWidget {
  final String recordId;
  const BorrowLendingDetailScreen({super.key, required this.recordId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final async = ref.watch(borrowLendingProvider);

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.t('bl.detailTitle')),
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(child: Text('${context.t('common.error')}: $e')),
          data: (records) {
            final r = records.firstWhere(
              (x) => x.id == recordId,
              orElse: () => _missingRecord,
            );
            if (identical(r, _missingRecord)) {
              return Center(
                child: Text(context.t('bl.recordGone')),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _Header(record: r, symbol: symbol),
                const SizedBox(height: 16),
                _DetailsCard(record: r, symbol: symbol),
                if (r.imagePath != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(AppRadius.card),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('bl.proofImage'),
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ReceiptPreview(stored: r.imagePath!, size: 96),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                _RepaymentHistory(record: r, symbol: symbol),
                const SizedBox(height: 22),
                _ActionRow(record: r, symbol: symbol),
              ],
            );
          },
        ),
      ),
    );
  }

  static final _missingRecord = BorrowLending(
    id: '',
    type: BorrowLendingType.borrowed,
    person: '',
    amount: 0,
    date: DateTime.fromMillisecondsSinceEpoch(0),
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class _Header extends StatelessWidget {
  final BorrowLending record;
  final String symbol;
  const _Header({required this.record, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isBorrow = record.type == BorrowLendingType.borrowed;
    final accent = isBorrow ? AppColors.expense : AppColors.income;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            isBorrow ? context.t('bl.borrowedFrom') : context.t('bl.lentTo'),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: brand.inkSoft,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            record.person.isEmpty ? context.t('bl.unknownPerson') : record.person,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('bl.amount'),
                      style: TextStyle(
                        fontSize: 11,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      formatMoney(symbol, record.amount),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ],
                ),
              ),
              Container(width: 1, height: 30, color: brand.divider),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t('bl.remaining'),
                        style: TextStyle(
                          fontSize: 11,
                          color: brand.inkSoft,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        formatMoney(symbol, record.remaining),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: record.progress,
              minHeight: 6,
              backgroundColor: brand.divider,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  final BorrowLending record;
  final String symbol;
  const _DetailsCard({required this.record, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          _row(context, context.t('bl.dateLabel'),
              DateFormat('MMM d, yyyy').format(record.date)),
          if (record.dueDate != null)
            _row(context, context.t('bl.dueDateLabel'),
                DateFormat('MMM d, yyyy').format(record.dueDate!)),
          if (record.note.isNotEmpty)
            _row(context, context.t('bl.note'), record.note),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value) {
    final brand = context.brand;
    return Padding(
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
    );
  }
}

class _RepaymentHistory extends ConsumerWidget {
  final BorrowLending record;
  final String symbol;
  const _RepaymentHistory({required this.record, required this.symbol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.t('bl.history'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              if (record.status != BorrowLendingStatus.cancelled &&
                  record.status != BorrowLendingStatus.settled)
                TextButton(
                  onPressed: () => _addRepayment(context, ref),
                  child: Text(context.t('bl.addRepayment')),
                ),
            ],
          ),
          if (record.repayments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                context.t('bl.noRepayments'),
                style: TextStyle(color: brand.inkSoft, fontSize: 13),
              ),
            )
          else
            for (final r in record.repayments)
              _repaymentRow(context, ref, r),
        ],
      ),
    );
  }

  Widget _repaymentRow(
    BuildContext context,
    WidgetRef ref,
    BorrowLendingRepayment r,
  ) {
    final brand = context.brand;
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
              CupertinoIcons.checkmark,
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
                  formatMoney(symbol, r.amount),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  r.note.isEmpty
                      ? DateFormat('MMM d, yyyy').format(r.date)
                      : '${r.note} · ${DateFormat('MMM d, yyyy').format(r.date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: brand.inkSoft),
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
                    .read(borrowLendingServiceProvider)
                    .removeRepayment(user.uid, record, r.id);
                if (context.mounted) {
                  AppToast.show(context, 'Repayment removed', type: AppToastType.success);
                }
              } catch (_) {
                if (context.mounted) {
                  AppToast.show(context, 'Failed to remove repayment', type: AppToastType.error);
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

  Future<void> _addRepayment(BuildContext context, WidgetRef ref) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final symbol = ref.read(currencySymbolProvider).valueOrNull ?? '\$';
    final ctrl = TextEditingController(
      text: record.remaining.toStringAsFixed(2),
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
                context.t('bl.addRepayment'),
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
    try {
      await ref.read(borrowLendingServiceProvider).addRepayment(
            user.uid,
            record,
            BorrowLendingRepayment(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              amount: amount,
              date: DateTime.now(),
            ),
          );
      if (context.mounted) {
        AppToast.show(context, 'Repayment added', type: AppToastType.success);
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.show(context, 'Failed to add repayment', type: AppToastType.error);
      }
    }
  }
}

class _ActionRow extends ConsumerWidget {
  final BorrowLending record;
  final String symbol;
  const _ActionRow({required this.record, required this.symbol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _ActionBtn(
          icon: CupertinoIcons.pencil,
          label: context.t('common.edit'),
          onTap: () => Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (_) => AddEditBorrowLendingScreen(record: record),
            ),
          ),
        ),
        if (record.status != BorrowLendingStatus.settled &&
            record.status != BorrowLendingStatus.cancelled)
          _ActionBtn(
            icon: CupertinoIcons.check_mark_circled,
            label: context.t('bl.markSettled'),
            onTap: () async {
              final user = ref.read(authStateProvider).valueOrNull;
              if (user == null) return;
              try {
                await ref
                    .read(borrowLendingServiceProvider)
                    .markSettled(user.uid, record);
                if (context.mounted) {
                  AppToast.show(context, 'Marked as settled', type: AppToastType.success);
                }
              } catch (_) {
                if (context.mounted) {
                  AppToast.show(context, 'Failed to settle', type: AppToastType.error);
                }
              }
            },
          ),
        if (record.status == BorrowLendingStatus.cancelled)
          _ActionBtn(
            icon: CupertinoIcons.refresh,
            label: context.t('inst.reactivate'),
            onTap: () async {
              final user = ref.read(authStateProvider).valueOrNull;
              if (user == null) return;
              try {
                await ref
                    .read(borrowLendingServiceProvider)
                    .setCancelled(user.uid, record, false);
                if (context.mounted) {
                  AppToast.show(context, 'Reactivated', type: AppToastType.success);
                }
              } catch (_) {
                if (context.mounted) {
                  AppToast.show(context, 'Failed to reactivate', type: AppToastType.error);
                }
              }
            },
          )
        else if (record.status != BorrowLendingStatus.settled)
          _ActionBtn(
            icon: CupertinoIcons.xmark_circle,
            label: context.t('common.cancel'),
            destructive: true,
            onTap: () async {
              final user = ref.read(authStateProvider).valueOrNull;
              if (user == null) return;
              try {
                await ref
                    .read(borrowLendingServiceProvider)
                    .setCancelled(user.uid, record, true);
                if (context.mounted) {
                  AppToast.show(context, 'Cancelled', type: AppToastType.success);
                }
              } catch (_) {
                if (context.mounted) {
                  AppToast.show(context, 'Failed to cancel', type: AppToastType.error);
                }
              }
            },
          ),
        _ActionBtn(
          icon: CupertinoIcons.trash,
          label: context.t('common.delete'),
          destructive: true,
          onTap: () => _confirmDelete(context, ref),
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
        await ref
            .read(borrowLendingServiceProvider)
            .delete(user.uid, record.id);
        if (context.mounted) {
          AppToast.show(context, 'Record deleted', type: AppToastType.success);
          Navigator.pop(context);
        }
      } catch (_) {
        if (context.mounted) {
          AppToast.show(context, 'Failed to delete', type: AppToastType.error);
        }
      }
    }
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool destructive;
  const _ActionBtn({
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
}
