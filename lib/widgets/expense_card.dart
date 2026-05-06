import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/expense.dart';
import '../services/i18n.dart';
import '../services/money_format.dart';
import '../theme/app_theme.dart';

/// iOS-style expense row.
class ExpenseCard extends StatelessWidget {
  final Expense expense;
  final String currencySymbol;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;
  final VoidCallback? onLongPress;
  final Account? account;

  const ExpenseCard({
    super.key,
    required this.expense,
    required this.currencySymbol,
    required this.onTap,
    this.onDelete,
    this.onLongPress,
    this.account,
  });

  @override
  Widget build(BuildContext context) {
    final card = _CardContents(
      expense: expense,
      currencySymbol: currencySymbol,
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: onLongPress,
      account: account,
    );

    if (onDelete == null) return card;

    return Dismissible(
      key: ValueKey('expense-${expense.id}'),
      direction: DismissDirection.endToStart,
      background: const SizedBox.shrink(),
      secondaryBackground: _DeleteBackground(),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        final ok = await showCupertinoDialog<bool>(
          context: context,
          builder: (ctx) => CupertinoAlertDialog(
            title: Text(context.t('expense.deleteTitle')),
            content: Text(
              context
                  .t('expense.deleteMessage')
                  .replaceFirst(
                    '{category}',
                    context.categoryLabel(expense.category),
                  )
                  .replaceFirst(
                    '{amount}',
                    formatMoney(currencySymbol, expense.amount),
                  ),
            ),
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
          HapticFeedback.heavyImpact();
          await onDelete!();
          return true;
        }
        return false;
      },
      child: card,
    );
  }
}

class _CardContents extends StatelessWidget {
  final Expense expense;
  final String currencySymbol;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Account? account;

  const _CardContents({
    required this.expense,
    required this.currencySymbol,
    required this.onTap,
    this.onLongPress,
    this.account,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isTransfer = expense.type == EntryType.transfer;
    final isReceive = expense.type == EntryType.receive;
    final isIncome = expense.type == EntryType.income;
    final isTransferType = isTransfer || isReceive;

    final style = isTransferType
        ? (isTransfer
              ? CategoryStyle(
                  background: AppColors.blush,
                  accent: AppColors.expense,
                  icon: CupertinoIcons.arrow_right_arrow_left_circle_fill,
                )
              : CategoryStyle(
                  background: AppColors.sky,
                  accent: const Color(0xFF2A6FB5),
                  icon: CupertinoIcons.arrow_right_arrow_left_circle_fill,
                ))
        : styleFor(expense.category);

    final amountColor = (isIncome || isReceive) ? brand.income : brand.ink;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(
      expense.date.year,
      expense.date.month,
      expense.date.day,
    );
    final dateStr = d == today
        ? 'Today'
        : d == yesterday
        ? 'Yesterday'
        : DateFormat('MMM d').format(expense.date);

    String title;
    String subtitle;

    if (isTransferType) {
      final cp = expense.counterpart?.trim() ?? '';
      if (isTransfer) {
        title = cp.isNotEmpty ? 'Transfer → $cp' : 'Transfer';
      } else {
        title = cp.isNotEmpty ? 'Receive ← $cp' : 'Receive';
      }
      subtitle = _buildSubtitle(dateStr, account);
    } else {
      final note = expense.note.trim();
      title = note.isEmpty
          ? context.categoryLabel(expense.category)
          : '${context.categoryLabel(expense.category)} · $note';
      subtitle = _buildSubtitle(dateStr, account);
    }

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(18),
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
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(style.icon, size: 20, color: style.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: brand.inkSoft,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Text(
                  (isIncome || isReceive)
                      ? formatMoney(
                          currencySymbol,
                          expense.amount,
                          forceSign: true,
                        )
                      : formatMoney(currencySymbol, -expense.amount),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: amountColor,
                  ),
                ),
                if (expense.receiptUrl != null) ...[
                  const SizedBox(width: 6),
                  Icon(
                    CupertinoIcons.paperclip,
                    size: 14,
                    color: brand.inkSoft,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _buildSubtitle(String dateStr, Account? acct) {
    if (acct != null) return '$dateStr · ${acct.name}';
    return dateStr;
  }
}

class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: AppColors.expense,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(CupertinoIcons.delete, color: Colors.white, size: 22),
          const SizedBox(width: 8),
          Text(
            context.t('common.delete'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
