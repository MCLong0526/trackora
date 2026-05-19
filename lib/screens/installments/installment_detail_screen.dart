import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/account.dart';
import '../../models/expense.dart';
import '../../models/installment.dart';
import '../../repositories/firebase_expense_repository.dart';
import '../../repositories/local_expense_repository.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../services/sync_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'add_edit_installment_screen.dart';

class InstallmentDetailScreen extends ConsumerWidget {
  final String installmentId;
  const InstallmentDetailScreen({super.key, required this.installmentId});

  static final _missing = Installment(
    id: '',
    name: '',
    amount: 0,
    dayOfMonth: 1,
    category: 'Bills',
    startDate: DateTime.fromMillisecondsSinceEpoch(0),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final selectedMonth = ref.watch(selectedMonthProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final itemsAsync = ref.watch(installmentsProvider);

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: itemsAsync.valueOrNull != null
            ? Text(
                itemsAsync.valueOrNull!
                    .firstWhere(
                      (i) => i.id == installmentId,
                      orElse: () => _missing,
                    )
                    .name,
              )
            : const SizedBox.shrink(),
        actions: [
          if (itemsAsync.valueOrNull != null)
            Builder(
              builder: (ctx) {
                final inst = itemsAsync.valueOrNull!.firstWhere(
                  (i) => i.id == installmentId,
                  orElse: () => _missing,
                );
                if (identical(inst, _missing)) return const SizedBox.shrink();
                return IconButton(
                  icon: const Icon(CupertinoIcons.ellipsis_circle, size: 22),
                  onPressed: () => _showActionsSheet(ctx, ref, inst, user?.uid),
                );
              },
            ),
        ],
      ),
      body: itemsAsync.when(
        loading: () => const Center(child: CupertinoActivityIndicator()),
        error: (e, _) =>
            Center(child: Text('${context.t('common.error')}: $e')),
        data: (items) {
          final inst = items.firstWhere(
            (i) => i.id == installmentId,
            orElse: () => _missing,
          );
          if (identical(inst, _missing)) {
            return Center(child: Text(context.t('common.error')));
          }
          return SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
              children: [
                _HeaderCard(inst: inst, symbol: symbol, month: selectedMonth),
                const SizedBox(height: 20),
                _SectionLabel(label: 'PLAN'),
                const SizedBox(height: 8),
                _PlanDetailsCard(inst: inst),
                const SizedBox(height: 16),
                _StatusCard(
                  inst: inst,
                  month: selectedMonth,
                  userId: user?.uid,
                  accounts: ref.watch(accountsProvider).valueOrNull ?? const [],
                ),
                const SizedBox(height: 20),
                _RecentPaymentsSection(inst: inst, symbol: symbol),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showActionsSheet(
    BuildContext context,
    WidgetRef ref,
    Installment inst,
    String? userId,
  ) {
    if (userId == null) return;
    final isActive = inst.status == InstallmentStatus.active;
    final isCancelled = inst.status == InstallmentStatus.cancelled;

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
                  builder: (_) => AddEditInstallmentScreen(installment: inst),
                ),
              );
            },
            child: Text(context.t('inst.edit')),
          ),
          if (isActive)
            CupertinoActionSheetAction(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await ref
                      .read(installmentServiceProvider)
                      .markCompleted(userId, inst);
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      'Marked as completed',
                      type: AppToastType.success,
                    );
                    Navigator.pop(context);
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      'Failed to complete',
                      type: AppToastType.error,
                    );
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
                  await ref
                      .read(installmentServiceProvider)
                      .reactivate(userId, inst);
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      'Reactivated',
                      type: AppToastType.success,
                    );
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      'Failed to reactivate',
                      type: AppToastType.error,
                    );
                  }
                }
              },
              child: Text(context.t('inst.reactivate')),
            ),
          if (!isCancelled)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(ctx);
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
                if (ok == true && context.mounted) {
                  try {
                    await ref
                        .read(installmentServiceProvider)
                        .setCancelled(userId, inst, true);
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        'Installment cancelled',
                        type: AppToastType.success,
                      );
                    }
                  } catch (_) {
                    if (context.mounted) {
                      AppToast.show(
                        context,
                        'Failed to cancel',
                        type: AppToastType.error,
                      );
                    }
                  }
                }
              },
              child: Text(context.t('inst.cancel')),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
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
              if (ok == true && context.mounted) {
                try {
                  await ref
                      .read(installmentServiceProvider)
                      .delete(userId, inst.id);
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      'Installment deleted',
                      type: AppToastType.success,
                    );
                    Navigator.pop(context);
                  }
                } catch (_) {
                  if (context.mounted) {
                    AppToast.show(
                      context,
                      'Failed to delete',
                      type: AppToastType.error,
                    );
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

// ── Helpers ───────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF8E8E93),
        letterSpacing: 0.8,
      ),
    );
  }
}

