import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';

import '../../models/borrow_lending.dart';
import '../../models/person.dart';
import '../../screens/people/people_screen.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/person_avatar.dart';
import '../../widgets/receipt_preview.dart';

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
  final _personCtrl = TextEditingController();
  final _amount = TextEditingController();
  final _note = TextEditingController();

  BorrowLendingType _type = BorrowLendingType.borrowed;
  DateTime _date = DateTime.now();
  DateTime? _dueDate;
  File? _newImage;
  String? _existingImagePath;
  bool _saving = false;

  // Tracks colorIndex when person is selected from picker
  int? _personColorIndex;

  bool get _isEdit => widget.record != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final r = widget.record!;
      _type = r.type;
      _personCtrl.text = r.person;
      _amount.text = r.amount.toStringAsFixed(2);
      _note.text = r.note;
      _date = r.date;
      _dueDate = r.dueDate;
      _existingImagePath = r.imagePath;
    }
  }

  @override
  void dispose() {
    _personCtrl.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickPerson() async {
    FocusScope.of(context).unfocus();
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PersonOrNamePickerSheet(
        currentName: _personCtrl.text.isEmpty ? null : _personCtrl.text,
      ),
    );
    if (result is Person) {
      setState(() {
        _personCtrl.text = result.name;
        _personColorIndex = result.colorIndex;
      });
    } else if (result is String && result.trim().isNotEmpty) {
      setState(() {
        _personCtrl.text = result.trim();
        _personColorIndex = null;
      });
    }
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
                minimumDate:
                    DateTime.now().subtract(const Duration(days: 365 * 10)),
                maximumDate:
                    DateTime.now().add(const Duration(days: 365 * 10)),
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

    String? imagePath = _existingImagePath;
    if (_newImage != null) {
      try {
        imagePath = await ref
            .read(storageServiceProvider)
            .saveReceipt(user.uid, _newImage!);
      } catch (uploadError) {
        if (mounted) {
          final msg = 'Image upload failed: $uploadError';
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
          person: _personCtrl.text.trim(),
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
            person: _personCtrl.text.trim(),
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
      if (mounted) {
        AppToast.show(
          context,
          _isEdit ? 'Record updated' : 'Record saved',
          type: AppToastType.success,
        );
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, context.t('common.saveFailed'),
            type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(CupertinoIcons.xmark, color: brand.ink, size: 20),
        ),
        title: Text(
          _isEdit ? context.t('bl.edit') : context.t('bl.new'),
          style: TextStyle(
            color: brand.ink,
            fontWeight: FontWeight.w700,
            fontSize: 17,
            letterSpacing: -0.374,
          ),
        ),
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SafeArea(
          child: Form(
            key: _formKey,
            child: ListView(
              keyboardDismissBehavior:
                  ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
              children: [
                _typeToggle(brand),
                const SizedBox(height: 16),
                _personField(brand),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amount,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: context.t('bl.amount'),
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
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: context.t('bl.note'),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 16),
                _dateTile(
                  icon: CupertinoIcons.calendar,
                  label: context.t('bl.dateLabel'),
                  value: DateFormat('MMM d, yyyy').format(_date),
                  onTap: () => _pickDate(due: false),
                ),
                const SizedBox(height: 10),
                _dateTile(
                  icon: CupertinoIcons.calendar_badge_plus,
                  label: context.t('bl.dueDateLabel'),
                  value: _dueDate == null
                      ? context.t('bl.dueDateOptional')
                      : DateFormat('MMM d, yyyy').format(_dueDate!),
                  onTap: () => _pickDate(due: true),
                  trailingClear: _dueDate != null
                      ? () => setState(() => _dueDate = null)
                      : null,
                  valueSoft: _dueDate == null,
                ),
                const SizedBox(height: 10),
                _imageCard(brand),
                const SizedBox(height: 28),
                _saveButton(brand),
              ],
            ),
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
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: -0.2,
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

  Widget _personField(BrandColors brand) {
    final hasName = _personCtrl.text.trim().isNotEmpty;
    final name = _personCtrl.text.trim();
    final colorIdx = _personColorIndex ??
        (hasName ? personColorIndex(name) : null);

    return FormField<String>(
      validator: (_) =>
          !hasName ? context.t('bl.personRequired') : null,
      builder: (state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _pickPerson,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(AppRadius.field),
                  border: state.hasError
                      ? Border.all(color: AppColors.expense, width: 1.5)
                      : null,
                ),
                child: Row(
                  children: [
                    if (hasName)
                      PersonAvatar(
                        name: name,
                        colorIndex: colorIdx,
                        size: 40,
                      )
                    else
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: brand.divider,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.person,
                          size: 20,
                          color: brand.inkSoft,
                        ),
                      ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: hasName
                          ? Text(
                              name,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -0.2,
                                color: brand.ink,
                              ),
                            )
                          : Text(
                              context.t('bl.person'),
                              style: TextStyle(
                                fontSize: 15,
                                color: brand.inkSoft,
                              ),
                            ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_right,
                      size: 16,
                      color: brand.inkSoft,
                    ),
                  ],
                ),
              ),
            ),
            if (state.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 14),
                child: Text(
                  state.errorText!,
                  style: TextStyle(fontSize: 12, color: AppColors.expense),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _dateTile({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    VoidCallback? trailingClear,
    bool valueSoft = false,
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
              Icon(icon, color: brand.ink, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: brand.ink,
                  ),
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  color: valueSoft ? brand.inkSoft : brand.ink,
                  fontSize: 14,
                ),
              ),
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
                  hasAny
                      ? context.t('bl.imageAttached')
                      : context.t('bl.attachImage'),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: brand.ink,
                  ),
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

  Widget _saveButton(BrandColors brand) {
    return GestureDetector(
      onTap: _saving ? null : _save,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: _saving
              ? brand.ink.withValues(alpha: 0.5)
              : brand.accentDark,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        alignment: Alignment.center,
        child: _saving
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(
                _isEdit ? context.t('common.update') : context.t('common.save'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.374,
                  color: foregroundOn(brand.accentDark),
                ),
              ),
      ),
    );
  }
}
