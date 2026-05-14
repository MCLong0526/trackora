import 'dart:developer' as dev;
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/account.dart';
import '../../models/expense.dart';
import '../../repositories/local_expense_repository.dart';
import '../../screens/accounts/add_edit_account_screen.dart';
import '../../services/i18n.dart';
import '../../services/ocr_parser.dart';
import '../../services/sync_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/receipt_preview.dart';
import '../../widgets/section_card.dart';

// ── Channel ────────────────────────────────────────────────────────────────────

const _shareChannel = MethodChannel('trackora/share_import');

// ── Constants ─────────────────────────────────────────────────────────────────

const _expenseCategories = [
  'Food',
  'Groceries',
  'Transport',
  'Shopping',
  'Entertainment',
  'Health',
  'Bills',
  'Others',
];

const _incomeCategories = ['Salary', 'Others'];

// ── Screen ────────────────────────────────────────────────────────────────────

class ImportReceiptScreen extends ConsumerStatefulWidget {
  const ImportReceiptScreen({
    super.key,
    this.onClose,
    this.cameraFile,
    this.openCamera = false,
  });

  final VoidCallback? onClose;
  // When set, OCR runs on this file directly (camera flow) instead of reading
  // from the share extension app group container.
  final File? cameraFile;
  final bool openCamera;

  @override
  ConsumerState<ImportReceiptScreen> createState() =>
      _ImportReceiptScreenState();
}

