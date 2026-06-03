import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/account.dart';
import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../repositories/local_expense_group_repository.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
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
enum _SplitMode { noSplit, even, byPercent, byAmount, youOwe, theyOwe }

// ── Screen ────────────────────────────────────────────────────────────────────

class AddGroupExpenseScreen extends ConsumerStatefulWidget {
  final ExpenseGroup group;
  final GroupExpenseItem? existing;
  /// When set, pre-fills all fields from this expense but saves as a NEW record.
  final GroupExpenseItem? copyFrom;

  const AddGroupExpenseScreen({
    super.key,
    required this.group,
    this.existing,
    this.copyFrom,
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
  final _youCtrl = TextEditingController();
  final _partnerCtrl = TextEditingController();
  bool _syncingAmounts = false;

  String _category = 'Food';
  DateTime _date = DateTime.now();
  String? _paidByUid;
  String? _paidByAccountId;
  late Set<String> _splitBetween;
  _SplitMode _splitMode = _SplitMode.even;
  // uid → percent (0–100); only used when _splitMode == byPercent/byAmount
  Map<String, double> _splitCustomPercents = {};
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

    if (widget.existing != null) {
      _splitBetween = widget.existing!.splitBetween.toSet();
    } else {
      // Default: no split — the payer records their own expense in the group
      // without creating any debt between members.
      _splitMode = _SplitMode.noSplit;
      _splitBetween = {?_paidByUid};
    }

    // copyFrom: pre-fills as a new entry (same logic, but _isEdit stays false)
    final template = widget.existing ?? widget.copyFrom;
    if (template != null) {
      final e = template;
      _amountCtrl.text = e.amount.toStringAsFixed(2);
      _notesCtrl.text = e.notes ?? '';
      _category = e.category;
      _date = e.date;
      _paidByAccountId = e.paidByAccountId;
      // Infer split mode: prefer explicit splitPercents, fall back to splitBetween.
      if (e.splitPercents != null && e.splitPercents!.isNotEmpty) {
        _splitCustomPercents = Map<String, double>.from(e.splitPercents!);
        // Restore the exact split mode that was saved.
        switch (e.splitModeType) {
          case 'byPercent':
            _splitMode = _SplitMode.byPercent;
          case 'byAmount':
            _splitMode = _SplitMode.byAmount;
          default:
            _splitMode = _SplitMode.byAmount;
        }
      } else if (e.splitModeType == 'noSplit') {
        _splitMode = _SplitMode.noSplit;
      } else if (e.splitModeType == 'youOwe') {
        _splitMode = _SplitMode.youOwe;
      } else if (e.splitModeType == 'theyOwe') {
        _splitMode = _SplitMode.theyOwe;
      } else if (e.splitBetween.length == widget.group.memberUids.length) {
        _splitMode = _SplitMode.even;
      } else if (e.splitBetween.length == 1) {
        _splitMode = e.splitBetween.first == user?.uid
            ? _SplitMode.youOwe
            : _SplitMode.theyOwe;
      }
      // Sync the YOU/PARTNER sub-amount fields once the first frame is laid out.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncSubAmounts();
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _amountFocus.dispose();
    _youCtrl.dispose();
    _partnerCtrl.dispose();
    _saveBtnCtrl.dispose();
    super.dispose();
  }

  // Sync the YOU/PARTNER sub-amount fields based on total + split mode.
  void _syncSubAmounts() {
    if (_syncingAmounts) return;
    _syncingAmounts = true;
    final total = _parsedAmount;
    final user = ref.read(authStateProvider).valueOrNull;
    double youAmt;
    double partnerAmt;
    switch (_splitMode) {
      case _SplitMode.noSplit:
        youAmt = total;
        partnerAmt = 0;
      case _SplitMode.even:
        youAmt = total / 2;
        partnerAmt = total / 2;
      case _SplitMode.youOwe:
        youAmt = 0;
        partnerAmt = total;
      case _SplitMode.theyOwe:
        youAmt = total;
        partnerAmt = 0;
      case _SplitMode.byPercent:
      case _SplitMode.byAmount:
        final myPct = _splitCustomPercents[user?.uid] ?? 50.0;
        youAmt = total * myPct / 100;
        partnerAmt = total - youAmt;
    }
    if (total > 0) {
      _youCtrl.text = youAmt.toStringAsFixed(2);
      _partnerCtrl.text = partnerAmt.toStringAsFixed(2);
    } else {
      _youCtrl.clear();
      _partnerCtrl.clear();
    }
    _syncingAmounts = false;
  }

  // When the total is first entered, keep the YOU/PARTNER amounts reflecting the
  // current split mode. If the user has already nudged a per-person amount we are
  // in byAmount mode and the custom percents are preserved by _syncSubAmounts.
  // Even-split intent is left untouched here — this is a no-op safeguard so that
  // typing the total never silently flips the chosen split mode.
  void _autoSetSplitByAmount() {
    // Intentionally no-op: split mode is owned by _setSplitMode and the
    // _onYouAmountChanged / _onPartnerAmountChanged handlers. _syncSubAmounts
    // already refreshes the displayed per-person amounts for the active mode.
  }

  void _onYouAmountChanged() {
    if (_syncingAmounts) return;
    final total = _parsedAmount;
    if (total <= 0) return;
    final you = (double.tryParse(_youCtrl.text) ?? 0).clamp(0.0, total);
    final partner = total - you;
    _syncingAmounts = true;
    _partnerCtrl.text = partner.toStringAsFixed(2);
    _syncingAmounts = false;
    final myPct = you / total * 100;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    final partnerUid = widget.group.members.where((m) => m.uid != uid).firstOrNull?.uid;
    if (uid != null && partnerUid != null) {
      setState(() {
        _splitMode = _SplitMode.byAmount;
        _splitCustomPercents = {uid: myPct, partnerUid: 100 - myPct};
        _splitBetween = widget.group.memberUids.toSet();
      });
    }
  }

  void _onPartnerAmountChanged() {
    if (_syncingAmounts) return;
    final total = _parsedAmount;
    if (total <= 0) return;
    final partner = (double.tryParse(_partnerCtrl.text) ?? 0).clamp(0.0, total);
    final you = total - partner;
    _syncingAmounts = true;
    _youCtrl.text = you.toStringAsFixed(2);
    _syncingAmounts = false;
    final myPct = you / total * 100;
    final uid = ref.read(authStateProvider).valueOrNull?.uid;
    final partnerUid = widget.group.members.where((m) => m.uid != uid).firstOrNull?.uid;
    if (uid != null && partnerUid != null) {
      setState(() {
        _splitMode = _SplitMode.byAmount;
        _splitCustomPercents = {uid: myPct, partnerUid: 100 - myPct};
        _splitBetween = widget.group.memberUids.toSet();
      });
    }
  }

  String _splitModeTypeString(_SplitMode mode) => switch (mode) {
    _SplitMode.noSplit => 'noSplit',
    _SplitMode.even => 'even',
    _SplitMode.byPercent => 'byPercent',
    _SplitMode.byAmount => 'byAmount',
    _SplitMode.youOwe => 'youOwe',
    _SplitMode.theyOwe => 'theyOwe',
  };

  void _setSplitMode(_SplitMode mode, {Map<String, double>? customPercents}) {
    final user = ref.read(authStateProvider).valueOrNull;
    setState(() {
      _splitMode = mode;
      _splitCustomPercents = customPercents ?? {};
      switch (mode) {
        case _SplitMode.noSplit:
          _splitBetween = {if (user != null) user.uid};
        case _SplitMode.even:
          _splitBetween = widget.group.memberUids.toSet();
        case _SplitMode.byPercent:
        case _SplitMode.byAmount:
          _splitBetween = widget.group.memberUids.toSet();
        case _SplitMode.youOwe:
          _splitBetween = {if (user != null) user.uid};
        case _SplitMode.theyOwe:
          final partner = widget.group.memberUids
              .where ((uid) => uid != user?.uid)
              .firstOrNull;
          _splitBetween = {?partner};
      }
    });
    // Keep sub-amount fields in sync
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncSubAmounts());
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
      AppToast.show(context, context.t('groupExpense.selectWhoPaid'));
      return;
    }
    if (_splitBetween.isEmpty) {
      AppToast.show(context, context.t('groupExpense.selectSplit'));
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
        paidByAccountId: _paidByAccountId,
        splitBetween: _splitBetween.toList(),
        splitPercents: _splitCustomPercents.isNotEmpty
            ? _splitCustomPercents
            : null,
        splitModeType: _splitModeTypeString(_splitMode),
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
        // Mirror update to local cache so offline stream reflects change immediately.
        if (storageMode == StorageMode.firebase) {
          await LocalExpenseGroupRepository().updateExpense(expense);
        }
      } else {
        final savedId = await service.addExpense(expense);
        // Write to local cache with the real ID so offline stream updates instantly.
        if (storageMode == StorageMode.firebase) {
          final cached = GroupExpenseItem(
            id: savedId,
            groupId: expense.groupId,
            description: expense.description,
            amount: expense.amount,
            paidBy: expense.paidBy,
            paidByAccountId: expense.paidByAccountId,
            splitBetween: expense.splitBetween,
            splitPercents: expense.splitPercents,
            splitModeType: expense.splitModeType,
            category: expense.category,
            date: expense.date,
            createdBy: expense.createdBy,
            notes: expense.notes,
            createdAt: expense.createdAt,
            updatedAt: expense.updatedAt,
          );
          await LocalExpenseGroupRepository().addExpense(cached);
        }
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
            _isEdit
                ? context.t('group.entryUpdated')
                : context.t('group.entrySaved'),
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
        title: Text(context.t('group.deleteExpense')),
        content: Text(context.t('group.deleteExpensePermanent')),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('common.delete')),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('common.cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await ref
          .read(expenseGroupServiceProvider)
          .deleteExpense(widget.group.id, widget.existing!.id);
      // Mirror delete to local cache so the stream removes it immediately.
      if (storageMode == StorageMode.firebase) {
        await LocalExpenseGroupRepository()
            .deleteExpense(widget.group.id, widget.existing!.id);
      }
      if (mounted) {
        AppToast.show(context, context.t('group.entryDeleted'),
            type: AppToastType.success);
        await Future.delayed(const Duration(milliseconds: 480));
        if (mounted) Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          context.t('group.failedToDeleteEntry'),
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

  void _showAccountSheet(List<Account> accounts) {
    if (accounts.isEmpty) return;
    final brand = context.brand;
    FocusScope.of(context).unfocus();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: brand.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: SizedBox(
            height: 420,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                  child: Text(
                    context.t('groupExpense.payFromAccount'),
                    style: TextStyle(
                      fontSize: 18,
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
                        trailing: _paidByAccountId == null
                            ? Icon(
                                CupertinoIcons.checkmark_alt,
                                color: brand.accentDark,
                              )
                            : null,
                        onTap: () {
                          setState(() => _paidByAccountId = null);
                          Navigator.pop(ctx);
                        },
                      ),
                      ...accounts.map((a) {
                        final isSelected = _paidByAccountId == a.id;
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
                            setState(() => _paidByAccountId = a.id);
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
        );
      },
    );
  }

  IconData _iconForType(AccountType type) {
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

  Color _accentForType(AccountType type) {
    switch (type) {
      case AccountType.bank:
        return const Color(0xFF2A6FB5);
      case AccountType.eWallet:
        return const Color(0xFF1F7A60);
      case AccountType.cash:
        return const Color(0xFFA0801C);
      case AccountType.investment:
        return const Color(0xFF2E9E5A);
      case AccountType.savings:
        return const Color(0xFF2E7EB5);
      case AccountType.crypto:
        return const Color(0xFFE8820E);
      case AccountType.forex:
        return const Color(0xFF7F4FD4);
      case AccountType.creditCard:
        return const Color(0xFFB03060);
      case AccountType.loan:
        return const Color(0xFF9C4A1A);
      case AccountType.mortgage:
        return const Color(0xFF6B4D2A);
      case AccountType.bnpl:
        return const Color(0xFF5C3A9E);
      case AccountType.otherLiability:
        return const Color(0xFF7A4040);
    }
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
    final screenHeight = MediaQuery.of(context).size.height;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: screenHeight * 0.70),
        child: _SplitSheet(
          members: widget.group.members,
          currentUserId: user?.uid,
          currentMode: _splitMode,
          currentPercents: _splitCustomPercents,
          amount: _parsedAmount,
          symbol: symbol,
          partnerName: partner?.displayName ?? context.t('group.partnerFallback'),
          onSelected: (mode, percents) {
            _setSplitMode(mode, customPercents: percents);
            Navigator.pop(context);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '';
    final user = ref.watch(authStateProvider).valueOrNull;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final members = widget.group.members;
    final partner =
        members.where((m) => m.uid != user?.uid).firstOrNull;
    final partnerName = partner?.displayName ?? context.t('group.partnerFallback');
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
        ? context.t('group.you')
        : paidByMember?.displayName ?? context.t('groupExpense.select');

    // Split label & badge
    final String splitLabel;
    final Color splitBadgeBg;
    final Color splitBadgeFg;
    if (_splitMode == _SplitMode.noSplit) {
      splitLabel = context.t('groupExpense.splitNoSplit');
      splitBadgeBg = const Color(0xFFEEEEF1);
      splitBadgeFg = const Color(0xFF5B5B66);
    } else if (_splitMode == _SplitMode.even) {
      splitLabel = context.t('groupExpense.fiftyFifty');
      splitBadgeBg = const Color(0xFFD7F4E5);
      splitBadgeFg = const Color(0xFF1A8E54);
    } else if (_splitMode == _SplitMode.byPercent) {
      final myPct = _splitCustomPercents[user?.uid] ?? 50.0;
      splitLabel = '${myPct.toStringAsFixed(0)}% / ${(100-myPct).toStringAsFixed(0)}%';
      splitBadgeBg = const Color(0xFFEAE3F8);
      splitBadgeFg = const Color(0xFF5A4AAB);
    } else if (_splitMode == _SplitMode.byAmount) {
      final myPct = _splitCustomPercents[user?.uid] ?? 50.0;
      final partnerPct = 100 - myPct;
      splitLabel = '${myPct.toStringAsFixed(0)}% / ${partnerPct.toStringAsFixed(0)}%';
      splitBadgeBg = const Color(0xFFFFF1D2);
      splitBadgeFg = const Color(0xFF9A6B00);
    } else if (_splitMode == _SplitMode.youOwe) {
      splitLabel = context.t('groupExpense.youOweBadgeShort');
      splitBadgeBg = const Color(0xFFFBDDE0);
      splitBadgeFg = const Color(0xFFC03340);
    } else {
      splitLabel = context.t('groupExpense.theyOweBadgeShort');
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
                      _isEdit
                          ? context.t('common.edit')
                          : context.t('groupExpense.newEntry'),
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
                    const EdgeInsets.fromLTRB(14, 0, 14, 14),
                child: Column(
                  children: [
                    // ── Outer purple card ────────────────────
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: _kGroupTint,
                        borderRadius: BorderRadius.circular(28),
                      ),
                      padding: const EdgeInsets.fromLTRB(
                          16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment:
                            CrossAxisAlignment.start,
                        children: [
                          // Hero row: avatar pair + title
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: Colors.white
                                      .withValues(alpha: 0.55),
                                  borderRadius:
                                      BorderRadius.circular(14),
                                ),
                                child: Center(
                                  child: SizedBox(
                                    width: partner != null ? 40 : 26,
                                    height: 26,
                                    child: Stack(
                                      clipBehavior: Clip.none,
                                      children: [
                                        _GroupAvatar(
                                            initial: userInitial,
                                            bg: Colors.white,
                                            fg: const Color(
                                                0xFF5A4AAB),
                                            size: 26),
                                        if (partner != null)
                                          Positioned(
                                            left: 14,
                                            child: _GroupAvatar(
                                                initial:
                                                    partnerInitial,
                                                bg: Colors.white,
                                                fg: const Color(
                                                    0xFF1FBE71),
                                                size: 26),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.t('groupExpense.title'),
                                      style: const TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: _kGroupInk,
                                        letterSpacing: -0.4,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      context
                                          .t('groupExpense.splittingWith')
                                          .replaceAll('{name}', partnerName),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: _kGroupInkSoft,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: 16),

                          // "Total amount" label
                          Text(
                            context.t('groupExpense.totalAmount'),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: _kGroupInkSoft,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 4),

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
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: _kGroupInk,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: TextField(
                                    controller: _amountCtrl,
                                    focusNode: _amountFocus,
                                    cursorHeight: 34.0,
                                    keyboardType:
                                        const TextInputType
                                            .numberWithOptions(
                                                decimal: true),
                                    style: TextStyle(
                                      fontSize: 34,
                                      fontWeight: FontWeight.w700,
                                      color: amount > 0
                                          ? _kGroupInk
                                          : const Color(
                                              0x516B4FB2),
                                      letterSpacing: -1.0,
                                      height: 1.0,
                                    ),
                                    decoration: const InputDecoration(
                                      border: InputBorder.none,
                                      filled: false,
                                      fillColor: Colors.transparent,
                                      hintText: '0.00',
                                      hintStyle: TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0x516B4FB2),
                                        letterSpacing: -1.0,
                                        height: 1.0,
                                      ),
                                      isDense: true,
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                    textInputAction:
                                        TextInputAction.done,
                                    onSubmitted: (_) =>
                                        FocusScope.of(context).unfocus(),
                                    onChanged: (_) {
                                      setState(() {});
                                      _syncSubAmounts();
                                      _autoSetSplitByAmount();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),

                          // Split breakdown — interactive YOU / PARTNER inputs
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              children: [
                                // YOU
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      _GroupAvatar(
                                          initial: userInitial,
                                          bg: Colors.white,
                                          fg: const Color(0xFF5A4AAB),
                                          size: 22),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              context.t('groupExpense.you'),
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                color: _kGroupInkSoft,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  symbol,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: _kGroupInk,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: TextField(
                                                    controller: _youCtrl,
                                                    cursorHeight: 13.0,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w700,
                                                      color: _kGroupInk,
                                                    ),
                                                    decoration: const InputDecoration(
                                                      border: InputBorder.none,
                                                      isDense: true,
                                                      contentPadding: EdgeInsets.zero,
                                                      hintText: '0.00',
                                                      hintStyle: TextStyle(
                                                        fontSize: 13,
                                                        color: _kGroupInkSoft,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    onChanged: (_) => _onYouAmountChanged(),
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
                                // Divider
                                Container(
                                  width: 1,
                                  height: 30,
                                  color: const Color(0x2E6B4FB2),
                                ),
                                const SizedBox(width: 8),
                                // PARTNER
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      _GroupAvatar(
                                          initial: partnerInitial,
                                          bg: Colors.white,
                                          fg: const Color(0xFF1FBE71),
                                          size: 22),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              partnerName.toUpperCase().split(' ').first,
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                color: _kGroupInkSoft,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  symbol,
                                                  style: const TextStyle(
                                                    fontSize: 12,
                                                    color: _kGroupInk,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: TextField(
                                                    controller: _partnerCtrl,
                                                    cursorHeight: 13.0,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    style: const TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w700,
                                                      color: _kGroupInk,
                                                    ),
                                                    decoration: const InputDecoration(
                                                      border: InputBorder.none,
                                                      isDense: true,
                                                      contentPadding: EdgeInsets.zero,
                                                      hintText: '0.00',
                                                      hintStyle: TextStyle(
                                                        fontSize: 13,
                                                        color: _kGroupInkSoft,
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    onChanged: (_) => _onPartnerAmountChanged(),
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
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Category label
                          Text(
                            context.t('groupExpense.category'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _kGroupInk,
                            ),
                          ),
                          const SizedBox(height: 8),

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
                                        right: 10),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
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
                                            size: 18,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          cat.label,
                                          style: TextStyle(
                                            fontSize: 9,
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
                            const SizedBox(height: 8),
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              transitionBuilder: (child, anim) =>
                                  FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: Tween<Offset>(
                                    begin: const Offset(0, 0.3),
                                    end: Offset.zero,
                                  ).animate(anim),
                                  child: child,
                                ),
                              ),
                              child: Row(
                                key: ValueKey(_category),
                                children: [
                                  Container(
                                    width: 5,
                                    height: 5,
                                    decoration: BoxDecoration(
                                      color: catMeta.color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    context.categoryLabel(_category),
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: catMeta.color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: 12),

                          // ── Inner white card ─────────────────
                          Container(
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius:
                                  BorderRadius.circular(18),
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
                                    size: 28,
                                  ),
                                  title: context.t('groupExpense.paidBy'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        paidByName,
                                        style: const TextStyle(
                                          fontSize: 14,
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

                                // Account picker (only shown when current user is payer and has accounts)
                                if (_paidByUid == user?.uid && accounts.isNotEmpty) ...[
                                  _EntryDivider(),
                                  _EntryRow(
                                    onTap: () => _showAccountSheet(accounts),
                                    leading: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF4F4F7),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.creditcard_fill,
                                        color: Color(0xFF5B5B66),
                                        size: 14,
                                      ),
                                    ),
                                    title: context.t('groupExpense.account'),
                                    trailing: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _paidByAccountId != null
                                              ? (accounts.cast<Account?>().firstWhere(
                                                    (a) => a?.id == _paidByAccountId,
                                                    orElse: () => null,
                                                  )?.name ?? context.t('groupExpense.select'))
                                              : context.t('groupExpense.select'),
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF5B5B66),
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        const Icon(CupertinoIcons.chevron_right,
                                            color: Color(0xFFC9C9CF), size: 14),
                                      ],
                                    ),
                                  ),
                                ],

                                _EntryDivider(),

                                // Split — badge auto-reflects current percentages whenever YOU/PARTNER amounts change
                                _EntryRow(
                                  onTap: _showSplitSheet,
                                  leading: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF4F4F7),
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: const Icon(
                                      CupertinoIcons
                                          .arrow_left_right,
                                      color: Color(0xFF5B5B66),
                                      size: 14,
                                    ),
                                  ),
                                  title: context.t('groupExpense.split'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Container(
                                        padding:
                                            const EdgeInsets.fromLTRB(
                                                8, 3, 8, 3),
                                        decoration: BoxDecoration(
                                          color: splitBadgeBg,
                                          borderRadius:
                                              BorderRadius.circular(
                                                  7),
                                        ),
                                        child: Text(
                                          splitLabel,
                                          style: TextStyle(
                                            fontSize: 12,
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
                                  leading: const SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Icon(
                                      CupertinoIcons.calendar,
                                      color: Color(0xFF0B0B0F),
                                      size: 20,
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
                                          fontSize: 14,
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
                                          16, 10, 16, 10),
                                  child: Row(
                                    children: [
                                      const SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: Icon(
                                          CupertinoIcons.doc,
                                          color: Color(0xFF0B0B0F),
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: _notesCtrl,
                                          cursorHeight: 15.0,
                                          textCapitalization:
                                              TextCapitalization
                                                  .sentences,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            color: Color(0xFF0B0B0F),
                                            fontWeight:
                                                FontWeight.w600,
                                          ),
                                          decoration: InputDecoration(
                                            border: InputBorder.none,
                                            hintText: context
                                                .t('groupExpense.note'),
                                            hintStyle: const TextStyle(
                                              fontSize: 14,
                                              color: Color(0xFF8E8E96),
                                              fontWeight: FontWeight.w400,
                                            ),
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
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
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
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
                  // Pill save button — matches personal expense button style
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _saveBtnBounce,
                      builder: (context, child) => Transform.scale(
                        scale: _saveSuccess ? _saveBtnBounce.value : 1.0,
                        child: child,
                      ),
                      child: GestureDetector(
                        onTap: (_saving || _saveSuccess)
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                _save();
                              },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          curve: Curves.easeInOutCubic,
                          height: 56,
                          decoration: BoxDecoration(
                            color: _saveSuccess
                                ? const Color(0xFF1FBE71)
                                : (_saving || _parsedAmount > 0)
                                    ? _kGroupInk
                                    : Colors.white,
                            borderRadius: BorderRadius.circular(28),
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
                                        const SizedBox(width: 9),
                                        Text(
                                          _isEdit
                                              ? context.t('group.entryUpdated')
                                              : context.t('group.entrySaved'),
                                          style: const TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                            letterSpacing: 0.1,
                                          ),
                                        ),
                                      ],
                                    )
                                  : _saving
                                      ? const SizedBox(
                                          key: ValueKey('loading'),
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.white,
                                          ),
                                        )
                                      : Row(
                                          key: const ValueKey('idle'),
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              CupertinoIcons
                                                  .checkmark_circle_fill,
                                              color: _parsedAmount > 0
                                                  ? Colors.white
                                                  : const Color(
                                                      0xFF8E8E96),
                                              size: 20,
                                            ),
                                            const SizedBox(width: 9),
                                            Text(
                                              _isEdit
                                                  ? context
                                                      .t('groupExpense.update')
                                                  : context
                                                      .t('groupExpense.save'),
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight:
                                                    FontWeight.w700,
                                                color: _parsedAmount > 0
                                                    ? Colors.white
                                                    : const Color(
                                                        0xFF8E8E96),
                                                letterSpacing: 0.1,
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
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Row(
          children: [
            leading,
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
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
          Text(
            context.t('groupExpense.whoPaid'),
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0B0B0F),
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.t('groupExpense.whoPaidDesc'),
            style: const TextStyle(fontSize: 14, color: Color(0xFF5B5B66)),
          ),
          const SizedBox(height: 18),
          ...members.map((m) {
            final isYou = m.uid == currentUserId;
            final name =
                isYou ? context.t('group.you') : m.displayName;
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

class _SplitSheet extends StatefulWidget {
  final List<GroupMember> members;
  final String? currentUserId;
  final _SplitMode currentMode;
  final Map<String, double> currentPercents;
  final double amount;
  final String symbol;
  final String partnerName;
  final void Function(_SplitMode, Map<String, double>?) onSelected;

  const _SplitSheet({
    required this.members,
    required this.currentUserId,
    required this.currentMode,
    required this.currentPercents,
    required this.amount,
    required this.symbol,
    required this.partnerName,
    required this.onSelected,
  });

  @override
  State<_SplitSheet> createState() => _SplitSheetState();
}

class _SplitSheetState extends State<_SplitSheet> {
  late _SplitMode _selectedMode;
  late double _myPercent; // 0–100
  late TextEditingController _myAmountCtrl;

  String get _partnerUid =>
      widget.members.firstWhere((m) => m.uid != widget.currentUserId,
          orElse: () => widget.members.first).uid;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.currentMode;
    _myPercent = widget.currentPercents[widget.currentUserId] ?? 50.0;
    final myAmt = widget.amount > 0
        ? (widget.amount * (_myPercent / 100))
        : 0.0;
    _myAmountCtrl = TextEditingController(
      text: myAmt > 0 ? myAmt.toStringAsFixed(2) : '',
    );
  }

  @override
  void dispose() {
    _myAmountCtrl.dispose();
    super.dispose();
  }

  Map<String, double>? _buildPercents() {
    if (_selectedMode == _SplitMode.byPercent) {
      return {
        if (widget.currentUserId != null) widget.currentUserId!: _myPercent,
        _partnerUid: 100.0 - _myPercent,
      };
    } else if (_selectedMode == _SplitMode.byAmount && widget.amount > 0) {
      final myAmt = double.tryParse(_myAmountCtrl.text) ?? 0.0;
      final myPct = (myAmt / widget.amount * 100).clamp(0.0, 100.0);
      return {
        if (widget.currentUserId != null) widget.currentUserId!: myPct,
        _partnerUid: 100.0 - myPct,
      };
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final options = [
      _SplitOptionData(
        mode: _SplitMode.noSplit,
        title: context.t('groupExpense.splitNoSplit'),
        subtitle: context.t('groupExpense.splitNoSplitDesc'),
        badge: context.t('groupExpense.splitNoSplitBadge'),
        badgeBg: const Color(0xFFEEEEF1),
        badgeFg: const Color(0xFF5B5B66),
      ),
      _SplitOptionData(
        mode: _SplitMode.even,
        title: context.t('groupExpense.splitEvenly'),
        subtitle: widget.amount > 0
            ? context.t('groupExpense.splitEvenlyAmt').replaceAll(
                '{amount}',
                '${widget.symbol}${(widget.amount / 2).toStringAsFixed(2)}')
            : context.t('groupExpense.splitEqualBoth'),
        badge: context.t('groupExpense.fiftyFifty'),
        badgeBg: const Color(0xFFD7F4E5),
        badgeFg: const Color(0xFF1A8E54),
      ),
      _SplitOptionData(
        mode: _SplitMode.byPercent,
        title: context.t('groupExpense.splitByPercent'),
        subtitle: context.t('groupExpense.splitByPercentDesc'),
        badge: context.t('groupExpense.splitByPercentBadge'),
        badgeBg: const Color(0xFFEAE3F8),
        badgeFg: const Color(0xFF5A4AAB),
      ),
      _SplitOptionData(
        mode: _SplitMode.byAmount,
        title: context.t('groupExpense.splitByAmount'),
        subtitle: context.t('groupExpense.splitByAmountDesc'),
        badge: context.t('groupExpense.splitByAmountBadge'),
        badgeBg: const Color(0xFFFFF1D2),
        badgeFg: const Color(0xFF9A6B00),
      ),
      _SplitOptionData(
        mode: _SplitMode.youOwe,
        title: context
            .t('groupExpense.youOweAll')
            .replaceAll('{partner}', widget.partnerName),
        subtitle: widget.amount > 0
            ? context.t('groupExpense.youOweAllDesc').replaceAll(
                '{amount}',
                '${widget.symbol}${widget.amount.toStringAsFixed(2)}')
            : context.t('groupExpense.youCover'),
        badge: context.t('groupExpense.youOweBadge'),
        badgeBg: const Color(0xFFFBDDE0),
        badgeFg: const Color(0xFFC03340),
      ),
      _SplitOptionData(
        mode: _SplitMode.theyOwe,
        title: context
            .t('groupExpense.theyOweAll')
            .replaceAll('{partner}', widget.partnerName),
        subtitle: widget.amount > 0
            ? context
                .t('groupExpense.theyOweAllDesc')
                .replaceAll('{partner}', widget.partnerName)
                .replaceAll(
                    '{amount}',
                    '${widget.symbol}${widget.amount.toStringAsFixed(2)}')
            : context.t('groupExpense.theyCover'),
        badge: context.t('groupExpense.theyOweBadge'),
        badgeBg: const Color(0xFFFFF1D2),
        badgeFg: const Color(0xFF9A6B00),
      ),
    ];

    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          topRight: Radius.circular(30),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Fixed header — swipe down here to close ─────────
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 150) Navigator.pop(context);
            },
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 10),
              child: Column(
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
                  Text(
                    context.t('groupExpense.howToSplit'),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0B0B0F),
                      letterSpacing: -0.4,
                    ),
                  ),
                  if (widget.amount > 0)
                    Text(
                      context
                          .t('groupExpense.amountBetween')
                          .replaceAll('{amount}',
                              '${widget.symbol}${widget.amount.toStringAsFixed(2)}')
                          .replaceAll('{partner}', widget.partnerName),
                      style: const TextStyle(
                          fontSize: 14, color: Color(0xFF5B5B66)),
                    ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          // ── Scrollable content ──────────────────────────────
          Flexible(
            child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 4, 24, keyboardH + safeBottom + 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          ...options.map((opt) {
            final selected = opt.mode == _selectedMode;
            return GestureDetector(
              onTap: () {
                setState(() => _selectedMode = opt.mode);
                if (opt.mode != _SplitMode.byPercent &&
                    opt.mode != _SplitMode.byAmount) {
                  widget.onSelected(opt.mode, null);
                }
              },
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

          // Custom percent input
          if (_selectedMode == _SplitMode.byPercent) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${context.t('group.you')}: ${_myPercent.toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF5A4AAB))),
                      const Spacer(),
                      Text('${widget.partnerName}: ${(100 - _myPercent).toStringAsFixed(0)}%',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1FBE71))),
                    ],
                  ),
                  Slider(
                    value: _myPercent,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    activeColor: const Color(0xFF1A6CFF),
                    onChanged: (v) => setState(() => _myPercent = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: const Color(0xFF1A6CFF),
                borderRadius: BorderRadius.circular(16),
                onPressed: () => widget.onSelected(_selectedMode, _buildPercents()),
                child: Text(context.t('groupExpense.confirmSplit'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],

          // Custom amount input — always show when byAmount is selected
          if (_selectedMode == _SplitMode.byAmount) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(context.t('groupExpense.yourAmount').replaceAll('{symbol}', widget.symbol),
                      style: const TextStyle(fontSize: 13, color: Color(0xFF5B5B66))),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _myAmountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '0.00',
                      prefixText: '${widget.symbol}  ',
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Builder(builder: (_) {
                    final myAmt = double.tryParse(_myAmountCtrl.text) ?? 0.0;
                    final partnerAmt = (widget.amount - myAmt).clamp(0.0, widget.amount);
                    return Text(
                      '${widget.partnerName}: ${widget.symbol}${partnerAmt.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13, color: Color(0xFF5B5B66)),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: const Color(0xFF1A6CFF),
                borderRadius: BorderRadius.circular(16),
                onPressed: () => widget.onSelected(_selectedMode, _buildPercents()),
                child: Text(context.t('groupExpense.confirmSplit'), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
              ),
            ),
          ],
        ],
        ),
        ), // end SingleChildScrollView
          ), // end Flexible
        ],
      ), // end Column
    ); // end Container
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
