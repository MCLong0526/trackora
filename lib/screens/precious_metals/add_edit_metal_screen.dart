import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/account.dart';
import '../../models/precious_metal.dart';
import '../../repositories/firebase_precious_metal_repository.dart';
import '../../state/providers.dart';
import '../../services/i18n.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

class AddEditMetalScreen extends ConsumerStatefulWidget {
  final PreciousMetal? metal;
  final MetalType? initialMetal;
  final MetalAction? initialAction;

  const AddEditMetalScreen({
    super.key,
    this.metal,
    this.initialMetal,
    this.initialAction,
  });

  @override
  ConsumerState<AddEditMetalScreen> createState() => _State();
}

class _State extends ConsumerState<AddEditMetalScreen> {
  final _weightCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _totalCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  final _weightFocus = FocusNode();
  final _priceFocus = FocusNode();
  final _totalFocus = FocusNode();

  late MetalType _metalType;
  late MetalAction _action;
  late DateTime _date;
  String? _accountId;
  bool _saving = false;
  bool _manualTotal = false;

  bool get _isEdit => widget.metal != null && widget.metal!.id.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _metalType = widget.metal?.metalType ?? widget.initialMetal ?? MetalType.gold;
    _action = widget.metal?.action ?? widget.initialAction ?? MetalAction.buy;
    _date = widget.metal?.date ?? DateTime.now();
    _accountId = widget.metal?.accountId;

    final m = widget.metal;
    if (m != null) {
      if (m.weightGrams > 0) _weightCtrl.text = _fmt(m.weightGrams);
      if (m.pricePerGram != null) _priceCtrl.text = _fmt(m.pricePerGram!);
      if (m.totalAmount > 0) _totalCtrl.text = _fmt(m.totalAmount);
    }
    _notesCtrl.text = widget.metal?.notes ?? '';

