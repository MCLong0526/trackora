import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../widgets/app_toast.dart';

// ── Design tokens (from design file) ─────────────────────────────────────────
const _kGroupTint = Color(0xFFE9E2F3);
const _kGroupInk = Color(0xFF6B4FB2);
const _kGroupInkSoft = Color(0x8C6B4FB2); // rgba(107,79,178,0.55)
const _kBg = Color(0xFFEFEEF2);

// ── Category metadata ─────────────────────────────────────────────────────────
const _kCategories = [
  _CatMeta('Food', CupertinoIcons.bag_fill, Color(0xFFC77B2A)),
  _CatMeta('Groceries', CupertinoIcons.cube_box_fill, Color(0xFF1FBE71)),
  _CatMeta('Transport', CupertinoIcons.car_fill, Color(0xFF1A6CFF)),
  _CatMeta('Shopping', CupertinoIcons.cart_fill, Color(0xFFC5333A)),
  _CatMeta('Entertainment', CupertinoIcons.film_fill, Color(0xFFC5333A)),
  _CatMeta('Health', CupertinoIcons.heart_fill, Color(0xFFFF6B6B)),
  _CatMeta('Bills', CupertinoIcons.doc_fill, Color(0xFF8E8E96)),
  _CatMeta('Others', CupertinoIcons.ellipsis_circle_fill,
      Color(0xFFAAAAAA)),
];

class _CatMeta {
  final String label;
  final IconData icon;
  final Color color;
  const _CatMeta(this.label, this.icon, this.color);
}

// ── Split mode ────────────────────────────────────────────────────────────────
enum _SplitMode { even, youOwe, theyOwe }

// ── Screen ────────────────────────────────────────────────────────────────────

class AddGroupExpenseScreen extends ConsumerStatefulWidget {
  final ExpenseGroup group;
  final GroupExpenseItem? existing;

  const AddGroupExpenseScreen({
    super.key,
    required this.group,
    this.existing,
  });

  @override
  ConsumerState<AddGroupExpenseScreen> createState() =>
      _AddGroupExpenseScreenState();
}

