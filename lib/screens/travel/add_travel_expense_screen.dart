import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/travel_expense.dart';
import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../widgets/app_toast.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _blue = Color(0xFF0066CC);
const _hairline = Color(0xFFE0E0E0);
const _parchment = Color(0xFFF5F5F7);
const _inkColor = Color(0xFF1D1D1F);
const _ink48 = Color(0xFF7A7A7A);

TextStyle _display(double size,
        {double tracking = -0.374, double lh = 1.10, Color? color}) =>
    TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: tracking,
        height: lh,
        color: color ?? _inkColor);

TextStyle _body(double size,
        {FontWeight weight = FontWeight.w400, Color? color}) =>
    TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? _inkColor,
        height: 1.4);

TextStyle _eyebrow({Color? color}) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: color ?? _ink48,
    );

// ── Screen ────────────────────────────────────────────────────────────────────

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
    'food', 'transport', 'accommodation', 'activities', 'shopping', 'general',
  ];

  static const _categoryIcons = <String, IconData>{
    'food': CupertinoIcons.cart_fill,
    'transport': CupertinoIcons.car_fill,
    'accommodation': CupertinoIcons.house_fill,
    'activities': CupertinoIcons.star_fill,
    'shopping': CupertinoIcons.bag_fill,
    'general': CupertinoIcons.square_grid_2x2_fill,
  };

  static const _categoryColors = <String, Color>{
    'food': Color(0xFFFF9500),
    'transport': Color(0xFF3478F6),
    'accommodation': Color(0xFF5856D6),
    'activities': Color(0xFFFF2D55),
    'shopping': Color(0xFF34C759),
    'general': Color(0xFF8E8E93),
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
      AppToast.show(context, context.t('validation.enterAmount'),
          type: AppToastType.error);
      return;
    }
    if (_paidByMemberId.isEmpty) {
      AppToast.show(context, context.t('travel.saveFailed'),
          type: AppToastType.error);
      return;
    }
    if (_splitAmong.isEmpty) {
      AppToast.show(context, context.t('travel.selectMembers'),
          type: AppToastType.error);
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
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
          updatedAt: DateTime.now(),
        );
        await svc.updateExpense(widget.group.id, updated);
        if (mounted) {
          AppToast.show(context, context.t('travel.expenseUpdated'),
              type: AppToastType.success,
              icon: CupertinoIcons.checkmark_circle_fill);
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
          notes: _notesCtrl.text.trim().isEmpty
              ? null
              : _notesCtrl.text.trim(),
        );
        if (mounted) {
          AppToast.show(context, context.t('travel.expenseAdded'),
              type: AppToastType.success,
              icon: CupertinoIcons.checkmark_circle_fill);
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, context.t('travel.saveFailed'),
            type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : _parchment;
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;
    final dateFormat = DateFormat('MMM d, yyyy');

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text(
                      context.t('common.cancel'),
                      style: _body(17, color: _ink48),
                    ),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _isEdit
                            ? context.t('travel.editExpense')
                            : context.t('travel.addExpense'),
                        style: _body(17, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: _saving
                        ? const CupertinoActivityIndicator()
                        : Text(
                            context.t('common.save'),
                            style: _body(17,
                                weight: FontWeight.w600,
                                color: _blue),
                          ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // ── Amount hero ───────────────────────────────────────────────
            Container(
              color: surface,
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text(
                        widget.group.currency,
                        style: _display(22,
                            tracking: -0.4, color: _ink48),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _amountCtrl,
                          keyboardType:
                              const TextInputType.numberWithOptions(
                                  decimal: true),
                          autofocus: !_isEdit,
                          decoration: InputDecoration(
                            hintText: '0.00',
                            border: InputBorder.none,
                            hintStyle:
                                _display(40, tracking: -1.0, color: _ink48),
                          ),
                          style: _display(40, tracking: -1.0),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),
                  Divider(color: border, height: 1),
                  const SizedBox(height: 12),

                  // Description row
                  TextField(
                    controller: _descCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: context.t('travel.fieldDescription'),
                      border: InputBorder.none,
                      hintStyle: _body(17, color: _ink48),
                    ),
                    style: _body(17),
                  ),
                ],
              ),
            ),

            // ── Form sections ─────────────────────────────────────────────
            Expanded(
              child: ListView(
                padding:
                    const EdgeInsets.fromLTRB(20, 16, 20, 40),
                children: [
                  // Category
                  _EyebrowLabel(context.t('travel.fieldCategory')),
                  SizedBox(
                    height: 68,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _categories.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final cat = _categories[i];
                        final selected = _category == cat;
                        final catColor = _categoryColors[cat] ??
                            const Color(0xFF8E8E93);
                        return GestureDetector(
                          onTap: () =>
                              setState(() => _category = cat),
                          child: AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: selected
                                  ? _blue
                                  : surface,
                              borderRadius:
                                  BorderRadius.circular(13),
                              border: Border.all(
                                color: selected
                                    ? _blue
                                    : border,
                                width: 0.5,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _categoryIcons[cat] ??
                                      CupertinoIcons
                                          .square_grid_2x2_fill,
                                  size: 18,
                                  color: selected
                                      ? Colors.white
                                      : catColor,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  cat,
                                  style: _eyebrow(
                                      color: selected
                                          ? Colors.white
                                          : _ink48),
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
                  _EyebrowLabel(context.t('travel.fieldDate')),
                  _FormCard(
                    isDark: isDark,
                    child: _FormRow(
                      label: context.t('travel.fieldDate'),
                      value: dateFormat.format(_date),
                      valueColor: _blue,
                      onTap: _pickDate,
                      border: border,
                      isLast: true,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Paid By
                  _EyebrowLabel(context.t('travel.fieldPaidBy')),
                  _FormCard(
                    isDark: isDark,
                    child: Column(
                      children: widget.members.asMap().entries.map((e) {
                        final idx = e.key;
                        final m = e.value;
                        final selected = m.id == _paidByMemberId;
                        final isLast =
                            idx == widget.members.length - 1;
                        return _SelectRow(
                          label: m.name,
                          selected: selected,
                          isLast: isLast,
                          border: border,
                          onTap: () =>
                              setState(() => _paidByMemberId = m.id),
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Split Among
                  _EyebrowLabel(context.t('travel.fieldSplitAmong')),
                  _FormCard(
                    isDark: isDark,
                    child: Column(
                      children: widget.members.asMap().entries.map((e) {
                        final idx = e.key;
                        final m = e.value;
                        final checked = _splitAmong.contains(m.id);
                        final isLast =
                            idx == widget.members.length - 1;

                        double? share;
                        if (checked && _splitAmong.isNotEmpty) {
                          final amt = double.tryParse(_amountCtrl.text
                                  .trim()
                                  .replaceAll(',', '.')) ??
                              0;
                          share = amt / _splitAmong.length;
                        }

                        return _CheckRow(
                          label: m.name,
                          sublabel: share != null && share > 0
                              ? '${widget.group.currency} ${share.toStringAsFixed(2)} ${context.t('travel.perPerson')}'
                              : null,
                          checked: checked,
                          isLast: isLast,
                          border: border,
                          onToggle: () {
                            setState(() {
                              if (checked) {
                                _splitAmong.remove(m.id);
                              } else {
                                _splitAmong.add(m.id);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Notes (optional)
                  _EyebrowLabel(context.t('travel.fieldNotes')),
                  _FormCard(
                    isDark: isDark,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                      child: TextField(
                        controller: _notesCtrl,
                        textCapitalization:
                            TextCapitalization.sentences,
                        maxLines: 3,
                        minLines: 2,
                        decoration: InputDecoration(
                          hintText: context.t('travel.fieldNotes'),
                          border: InputBorder.none,
                          hintStyle: _body(15, color: _ink48),
                        ),
                        style: _body(15),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // Save pill
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      width: double.infinity,
                      padding:
                          const EdgeInsets.symmetric(vertical: 16),
                      decoration: BoxDecoration(
                        color: _saving
                            ? _blue.withValues(alpha: 0.5)
                            : _blue,
                        borderRadius:
                            BorderRadius.circular(9999),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            CupertinoIcons.checkmark_circle_fill,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _isEdit
                                ? context.t('common.save')
                                : context.t('travel.addExpense'),
                            style: _body(16,
                                weight: FontWeight.w600,
                                color: Colors.white),
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
      ),
    );
  }
}

// ── Form helpers ──────────────────────────────────────────────────────────────

class _EyebrowLabel extends StatelessWidget {
  final String text;
  const _EyebrowLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(text.toUpperCase(), style: _eyebrow()),
    );
  }
}

class _FormCard extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _FormCard({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: child,
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  final VoidCallback onTap;
  final Color border;
  final bool isLast;

  const _FormRow({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.onTap,
    required this.border,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(child: Text(label, style: _body(16))),
                Text(value,
                    style: _body(16,
                        weight: FontWeight.w500,
                        color: valueColor)),
                const SizedBox(width: 4),
                const Icon(CupertinoIcons.chevron_forward,
                    size: 14, color: _ink48),
              ],
            ),
          ),
        ),
        if (!isLast) Divider(height: 1, color: border, indent: 16),
      ],
    );
  }
}

class _SelectRow extends StatelessWidget {
  final String label;
  final bool selected;
  final bool isLast;
  final Color border;
  final VoidCallback onTap;

  const _SelectRow({
    required this.label,
    required this.selected,
    required this.isLast,
    required this.border,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: _body(16,
                        weight: selected
                            ? FontWeight.w600
                            : FontWeight.w400),
                  ),
                ),
                if (selected)
                  const Icon(CupertinoIcons.checkmark_circle_fill,
                      color: _blue, size: 22)
                else
                  const Icon(CupertinoIcons.circle,
                      color: _ink48, size: 22),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: border, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final String? sublabel;
  final bool checked;
  final bool isLast;
  final Color border;
  final VoidCallback onToggle;

  const _CheckRow({
    required this.label,
    this.sublabel,
    required this.checked,
    required this.isLast,
    required this.border,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        GestureDetector(
          onTap: onToggle,
          child: Container(
            color: Colors.transparent,
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: _body(16)),
                      if (sublabel != null)
                        Text(sublabel!,
                            style: _body(12, color: _ink48)),
                    ],
                  ),
                ),
                Checkbox(
                  value: checked,
                  onChanged: (_) => onToggle(),
                  activeColor: _blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  materialTapTargetSize:
                      MaterialTapTargetSize.shrinkWrap,
                ),
              ],
            ),
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: border, indent: 16, endIndent: 16),
      ],
    );
  }
}

// ── Date picker ───────────────────────────────────────────────────────────────

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;

    return Container(
      height: 320,
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: border, width: 0.5)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                CupertinoButton(
                  child: Text(context.t('common.cancel'),
                      style: _body(17, color: _ink48)),
                  onPressed: () => Navigator.pop(context),
                ),
                CupertinoButton(
                  child: Text(context.t('common.done'),
                      style: _body(17,
                          weight: FontWeight.w600, color: _blue)),
                  onPressed: () => Navigator.pop(context, _picked),
                ),
              ],
            ),
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
