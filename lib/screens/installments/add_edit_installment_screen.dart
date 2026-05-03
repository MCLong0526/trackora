import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/installment.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/section_card.dart';
import '../expenses/add_edit_expense_screen.dart' show kExpenseCategories;

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
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _months = TextEditingController();
  final _alreadyPaid = TextEditingController();
  final _remainingMonths = TextEditingController();
  final _remainingBalance = TextEditingController();
  final _principal = TextEditingController();

  int _day = 1;
  String _category = 'Bills';
  DateTime _start = DateTime.now();
  DateTime? _end;
  bool _lifetime = false;
  bool _saving = false;

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
      _end = i.endDate;
      _lifetime = i.isLifetime;
      if (i.totalMonths != null) _months.text = i.totalMonths.toString();
      if (i.paidCount > 0) _alreadyPaid.text = i.paidCount.toString();
      if (i.monthsLeft != null) _remainingMonths.text = '${i.monthsLeft}';
      if (i.remainingAmountOverride != null) {
        _remainingBalance.text = i.remainingAmountOverride!.toStringAsFixed(2);
      }
      if (i.originalPrincipal != null) {
        _principal.text = i.originalPrincipal!.toStringAsFixed(2);
      }
    } else {
      _months.text = '12';
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    _months.dispose();
    _alreadyPaid.dispose();
    _remainingMonths.dispose();
    _remainingBalance.dispose();
    _principal.dispose();
    super.dispose();
  }

  /// Compute the resolved plan from total months + either months paid or
  /// months left. The UI shows total paid so far, while the model stores
  /// only the pre-Trackora paid count because in-app paid months live in
  /// [Installment.paidMonths].
  /// Returns null if the inputs are inconsistent / unparseable.
  ({
    int? totalMonths,
    int paidAtStart,
    double? principal,
    double? remainingOverride,
  })?
  _resolvePlan() {
    final inAppPaid = widget.installment?.paidInApp ?? 0;
    final remainingOverride = double.tryParse(_remainingBalance.text.trim());
    if (remainingOverride != null && remainingOverride < 0) return null;

    if (_lifetime) {
      return (
        totalMonths: null,
        paidAtStart: ((int.tryParse(_alreadyPaid.text.trim()) ?? 0) - inAppPaid)
            .clamp(0, 1000000)
            .toInt(),
        principal: double.tryParse(_principal.text.trim()),
        remainingOverride: remainingOverride,
      );
    }

    final amount = double.tryParse(_amount.text.trim()) ?? 0;
    int? total = int.tryParse(_months.text.trim());
    final paidInput = int.tryParse(_alreadyPaid.text.trim());
    final leftInput = int.tryParse(_remainingMonths.text.trim());
    int effectivePaid = paidInput ?? 0;
    double? principal = double.tryParse(_principal.text.trim());

    if (leftInput != null && leftInput < 0) return null;
    if (paidInput != null && paidInput < 0) return null;

    if (total != null && leftInput != null) {
      effectivePaid = total - leftInput;
    } else if (total == null && paidInput != null && leftInput != null) {
      total = paidInput + leftInput;
      effectivePaid = paidInput;
    } else if (total == null && leftInput != null) {
      total = leftInput + effectivePaid;
    } else if (total == null && remainingOverride != null && amount > 0) {
      final inferredLeft = (remainingOverride / amount).ceil();
      total = effectivePaid + inferredLeft;
    }

    if (total != null && total <= 0) return null;
    if (total != null) {
      effectivePaid = effectivePaid.clamp(0, total).toInt();
    }
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
      final i = Installment(
        id: widget.installment?.id ?? '',
        name: _name.text.trim(),
        amount: double.parse(_amount.text),
        dayOfMonth: _day,
        category: _category,
        startDate: _start,
        endDate: _end,
        paidMonths: widget.installment?.paidMonths ?? const [],
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
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(context.t('common.saveFailed'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
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
    await ref
        .read(installmentServiceProvider)
        .delete(user.uid, widget.installment!.id);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _toggleCancelled() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null || !_isEdit) return;
    final i = widget.installment!;
    final svc = ref.read(installmentServiceProvider);
    if (i.cancelled) {
      await svc.reactivate(user.uid, i);
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
      await svc.setCancelled(user.uid, i, true);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _markCompleted() async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null || !_isEdit) return;
    await ref
        .read(installmentServiceProvider)
        .markCompleted(user.uid, widget.installment!);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _pickStartDate() async {
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
    final selectedFg = foregroundOn(brand.accentDark);
    final existing = widget.installment;
    final status = existing?.status;

    return Scaffold(
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
              icon: const Icon(
                CupertinoIcons.delete,
                color: AppColors.expense,
                size: 20,
              ),
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
              if (_isEdit && status != null && existing != null)
                _StatusSummary(installment: existing),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  hintText: context.t('inst.nameHint'),
                  labelText: context.t('inst.name'),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.t('validation.enterName')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _amount,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: context.t('inst.monthlyAmount'),
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
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  context.t('inst.planLength'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(context.t('inst.lifetime')),
                      subtitle: Text(
                        _lifetime
                            ? context.t('inst.lifetimeSubtitle')
                            : context.t('inst.fixedSubtitle'),
                        style: TextStyle(fontSize: 12, color: brand.inkSoft),
                      ),
                      value: _lifetime,
                      onChanged: (v) => setState(() => _lifetime = v),
                    ),
                    if (!_lifetime) ...[
                      TextFormField(
                        controller: _months,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          labelText: context.t('inst.totalMonths'),
                          hintText: context.t('inst.totalMonthsHint'),
                        ),
                        validator: (v) {
                          if (_lifetime) return null;
                          final n = int.tryParse((v ?? '').trim());
                          if ((v ?? '').trim().isEmpty) return null;
                          if (n == null || n <= 0) {
                            return context.t('validation.enterMonths');
                          }
                          if (n > 600) {
                            return context.t('validation.tooManyMonths');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _alreadyPaid,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: context.t('inst.monthsPaid'),
                                hintText: context.t('inst.monthsPaidHint'),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextFormField(
                              controller: _remainingMonths,
                              keyboardType: TextInputType.number,
                              decoration: InputDecoration(
                                labelText: context.t('inst.monthsLeft'),
                                hintText: context.t('inst.monthsLeftHint'),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _remainingBalance,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: context.t('inst.optionalRemaining'),
                        hintText: context.t('inst.remainingHint'),
                        prefixText: '$symbol  ',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  context.t('inst.startDate'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SectionCard(
                onTap: _pickStartDate,
                child: Row(
                  children: [
                    Icon(CupertinoIcons.calendar, color: brand.ink),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        DateFormat('MMM d, yyyy').format(_start),
                        style: const TextStyle(fontWeight: FontWeight.w600),
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
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  context.t('inst.dueDay'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              SectionCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: SizedBox(
                  height: 48,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: 28,
                    itemBuilder: (_, idx) {
                      final d = idx + 1;
                      final selected = d == _day;
                      return GestureDetector(
                        onTap: () => setState(() => _day = d),
                        child: Container(
                          width: 40,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            color: selected
                                ? brand.accentDark
                                : brand.background,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$d',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: selected ? selectedFg : brand.ink,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  context.t('inst.category'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kExpenseCategories.map((c) {
                  final s = styleFor(c);
                  final selected = c == _category;
                  return GestureDetector(
                    onTap: () => setState(() => _category = c),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 9,
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
                            size: 14,
                            color: selected ? selectedFg : s.accent,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            context.categoryLabel(c),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: selected ? selectedFg : AppColors.ink,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 18),
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 8),
                child: Text(
                  context.t('inst.originalTotal'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              TextFormField(
                controller: _principal,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  hintText: 'e.g. ${formatMoney(symbol, 24000)}',
                  prefixText: '$symbol  ',
                ),
              ),
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
                            : context.t('inst.save'),
                      ),
              ),
              if (_isEdit) ...[
                const SizedBox(height: 12),
                if (status == InstallmentStatus.active)
                  OutlinedButton(
                    onPressed: _markCompleted,
                    child: Text(context.t('inst.markCompleted')),
                  ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _toggleCancelled,
                  style: TextButton.styleFrom(
                    foregroundColor: status == InstallmentStatus.cancelled
                        ? AppColors.income
                        : AppColors.expense,
                  ),
                  child: Text(
                    status == InstallmentStatus.cancelled
                        ? context.t('inst.reactivate')
                        : context.t('inst.cancel'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

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
      // Show what's still to pay, not what's already done. The "X / Y
      // months paid" line lives on the list tile's progress row, where
      // it's contextual; here we want the user to see the commitment.
      lines.add('${context.t('inst.monthsLeft')}: $left');
      lines.add(
        '${context.t('inst.remainingAmount')}: '
        '${formatMoney(symbol, remaining)}',
      );
    } else {
      // Completed / cancelled — keep terse.
      lines.add(
        i.status == InstallmentStatus.completed
            ? context
                  .t('inst.completedSummary')
                  .replaceFirst('{months}', '${i.totalMonths}')
            : context.t('inst.cancelledSummary'),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: SectionCard(
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
                InstallmentStatus.completed => context.t(
                  'inst.statusCompleted',
                ),
                InstallmentStatus.cancelled => context.t(
                  'inst.statusCancelled',
                ),
              },
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 6),
            for (final l in lines)
              Text(l, style: TextStyle(fontSize: 13, color: brand.ink)),
          ],
        ),
      ),
    );
  }
}
