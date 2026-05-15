import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/travel_expense.dart';
import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

class AddTravelExpenseScreen extends ConsumerStatefulWidget {
  final TravelGroup group;
  final List<TravelGroupMember> members;
  final TravelExpense? expense;

  const AddTravelExpenseScreen({
    super.key,
    required this.group,
    required this.members,
    this.expense,
  });

  @override
  ConsumerState<AddTravelExpenseScreen> createState() =>
      _AddTravelExpenseScreenState();
}

class _AddTravelExpenseScreenState
    extends ConsumerState<AddTravelExpenseScreen> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();

  late String _paidByMemberId;
  late Set<String> _splitAmong;
  late DateTime _date;
  String _category = 'food';
  bool _saving = false;

  bool get _isEdit => widget.expense != null;

  static const _categories = [
    'food',
    'transport',
    'accommodation',
    'activities',
    'shopping',
    'general',
  ];

  static const _categoryIcons = <String, IconData>{
    'food': CupertinoIcons.cart_fill,
    'transport': CupertinoIcons.car_fill,
    'accommodation': CupertinoIcons.house_fill,
    'activities': CupertinoIcons.star_fill,
    'shopping': CupertinoIcons.bag_fill,
    'general': CupertinoIcons.square_grid_2x2_fill,
  };

  @override
  void initState() {
    super.initState();
    final memberIds = widget.members.map((m) => m.id).toList();

    if (_isEdit) {
      final e = widget.expense!;
      _amountCtrl.text = e.amount.toStringAsFixed(2);
      _descCtrl.text = e.description;
      _notesCtrl.text = e.notes ?? '';
      _paidByMemberId = e.paidByMemberId;
      _splitAmong = Set<String>.from(e.splitAmong);
      _date = e.date;
      _category = e.category;
    } else {
      _paidByMemberId = memberIds.isNotEmpty ? memberIds.first : '';
      _splitAmong = Set<String>.from(memberIds);
      _date = DateTime.now();
    }
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showCupertinoModalPopup<DateTime?>(
      context: context,
      builder: (ctx) => _DatePickerSheet(initial: _date),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final amountStr = _amountCtrl.text.trim().replaceAll(',', '.');
    final amount = double.tryParse(amountStr);
    final desc = _descCtrl.text.trim();

    if (amount == null || amount <= 0) {
      AppToast.show(
        context,
        context.t('validation.enterAmount'),
        type: AppToastType.error,
      );
      return;
    }
    if (_paidByMemberId.isEmpty) {
      AppToast.show(
        context,
        context.t('travel.saveFailed'),
        type: AppToastType.error,
      );
      return;
    }
    if (_splitAmong.isEmpty) {
      AppToast.show(
        context,
        context.t('travel.selectMembers'),
        type: AppToastType.error,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final user = ref.read(authStateProvider).valueOrNull;
      final svc = ref.read(travelGroupServiceProvider);

      if (_isEdit) {
        final updated = widget.expense!.copyWith(
          amount: amount,
          description: desc,
          category: _category,
          date: _date,
          paidByMemberId: _paidByMemberId,
          splitAmong: _splitAmong.toList(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
          updatedAt: DateTime.now(),
        );
        await svc.updateExpense(widget.group.id, updated);
        if (mounted) {
          AppToast.show(
            context,
            context.t('travel.expenseUpdated'),
            type: AppToastType.success,
            icon: CupertinoIcons.checkmark_circle_fill,
          );
          Navigator.pop(context);
        }
      } else {
        await svc.addExpense(
          groupId: widget.group.id,
          addedByUserId: user?.uid ?? '',
          amount: amount,
          description: desc,
          category: _category,
          date: _date,
          paidByMemberId: _paidByMemberId,
          splitAmong: _splitAmong.toList(),
          notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        );
        if (mounted) {
          AppToast.show(
            context,
            context.t('travel.expenseAdded'),
            type: AppToastType.success,
            icon: CupertinoIcons.checkmark_circle_fill,
          );
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          context.t('travel.saveFailed'),
          type: AppToastType.error,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final dateFormat = DateFormat('MMM d, yyyy');

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _isEdit
              ? context.t('travel.editExpense')
              : context.t('travel.addExpense'),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: CupertinoActivityIndicator(),
            )
          else
            TextButton(
              onPressed: _save,
              child: Text(
                context.t('common.save'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                  color: Color(0xFF3478F6),
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            // Amount
            _SectionLabel(context.t('travel.fieldAmount').toUpperCase()),
            _InputCard(
              child: Row(
                children: [
                  Text(
                    widget.group.currency,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: brand.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      autofocus: !_isEdit,
                      decoration: InputDecoration(
                        hintText: '0.00',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: brand.inkSoft),
                      ),
                      style: TextStyle(
                        color: brand.ink,
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Description
            _SectionLabel(context.t('travel.fieldDescription').toUpperCase()),
            _InputCard(
              child: TextField(
                controller: _descCtrl,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: context.t('travel.fieldDescription'),
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: brand.inkSoft),
                ),
                style: TextStyle(color: brand.ink, fontSize: 16),
              ),
            ),

            const SizedBox(height: 20),

            // Category
            _SectionLabel(context.t('travel.fieldCategory').toUpperCase()),
            SizedBox(
              height: 64,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _categories.length,
                separatorBuilder: (context2, i2) => const SizedBox(width: 10),
                itemBuilder: (ctx, i) {
                  final cat = _categories[i];
                  final selected = _category == cat;
                  return GestureDetector(
                    onTap: () => setState(() => _category = cat),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFF3478F6)
                            : brand.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _categoryIcons[cat] ??
                                CupertinoIcons.circle_grid_hex,
                            size: 18,
                            color: selected ? Colors.white : brand.inkSoft,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            cat,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color:
                                  selected ? Colors.white : brand.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // Date
            _SectionLabel(context.t('travel.fieldDate').toUpperCase()),
            _Tile(
              label: context.t('travel.fieldDate'),
              trailing: dateFormat.format(_date),
              trailingColor: const Color(0xFF3478F6),
              onTap: _pickDate,
              brand: brand,
            ),

            const SizedBox(height: 20),

            // Paid By
            _SectionLabel(context.t('travel.fieldPaidBy').toUpperCase()),
            Container(
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: widget.members.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final m = entry.value;
                  final selected = m.id == _paidByMemberId;
                  return Column(
                    children: [
                      InkWell(
                        onTap: () =>
                            setState(() => _paidByMemberId = m.id),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  m.name,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: brand.ink,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                              if (selected)
                                const Icon(
                                  CupertinoIcons.checkmark_circle_fill,
                                  color: Color(0xFF3478F6),
                                  size: 22,
                                )
                              else
                                Icon(
                                  CupertinoIcons.circle,
                                  color: brand.inkSoft,
                                  size: 22,
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (idx < widget.members.length - 1)
                        Divider(
                          height: 1,
                          color: brand.divider,
                          indent: 16,
                          endIndent: 16,
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 20),

            // Split Among
            _SectionLabel(context.t('travel.fieldSplitAmong').toUpperCase()),
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: widget.members.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final m = entry.value;
                        final checked = _splitAmong.contains(m.id);
                        return Column(
                          children: [
                            InkWell(
                              onTap: () {
                                setState(() {
                                  if (checked) {
                                    _splitAmong.remove(m.id);
                                  } else {
                                    _splitAmong.add(m.id);
                                  }
                                });
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            m.name,
                                            style: TextStyle(
                                              fontSize: 16,
                                              color: brand.ink,
                                            ),
                                          ),
                                          if (checked &&
                                              _splitAmong.isNotEmpty)
                                            Builder(builder: (ctx) {
                                              final amt = double.tryParse(
                                                      _amountCtrl.text
                                                          .trim()
                                                          .replaceAll(',', '.')) ??
                                                  0;
                                              final share = amt /
                                                  _splitAmong.length;
                                              return Text(
                                                '${widget.group.currency} ${share.toStringAsFixed(2)} ${context.t('travel.perPerson')}',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  color: brand.inkSoft,
                                                ),
                                              );
                                            }),
                                        ],
                                      ),
                                    ),
                                    Checkbox(
                                      value: checked,
                                      onChanged: (v) {
                                        setState(() {
                                          if (v == true) {
                                            _splitAmong.add(m.id);
                                          } else {
                                            _splitAmong.remove(m.id);
                                          }
                                        });
                                      },
                                      activeColor: const Color(0xFF3478F6),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            if (idx < widget.members.length - 1)
                              Divider(
                                height: 1,
                                color: brand.divider,
                                indent: 16,
                                endIndent: 16,
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Notes
            _SectionLabel(context.t('travel.fieldNotes').toUpperCase()),
            _InputCard(
              child: TextField(
                controller: _notesCtrl,
                textCapitalization: TextCapitalization.sentences,
                maxLines: 3,
                minLines: 2,
                decoration: InputDecoration(
                  hintText: context.t('travel.fieldNotes'),
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: brand.inkSoft),
                ),
                style: TextStyle(color: brand.ink, fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8E8E93),
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _InputCard extends StatelessWidget {
  final Widget child;
  const _InputCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: child,
    );
  }
}

class _Tile extends StatelessWidget {
  final String label;
  final String trailing;
  final Color trailingColor;
  final VoidCallback onTap;
  final BrandColors brand;

  const _Tile({
    required this.label,
    required this.trailing,
    required this.trailingColor,
    required this.onTap,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: TextStyle(fontSize: 16, color: brand.ink)),
            Text(
              trailing,
              style: TextStyle(
                fontSize: 16,
                color: trailingColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePickerSheet extends StatefulWidget {
  final DateTime initial;
  const _DatePickerSheet({required this.initial});

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late DateTime _picked;

  @override
  void initState() {
    super.initState();
    _picked = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      height: 320,
      color: brand.surface,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CupertinoButton(
                child: Text(
                  context.t('common.cancel'),
                  style: const TextStyle(color: Color(0xFF8E8E93)),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              CupertinoButton(
                child: Text(context.t('common.done')),
                onPressed: () => Navigator.pop(context, _picked),
              ),
            ],
          ),
          Expanded(
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.date,
              initialDateTime: _picked,
              maximumDate: DateTime.now().add(const Duration(days: 365)),
              onDateTimeChanged: (dt) => setState(() => _picked = dt),
            ),
          ),
        ],
      ),
    );
  }
}
