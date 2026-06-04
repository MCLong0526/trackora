import 'dart:developer' as dev;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/account.dart';
import '../../models/expense.dart';
import '../../models/split_bill.dart';
import '../../repositories/local_expense_repository.dart';
import '../../repositories/local_split_bill_repository.dart';
import '../../repositories/split_bill_repository.dart';
import '../../screens/accounts/add_edit_account_screen.dart';
import '../../models/person.dart';
import '../../screens/expenses/bill_receipt_screen.dart';
import '../../screens/expenses/split_bill_screen.dart';
import '../../screens/people/people_screen.dart';
import '../../services/i18n.dart';
import '../../services/prefs_service.dart';
import '../../services/sync_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/currency_picker.dart';
import '../../widgets/receipt_preview.dart';
import '../../widgets/section_card.dart';

const kExpenseCategories = [
  'Food',
  'Groceries',
  'Transport',
  'Shopping',
  'Entertainment',
  'Health',
  'Bills',
  'PreciousMetal',
  'Stock',
  'Others',
];

const kIncomeCategories = ['Salary', 'PreciousMetal', 'Stock', 'Others'];

class AddEditExpenseScreen extends ConsumerStatefulWidget {
  final Expense? expense;

  /// When set, pre-fills the form from this expense but saves as a NEW record.
  final Expense? copyFrom;
  final EntryType? initialType;
  final double? initialAmount;
  final String? initialToAccountId;

  const AddEditExpenseScreen({
    super.key,
    this.expense,
    this.copyFrom,
    this.initialType,
    this.initialAmount,
    this.initialToAccountId,
  });

  @override
  ConsumerState<AddEditExpenseScreen> createState() =>
      _AddEditExpenseScreenState();
}

