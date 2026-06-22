import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../models/account.dart';
import '../models/expense.dart';
import '../services/i18n.dart';
import '../services/prefs_service.dart';
import '../services/money_format.dart';
import '../theme/app_theme.dart';

/// iOS-style expense row with two-action swipe.
///
/// Right-to-left: reveals Edit + Delete buttons.
/// Left-to-right: triggers copy action.
///
/// Call [ExpenseCard.closeAll] from a scroll listener to dismiss any open row.
class ExpenseCard extends StatefulWidget {
  /// Closes any currently-open swipe row across all visible ExpenseCards.
  static void closeAll() => _ExpenseCardState._closeAllOpen();
  final Expense expense;
  final String currencySymbol;
  final VoidCallback onTap;
  final Future<void> Function()? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onCopy;
  final VoidCallback? onLongPress;
  final Account? account;

  /// When true, renders as a flat row (no outer card decoration).
  final bool flat;

  /// When true, shows a small split-bill indicator in the trailing row.
  final bool hasSplitBill;

  /// Number of people who still owe on this expense's split bill. When > 0 a
  /// badge is shown so the user knows money is still outstanding.
  final int splitUnsettledCount;

  /// Optional coordinator for one-at-a-time swipe behavior.
  final ValueNotifier<String?>? coordinator;

  /// Unique ID for this row within the coordinator.
  final String? rowId;

  const ExpenseCard({
    super.key,
    required this.expense,
    required this.currencySymbol,
    required this.onTap,
    this.onDelete,
    this.onEdit,
    this.onCopy,
    this.onLongPress,
    this.account,
    this.flat = false,
    this.hasSplitBill = false,
    this.splitUnsettledCount = 0,
    this.coordinator,
    this.rowId,
  });

  @override
  State<ExpenseCard> createState() => _ExpenseCardState();
}

