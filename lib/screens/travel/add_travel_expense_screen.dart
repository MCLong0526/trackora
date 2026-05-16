import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/travel_expense.dart';
import '../../models/travel_group.dart';
import '../../services/exchange_rate_service.dart';
import '../../services/i18n.dart';
import '../../services/prefs_service.dart';
import '../../state/providers.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/currency_picker.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _blue = Color(0xFF0066CC);
const _hairline = Color(0xFFE0E0E0);
const _parchment = Color(0xFFF5F5F7);
const _inkColor = Color(0xFF1D1D1F);
const _ink48 = Color(0xFF7A7A7A);

TextStyle _display(double sz, {double tracking = -0.374, double lh = 1.10, Color? color}) =>
    TextStyle(fontSize: sz, fontWeight: FontWeight.w600, letterSpacing: tracking, height: lh, color: color ?? _inkColor);

TextStyle _body(double sz, {FontWeight weight = FontWeight.w400, Color? color}) =>
    TextStyle(fontSize: sz, fontWeight: weight, color: color ?? _inkColor, height: 1.4);

TextStyle _eyebrow({Color? color}) =>
    TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: color ?? _ink48);

// ── Split mode ────────────────────────────────────────────────────────────────

enum _SplitMode { equally, amount, percent, shares }

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

  late String _paidByMemberId;
  late Set<String> _splitAmong;
  _SplitMode _splitMode = _SplitMode.equally;
  final Map<String, TextEditingController> _customCtrls = {};
  late DateTime _date;
  String _category = 'food';
  bool _saving = false;
  late String _currencyCode;

  bool get _isEdit => widget.expense != null;

  static const _categories = [
    'food', 'transport', 'accommodation', 'activities', 'shopping', 'general',
  ];

  static const _catIcons = <String, IconData>{
    'food': CupertinoIcons.cart_fill,
    'transport': CupertinoIcons.car_fill,
    'accommodation': CupertinoIcons.house_fill,
    'activities': CupertinoIcons.star_fill,
    'shopping': CupertinoIcons.bag_fill,
    'general': CupertinoIcons.square_grid_2x2_fill,
  };

  static const _catColors = <String, Color>{
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
    // Init custom controllers
    for (final m in widget.members) {
      _customCtrls[m.id] = TextEditingController();
    }

    _currencyCode = widget.group.currency;

    if (_isEdit) {
      final e = widget.expense!;
      _amountCtrl.text = e.amount.toStringAsFixed(2);
      _descCtrl.text = e.description;
      _paidByMemberId = e.paidByMemberId;
      _splitAmong = Set<String>.from(e.splitAmong);
      _date = e.date;
      _category = e.category;
      _currencyCode = e.currencyCode ?? widget.group.currency;
      // Restore split mode + custom field values from saved data
      if (e.splitAmounts != null && e.splitAmounts!.isNotEmpty) {
        final mode = _SplitMode.values.firstWhere(
          (m) => m.name == (e.splitMode ?? 'amount'),
          orElse: () => _SplitMode.amount,
        );
        _splitMode = mode;
        for (final entry in e.splitAmounts!.entries) {
          final ctrl = _customCtrls[entry.key];
          if (ctrl == null) continue;
          switch (mode) {
            case _SplitMode.percent:
              final pct = e.amount > 0 ? (entry.value / e.amount * 100) : 0.0;
              ctrl.text = pct.toStringAsFixed(1);
            case _SplitMode.shares:
              // Use raw amounts as share units (proportional, not absolute)
              ctrl.text = entry.value.toStringAsFixed(2);
            case _SplitMode.amount:
              ctrl.text = entry.value.toStringAsFixed(2);
            case _SplitMode.equally:
              break;
          }
        }
      }
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
    for (final c in _customCtrls.values) { c.dispose(); }
    super.dispose();
  }

  double get _parsedAmount =>
      double.tryParse(_amountCtrl.text.trim().replaceAll(',', '.')) ?? 0;

  void _onCustomFieldChanged(String memberId, String value) {
    setState(() {});
    if (_splitAmong.length != 2) return;

    final other = _splitAmong.firstWhere((id) => id != memberId, orElse: () => '');
    if (other.isEmpty) return;

    switch (_splitMode) {
      case _SplitMode.percent:
        final entered = double.tryParse(value) ?? 0;
        final remainder = (100.0 - entered).clamp(0.0, 100.0);
        _customCtrls[other]?.text = remainder.toStringAsFixed(1);
      case _SplitMode.amount:
        final entered = double.tryParse(value) ?? 0;
        final remainder = (_parsedAmount - entered).clamp(0.0, _parsedAmount);
        _customCtrls[other]?.text = remainder.toStringAsFixed(2);
      case _SplitMode.shares:
      case _SplitMode.equally:
        break;
    }
  }

  double _shareFor(String memberId) {
    if (_splitAmong.isEmpty) return 0;
    switch (_splitMode) {
      case _SplitMode.equally:
        return _parsedAmount / _splitAmong.length;
      case _SplitMode.amount:
        return double.tryParse(_customCtrls[memberId]?.text.trim() ?? '') ?? 0;
      case _SplitMode.percent:
        final pct = double.tryParse(_customCtrls[memberId]?.text.trim() ?? '') ?? 0;
        return _parsedAmount * pct / 100;
      case _SplitMode.shares:
        final myShares = double.tryParse(_customCtrls[memberId]?.text.trim() ?? '') ?? 0;
        final totalShares = _splitAmong.fold(0.0, (sum, id) =>
            sum + (double.tryParse(_customCtrls[id]?.text.trim() ?? '') ?? 0));
        return totalShares > 0 ? _parsedAmount * myShares / totalShares : 0;
    }
  }

  Future<void> _pickDate() async {
    final picked = await showCupertinoModalPopup<DateTime?>(
      context: context,
      builder: (ctx) => _DatePickerSheet(initial: _date),
    );
    if (picked != null) setState(() => _date = picked);
  }

  void _showCategoryPicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? const Color(0xFF2C2C2E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE0E0E0),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Text('Category', style: _display(18, tracking: -0.3)),
                  const SizedBox(height: 16),
                  GridView.count(
                    crossAxisCount: 3,
                    shrinkWrap: true,
                    mainAxisSpacing: 10,
                    crossAxisSpacing: 10,
                    childAspectRatio: 1.4,
                    children: _categories.map((cat) {
                      final selected = cat == _category;
                      final color = _catColors[cat] ?? const Color(0xFF8E8E93);
                      return GestureDetector(
                        onTap: () {
                          setState(() => _category = cat);
                          Navigator.pop(ctx);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected ? _blue : color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _catIcons[cat] ?? CupertinoIcons.square_grid_2x2_fill,
                                color: selected ? Colors.white : color,
                                size: 22,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                cat[0].toUpperCase() + cat.substring(1),
                                style: TextStyle(
                                  fontSize: 11, fontWeight: FontWeight.w600,
                                  color: selected ? Colors.white : color,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final amount = _parsedAmount;
    final desc = _descCtrl.text.trim();

    if (amount <= 0) {
      AppToast.show(context, context.t('validation.enterAmount'),
          type: AppToastType.error);
      return;
    }
    if (_paidByMemberId.isEmpty) {
      AppToast.show(context, context.t('travel.saveFailed'), type: AppToastType.error);
      return;
    }
    if (_splitAmong.isEmpty) {
      AppToast.show(context, context.t('travel.selectMembers'), type: AppToastType.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final user = ref.read(authStateProvider).valueOrNull;
      final svc = ref.read(travelGroupServiceProvider);

      // Resolve currency fields
      final groupCurrency = widget.group.currency;
      final String? currencyCodeField =
          _currencyCode != groupCurrency ? _currencyCode : null;
      double? fxRate;
      if (currencyCodeField != null) {
        fxRate = await ExchangeRateService().getRate(
          from: _currencyCode,
          to: groupCurrency,
          base: groupCurrency,
        );
      }

      // Build per-member amounts for non-equal splits
      final Map<String, double>? splitAmountsMap = _splitMode != _SplitMode.equally
          ? {for (final id in _splitAmong) id: _shareFor(id)}
          : null;
      final String? splitModeStr = _splitMode != _SplitMode.equally
          ? _splitMode.name
          : null;

      if (_isEdit) {
        final updated = widget.expense!.copyWith(
          amount: amount,
          description: desc,
          category: _category,
          date: _date,
          paidByMemberId: _paidByMemberId,
          splitAmong: _splitAmong.toList(),
          splitAmounts: splitAmountsMap,
          splitMode: splitModeStr,
          currencyCode: currencyCodeField,
          exchangeRate: fxRate,
          updatedAt: DateTime.now(),
        );
        await svc.updateExpense(widget.group.id, updated);
        if (mounted) {
          AppToast.show(context, context.t('travel.expenseUpdated'),
              type: AppToastType.success, icon: CupertinoIcons.checkmark_circle_fill);
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
          splitAmounts: splitAmountsMap,
          splitMode: splitModeStr,
          currencyCode: currencyCodeField,
          exchangeRate: fxRate,
        );
        if (mounted) {
          AppToast.show(context, context.t('travel.expenseAdded'),
              type: AppToastType.success, icon: CupertinoIcons.checkmark_circle_fill);
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) AppToast.show(context, context.t('travel.saveFailed'), type: AppToastType.error);
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
    final dateLabelFmt = DateFormat('MMM d');
    final now = DateTime.now();
    final isToday = DateFormat('yyyy-MM-dd').format(_date) == DateFormat('yyyy-MM-dd').format(now);
    final dateLabel = isToday ? 'Today, ${dateLabelFmt.format(_date)}' : dateLabelFmt.format(_date);
    final catDisplay = _category[0].toUpperCase() + _category.substring(1);
    final catColor = _catColors[_category] ?? const Color(0xFF8E8E93);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: bg,
        resizeToAvoidBottomInset: true,
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header ────────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Text(context.t('common.cancel'),
                          style: _body(17, color: _blue)),
                    ),
                    Expanded(
                      child: Column(
                        children: [
                          Text(
                            _isEdit
                                ? context.t('travel.editExpense')
                                : context.t('travel.addExpense'),
                            style: _body(17, weight: FontWeight.w600),
                          ),
                          Text(
                            widget.group.name,
                            style: _body(12, color: _blue),
                          ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _saving ? null : _save,
                      child: _saving
                          ? const CupertinoActivityIndicator()
                          : Text(context.t('common.save'),
                              style: _body(17, weight: FontWeight.w600, color: _blue)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // ── Scrollable form ───────────────────────────────────────────
              Expanded(
                child: ListView(
                  padding: EdgeInsets.fromLTRB(18, 0, 18,
                      40 + MediaQuery.viewInsetsOf(context).bottom),
                  children: [
                    // AMOUNT section
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text('AMOUNT', style: _eyebrow()),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: border, width: 0.5),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          GestureDetector(
                            onTap: () => showCurrencyPickerSheet(
                              context,
                              current: _currencyCode,
                              onPicked: (code) => setState(() => _currencyCode = code),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: _blue.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(_currencyCode,
                                  style: _display(16, tracking: -0.2, color: _blue)),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _amountCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              autofocus: !_isEdit,
                              cursorHeight: 36,
                              decoration: InputDecoration(
                                hintText: '0.00',
                                border: InputBorder.none,
                                hintStyle: _display(36, tracking: -1.0, color: _ink48),
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                              style: _display(36, tracking: -1.0),
                              onChanged: (_) => setState(() {}),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Builder(builder: (ctx) {
                      final groupCurrency = widget.group.currency;
                      final isForeign = _currencyCode != groupCurrency;
                      final converter = ref.watch(currencyConverterProvider).valueOrNull;
                      if (!isForeign || converter == null) return const SizedBox(height: 16);
                      final groupSym = kSupportedCurrencies[groupCurrency] ?? groupCurrency;
                      return ListenableBuilder(
                        listenable: _amountCtrl,
                        builder: (_, child) {
                          final amt = double.tryParse(_amountCtrl.text) ?? 0;
                          if (amt <= 0) return const SizedBox(height: 16);
                          final converted = amt * converter.crossRate(_currencyCode, groupCurrency);
                          return Padding(
                            padding: const EdgeInsets.only(top: 6, left: 4, bottom: 10),
                            child: Text(
                              'est. $groupSym ${converted.toStringAsFixed(2)}',
                              style: _body(13, color: _ink48),
                            ),
                          );
                        },
                      );
                    }),

                    // DESCRIPTION section
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text('DESCRIPTION', style: _eyebrow()),
                    ),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: border, width: 0.5),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _descCtrl,
                            textCapitalization: TextCapitalization.sentences,
                            decoration: InputDecoration(
                              hintText: context.t('travel.fieldDescription'),
                              border: InputBorder.none,
                              hintStyle: _body(16, color: _ink48),
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                            style: _body(16, weight: FontWeight.w500),
                          ),
                          const SizedBox(height: 8),
                          Divider(height: 1, color: border),
                          // Category + date info row
                          Row(
                            children: [
                              GestureDetector(
                                onTap: _showCategoryPicker,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 20, height: 20,
                                        decoration: BoxDecoration(
                                          color: catColor.withValues(alpha: 0.12),
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Icon(
                                          _catIcons[_category] ?? CupertinoIcons.square_grid_2x2_fill,
                                          color: catColor, size: 12,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Text(catDisplay, style: _body(13, color: _ink48)),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                child: Text('·', style: _body(13, color: _ink48)),
                              ),
                              GestureDetector(
                                onTap: _pickDate,
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  child: Text(dateLabel, style: _body(13, color: _ink48)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // PAID BY section
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 10),
                      child: Text('PAID BY', style: _eyebrow()),
                    ),
                    SizedBox(
                      height: 82,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: widget.members.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (_, i) {
                          final m = widget.members[i];
                          final selected = m.id == _paidByMemberId;
                          final avatarBg = _memberBgs[i % _memberBgs.length];
                          final initial = m.name.isNotEmpty ? m.name[0].toUpperCase() : '?';
                          return _Pressable(
                            onTap: () => setState(() => _paidByMemberId = m.id),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  curve: Curves.easeOutBack,
                                  width: 50, height: 50,
                                  decoration: BoxDecoration(
                                    color: selected ? _blue : avatarBg,
                                    shape: BoxShape.circle,
                                    border: selected
                                        ? Border.all(color: _blue, width: 2)
                                        : Border.all(color: border, width: 1),
                                  ),
                                  child: Center(
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        color: selected ? Colors.white : _inkColor,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 6),
                                AnimatedDefaultTextStyle(
                                  duration: const Duration(milliseconds: 200),
                                  style: _body(12,
                                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                                      color: selected ? _blue : _inkColor),
                                  child: Text(
                                    m.name.split(' ').first,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // SPLIT BETWEEN section
                    Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text('SPLIT BETWEEN', style: _eyebrow()),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () {
                            // Toggle: if all selected, deselect all (except payer), else select all
                            setState(() {
                              if (_splitAmong.length == widget.members.length) {
                                _splitAmong = {_paidByMemberId};
                              } else {
                                _splitAmong = widget.members.map((m) => m.id).toSet();
                              }
                            });
                          },
                          child: Text('Custom',
                              style: _body(13, color: _blue)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    // Split mode tabs
                    Container(
                      padding: const EdgeInsets.all(3),
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE8E8EA),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: _SplitMode.values.map((mode) {
                          final selected = mode == _splitMode;
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() {
                                _splitMode = mode;
                                // Reset custom fields when switching modes
                                if (mode != _SplitMode.equally) {
                                  final amt = _parsedAmount;
                                  final share = _splitAmong.isNotEmpty
                                      ? amt / _splitAmong.length : 0.0;
                                  for (final m in widget.members) {
                                    if (_splitAmong.contains(m.id)) {
                                      switch (mode) {
                                        case _SplitMode.amount:
                                          _customCtrls[m.id]?.text = share.toStringAsFixed(2);
                                        case _SplitMode.percent:
                                          _customCtrls[m.id]?.text = _splitAmong.isNotEmpty
                                              ? (100 / _splitAmong.length).toStringAsFixed(1) : '0';
                                        case _SplitMode.shares:
                                          _customCtrls[m.id]?.text = '1';
                                        case _SplitMode.equally:
                                          break;
                                      }
                                    } else {
                                      _customCtrls[m.id]?.clear();
                                    }
                                  }
                                }
                              }),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                padding: const EdgeInsets.symmetric(vertical: 7),
                                decoration: BoxDecoration(
                                  color: selected
                                      ? (isDark ? const Color(0xFF3A3A3C) : Colors.white)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                  boxShadow: selected
                                      ? [BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.07),
                                          blurRadius: 3, offset: const Offset(0, 1))]
                                      : null,
                                ),
                                child: Text(
                                  _splitModeLabel(mode),
                                  textAlign: TextAlign.center,
                                  style: _body(12,
                                      weight: selected ? FontWeight.w600 : FontWeight.w400,
                                      color: selected ? _inkColor : _ink48),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Split member list
                    Container(
                      decoration: BoxDecoration(
                        color: surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: border, width: 0.5),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(18),
                        child: Column(
                          children: widget.members.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final m = entry.value;
                            final checked = _splitAmong.contains(m.id);
                            final isLast = idx == widget.members.length - 1;
                            final initial = m.name.isNotEmpty ? m.name[0].toUpperCase() : '?';
                            final avatarBg = _memberBgs[idx % _memberBgs.length];
                            final share = checked ? _shareFor(m.id) : 0.0;
                            final shareLabel = checked && _parsedAmount > 0
                                ? '$_currencyCode ${share.toStringAsFixed(2)}'
                                : null;

                            return Column(
                              children: [
                                GestureDetector(
                                  onTap: _splitMode == _SplitMode.equally
                                      ? () => setState(() {
                                            if (checked) {
                                              _splitAmong.remove(m.id);
                                            } else {
                                              _splitAmong.add(m.id);
                                            }
                                          })
                                      : null,
                                  behavior: HitTestBehavior.opaque,
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                                    child: Row(
                                      children: [
                                        // Avatar
                                        Container(
                                          width: 36, height: 36,
                                          decoration: BoxDecoration(
                                            color: avatarBg, shape: BoxShape.circle,
                                          ),
                                          child: Center(
                                            child: Text(initial,
                                                style: _body(14, weight: FontWeight.w700)),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        // Name + YOU badge
                                        Expanded(
                                          child: Row(
                                            children: [
                                              Text(m.name,
                                                  style: _body(15, weight: FontWeight.w400)),
                                              // YOU badge if needed (check via name "You" or isMe flag)
                                            ],
                                          ),
                                        ),
                                        // Custom amount field or share label
                                        if (_splitMode == _SplitMode.equally) ...[
                                          if (shareLabel != null)
                                            Text(shareLabel,
                                                style: _body(14,
                                                    weight: FontWeight.w500,
                                                    color: _ink48)),
                                          const SizedBox(width: 10),
                                          SizedBox(
                                            width: 24, height: 24,
                                            child: Checkbox(
                                              value: checked,
                                              onChanged: (_) => setState(() {
                                                if (checked) {
                                                  _splitAmong.remove(m.id);
                                                } else {
                                                  _splitAmong.add(m.id);
                                                }
                                              }),
                                              activeColor: _blue,
                                              shape: RoundedRectangleBorder(
                                                  borderRadius: BorderRadius.circular(6)),
                                              materialTapTargetSize:
                                                  MaterialTapTargetSize.shrinkWrap,
                                            ),
                                          ),
                                        ] else ...[
                                          // Custom amount/percent/shares text field
                                          SizedBox(
                                            width: 80,
                                            child: TextField(
                                              controller: _customCtrls[m.id],
                                              keyboardType: const TextInputType.numberWithOptions(
                                                  decimal: true),
                                              textAlign: TextAlign.right,
                                              decoration: InputDecoration(
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(8),
                                                  borderSide: BorderSide(color: border),
                                                ),
                                                contentPadding: const EdgeInsets.symmetric(
                                                    horizontal: 10, vertical: 8),
                                                hintText: _splitMode == _SplitMode.percent
                                                    ? '%' : _splitMode == _SplitMode.shares
                                                        ? 'shares' : '0.00',
                                                hintStyle: _body(13, color: _ink48),
                                                isDense: true,
                                              ),
                                              style: _body(13),
                                              onChanged: (v) => _onCustomFieldChanged(m.id, v),
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                                if (!isLast)
                                  Divider(height: 1, color: border, indent: 62, endIndent: 16),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Save button
                    _Pressable(
                      onTap: _saving ? null : _save,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        decoration: BoxDecoration(
                          color: _saving ? _blue.withValues(alpha: 0.5) : _blue,
                          borderRadius: BorderRadius.circular(9999),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (_saving)
                              const CupertinoActivityIndicator(color: Colors.white)
                            else ...[
                              const Icon(CupertinoIcons.checkmark_circle_fill,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                _isEdit ? context.t('common.save') : context.t('travel.addExpense'),
                                style: _body(16, weight: FontWeight.w600, color: Colors.white),
                              ),
                            ],
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
      ),
    );
  }

  String _splitModeLabel(_SplitMode mode) {
    switch (mode) {
      case _SplitMode.equally: return 'Equally';
      case _SplitMode.amount: return 'Amount';
      case _SplitMode.percent: return 'Percent';
      case _SplitMode.shares: return 'Shares';
    }
  }
}

// ── Press animation wrapper ───────────────────────────────────────────────────

class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.95).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) { if (widget.onTap != null) _ctrl.forward(); },
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// ── Reusable constants ────────────────────────────────────────────────────────

const _memberBgs = [
  Color(0xFFE8E8EA), Color(0xFFDCDCE0), Color(0xFFD0D0D5),
  Color(0xFFC4C4CA), Color(0xFFB8B8BF),
];

// ── Date picker sheet ─────────────────────────────────────────────────────────

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
                      style: _body(17, weight: FontWeight.w600, color: _blue)),
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
