import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../screens/expenses/add_edit_expense_screen.dart'
    show kExpenseCategories;
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

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
        notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final members = widget.group.members;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '';

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Icon(CupertinoIcons.xmark, color: AppActionBlue.color, size: 20),
        ),
        title: Text(
          _isEdit
              ? context.t('common.edit')
              : context.t('group.addExpense'),
          style: TextStyle(
            color: brand.ink,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.only(right: 16),
            onPressed: _saving ? null : _save,
            child: _saving
                ? const CupertinoActivityIndicator()
                : Text(
                    _isEdit
                        ? context.t('common.update')
                        : context.t('common.save'),
                    style: const TextStyle(
                      color: AppActionBlue.color,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
          children: [
            // Amount + Description
            _Card(
              brand: brand,
              children: [
                _Field(
                  brand: brand,
                  label: context.t('expense.amount'),
                  child: Row(
                    children: [
                      Text(symbol,
                          style: TextStyle(
                            color: brand.ink,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          )),
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _amountCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: TextStyle(color: brand.ink, fontSize: 16),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            hintText: '0.00',
                            hintStyle: TextStyle(color: brand.inkSoft),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                _divider(brand),
                _Field(
                  brand: brand,
                  label: context.t('travel.fieldDescription'),
                  child: TextField(
                    controller: _descCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(color: brand.ink, fontSize: 16),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'e.g. Dinner, Uber',
                      hintStyle: TextStyle(color: brand.inkSoft),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Category + Date
            _Card(
              brand: brand,
              children: [
                _PickerRow(
                  brand: brand,
                  label: context.t('expense.category'),
                  value: _category,
                  onTap: () => _pickCategory(context, brand),
                ),
                _divider(brand),
                _PickerRow(
                  brand: brand,
                  label: context.t('expense.date'),
                  value: DateFormat('MMM d, yyyy').format(_date),
                  onTap: () => _pickDate(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Paid by
            _Card(
              brand: brand,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t('group.paidBy'),
                        style: TextStyle(
                          color: brand.inkSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: members.map((m) {
                          final selected = m.uid == _paidByUid;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _paidByUid = m.uid),
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
              ],
            ),
            const SizedBox(height: 12),

            // Split between
            _Card(
              brand: brand,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            context.t('group.splitBetween'),
                            style: TextStyle(
                              color: brand.inkSoft,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => setState(() => _splitBetween =
                                widget.group.memberUids.toSet()),
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
                          final selected = _splitBetween.contains(m.uid);
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
              ],
            ),
            const SizedBox(height: 12),

            // Notes
            _Card(
              brand: brand,
              children: [
                _Field(
                  brand: brand,
                  label: context.t('expense.note'),
                  child: TextField(
                    controller: _notesCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    style: TextStyle(color: brand.ink, fontSize: 16),
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Optional',
                      hintStyle: TextStyle(color: brand.inkSoft),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _splitSummary(String symbol) {
    final amt = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amt <= 0 || _splitBetween.isEmpty) return '';
    final perPerson = amt / _splitBetween.length;
    return '$symbol${perPerson.toStringAsFixed(2)} per person';
  }

  Widget _divider(BrandColors brand) => Divider(
        height: 1,
        thickness: 0.5,
        indent: 16,
        endIndent: 16,
        color: brand.divider,
      );

  void _pickCategory(BuildContext context, BrandColors brand) {
    showModalBottomSheet(
      context: context,
      backgroundColor: brand.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: brand.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          ...kExpenseCategories.map(
            (cat) => ListTile(
              title: Text(cat,
                  style: TextStyle(color: brand.ink, fontSize: 16)),
              trailing: _category == cat
                  ? Icon(CupertinoIcons.checkmark,
                      color: AppActionBlue.color, size: 18)
                  : null,
              onTap: () {
                setState(() => _category = cat);
                Navigator.pop(context);
              },
            ),
          ),
        ],
      ),
    );
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
}

class _Card extends StatelessWidget {
  final BrandColors brand;
  final List<Widget> children;

  const _Card({required this.brand, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final BrandColors brand;
  final String label;
  final Widget child;

  const _Field({required this.brand, required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: brand.inkSoft,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          child,
        ],
      ),
    );
  }
}

class _PickerRow extends StatelessWidget {
  final BrandColors brand;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _PickerRow({
    required this.brand,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(label,
                  style: TextStyle(color: brand.ink, fontSize: 16)),
            ),
            Text(value,
                style: TextStyle(
                    color: brand.inkSoft, fontSize: 16)),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right,
                color: brand.inkSoft, size: 16),
          ],
        ),
      ),
    );
  }
}

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
              color:
                  selected ? AppActionBlue.color : brand.ink,
              fontSize: 14,
              fontWeight:
                  selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
