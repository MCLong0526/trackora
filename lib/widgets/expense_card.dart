import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/expense.dart';
import '../services/i18n.dart';
import '../services/money_format.dart';
import '../theme/app_theme.dart';

/// iOS-style expense row.
///
/// Tap → opens [onTap].
/// Swipe right-to-left → red trash background, prompts a Cupertino confirm
/// dialog, then calls [onDelete] when the user confirms.
class ExpenseCard extends StatelessWidget {
  final Expense expense;
  final String currencySymbol;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;
  final VoidCallback? onLongPress;

  const ExpenseCard({
    super.key,
    required this.expense,
    required this.currencySymbol,
    required this.onTap,
    this.onDelete,
    this.onLongPress,
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

  const _CardContents({
    required this.expense,
    required this.currencySymbol,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final style = styleFor(expense.category);
    final isIncome = expense.type == EntryType.income;
    final dateStr = DateFormat('MMM d').format(expense.date);
    final amountColor = isIncome ? brand.income : brand.ink;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(AppRadius.card - 4),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(style.icon, size: 22, color: style.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.categoryLabel(expense.category),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: brand.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    expense.note.isEmpty
                        ? dateStr
                        : '${expense.note} · $dateStr',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: brand.inkSoft),
                  ),
                ],
              ),
            ),
            Row(
              children: [
                Text(
                  isIncome
                      ? formatMoney(
                          currencySymbol,
                          expense.amount,
                          forceSign: true,
                        )
                      : formatMoney(currencySymbol, -expense.amount),
                  style: TextStyle(
                    fontSize: 16,
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
}

class _DeleteBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: AppColors.expense,
        borderRadius: BorderRadius.circular(AppRadius.card - 4),
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