// ── Header Card ───────────────────────────────────────────────

class _HeaderCard extends StatelessWidget {
  final Installment inst;
  final String symbol;
  final DateTime month;

  const _HeaderCard({
    required this.inst,
    required this.symbol,
    required this.month,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final style = styleFor(inst.category);
    final paid = inst.isPaidIn(month);

    // Split amount into whole + decimal for display
    final raw = formatMoney(symbol, inst.amount);
    final dotIdx = raw.indexOf('.');
    final mainPart = dotIdx >= 0 ? raw.substring(0, dotIdx) : raw;
    final decPart = dotIdx >= 0 ? raw.substring(dotIdx) : '';

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
        ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: style.background,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(style.icon, color: style.accent, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'MONTHLY PAYMENT',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: brand.inkSoft,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      mainPart,
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                        letterSpacing: -1,
                      ),
                    ),
                    if (decPart.isNotEmpty)
                      Text(
                        decPart,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: brand.inkSoft,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: paid
                  ? const Color(0xFFDCFCE7)
                  : const Color(0xFFFEE2E2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              paid ? 'PAID' : 'UNPAID',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: paid
                    ? const Color(0xFF16A34A)
                    : AppColors.expense,
                letterSpacing: 0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Plan Details Card ─────────────────────────────────────────

class _PlanDetailsCard extends StatelessWidget {
  final Installment inst;
  const _PlanDetailsCard({required this.inst});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final next = inst.nextDueDate();
    final rows = <(String, String)>[
      ('Type', inst.isLifetime ? 'Lifetime' : '${inst.totalMonths} months'),
      ('Start date', DateFormat('MMM d, yyyy').format(inst.startDate)),
      ('Months paid', '${inst.paidCount}'),
      if (next != null)
        ('Next payment', DateFormat('MMM d, yyyy').format(next)),
      ('Due day', '${inst.dayOfMonth}${_ordinal(inst.dayOfMonth)} of each month'),
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
                  Text(
                    rows[i].$2,
                    style: TextStyle(
                      fontSize: 15,
                      color: brand.inkSoft,
                      fontWeight: FontWeight.w400,
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

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return 'th';
    return switch (n % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }
}

// ── Status Card ───────────────────────────────────────────────

class _StatusCard extends ConsumerStatefulWidget {
  final Installment inst;
  final DateTime month;
  final String? userId;
  final List<Account> accounts;

  const _StatusCard({
    required this.inst,
    required this.month,
    required this.userId,
    required this.accounts,
  });

  @override
  ConsumerState<_StatusCard> createState() => _StatusCardState();
}

class _StatusCardState extends ConsumerState<_StatusCard> {
  String? _selectedAccountId;

  Future<void> _handleMarkPaid() async {
    if (widget.userId == null) return;
    HapticFeedback.selectionClick();

    // Show account picker if accounts exist
    if (widget.accounts.isNotEmpty) {
      final accountId = await _showAccountPicker();
      if (!mounted) return;
      _selectedAccountId = accountId;
    }

    final svc = ref.read(installmentServiceProvider);
    try {
      // 1. Update installment paidMonths
      await svc.markPaid(widget.userId!, widget.inst, widget.month);

      // 2. Create activity expense with proper offline-first sync
      await _createPaymentExpense(
        userId: widget.userId!,
        inst: widget.inst,
        month: widget.month,
        accountId: _selectedAccountId,
      );

      if (mounted) {
        AppToast.show(context, 'Marked as paid', type: AppToastType.success);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Failed to update payment', type: AppToastType.error);
      }
    }
  }

  /// Creates (or re-upserts) the expense activity record for a payment.
  /// Uses a deterministic ID so marking paid twice doesn't create duplicates.
  Future<void> _createPaymentExpense({
    required String userId,
    required Installment inst,
    required DateTime month,
    String? accountId,
  }) async {
    final key = Installment.monthKey(month);
    // Deterministic ID: stable across retries, prevents duplicates.
    final expenseId = 'inst_${inst.id}_$key';
    final now = DateTime.now();
    final expense = Expense(
      id: expenseId,
      amount: inst.amount,
      category: inst.category,
      note: '${inst.name} (installment)',
      date: inst.dueDateIn(month),
      type: EntryType.expense,
      accountId: accountId,
      createdAt: now,
      updatedAt: now,
      sourceInstallmentId: inst.id,
      sourceMonthKey: key,
    );

    final local = LocalExpenseRepository();
    await local.upsertExpense(userId, expense);

    if (storageMode == StorageMode.firebase) {
      final isOnline = ref.read(isOnlineProvider);
      if (isOnline) {
        try {
          await FirebaseExpenseRepository().upsertExpense(userId, expense);
          await SyncService().clearPending(userId, expenseId);
        } catch (_) {
          await SyncService().markPending(userId, expenseId);
        }
      } else {
        await SyncService().markPending(userId, expenseId);
      }
    }
  }

  /// Deletes the expense activity record for a payment.
  Future<void> _deletePaymentExpense({
    required String userId,
    required Installment inst,
    required DateTime month,
  }) async {
    final key = Installment.monthKey(month);
    final expenseId = 'inst_${inst.id}_$key';
    if (storageMode == StorageMode.firebase) {
      final isOnline = ref.read(isOnlineProvider);
      await SyncService().deleteExpense(
        userId: userId,
        expenseId: expenseId,
        isOnline: isOnline,
      );
    } else {
      await LocalExpenseRepository().deleteExpense(userId, expenseId);
    }
  }

  Future<String?> _showAccountPicker() async {
    final brand = context.brand;
    return showModalBottomSheet<String?>(
      context: context,
      backgroundColor: brand.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        top: false,
        child: SizedBox(
          height: 360,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(
                  'Pay from account',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  'Which account would you like to deduct from?',
                  style: TextStyle(fontSize: 13, color: brand.inkSoft),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      leading: Icon(CupertinoIcons.xmark_circle, color: brand.inkSoft),
                      title: Text('No account', style: TextStyle(color: brand.inkSoft)),
                      trailing: _selectedAccountId == null
                          ? Icon(CupertinoIcons.checkmark_alt, color: brand.accentDark)
                          : null,
                      onTap: () => Navigator.pop(ctx, null),
                    ),
                    ...widget.accounts.map((a) {
                      final isSelected = _selectedAccountId == a.id;
                      return ListTile(
                        leading: Icon(
                          _iconForType(a.type),
                          color: _accentForType(a.type),
                        ),
                        title: Text(
                          a.name,
                          style: TextStyle(
                            color: brand.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(a.type.label, style: TextStyle(color: brand.inkSoft)),
                        trailing: isSelected
                            ? Icon(CupertinoIcons.checkmark_alt, color: brand.accentDark)
                            : null,
                        onTap: () => Navigator.pop(ctx, a.id),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconForType(AccountType type) {
    return switch (type) {
      AccountType.bank => CupertinoIcons.building_2_fill,
      AccountType.eWallet => CupertinoIcons.device_phone_portrait,
      AccountType.cash => CupertinoIcons.money_dollar_circle_fill,
      AccountType.investment => CupertinoIcons.chart_bar_fill,
      AccountType.savings => CupertinoIcons.archivebox_fill,
      AccountType.crypto => CupertinoIcons.bitcoin_circle_fill,
      AccountType.forex => CupertinoIcons.globe,
      AccountType.creditCard => CupertinoIcons.creditcard_fill,
      AccountType.loan => CupertinoIcons.doc_text_fill,
      _ => CupertinoIcons.creditcard,
    };
  }

  Color _accentForType(AccountType type) {
    return switch (type) {
      AccountType.bank => const Color(0xFF2563EB),
      AccountType.eWallet => const Color(0xFF7C3AED),
      AccountType.cash => const Color(0xFF16A34A),
      AccountType.investment => const Color(0xFFD97706),
      AccountType.savings => const Color(0xFF0891B2),
      AccountType.crypto => const Color(0xFFF59E0B),
      AccountType.forex => const Color(0xFF059669),
      AccountType.creditCard => const Color(0xFFDC2626),
      AccountType.loan => const Color(0xFF6B7280),
      _ => const Color(0xFF6B7280),
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.inst.status != InstallmentStatus.active) return const SizedBox.shrink();
    final brand = context.brand;
    final paid = widget.inst.isPaidIn(widget.month);
    final monthLabel = DateFormat('MMM').format(widget.month);
    final next = widget.inst.nextDueDate();
    final nextStr = next != null
        ? 'Next charge on ${DateFormat('MMM d, yyyy').format(next)}'
        : '';

    return GestureDetector(
      onTap: () async {
        if (widget.userId == null) return;
        HapticFeedback.selectionClick();
        final svc = ref.read(installmentServiceProvider);
        try {
          if (paid) {
            await svc.markUnpaid(widget.userId!, widget.inst, widget.month);
            await _deletePaymentExpense(
              userId: widget.userId!,
              inst: widget.inst,
              month: widget.month,
            );
            if (context.mounted) {
              AppToast.show(context, 'Marked as unpaid', type: AppToastType.success);
            }
          } else {
            await _handleMarkPaid();
            return;
          }
        } catch (_) {
          if (context.mounted) {
            AppToast.show(context, 'Failed to update payment', type: AppToastType.error);
          }
        }
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: paid
              ? const Color(0xFFF0FDF4)
              : const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: paid ? AppColors.income : const Color(0xFFF59E0B),
                shape: BoxShape.circle,
              ),
              child: Icon(
                paid ? CupertinoIcons.check_mark : CupertinoIcons.clock,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    paid ? 'Paid for $monthLabel' : 'Unpaid for $monthLabel',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: paid
                          ? AppColors.income
                          : const Color(0xFFD97706),
                    ),
                  ),
                  Text(
                    paid && nextStr.isNotEmpty
                        ? nextStr
                        : widget.accounts.isNotEmpty
                            ? 'Tap to pay • choose account'
                            : 'Tap to mark as paid',
                    style: TextStyle(
                      fontSize: 12,
                      color: brand.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Recent Payments ───────────────────────────────────────────

class _RecentPaymentsSection extends StatelessWidget {
  final Installment inst;
  final String symbol;

  const _RecentPaymentsSection({required this.inst, required this.symbol});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final sorted = [...inst.paidMonths]..sort((a, b) => b.compareTo(a));
    final recent = sorted.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text(
              'RECENT PAYMENTS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
                letterSpacing: 0.8,
              ),
            ),
            const Spacer(),
            if (inst.paidMonths.length > 5)
              const Text(
                'See all',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppActionBlue.color,
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(18),
            ),
          child: recent.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'No payments recorded yet',
                    style: TextStyle(color: brand.inkSoft, fontSize: 13),
                  ),
                )
              : Column(
                  children: [
                    for (int i = 0; i < recent.length; i++) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: _PaymentRow(
                          monthKey: recent[i],
                          amount: inst.amount,
                          symbol: symbol,
                        ),
                      ),
                      if (i < recent.length - 1)
                        Divider(
                          height: 1,
                          color: brand.divider,
                          indent: 16,
                          endIndent: 16,
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

class _PaymentRow extends StatelessWidget {
  final String monthKey;
  final double amount;
  final String symbol;

  const _PaymentRow({
    required this.monthKey,
    required this.amount,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    DateTime? date;
    try {
      final parts = monthKey.split('-');
      if (parts.length >= 2) {
        date = DateTime(int.parse(parts[0]), int.parse(parts[1]), 1);
      }
    } catch (_) {}
    final label =
        date != null ? DateFormat('MMM d, yyyy').format(date) : monthKey;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF22C55E),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: brand.ink,
          ),
        ),
        const Spacer(),
        Text(
          formatMoney(symbol, amount),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: brand.inkSoft,
          ),
        ),
      ],
    );
  }
}

