import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/borrow_lending.dart';
import '../../models/person.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../services/prefs_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/person_avatar.dart';
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
    final mainCode = ref.watch(currencyCodeProvider).valueOrNull ?? 'MYR';
    final async = ref.watch(borrowLendingProvider);
    final people = ref.watch(peopleProvider).valueOrNull ?? [];

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.t('bl.detailTitle')),
        actions: [
          async.whenData((records) {
            final r = records.firstWhere(
              (x) => x.id == recordId,
              orElse: () => _missingRecord,
            );
            if (identical(r, _missingRecord)) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(CupertinoIcons.ellipsis_circle),
              onPressed: () {
                HapticFeedback.mediumImpact();
                _showActions(context, ref, r);
              },
            );
          }).valueOrNull ??
              const SizedBox.shrink(),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) =>
              Center(child: Text('${context.t('common.error')}: $e')),
          data: (records) {
            final r = records.firstWhere(
              (x) => x.id == recordId,
              orElse: () => _missingRecord,
            );
            if (identical(r, _missingRecord)) {
              return Center(child: Text(context.t('bl.recordGone')));
            }

            final effectiveCode = r.currency ?? mainCode;
            final symbol =
                kSupportedCurrencies[effectiveCode] ?? effectiveCode;

            final matched = people
                .where((p) =>
                    p.name.toLowerCase() == r.person.toLowerCase())
                .firstOrNull;

            return ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _HeroCard(
                  record: r,
                  symbol: symbol,
                  matchedPerson: matched,
                ),
                const SizedBox(height: 14),
                _DetailsCard(record: r),
                if (r.imagePath != null) ...[
                  const SizedBox(height: 14),
                  _ProofCard(imagePath: r.imagePath!),
                ],
                const SizedBox(height: 14),
                _RepaymentCard(record: r, symbol: symbol),
              ],
            );
          },
        ),
      ),
    );
  }

  void _showActions(
      BuildContext context, WidgetRef ref, BorrowLending record) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) {
        return CupertinoActionSheet(
          actions: [
            // Edit
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) =>
                        AddEditBorrowLendingScreen(record: record),
                  ),
                );
              },
              child: Text(context.t('common.edit')),
            ),
            // Mark settled (if active or partial)
            if (record.status == BorrowLendingStatus.active ||
                record.status == BorrowLendingStatus.partial)
              CupertinoActionSheetAction(
                onPressed: () async {
                  Navigator.pop(ctx);
                  HapticFeedback.mediumImpact();
                  final user =
                      ref.read(authStateProvider).valueOrNull;
                  if (user == null) return;
                  try {
                    await ref
                        .read(borrowLendingServiceProvider)
                        .markSettled(user.uid, record);
                    if (context.mounted) {
                      AppToast.show(context, 'Marked as settled',
                          type: AppToastType.success);
                    }
                  } catch (_) {
                    if (context.mounted) {
                      AppToast.show(context, 'Failed to settle',
                          type: AppToastType.error);
                    }
                  }
                },
                child: Text(context.t('bl.markSettled')),
              ),
            // Cancel / Reactivate
            if (record.status == BorrowLendingStatus.cancelled)
              CupertinoActionSheetAction(
                onPressed: () async {
                  Navigator.pop(ctx);
                  HapticFeedback.mediumImpact();
                  final user =
                      ref.read(authStateProvider).valueOrNull;
                  if (user == null) return;
                  try {
                    await ref
                        .read(borrowLendingServiceProvider)
                        .setCancelled(user.uid, record, false);
                    if (context.mounted) {
                      AppToast.show(context, 'Reactivated',
                          type: AppToastType.success);
                    }
                  } catch (_) {
                    if (context.mounted) {
                      AppToast.show(context, 'Failed to reactivate',
                          type: AppToastType.error);
                    }
                  }
                },
                child: Text(context.t('inst.reactivate')),
              )
            else if (record.status != BorrowLendingStatus.settled)
              CupertinoActionSheetAction(
                isDestructiveAction: true,
                onPressed: () async {
                  Navigator.pop(ctx);
                  HapticFeedback.mediumImpact();
                  final user =
                      ref.read(authStateProvider).valueOrNull;
                  if (user == null) return;
                  try {
                    await ref
                        .read(borrowLendingServiceProvider)
                        .setCancelled(user.uid, record, true);
                    if (context.mounted) {
                      AppToast.show(context, 'Cancelled',
                          type: AppToastType.success);
                    }
                  } catch (_) {
                    if (context.mounted) {
                      AppToast.show(context, 'Failed to cancel',
                          type: AppToastType.error);
                    }
                  }
                },
                child: Text(context.t('common.cancel')),
              ),
            // Delete
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(ctx);
                HapticFeedback.mediumImpact();
                await _confirmDelete(context, ref, record);
              },
              child: Text(context.t('common.delete')),
            ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.t('common.cancel')),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, BorrowLending record) async {
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
          AppToast.show(context, 'Record deleted',
              type: AppToastType.success);
          Navigator.pop(context);
        }
      } catch (_) {
        if (context.mounted) {
          AppToast.show(context, 'Failed to delete',
              type: AppToastType.error);
        }
      }
    }
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

