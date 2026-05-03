import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../models/expense.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
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
  'Others',
];

const kIncomeCategories = ['Salary', 'Others'];

class AddEditExpenseScreen extends ConsumerStatefulWidget {
  final Expense? expense;
  const AddEditExpenseScreen({super.key, this.expense});

  @override
  ConsumerState<AddEditExpenseScreen> createState() =>
      _AddEditExpenseScreenState();
}

class _AddEditExpenseScreenState extends ConsumerState<AddEditExpenseScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  EntryType _type = EntryType.expense;
  String _category = kExpenseCategories.first;
  DateTime _date = DateTime.now();
  bool _saving = false;
  File? _newReceipt;
  String? _existingReceiptUrl;

  bool get _isEdit => widget.expense != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final e = widget.expense!;
      _amountController.text = e.amount.toStringAsFixed(2);
      _noteController.text = e.note;
      _category = e.category;
      _date = e.date;
      _type = e.type;
      _existingReceiptUrl = e.receiptUrl;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  List<String> get _categories =>
      _type == EntryType.income ? kIncomeCategories : kExpenseCategories;

  Future<void> _pickReceipt() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked != null) {
      setState(() => _newReceipt = File(picked.path));
    }
  }

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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final expenses = ref.read(expenseRepositoryProvider);
    final storage = ref.read(storageServiceProvider);

    try {
      String? receiptUrl = _existingReceiptUrl;
      if (_newReceipt != null) {
        receiptUrl = await storage.saveReceipt(user.uid, _newReceipt!);
      }

      final amount = double.parse(_amountController.text);
      final now = DateTime.now();

      if (_isEdit) {
        final updated = widget.expense!.copyWith(
          amount: amount,
          category: _category,
          note: _noteController.text.trim(),
          date: _date,
          type: _type,
          receiptUrl: receiptUrl,
          updatedAt: now,
        );
        await expenses.updateExpense(user.uid, updated);
      } else {
        final e = Expense(
          id: '',
          amount: amount,
          category: _category,
          note: _noteController.text.trim(),
          date: _date,
          type: _type,
          receiptUrl: receiptUrl,
          createdAt: now,
          updatedAt: now,
        );
        await expenses.addExpense(user.uid, e);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${context.t('common.saveFailed')}: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
    await ref
        .read(expenseRepositoryProvider)
        .deleteExpense(user.uid, widget.expense!.id);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final dateLabel = DateFormat('MMM d, yyyy').format(_date);
    final selectedChipFg = foregroundOn(brand.accentDark);

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit ? context.t('expense.edit') : context.t('expense.new'),
        ),
        actions: [
          if (_isEdit)
            IconButton(
              icon: const Icon(CupertinoIcons.delete, size: 20),
              color: AppColors.expense,
              onPressed: _delete,
            ),
        ],
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              _typeToggle(),
              const SizedBox(height: 18),
              SectionCard(
                color: _type == EntryType.income
                    ? AppColors.mint
                    : AppColors.lilac,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('expense.amount'),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            symbol,
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: TextFormField(
                            controller: _amountController,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(
                              fontSize: 38,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -1,
                            ),
                            decoration: const InputDecoration(
                              filled: false,
                              hintText: '0.00',
                              hintStyle: TextStyle(
                                color: AppColors.inkSoft,
                                fontWeight: FontWeight.w800,
                                fontSize: 38,
                                letterSpacing: -1,
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
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  context.t('expense.category'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: _categories.map((c) {
                  final selected = c == _category;
                  final s = styleFor(c);
                  return GestureDetector(
                    onTap: () => setState(() => _category = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
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
                            context.categoryLabel(c),
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
              ),
              const SizedBox(height: 18),
              SectionCard(
                onTap: _pickDate,
                child: Row(
                  children: [
                    Icon(CupertinoIcons.calendar, color: brand.ink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        context.t('expense.date'),
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    Text(dateLabel, style: TextStyle(color: brand.inkSoft)),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                maxLines: 2,
                decoration: InputDecoration(
                  hintText: context.t('expense.note'),
                ),
              ),
              const SizedBox(height: 12),
              _receiptCard(brand),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        _isEdit
                            ? context.t('common.update')
                            : context.t('expense.saveEntry'),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _receiptCard(BrandColors brand) {
    final hasNew = _newReceipt != null;
    final hasExisting = _existingReceiptUrl != null && !hasNew;
    final hasAny = hasNew || hasExisting;

    return SectionCard(
      onTap: hasAny ? null : _pickReceipt,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.paperclip, color: brand.ink),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasAny
                      ? context.t('expense.receipt')
                      : context.t('expense.attachReceipt'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (!hasAny)
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 16,
                  color: brand.inkSoft,
                ),
            ],
          ),
          if (hasAny) ...[
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasNew)
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      CupertinoPageRoute(
                        builder: (_) => Scaffold(
                          backgroundColor: Colors.black,
                          appBar: AppBar(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                            leading: IconButton(
                              icon: const Icon(CupertinoIcons.xmark),
                              onPressed: () => Navigator.pop(context),
                            ),
                            title: Text(context.t('expense.receipt')),
                          ),
                          body: Center(
                            child: InteractiveViewer(
                              child: Image.file(
                                _newReceipt!,
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                        ),
                        fullscreenDialog: true,
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(
                        _newReceipt!,
                        width: 64,
                        height: 64,
                        fit: BoxFit.cover,
                      ),
                    ),
                  )
                else
                  ReceiptPreview(stored: _existingReceiptUrl!),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasNew
                            ? context.t('expense.newAttachment')
                            : context.t('expense.savedAttachment'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.t('expense.tapThumbnail'),
                        style: TextStyle(fontSize: 11, color: brand.inkSoft),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        children: [
                          TextButton(
                            onPressed: _pickReceipt,
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              minimumSize: const Size(0, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(context.t('expense.replace')),
                          ),
                          TextButton(
                            onPressed: () => setState(() {
                              _newReceipt = null;
                              _existingReceiptUrl = null;
                            }),
                            style: TextButton.styleFrom(
                              foregroundColor: AppColors.expense,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              minimumSize: const Size(0, 30),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(context.t('expense.remove')),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _typeToggle() {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          _typeChip(context.t('expense.expense'), EntryType.expense),
          _typeChip(context.t('expense.income'), EntryType.income),
        ],
      ),
    );
  }

  Widget _typeChip(String label, EntryType type) {
    final brand = context.brand;
    final selected = _type == type;
    final selectedFg = foregroundOn(brand.accentDark);
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _type = type;
            if (!_categories.contains(_category)) {
              _category = _categories.first;
            }
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? brand.accentDark : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: selected ? selectedFg : brand.ink,
            ),
          ),
        ),
      ),
    );
  }
}
