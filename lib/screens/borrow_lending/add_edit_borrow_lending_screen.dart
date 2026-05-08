import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../models/borrow_lending.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/receipt_preview.dart';

/// Add or edit a borrow / lending record.
///
/// Reuses `StorageService` for the image attachment so receipts and
/// borrow-proof photos share the same on-disk receipts directory.
class AddEditBorrowLendingScreen extends ConsumerStatefulWidget {
  final BorrowLending? record;
  const AddEditBorrowLendingScreen({super.key, this.record});

  @override
  ConsumerState<AddEditBorrowLendingScreen> createState() =>
      _AddEditBorrowLendingScreenState();
}

class _AddEditBorrowLendingScreenState
    extends ConsumerState<AddEditBorrowLendingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _person = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  BorrowLendingType _type = BorrowLendingType.borrowed;
  DateTime _date = DateTime.now();
  DateTime? _dueDate;
  File? _newImage;
  String? _existingImagePath;
  bool _saving = false;

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final r = widget.record!;
      _type = r.type;
      _person.text = r.person;
      _amount.text = r.amount.toStringAsFixed(2);
      _note.text = r.note;
      _date = r.date;
      _dueDate = r.dueDate;
      _existingImagePath = r.imagePath;
    }
  }

  @override
  void dispose() {
    _person.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 70,
    );
    if (picked != null) {
      setState(() => _newImage = File(picked.path));
    }
  }

  Future<void> _pickDate({required bool due}) async {
    final initial = due ? (_dueDate ?? DateTime.now()) : _date;
    DateTime temp = initial;
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
                initialDateTime: initial,
                minimumDate: DateTime.now().subtract(const Duration(days: 365 * 10)),
                maximumDate: DateTime.now().add(const Duration(days: 365 * 10)),
                onDateTimeChanged: (d) => temp = d,
              ),
            ),
            CupertinoButton(
              onPressed: () {
                setState(() {
                  if (due) {
                    _dueDate = temp;
                  } else {
                    _date = temp;
                  }
                });
                Navigator.pop(ctx);
              },
              child: Text(context.t('common.done')),
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
    if (user == null) {
      setState(() => _saving = false);
      return;
    }

    // Upload image first so a failure aborts before writing Firestore.
    String? imagePath = _existingImagePath;
    if (_newImage != null) {
      try {
        imagePath = await ref
            .read(storageServiceProvider)
            .saveReceipt(user.uid, _newImage!);
      } catch (uploadError) {
        if (mounted) {
          final msg = _storageErrorMessage(uploadError);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
          );
          setState(() => _saving = false);
        }
        return;
      }
    }

    try {
      final now = DateTime.now();
      final amount = double.parse(_amount.text);
      final svc = ref.read(borrowLendingServiceProvider);

      if (_isEdit) {
        final updated = widget.record!.copyWith(
          type: _type,
          person: _person.text.trim(),
          amount: amount,
          note: _note.text.trim(),
          date: _date,
          dueDate: _dueDate,
          imagePath: imagePath,
          updatedAt: now,
        );
        await svc.update(user.uid, updated);
      } else {
        await svc.add(
          user.uid,
          BorrowLending(
            id: '',
            type: _type,
            person: _person.text.trim(),
            amount: amount,
            note: _note.text.trim(),
            date: _date,
            dueDate: _dueDate,
            imagePath: imagePath,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.t('common.saveFailed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  static String _storageErrorMessage(Object e) {
    return 'Image upload failed: $e';
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_isEdit ? context.t('bl.edit') : context.t('bl.new')),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _typeToggle(brand),
              const SizedBox(height: 16),
              TextFormField(
                controller: _person,
                decoration: InputDecoration(
                  labelText: context.t('bl.person'),
                  hintText: context.t('bl.personHint'),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.t('bl.personRequired')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: context.t('bl.amount'),
                  prefixText: '$symbol  ',
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
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: context.t('bl.note'),
                  hintText: context.t('bl.noteHint'),
                ),
              ),
              const SizedBox(height: 16),
              _dateTile(
                label: context.t('bl.dateLabel'),
                value: DateFormat('MMM d, yyyy').format(_date),
                onTap: () => _pickDate(due: false),
              ),
              const SizedBox(height: 10),
              _dateTile(
                label: context.t('bl.dueDateLabel'),
                value: _dueDate == null
                    ? context.t('bl.dueDateOptional')
                    : DateFormat('MMM d, yyyy').format(_dueDate!),
                onTap: () => _pickDate(due: true),
                trailingClear: _dueDate != null
                    ? () => setState(() => _dueDate = null)
                    : null,
              ),
              const SizedBox(height: 16),
              _imageCard(brand),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isEdit
                        ? context.t('common.update')
                        : context.t('common.save')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _typeToggle(BrandColors brand) {
    final selectedFg = foregroundOn(brand.accentDark);
    Widget chip(BorrowLendingType type, String label) {
      final selected = _type == type;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _type = type),
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
                fontWeight: FontWeight.w700,
                color: selected ? selectedFg : brand.ink,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        children: [
          chip(BorrowLendingType.borrowed, context.t('bl.typeBorrowed')),
          chip(BorrowLendingType.lent, context.t('bl.typeLent')),
        ],
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required String value,
    required VoidCallback onTap,
    VoidCallback? trailingClear,
  }) {
    final brand = context.brand;
    return Material(
      color: brand.surface,
      borderRadius: BorderRadius.circular(AppRadius.field),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.field),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(CupertinoIcons.calendar, color: brand.ink, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
              Text(value, style: TextStyle(color: brand.inkSoft)),
              if (trailingClear != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: trailingClear,
                  child: Icon(
                    CupertinoIcons.clear_circled_solid,
                    size: 16,
                    color: brand.inkSoft,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _imageCard(BrandColors brand) {
    final hasNew = _newImage != null;
    final hasExisting = _existingImagePath != null && !hasNew;
    final hasAny = hasNew || hasExisting;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CupertinoIcons.photo, color: brand.ink, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasAny ? context.t('bl.imageAttached') : context.t('bl.attachImage'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              if (!hasAny)
                TextButton(
                  onPressed: _pickImage,
                  child: Text(context.t('common.add')),
                ),
            ],
          ),
          if (hasAny) ...[
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (hasNew)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      _newImage!,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                    ),
                  )
                else
                  ReceiptPreview(stored: _existingImagePath!),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      TextButton(
                        onPressed: _pickImage,
                        child: Text(context.t('expense.replace')),
                      ),
                      TextButton(
                        onPressed: () => setState(() {
                          _newImage = null;
                          _existingImagePath = null;
                        }),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.expense,
                        ),
                        child: Text(context.t('expense.remove')),
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
}
