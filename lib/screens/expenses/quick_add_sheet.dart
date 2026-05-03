import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/expense.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import 'add_edit_expense_screen.dart' show kExpenseCategories;

/// Compact quick-add dialog — opens directly from the iOS widget's
/// **Custom** button (`trackora://quickadd`) and from the small
/// widget's chrome tap.
///
/// Why this exists: iOS WidgetKit does not allow text input inside a
/// widget. The next best thing is to pop up a tiny dialog that's still
/// faster than the full add-expense screen — keypad amount entry, a row
/// of category chips, save. The full screen remains available via the
/// FAB / `trackora://add`.
///
/// On save the widget's shared totals are nudged optimistically so the
/// home screen reflects the new entry without waiting for the next
/// dashboard rebuild (the dashboard still re-pushes authoritative
/// numbers when reopened).
class QuickAddSheet extends ConsumerStatefulWidget {
  /// Optional preset amount. Used by the iOS-16 fallback link
  /// `trackora://quickadd?amount=10` so older iOS still gets a one-tap
  /// flow even without App Intents.
  final double? presetAmount;

  const QuickAddSheet({super.key, this.presetAmount});

  static Future<void> show(BuildContext context, {double? presetAmount}) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.t('quickAdd.title'),
      barrierColor: Colors.black.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, _, _) => QuickAddSheet(presetAmount: presetAmount),
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  ConsumerState<QuickAddSheet> createState() => _QuickAddSheetState();
}

class _QuickAddSheetState extends ConsumerState<QuickAddSheet> {
  static const _maxAmountCents = 999900;

  int _amountCents = 0;
  String _category = kExpenseCategories.first;
  bool _saving = false;
  String? _error;

  double get _amount => _amountCents / 100;

  @override
  void initState() {
    super.initState();
    if (widget.presetAmount != null && widget.presetAmount! > 0) {
      _amountCents = _toCents(widget.presetAmount!);
    }
  }

  int _toCents(double amount) {
    return (amount * 100).round().clamp(0, _maxAmountCents).toInt();
  }

  void _appendDigit(int digit) {
    if (_saving) return;
    final next = (_amountCents * 10) + digit;
    if (next > _maxAmountCents) return;
    setState(() {
      _amountCents = next;
      _error = null;
    });
    HapticFeedback.selectionClick();
  }

  void _backspace() {
    if (_saving || _amountCents == 0) return;
    setState(() {
      _amountCents = _amountCents ~/ 10;
      _error = null;
    });
    HapticFeedback.selectionClick();
  }

  void _clearAmount() {
    if (_saving || _amountCents == 0) return;
    setState(() {
      _amountCents = 0;
      _error = null;
    });
    HapticFeedback.selectionClick();
  }

  Future<void> _save() async {
    final amount = _amount;
    if (amount <= 0) {
      setState(() => _error = context.t('validation.enterAmount'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      setState(() {
        _saving = false;
        _error = context.t('auth.notSignedIn');
      });
      return;
    }
    final repo = ref.read(expenseRepositoryProvider);
    final now = DateTime.now();

    try {
      await repo.addExpense(
        user.uid,
        Expense(
          id: '',
          amount: amount,
          category: _category,
          note: 'Quick add',
          date: now,
          type: EntryType.expense,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await ref
          .read(widgetSyncServiceProvider)
          .nudgeQuickExpense(
            amount,
            budgetable: _category != 'Bills',
            nextDraftAmount: amount,
          );
      HapticFeedback.mediumImpact();
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = context.t('common.saveFailed');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.18),
                        blurRadius: 28,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              context.t('quickAdd.title'),
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(CupertinoIcons.xmark, size: 20),
                            onPressed: () => Navigator.pop(context),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _AmountDisplay(
                        value: formatMoney(symbol, _amount),
                        muted: _amountCents == 0,
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.expense,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      const SizedBox(height: 12),
                      _AmountKeypad(
                        onDigit: _appendDigit,
                        onBackspace: _backspace,
                        onClear: _clearAmount,
                        saving: _saving,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.t('expense.category'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: kExpenseCategories.map((c) {
                          final selected = c == _category;
                          final s = styleFor(c);
                          return GestureDetector(
                            onTap: () => setState(() => _category = c),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: selected
                                    ? brand.accentDark
                                    : s.background,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.chip,
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    s.icon,
                                    size: 14,
                                    color: selected
                                        ? foregroundOn(brand.accentDark)
                                        : s.accent,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    context.categoryLabel(c),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: selected
                                          ? foregroundOn(brand.accentDark)
                                          : AppColors.ink,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _saving || _amountCents == 0
                              ? null
                              : _save,
                          child: _saving
                              ? SizedBox(
                                  height: 16,
                                  width: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                  ),
                                )
                              : Text(context.t('common.save')),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AmountDisplay extends StatelessWidget {
  final String value;
  final bool muted;

  const _AmountDisplay({required this.value, required this.muted});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: double.infinity,
      height: 74,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: brand.divider),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerRight,
        child: Text(
          value,
          maxLines: 1,
          style: TextStyle(
            color: muted ? brand.inkSoft : brand.ink,
            fontSize: 38,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _AmountKeypad extends StatelessWidget {
  final ValueChanged<int> onDigit;
  final VoidCallback onBackspace;
  final VoidCallback onClear;
  final bool saving;

  const _AmountKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.saving,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final row in const [
          [1, 2, 3],
          [4, 5, 6],
          [7, 8, 9],
        ]) ...[
          Row(
            children: [
              for (final digit in row) ...[
                Expanded(
                  child: _KeypadButton(
                    onTap: saving ? null : () => onDigit(digit),
                    child: Text('$digit'),
                  ),
                ),
                if (digit != row.last) const SizedBox(width: 8),
              ],
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: _KeypadButton(
                onTap: saving ? null : onClear,
                child: const Text('C'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KeypadButton(
                onTap: saving ? null : () => onDigit(0),
                child: const Text('0'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KeypadButton(
                onTap: saving ? null : onBackspace,
                child: const Icon(CupertinoIcons.delete_left, size: 22),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _KeypadButton extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _KeypadButton({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SizedBox(
      height: 48,
      child: Material(
        color: brand.background,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: IconTheme.merge(
            data: IconThemeData(color: brand.ink),
            child: DefaultTextStyle.merge(
              textAlign: TextAlign.center,
              style: TextStyle(
                color: brand.ink,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                letterSpacing: 0,
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
