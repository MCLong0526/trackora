import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_config.dart';
import '../../models/account.dart';
import '../../models/expense.dart';
import '../../repositories/local_expense_repository.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../services/sync_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'add_edit_expense_screen.dart' show kExpenseCategories;

/// Compact quick-add dialog — opens from iOS Back Tap, widget deep-links,
/// Siri shortcut (`trackora://quickadd`), or the Action Button.
class QuickAddSheet extends ConsumerStatefulWidget {
  final double? presetAmount;
  final String? presetCategory;

  const QuickAddSheet({super.key, this.presetAmount, this.presetCategory});

  static Future<void> show(
    BuildContext context, {
    double? presetAmount,
    String? presetCategory,
  }) {
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: context.t('quickAdd.title'),
      barrierColor: context.brand.ink.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, _, _) => QuickAddSheet(
        presetAmount: presetAmount,
        presetCategory: presetCategory,
      ),
      transitionBuilder: (_, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.08),
              end: Offset.zero,
            ).animate(curved),
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
  String? _accountId;
  final _noteCtrl = TextEditingController();
  bool _saving = false;
  String? _error;

  double get _amount => _amountCents / 100;

  @override
  void initState() {
    super.initState();
    if (widget.presetAmount != null && widget.presetAmount! > 0) {
      _amountCents = _toCents(widget.presetAmount!);
    }
    if (widget.presetCategory != null &&
        kExpenseCategories.contains(widget.presetCategory)) {
      _category = widget.presetCategory!;
    }
  }

  @override
  void dispose() {
    _noteCtrl.dispose();
    super.dispose();
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
    final isOnline = ref.read(isOnlineProvider);
    final repo = ref.read(expenseRepositoryProvider);
    final now = DateTime.now();
    final expense = Expense(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      amount: amount,
      category: _category,
      note: _noteCtrl.text.trim(),
      date: now,
      type: EntryType.expense,
      accountId: _accountId,
      createdAt: now,
      updatedAt: now,
    );

    try {
      if (isOnline) {
        try {
          await repo.addExpense(user.uid, expense);
          await LocalExpenseRepository().upsertExpense(user.uid, expense);
        } catch (_) {
          await LocalExpenseRepository().upsertExpense(user.uid, expense);
          if (storageMode == StorageMode.firebase) {
            await SyncService().markPending(user.uid, expense.id);
          }
        }
      } else {
        await LocalExpenseRepository().upsertExpense(user.uid, expense);
        if (storageMode == StorageMode.firebase) {
          await SyncService().markPending(user.uid, expense.id);
        }
      }
      await ref
          .read(widgetSyncServiceProvider)
          .nudgeQuickExpense(
            amount,
            budgetable: _category != 'Bills',
            nextDraftAmount: amount,
          );
      HapticFeedback.mediumImpact();
      if (mounted) {
        AppToast.show(
          context,
          isOnline
              ? context.t('expense.entrySaved')
              : context.t('expense.savedOffline'),
          type: AppToastType.success,
          icon: CupertinoIcons.checkmark_circle_fill,
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = context.t('common.saveFailed');
        });
      }
    }
  }

  void _showAccountPicker(List<Account> accounts, BrandColors brand) {
    showModalBottomSheet<void>(
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
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Text(
                  context.t('expense.selectAccount'),
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  children: [
                    ListTile(
                      leading: Icon(
                        CupertinoIcons.xmark_circle,
                        color: brand.inkSoft,
                      ),
                      title: Text(
                        context.t('expense.none'),
                        style: TextStyle(color: brand.inkSoft),
                      ),
                      trailing: _accountId == null
                          ? Icon(
                              CupertinoIcons.checkmark_alt,
                              color: brand.accentDark,
                            )
                          : null,
                      onTap: () {
                        setState(() => _accountId = null);
                        Navigator.pop(ctx);
                      },
                    ),
                    ...accounts.map((a) {
                      final isSelected = _accountId == a.id;
                      return ListTile(
                        leading: Icon(
                          _iconForAccountType(a.type),
                          color: _accentForAccountType(a.type),
                        ),
                        title: Text(
                          a.name,
                          style: TextStyle(
                            color: brand.ink,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          a.type.label,
                          style: TextStyle(color: brand.inkSoft),
                        ),
                        trailing: isSelected
                            ? Icon(
                                CupertinoIcons.checkmark_alt,
                                color: brand.accentDark,
                              )
                            : null,
                        onTap: () {
                          setState(() => _accountId = a.id);
                          Navigator.pop(ctx);
                        },
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

  IconData _iconForAccountType(AccountType type) {
    switch (type) {
      case AccountType.bank:
        return CupertinoIcons.building_2_fill;
      case AccountType.eWallet:
        return CupertinoIcons.device_phone_portrait;
      case AccountType.cash:
        return CupertinoIcons.money_dollar_circle_fill;
      case AccountType.investment:
        return CupertinoIcons.chart_bar_fill;
      case AccountType.savings:
        return CupertinoIcons.archivebox_fill;
      case AccountType.crypto:
        return CupertinoIcons.bitcoin_circle_fill;
      case AccountType.forex:
        return CupertinoIcons.globe;
      case AccountType.creditCard:
        return CupertinoIcons.creditcard_fill;
      case AccountType.loan:
        return CupertinoIcons.doc_text_fill;
      case AccountType.mortgage:
        return CupertinoIcons.house_fill;
      case AccountType.bnpl:
        return CupertinoIcons.cart_fill;
      case AccountType.otherLiability:
        return CupertinoIcons.minus_circle_fill;
    }
  }

  Color _accentForAccountType(AccountType type) {
    switch (type) {
      case AccountType.bank:
        return const Color(0xFF2A6FB5);
      case AccountType.eWallet:
        return const Color(0xFF8B5CF6);
      case AccountType.cash:
        return const Color(0xFF2A7D5A);
      case AccountType.investment:
        return const Color(0xFF2E9E5A);
      case AccountType.savings:
        return const Color(0xFF2E7EB5);
      case AccountType.crypto:
        return const Color(0xFFE8820E);
      case AccountType.forex:
        return const Color(0xFF7F4FD4);
      case AccountType.creditCard:
      case AccountType.loan:
      case AccountType.mortgage:
      case AccountType.bnpl:
      case AccountType.otherLiability:
        return AppColors.expense;
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final selectedAccount = accounts
        .where((a) => a.id == _accountId)
        .firstOrNull;

    return SafeArea(
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.fromLTRB(
          16,
          20,
          16,
          MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Material(
                color: Colors.transparent,
                child: Container(
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 18, 12, 0),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                context.t('quickAdd.title'),
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  color: brand.ink,
                                ),
                              ),
                            ),
                            CupertinoButton(
                              padding: EdgeInsets.zero,
                              onPressed: () => Navigator.pop(context),
                              child: Container(
                                width: 30,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: brand.background,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  CupertinoIcons.xmark,
                                  size: 14,
                                  color: brand.inkSoft,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Amount display
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _AmountDisplay(
                          value: formatMoney(symbol, _amount),
                          muted: _amountCents == 0,
                          brand: brand,
                        ),
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
                          child: Text(
                            _error!,
                            style: const TextStyle(
                              color: AppColors.expense,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      const SizedBox(height: 14),

                      // Keypad
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: _AmountKeypad(
                          onDigit: _appendDigit,
                          onBackspace: _backspace,
                          onClear: _clearAmount,
                          saving: _saving,
                          brand: brand,
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Category chips
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          context.t('expense.category'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: brand.inkSoft,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Wrap(
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
                                  horizontal: 11,
                                  vertical: 7,
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
                                      size: 13,
                                      color: selected
                                          ? foregroundOn(brand.accentDark)
                                          : s.accent,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      context.categoryLabel(c),
                                      style: TextStyle(
                                        fontSize: 11,
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
                      ),
                      const SizedBox(height: 14),

                      // Divider
                      Divider(height: 1, thickness: 0.5, color: brand.divider),

                      // Account row
                      InkWell(
                        onTap: accounts.isEmpty
                            ? null
                            : () => _showAccountPicker(accounts, brand),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selectedAccount != null
                                    ? _iconForAccountType(selectedAccount.type)
                                    : CupertinoIcons.creditcard,
                                size: 17,
                                color: selectedAccount != null
                                    ? _accentForAccountType(
                                        selectedAccount.type,
                                      )
                                    : brand.inkSoft,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.t('expense.account'),
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: brand.ink,
                                  ),
                                ),
                              ),
                              Text(
                                selectedAccount?.name ??
                                    context.t('expense.none'),
                                style: TextStyle(
                                  fontSize: 14,
                                  color: brand.inkSoft,
                                ),
                              ),
                              const SizedBox(width: 4),
                              if (accounts.isNotEmpty)
                                Icon(
                                  CupertinoIcons.chevron_right,
                                  size: 12,
                                  color: brand.inkSoft,
                                ),
                            ],
                          ),
                        ),
                      ),
                      Divider(
                        height: 1,
                        thickness: 0.5,
                        color: brand.divider,
                        indent: 20,
                      ),

                      // Notes row
                      Padding(
                        padding: const EdgeInsets.only(left: 20, right: 16),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 13),
                              child: Icon(
                                CupertinoIcons.doc_text,
                                size: 17,
                                color: brand.inkSoft,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextField(
                                controller: _noteCtrl,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: brand.ink,
                                ),
                                decoration: InputDecoration(
                                  hintText: context.t('expense.note'),
                                  hintStyle: TextStyle(
                                    color: brand.inkSoft,
                                    fontSize: 14,
                                  ),
                                  filled: false,
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  contentPadding: const EdgeInsets.symmetric(
                                    vertical: 13,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // Save button
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                        child: SizedBox(
                          height: 50,
                          child: FilledButton(
                            onPressed: _saving || _amountCents == 0
                                ? null
                                : _save,
                            style: FilledButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _saving
                                ? SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onPrimary,
                                    ),
                                  )
                                : Text(
                                    context.t('common.save'),
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                          ),
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
  final BrandColors brand;

  const _AmountDisplay({
    required this.value,
    required this.muted,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 68,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(12),
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
            fontSize: 36,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.5,
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
  final BrandColors brand;

  const _AmountKeypad({
    required this.onDigit,
    required this.onBackspace,
    required this.onClear,
    required this.saving,
    required this.brand,
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
                    brand: brand,
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
                brand: brand,
                child: const Text('C'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KeypadButton(
                onTap: saving ? null : () => onDigit(0),
                brand: brand,
                child: const Text('0'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _KeypadButton(
                onTap: saving ? null : onBackspace,
                brand: brand,
                child: const Icon(CupertinoIcons.delete_left, size: 20),
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
  final BrandColors brand;

  const _KeypadButton({
    required this.child,
    required this.onTap,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: Material(
        color: brand.background,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: IconTheme.merge(
            data: IconThemeData(color: brand.ink),
            child: DefaultTextStyle.merge(
              textAlign: TextAlign.center,
              style: TextStyle(
                color: brand.ink,
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
              child: Center(child: child),
            ),
          ),
        ),
      ),
    );
  }
}
