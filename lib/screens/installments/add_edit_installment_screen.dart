import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/installment.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/section_card.dart';

class AddEditInstallmentScreen extends ConsumerStatefulWidget {
  final Installment? installment;
  const AddEditInstallmentScreen({super.key, this.installment});

  @override
  ConsumerState<AddEditInstallmentScreen> createState() =>
      _AddEditInstallmentScreenState();
}

class _AddEditInstallmentScreenState
    extends ConsumerState<AddEditInstallmentScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameFocus = FocusNode();

  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _months = TextEditingController();
  final _remainingMonths = TextEditingController();
  final _remainingBalance = TextEditingController();
  final _principal = TextEditingController();
  final _alreadyPaid = TextEditingController();

  // Auto-calculation tracking
  bool _principalIsAuto = false;
  bool _remainingIsAuto = false;
  bool _monthsLeftIsAuto = false;
  bool _updating = false;

  int _day = 1;
  String _category = 'Bills';
  DateTime _start = DateTime.now();
  bool _lifetime = false;
  bool _saving = false;
  bool _success = false;
  bool _currentMonthPaid = false;

  bool get _isEdit => widget.installment != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final i = widget.installment!;
      _name.text = i.name;
      _amount.text = i.amount.toStringAsFixed(2);
      _day = i.dayOfMonth;
      _category = i.category;
      _start = i.startDate;
      _lifetime = i.isLifetime;
      if (i.totalMonths != null) _months.text = i.totalMonths.toString();
      if (i.monthsLeft != null) _remainingMonths.text = '${i.monthsLeft}';
      if (i.remainingAmountOverride != null) {
        _remainingBalance.text = i.remainingAmountOverride!.toStringAsFixed(2);
      }
      if (i.originalPrincipal != null) {
        _principal.text = i.originalPrincipal!.toStringAsFixed(2);
      }
      if (i.paidCount > 0) _alreadyPaid.text = i.paidMonthsAtStart.toString();
      _currentMonthPaid = i.isPaidIn(DateTime.now());
      // In edit mode, existing values are user-entered, not auto
      _principalIsAuto = false;
      _remainingIsAuto = false;
      _monthsLeftIsAuto = false;
    } else {
      // New installment: optional fields start auto-calculable
      _principalIsAuto = true;
      _remainingIsAuto = true;
      _monthsLeftIsAuto = true;
    }

    _amount.addListener(_recalculate);
    _months.addListener(_recalculate);
    _remainingMonths.addListener(_onMonthsLeftChanged);
    _remainingBalance.addListener(_onRemainingChanged);
    _principal.addListener(_onPrincipalChanged);
  }

  @override
  void dispose() {
    _nameFocus.dispose();
    _name.dispose();
    _amount.dispose();
    _months.dispose();
    _remainingMonths.dispose();
    _remainingBalance.dispose();
    _principal.dispose();
    _alreadyPaid.dispose();
    super.dispose();
  }

  void _onMonthsLeftChanged() {
    if (_updating) return;
    if (_remainingMonths.text.trim().isEmpty) {
      _monthsLeftIsAuto = true;
    } else {
      _monthsLeftIsAuto = false;
      _remainingIsAuto = true;
    }
    _recalculate();
  }

  void _onRemainingChanged() {
    if (_updating) return;
    if (_remainingBalance.text.trim().isEmpty) {
      _remainingIsAuto = true;
    } else {
      _remainingIsAuto = false;
      _monthsLeftIsAuto = true;
    }
    _recalculate();
  }

  void _onPrincipalChanged() {
    if (_updating) return;
    _principalIsAuto = _principal.text.trim().isEmpty;
  }

  void _recalculate() {
    if (_updating) return;
    _updating = true;
    try {
      final amount = double.tryParse(_amount.text.trim()) ?? 0;
      final totalMonths = int.tryParse(_months.text.trim());
      final monthsLeft = int.tryParse(_remainingMonths.text.trim());

      // Rule 1: Original total = amount × total months
      if (_principalIsAuto && amount > 0 && totalMonths != null && totalMonths > 0) {
        _principal.text = (amount * totalMonths).toStringAsFixed(2);
      }

      // Rule 2: Remaining = amount × months left
      if (_remainingIsAuto && amount > 0 && monthsLeft != null && monthsLeft >= 0) {
        _remainingBalance.text = (amount * monthsLeft).toStringAsFixed(2);
      }

      // Rule 3: Months left = remaining / amount (when remaining is user-entered)
      if (_monthsLeftIsAuto && !_remainingIsAuto) {
        final remaining = double.tryParse(_remainingBalance.text.trim());
        if (amount > 0 && remaining != null && remaining >= 0) {
          _remainingMonths.text = (remaining / amount).ceil().toString();
        }
      }
    } finally {
      _updating = false;
    }
  }

  ({
    int? totalMonths,
    int paidAtStart,
    double? principal,
    double? remainingOverride,
  })?
  _resolvePlan() {
    final currentKey = Installment.monthKey(DateTime.now());
    final existingPaidMonths = widget.installment?.paidMonths ?? const <String>[];
    final currentMonthWasPaid = existingPaidMonths.contains(currentKey);

    // Compute how many in-app paid months there will be AFTER save, accounting
    // for the current-month toggle adding or removing one entry.
    int inAppPaid = widget.installment?.paidInApp ?? 0;
    if (_currentMonthPaid && !currentMonthWasPaid) inAppPaid += 1;
    if (!_currentMonthPaid && currentMonthWasPaid) inAppPaid -= 1;

    final remainingOverride = double.tryParse(_remainingBalance.text.trim());
    if (remainingOverride != null && remainingOverride < 0) return null;

    if (_lifetime) {
      final alreadyPaid = (int.tryParse(_alreadyPaid.text.trim()) ?? 0)
          .clamp(0, 1000000)
          .toInt();
      return (
        totalMonths: null,
        paidAtStart: (alreadyPaid - inAppPaid).clamp(0, 1000000).toInt(),
        principal: double.tryParse(_principal.text.trim()),
        remainingOverride: remainingOverride,
      );
    }

    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    int? total = int.tryParse(_months.text.trim());
    final leftInput = int.tryParse(_remainingMonths.text.trim());
    double? principal = double.tryParse(_principal.text.trim());

    if (leftInput != null && leftInput < 0) return null;

    // Derive effective paid months from total - left (or existing paidCount).
    int effectivePaid = 0;
    if (total != null && leftInput != null) {
      effectivePaid = (total - leftInput).clamp(0, total);
    } else if (total != null) {
      effectivePaid = 0;
    } else if (leftInput != null) {
      total = leftInput;
      effectivePaid = 0;
    } else if (remainingOverride != null && amount > 0) {
      final inferredLeft = (remainingOverride / amount).ceil();
      total = inferredLeft;
      effectivePaid = 0;
    }

    if (total != null && total <= 0) return null;
    final paidAtStart = (effectivePaid - inAppPaid).clamp(0, 1000000).toInt();
    return (
      totalMonths: total,
      paidAtStart: paidAtStart,
      principal: principal,
      remainingOverride: remainingOverride,
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final resolved = _resolvePlan();
    if (resolved == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('validation.planInvalid'))),
      );
      return;
    }
    if (!_lifetime && resolved.totalMonths == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.t('validation.totalMonthsRequired'))),
      );
      return;
    }

    setState(() => _saving = true);
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      setState(() => _saving = false);
      return;
    }
    final svc = ref.read(installmentServiceProvider);

    try {
      final currentKey = Installment.monthKey(DateTime.now());
      final basePaidMonths = List<String>.from(
        widget.installment?.paidMonths ?? const <String>[],
      );
      if (_currentMonthPaid && !basePaidMonths.contains(currentKey)) {
        basePaidMonths.add(currentKey);
      } else if (!_currentMonthPaid && basePaidMonths.contains(currentKey)) {
        basePaidMonths.remove(currentKey);
      }

      final i = Installment(
        id: widget.installment?.id ?? '',
        name: _name.text.trim(),
        amount: double.parse(_amount.text),
        dayOfMonth: _day,
        category: _category,
        startDate: _start,
        paidMonths: basePaidMonths,
        totalMonths: resolved.totalMonths,
        cancelled: widget.installment?.cancelled ?? false,
        paidMonthsAtStart: resolved.paidAtStart,
        originalPrincipal: resolved.principal,
        remainingAmountOverride: resolved.remainingOverride,
      );
      if (_isEdit) {
        await svc.update(user.uid, i);
      } else {
        await svc.add(user.uid, i);
      }
      if (mounted) {
        setState(() { _saving = false; _success = true; });
        AppToast.show(
          context,
          _isEdit ? 'Installment updated' : 'Installment added',
          type: AppToastType.success,
        );
        await Future.delayed(const Duration(milliseconds: 700));
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, context.t('common.saveFailed'), type: AppToastType.error);
      }
    } finally {
      if (mounted && !_success) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null || !_isEdit) return;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('inst.deleteTitle')),
        content: Text(context.t('inst.deleteMessage')),
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
    if (ok != true) return;
    try {
      await ref
          .read(installmentServiceProvider)
          .delete(user.uid, widget.installment!.id);
      if (mounted) {
        AppToast.show(context, 'Installment deleted', type: AppToastType.success);
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Failed to delete', type: AppToastType.error);
      }
    }
  }

  Future<void> _toggleCancelled() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null || !_isEdit) return;
    final i = widget.installment!;
    final svc = ref.read(installmentServiceProvider);
    if (i.cancelled) {
      try {
        await svc.reactivate(user.uid, i);
        if (mounted) {
          AppToast.show(context, 'Reactivated', type: AppToastType.success);
          Navigator.pop(context);
        }
      } catch (_) {
        if (mounted) {
          AppToast.show(context, 'Failed to reactivate', type: AppToastType.error);
        }
      }
    } else {
      final ok = await showCupertinoDialog<bool>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(context.t('inst.cancelTitle')),
          content: Text(context.t('inst.cancelMessage')),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(context.t('inst.keep')),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(context.t('inst.cancelIt')),
            ),
          ],
        ),
      );
      if (ok != true) return;
      try {
        await svc.setCancelled(user.uid, i, true);
        if (mounted) {
          AppToast.show(context, 'Installment cancelled', type: AppToastType.success);
          Navigator.pop(context);
        }
      } catch (_) {
        if (mounted) {
          AppToast.show(context, 'Failed to cancel', type: AppToastType.error);
        }
      }
    }
  }

  Future<void> _markCompleted() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null || !_isEdit) return;
    try {
      await ref
          .read(installmentServiceProvider)
          .markCompleted(user.uid, widget.installment!);
      if (mounted) {
        AppToast.show(context, 'Marked as completed', type: AppToastType.success);
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, 'Failed to complete', type: AppToastType.error);
      }
    }
  }

  Future<void> _showActionsSheet() async {
    final i = widget.installment!;
    final status = i.status;
    await showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          if (status == InstallmentStatus.active)
            CupertinoActionSheetAction(
              onPressed: () {
                Navigator.pop(ctx);
                _markCompleted();
              },
              child: Text(context.t('inst.markCompleted')),
            ),
          CupertinoActionSheetAction(
            isDestructiveAction: status != InstallmentStatus.cancelled,
            onPressed: () {
              Navigator.pop(ctx);
              _toggleCancelled();
            },
            child: Text(
              status == InstallmentStatus.cancelled
                  ? context.t('inst.reactivate')
                  : context.t('inst.cancel'),
            ),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _delete();
            },
            child: Text(context.t('common.delete')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(context.t('common.cancel')),
        ),
      ),
    );
  }

  Future<void> _pickStartDate() async {
    FocusScope.of(context).unfocus();
    DateTime temp = _start;
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
                initialDateTime: _start,
                maximumDate: DateTime.now().add(const Duration(days: 365 * 5)),
                onDateTimeChanged: (d) => temp = d,
              ),
            ),
            CupertinoButton(
              child: Text(context.t('common.done')),
              onPressed: () {
                setState(() => _start = temp);
                Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final existing = widget.installment;
    final status = existing?.status;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
        backgroundColor: brand.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(CupertinoIcons.xmark),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(_isEdit ? context.t('inst.edit') : context.t('inst.new')),
          actions: [
            if (_isEdit)
              IconButton(
                icon: const Icon(CupertinoIcons.ellipsis_circle, size: 22),
                onPressed: _showActionsSheet,
              ),
          ],
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  children: [
                // Status summary (edit mode only)
                if (_isEdit && status != null && existing != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _StatusSummary(installment: existing),
                  ),

                // ── Section: Basic Info ──────────────────────────────
                _SectionHeader(label: 'DETAILS'),
                const SizedBox(height: 8),
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _FieldRow(
                        child: TextFormField(
                          controller: _name,
                          focusNode: _nameFocus,
                          autofocus: false,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: InputDecoration(
                            hintText: context.t('inst.nameHint'),
                            labelText: context.t('inst.name'),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? context.t('validation.enterName')
                              : null,
                        ),
                      ),
                      _Divider(brand: brand),
                      _FieldRow(
                        child: TextFormField(
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            labelText: context.t('inst.monthlyAmount'),
                            prefixText: '$symbol  ',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
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
                ),

                const SizedBox(height: 24),

                // ── Section: Plan ────────────────────────────────────
                _SectionHeader(label: context.t('inst.planLength')),
                const SizedBox(height: 8),
                _PlanTypeSelector(
                  isLifetime: _lifetime,
                  onChanged: (isLifetime) => setState(() {
                    _lifetime = isLifetime;
                    if (isLifetime) {
                      _updating = true;
                      _months.clear();
                      _remainingMonths.clear();
                      _updating = false;
                    }
                  }),
                ),
                const SizedBox(height: 8),
                // Fix 3: ClipRect + AnimatedSize for smooth height transition.
                // SectionCard has no key (persistent). AnimatedSwitcher crossfades
                // the inner Column content, with previousChildren pinned via
                // Positioned so they don't affect Stack height (only current child does).
                ClipRect(
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 280),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment.topCenter,
                    child: SectionCard(
                      padding: EdgeInsets.zero,
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        layoutBuilder: (currentChild, previousChildren) => Stack(
                          alignment: Alignment.topCenter,
                          children: [
                            ...previousChildren.map(
                              (c) => Positioned(top: 0, left: 0, right: 0, child: c),
                            ),
                            ?currentChild,
                          ],
                        ),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: child,
                        ),
                        child: Column(
                          key: ValueKey(_lifetime),
                          children: [
                            if (!_lifetime) ...[
                              _FieldRow(
                                child: TextFormField(
                                  controller: _months,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: context.t('inst.totalMonths'),
                                    hintText: context.t('inst.totalMonthsHint'),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    suffixText: _months.text.isNotEmpty ? 'mo' : null,
                                  ),
                                  validator: (v) {
                                    if (_lifetime) return null;
                                    final n = int.tryParse((v ?? '').trim());
                                    if ((v ?? '').trim().isEmpty) return null;
                                    if (n == null || n <= 0) {
                                      return context.t('validation.enterMonths');
                                    }
                                    if (n > 600) return context.t('validation.tooManyMonths');
                                    return null;
                                  },
                                ),
                              ),
                              _Divider(brand: brand),
                              _FieldRow(
                                child: TextFormField(
                                  controller: _remainingMonths,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: context.t('inst.monthsLeft'),
                                    hintText: context.t('inst.monthsLeftHint'),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    suffixText: _remainingMonths.text.isNotEmpty ? 'mo' : null,
                                    suffixStyle: _monthsLeftIsAuto
                                        ? TextStyle(color: brand.accentDark, fontSize: 12)
                                        : null,
                                  ),
                                ),
                              ),
                              _Divider(brand: brand),
                              _FieldRow(
                                child: TextFormField(
                                  controller: _remainingBalance,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: context.t('inst.optionalRemaining'),
                                    hintText: context.t('inst.remainingHint'),
                                    prefixText: '$symbol  ',
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              _Divider(brand: brand),
                              _FieldRow(
                                child: TextFormField(
                                  controller: _principal,
                                  keyboardType: const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                                  decoration: InputDecoration(
                                    labelText: context.t('inst.originalTotal'),
                                    hintText: 'e.g. ${formatMoney(symbol, 24000)}',
                                    prefixText: '$symbol  ',
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                ),
                              ),
                              if (!_isEdit) _Divider(brand: brand),
                            ],
                            if (_lifetime) ...[
                              _FieldRow(
                                child: TextFormField(
                                  controller: _alreadyPaid,
                                  keyboardType: TextInputType.number,
                                  decoration: InputDecoration(
                                    labelText: context.t('inst.monthsPaid'),
                                    hintText: context.t('inst.monthsPaidHint'),
                                    border: InputBorder.none,
                                    enabledBorder: InputBorder.none,
                                    focusedBorder: InputBorder.none,
                                    contentPadding: EdgeInsets.zero,
                                    suffixText: _alreadyPaid.text.isNotEmpty ? 'mo' : null,
                                  ),
                                ),
                              ),
                              if (!_isEdit) _Divider(brand: brand),
                            ],
                            if (!_isEdit)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                                child: Row(
                                  children: [
                                    AnimatedSwitcher(
                                      duration: const Duration(milliseconds: 250),
                                      transitionBuilder: (child, animation) =>
                                          ScaleTransition(
                                            scale: Tween<double>(
                                              begin: 0.65,
                                              end: 1.0,
                                            ).animate(CurvedAnimation(
                                              parent: animation,
                                              curve: Curves.easeOutCubic,
                                            )),
                                            child: FadeTransition(
                                              opacity: animation,
                                              child: child,
                                            ),
                                          ),
                                      child: _currentMonthPaid
                                          ? const Icon(
                                              CupertinoIcons.checkmark_seal_fill,
                                              key: ValueKey(true),
                                              size: 20,
                                              color: Color(0xFF34C759),
                                            )
                                          : Icon(
                                              CupertinoIcons.checkmark_seal,
                                              key: ValueKey(false),
                                              size: 20,
                                              color: brand.inkSoft,
                                            ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        context.t('inst.currentMonthPaid'),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 15,
                                        ),
                                      ),
                                    ),
                                    CupertinoSwitch(
                                      value: _currentMonthPaid,
                                      activeTrackColor: const Color(0xFF34C759),
                                      onChanged: (v) =>
                                          setState(() => _currentMonthPaid = v),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 24),

                // ── Section: Schedule ────────────────────────────────
                _SectionHeader(label: 'SCHEDULE'),
                const SizedBox(height: 8),
                SectionCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      InkWell(
                        onTap: _pickStartDate,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                          child: Row(
                            children: [
                              Icon(CupertinoIcons.calendar, size: 18, color: brand.inkSoft),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  context.t('inst.startDate'),
                                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                                ),
                              ),
                              Text(
                                DateFormat('MMM d, yyyy').format(_start),
                                style: TextStyle(color: brand.inkSoft, fontSize: 15),
                              ),
                              const SizedBox(width: 4),
                              Icon(CupertinoIcons.chevron_right, size: 13, color: brand.inkSoft),
                            ],
                          ),
                        ),
                      ),
                      _Divider(brand: brand),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(CupertinoIcons.calendar_badge_plus, size: 18, color: brand.inkSoft),
                                const SizedBox(width: 12),
                                Text(
                                  context.t('inst.dueDay'),
                                  style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
                                ),
                                const Spacer(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: brand.accentDark.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '$_day${_ordinal(_day)}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: brand.accentDark,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 42,
                              child: ListView.builder(
                                scrollDirection: Axis.horizontal,
                                itemCount: 28,
                                itemBuilder: (_, idx) {
                                  final d = idx + 1;
                                  final selected = d == _day;
                                  return GestureDetector(
                                    onTap: () => setState(() => _day = d),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 120),
                                      width: 36,
                                      margin: const EdgeInsets.symmetric(horizontal: 2),
                                      decoration: BoxDecoration(
                                        color: selected ? brand.accentDark : brand.background,
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      alignment: Alignment.center,
                                      child: Text(
                                        '$d',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: selected ? foregroundOn(brand.accentDark) : brand.ink,
                                        ),
                                      ),
                                    ),
                                  );
                                },
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

              // ── Sticky Save Button ────────────────────────────────
              Container(
                decoration: BoxDecoration(
                  color: brand.background,
                  border: Border(
                    top: BorderSide(color: brand.divider, width: 0.5),
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).padding.bottom + 12,
                ),
                child: FilledButton(
                  onPressed: (_saving || _success) ? null : _save,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: _success
                        ? const Icon(
                            CupertinoIcons.checkmark_alt,
                            size: 20,
                            key: ValueKey('check'),
                          )
                        : _saving
                            ? SizedBox(
                                key: const ValueKey('loading'),
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color:
                                      Theme.of(context).colorScheme.onPrimary,
                                ),
                              )
                            : Text(
                                _isEdit
                                    ? context.t('common.update')
                                    : context.t('inst.save'),
                                key: const ValueKey('label'),
                              ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _ordinal(int n) {
    if (n >= 11 && n <= 13) return 'th';
    return switch (n % 10) {
      1 => 'st',
      2 => 'nd',
      3 => 'rd',
      _ => 'th',
    };
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: context.brand.inkSoft,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  final Widget child;
  const _FieldRow({required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: child,
    );
  }
}

class _Divider extends StatelessWidget {
  final BrandColors brand;
  const _Divider({required this.brand});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: brand.divider, indent: 16, endIndent: 16);
  }
}

class _PlanTypeSelector extends StatelessWidget {
  final bool isLifetime;
  final ValueChanged<bool> onChanged;
  const _PlanTypeSelector({required this.isLifetime, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final selectedFg = foregroundOn(brand.accentDark);

    Widget option(bool lifetime, IconData icon, String label) {
      final selected = isLifetime == lifetime;
      return Expanded(
        child: GestureDetector(
          onTap: () => onChanged(lifetime),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    icon,
                    key: ValueKey(selected),
                    size: 14,
                    color: selected ? selectedFg : brand.inkSoft,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 200),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected ? selectedFg : brand.ink,
                  ),
                  child: Text(label),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (ctx, constraints) {
        final pillW = (constraints.maxWidth - 8) / 2;
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                left: isLifetime ? pillW : 0,
                top: 0,
                bottom: 0,
                width: pillW,
                child: Container(
                  decoration: BoxDecoration(
                    color: brand.accentDark,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                ),
              ),
              Row(
                children: [
                  option(
                    false,
                    CupertinoIcons.calendar,
                    context.t('inst.fixedTermShort'),
                  ),
                  option(
                    true,
                    CupertinoIcons.infinite,
                    context.t('inst.lifetimeShort'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Status Summary ─────────────────────────────────────────────────────────────

class _StatusSummary extends ConsumerWidget {
  final Installment installment;
  const _StatusSummary({required this.installment});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final i = installment;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final lines = <String>[];
    if (i.isLifetime) {
      lines.add(context.t('inst.lifetime'));
      lines.add(context.t('inst.cancelAnytime'));
    } else if (i.status == InstallmentStatus.active) {
      final left = i.monthsLeft ?? 0;
      final remaining = i.totalRemaining ?? 0;
      lines.add('${context.t('inst.monthsLeft')}: $left');
      lines.add(
        '${context.t('inst.remainingAmount')}: ${formatMoney(symbol, remaining)}',
      );
    } else {
      lines.add(
        i.status == InstallmentStatus.completed
            ? context
                  .t('inst.completedSummary')
                  .replaceFirst('{months}', '${i.totalMonths}')
            : context.t('inst.cancelledSummary'),
      );
    }
    return SectionCard(
      color: switch (i.status) {
        InstallmentStatus.active => AppColors.mint,
        InstallmentStatus.completed => AppColors.sky,
        InstallmentStatus.cancelled => AppColors.divider,
      },
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            switch (i.status) {
              InstallmentStatus.active =>
                i.isLifetime
                    ? context.t('inst.statusLifetime')
                    : context.t('inst.statusActive'),
              InstallmentStatus.completed => context.t('inst.statusCompleted'),
              InstallmentStatus.cancelled => context.t('inst.statusCancelled'),
            },
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          for (final l in lines)
            Text(l, style: TextStyle(fontSize: 13, color: brand.ink)),
        ],
      ),
    );
  }
}