class _ImportReceiptScreenState extends ConsumerState<ImportReceiptScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();

  EntryType _type = EntryType.expense;
  String _category = _expenseCategories.first;
  DateTime _date = DateTime.now();
  String? _accountId;
  File? _receiptFile;

  bool _loading = true;
  bool _saving = false;
  bool _notificationSent = false;

  @override
  void initState() {
    super.initState();
    if (widget.cameraFile != null) {
      _runOcrOnCameraFile(widget.cameraFile!);
    } else if (widget.openCamera) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pickCameraAndRunOcr();
      });
    } else {
      _runOcr();
    }
  }

  @override
  void dispose() {
    widget.onClose?.call();
    _amountCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  // ── OCR ──────────────────────────────────────────────────────────────────────

  Future<void> _runOcr() async {
    try {
      final raw = await _shareChannel.invokeMethod<Map<Object?, Object?>>(
        'checkPendingShare',
      );
      if (raw == null || !mounted) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final data = Map<String, dynamic>.from(raw);
      final imagePath = data['imagePath'] as String?;
      final rawText = data['rawText'] as String? ?? '';

      dev.log('[IMPORT_OCR] rawText: $rawText', name: 'ImportReceiptScreen');

      if (imagePath != null && imagePath.isNotEmpty) {
        final f = File(imagePath);
        if (f.existsSync()) setState(() => _receiptFile = f);
      }

      final parsed = OcrParser.parse(rawText);
      if (!mounted) return;

      final hasAmount = parsed.amount != null;
      final hasMerchant = parsed.merchant != null;

      setState(() {
        if (hasAmount) _amountCtrl.text = parsed.amount!.toStringAsFixed(2);
        if (hasMerchant) _noteCtrl.text = 'Store: ${parsed.merchant!}';
        if (parsed.date != null) _date = parsed.date!;
        _loading = false;
      });

      if (!_notificationSent) {
        _notificationSent = true;
        if (hasAmount && hasMerchant) {
          AppToast.show(
            context,
            'Receipt scanned',
            type: AppToastType.success,
            icon: CupertinoIcons.doc_text_fill,
          );
        } else if (hasAmount || hasMerchant) {
          AppToast.show(
            context,
            'Expense ready to review',
            type: AppToastType.info,
            icon: CupertinoIcons.doc_text,
          );
        } else {
          AppToast.show(
            context,
            'Couldn\'t read receipt — fill in manually',
            type: AppToastType.info,
            icon: CupertinoIcons.pencil,
          );
        }
      }
    } catch (e) {
      dev.log('[IMPORT_OCR] Error: $e', name: 'ImportReceiptScreen');
      if (!mounted) return;
      setState(() => _loading = false);
      if (!_notificationSent) {
        _notificationSent = true;
        AppToast.show(
          context,
          'OCR failed — enter details manually',
          type: AppToastType.error,
        );
      }
    }
  }

  // ── Camera OCR ───────────────────────────────────────────────────────────────

  Future<void> _pickCameraAndRunOcr() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
      );
      if (!mounted) return;
      if (picked == null) {
        setState(() => _loading = false);
        AppToast.show(
          context,
          'Scan cancelled — enter details manually',
          type: AppToastType.info,
          icon: CupertinoIcons.pencil,
        );
        return;
      }
      await _runOcrOnCameraFile(File(picked.path));
    } catch (e) {
      dev.log(
        '[IMPORT_OCR] Camera picker error: $e',
        name: 'ImportReceiptScreen',
      );
      if (!mounted) return;
      setState(() => _loading = false);
      AppToast.show(
        context,
        'Camera unavailable — enter details manually',
        type: AppToastType.error,
      );
    }
  }

  Future<void> _runOcrOnCameraFile(File file) async {
    try {
      if (file.existsSync()) setState(() => _receiptFile = file);

      final rawText =
          await _shareChannel.invokeMethod<String>('runOcrOnImage', {
            'imagePath': file.path,
          }) ??
          '';

      dev.log(
        '[IMPORT_OCR] camera rawText: $rawText',
        name: 'ImportReceiptScreen',
      );

      final parsed = OcrParser.parse(rawText);
      if (!mounted) return;

      final hasAmount = parsed.amount != null;
      final hasMerchant = parsed.merchant != null;

      setState(() {
        if (hasAmount) _amountCtrl.text = parsed.amount!.toStringAsFixed(2);
        if (hasMerchant) _noteCtrl.text = 'Store: ${parsed.merchant!}';
        if (parsed.date != null) _date = parsed.date!;
        _loading = false;
      });

      if (!_notificationSent) {
        _notificationSent = true;
        if (hasAmount || hasMerchant) {
          AppToast.show(
            context,
            'Receipt scanned',
            type: AppToastType.success,
            icon: CupertinoIcons.doc_text_fill,
          );
        } else {
          AppToast.show(
            context,
            'Couldn\'t read receipt — fill in manually',
            type: AppToastType.info,
            icon: CupertinoIcons.pencil,
          );
        }
      }
    } catch (e) {
      dev.log('[IMPORT_OCR] Camera OCR error: $e', name: 'ImportReceiptScreen');
      if (!mounted) return;
      setState(() => _loading = false);
      if (!_notificationSent) {
        _notificationSent = true;
        AppToast.show(
          context,
          'OCR failed — enter details manually',
          type: AppToastType.error,
        );
      }
    }
  }

  // ── Save ─────────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final isOnline = ref.read(isOnlineProvider);
    final expenses = ref.read(expenseRepositoryProvider);
    final storage = ref.read(storageServiceProvider);

    try {
      String? receiptUrl;
      if (_receiptFile != null) {
        try {
          receiptUrl = isOnline
              ? await storage.saveReceipt(user.uid, _receiptFile!)
              : await storage.saveReceiptLocally(user.uid, _receiptFile!);
        } catch (e) {
          dev.log(
            '[IMPORT_OCR] Receipt upload failed (non-fatal): $e',
            name: 'ImportReceiptScreen',
          );
        }
      }

      final now = DateTime.now();
      final expense = Expense(
        id: now.microsecondsSinceEpoch.toString(),
        amount: double.parse(_amountCtrl.text),
        category: _category,
        note: _noteCtrl.text.trim(),
        date: _date,
        type: _type,
        receiptUrl: receiptUrl,
        accountId: _accountId,
        createdAt: now,
        updatedAt: now,
      );

      if (isOnline) {
        await expenses.addExpense(user.uid, expense);
      } else {
        await LocalExpenseRepository().upsertExpense(user.uid, expense);
        if (storageMode == StorageMode.firebase) {
          await SyncService().markPending(user.uid, expense.id);
        }
      }

      await _shareChannel.invokeMethod('clearPendingShare');

      if (mounted) {
        AppToast.show(
          context,
          isOnline
              ? 'Expense saved'
              : 'Saved offline — will sync when connected',
          type: AppToastType.success,
          icon: CupertinoIcons.checkmark_circle_fill,
        );
        widget.onClose?.call();
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Save failed: $e', type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancel() async {
    try {
      await _shareChannel.invokeMethod('clearPendingShare');
    } catch (_) {}
    if (mounted) {
      widget.onClose?.call();
      Navigator.pop(context);
    }
  }

  // ── Pickers ───────────────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
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
          height: 400,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
                child: Text(
                  'Select Account',
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
                        'None',
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

  void _openReceiptViewer() {
    if (_receiptFile == null) return;
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => ReceiptViewerScreen(stored: _receiptFile!.path),
        fullscreenDialog: true,
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

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

  // ── Build ─────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final dateLabel = DateFormat('MMM d, yyyy').format(_date);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final selectedAccount = accounts
        .where((a) => a.id == _accountId)
        .firstOrNull;

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: GestureDetector(
          onTap: _cancel,
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: brand.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(CupertinoIcons.xmark, size: 17, color: brand.ink),
          ),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Import Receipt',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
            ),
            if (_loading)
              Text(
                'Scanning…',
                style: TextStyle(
                  fontSize: 12,
                  color: brand.inkSoft,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
      ),
      body: _loading
          ? _buildLoadingState(brand)
          : _buildForm(brand, symbol, dateLabel, accounts, selectedAccount),
    );
  }

  Widget _buildLoadingState(BrandColors brand) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: brand.accentDark,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Reading receipt…',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: brand.inkSoft,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'OCR in progress',
            style: TextStyle(fontSize: 13, color: brand.inkSoft),
          ),
        ],
      ),
    );
  }

  Widget _buildForm(
    BrandColors brand,
    String symbol,
    String dateLabel,
    List<Account> accounts,
    Account? selectedAccount,
  ) {
    final selectedChipFg = foregroundOn(brand.accentDark);
    return SafeArea(
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            _typeToggle(brand),
            const SizedBox(height: 14),
            _amountCard(symbol, brand),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                context.t('expense.category'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
            _categoryChips(selectedChipFg, brand),
            const SizedBox(height: 18),
            _detailsCard(brand, dateLabel, accounts, selectedAccount),
            const SizedBox(height: 14),
            if (_receiptFile != null) ...[
              _receiptThumbnail(brand),
              const SizedBox(height: 28),
            ] else
              const SizedBox(height: 14),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : const Text(
                        'Save Expense',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _typeToggle(BrandColors brand) {
    return SectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [EntryType.expense, EntryType.income].map((t) {
          final selected = _type == t;
          final label = t == EntryType.expense ? 'Expense' : 'Income';
          final color = t == EntryType.expense
              ? AppColors.expense
              : AppColors.income;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _type = t),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                height: 38,
                decoration: BoxDecoration(
                  color: selected
                      ? color.withValues(alpha: 0.15)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: selected ? color : brand.inkSoft,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _amountCard(String symbol, BrandColors brand) {
    return SectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              symbol,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextFormField(
              controller: _amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: const TextStyle(
                fontSize: 38,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
              decoration: InputDecoration(
                filled: false,
                hintText: '0.00',
                hintStyle: TextStyle(
                  fontSize: 38,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1,
                  color: brand.inkSoft,
                ),
                contentPadding: EdgeInsets.zero,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              validator: (v) {
                if (v == null || v.isEmpty) return 'Enter amount';
                if (double.tryParse(v) == null) return 'Invalid number';
                return null;
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _categoryChips(Color selectedChipFg, BrandColors brand) {
    final categories = _type == EntryType.income
        ? _incomeCategories
        : _expenseCategories;
    if (!categories.contains(_category)) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => setState(() => _category = categories.first),
      );
    }
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: categories.map((cat) {
        final selected = _category == cat;
        final s = styleFor(cat);
        return GestureDetector(
          onTap: () => setState(() => _category = cat),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? brand.accentDark : s.background,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  s.icon,
                  size: 16,
                  color: selected ? selectedChipFg : s.accent,
                ),
                const SizedBox(width: 8),
                Text(
                  context.categoryLabel(cat),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? selectedChipFg : AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _detailsCard(
    BrandColors brand,
    String dateLabel,
    List<Account> accounts,
    Account? selectedAccount,
  ) {
    final divider = Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 46),
      color: brand.divider,
    );

    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Column(
          children: [
            // Account row
            InkWell(
              onTap: () {
                if (accounts.isEmpty) {
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => const AddEditAccountScreen(),
                    ),
                  );
                  return;
                }
                _showAccountPicker(accounts, brand);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
                child: Row(
                  children: [
                    Icon(
                      selectedAccount != null
                          ? _iconForAccountType(selectedAccount.type)
                          : CupertinoIcons.creditcard,
                      size: 18,
                      color: selectedAccount != null
                          ? _accentForAccountType(selectedAccount.type)
                          : brand.inkSoft,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: const Text(
                        'Account',
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    Text(
                      selectedAccount?.name ??
                          (accounts.isEmpty ? 'Add account' : 'None'),
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

            // Date row
            InkWell(
              onTap: _pickDate,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
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

            // Notes / remarks row
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Icon(
                      CupertinoIcons.doc_text,
                      size: 18,
                      color: brand.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _noteCtrl,
                      maxLines: 2,
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
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 13,
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
    );
  }

  Widget _receiptThumbnail(BrandColors brand) {
    return GestureDetector(
      onTap: _openReceiptViewer,
      child: Container(
        height: 120,
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(AppRadius.card),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.card),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.file(_receiptFile!, fit: BoxFit.cover),
              // Bottom scrim for legibility
              Align(
                alignment: Alignment.bottomCenter,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.50),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                bottom: 9,
                right: 12,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.arrow_up_left_arrow_down_right,
                      size: 11,
                      color: Colors.white70,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Tap to view',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w500,
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