    _weightCtrl.addListener(_autoCalc);
    _priceCtrl.addListener(_autoCalc);
  }

  @override
  void dispose() {
    _weightCtrl.dispose();
    _priceCtrl.dispose();
    _totalCtrl.dispose();
    _notesCtrl.dispose();
    _weightFocus.dispose();
    _priceFocus.dispose();
    _totalFocus.dispose();
    super.dispose();
  }

  static String _fmt(double v) {
    if (v == v.truncateToDouble()) return v.toInt().toString();
    final s = v.toStringAsFixed(6);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  }

  void _selectAll(TextEditingController c) {
    if (c.text.isEmpty) return;
    c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
  }

  void _autoCalc() {
    if (_manualTotal) return;
    final w = double.tryParse(_weightCtrl.text);
    final p = double.tryParse(_priceCtrl.text);
    if (w != null && p != null) {
      _totalCtrl.text = (w * p).toStringAsFixed(2);
    } else if (_weightCtrl.text.isEmpty || _priceCtrl.text.isEmpty) {
      _totalCtrl.text = '';
    }
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    final weight = double.tryParse(_weightCtrl.text);
    final total = double.tryParse(_totalCtrl.text);
    if (weight == null || weight <= 0) {
      AppToast.show(context, 'Enter a valid weight', type: AppToastType.error);
      return;
    }
    if (total == null || total <= 0) {
      AppToast.show(context, 'Enter a valid amount', type: AppToastType.error);
      return;
    }
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final repo = ref.read(preciousMetalRepositoryProvider);
      final now = DateTime.now();
      final pricePerGram = double.tryParse(_priceCtrl.text);
      final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

      if (_isEdit) {
        final updated = widget.metal!.copyWith(
          metalType: _metalType,
          action: _action,
          weightGrams: weight,
          pricePerGram: pricePerGram,
          totalAmount: total,
          date: _date,
          notes: notes,
          accountId: _accountId,
        );
        await repo.update(user.uid, updated);
        _bgSyncUpdate(user.uid, updated);
        if (mounted) {
          AppToast.show(context, 'Record updated', type: AppToastType.success);
          Navigator.pop(context, updated);
        }
      } else {
        final id = now.microsecondsSinceEpoch.toString();
        final newM = PreciousMetal(
          id: id,
          metalType: _metalType,
          action: _action,
          weightGrams: weight,
          pricePerGram: pricePerGram,
          totalAmount: total,
          date: _date,
          notes: notes,
          accountId: _accountId,
          createdAt: now,
        );
        await repo.add(user.uid, newM);
        _bgSyncAdd(user.uid, newM);
        if (mounted) {
          AppToast.show(
            context,
            _action == MetalAction.buy
                ? '${_metalType.label} purchased'
                : '${_metalType.label} sold',
            type: AppToastType.success,
          );
          Navigator.pop(context, 'saved');
        }
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(
          context,
          _isEdit ? 'Update failed' : 'Save failed',
          type: AppToastType.error,
        );
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _delete() async {
    FocusScope.of(context).unfocus();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Delete Record'),
        content: const Text('This record will be permanently deleted.'),
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
    if (confirmed != true) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;

    setState(() => _saving = true);
    try {
      final id = widget.metal!.id;
      await ref.read(preciousMetalRepositoryProvider).delete(user.uid, id);
      _bgSyncDelete(user.uid, id);
      if (mounted) {
        AppToast.show(context, context.t('metal.deletedToast'), type: AppToastType.success);
        Navigator.pop(context, 'deleted');
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, context.t('metal.deleteFailed'), type: AppToastType.error);
        setState(() => _saving = false);
      }
    }
  }

  void _bgSyncAdd(String uid, PreciousMetal m) {
    if (storageMode != StorageMode.firebase) return;
    FirebasePreciousMetalRepository().add(uid, m).catchError((_) {});
  }

  void _bgSyncUpdate(String uid, PreciousMetal m) {
    if (storageMode != StorageMode.firebase) return;
    FirebasePreciousMetalRepository().update(uid, m).catchError((_) {});
  }

  void _bgSyncDelete(String uid, String id) {
    if (storageMode != StorageMode.firebase) return;
    FirebasePreciousMetalRepository().delete(uid, id).catchError((_) {});
  }

  Future<void> _pickDate() async {
    FocusScope.of(context).unfocus();
    DateTime temp = _date;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) {
        final brand = ctx.brand;
        return Container(
          height: 300,
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: brand.inkSoft.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: temp,
                  maximumDate: DateTime.now().add(const Duration(days: 1)),
                  minimumDate: DateTime(2000),
                  onDateTimeChanged: (d) => temp = d,
                ),
              ),
              CupertinoButton(
                child: Text(
                  'Done',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: _metalType.primaryColor,
                  ),
                ),
                onPressed: () {
                  setState(() => _date = temp);
                  Navigator.pop(ctx);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final metalColor = _metalType.primaryColor;

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: brand.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(CupertinoIcons.xmark, size: 17, color: brand.ink),
          ),
        ),
        title: Text(
          _isEdit ? context.t('metal.editRecord') : context.t('metal.newTransaction'),
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          if (_isEdit)
            GestureDetector(
              onTap: _saving ? null : _delete,
              child: Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.blush,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.delete,
                  size: 17,
                  color: AppColors.expense,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // ── Metal / Action selectors (new record only) ───────────────────
            if (!_isEdit) ...[
              _MetalActionToggle(
                metalType: _metalType,
                action: _action,
                onMetalChanged: (t) => setState(() {
                  _metalType = t;
                  _manualTotal = false;
                }),
                onActionChanged: (a) => setState(() => _action = a),
              ),
              const SizedBox(height: 14),
            ],

            // ── Edit mode: metal/action badge ────────────────────────────────
            if (_isEdit) ...[
              _EditBadge(metal: widget.metal!),
              const SizedBox(height: 14),
            ],

            // ── Amount inputs ────────────────────────────────────────────────
            _SectionLabel(context.t('metal.sectionAmount')),
            const SizedBox(height: 10),
            _InputGroup(
              brand: brand,
              children: [
                _Field(
                  label: context.t('metal.weightGramsFull'),
                  controller: _weightCtrl,
                  focusNode: _weightFocus,
                  hint: 'e.g. 10.50',
                  suffix: 'g',
                  onTap: () => _selectAll(_weightCtrl),
                  nextFocus: _priceFocus,
                ),
                _FieldDivider(brand: brand),
                _Field(
                  label: context.t('metal.pricePerGramFull'),
                  controller: _priceCtrl,
                  focusNode: _priceFocus,
                  hint: 'Optional',
                  prefix: symbol,
                  onTap: () => _selectAll(_priceCtrl),
                  nextFocus: _totalFocus,
                ),
                _FieldDivider(brand: brand),
                _Field(
                  label: context.t('metal.totalAmount'),
                  controller: _totalCtrl,
                  focusNode: _totalFocus,
                  hint: 'e.g. 892.50',
                  prefix: symbol,
                  accent: metalColor,
                  onTap: () {
                    _selectAll(_totalCtrl);
                    setState(() => _manualTotal = true);
                  },
                  onChanged: (_) => setState(() => _manualTotal = true),
                  isLast: true,
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ── Details ──────────────────────────────────────────────────────
            _SectionLabel(context.t('metal.sectionDetails')),
            const SizedBox(height: 10),
            _InputGroup(
              brand: brand,
              children: [
                _DateRow(
                  date: _date,
                  brand: brand,
                  metalColor: metalColor,
                  onTap: _pickDate,
                ),
                if (accounts.isNotEmpty) ...[
                  _FieldDivider(brand: brand),
                  _AccountRow(
                    accounts: accounts,
                    selectedId: _accountId,
                    brand: brand,
                    metalColor: metalColor,
                    onChanged: (id) => setState(() => _accountId = id),
                  ),
                ],
                _FieldDivider(brand: brand),
                _NotesRow(controller: _notesCtrl, brand: brand),
              ],
            ),

            const SizedBox(height: 28),

            // ── Save button ──────────────────────────────────────────────────
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _saving ? null : _save,
                style: FilledButton.styleFrom(
                  backgroundColor: metalColor,
                  disabledBackgroundColor: metalColor.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                child: _saving
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isEdit ? context.t('metal.saveChanges') : (_action == MetalAction.buy ? context.t('metal.recordPurchase') : context.t('metal.recordSale')),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Metal + Action toggle (for new records)
// ─────────────────────────────────────────────────────────────────────────────

class _MetalActionToggle extends StatelessWidget {
  final MetalType metalType;
  final MetalAction action;
  final ValueChanged<MetalType> onMetalChanged;
  final ValueChanged<MetalAction> onActionChanged;

  const _MetalActionToggle({
    required this.metalType,
    required this.action,
    required this.onMetalChanged,
    required this.onActionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      children: [
        // Metal selector
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Row(
            children: MetalType.values.map((t) {
              final selected = t == metalType;
              final c = t.primaryColor;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onMetalChanged(t),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? c.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: selected
                          ? Border.all(color: c.withValues(alpha: 0.30))
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CustomPaint(
                          size: const Size(18, 11),
                          painter: _IngotPainter(isGold: t == MetalType.gold),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          t.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? c : brand.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
        const SizedBox(height: 8),
        // Action selector
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Row(
            children: MetalAction.values.map((a) {
              final selected = a == action;
              final c = a == MetalAction.buy ? AppColors.income : AppColors.expense;
              return Expanded(
                child: GestureDetector(
                  onTap: () => onActionChanged(a),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: selected ? c.withValues(alpha: 0.12) : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                      border: selected
                          ? Border.all(color: c.withValues(alpha: 0.28))
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          a == MetalAction.buy
                              ? CupertinoIcons.arrow_down_circle_fill
                              : CupertinoIcons.arrow_up_circle_fill,
                          size: 14,
                          color: selected ? c : brand.inkSoft,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          a.label,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? c : brand.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Edit mode badge — shows metal type + action + date at a glance
// ─────────────────────────────────────────────────────────────────────────────

class _EditBadge extends StatelessWidget {
  final PreciousMetal metal;
  const _EditBadge({required this.metal});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isBuy = metal.action == MetalAction.buy;
    final actionColor = isBuy ? AppColors.income : AppColors.expense;
    final metalColor = metal.metalType.primaryColor;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.field),
        ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: metalColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: CustomPaint(
                size: const Size(22, 14),
                painter: _IngotPainter(isGold: metal.metalType == MetalType.gold),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metal.metalType.label,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
                Text(
                  DateFormat('d MMMM yyyy').format(metal.date),
                  style: TextStyle(
                    fontSize: 12,
                    color: brand.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: actionColor.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: actionColor.withValues(alpha: 0.25)),
            ),
            child: Text(
              isBuy ? context.t('metal.buy') : context.t('metal.sell'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: actionColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared UI primitives
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF8E8E93),
        letterSpacing: 0.8,
      ),
    );
  }
}

class _InputGroup extends StatelessWidget {
  final List<Widget> children;
  final BrandColors brand;

  const _InputGroup({required this.children, required this.brand});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(22),
        ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: Column(children: children),
      ),
    );
  }
}

class _FieldDivider extends StatelessWidget {
  final BrandColors brand;
  const _FieldDivider({required this.brand});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 60),
      child: Divider(height: 0.5, thickness: 0.5, color: brand.divider),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Numeric field row
// ─────────────────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final String? prefix;
  final String? suffix;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final FocusNode? nextFocus;
  final bool isLast;
  final Color? accent;

  const _Field({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.prefix,
    this.suffix,
    this.onTap,
    this.onChanged,
    this.nextFocus,
    this.isLast = false,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (prefix != null)
            SizedBox(
              width: 40,
              child: Text(
                prefix!,
                style: TextStyle(fontSize: 15, color: brand.inkSoft, fontWeight: FontWeight.w500),
              ),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: brand.inkSoft),
                ),
                const SizedBox(height: 2),
                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textInputAction: nextFocus != null ? TextInputAction.next : TextInputAction.done,
                  onTap: onTap,
                  onChanged: onChanged,
                  onSubmitted: (_) {
                    if (nextFocus != null) FocusScope.of(context).requestFocus(nextFocus);
                  },
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: accent ?? brand.ink,
                  ),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w400,
                      color: brand.inkSoft.withValues(alpha: 0.45),
                    ),
                    filled: false,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 4),
                    suffixText: suffix,
                    suffixStyle: TextStyle(fontSize: 14, color: brand.inkSoft),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Details rows
// ─────────────────────────────────────────────────────────────────────────────

class _DateRow extends StatelessWidget {
  final DateTime date;
  final BrandColors brand;
  final Color metalColor;
  final VoidCallback onTap;

  const _DateRow({
    required this.date,
    required this.brand,
    required this.metalColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            Icon(CupertinoIcons.calendar, size: 18, color: brand.inkSoft),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Date',
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
              ),
            ),
            Text(
              DateFormat('d MMM yyyy').format(date),
              style: TextStyle(color: brand.inkSoft, fontSize: 15),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right, size: 13, color: brand.inkSoft),
          ],
        ),
      ),
    );
  }
}

class _AccountRow extends StatelessWidget {
  final List<Account> accounts;
  final String? selectedId;
  final BrandColors brand;
  final Color metalColor;
  final ValueChanged<String?> onChanged;

  const _AccountRow({
    required this.accounts,
    required this.selectedId,
    required this.brand,
    required this.metalColor,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final selected = accounts.where((a) => a.id == selectedId).firstOrNull;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          Icon(CupertinoIcons.creditcard, size: 18, color: brand.inkSoft),
          const SizedBox(width: 12),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: selectedId,
                isDense: true,
                isExpanded: true,
                dropdownColor: brand.surface,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: brand.ink,
                ),
                hint: Text(
                  'Account',
                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                ),
                selectedItemBuilder: (_) => [
                  Text(
                    'None',
                    style: TextStyle(
                      fontSize: 15,
                      color: brand.inkSoft.withValues(alpha: 0.55),
                    ),
                  ),
                  ...accounts.map(
                    (a) => Text(
                      a.name,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: brand.ink),
                    ),
                  ),
                ],
                items: [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None', style: TextStyle(color: brand.inkSoft)),
                  ),
                  ...accounts.map(
                    (a) => DropdownMenuItem<String?>(
                      value: a.id,
                      child: Text(a.name, style: TextStyle(color: brand.ink)),
                    ),
                  ),
                ],
                onChanged: onChanged,
              ),
            ),
          ),
          Text(
            selected?.name ?? 'None',
            style: TextStyle(color: brand.inkSoft, fontSize: 15),
          ),
          const SizedBox(width: 4),
          Icon(CupertinoIcons.chevron_right, size: 13, color: brand.inkSoft),
        ],
      ),
    );
  }
}

