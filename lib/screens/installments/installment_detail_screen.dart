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
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Icon(
              CupertinoIcons.arrow_up_right_diamond,
              color: const Color(0xFF6366F1),
              size: 22,
            ),
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
                ),
                const SizedBox(height: 20),
                _RecentPaymentsSection(inst: inst, symbol: symbol),
                const SizedBox(height: 28),
                _ActionButtons(inst: inst, userId: user?.uid),
              ],
            ),
          );
        },
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
        fontWeight: FontWeight.w800,
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
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
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
                        fontWeight: FontWeight.w900,
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
                fontWeight: FontWeight.w800,
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
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF6366F1).withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
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

class _StatusCard extends ConsumerWidget {
  final Installment inst;
  final DateTime month;
  final String? userId;

  const _StatusCard({
    required this.inst,
    required this.month,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (inst.status != InstallmentStatus.active) return const SizedBox.shrink();
    final brand = context.brand;
    final paid = inst.isPaidIn(month);
    final monthLabel = DateFormat('MMM').format(month);
    final next = inst.nextDueDate();
    final nextStr = next != null
        ? 'Next charge on ${DateFormat('MMM d, yyyy').format(next)}'
        : '';

    return GestureDetector(
      onTap: () async {
        if (userId == null) return;
        HapticFeedback.selectionClick();
        final svc = ref.read(installmentServiceProvider);
        try {
          if (paid) {
            await svc.markUnpaid(userId!, inst, month);
            if (context.mounted) {
              AppToast.show(context, 'Marked as unpaid', type: AppToastType.success);
            }
          } else {
            await svc.markPaid(userId!, inst, month);
            if (context.mounted) {
              AppToast.show(context, 'Marked as paid', type: AppToastType.success);
            }
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
                fontWeight: FontWeight.w800,
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
                  color: Color(0xFF6366F1),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6366F1).withValues(alpha: 0.04),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
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

// ── Action Buttons ────────────────────────────────────────────

class _ActionButtons extends ConsumerWidget {
  final Installment inst;
  final String? userId;

  const _ActionButtons({required this.inst, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isActive = inst.status == InstallmentStatus.active;
    final isCancelled = inst.status == InstallmentStatus.cancelled;
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _OutlineBtn(
                label: 'Edit',
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) =>
                        AddEditInstallmentScreen(installment: inst),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FilledBtn(
                label: isActive
                    ? 'Mark complete'
                    : isCancelled
                    ? 'Reactivate'
                    : 'Completed',
                color: const Color(0xFF6366F1),
                textColor: Colors.white,
                onTap: isActive
                    ? () async {
                        if (userId == null) return;
                        try {
                          await ref
                              .read(installmentServiceProvider)
                              .markCompleted(userId!, inst);
                          if (context.mounted) {
                            AppToast.show(context, 'Marked as completed', type: AppToastType.success);
                            Navigator.pop(context);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            AppToast.show(context, 'Failed to complete', type: AppToastType.error);
                          }
                        }
                      }
                    : isCancelled
                    ? () async {
                        if (userId == null) return;
                        try {
                          await ref
                              .read(installmentServiceProvider)
                              .reactivate(userId!, inst);
                          if (context.mounted) {
                            AppToast.show(context, 'Reactivated', type: AppToastType.success);
                          }
                        } catch (_) {
                          if (context.mounted) {
                            AppToast.show(context, 'Failed to reactivate', type: AppToastType.error);
                          }
                        }
                      }
                    : () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _FilledBtn(
                label: 'Cancel installment',
                color: const Color(0xFFFEE2E2),
                textColor: AppColors.expense,
                onTap: () => _confirmCancel(context, ref),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FilledBtn(
                label: 'Delete',
                color: const Color(0xFFFEE2E2),
                textColor: AppColors.expense,
                onTap: () => _confirmDelete(context, ref),
              ),
            ),
          ],
        ),
      ],
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
      try {
        await ref
            .read(installmentServiceProvider)
            .setCancelled(userId!, inst, true);
        if (context.mounted) {
          AppToast.show(context, 'Installment cancelled', type: AppToastType.success);
        }
      } catch (_) {
        if (context.mounted) {
          AppToast.show(context, 'Failed to cancel', type: AppToastType.error);
        }
      }
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
      try {
        await ref.read(installmentServiceProvider).delete(userId!, inst.id);
        if (context.mounted) {
          AppToast.show(context, 'Installment deleted', type: AppToastType.success);
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

class _OutlineBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineBtn({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: brand.divider, width: 1.5),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: brand.ink,
          ),
        ),
      ),
    );
  }
}

class _FilledBtn extends StatelessWidget {
  final String label;
  final Color color;
  final Color? textColor;
  final VoidCallback onTap;
  const _FilledBtn({
    required this.label,
    required this.color,
    required this.onTap,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final fg = textColor ?? foregroundOn(color);
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
    );
  }
}