class _AddGroupExpenseScreenState
    extends ConsumerState<AddGroupExpenseScreen>
    with TickerProviderStateMixin {
  final _amountCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _amountFocus = FocusNode();

  String _category = 'Food';
  DateTime _date = DateTime.now();
  String? _paidByUid;
  late Set<String> _splitBetween;
  _SplitMode _splitMode = _SplitMode.even;
  bool _saving = false;
  bool _saveSuccess = false;

  late AnimationController _saveBtnCtrl;
  late Animation<double> _saveBtnBounce;

  bool get _isEdit => widget.existing != null;
  double get _parsedAmount =>
      double.tryParse(_amountCtrl.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    _saveBtnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _saveBtnBounce = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.07), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.07, end: 0.95), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _saveBtnCtrl, curve: Curves.easeOut));

    final user = ref.read(authStateProvider).valueOrNull;
    _paidByUid = widget.existing?.paidBy ?? user?.uid;
    _splitBetween = widget.existing != null
        ? widget.existing!.splitBetween.toSet()
        : widget.group.memberUids.toSet();

    if (widget.existing != null) {
      final e = widget.existing!;
      _amountCtrl.text = e.amount.toStringAsFixed(2);
      _notesCtrl.text = e.notes ?? '';
      _category = e.category;
      _date = e.date;
      // Infer split mode from splitBetween
      if (e.splitBetween.length == widget.group.memberUids.length) {
        _splitMode = _SplitMode.even;
      } else if (e.splitBetween.length == 1) {
        _splitMode = e.splitBetween.first == user?.uid
            ? _SplitMode.youOwe
            : _SplitMode.theyOwe;
      }
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _amountFocus.dispose();
    _saveBtnCtrl.dispose();
    super.dispose();
  }

  void _setSplitMode(_SplitMode mode) {
    final user = ref.read(authStateProvider).valueOrNull;
    setState(() {
      _splitMode = mode;
      switch (mode) {
        case _SplitMode.even:
          _splitBetween = widget.group.memberUids.toSet();
        case _SplitMode.youOwe:
          _splitBetween = {if (user != null) user.uid};
        case _SplitMode.theyOwe:
          final partner = widget.group.memberUids
              .where((uid) => uid != user?.uid)
              .firstOrNull;
          _splitBetween = {if (partner != null) partner};
      }
    });
  }

  Future<void> _save() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      AppToast.show(context, context.t('validation.invalidAmount'));
      return;
    }
    if (_paidByUid == null) {
      AppToast.show(context, 'Select who paid');
      return;
    }
    if (_splitBetween.isEmpty) {
      AppToast.show(context, 'Select at least one person to split with');
      return;
    }

    final desc = _isEdit && widget.existing!.description.isNotEmpty
        ? widget.existing!.description
        : _category;

    setState(() => _saving = true);
    try {
      final service = ref.read(expenseGroupServiceProvider);
      final now = DateTime.now();
      final expense = GroupExpenseItem(
        id: widget.existing?.id ?? '',
        groupId: widget.group.id,
        description: desc,
        amount: amount,
        paidBy: _paidByUid!,
        splitBetween: _splitBetween.toList(),
        category: _category,
        date: _date,
        createdBy: widget.existing?.createdBy ?? user.uid,
        notes: _notesCtrl.text.trim().isEmpty
            ? null
            : _notesCtrl.text.trim(),
        createdAt: widget.existing?.createdAt ?? now,
        updatedAt: now,
      );
      if (_isEdit) {
        await service.updateExpense(expense);
      } else {
        await service.addExpense(expense);
      }
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _saving = false;
          _saveSuccess = true;
        });
        await _saveBtnCtrl.forward(from: 0);
        if (mounted) {
          AppToast.show(
            context,
            _isEdit ? 'Entry updated' : 'Entry saved',
            type: AppToastType.success,
          );
        }
        await Future.delayed(const Duration(milliseconds: 480));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          context.t('common.saveFailed'),
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted && !_saveSuccess) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete expense?'),
        content: const Text('This will permanently remove this expense.'),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(expenseGroupServiceProvider)
          .deleteExpense(widget.group.id, widget.existing!.id);
      if (mounted) {
        AppToast.show(context, 'Entry deleted', type: AppToastType.success);
        await Future.delayed(const Duration(milliseconds: 480));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          'Failed to delete entry',
          type: AppToastType.error,
        );
      }
    }
  }

  void _pickDate() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 260,
        color: _kBg,
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: _date,
          maximumDate: DateTime.now().add(const Duration(days: 1)),
          onDateTimeChanged: (dt) => setState(() => _date = dt),
        ),
      ),
    );
  }

  void _showPaidBySheet() {
    final user = ref.read(authStateProvider).valueOrNull;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _PaidBySheet(
        members: widget.group.members,
        selectedUid: _paidByUid,
        currentUserId: user?.uid,
        onSelected: (uid) {
          setState(() => _paidByUid = uid);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showSplitSheet() {
    final user = ref.read(authStateProvider).valueOrNull;
    final partner = widget.group.members
        .where((m) => m.uid != user?.uid)
        .firstOrNull;
    final symbol = ref.read(currencySymbolProvider).valueOrNull ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _SplitSheet(
        members: widget.group.members,
        currentUserId: user?.uid,
        currentMode: _splitMode,
        amount: _parsedAmount,
        symbol: symbol,
        partnerName: partner?.displayName ?? 'Partner',
        onSelected: (mode) {
          _setSplitMode(mode);
          Navigator.pop(context);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '';
    final user = ref.watch(authStateProvider).valueOrNull;
    final members = widget.group.members;
    final partner =
        members.where((m) => m.uid != user?.uid).firstOrNull;
    final partnerName = partner?.displayName ?? 'Partner';
    final partnerInitial =
        partnerName.isNotEmpty ? partnerName[0].toUpperCase() : 'P';
    final userMember =
        members.where((m) => m.uid == user?.uid).firstOrNull;
    final userInitial =
        (userMember?.displayName.isNotEmpty == true)
            ? userMember!.displayName[0].toUpperCase()
            : 'Y';

    final catMeta = _kCategories.firstWhere(
      (c) => c.label == _category,
      orElse: () => _kCategories.last,
    );
    final amount = _parsedAmount;
    final paidByMember = members.where((m) => m.uid == _paidByUid).firstOrNull;
    final paidByName = paidByMember?.uid == user?.uid
        ? 'You'
        : paidByMember?.displayName ?? 'Select';

    // Split label & badge
    final String splitLabel;
    final Color splitBadgeBg;
    final Color splitBadgeFg;
    if (_splitMode == _SplitMode.even) {
      splitLabel = '50 / 50';
      splitBadgeBg = const Color(0xFFD7F4E5);
      splitBadgeFg = const Color(0xFF1A8E54);
    } else if (_splitMode == _SplitMode.youOwe) {
      splitLabel = 'You owe';
      splitBadgeBg = const Color(0xFFFBDDE0);
      splitBadgeFg = const Color(0xFFC03340);
    } else {
      splitLabel = 'They owe';
      splitBadgeBg = const Color(0xFFFFF1D2);
      splitBadgeFg = const Color(0xFF9A6B00);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
      backgroundColor: _kBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Top bar (X + title) ──────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: const Icon(CupertinoIcons.xmark,
                          color: Color(0xFF0B0B0F), size: 16),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      _isEdit ? context.t('common.edit') : 'New entry',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B0B0F),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  if (_isEdit)
                    GestureDetector(
                      onTap: _delete,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFEEEE),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.delete,
                          color: Color(0xFFD93025),
                          size: 18,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // ── Scrollable body ──────────────────────────────
            Expanded(
              child: SingleChildScrollView(
                padding:
                    const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    // ── Outer purple card ────────────────────
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _kGroupTint,
                        borderRadius: BorderRadius.circular(32),
                      ),
                      padding: const EdgeInsets.fromLTRB(
                          18, 20, 18, 20),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          // Hero row: avatar pair + title
                          Row(
                            children: [
                              Container(
                                width: 60,
                                height: 60,
                                decoration: BoxDecoration(
                                  color: Colors.white
                                      .withValues(alpha: 0.55),
                                  borderRadius:
                                      BorderRadius.circular(16),
                                ),
                                child: Center(
                                  child: SizedBox(
                                    width: 46,
                                    height: 30,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        _GroupAvatar(
                                            initial: userInitial,
                                            bg: Colors.white,
                                            fg: const Color(
                                                0xFF5A4AAB),
                                            size: 30),
                                        Positioned(
                                          left: 16,
                                          child: _GroupAvatar(
                                              initial:
                                                  partnerInitial,
                                              bg: Colors.white,
                                              fg: const Color(
                                                  0xFF1FBE71),
                                              size: 30),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Group expense',
                                      style: TextStyle(
                                        fontSize: 26,
                                        fontWeight: FontWeight.w700,
                                        color: _kGroupInk,
                                        letterSpacing: -0.5,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Splitting with $partnerName',
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: _kGroupInkSoft,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 28),

                          // Amount row
                          GestureDetector(
                            onTap: () => _amountFocus.requestFocus(),
                            child: Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  symbol,
                                  style: const TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w600,
                                    color: _kGroupInk,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: TextField(
                                    controller: _amountCtrl,
                                    focusNode: _amountFocus,
                                    keyboardType:
                                        const TextInputType
                                            .numberWithOptions(
                                                decimal: true),
                                    style: TextStyle(
                                      fontSize: 44,
                                      fontWeight: FontWeight.w700,
                                      color: amount > 0
                                          ? _kGroupInk
                                          : const Color(
                                              0x516B4FB2),
                                      letterSpacing: -1.5,
                                      height: 1.0,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      // Override theme-level fill
                                      filled: false,
                                      fillColor: Colors.transparent,
                                      hintText: '0.00',
                                      hintStyle: TextStyle(
                                        fontSize: 44,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0x516B4FB2),
                                        letterSpacing: -1.5,
                                        height: 1.0,
                                      ),
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    textInputAction:
                                        TextInputAction.done,
                                    onSubmitted: (_) =>
                                        FocusScope.of(context).unfocus(),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Split breakdown pill (visible when amount > 0)
                          if (amount > 0) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.fromLTRB(
                                  14, 10, 14, 10),
                              decoration: BoxDecoration(
                                color: Colors.white
                                    .withValues(alpha: 0.55),
                                borderRadius:
                                    BorderRadius.circular(14),
                              ),
                              child: Row(
                                children: [
                                  // You
                                  Expanded(
                                    child: Row(
                                      children: [
                                        _GroupAvatar(
                                            initial: userInitial,
                                            bg: Colors.white,
                                            fg: const Color(
                                                0xFF5A4AAB),
                                            size: 26),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [
                                            const Text(
                                              'YOU',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color:
                                                    _kGroupInkSoft,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                            Text(
                                              _splitMode ==
                                                      _SplitMode
                                                          .theyOwe
                                                  ? '$symbol${amount.toStringAsFixed(2)}'
                                                  : _splitMode ==
                                                          _SplitMode
                                                              .youOwe
                                                      ? '${symbol}0.00'
                                                      : '$symbol${(amount / 2).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight:
                                                    FontWeight.w700,
                                                color: _kGroupInk,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Divider
                                  Container(
                                    width: 1,
                                    height: 36,
                                    color: const Color(0x2E6B4FB2),
                                  ),
                                  const SizedBox(width: 10),
                                  // Partner
                                  Expanded(
                                    child: Row(
                                      children: [
                                        _GroupAvatar(
                                            initial: partnerInitial,
                                            bg: Colors.white,
                                            fg: const Color(
                                                0xFF1FBE71),
                                            size: 26),
                                        const SizedBox(width: 8),
                                        Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment
                                                  .start,
                                          children: [
                                            Text(
                                              partnerName
                                                  .toUpperCase()
                                                  .split(' ')
                                                  .first,
                                              style: const TextStyle(
                                                fontSize: 11,
                                                fontWeight:
                                                    FontWeight.w600,
                                                color:
                                                    _kGroupInkSoft,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                            Text(
                                              _splitMode ==
                                                      _SplitMode
                                                          .youOwe
                                                  ? '$symbol${amount.toStringAsFixed(2)}'
                                                  : _splitMode ==
                                                          _SplitMode
                                                              .theyOwe
                                                      ? '${symbol}0.00'
                                                      : '$symbol${(amount / 2).toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight:
                                                    FontWeight.w700,
                                                color: _kGroupInk,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 22),

                          // Category label
                          const Text(
                            'Category',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _kGroupInk,
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Category circles (horizontal scroll)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: _kCategories.map((cat) {
                                final active =
                                    cat.label == _category;
                                return GestureDetector(
                                  onTap: () {
                                    HapticFeedback.selectionClick();
                                    setState(
                                        () => _category = cat.label);
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(
                                        right: 14),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color: active
                                                ? cat.color
                                                : Colors.white,
                                            shape: BoxShape.circle,
                                            boxShadow: active
                                                ? null
                                                : [
                                                    BoxShadow(
                                                      color: Colors
                                                          .black
                                                          .withValues(
                                                              alpha:
                                                                  0.04),
                                                      blurRadius: 4,
                                                      offset:
                                                          const Offset(
                                                              0, 1),
                                                    )
                                                  ],
                                          ),
                                          child: Icon(
                                            cat.icon,
                                            color: active
                                                ? Colors.white
                                                : cat.color,
                                            size: 24,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          cat.label,
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: active
                                                ? _kGroupInk
                                                : _kGroupInkSoft,
                                            fontWeight: active
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),

                          if (_category.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: catMeta.color,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _category,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: catMeta.color,
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 18),

                          // ── Inner white card ─────────────────
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(22),
                            ),
                            child: Column(
                              children: [
                                // Paid by
                                _EntryRow(
                                  onTap: _showPaidBySheet,
                                  leading: _GroupAvatar(
                                    initial: (paidByMember?.uid ==
                                                user?.uid
                                            ? userInitial
                                            : (paidByMember
                                                        ?.displayName
                                                        .isNotEmpty ==
                                                    true
                                                ? paidByMember!
                                                    .displayName[0]
                                                    .toUpperCase()
                                                : partnerInitial)),
                                    bg: const Color(0xFFEAE3F8),
                                    fg: const Color(0xFF5A4AAB),
                                    size: 32,
                                  ),
                                  title: 'Paid by',
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        paidByName,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Color(0xFF5B5B66),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                          CupertinoIcons
                                              .chevron_right,
                                          color: Color(0xFFC9C9CF),
                                          size: 14),
                                    ],
                                  ),
                                ),

                                _EntryDivider(),

                                // Split
                                _EntryRow(
                                  onTap: _showSplitSheet,
                                  leading: Container(
                                    width: 32,
                                    height: 32,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF4F4F7),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      CupertinoIcons
                                          .arrow_left_right,
                                      color: Color(0xFF5B5B66),
                                      size: 16,
                                    ),
                                  ),
                                  title: 'Split',
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding:
                                            const EdgeInsets.fromLTRB(
                                                10, 4, 10, 4),
                                        decoration: BoxDecoration(
                                          color: splitBadgeBg,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  8),
                                        ),
                                        child: Text(
                                          splitLabel,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight:
                                                FontWeight.w700,
                                            color: splitBadgeFg,
                                            letterSpacing: 0.2,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                          CupertinoIcons
                                              .chevron_right,
                                          color: Color(0xFFC9C9CF),
                                          size: 14),
                                    ],
                                  ),
                                ),

                                _EntryDivider(),

                                // Date
                                _EntryRow(
                                  onTap: _pickDate,
                                  leading: Container(
                                    width: 32,
                                    height: 32,
                                    child: const Icon(
                                      CupertinoIcons.calendar,
                                      color: Color(0xFF0B0B0F),
                                      size: 22,
                                    ),
                                  ),
                                  title: context.t('expense.date'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        DateFormat('MMM d, yyyy')
                                            .format(_date),
                                        style: const TextStyle(
                                          fontSize: 16,
                                          color: Color(0xFF8E8E96),
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      const Icon(
                                          CupertinoIcons
                                              .chevron_right,
                                          color: Color(0xFFC9C9CF),
                                          size: 14),
                                    ],
                                  ),
                                ),

                                _EntryDivider(),

                                // Note
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(
                                          20, 14, 20, 14),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 32,
                                        height: 32,
                                        child: const Icon(
                                          CupertinoIcons.doc,
                                          color: Color(0xFF0B0B0F),
                                          size: 20,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: TextField(
                                          controller: _notesCtrl,
                                          textCapitalization:
                                              TextCapitalization
                                                  .sentences,
                                          style: const TextStyle(
                                            fontSize: 17,
                                            color: Color(0xFF0B0B0F),
                                            fontWeight:
                                                FontWeight.w600,
                                          ),
                                          decoration:
                                              const InputDecoration(
                                            border:
                                                InputBorder.none,
                                            hintText:
                                                'Note (optional)',
                                            hintStyle: TextStyle(
                                              fontSize: 17,
                                              color:
                                                  Color(0xFF8E8E96),
                                              fontWeight:
                                                  FontWeight.w400,
                                            ),
                                            isDense: true,
                                            contentPadding:
                                                EdgeInsets.zero,
                                          ),
                                          textInputAction:
                                              TextInputAction.done,
                                          onSubmitted: (_) =>
                                              FocusScope.of(context)
                                                  .unfocus(),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ── Save bar ─────────────────────────────────────
            Padding(
              padding: EdgeInsets.fromLTRB(16, 10, 16,
                  MediaQuery.of(context).padding.bottom + 12),
              child: Row(
                children: [
                  // Circle category icon
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:
                              Colors.black.withValues(alpha: 0.06),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(catMeta.icon,
                        color: catMeta.color, size: 22),
                  ),
                  const SizedBox(width: 10),
                  // Pill save button
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _saveBtnBounce,
                      builder: (context, child) => Transform.scale(
                        scale: _saveSuccess ? _saveBtnBounce.value : 1.0,
                        child: child,
                      ),
                      child: GestureDetector(
                        onTap: (_saving || _saveSuccess) ? null : _save,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 56,
                          decoration: BoxDecoration(
                            color: _saveSuccess
                                ? const Color(0xFF1FBE71)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(28),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black
                                    .withValues(alpha: 0.06),
                                blurRadius: 14,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Center(
                            child: AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, anim) =>
                                  ScaleTransition(
                                scale: anim,
                                child: FadeTransition(
                                    opacity: anim, child: child),
                              ),
                              child: _saveSuccess
                                  ? Row(
                                      key: const ValueKey('success'),
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          CupertinoIcons.checkmark_alt,
                                          color: Colors.white,
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                          _isEdit
                                              ? 'Entry updated'
                                              : 'Entry saved',
                                          style: const TextStyle(
                                            fontSize: 17,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: -0.2,
                                          ),
                                        ),
                                      ],
                                    )
                                  : _saving
                                      ? const CupertinoActivityIndicator(
                                          key: ValueKey('loading'),
                                        )
                                      : Row(
                                          key: const ValueKey('idle'),
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Container(
                                              width: 22,
                                              height: 22,
                                              decoration:
                                                  const BoxDecoration(
                                                color: Color(0xFF0B0B0F),
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                CupertinoIcons
                                                    .checkmark_alt,
                                                color: Colors.white,
                                                size: 13,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            const Text(
                                              'Save entry',
                                              style: TextStyle(
                                                fontSize: 17,
                                                fontWeight:
                                                    FontWeight.w700,
                                                color: Color(0xFF0B0B0F),
                                                letterSpacing: -0.2,
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
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

// ── Shared widgets ────────────────────────────────────────────────────────────

class _GroupAvatar extends StatelessWidget {
  final String initial;
  final Color bg;
  final Color fg;
  final double size;
  const _GroupAvatar(
      {required this.initial,
      required this.bg,
      required this.fg,
      required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            fontSize: size * 0.43,
            fontWeight: FontWeight.w700,
            color: fg,
          ),
        ),
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final Widget trailing;
  final VoidCallback? onTap;
  const _EntryRow(
      {required this.leading,
      required this.title,
      required this.trailing,
      this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0B0B0F),
                  letterSpacing: -0.2,
                ),
              ),
            ),
            trailing,
          ],
        ),
      ),
    );
  }
}

class _EntryDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      color: const Color(0xFFEEEEF1),
    );
  }
}

// ── Paid By Bottom Sheet ──────────────────────────────────────────────────────

class _PaidBySheet extends StatelessWidget {
  final List<GroupMember> members;
  final String? selectedUid;
  final String? currentUserId;
  final ValueChanged<String> onSelected;

  const _PaidBySheet({
    required this.members,
    required this.selectedUid,
    required this.currentUserId,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 14, 24, MediaQuery.of(context).padding.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D1D6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Who paid?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0B0B0F),
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Pick the person whose money left the account.',
            style: TextStyle(fontSize: 14, color: Color(0xFF5B5B66)),
          ),
          const SizedBox(height: 18),
          ...members.map((m) {
            final isYou = m.uid == currentUserId;
            final name =
                isYou ? 'You' : m.displayName;
            final initial = name.isNotEmpty
                ? name[0].toUpperCase()
                : '?';
            final selected = m.uid == selectedUid;
            return GestureDetector(
              onTap: () => onSelected(m.uid),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF1A6CFF)
                        : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF1A6CFF)
                                .withValues(alpha: 0.12),
                            blurRadius: 12,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    _GroupAvatar(
                      initial: initial,
                      bg: isYou
                          ? const Color(0xFFEAE3F8)
                          : const Color(0xFFD7F4E5),
                      fg: isYou
                          ? const Color(0xFF5A4AAB)
                          : const Color(0xFF1FBE71),
                      size: 44,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF0B0B0F),
                            ),
                          ),
                          if (!isYou)
                            Text(
                              m.displayName,
                              style: const TextStyle(
                                  fontSize: 13,
                                  color: Color(0xFF8E8E96)),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF1A6CFF)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: selected
                            ? null
                            : Border.all(
                                color: const Color(0xFFD1D1D6),
                                width: 2),
                      ),
                      child: selected
                          ? const Icon(CupertinoIcons.checkmark,
                              color: Colors.white, size: 14)
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Split Bottom Sheet ────────────────────────────────────────────────────────

class _SplitSheet extends StatelessWidget {
  final List<GroupMember> members;
  final String? currentUserId;
  final _SplitMode currentMode;
  final double amount;
  final String symbol;
  final String partnerName;
  final ValueChanged<_SplitMode> onSelected;

  const _SplitSheet({
    required this.members,
    required this.currentUserId,
    required this.currentMode,
    required this.amount,
    required this.symbol,
    required this.partnerName,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final options = [
      _SplitOptionData(
        mode: _SplitMode.even,
        title: 'Split evenly',
        subtitle: amount > 0
            ? '$symbol${(amount / 2).toStringAsFixed(2)} each'
            : 'Equal split between both',
        badge: '50 / 50',
        badgeBg: const Color(0xFFD7F4E5),
        badgeFg: const Color(0xFF1A8E54),
      ),
      _SplitOptionData(
        mode: _SplitMode.youOwe,
        title: '$partnerName paid, you owe all',
        subtitle: amount > 0
            ? 'You owe $symbol${amount.toStringAsFixed(2)}'
            : 'You cover your portion',
        badge: '100% you owe',
        badgeBg: const Color(0xFFFBDDE0),
        badgeFg: const Color(0xFFC03340),
      ),
      _SplitOptionData(
        mode: _SplitMode.theyOwe,
        title: 'You paid, $partnerName owes all',
        subtitle: amount > 0
            ? '$partnerName owes $symbol${amount.toStringAsFixed(2)}'
            : 'They cover their portion',
        badge: '100% they owe',
        badgeBg: const Color(0xFFFFF1D2),
        badgeFg: const Color(0xFF9A6B00),
      ),
    ];

    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 14, 24, MediaQuery.of(context).padding.bottom + 28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: const Color(0xFFD1D1D6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'How to split?',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0B0B0F),
              letterSpacing: -0.4,
            ),
          ),
          if (amount > 0)
            Text(
              '$symbol${amount.toStringAsFixed(2)} between you & $partnerName',
              style: const TextStyle(
                  fontSize: 14, color: Color(0xFF5B5B66)),
            ),
          const SizedBox(height: 14),
          ...options.map((opt) {
            final selected = opt.mode == currentMode;
            return GestureDetector(
              onTap: () => onSelected(opt.mode),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF1A6CFF)
                        : Colors.transparent,
                    width: 2,
                  ),
                  boxShadow: selected
                      ? [
                          BoxShadow(
                            color: const Color(0xFF1A6CFF)
                                .withValues(alpha: 0.1),
                            blurRadius: 12,
                            spreadRadius: 2,
                          )
                        ]
                      : null,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  opt.title,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF0B0B0F),
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding:
                                    const EdgeInsets.fromLTRB(
                                        8, 2, 8, 2),
                                decoration: BoxDecoration(
                                  color: opt.badgeBg,
                                  borderRadius:
                                      BorderRadius.circular(6),
                                ),
                                child: Text(
                                  opt.badge,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: opt.badgeFg,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            opt.subtitle,
                            style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF8E8E96)),
                          ),
                          // 50/50 bar for even split
                          if (opt.mode == _SplitMode.even) ...[
                            const SizedBox(height: 10),
                            ClipRRect(
                              borderRadius:
                                  BorderRadius.circular(4),
                              child: SizedBox(
                                height: 8,
                                child: Row(
                                  children: [
                                    Expanded(
                                        child: Container(
                                            color: const Color(
                                                0xFF5A4AAB))),
                                    Expanded(
                                        child: Container(
                                            color: const Color(
                                                0xFF1FBE71))),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF1A6CFF)
                            : Colors.transparent,
                        shape: BoxShape.circle,
                        border: selected
                            ? null
                            : Border.all(
                                color: const Color(0xFFD1D1D6),
                                width: 2),
                      ),
                      child: selected
                          ? const Icon(CupertinoIcons.checkmark,
                              color: Colors.white, size: 13)
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _SplitOptionData {
  final _SplitMode mode;
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeBg;
  final Color badgeFg;
  const _SplitOptionData({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.badge,
    required this.badgeBg,
    required this.badgeFg,
  });
}