class _AddEditExpenseScreenState extends ConsumerState<AddEditExpenseScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();
  final _counterpartController = TextEditingController();
  final _amountFocus = FocusNode();

  late AnimationController _entranceCtrl;
  late Animation<double> _entranceFade;
  late Animation<Offset> _entranceSlide;

  late AnimationController _closeCtrl;
  late AnimationController _snapCtrl;
  double _dragOffset = 0.0;
  double _snapStartOffset = 0.0;

  late AnimationController _saveBtnCtrl;
  late Animation<double> _saveBtnBounce;
  bool _saveSuccess = false;

  late AnimationController _typeMenuCtrl;
  late List<Animation<double>> _typeChipAnimations;
  bool _typeMenuOpen = false;

  late PageController _typePageCtrl;
  double _typePageOffset = 0;

  late EntryType _type;
  String _category = kExpenseCategories.first;
  DateTime _date = DateTime.now();
  String? _accountId;
  String? _toAccountId;
  bool _isAccountTransfer = false;
  bool _saving = false;
  bool _hasValidAmount = false;
  String _currencyCode = 'MYR';
  File? _newReceipt;
  String? _existingReceiptUrl;

  bool _swipeHintVisible = true;

  final _cardScrollCtrl = ScrollController();
  bool _cardScrolled = false; // not at top → show top fade
  bool _cardAtBottom = true; // at bottom (or no overflow) → hide bottom fade

  bool _splitBillEnabled = false;
  List<SplitMember> _splitMembers = [];
  SplitMode _splitMode = SplitMode.equally;
  double _splitBillTotal =
      0.0; // total of the whole bill (not just payer's share)
  SplitBill? _splitBill;

  bool get _isEdit => widget.expense != null;

  Color get _typeColor {
    switch (_type) {
      case EntryType.income:
        return const Color(0xFF1F7A60);
      case EntryType.transfer:
        return const Color(0xFFB23A4A);
      case EntryType.receive:
        return const Color(0xFF2A6FB5);
      case EntryType.expense:
        return const Color(0xFF6B40A8);
    }
  }

  @override
  void initState() {
    super.initState();

    _entranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceCtrl,
      curve: Curves.easeOut,
    );
    _entranceSlide =
        Tween<Offset>(begin: const Offset(0, 0.05), end: Offset.zero).animate(
          CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOutCubic),
        );

    _closeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 360),
    );

    _cardScrollCtrl.addListener(_updateCardFadeState);
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCardFadeState());

    _saveBtnCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 460),
    );
    _saveBtnBounce = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.07), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 1.07, end: 0.95), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.95, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _saveBtnCtrl, curve: Curves.easeOut));

    _typeMenuCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _typeChipAnimations = List.generate(4, (i) {
      return CurvedAnimation(
        parent: _typeMenuCtrl,
        curve: Interval(i * 0.07, 0.55 + i * 0.07, curve: Curves.easeOutBack),
      );
    });

    _type = widget.initialType ?? EntryType.expense;
    if (widget.initialToAccountId != null) {
      _toAccountId = widget.initialToAccountId;
      // Auto-enable account transfer mode when a destination account is pre-set
      // (e.g. navigating from the credit card "Pay Card" button).
      if (_type == EntryType.transfer) {
        _isAccountTransfer = true;
      }
    }
    final template = widget.expense ?? widget.copyFrom;
    if (template != null) {
      _amountController.text = template.amount.toStringAsFixed(2);
      _noteController.text = template.note;
      _category = template.category;
      _date = template.date;
      _type = template.type;
      _accountId = template.accountId;
      _toAccountId = template.toAccountId;
      if (_isEdit) _existingReceiptUrl = template.receiptUrl;
      _counterpartController.text = template.counterpart ?? '';
      if (template.type == EntryType.transfer && template.toAccountId != null) {
        _isAccountTransfer = true;
      }
    } else if (widget.initialAmount != null && widget.initialAmount! > 0) {
      _amountController.text = widget.initialAmount!.toStringAsFixed(2);
    }

    final initialTypeIndex = _typeIndexFor(_type);
    _typePageCtrl = PageController(
      initialPage: initialTypeIndex,
      viewportFraction: 0.90,
    );
    _typePageOffset = initialTypeIndex.toDouble();
    _typePageCtrl.addListener(() {
      setState(() => _typePageOffset = _typePageCtrl.page ?? _typePageOffset);
    });

    _hasValidAmount = _checkAmountValid();
    _amountController.addListener(_onAmountChanged);
    _loadInitialCurrency();
    if (_isEdit) _loadSplitBill();
    if (widget.copyFrom != null) _loadSplitBillForCopy();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _entranceCtrl.forward();
    });
  }

  bool _checkAmountValid() {
    final text = _amountController.text;
    return text.isNotEmpty && (double.tryParse(text) ?? 0) > 0;
  }

  void _onAmountChanged() {
    final valid = _checkAmountValid();
    if (valid != _hasValidAmount) {
      setState(() => _hasValidAmount = valid);
    }
  }

  @override
  void dispose() {
    _amountController.removeListener(_onAmountChanged);
    _entranceCtrl.dispose();
    _closeCtrl.dispose();
    _snapCtrl.dispose();
    _saveBtnCtrl.dispose();
    _typeMenuCtrl.dispose();
    _typePageCtrl.dispose();
    _amountController.dispose();
    _amountFocus.dispose();
    _noteController.dispose();
    _counterpartController.dispose();
    _cardScrollCtrl.dispose();
    super.dispose();
  }

  // ─── Close / Dismiss ─────────────────────────────────────────────────────────

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

  Widget _buildDragHandle(BrandColors brand) {
    final pillW = (36.0 + (_dragOffset * 0.3).clamp(0.0, 20.0));
    final accent = _kTypeAccents[_typeIndexFor(_type)];
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
                color: accent.withValues(alpha: 0.40),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              'swipe down to close',
              style: TextStyle(
                fontSize: 11,
                color: accent.withValues(alpha: 0.55),
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<String> get _categories {
    if (_type == EntryType.income) return kIncomeCategories;
    if (_type == EntryType.transfer || _type == EntryType.receive) {
      return const ['Transfer'];
    }
    return kExpenseCategories;
  }

  Future<void> _pickReceipt() async {
    FocusScope.of(context).unfocus();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked != null) {
      setState(() => _newReceipt = File(picked.path));
    }
  }

  // Clear focus after a picker closes so the amount field doesn't regain
  // focus and re-open the keyboard/numpad.
  void _dismissKeyboard() {
    if (!mounted) return;
    FocusScope.of(context).unfocus();
  }

  // Recompute fade visibility: top fade shows when scrolled away from the top,
  // bottom fade shows only while there is more content below.
  void _updateCardFadeState() {
    if (!_cardScrollCtrl.hasClients) return;
    final pos = _cardScrollCtrl.position;
    final hasOverflow = pos.maxScrollExtent > 0;
    final atTop = _cardScrollCtrl.offset <= 4;
    final atBottom = _cardScrollCtrl.offset >= pos.maxScrollExtent - 4;
    final newScrolled = hasOverflow && !atTop;
    final newAtBottom = !hasOverflow || atBottom;
    if (newScrolled != _cardScrolled || newAtBottom != _cardAtBottom) {
      setState(() {
        _cardScrolled = newScrolled;
        _cardAtBottom = newAtBottom;
      });
    }
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: 280,
        color: ctx.brand.background,
        child: Column(
          children: [
            SizedBox(
              height: 220,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.date,
                initialDateTime: _date,
                maximumDate: DateTime.now().add(const Duration(days: 1)),
                onDateTimeChanged: (d) => setState(() => _date = d),
              ),
            ),
            CupertinoButton(
              child: Text(context.t('common.done')),
              onPressed: () => Navigator.pop(ctx),
            ),
          ],
        ),
      ),
    );
    _dismissKeyboard();
  }

  Future<void> _openSplitBillSheet(BuildContext context) async {
    FocusScope.of(context).unfocus();
    final symbol = ref.read(currencySymbolProvider).valueOrNull ?? '\$';
    final amount = double.tryParse(_amountController.text) ?? 0;
    final totalAmount = _splitBillEnabled && _splitBillTotal > 0
        ? _splitBillTotal
        : amount;
    final title = _noteController.text.trim().isNotEmpty
        ? _noteController.text.trim()
        : _category;

    final displayName = ref.read(userNameProvider);
    final result = await Navigator.push<SplitBillResult>(
      context,
      CupertinoPageRoute(
        builder: (_) => SplitBillScreen(
          totalAmount: totalAmount,
          currencySymbol: symbol,
          expenseTitle: title,
          initialMembers: _splitMembers,
          initialSplitMode: _splitMode,
          userName: displayName,
        ),
        fullscreenDialog: true,
      ),
    );

    if (result != null) {
      // Find payer's share — that's what the current user owes/spent
      final payer = result.members.firstWhere(
        (m) => m.isPayer,
        orElse: () => result.members.first,
      );
      setState(() {
        _splitBillEnabled = true;
        _splitMembers = result.members;
        _splitMode = result.splitMode;
        _splitBillTotal = result.totalAmount;
        _splitBill = null;
        _amountController.text = payer.amount.toStringAsFixed(2);
      });
      // Prevent the amount field from auto-focusing when returning
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).unfocus();
      });
    } else if (_splitMembers.isEmpty) {
      // User cancelled without configuring, turn off toggle
      setState(() => _splitBillEnabled = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isAccountTransfer && _toAccountId == null) {
      AppToast.show(
        context,
        context.t('expense.selectDestAccount'),
        type: AppToastType.error,
      );
      return;
    }
    if (_isAccountTransfer && _toAccountId == _accountId) {
      AppToast.show(
        context,
        context.t('expense.sameAccountError'),
        type: AppToastType.error,
      );
      return;
    }
    setState(() => _saving = true);

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final isOnline = ref.read(isOnlineProvider);
    final expenses = ref.read(expenseRepositoryProvider);
    final storage = ref.read(storageServiceProvider);

    try {
      String? receiptUrl = _existingReceiptUrl;
      String? uploadedNewUrl;

      if (_newReceipt != null && isOnline) {
        dev.log(
          '[RECEIPT_UPLOAD] User selected new receipt — uploading for user ${user.uid}',
          name: 'AddEditExpense',
        );
        try {
          uploadedNewUrl = await storage.saveReceipt(user.uid, _newReceipt!);
          receiptUrl = uploadedNewUrl;
          dev.log('[RECEIPT_UPLOAD] Upload succeeded.', name: 'AddEditExpense');
        } catch (uploadError) {
          dev.log(
            '[RECEIPT_UPLOAD] Upload failed: $uploadError — saving entry without receipt.',
            name: 'AddEditExpense',
            error: uploadError,
          );
          receiptUrl = _existingReceiptUrl;
        }
      } else if (_newReceipt != null && !isOnline) {
        dev.log(
          '[RECEIPT_UPLOAD] Offline — saving receipt locally, will upload on sync.',
          name: 'AddEditExpense',
        );
        try {
          receiptUrl = await storage.saveReceiptLocally(user.uid, _newReceipt!);
          dev.log(
            '[RECEIPT_UPLOAD] Saved locally: $receiptUrl',
            name: 'AddEditExpense',
          );
        } catch (localSaveError) {
          dev.log(
            '[RECEIPT_UPLOAD] Local save failed: $localSaveError — continuing without receipt.',
            name: 'AddEditExpense',
            error: localSaveError,
          );
          receiptUrl = _existingReceiptUrl;
        }
      }

      final amount = double.parse(_amountController.text);
      final now = DateTime.now();

      final mainCode = await ref.read(currencyCodeProvider.future);
      final fxService = ref.read(exchangeRateServiceProvider);
      final String? originalCurrencyField = _currencyCode != mainCode
          ? _currencyCode
          : null;
      double? fxRate;
      double? baseCurrencyAmount;
      if (_currencyCode != mainCode) {
        fxRate = await fxService.getRate(
          from: _currencyCode,
          to: mainCode,
          base: mainCode,
        );
        if (fxRate != null) baseCurrencyAmount = amount * fxRate;
      }

      String category;
      String? counterpart;
      String? toAccountId;

      if (_type == EntryType.transfer || _type == EntryType.receive) {
        category = 'Transfer';
        if (_isAccountTransfer) {
          toAccountId = _toAccountId;
          counterpart = null;
        } else {
          counterpart = _counterpartController.text.trim();
          toAccountId = null;
        }
      } else {
        category = _category;
        counterpart = null;
        toAccountId = null;
      }

      String savedExpenseId;
      if (_isEdit) {
        final updated = widget.expense!.copyWith(
          amount: amount,
          category: category,
          note: _noteController.text.trim(),
          date: _date,
          type: _type,
          receiptUrl: receiptUrl,
          accountId: _accountId,
          toAccountId: toAccountId,
          counterpart: counterpart,
          originalCurrency: originalCurrencyField,
          exchangeRate: fxRate,
          baseCurrencyAmount: baseCurrencyAmount,
          updatedAt: now,
        );
        savedExpenseId = updated.id;
        dev.log(
          '[SAVE] Updating expense ${updated.id} | online: $isOnline | receiptUrl: ${receiptUrl != null ? "set" : "null"}',
          name: 'AddEditExpense',
        );
        if (isOnline) {
          try {
            await expenses.updateExpense(user.uid, updated);
            await LocalExpenseRepository().upsertExpense(user.uid, updated);
            if (uploadedNewUrl != null && _existingReceiptUrl != null) {
              await storage.delete(_existingReceiptUrl!);
            }
          } catch (_) {
            await LocalExpenseRepository().upsertExpense(user.uid, updated);
            if (storageMode == StorageMode.firebase) {
              await SyncService().markPending(user.uid, updated.id);
            }
          }
        } else {
          await LocalExpenseRepository().updateExpense(user.uid, updated);
          if (storageMode == StorageMode.firebase) {
            await SyncService().markPending(user.uid, updated.id);
          }
        }
      } else {
        final e = Expense(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          amount: amount,
          category: category,
          note: _noteController.text.trim(),
          date: _date,
          type: _type,
          receiptUrl: receiptUrl,
          accountId: _accountId,
          toAccountId: toAccountId,
          counterpart: counterpart,
          originalCurrency: originalCurrencyField,
          exchangeRate: fxRate,
          baseCurrencyAmount: baseCurrencyAmount,
          createdAt: now,
          updatedAt: now,
        );
        savedExpenseId = e.id;
        dev.log(
          '[SAVE] Adding expense ${e.id} | online: $isOnline | receiptUrl: ${receiptUrl != null ? "set" : "null"}',
          name: 'AddEditExpense',
        );
        if (isOnline) {
          try {
            await expenses.addExpense(user.uid, e);
            await LocalExpenseRepository().upsertExpense(user.uid, e);
          } catch (_) {
            await LocalExpenseRepository().upsertExpense(user.uid, e);
            if (storageMode == StorageMode.firebase) {
              await SyncService().markPending(user.uid, e.id);
            }
          }
        } else {
          await LocalExpenseRepository().upsertExpense(user.uid, e);
          if (storageMode == StorageMode.firebase) {
            await SyncService().markPending(user.uid, e.id);
          }
        }
      }

      // Save / update split bill — local-first, then Firestore best-effort.
      if (_splitBillEnabled && _splitMembers.isNotEmpty) {
        _splitBill = await _saveSplitBill(
          uid: user.uid,
          expenseId: savedExpenseId,
          category: category,
          isOnline: isOnline,
        );
      } else if (_isEdit) {
        await _deleteSplitBillForExpense(
          uid: user.uid,
          expenseId: savedExpenseId,
          isOnline: isOnline,
        );
      }

      if (mounted) {
        FocusScope.of(context).unfocus();
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
                ? context.t('expense.entryUpdated')
                : context.t('expense.entrySaved'),
            type: AppToastType.success,
          );
        }
        await Future.delayed(const Duration(milliseconds: 480));
        if (mounted) await _animatedClose();
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          '${context.t('common.saveFailed')}: $e',
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted && !_saveSuccess) setState(() => _saving = false);
    }
  }

  Future<SplitBill?> _saveSplitBill({
    required String uid,
    required String expenseId,
    required String category,
    required bool isOnline,
  }) async {
    try {
      final now2 = DateTime.now();
      final mainCode2 = await ref.read(currencyCodeProvider.future);
      final sym = ref.read(currencySymbolProvider).valueOrNull ?? '\$';
      final billTotal = _splitBillTotal > 0
          ? _splitBillTotal
          : _splitMembers.fold<double>(0, (s, m) => s + m.amount);
      final title = _noteController.text.trim().isNotEmpty
          ? _noteController.text.trim()
          : category;

      // Look up existing local record to preserve billNumber / createdAt.
      final existingLocal = await LocalSplitBillRepository()
          .getSplitBillByExpenseId(uid, expenseId);

      final billNumber =
          existingLocal?.billNumber ??
          '#${now2.year}-${(now2.millisecondsSinceEpoch % 10000).toString().padLeft(4, '0')}';
      final createdAt = existingLocal?.createdAt ?? now2;
      final localId =
          existingLocal?.id ?? DateTime.now().microsecondsSinceEpoch.toString();

      final bill = SplitBill(
        id: localId,
        expenseId: expenseId,
        billNumber: billNumber,
        title: title,
        totalAmount: billTotal,
        currency: mainCode2,
        currencySymbol: sym,
        splitMode: _splitMode,
        members: _splitMembers,
        date: _date,
        createdAt: createdAt,
        updatedAt: now2,
      );

      // Step 1: Always write to local Hive first (guaranteed, no network needed).
      if (existingLocal != null) {
        await LocalSplitBillRepository().updateSplitBill(uid, bill);
      } else {
        await LocalSplitBillRepository().saveSplitBill(uid, bill);
      }

      // Step 2: Sync to Firestore when online (best-effort, non-fatal).
      if (isOnline) {
        try {
          final existingRemote = await SplitBillRepository()
              .getSplitBillByExpenseId(uid, expenseId);
          if (existingRemote != null) {
            await SplitBillRepository().updateSplitBill(
              uid,
              SplitBill(
                id: existingRemote.id,
                expenseId: bill.expenseId,
                billNumber: bill.billNumber,
                title: bill.title,
                totalAmount: bill.totalAmount,
                currency: bill.currency,
                currencySymbol: bill.currencySymbol,
                splitMode: bill.splitMode,
                members: bill.members,
                date: bill.date,
                createdAt: bill.createdAt,
                updatedAt: bill.updatedAt,
              ),
            );
          } else {
            await SplitBillRepository().saveSplitBill(uid, bill);
          }
        } catch (firestoreErr) {
          dev.log(
            '[SAVE] Firestore split-bill sync failed (local copy saved): $firestoreErr',
            name: 'AddEditExpense',
          );
        }
      }
      return bill;
    } catch (e) {
      dev.log('[SAVE] Split-bill save error: $e', name: 'AddEditExpense');
      return null;
    }
  }

  Future<void> _deleteSplitBillForExpense({
    required String uid,
    required String expenseId,
    required bool isOnline,
  }) async {
    try {
      final existingLocal = await LocalSplitBillRepository()
          .getSplitBillByExpenseId(uid, expenseId);
      if (existingLocal != null) {
        await LocalSplitBillRepository().deleteSplitBill(
          uid,
          existingLocal.id,
          expenseId,
        );
      }

      if (isOnline) {
        try {
          final existingRemote = await SplitBillRepository()
              .getSplitBillByExpenseId(uid, expenseId);
          if (existingRemote != null) {
            await SplitBillRepository().deleteSplitBill(uid, existingRemote.id);
          }
        } catch (firestoreErr) {
          dev.log(
            '[SAVE] Firestore split-bill delete failed: $firestoreErr',
            name: 'AddEditExpense',
          );
        }
      }
      _splitBill = null;
    } catch (e) {
      dev.log('[SAVE] Split-bill delete error: $e', name: 'AddEditExpense');
    }
  }

  Future<void> _loadInitialCurrency() async {
    final mainCode = await ref.read(currencyCodeProvider.future);
    if (!mounted) return;
    final template = widget.expense ?? widget.copyFrom;
    setState(() => _currencyCode = template?.originalCurrency ?? mainCode);
  }

  Future<void> _loadSplitBill() async {
    final expenseId = widget.expense?.id;
    if (expenseId == null) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    try {
      // Try local first — fast and works offline.
      SplitBill? bill = await LocalSplitBillRepository()
          .getSplitBillByExpenseId(user.uid, expenseId);

      bill ??= await _findLegacyLocalSplitBill(user.uid, expenseId);

      // Fall back to Firestore if not cached locally.
      if (bill == null && ref.read(isOnlineProvider)) {
        try {
          bill = await SplitBillRepository().getSplitBillByExpenseId(
            user.uid,
            expenseId,
          );
          // Cache it locally so next open is instant.
          if (bill != null) {
            await LocalSplitBillRepository().saveSplitBill(user.uid, bill);
          }
        } catch (firestoreErr) {
          dev.log(
            '[LOAD] Firestore split-bill lookup failed: $firestoreErr',
            name: 'AddEditExpense',
          );
        }
      }

      if (!mounted || bill == null) return;
      setState(() {
        _splitBillEnabled = true;
        _splitMembers = bill!.members;
        _splitMode = bill.splitMode;
        _splitBillTotal = bill.totalAmount;
        _splitBill = bill;
        final payer = bill.members.firstWhere(
          (m) => m.isPayer,
          orElse: () => bill!.members.first,
        );
        _amountController.text = payer.amount.toStringAsFixed(2);
      });
    } catch (e) {
      dev.log('[LOAD] Split-bill load error: $e', name: 'AddEditExpense');
    }
  }

  Future<void> _loadSplitBillForCopy() async {
    final source = widget.copyFrom;
    if (source == null) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    try {
      SplitBill? bill = await LocalSplitBillRepository()
          .getSplitBillByExpenseId(user.uid, source.id);
      if (bill == null) {
        final expectedTitle =
            source.note.trim().isNotEmpty ? source.note.trim() : source.category;
        final bills = await LocalSplitBillRepository().getAllSplitBills(user.uid);
        for (final b in bills) {
          if (b.title != expectedTitle) { continue; }
          if (!_sameCalendarDate(b.date, source.date)) { continue; }
          bill = b;
          break;
        }
      }
      if (bill == null && ref.read(isOnlineProvider)) {
        try {
          bill = await SplitBillRepository()
              .getSplitBillByExpenseId(user.uid, source.id);
        } catch (_) {}
      }
      if (!mounted || bill == null) return;
      setState(() {
        _splitBillEnabled = true;
        _splitMembers = bill!.members.map((m) => m.copyWith()).toList();
        _splitMode = bill.splitMode;
        _splitBillTotal = bill.totalAmount;
      });
    } catch (e) {
      dev.log('[COPY] Split-bill copy load error: $e', name: 'AddEditExpense');
    }
  }

  Future<SplitBill?> _findLegacyLocalSplitBill(
    String uid,
    String expenseId,
  ) async {
    final expense = widget.expense;
    if (expense == null) return null;

    final expectedTitle = expense.note.trim().isNotEmpty
        ? expense.note.trim()
        : expense.category;
    final bills = await LocalSplitBillRepository().getAllSplitBills(uid);
    for (final bill in bills) {
      if (bill.expenseId == expenseId) continue;
      if (bill.title != expectedTitle) continue;
      if (!_sameCalendarDate(bill.date, expense.date)) continue;
      if ((bill.payer.amount - expense.amount).abs() > 0.01) continue;
      if (_durationAbs(bill.createdAt.difference(expense.createdAt)) >
          const Duration(minutes: 5)) {
        continue;
      }

      final relinked = _withExpenseId(bill, expenseId);
      await LocalSplitBillRepository().updateSplitBill(uid, relinked);
      return relinked;
    }
    return null;
  }

  bool _sameCalendarDate(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Duration _durationAbs(Duration duration) {
    return duration.isNegative ? -duration : duration;
  }

  SplitBill _withExpenseId(SplitBill bill, String expenseId) {
    return SplitBill(
      id: bill.id,
      expenseId: expenseId,
      billNumber: bill.billNumber,
      title: bill.title,
      totalAmount: bill.totalAmount,
      currency: bill.currency,
      currencySymbol: bill.currencySymbol,
      splitMode: bill.splitMode,
      members: bill.members,
      date: bill.date,
      createdAt: bill.createdAt,
      updatedAt: DateTime.now(),
    );
  }

  Future<void> _delete() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null || !_isEdit) return;
    final confirm = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('expense.deleteTitle')),
        content: Text(context.t('common.cannotBeUndone')),
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
    if (confirm != true) return;
    final expenseId = widget.expense!.id;
    try {
      final isOnline =
          storageMode == StorageMode.firebase && ref.read(isOnlineProvider);
      await _deleteSplitBillForExpense(
        uid: user.uid,
        expenseId: expenseId,
        isOnline: isOnline,
      );
      if (storageMode == StorageMode.firebase) {
        await SyncService().deleteExpense(
          userId: user.uid,
          expenseId: expenseId,
          isOnline: isOnline,
        );
      } else {
        await LocalExpenseRepository().deleteExpense(user.uid, expenseId);
      }
    } catch (e, st) {
      dev.log(
        '[Expense] delete failed: $e',
        name: 'AddEditExpense',
        stackTrace: st,
      );
      if (mounted) {
        AppToast.show(
          context,
          context.t('common.error'),
          type: AppToastType.error,
        );
      }
      return;
    }
    if (mounted) {
      AppToast.show(
        context,
        context.t('expense.entryDeleted'),
        type: AppToastType.success,
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final dateLabel = DateFormat('MMM d, yyyy').format(_date);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];

    return Scaffold(
      backgroundColor: brand.background,
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
        child: GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            if (_typeMenuOpen) {
              setState(() => _typeMenuOpen = false);
              _typeMenuCtrl.reverse();
            }
          },
          behavior: HitTestBehavior.translucent,
          child: SafeArea(
            child: FadeTransition(
              opacity: _entranceFade,
              child: SlideTransition(
                position: _entranceSlide,
                child: Form(
                  key: _formKey,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Column(
                        children: [
                          // ── Drag handle + close hint ──────────────────────────────
                          _buildDragHandle(brand),
                          Expanded(
                            child: PageView.builder(
                              clipBehavior: Clip.none,
                              controller: _typePageCtrl,
                              itemCount: 4,
                              onPageChanged: _switchType,
                              itemBuilder: (context, i) => _buildFullTypeCard(
                                index: i,
                                brand: brand,
                                symbol: symbol,
                                dateLabel: dateLabel,
                                accounts: accounts,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _pageIndicator(brand),
                          const SizedBox(height: 6),
                          _swipeHint(brand),
                          const SizedBox(height: 80),
                        ],
                      ),
                      // Type picker chips — float above the bottom bar
                      Positioned(
                        bottom: 86,
                        left: 16,
                        right: 16,
                        child: _typeChipsOverlay(brand),
                      ),
                      // Bottom action bar
                      Positioned(
                        bottom: 16,
                        left: 20,
                        right: 20,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (_isEdit) ...[
                              GestureDetector(
                                onTap: _delete,
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AppColors.blush,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.delete,
                                    size: 20,
                                    color: AppColors.expense,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            _typeMenuButton(brand),
                            const SizedBox(width: 12),
                            Expanded(child: _floatingSavePill(brand)),
                          ],
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

  // ─── Type Card Swiper ─────────────────────────────────────────────────────────

  static const _kTypes = [
    EntryType.expense,
    EntryType.income,
    EntryType.transfer,
    EntryType.receive,
  ];

  int _typeIndexFor(EntryType t) => _kTypes.indexOf(t);

  void _switchType(int index) {
    final t = _kTypes[index];
    if (_type == t) return;
    HapticFeedback.selectionClick();
    if (_cardScrollCtrl.hasClients) _cardScrollCtrl.jumpTo(0);
    setState(() {
      _type = t;
      _cardScrolled = false;
      _cardAtBottom = true;
      _swipeHintVisible = false;
      _isAccountTransfer = false;
      _toAccountId = null;
      if (!(t == EntryType.transfer || t == EntryType.receive)) {
        if (!_categories.contains(_category)) {
          _category = _categories.first;
        }
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateCardFadeState());
  }

  // ─── Page Indicator ───────────────────────────────────────────────────────────

  Widget _pageIndicator(BrandColors brand) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(4, (i) {
        final distance = (_typePageOffset - i).abs().clamp(0.0, 1.0);
        final progress = 1.0 - distance;
        final activeAccent = _kTypeAccents[_typeIndexFor(_type)];
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: 8.0 + (progress * 18.0),
          height: 8,
          decoration: BoxDecoration(
            color: activeAccent.withValues(alpha: 0.20 + (progress * 0.80)),
            borderRadius: BorderRadius.circular(4),
          ),
        );
      }),
    );
  }

  // ─── Swipe Hint ───────────────────────────────────────────────────────────────

  Widget _swipeHint(BrandColors brand) {
    return AnimatedOpacity(
      opacity: _swipeHintVisible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOut,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(CupertinoIcons.chevron_left, size: 10, color: brand.inkSoft.withValues(alpha: 0.5)),
          const SizedBox(width: 4),
          Text(
            context.t('expense.swipeToSwitch'),
            style: TextStyle(
              fontSize: 11,
              color: brand.inkSoft.withValues(alpha: 0.5),
              fontWeight: FontWeight.w500,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(width: 4),
          Icon(CupertinoIcons.chevron_right, size: 10, color: brand.inkSoft.withValues(alpha: 0.5)),
        ],
      ),
    );
  }

  // ─── Type Menu Button ─────────────────────────────────────────────────────────

  Widget _typeMenuButton(BrandColors brand) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        setState(() => _typeMenuOpen = !_typeMenuOpen);
        if (_typeMenuOpen) {
          _typeMenuCtrl.forward(from: 0);
        } else {
          _typeMenuCtrl.reverse();
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          color: _typeMenuOpen ? _typeColor : brand.surface,
          shape: BoxShape.circle,
        ),
        child: AnimatedRotation(
          turns: _typeMenuOpen ? 0.125 : 0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          child: Icon(
            CupertinoIcons.square_grid_2x2,
            size: 20,
            color: _typeMenuOpen ? Colors.white : brand.ink,
          ),
        ),
      ),
    );
  }

  // ─── Type Chips Overlay ───────────────────────────────────────────────────────

  Widget _typeChipsOverlay(BrandColors brand) {
    return AnimatedBuilder(
      animation: _typeMenuCtrl,
      builder: (context, _) {
        if (_typeMenuCtrl.value == 0 && !_typeMenuOpen) {
          return const SizedBox.shrink();
        }
        final typeLabels = [
          context.t('expense.expense'),
          context.t('expense.income'),
          context.t('expense.transfer'),
          context.t('expense.receive'),
        ];
        return Row(
          children: List.generate(4, (i) {
            final t = _kTypes[i];
            final isSelected = t == _type;
            final chipAnim = _typeChipAnimations[i];
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(right: i < 3 ? 7 : 0),
                child: Transform.scale(
                  scale: chipAnim.value,
                  alignment: Alignment.bottomCenter,
                  child: Opacity(
                    opacity: chipAnim.value.clamp(0.0, 1.0),
                    child: GestureDetector(
                      onTap: () => _selectTypeFromMenu(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? _kTypeAccents[i] : brand.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _kTypeIcons[i],
                              size: 18,
                              color: isSelected
                                  ? Colors.white
                                  : _kTypeAccents[i],
                            ),
                            const SizedBox(height: 5),
                            Text(
                              typeLabels[i],
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected ? Colors.white : brand.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }

  void _selectTypeFromMenu(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _typeMenuOpen = false;
      _swipeHintVisible = false;
      _typeMenuCtrl.reverse();
    });
    final targetType = _kTypes[index];
    if (targetType != _type) {
      _typePageCtrl.animateToPage(
        index,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  // ─── Full Type Cards ──────────────────────────────────────────────────────────

  static const _kTypeAccents = [
    Color(0xFF6B40A8),
    Color(0xFF1F7A60),
    Color(0xFFB23A4A),
    Color(0xFF2A6FB5),
  ];

  static const _kTypeIcons = [
    CupertinoIcons.minus_circle_fill,
    CupertinoIcons.plus_circle_fill,
    CupertinoIcons.arrow_right_arrow_left_circle_fill,
    CupertinoIcons.arrow_down_left_circle_fill,
  ];

  Widget _buildFullTypeCard({
    required int index,
    required BrandColors brand,
    required String symbol,
    required String dateLabel,
    required List<Account> accounts,
  }) {
    final type = _kTypes[index];
    final isActive = type == _type;
    final distance = (_typePageOffset - index).abs().clamp(0.0, 1.0);
    final scale = 1.0 - (distance * 0.10);
    final opacity = (1.0 - (distance * 0.50)).clamp(0.0, 1.0);
    final translateY = distance * 18.0;
    final blurAmount = distance * 2.5;

    final labels = [
      context.t('expense.expense'),
      context.t('expense.income'),
      context.t('expense.transfer'),
      context.t('expense.receive'),
    ];
    final subtitles = [
      context.t('expense.typeExpenseDesc'),
      context.t('expense.typeIncomeDesc'),
      context.t('expense.typeTransferDesc'),
      context.t('expense.typeReceiveDesc'),
    ];
    final bgColors = [
      AppColors.lilac,
      AppColors.mint,
      AppColors.blush,
      AppColors.sky,
    ];

    final accent = _kTypeAccents[index];
    final bg = bgColors[index];
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardChild = Container(
      margin: const EdgeInsets.fromLTRB(10, 4, 10, 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(28),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: isActive
            ? _activeCardContent(
                type: type,
                accent: accent,
                icon: _kTypeIcons[index],
                label: labels[index],
                subtitle: subtitles[index],
                brand: brand,
                symbol: symbol,
                dateLabel: dateLabel,
                accounts: accounts,
                isDark: isDark,
              )
            : _inactiveCardPreview(
                accent: accent,
                icon: _kTypeIcons[index],
                label: labels[index],
                subtitle: subtitles[index],
              ),
      ),
    );

    return Transform(
      transform: Matrix4.identity()
        ..setEntry(3, 2, 0.001)
        ..translateByDouble(0.0, translateY, 0.0, 1.0)
        ..scaleByDouble(scale, scale, 1.0, 1.0),
      alignment: Alignment.topCenter,
      child: Opacity(
        opacity: opacity,
        child: blurAmount > 0.3
            ? ImageFiltered(
                imageFilter: ImageFilter.blur(
                  sigmaX: blurAmount,
                  sigmaY: blurAmount,
                ),
                child: cardChild,
              )
            : cardChild,
      ),
    );
  }

  Widget _activeCardContent({
    required EntryType type,
    required Color accent,
    required IconData icon,
    required String label,
    required String subtitle,
    required BrandColors brand,
    required String symbol,
    required String dateLabel,
    required List<Account> accounts,
    required bool isDark,
  }) {
    const sectionGap = 10.0;
    const iconSize = 40.0;
    const iconRadius = 12.0;
    const iconInner = 20.0;
    const labelFontSize = 19.0;
    final compact = type == EntryType.income ||
        type == EntryType.transfer ||
        type == EntryType.receive;

    final bg = [
      AppColors.lilac,
      AppColors.mint,
      AppColors.blush,
      AppColors.sky,
    ][_typeIndexFor(type)];

    return Stack(
      children: [
        NotificationListener<ScrollMetricsNotification>(
          onNotification: (_) {
            WidgetsBinding.instance.addPostFrameCallback(
                (_) => _updateCardFadeState());
            return false;
          },
          child: SingleChildScrollView(
            controller: _cardScrollCtrl,
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
            child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Header
          Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(iconRadius),
                ),
                child: Icon(icon, size: iconInner, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: labelFontSize,
                        fontWeight: FontWeight.w600,
                        color: accent,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: accent.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: sectionGap),
          // Amount field
          Builder(
            builder: (context) {
              final entrySymbol =
                  kSupportedCurrencies[_currencyCode] ?? _currencyCode;
              final converter = ref
                  .watch(currencyConverterProvider)
                  .valueOrNull;
              final mainCode =
                  converter?.base ??
                  ref.watch(currencyCodeProvider).valueOrNull ??
                  'MYR';
              final mainSymbol = kSupportedCurrencies[mainCode] ?? mainCode;
              final isForeign = _currencyCode != mainCode;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          entrySymbol,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: brand.inkSoft,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: TextFormField(
                          controller: _amountController,
                          focusNode: _amountFocus,
                          cursorHeight: 40.0,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          style: TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -2,
                            color: brand.ink,
                          ),
                          decoration: InputDecoration(
                            filled: false,
                            hintText: '0.00',
                            hintStyle: TextStyle(
                              color: brand.inkSoft.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w600,
                              fontSize: 40,
                              letterSpacing: -2,
                            ),
                            contentPadding: EdgeInsets.zero,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                          ),
                          validator: (v) {
                            if (v == null || v.isEmpty) {
                              return context.t('validation.enterAmount');
                            }
                            final n = double.tryParse(v);
                            if (n == null || n <= 0) {
                              return context.t('validation.invalidAmount');
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                  if (isForeign && converter != null)
                    ListenableBuilder(
                      listenable: _amountController,
                      builder: (ctx, _) {
                        final amt =
                            double.tryParse(_amountController.text) ?? 0;
                        if (amt <= 0) return const SizedBox.shrink();
                        final converted = converter.toBase(amt, _currencyCode);
                        return Padding(
                          padding: const EdgeInsets.only(
                            top: 2,
                            left: 2,
                            bottom: 4,
                          ),
                          child: Text(
                            'est. $mainSymbol ${converted.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              color: brand.inkSoft,
                              letterSpacing: -0.2,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              );
            },
          ),
          SizedBox(height: sectionGap),
          // Category section (expense / income)
          if (type == EntryType.expense || type == EntryType.income) ...[
            Padding(
              padding: EdgeInsets.only(left: 2, bottom: compact ? 6 : 10),
              child: Text(
                context.t('expense.category'),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: accent.withValues(alpha: 0.85),
                  fontSize: compact ? 12 : 14,
                ),
              ),
            ),
            _categorySelector(brand, compact: compact),
            const SizedBox(height: 6),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              transitionBuilder: (child, anim) => FadeTransition(
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
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: styleFor(_category).accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    context.categoryLabel(_category),
                    style: TextStyle(
                      fontSize: compact ? 12 : 13,
                      fontWeight: FontWeight.w600,
                      color: styleFor(_category).accent,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: compact ? 8 : 12),
          ],
          // Transfer-specific
          if (type == EntryType.transfer) ...[
            _accountTransferToggle(brand, compact: compact),
            SizedBox(height: compact ? 8 : 12),
            if (!_isAccountTransfer) ...[
              _counterpartField(brand),
              SizedBox(height: compact ? 8 : 12),
            ],
          ],
          // Receive-specific
          if (type == EntryType.receive) ...[
            _counterpartField(brand),
            SizedBox(height: compact ? 8 : 12),
          ],
          _groupedDetailsCard(
            brand: brand,
            accounts: accounts,
            dateLabel: dateLabel,
            isAccountTransfer: type == EntryType.transfer && _isAccountTransfer,
            entryType: type,
            compact: true,
          ),
            ],
          ),
        ),
      ),
              // Bottom fade — hidden once scrolled to the very end
              Positioned(
                left: 0, right: 0, bottom: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _cardAtBottom ? 0.0 : 1.0,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [bg.withValues(alpha: 0), bg.withValues(alpha: 0.65)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              // Top fade — visible when scrolled away from top
              Positioned(
                left: 0, right: 0, top: 0,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 200),
                    opacity: _cardScrolled ? 1.0 : 0.0,
                    child: Container(
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [bg.withValues(alpha: 0.60), bg.withValues(alpha: 0)],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
  }

  Widget _inactiveCardPreview({
    required Color accent,
    required IconData icon,
    required String label,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, size: 26, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: accent,
                        letterSpacing: -0.5,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: accent.withValues(alpha: 0.65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          ListenableBuilder(
            listenable: _amountController,
            builder: (context, _) {
              final previewBrand = context.brand;
              return Text(
                _amountController.text.isEmpty
                    ? '0.00'
                    : _amountController.text,
                style: TextStyle(
                  fontSize: 40,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -2,
                  color: previewBrand.inkSoft,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── Category Selector ───────────────────────────────────────────────────────

  Widget _categorySelector(BrandColors brand, {bool compact = false}) {
    final cats = _categories;
    final itemSize = compact ? 44.0 : 52.0;
    return SizedBox(
      height: compact ? 50 : 64,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: cats.length,
        itemBuilder: (context, idx) {
          final c = cats[idx];
          final selected = c == _category;
          final s = styleFor(c);
          return GestureDetector(
            onTap: () {
              if (_category == c) return;
              HapticFeedback.selectionClick();
              setState(() => _category = c);
            },
            child: Padding(
              padding: EdgeInsets.only(right: idx < cats.length - 1 ? 8 : 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                width: itemSize,
                height: itemSize,
                decoration: BoxDecoration(
                  color: selected ? s.accent : brand.surface,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  s.icon,
                  size: compact ? 17 : 20,
                  color: selected ? Colors.white : s.accent,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ─── Floating Save Pill ───────────────────────────────────────────────────────

  static final _kSuccessGreen = AppColors.income;

  Widget _floatingSavePill(BrandColors brand) {
    final active = _hasValidAmount && !_saving && !_saveSuccess;
    final bgColor = _saveSuccess
        ? _kSuccessGreen
        : (_saving || _hasValidAmount)
        ? _typeColor
        : brand.surface;

    return AnimatedBuilder(
      animation: _saveBtnBounce,
      builder: (context, child) => Transform.scale(
        scale: _saveSuccess ? _saveBtnBounce.value : 1.0,
        child: child,
      ),
      child: GestureDetector(
        onTap: () {
          if (_saving || _saveSuccess) return;
          if (_typeMenuOpen) {
            setState(() => _typeMenuOpen = false);
            _typeMenuCtrl.reverse();
          }
          HapticFeedback.mediumImpact();
          _save();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOutCubic,
          height: 56,
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Center(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, anim) => ScaleTransition(
                scale: anim,
                child: FadeTransition(opacity: anim, child: child),
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
                          context.t('expense.entrySavedSuccess'),
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
                      key: ValueKey('saving'),
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
                          CupertinoIcons.checkmark_circle_fill,
                          color: active ? Colors.white : brand.inkSoft,
                          size: 20,
                        ),
                        const SizedBox(width: 9),
                        Text(
                          _isEdit
                              ? context.t('common.update')
                              : context.t('expense.saveEntry'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white : brand.inkSoft,
                            letterSpacing: 0.1,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Account Transfer Toggle ──────────────────────────────────────────────────

  Widget _accountTransferToggle(BrandColors brand, {bool compact = false}) {
    return SectionCard(
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.sky,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              CupertinoIcons.arrow_right_arrow_left,
              size: 18,
              color: Color(0xFF2A6FB5),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('expense.transferBetweenAccounts'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  'e.g. Maybank → Touch \'n Go',
                  style: TextStyle(fontSize: 12, color: brand.inkSoft),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: _isAccountTransfer,
            onChanged: (v) => setState(() {
              _isAccountTransfer = v;
              if (v) {
                _toAccountId = null;
                _counterpartController.clear();
              }
            }),
          ),
        ],
      ),
    );
  }

  // ─── Grouped Details Card ─────────────────────────────────────────────────────

  Widget _groupedDetailsCard({
    required BrandColors brand,
    required List<Account> accounts,
    required String dateLabel,
    required bool isAccountTransfer,
    EntryType? entryType,
    bool compact = false,
  }) {
    final rowVPad = compact ? 9.0 : 13.0;
    final divider = Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 46),
      color: brand.divider,
    );

    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Column(
          children: [
            if (isAccountTransfer) ...[
              _inlineAccountRow(
                accounts: accounts,
                brand: brand,
                label: context.t('expense.from'),
                selectedId: _accountId,
                excludeId: _toAccountId,
                onSelect: (id) => setState(() => _accountId = id),
                rowVPad: rowVPad,
              ),
              divider,
              _inlineAccountRow(
                accounts: accounts,
                brand: brand,
                label: context.t('expense.to'),
                selectedId: _toAccountId,
                excludeId: _accountId,
                onSelect: (id) => setState(() => _toAccountId = id),
                rowVPad: rowVPad,
              ),
            ] else ...[
              _inlineAccountRow(
                accounts: accounts,
                brand: brand,
                label: context.t('expense.account'),
                selectedId: _accountId,
                onSelect: (id) => setState(() => _accountId = id),
                rowVPad: rowVPad,
              ),
            ],
            divider,
            // Date row
            InkWell(
              onTap: _pickDate,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: rowVPad,
                ),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.calendar,
                      size: 18,
                      color: brand.inkSoft,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.t('expense.date'),
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      dateLabel,
                      style: TextStyle(color: brand.inkSoft, fontSize: 15),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 13,
                      color: brand.inkSoft,
                    ),
                  ],
                ),
              ),
            ),
            divider,
            // Currency row
            CurrencyPickerTile(
              value: _currencyCode,
              onChanged: (code) => setState(() => _currencyCode = code),
              label: 'Currency',
            ),
            // Split bill toggle (expense only)
            if (entryType == EntryType.expense) ...[
              divider,
              _splitBillToggleRow(brand),
              if (_splitBillEnabled) ...[
                divider,
                _splitWithRow(brand),
                if (_splitBill != null) ...[divider, _generateReceiptButton()],
              ],
            ],
            divider,
            // Note row
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.only(top: rowVPad),
                    child: Icon(
                      CupertinoIcons.doc_text,
                      size: 18,
                      color: brand.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _noteController,
                      maxLines: null,
                      minLines: 1,
                      style: const TextStyle(fontSize: 15),
                      decoration: InputDecoration(
                        hintText: context.t('expense.note'),
                        hintStyle: TextStyle(
                          color: brand.inkSoft,
                          fontSize: 15,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          vertical: rowVPad,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            divider,
            // Receipt row
            InkWell(
              onTap: (_newReceipt == null && _existingReceiptUrl == null)
                  ? _pickReceipt
                  : null,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: compact ? 9.0 : 12.0,
                ),
                child: _receiptInlineContent(brand),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── Split Bill Toggle Row ────────────────────────────────────────────────────

  String _splitSubtitle(String symbol) {
    final n = _splitMembers.length;
    if (n == 0) return '';
    switch (_splitMode) {
      case SplitMode.equally:
        final each = _splitBillTotal > 0
            ? _splitBillTotal / n
            : _splitMembers.fold<double>(0, (s, m) => s + m.amount) / n;
        return '$n people · $symbol ${each.toStringAsFixed(2)} each';
      case SplitMode.amount:
        final total = _splitMembers.fold<double>(0, (s, m) => s + m.amount);
        return '$n people · $symbol ${total.toStringAsFixed(2)} total';
      case SplitMode.percent:
        return '$n people · by percentage';
      case SplitMode.shares:
        return '$n people · by shares';
    }
  }

  Widget _splitBillToggleRow(BrandColors brand) {
    final symbol = ref.read(currencySymbolProvider).valueOrNull ?? '\$';

    return InkWell(
      onTap: () => _openSplitBillSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.person_2,
              size: 18,
              color: _splitBillEnabled
                  ? const Color(0xFF6B40A8)
                  : brand.inkSoft,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Split bill',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: _splitBillEnabled
                          ? const Color(0xFF6B40A8)
                          : brand.ink,
                    ),
                  ),
                  if (_splitBillEnabled && _splitMembers.isNotEmpty)
                    Text(
                      _splitSubtitle(symbol),
                      style: TextStyle(fontSize: 12, color: brand.inkSoft),
                    )
                  else
                    Text(
                      'Share this expense with others',
                      style: TextStyle(fontSize: 12, color: brand.inkSoft),
                    ),
                ],
              ),
            ),
            CupertinoSwitch(
              value: _splitBillEnabled,
              activeTrackColor: const Color(0xFF6B40A8),
              onChanged: (v) {
                HapticFeedback.selectionClick();
                if (v) {
                  // Just enable — user taps Edit to configure
                  final amount = double.tryParse(_amountController.text) ?? 0;
                  setState(() {
                    _splitBillEnabled = true;
                    if (_splitBillTotal <= 0) _splitBillTotal = amount;
                    if (_splitMembers.isEmpty) {
                      _splitMembers = [
                        SplitMember(
                          id: DateTime.now().microsecondsSinceEpoch.toString(),
                          name: 'You',
                          colorIndex: 0,
                          amount: amount,
                          isPayer: true,
                        ),
                      ];
                    }
                  });
                } else {
                  setState(() {
                    _splitBillEnabled = false;
                    _splitBill = null;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  // ─── Split With Row (inside details card) ────────────────────────────────────

  Widget _splitWithRow(BrandColors brand) {
    final debtors = _splitMembers.where((m) => !m.isPayer).toList();
    return InkWell(
      onTap: () => _openSplitBillSheet(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Icon(CupertinoIcons.person_2_fill, size: 18, color: brand.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Split with',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
            // Mini avatars (up to 3 debtors)
            ...debtors.take(3).map((m) {
              final color =
                  _kSplitAvatarColors[m.colorIndex %
                      _kSplitAvatarColors.length];
              return Container(
                width: 24,
                height: 24,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: Center(
                  child: Text(
                    m.initials.isNotEmpty ? m.initials[0] : '?',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              );
            }),
            if (debtors.length > 3)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(
                  '+${debtors.length - 3}',
                  style: TextStyle(fontSize: 12, color: brand.inkSoft),
                ),
              ),
            const SizedBox(width: 4),
            const Text(
              'Edit',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF6B40A8),
              ),
            ),
            const SizedBox(width: 2),
            const Icon(
              CupertinoIcons.chevron_right,
              size: 13,
              color: Color(0xFF6B40A8),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openBillReceipt() async {
    final bill = _splitBill;
    if (bill == null) return;

    await Navigator.push(
      context,
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => BillReceiptScreen(bill: bill),
      ),
    );
    if (mounted) await _loadSplitBill();
  }

  Widget _generateReceiptButton() {
    return GestureDetector(
      onTap: _openBillReceipt,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF6B40A8),
            borderRadius: BorderRadius.circular(9999),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(CupertinoIcons.doc_text, color: Colors.white, size: 16),
              SizedBox(width: 8),
              Text(
                'Generate Receipt',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static const _kSplitAvatarColors = [
    Color(0xFF6B40A8),
    Color(0xFF2A82B4),
    Color(0xFFC0833A),
    Color(0xFF2A8C52),
    Color(0xFFB23A4A),
    Color(0xFFE8820E),
  ];

  // ─── Inline Account Row ───────────────────────────────────────────────────────

  Widget _inlineAccountRow({
    required List<Account> accounts,
    required BrandColors brand,
    required String label,
    required String? selectedId,
    String? excludeId,
    required void Function(String? id) onSelect,
    double rowVPad = 13.0,
  }) {
    final available = excludeId != null
        ? accounts.where((a) => a.id != excludeId).toList()
        : accounts;
    final selected = available.where((a) => a.id == selectedId).firstOrNull;

    return InkWell(
      onTap: () {
        if (available.isEmpty) {
          Navigator.push(
            context,
            CupertinoPageRoute(builder: (_) => const AddEditAccountScreen()),
          );
          return;
        }
        _showAccountPicker(
          available,
          brand,
          selectedId: selectedId,
          onSelect: onSelect,
        );
      },
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: rowVPad),
        child: Row(
          children: [
            Icon(
              selected != null
                  ? _iconForType(selected.type)
                  : CupertinoIcons.creditcard,
              size: 18,
              color: selected != null
                  ? _accentForType(selected.type)
                  : brand.inkSoft,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 15,
                ),
              ),
            ),
            Text(
              selected?.name ??
                  (available.isEmpty
                      ? context.t('expense.addAccount')
                      : context.t('expense.none')),
              style: TextStyle(color: brand.inkSoft, fontSize: 15),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right, size: 13, color: brand.inkSoft),
          ],
        ),
      ),
    );
  }

  // ─── Receipt Content ──────────────────────────────────────────────────────────

  Widget _receiptInlineContent(BrandColors brand) {
    final hasNew = _newReceipt != null;
    final hasExisting = _existingReceiptUrl != null;

    if (!hasNew && !hasExisting) {
      return Row(
        children: [
          Icon(CupertinoIcons.paperclip, size: 18, color: brand.inkSoft),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.t('expense.attachReceipt'),
              style: TextStyle(fontSize: 15, color: brand.inkSoft),
            ),
          ),
          Icon(CupertinoIcons.chevron_right, size: 13, color: brand.inkSoft),
        ],
      );
    }

    return Row(
      children: [
        Icon(CupertinoIcons.paperclip, size: 18, color: brand.inkSoft),
        const SizedBox(width: 12),
        if (hasNew)
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => Scaffold(
                  appBar: AppBar(title: Text(context.t('expense.receipt'))),
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
              child: Image.file(
                _newReceipt!,
                width: 44,
                height: 44,
                fit: BoxFit.contain,
              ),
            ),
          )
        else
          ReceiptPreview(stored: _existingReceiptUrl!, size: 44, fit: BoxFit.contain),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            hasNew
                ? context.t('expense.newAttachment')
                : context.t('expense.savedAttachment'),
            style: TextStyle(fontSize: 15, color: brand.ink, fontWeight: FontWeight.w500),
          ),
        ),
        GestureDetector(
          onTap: _pickReceipt,
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: brand.accentDark.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(CupertinoIcons.pencil, size: 15, color: brand.accentDark),
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
              color: AppColors.expense.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: const Icon(CupertinoIcons.delete, size: 15, color: AppColors.expense),
          ),
        ),
      ],
    );
  }

  // ─── Counterpart Field ────────────────────────────────────────────────────────

  Widget _counterpartField(BrandColors brand) {
    final label = _type == EntryType.transfer
        ? context.t('expense.toPerson')
        : context.t('expense.fromPerson');
    final hint = _type == EntryType.transfer
        ? 'e.g. John, Company ABC'
        : 'e.g. Sarah, Client XYZ';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _counterpartController,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            prefixIcon: Icon(
              _type == EntryType.transfer
                  ? CupertinoIcons.arrow_right_circle
                  : CupertinoIcons.arrow_left_circle,
              color: brand.inkSoft,
            ),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => _pickFromPeople(brand),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              border: Border.all(color: brand.divider),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.person_2_fill,
                  size: 14,
                  color: brand.inkSoft,
                ),
                const SizedBox(width: 6),
                Text(
                  context.t('expense.chooseFromPeople'),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickFromPeople(BrandColors brand) async {
    FocusScope.of(context).unfocus();
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PersonOrNamePickerSheet(
        currentName: _counterpartController.text.trim().isEmpty
            ? null
            : _counterpartController.text.trim(),
      ),
    );
    if (result is Person) {
      setState(() => _counterpartController.text = result.name);
    } else if (result is String && result.trim().isNotEmpty) {
      setState(() => _counterpartController.text = result.trim());
    }
    _dismissKeyboard();
  }

  void _showAccountPicker(
    List<Account> accounts,
    BrandColors brand, {
    required String? selectedId,
    required void Function(String? id) onSelect,
    bool allowNone = true,
  }) {
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
                    context.t('expense.selectAccount'),
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
                      if (allowNone)
                        ListTile(
                          leading: Icon(
                            CupertinoIcons.xmark_circle,
                            color: brand.inkSoft,
                          ),
                          title: Text(
                            context.t('expense.none'),
                            style: TextStyle(color: brand.inkSoft),
                          ),
                          trailing: selectedId == null
                              ? Icon(
                                  CupertinoIcons.checkmark_alt,
                                  color: brand.accentDark,
                                )
                              : null,
                          onTap: () {
                            onSelect(null);
                            Navigator.pop(ctx);
                          },
                        ),
                      ...accounts.map((a) {
                        final isSelected = selectedId == a.id;
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
                            onSelect(a.id);
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

  // ─── Account Type Helpers ─────────────────────────────────────────────────────

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
}
