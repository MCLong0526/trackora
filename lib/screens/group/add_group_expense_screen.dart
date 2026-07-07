import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/account.dart';
import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../repositories/local_expense_group_repository.dart';
import '../../services/amount_calc.dart';
import '../../services/i18n.dart';
import '../../widgets/amount_operator_bar.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../settings/manage_categories_screen.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/receipt_preview.dart';

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
  final _notesFocus = FocusNode();
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

  // Swipe-to-close
  late AnimationController _closeCtrl;
  late AnimationController _snapCtrl;
  double _dragOffset = 0.0;
  double _snapStartOffset = 0.0;

  // Receipt
  File? _newReceipt;
  String? _existingReceiptUrl;

  // Scroll fades
  final _scrollCtrl = ScrollController();
  bool _scrolled = false; // not at top → show top fade
  bool _atBottom = true; // at bottom (or not scrollable) → hide bottom fade

  late AnimationController _saveBtnCtrl;
  late Animation<double> _saveBtnBounce;

  bool get _isEdit => widget.existing != null;
  double get _parsedAmount =>
      evalAmount(_amountCtrl.text.trim()) ?? 0;

  // Theme-aware tokens for the group "hero card". In light mode they keep the
  // original lavender palette; in dark mode they flip to a dark elevated card
  // with readable light-lavender ink so the screen matches the personal
  // expense dark design instead of showing a bright purple block.
  bool get _isDark => Theme.of(context).brightness == Brightness.dark;
  Color get _cardTint => _isDark ? const Color(0xFF221E2B) : _kGroupTint;
  Color get _groupInk => _isDark ? const Color(0xFFD9C9F5) : _kGroupInk;
  Color get _groupInkSoft =>
      _isDark ? const Color(0xFF9C90B6) : _kGroupInkSoft;
  // Faded amount-placeholder ink.
  Color get _groupInkFaint =>
      _isDark ? const Color(0x66D9C9F5) : const Color(0x516B4FB2);
  // Inner translucent tile sitting on top of the hero card.
  Color get _groupTileBg => _isDark
      ? Colors.white.withValues(alpha: 0.06)
      : context.brand.surface.withValues(alpha: 0.55);
  // Primary save-button fill (vivid purple in dark so white text stays legible).
  Color get _groupBtnBg => _isDark ? const Color(0xFF7C5CD6) : _kGroupInk;

  @override
  void initState() {
    super.initState();
    attachAmountCalculator(_amountCtrl, _amountFocus);
    _closeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _saveBtnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _saveBtnBounce = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.07), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.07, end: 0.95), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _saveBtnCtrl, curve: Curves.easeOut));

    _scrollCtrl.addListener(_updateFadeState);

    // When the note field gains focus, scroll it into view above the keyboard.
    _notesFocus.addListener(() {
      if (!_notesFocus.hasFocus) return;
      // Wait for the keyboard to push the viewport up, then reveal the note.
      Future.delayed(const Duration(milliseconds: 250), () {
        if (!mounted || !_scrollCtrl.hasClients) return;
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
        );
      });
    });

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
      _existingReceiptUrl = e.receiptUrl;
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

    // Resolve the initial fade state once the content has been laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateFadeState());
  }

  // Recompute fade visibility: top fade shows when scrolled away from the top,
  // bottom fade shows only when there is more content below (not at the end).
  void _updateFadeState() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    final hasOverflow = pos.maxScrollExtent > 0;
    final atTop = _scrollCtrl.offset <= 4;
    final atBottom = _scrollCtrl.offset >= pos.maxScrollExtent - 4;
    final newScrolled = hasOverflow && !atTop;
    final newAtBottom = !hasOverflow || atBottom;
    if (newScrolled != _scrolled || newAtBottom != _atBottom) {
      setState(() {
        _scrolled = newScrolled;
        _atBottom = newAtBottom;
      });
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    _amountFocus.dispose();
    _notesFocus.dispose();
    _youCtrl.dispose();
    _partnerCtrl.dispose();
    _saveBtnCtrl.dispose();
    _closeCtrl.dispose();
    _snapCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ─── Swipe-to-close ───────────────────────────────────────────────────────

  void _onSnapTick() {
    if (!mounted) return;
    setState(() {
      _dragOffset =
          _snapStartOffset *
          (1.0 - Curves.easeOutCubic.transform(_snapCtrl.value));
    });
    if (_snapCtrl.isCompleted) {
      _snapCtrl.removeListener(_onSnapTick);
      _dragOffset = 0.0;
      _snapStartOffset = 0.0;
    }
  }

  void _snapBack() {
    _snapStartOffset = _dragOffset;
    _snapCtrl
      ..stop()
      ..reset()
      ..removeListener(_onSnapTick)
      ..addListener(_onSnapTick)
      ..forward();
  }

  Future<void> _animatedClose() async {
    if (_closeCtrl.isAnimating) return;
    _snapCtrl.stop();
    FocusScope.of(context).unfocus();
    HapticFeedback.lightImpact();
    await _closeCtrl.forward();
    if (mounted) Navigator.pop(context);
  }

  Widget _buildDragHandle() {
    final pillW = (36.0 + (_dragOffset * 0.3).clamp(0.0, 20.0));
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onVerticalDragUpdate: (details) {
        final dy = details.delta.dy;
        if (dy > 0 || _dragOffset > 0) {
          setState(() {
            _dragOffset = (_dragOffset + dy).clamp(0.0, 260.0);
          });
        }
      },
      onVerticalDragEnd: (details) {
        final velocity = details.primaryVelocity ?? 0;
        if (_dragOffset > 90 || velocity > 600) {
          _animatedClose();
        } else {
          _snapBack();
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: pillW,
              height: 4,
              decoration: BoxDecoration(
                color: _groupInkSoft.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'swipe down to close',
              style: TextStyle(
                fontSize: 11,
                color: _groupInkSoft.withValues(alpha: 0.55),
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Receipt ──────────────────────────────────────────────────────────────

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 70);
    if (picked != null) setState(() => _newReceipt = File(picked.path));
  }

  Widget _buildReceiptRow() {
    final hasNew = _newReceipt != null;
    final hasExisting = _existingReceiptUrl != null;

    final brand = context.brand;

    if (!hasNew && !hasExisting) {
      return InkWell(
        onTap: _pickReceipt,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: Icon(CupertinoIcons.paperclip, color: brand.ink, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Attach receipt',
                  style: TextStyle(fontSize: 14, color: brand.inkSoft),
                ),
              ),
              Icon(CupertinoIcons.chevron_right, color: brand.inkSoft, size: 14),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: Icon(CupertinoIcons.paperclip, color: brand.ink, size: 18),
          ),
          const SizedBox(width: 12),
          if (hasNew)
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const Text('Receipt')),
                    body: Center(
                      child: InteractiveViewer(
                        child: Image.file(_newReceipt!, fit: BoxFit.contain),
                      ),
                    ),
                  ),
                  fullscreenDialog: true,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(_newReceipt!, width: 44, height: 44, fit: BoxFit.cover),
              ),
            )
          else
            ReceiptPreview(stored: _existingReceiptUrl!, size: 44, fit: BoxFit.cover),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              hasNew ? 'New attachment' : 'Saved attachment',
              style: TextStyle(fontSize: 14, color: brand.ink, fontWeight: FontWeight.w500),
            ),
          ),
          GestureDetector(
            onTap: _pickReceipt,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF6B4FB2).withValues(alpha: _isDark ? 0.28 : 0.10),
                shape: BoxShape.circle,
              ),
              child: Icon(CupertinoIcons.pencil, size: 15, color: _isDark ? const Color(0xFFCBB8F0) : const Color(0xFF6B4FB2)),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() {
              _newReceipt = null;
              _existingReceiptUrl = null;
            }),
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFD93025).withValues(alpha: 0.10),
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.delete, size: 15, color: Color(0xFFD93025)),
            ),
          ),
        ],
      ),
    );
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

    final amount = evalAmount(_amountCtrl.text.trim());
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
      // Upload receipt if a new one was selected
      String? receiptUrl = _existingReceiptUrl;
      if (_newReceipt != null) {
        final isOnline = ref.read(isOnlineProvider);
        final storage = ref.read(storageServiceProvider);
        try {
          if (isOnline) {
            receiptUrl = await storage.saveReceipt(user.uid, _newReceipt!);
          } else {
            receiptUrl = await storage.saveReceiptLocally(user.uid, _newReceipt!);
          }
        } catch (_) {
          receiptUrl = _existingReceiptUrl;
        }
      }

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
        receiptUrl: receiptUrl,
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
            receiptUrl: expense.receiptUrl,
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
    FocusScope.of(context).unfocus();
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 260,
        color: Theme.of(context).brightness == Brightness.dark
            ? context.brand.background
            : _kBg,
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: _date,
          maximumDate: DateTime.now().add(const Duration(days: 1)),
          onDateTimeChanged: (dt) => setState(() => _date = dt),
        ),
      ),
    ).whenComplete(_dismissKeyboard);
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
    ).whenComplete(_dismissKeyboard);
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
    FocusScope.of(context).unfocus();
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
    ).whenComplete(_dismissKeyboard);
  }

  // Clear focus after a picker closes so the form's amount field doesn't
  // regain focus and re-open the keyboard/numpad.
  void _dismissKeyboard() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).unfocus();
    });
  }

  void _showSplitSheet() {
    FocusScope.of(context).unfocus();
    final user = ref.read(authStateProvider).valueOrNull;
    final partner = widget.group.members
        .where((m) => m.uid != user?.uid)
        .firstOrNull;
    final symbol = ref.read(currencySymbolProvider).valueOrNull ?? '';
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        final mq = MediaQuery.of(ctx);
        final keyboardH = mq.viewInsets.bottom;
        // Leave a comfortable gap below the status bar so the sheet never
        // reaches the very top, and shrink as the keyboard rises so the inner
        // scroll area takes the squeeze (Confirm button stays above keyboard).
        final topGap = mq.padding.top + 64;
        final maxH = mq.size.height - topGap - keyboardH;
        return Padding(
          padding: EdgeInsets.only(bottom: keyboardH),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH > 0 ? maxH : mq.size.height * 0.7),
            child: _SplitSheet(
              members: widget.group.members,
              currentUserId: user?.uid,
              currentMode: _splitMode,
              currentPercents: _splitCustomPercents,
              amount: _parsedAmount,
              symbol: symbol,
              partnerName: partner?.displayName ?? context.t('group.partnerFallback'),
              onSelected: (mode, percents) {
                FocusScope.of(context).unfocus();
                _setSplitMode(mode, customPercents: percents);
                Navigator.pop(context);
              },
            ),
          ),
        );
      },
    ).whenComplete(_dismissKeyboard);
  }

  /// Built-in group categories plus the user's custom expense categories, so
  /// the group flow offers the same "customize" set as personal expenses.
  List<_CatMeta> _buildCategoryMetas() {
    // Most-recently-added custom categories first, then the built-ins.
    final custom = ((ref.watch(customCategoriesProvider).valueOrNull ?? const [])
            .where((c) => !c.isIncome)
            .toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt)));
    if (custom.isEmpty) return _kCategories;
    final customMetas = [
      for (final c in custom)
        _CatMeta(c.name, styleFor(c.name).icon, styleFor(c.name).accent),
    ];
    return [...customMetas, ..._kCategories];
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

    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final catMetas = _buildCategoryMetas();
    final catMeta = catMetas.firstWhere(
      (c) => c.label == _category,
      orElse: () => catMetas.last,
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
      backgroundColor: isDark ? brand.background : _kBg,
      body: AnimatedBuilder(
        animation: _closeCtrl,
        builder: (context, child) {
          final t = Curves.easeInCubic.transform(_closeCtrl.value);
          final screenH = MediaQuery.of(context).size.height;
          final totalY = _dragOffset + t * screenH * 0.26;
          final scale = (1.0 - totalY / (screenH * 1.6)).clamp(0.78, 1.0);
          final opacity = (1.0 - totalY / 230.0).clamp(0.0, 1.0);
          return Opacity(
            opacity: opacity,
            child: Transform.translate(
              offset: Offset(0, totalY),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
          );
        },
        child: SafeArea(
        child: Column(
          children: [
            _buildDragHandle(),
            const SizedBox(height: 6),

            // ── Purple card — fixed top, scrollable inner card ──
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: Container(
                  color: _cardTint,
                  child: Stack(
                    children: [
                      NotificationListener<ScrollMetricsNotification>(
                        onNotification: (_) {
                          WidgetsBinding.instance.addPostFrameCallback(
                              (_) => _updateFadeState());
                          return false;
                        },
                        child: SingleChildScrollView(
                          controller: _scrollCtrl,
                          physics: const BouncingScrollPhysics(
                            parent: AlwaysScrollableScrollPhysics(),
                          ),
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                          // Hero row: avatar pair + title
                          Row(
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: _groupTileBg,
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
                                            bg: brand.surface,
                                            fg: const Color(
                                                0xFF5A4AAB),
                                            size: 26),
                                        if (partner != null)
                                          Positioned(
                                            left: 14,
                                            child: _GroupAvatar(
                                                initial:
                                                    partnerInitial,
                                                bg: brand.surface,
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
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.w700,
                                        color: _groupInk,
                                        letterSpacing: -0.4,
                                        height: 1.1,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      context
                                          .t('groupExpense.splittingWith')
                                          .replaceAll('{name}', partnerName),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: _groupInkSoft,
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
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: _groupInkSoft,
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
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: _groupInk,
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
                                          ? _groupInk
                                          : _groupInkFaint,
                                      letterSpacing: -1.0,
                                      height: 1.0,
                                    ),
                                    decoration: InputDecoration(
                                      border: InputBorder.none,
                                      enabledBorder: InputBorder.none,
                                      focusedBorder: InputBorder.none,
                                      filled: false,
                                      fillColor: Colors.transparent,
                                      hintText: '0.00',
                                      hintStyle: TextStyle(
                                        fontSize: 34,
                                        fontWeight: FontWeight.w600,
                                        color: _groupInkFaint,
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

                          AmountOperatorBar(
                            controller: _amountCtrl,
                            focusNode: _amountFocus,
                          ),

                          // Split breakdown — interactive YOU / PARTNER inputs
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                            decoration: BoxDecoration(
                              color: _groupTileBg,
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
                                          bg: brand.surface,
                                          fg: const Color(0xFF5A4AAB),
                                          size: 22),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              context.t('groupExpense.you'),
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                color: _groupInkSoft,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  symbol,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: _groupInk,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: TextField(
                                                    controller: _youCtrl,
                                                    cursorHeight: 13.0,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w700,
                                                      color: _groupInk,
                                                    ),
                                                    decoration: InputDecoration(
                                                      border: InputBorder.none,
                                                      enabledBorder: InputBorder.none,
                                                      focusedBorder: InputBorder.none,
                                                      filled: false,
                                                      isDense: true,
                                                      contentPadding: EdgeInsets.zero,
                                                      hintText: '0.00',
                                                      hintStyle: TextStyle(
                                                        fontSize: 13,
                                                        color: _groupInkSoft,
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
                                  color: _groupInkSoft.withValues(alpha: 0.25),
                                ),
                                const SizedBox(width: 8),
                                // PARTNER
                                Expanded(
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      _GroupAvatar(
                                          initial: partnerInitial,
                                          bg: brand.surface,
                                          fg: const Color(0xFF1FBE71),
                                          size: 22),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              partnerName.toUpperCase().split(' ').first,
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w600,
                                                color: _groupInkSoft,
                                                letterSpacing: 0.2,
                                              ),
                                            ),
                                            Row(
                                              children: [
                                                Text(
                                                  symbol,
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    color: _groupInk,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                Expanded(
                                                  child: TextField(
                                                    controller: _partnerCtrl,
                                                    cursorHeight: 13.0,
                                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight: FontWeight.w700,
                                                      color: _groupInk,
                                                    ),
                                                    decoration: InputDecoration(
                                                      border: InputBorder.none,
                                                      enabledBorder: InputBorder.none,
                                                      focusedBorder: InputBorder.none,
                                                      filled: false,
                                                      isDense: true,
                                                      contentPadding: EdgeInsets.zero,
                                                      hintText: '0.00',
                                                      hintStyle: TextStyle(
                                                        fontSize: 13,
                                                        color: _groupInkSoft,
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
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _groupInk,
                            ),
                          ),
                          const SizedBox(height: 8),

                          // Category circles (horizontal scroll)
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                // Customize chip (leading): add / edit custom
                                // categories.
                                GestureDetector(
                                  onTap: () async {
                                    FocusScope.of(context).unfocus();
                                    HapticFeedback.selectionClick();
                                    await Navigator.push(
                                      context,
                                      CupertinoPageRoute(
                                        builder: (_) =>
                                            const ManageCategoriesScreen(),
                                      ),
                                    );
                                    if (mounted) setState(() {});
                                  },
                                  child: Container(
                                    margin:
                                        const EdgeInsets.only(right: 10),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: 44,
                                          height: 44,
                                          decoration: BoxDecoration(
                                            color: brand.surface,
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                                color: brand.divider),
                                          ),
                                          child: Icon(CupertinoIcons.add,
                                              color: _groupInkSoft,
                                              size: 18),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          context.t('category.customize'),
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: _groupInkSoft,
                                            fontWeight: FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                ...catMetas.map((cat) {
                                final active =
                                    cat.label == _category;
                                return GestureDetector(
                                  onTap: () {
                                    FocusScope.of(context).unfocus();
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
                                                : brand.surface,
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
                                          context.categoryLabel(cat.label),
                                          style: TextStyle(
                                            fontSize: 9,
                                            color: active
                                                ? _groupInk
                                                : _groupInkSoft,
                                            fontWeight: active
                                                ? FontWeight.w600
                                                : FontWeight.w400,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                                }),
                              ],
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
                          // Inner white card
                          Container(
                            decoration: BoxDecoration(
                              color: brand.surface,
                              borderRadius: BorderRadius.circular(18),
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
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: brand.inkSoft,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                          CupertinoIcons
                                              .chevron_right,
                                          color: brand.inkSoft,
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
                                        color: brand.background,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        CupertinoIcons.creditcard_fill,
                                        color: brand.inkSoft,
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
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: brand.inkSoft,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Icon(CupertinoIcons.chevron_right,
                                            color: brand.inkSoft, size: 14),
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
                                      color: brand.background,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Icon(
                                      CupertinoIcons
                                          .arrow_left_right,
                                      color: brand.inkSoft,
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
                                      Icon(
                                          CupertinoIcons
                                              .chevron_right,
                                          color: brand.inkSoft,
                                          size: 14),
                                    ],
                                  ),
                                ),

                                _EntryDivider(),

                                // Date
                                _EntryRow(
                                  onTap: _pickDate,
                                  leading: SizedBox(
                                    width: 28,
                                    height: 28,
                                    child: Icon(
                                      CupertinoIcons.calendar,
                                      color: brand.ink,
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
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: brand.inkSoft,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                          CupertinoIcons
                                              .chevron_right,
                                          color: brand.inkSoft,
                                          size: 14),
                                    ],
                                  ),
                                ),

                                _EntryDivider(),

                                // Receipt
                                _buildReceiptRow(),

                                _EntryDivider(),

                                // Note
                                Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(
                                          16, 10, 16, 10),
                                  child: Row(
                                    children: [
                                      SizedBox(
                                        width: 28,
                                        height: 28,
                                        child: Icon(
                                          CupertinoIcons.doc,
                                          color: brand.ink,
                                          size: 18,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: TextField(
                                          controller: _notesCtrl,
                                          focusNode: _notesFocus,
                                          maxLines: null,
                                          minLines: 1,
                                          cursorHeight: 15.0,
                                          textCapitalization:
                                              TextCapitalization
                                                  .sentences,
                                          style: TextStyle(
                                            fontSize: 14,
                                            color: brand.ink,
                                            fontWeight:
                                                FontWeight.w600,
                                          ),
                                          decoration: InputDecoration(
                                            border: InputBorder.none,
                                            hintText: context
                                                .t('groupExpense.note'),
                                            hintStyle: TextStyle(
                                              fontSize: 14,
                                              color: brand.inkSoft,
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
                          ),    // Container (inner white card)
                            ],
                          ),    // Column (scroll content)
                        ),      // SingleChildScrollView
                      ),        // NotificationListener
                          // Bottom fade — hidden once scrolled to the very end
                          Positioned(
                            left: 0, right: 0, bottom: 0,
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _atBottom ? 0.0 : 1.0,
                                child: Container(
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [_cardTint.withValues(alpha: 0), _cardTint],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Top fade — visible only when scrolled away from top
                          Positioned(
                            left: 0, right: 0, top: 0,
                            child: IgnorePointer(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 200),
                                opacity: _scrolled ? 1.0 : 0.0,
                                child: Container(
                                  height: 32,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      begin: Alignment.topCenter,
                                      end: Alignment.bottomCenter,
                                      colors: [_cardTint, _cardTint.withValues(alpha: 0)],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],    // Stack children
                      ),      // Stack
                  ),          // Container (purple card)
                ),            // ClipRRect
              ),              // Padding
            ),                // Expanded

            // ── Save bar ─────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Row(
                children: [
                  if (_isEdit) ...[
                    GestureDetector(
                      onTap: _delete,
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: const BoxDecoration(
                          color: Color(0xFFFFEEEE),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          CupertinoIcons.delete,
                          color: Color(0xFFD93025),
                          size: 20,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  // Circle category icon
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: brand.surface,
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
                                    ? _groupBtnBg
                                    : brand.surface,
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
    final brand = context.brand;
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
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
      color: context.brand.divider,
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
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? brand.background : _kBg,
        borderRadius: const BorderRadius.only(
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
                color: brand.divider,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            context.t('groupExpense.whoPaid'),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: brand.ink,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.t('groupExpense.whoPaidDesc'),
            style: TextStyle(fontSize: 14, color: brand.inkSoft),
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
                  color: brand.surface,
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
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: brand.ink,
                            ),
                          ),
                          if (!isYou)
                            Text(
                              m.displayName,
                              style: TextStyle(
                                  fontSize: 13,
                                  color: brand.inkSoft),
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
  final _amountFocus = FocusNode();
  final _sheetScrollCtrl = ScrollController();
  bool _sheetAtBottom = true; // at end (or no overflow) → hide bottom fade

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
    _sheetScrollCtrl.addListener(_updateSheetFade);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateSheetFade());
  }

  void _updateSheetFade() {
    if (!_sheetScrollCtrl.hasClients) return;
    final pos = _sheetScrollCtrl.position;
    final hasOverflow = pos.maxScrollExtent > 0;
    final atBottom = _sheetScrollCtrl.offset >= pos.maxScrollExtent - 4;
    final next = !hasOverflow || atBottom;
    if (next != _sheetAtBottom) setState(() => _sheetAtBottom = next);
  }

  @override
  void dispose() {
    _myAmountCtrl.dispose();
    _amountFocus.dispose();
    _sheetScrollCtrl.dispose();
    super.dispose();
  }

  void _selectMode(_SplitMode mode) {
    setState(() => _selectedMode = mode);
    if (mode == _SplitMode.byAmount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _amountFocus.requestFocus();
      });
    } else if (mode != _SplitMode.byPercent) {
      widget.onSelected(mode, null);
    }
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

    final safeBottom = MediaQuery.of(context).padding.bottom;

    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? brand.background : _kBg,
        borderRadius: const BorderRadius.only(
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
                        color: brand.divider,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    context.t('groupExpense.howToSplit'),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
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
                      style: TextStyle(
                          fontSize: 14, color: brand.inkSoft),
                    ),
                  const SizedBox(height: 4),
                ],
              ),
            ),
          ),
          // ── Scrollable content with bottom fade ─────────────
          Flexible(
            child: Stack(
              children: [
            NotificationListener<ScrollMetricsNotification>(
              onNotification: (_) {
                WidgetsBinding.instance.addPostFrameCallback(
                    (_) => _updateSheetFade());
                return false;
              },
              child: SingleChildScrollView(
            controller: _sheetScrollCtrl,
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 48),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
          ...options.map((opt) {
            final selected = opt.mode == _selectedMode;
            final showInlineInput = selected &&
                (opt.mode == _SplitMode.byPercent || opt.mode == _SplitMode.byAmount);
            return GestureDetector(
              onTap: () => _selectMode(opt.mode),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: brand.surface,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      opt.title,
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w700,
                                        color: brand.ink,
                                        letterSpacing: -0.2,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
                                    decoration: BoxDecoration(
                                      color: opt.badgeBg,
                                      borderRadius: BorderRadius.circular(6),
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
                                style: TextStyle(fontSize: 13, color: brand.inkSoft),
                              ),
                              if (opt.mode == _SplitMode.even) ...[
                                const SizedBox(height: 10),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    height: 8,
                                    child: Row(
                                      children: [
                                        Expanded(child: Container(color: const Color(0xFF5A4AAB))),
                                        Expanded(child: Container(color: const Color(0xFF1FBE71))),
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
                            color: selected ? const Color(0xFF1A6CFF) : Colors.transparent,
                            shape: BoxShape.circle,
                            border: selected
                                ? null
                                : Border.all(color: const Color(0xFFD1D1D6), width: 2),
                          ),
                          child: selected
                              ? const Icon(CupertinoIcons.checkmark, color: Colors.white, size: 13)
                              : null,
                        ),
                      ],
                    ),
                    // Inline expansion for byPercent / byAmount
                    AnimatedSize(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      child: showInlineInput
                          ? Padding(
                              padding: const EdgeInsets.only(top: 14),
                              child: opt.mode == _SplitMode.byPercent
                                  ? Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              '${context.t('group.you')}: ${_myPercent.toStringAsFixed(0)}%',
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF5A4AAB)),
                                            ),
                                            const Spacer(),
                                            Text(
                                              '${widget.partnerName}: ${(100 - _myPercent).toStringAsFixed(0)}%',
                                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1FBE71)),
                                            ),
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
                                    )
                                  : Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          context.t('groupExpense.yourAmount').replaceAll('{symbol}', widget.symbol),
                                          style: TextStyle(fontSize: 13, color: brand.inkSoft),
                                        ),
                                        const SizedBox(height: 8),
                                        TextField(
                                          controller: _myAmountCtrl,
                                          focusNode: _amountFocus,
                                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (_) => _amountFocus.unfocus(),
                                          onChanged: (_) => setState(() {}),
                                          decoration: InputDecoration(
                                            hintText: '0.00',
                                            prefixText: '${widget.symbol}  ',
                                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                            filled: true,
                                            fillColor: brand.background,
                                            border: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              borderSide: BorderSide.none,
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              borderSide: BorderSide.none,
                                            ),
                                            focusedBorder: OutlineInputBorder(
                                              borderRadius: BorderRadius.circular(10),
                                              borderSide: BorderSide.none,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Builder(builder: (ctx) {
                                          final myAmt = double.tryParse(_myAmountCtrl.text) ?? 0.0;
                                          final partnerAmt = (widget.amount - myAmt).clamp(0.0, widget.amount);
                                          return Text(
                                            '${widget.partnerName}: ${widget.symbol}${partnerAmt.toStringAsFixed(2)}',
                                            style: TextStyle(fontSize: 13, color: brand.inkSoft),
                                          );
                                        }),
                                      ],
                                    ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
        ),
        ), // end SingleChildScrollView
        ), // end NotificationListener
              // Bottom fade overlay — hidden once scrolled to the end
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _sheetAtBottom ? 0.0 : 1.0,
                    child: Container(
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            (isDark ? brand.background : _kBg).withValues(alpha: 0),
                            isDark ? brand.background : _kBg,
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              ],
            ), // end Stack
          ), // end Flexible
          // ── Fixed Confirm Split button ───────────────────────
          if (_selectedMode == _SplitMode.byPercent || _selectedMode == _SplitMode.byAmount)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: SizedBox(
                width: double.infinity,
                child: CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  color: const Color(0xFF1A6CFF),
                  borderRadius: BorderRadius.circular(16),
                  onPressed: () => widget.onSelected(_selectedMode, _buildPercents()),
                  child: Text(
                    context.t('groupExpense.confirmSplit'),
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
            ),
          SizedBox(height: safeBottom + 8),
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
