import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

// ── Category metadata ─────────────────────────────────────────────────────────

const _kCategoryMeta = [
  _CatMeta('Food', CupertinoIcons.bag_fill, Color(0xFFF0A33A)),
  _CatMeta('Groceries', CupertinoIcons.cube_box_fill, Color(0xFF1FBE71)),
  _CatMeta('Transport', CupertinoIcons.car_fill, Color(0xFF1A6CFF)),
  _CatMeta('Shopping', CupertinoIcons.cart_fill, Color(0xFFF47A85)),
  _CatMeta('Entertainment', CupertinoIcons.film_fill, Color(0xFF9F3AAF)),
  _CatMeta('Health', CupertinoIcons.heart_fill, Color(0xFFFF6B6B)),
  _CatMeta('Bills', CupertinoIcons.doc_fill, Color(0xFF8E8E96)),
  _CatMeta('Others', CupertinoIcons.ellipsis_circle_fill, Color(0xFFAAAAAA)),
];

class _CatMeta {
  final String label;
  final IconData icon;
  final Color color;
  const _CatMeta(this.label, this.icon, this.color);
}

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
    extends ConsumerState<AddGroupExpenseScreen> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  String _category = 'Food';
  DateTime _date = DateTime.now();
  String? _paidByUid;
  late Set<String> _splitBetween;
  bool _saving = false;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authStateProvider).valueOrNull;
    _paidByUid = widget.existing?.paidBy ?? user?.uid;
    _splitBetween = widget.existing != null
        ? widget.existing!.splitBetween.toSet()
        : widget.group.memberUids.toSet();

    if (widget.existing != null) {
      final e = widget.existing!;
      _amountCtrl.text = e.amount.toStringAsFixed(2);
      _descCtrl.text = e.description;
      _notesCtrl.text = e.notes ?? '';
      _category = e.category;
      _date = e.date;
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      AppToast.show(context, context.t('validation.invalidAmount'));
      return;
    }
    final desc = _descCtrl.text.trim();
    if (desc.isEmpty) {
      AppToast.show(context, 'Enter a description');
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
        notes:
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        createdAt: widget.existing?.createdAt ?? now,
        updatedAt: now,
      );
      if (_isEdit) {
        await service.updateExpense(expense);
      } else {
        await service.addExpense(expense);
      }
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) AppToast.show(context, context.t('common.saveFailed'));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _splitSummary(String symbol) {
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amt <= 0 || _splitBetween.isEmpty) return '';
    final perPerson = amt / _splitBetween.length;
    return '$symbol${perPerson.toStringAsFixed(2)} per person';
  }

  void _pickDate(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 260,
        color: context.brand.surface,
        child: CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: _date,
          maximumDate: DateTime.now().add(const Duration(days: 1)),
          onDateTimeChanged: (dt) => setState(() => _date = dt),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final members = widget.group.members;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '';
    final partner = members.where((m) => m.uid != ref.read(authStateProvider).valueOrNull?.uid).firstOrNull;
    final partnerName = partner?.displayName ?? 'Partner';

    // Find current category meta
    final catMeta = _kCategoryMeta.firstWhere(
      (c) => c.label == _category,
      orElse: () => _kCategoryMeta.last,
    );

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: const Icon(CupertinoIcons.xmark,
              color: Color(0xFF8E8E96), size: 20),
        ),
        title: Text(
          _isEdit ? context.t('common.edit') : 'New entry',
          style: TextStyle(
            color: brand.ink,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Purple/lilac header card ─────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAE3F8),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Group info row
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF5A4AAB)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Icon(
                                CupertinoIcons.person_2_fill,
                                color: Color(0xFF5A4AAB),
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Group expense',
                                  style: TextStyle(
                                    color: Color(0xFF5A4AAB),
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  'Shared with $partnerName',
                                  style: const TextStyle(
                                    color: Color(0xFF8E7DD4),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),

                        const SizedBox(height: 24),

                        // Large amount field
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Text(
                              symbol,
                              style: const TextStyle(
                                color: Color(0xFF8E7DD4),
                                fontSize: 22,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: TextField(
                                controller: _amountCtrl,
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                        decimal: true),
                                style: const TextStyle(
                                  color: Color(0xFF2D1A72),
                                  fontSize: 48,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -1,
                                  height: 1.1,
                                ),
                                decoration: const InputDecoration(
                                  border: InputBorder.none,
                                  hintText: '0.00',
                                  hintStyle: TextStyle(
                                    color: Color(0xFFB0A3D8),
                                    fontSize: 48,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -1,
                                    height: 1.1,
                                  ),
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 20),

                        // Category icons row
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: _kCategoryMeta.map((cat) {
                              final isSelected = cat.label == _category;
                              return GestureDetector(
                                onTap: () =>
                                    setState(() => _category = cat.label),
                                child: _CategoryIcon(
                                    cat: cat, isSelected: isSelected),
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ── Description field ────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: TextField(
                      controller: _descCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      style: TextStyle(color: brand.ink, fontSize: 15),
                      decoration: InputDecoration(
                        border: InputBorder.none,
                        hintText: 'Description, e.g. Dinner, Uber',
                        hintStyle:
                            TextStyle(color: brand.inkSoft, fontSize: 15),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Detail card ──────────────────────────────
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        // Date row
                        _DetailRow(
                          icon: CupertinoIcons.calendar,
                          label: context.t('expense.date'),
                          value: DateFormat('MMM d, yyyy').format(_date),
                          onTap: () => _pickDate(context),
                          brand: brand,
                        ),
                        Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 16,
                            endIndent: 16,
                            color: brand.divider),

                        // Paid by row
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(CupertinoIcons.person_fill,
                                      color: brand.inkSoft, size: 16),
                                  const SizedBox(width: 8),
                                  Text(
                                    context.t('group.paidBy'),
                                    style: TextStyle(
                                      color: brand.ink,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: members.map((m) {
                                  final selected = m.uid == _paidByUid;
                                  return GestureDetector(
                                    onTap: () => setState(
                                        () => _paidByUid = m.uid),
                                    child: _MemberChip(
                                      brand: brand,
                                      name: m.displayName,
                                      selected: selected,
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),

                        Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 16,
                            endIndent: 16,
                            color: brand.divider),

                        // Split between row
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 12, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      Icon(CupertinoIcons.arrow_left_right,
                                          color: brand.inkSoft, size: 16),
                                      const SizedBox(width: 8),
                                      Text(
                                        context.t('group.splitBetween'),
                                        style: TextStyle(
                                          color: brand.ink,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                    ],
                                  ),
                                  GestureDetector(
                                    onTap: () => setState(() =>
                                        _splitBetween = widget
                                            .group.memberUids
                                            .toSet()),
                                    child: Text(
                                      context.t('group.splitEqually'),
                                      style: const TextStyle(
                                        color: AppActionBlue.color,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: members.map((m) {
                                  final selected =
                                      _splitBetween.contains(m.uid);
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() {
                                        if (selected) {
                                          _splitBetween.remove(m.uid);
                                        } else {
                                          _splitBetween.add(m.uid);
                                        }
                                      });
                                    },
                                    child: _MemberChip(
                                      brand: brand,
                                      name: m.displayName,
                                      selected: selected,
                                      checkmark: true,
                                    ),
                                  );
                                }).toList(),
                              ),
                              if (_splitBetween.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Text(
                                  _splitSummary(symbol),
                                  style: TextStyle(
                                    color: brand.inkSoft,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        Divider(
                            height: 1,
                            thickness: 0.5,
                            indent: 16,
                            endIndent: 16,
                            color: brand.divider),

                        // Note row
                        Padding(
                          padding:
                              const EdgeInsets.fromLTRB(16, 4, 16, 4),
                          child: Row(
                            children: [
                              Icon(CupertinoIcons.pencil,
                                  color: brand.inkSoft, size: 16),
                              const SizedBox(width: 8),
                              Expanded(
                                child: TextField(
                                  controller: _notesCtrl,
                                  textCapitalization:
                                      TextCapitalization.sentences,
                                  style: TextStyle(
                                      color: brand.ink, fontSize: 14),
                                  decoration: InputDecoration(
                                    border: InputBorder.none,
                                    hintText: '${context.t('expense.note')} (optional)',
                                    hintStyle: TextStyle(
                                        color: brand.inkSoft,
                                        fontSize: 14),
                                  ),
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

          // ── Bottom save bar ──────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 12,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: EdgeInsets.fromLTRB(
                16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
            child: Row(
              children: [
                // Category badge (decorative)
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: catMeta.color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(catMeta.icon,
                      color: catMeta.color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CupertinoButton(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    color: const Color(0xFF5A4AAB),
                    borderRadius: BorderRadius.circular(16),
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const CupertinoActivityIndicator(
                            color: Colors.white)
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(CupertinoIcons.checkmark_alt,
                                  color: Colors.white, size: 18),
                              SizedBox(width: 8),
                              Text(
                                'Save entry',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
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

// ── Category icon widget ──────────────────────────────────────────────────────

class _CategoryIcon extends StatelessWidget {
  final _CatMeta cat;
  final bool isSelected;
  const _CategoryIcon({required this.cat, required this.isSelected});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: isSelected
                  ? cat.color
                  : cat.color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: isSelected
                  ? Border.all(color: Colors.white, width: 2)
                  : null,
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: cat.color.withValues(alpha: 0.4),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      )
                    ]
                  : null,
            ),
            child: Icon(
              cat.icon,
              color: isSelected ? Colors.white : cat.color,
              size: 24,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            cat.label,
            style: TextStyle(
              color: isSelected
                  ? const Color(0xFF2D1A72)
                  : const Color(0xFF8E7DD4),
              fontSize: 11,
              fontWeight:
                  isSelected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Detail row ────────────────────────────────────────────────────────────────

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
  final BrandColors brand;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.brand,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, color: brand.inkSoft, size: 16),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      color: brand.ink,
                      fontSize: 14,
                      fontWeight: FontWeight.w500)),
            ),
            Text(value,
                style: TextStyle(color: brand.inkSoft, fontSize: 14)),
            const SizedBox(width: 4),
            if (onTap != null)
              Icon(CupertinoIcons.chevron_right,
                  color: brand.inkSoft, size: 14),
          ],
        ),
      ),
    );
  }
}

// ── Member chip ───────────────────────────────────────────────────────────────

class _MemberChip extends StatelessWidget {
  final BrandColors brand;
  final String name;
  final bool selected;
  final bool checkmark;

  const _MemberChip({
    required this.brand,
    required this.name,
    required this.selected,
    this.checkmark = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: selected
            ? AppActionBlue.color.withValues(alpha: 0.15)
            : brand.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: selected
              ? AppActionBlue.color.withValues(alpha: 0.5)
              : brand.divider.withValues(alpha: 0.4),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (checkmark && selected) ...[
            const Icon(CupertinoIcons.checkmark,
                color: AppActionBlue.color, size: 13),
            const SizedBox(width: 4),
          ],
          Text(
            name,
            style: TextStyle(
              color: selected ? AppActionBlue.color : brand.ink,
              fontSize: 14,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