// ---------------------------------------------------------------------------
// _StatusBadge
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final BorrowLendingStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status) {
      BorrowLendingStatus.active => (
          AppColors.mint,
          AppColors.income,
          'Active',
        ),
      BorrowLendingStatus.partial => (
          AppColors.butter,
          const Color(0xFFB36200),
          'Partial',
        ),
      BorrowLendingStatus.settled => (
          AppColors.mint,
          AppColors.income,
          'Settled',
        ),
      BorrowLendingStatus.cancelled => (
          AppColors.blush,
          AppColors.expense,
          'Cancelled',
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _HeroCard
// ---------------------------------------------------------------------------

class _HeroCard extends StatelessWidget {
  final BorrowLending record;
  final String symbol;
  final Person? matchedPerson;
  const _HeroCard({
    required this.record,
    required this.symbol,
    required this.matchedPerson,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isBorrow = record.type == BorrowLendingType.borrowed;
    final accent = isBorrow ? AppColors.expense : AppColors.income;
    final directionBg = isBorrow
        ? AppColors.blush
        : AppColors.mint;
    final directionFg = isBorrow ? AppColors.expense : AppColors.income;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Direction chip
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: directionBg,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              isBorrow
                  ? context.t('bl.borrowedFrom').toUpperCase()
                  : context.t('bl.lentTo').toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: directionFg,
                letterSpacing: 0.8,
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Avatar + Name + Status
          Row(
            children: [
              PersonAvatar(
                name: record.person.isEmpty
                    ? context.t('bl.unknownPerson')
                    : record.person,
                emoji: matchedPerson?.emoji,
                colorIndex: matchedPerson?.colorIndex,
                size: 52,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      record.person.isEmpty
                          ? context.t('bl.unknownPerson')
                          : record.person,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _StatusBadge(status: record.status),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          // Large amount
          Text(
            formatMoney(symbol, record.amount),
            style: TextStyle(
              fontSize: 34,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 14),
          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: record.progress,
              minHeight: 6,
              backgroundColor: brand.divider,
              valueColor: AlwaysStoppedAnimation(accent),
            ),
          ),
          const SizedBox(height: 12),
          // Remaining row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.t('bl.remaining'),
                style: TextStyle(
                  fontSize: 12,
                  color: brand.inkSoft,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                formatMoney(symbol, record.remaining),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _DetailsCard
// ---------------------------------------------------------------------------

class _DetailsCard extends StatelessWidget {
  final BorrowLending record;
  const _DetailsCard({required this.record});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final rows = <_DetailRow>[
      _DetailRow(
        icon: CupertinoIcons.calendar,
        label: context.t('bl.dateLabel'),
        value: DateFormat('MMM d, yyyy').format(record.date),
      ),
      if (record.dueDate != null)
        _DetailRow(
          icon: CupertinoIcons.alarm,
          label: context.t('bl.dueDateLabel'),
          value: DateFormat('MMM d, yyyy').format(record.dueDate!),
        ),
      if (record.note.isNotEmpty)
        _DetailRow(
          icon: CupertinoIcons.text_bubble,
          label: context.t('bl.note'),
          value: record.note,
        ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        children: [
          for (int i = 0; i < rows.length; i++) ...[
            _buildRow(context, rows[i]),
            if (i < rows.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: brand.divider,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, _DetailRow row) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(row.icon, size: 16, color: brand.inkSoft),
          const SizedBox(width: 10),
          Text(
            row.label,
            style: TextStyle(
              fontSize: 13,
              color: brand.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              row.value,
              textAlign: TextAlign.right,
              style: TextStyle(
                fontSize: 13,
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

class _DetailRow {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow(
      {required this.icon, required this.label, required this.value});
}

// ---------------------------------------------------------------------------
// _ProofCard
// ---------------------------------------------------------------------------

class _ProofCard extends StatelessWidget {
  final String imagePath;
  const _ProofCard({required this.imagePath});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.photo, size: 15, color: brand.inkSoft),
              const SizedBox(width: 8),
              Text(
                context.t('bl.proofImage'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: brand.inkSoft,
                  letterSpacing: 0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ReceiptPreview(stored: imagePath, size: 96),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// _RepaymentCard
// ---------------------------------------------------------------------------

class _RepaymentCard extends ConsumerWidget {
  final BorrowLending record;
  final String symbol;
  const _RepaymentCard({required this.record, required this.symbol});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final canAddRepayment =
        record.status != BorrowLendingStatus.cancelled &&
            record.status != BorrowLendingStatus.settled;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                context.t('bl.history').toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 11,
                  letterSpacing: 0.8,
                  color: brand.inkSoft,
                ),
              ),
              const Spacer(),
              if (canAddRepayment)
                CupertinoButton(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  onPressed: () => _addRepayment(context, ref),
                  child: Text(
                    context.t('bl.addRepayment'),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Empty state
          if (record.repayments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Text(
                context.t('bl.noRepayments'),
                style:
                    TextStyle(color: brand.inkSoft, fontSize: 13),
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
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.mint,
              borderRadius: BorderRadius.circular(10),
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
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: brand.ink,
                  ),
                ),
                Text(
                  r.note.isEmpty
                      ? DateFormat('MMM d, yyyy').format(r.date)
                      : '${r.note} · ${DateFormat('MMM d, yyyy').format(r.date)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11, color: brand.inkSoft),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () async {
              HapticFeedback.mediumImpact();
              final user =
                  ref.read(authStateProvider).valueOrNull;
              if (user == null) return;
              try {
                await ref
                    .read(borrowLendingServiceProvider)
                    .removeRepayment(user.uid, record, r.id);
                if (context.mounted) {
                  AppToast.show(context, 'Repayment removed',
                      type: AppToastType.success);
                }
              } catch (_) {
                if (context.mounted) {
                  AppToast.show(context, 'Failed to remove repayment',
                      type: AppToastType.error);
                }
              }
            },
            child: Padding(
              padding: const EdgeInsets.all(6),
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
    final sym = symbol;
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
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true),
                decoration:
                    InputDecoration(prefixText: '$sym  '),
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
        AppToast.show(context, 'Repayment added',
            type: AppToastType.success);
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.show(context, 'Failed to add repayment',
            type: AppToastType.error);
      }
    }
  }
}