class _NotesRow extends StatelessWidget {
  final TextEditingController controller;
  final BrandColors brand;

  const _NotesRow({required this.controller, required this.brand});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Icon(CupertinoIcons.doc_text, size: 18, color: brand.inkSoft),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              maxLines: 3,
              minLines: 1,
              textInputAction: TextInputAction.newline,
              style: TextStyle(fontSize: 15, color: brand.ink),
              decoration: InputDecoration(
                hintText: 'Add a note (optional)',
                hintStyle: TextStyle(fontSize: 15, color: brand.inkSoft.withValues(alpha: 0.45)),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 13),
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ingot painter (shared with precious_metals_screen)
// ─────────────────────────────────────────────────────────────────────────────

class _IngotPainter extends CustomPainter {
  final bool isGold;
  const _IngotPainter({required this.isGold});

  @override
  void paint(Canvas canvas, Size size) {
    final light = isGold ? const Color(0xFFFFE97A) : const Color(0xFFECF2F8);
    final mid = isGold ? const Color(0xFFD4AF37) : const Color(0xFFB8C8D8);
    final dark = isGold ? const Color(0xFF9A7020) : const Color(0xFF7A8A98);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rr = RRect.fromRectAndRadius(rect, Radius.circular(size.height * 0.22));
    canvas.drawRRect(
      rr,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, mid, dark],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );
    canvas.drawLine(
      Offset(size.width * 0.16, size.height * 0.30),
      Offset(size.width * 0.70, size.height * 0.30),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = size.height * 0.08
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_IngotPainter old) => old.isGold != isGold;
}