class _ExpenseCardState extends State<ExpenseCard>
    with SingleTickerProviderStateMixin {
  static final Set<_ExpenseCardState> _openInstances = {};

  static void _closeAllOpen() {
    for (final s in Set.of(_openInstances)) {
      if (s.mounted) s._closeActions();
    }
  }

  late AnimationController _controller;
  late Animation<double> _offsetAnimation;

  // Width of the right-action panel (Edit + Delete)
  static const double _rightActionWidth = 140.0;
  // Width of the left-action panel (Copy)
  static const double _leftActionWidth = 80.0;
  // Threshold beyond which a swipe is "committed" to snap open
  static const double _snapThreshold = 60.0;

  double _dragOffset = 0.0;
  double _dragStartOffset = 0.0;
  // -1 = sliding left (reveal right actions), 1 = sliding right (reveal left actions), 0 = neutral
  int _direction = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _offsetAnimation = Tween<double>(begin: 0, end: 0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    widget.coordinator?.addListener(_onCoordChange);
  }

  @override
  void dispose() {
    _openInstances.remove(this);
    widget.coordinator?.removeListener(_onCoordChange);
    _controller.dispose();
    super.dispose();
  }

  void _onCoordChange() {
    if (widget.coordinator!.value != widget.rowId && _dragOffset != 0) {
      _closeActions();
    }
  }

  void _onHorizontalDragStart(DragStartDetails _) {
    _controller.stop();
    _dragOffset = _offsetAnimation.value;
    _dragStartOffset = _dragOffset;
    _direction = 0;
    widget.coordinator?.value = widget.rowId;
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (_direction == 0) {
      if (details.delta.dx < 0) _direction = -1; // right actions
      if (details.delta.dx > 0) _direction = 1; // left actions (copy)
    }

    setState(() {
      _dragOffset += details.delta.dx;
      if (_dragStartOffset < 0 || _direction == -1) {
        _dragOffset = _dragOffset.clamp(-_rightActionWidth, 0.0);
      } else {
        _dragOffset = _dragOffset.clamp(0.0, _leftActionWidth);
      }
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldOpen = _dragOffset.abs() > _snapThreshold || velocity.abs() > 300;

    final rightInvolved = _dragStartOffset < 0 || (_direction == -1 && _dragStartOffset == 0);
    if (rightInvolved) {
      // Right panel: snap open or close
      if (shouldOpen && (widget.onDelete != null || widget.onEdit != null)) {
        _animateTo(-_rightActionWidth);
      } else {
        _animateTo(0);
      }
    } else {
      // Left panel: snap open — user must tap the button to copy
      if (shouldOpen && widget.onCopy != null) {
        _animateTo(_leftActionWidth);
      } else {
        _animateTo(0);
      }
    }
  }

  void _animateTo(double target) {
    _offsetAnimation = Tween<double>(
      begin: _dragOffset,
      end: target,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward(from: 0);
    setState(() => _dragOffset = target);
    if (target == 0) {
      _openInstances.remove(this);
    } else {
      _openInstances.add(this);
    }
  }

  void _closeActions() => _animateTo(0);

  Future<void> _confirmDelete() async {
    HapticFeedback.mediumImpact();
    _closeActions();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('expense.deleteTitle')),
        content: Text(
          context
              .t('expense.deleteMessage')
              .replaceFirst('{category}', context.categoryLabel(widget.expense.category))
              .replaceFirst('{amount}', formatMoney(
            widget.expense.originalCurrency != null
                ? (kSupportedCurrencies[widget.expense.originalCurrency!] ?? widget.expense.originalCurrency!)
                : widget.currencySymbol,
            widget.expense.amount,
          )),
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
      await widget.onDelete!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSwipeLeft = widget.onDelete != null || widget.onEdit != null;
    final canSwipeRight = widget.onCopy != null;

    final card = _CardContents(
      expense: widget.expense,
      currencySymbol: widget.currencySymbol,
      onTap: () {
        if (_dragOffset != 0) {
          _closeActions();
          return;
        }
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onLongPress: widget.onLongPress,
      account: widget.account,
      flat: widget.flat,
      hasSplitBill: widget.hasSplitBill,
      splitUnsettledCount: widget.splitUnsettledCount,
    );

    if (!canSwipeLeft && !canSwipeRight) return card;

    return GestureDetector(
      onHorizontalDragStart: _onHorizontalDragStart,
      onHorizontalDragUpdate: _onHorizontalDragUpdate,
      onHorizontalDragEnd: _onHorizontalDragEnd,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (ctx, _) {
          final offset = _controller.isAnimating
              ? _offsetAnimation.value
              : _dragOffset;
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Left action: Copy (revealed by rightward swipe)
              if (canSwipeRight)
                Positioned(
                  left: 16,
                  top: 0,
                  bottom: 0,
                  width: _leftActionWidth - 8,
                  child: Opacity(
                    opacity: (offset / _leftActionWidth).clamp(0.0, 1.0),
                    child: _CopyBackground(onTap: () {
                      _closeActions();
                      widget.onCopy!();
                    }),
                  ),
                ),
              // Right actions: Edit + Delete (revealed by leftward swipe)
              if (canSwipeLeft)
                Positioned(
                  right: 16,
                  top: 0,
                  bottom: 0,
                  width: _rightActionWidth - 8,
                  child: Opacity(
                    opacity: (-offset / _rightActionWidth).clamp(0.0, 1.0),
                    child: _RightActions(
                      showEdit: widget.onEdit != null,
                      showDelete: widget.onDelete != null,
                      onEdit: () {
                        _closeActions();
                        widget.onEdit!();
                      },
                      onDelete: _confirmDelete,
                    ),
                  ),
                ),
              // The card itself, translated horizontally
              Transform.translate(
                offset: Offset(
                  _controller.isAnimating ? _offsetAnimation.value : _dragOffset,
                  0,
                ),
                child: card,
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Card contents ──────────────────────────────────────────────

class _CardContents extends StatelessWidget {
  final Expense expense;
  final String currencySymbol;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Account? account;
  final bool flat;
  final bool hasSplitBill;
  final int splitUnsettledCount;

  const _CardContents({
    required this.expense,
    required this.currencySymbol,
    required this.onTap,
    this.onLongPress,
    this.account,
    this.flat = false,
    this.hasSplitBill = false,
    this.splitUnsettledCount = 0,
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
    final d = DateTime(expense.date.year, expense.date.month, expense.date.day);
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

    final rowContent = Row(
      children: [
        Stack(
          clipBehavior: Clip.none,
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
            if (hasSplitBill)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: splitUnsettledCount > 0
                        ? const Color(0xFFE8820E)
                        : const Color(0xFF1F7A60),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Center(
                    child: splitUnsettledCount > 0
                        ? const Text(
                            '!',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              height: 1,
                            ),
                          )
                        : const Icon(
                            CupertinoIcons.checkmark_alt,
                            size: 9,
                            color: Colors.white,
                          ),
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
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
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
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Builder(builder: (ctx) {
              final displaySym = expense.originalCurrency != null
                  ? (kSupportedCurrencies[expense.originalCurrency!] ?? expense.originalCurrency!)
                  : currencySymbol;
              final hasForeign = expense.originalCurrency != null &&
                  expense.baseCurrencyAmount != null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    (isIncome || isReceive)
                        ? formatMoney(displaySym, expense.amount, forceSign: true)
                        : formatMoney(displaySym, -expense.amount),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: amountColor,
                    ),
                  ),
                  if (hasForeign)
                    Text(
                      '≈ ${formatMoney(currencySymbol, expense.baseCurrencyAmount!)}',
                      style: TextStyle(
                        fontSize: 10,
                        color: brand.inkSoft,
                      ),
                    ),
                ],
              );
            }),
            if (expense.receiptUrl != null) ...[
              const SizedBox(width: 6),
              Icon(CupertinoIcons.paperclip, size: 14, color: brand.inkSoft),
            ],
          ],
        ),
      ],
    );

    if (flat) {
      return GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: rowContent,
        ),
      );
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
        ),
        child: rowContent,
      ),
    );
  }

  String _buildSubtitle(String dateStr, Account? acct) {
    if (acct != null) return '$dateStr · ${acct.displayName}';
    return dateStr;
  }
}

// ── Action backgrounds ─────────────────────────────────────────

class _RightActions extends StatelessWidget {
  final bool showEdit;
  final bool showDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RightActions({
    required this.showEdit,
    required this.showDelete,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showEdit)
          Expanded(
            child: GestureDetector(
              onTap: onEdit,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF5B8AF4),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(CupertinoIcons.pencil, color: Colors.white, size: 20),
                    SizedBox(height: 4),
                    Text(
                      'Edit',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (showEdit && showDelete) const SizedBox(width: 6),
        if (showDelete)
          Expanded(
            child: GestureDetector(
              onTap: onDelete,
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.expense,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      CupertinoIcons.delete,
                      color: Colors.white,
                      size: 20,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Delete',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _CopyBackground extends StatelessWidget {
  final VoidCallback onTap;

  const _CopyBackground({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.income,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(CupertinoIcons.doc_on_doc, color: Colors.white, size: 20),
            SizedBox(height: 4),
            Text(
              'Copy',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
