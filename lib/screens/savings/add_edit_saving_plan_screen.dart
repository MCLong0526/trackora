import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/saving_plan.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';

/// Create / edit a saving plan.
///
/// The form adapts to the chosen type:
///  • fixed → contribution amount + frequency required.
///  • flexible → just target.
///  • daysChallenge → totalDays required (suggests 30).
///  • weeksChallenge → totalWeeks required (suggests 12).
class AddEditSavingPlanScreen extends ConsumerStatefulWidget {
  final SavingPlan? plan;
  const AddEditSavingPlanScreen({super.key, this.plan});

  @override
  ConsumerState<AddEditSavingPlanScreen> createState() =>
      _AddEditSavingPlanScreenState();
}

class _AddEditSavingPlanScreenState
    extends ConsumerState<AddEditSavingPlanScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _target = TextEditingController();
  final _contribution = TextEditingController();
  final _totalDays = TextEditingController(text: '30');
  final _totalWeeks = TextEditingController(text: '12');
  final _note = TextEditingController();

  SavingPlanType _type = SavingPlanType.flexible;
  SavingFrequency _frequency = SavingFrequency.monthly;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _saving = false;

  bool get _isEdit => widget.plan != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      final p = widget.plan!;
      _name.text = p.name;
      _target.text = p.targetAmount.toStringAsFixed(2);
      _contribution.text = p.contributionAmount?.toStringAsFixed(2) ?? '';
      _type = p.type;
      _frequency = p.frequency ?? SavingFrequency.monthly;
      _startDate = p.startDate;
      _endDate = p.endDate;
      if (p.totalDays != null) _totalDays.text = '${p.totalDays}';
      if (p.totalWeeks != null) _totalWeeks.text = '${p.totalWeeks}';
      _note.text = p.note;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _contribution.dispose();
    _totalDays.dispose();
    _totalWeeks.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool start}) async {
    DateTime temp = start ? _startDate : (_endDate ?? DateTime.now());
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
                initialDateTime: temp,
                onDateTimeChanged: (d) => temp = d,
              ),
            ),
            CupertinoButton(
              onPressed: () {
                setState(() {
                  if (start) {
                    _startDate = temp;
                  } else {
                    _endDate = temp;
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
    try {
      final svc = ref.read(savingPlanServiceProvider);
      final now = DateTime.now();
      final target = double.parse(_target.text);

      // Per-type fields.
      double? contribution;
      SavingFrequency? frequency;
      int? totalDays;
      int? totalWeeks;
      switch (_type) {
        case SavingPlanType.fixed:
          contribution = double.tryParse(_contribution.text);
          frequency = _frequency;
          break;
        case SavingPlanType.flexible:
          break;
        case SavingPlanType.daysChallenge:
          totalDays = int.tryParse(_totalDays.text.trim());
          // Daily contribution is target / days.
          if (totalDays != null && totalDays > 0) {
            contribution = target / totalDays;
            frequency = SavingFrequency.daily;
          }
          break;
        case SavingPlanType.weeksChallenge:
          totalWeeks = int.tryParse(_totalWeeks.text.trim());
          if (totalWeeks != null && totalWeeks > 0) {
            contribution = target / totalWeeks;
            frequency = SavingFrequency.weekly;
          }
          break;
      }

      if (_isEdit) {
        final updated = widget.plan!.copyWith(
          name: _name.text.trim(),
          type: _type,
          targetAmount: target,
          contributionAmount: contribution,
          frequency: frequency,
          startDate: _startDate,
          endDate: _endDate,
          totalDays: totalDays,
          totalWeeks: totalWeeks,
          note: _note.text.trim(),
          updatedAt: now,
        );
        await svc.update(user.uid, updated);
      } else {
        await svc.add(
          user.uid,
          SavingPlan(
            id: '',
            name: _name.text.trim(),
            type: _type,
            targetAmount: target,
            contributionAmount: contribution,
            frequency: frequency,
            startDate: _startDate,
            endDate: _endDate,
            totalDays: totalDays,
            totalWeeks: totalWeeks,
            note: _note.text.trim(),
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
        title: Text(_isEdit ? context.t('sp.edit') : context.t('sp.new')),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            children: [
              _typeSelector(brand),
              const SizedBox(height: 16),
              TextFormField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: context.t('sp.fieldName'),
                  hintText: context.t('sp.fieldNameHint'),
                ),
                validator: (v) => (v == null || v.trim().isEmpty)
                    ? context.t('sp.nameRequired')
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _target,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: context.t('sp.fieldTarget'),
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
              if (_type == SavingPlanType.fixed) ...[
                TextFormField(
                  controller: _contribution,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: context.t('sp.fieldContribution'),
                    prefixText: '$symbol  ',
                  ),
                  validator: (v) {
                    if (_type != SavingPlanType.fixed) return null;
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
                _frequencyPicker(brand),
                const SizedBox(height: 12),
              ],
              if (_type == SavingPlanType.daysChallenge)
                TextFormField(
                  controller: _totalDays,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.t('sp.fieldDays'),
                    hintText: '30',
                  ),
                  validator: (v) {
                    if (_type != SavingPlanType.daysChallenge) return null;
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) {
                      return context.t('sp.invalidDays');
                    }
                    return null;
                  },
                ),
              if (_type == SavingPlanType.weeksChallenge)
                TextFormField(
                  controller: _totalWeeks,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: context.t('sp.fieldWeeks'),
                    hintText: '12',
                  ),
                  validator: (v) {
                    if (_type != SavingPlanType.weeksChallenge) return null;
                    final n = int.tryParse((v ?? '').trim());
                    if (n == null || n <= 0) {
                      return context.t('sp.invalidWeeks');
                    }
                    return null;
                  },
                ),
              if (_type == SavingPlanType.daysChallenge ||
                  _type == SavingPlanType.weeksChallenge)
                const SizedBox(height: 12),
              _dateTile(
                label: context.t('sp.fieldStartDate'),
                value: DateFormat('MMM d, yyyy').format(_startDate),
                onTap: () => _pickDate(start: true),
              ),
              const SizedBox(height: 10),
              _dateTile(
                label: context.t('sp.fieldEndDate'),
                value: _endDate == null
                    ? context.t('sp.optional')
                    : DateFormat('MMM d, yyyy').format(_endDate!),
                onTap: () => _pickDate(start: false),
                onClear:
                    _endDate == null ? null : () => setState(() => _endDate = null),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _note,
                maxLines: 2,
                decoration: InputDecoration(
                  labelText: context.t('sp.fieldNote'),
                ),
              ),
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

  Widget _typeSelector(BrandColors brand) {
    final selectedFg = foregroundOn(brand.accentDark);
    Widget opt(SavingPlanType type, String label, IconData icon) {
      final selected = _type == type;
      return GestureDetector(
        onTap: () => setState(() => _type = type),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? brand.accentDark : brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: selected ? selectedFg : brand.ink,
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: selected ? selectedFg : brand.ink,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        opt(SavingPlanType.fixed, context.t('sp.typeFixed'),
            CupertinoIcons.calendar_badge_plus),
        opt(SavingPlanType.flexible, context.t('sp.typeFlexible'),
            CupertinoIcons.drop_fill),
        opt(SavingPlanType.daysChallenge, context.t('sp.typeDays'),
            CupertinoIcons.number_circle),
        opt(SavingPlanType.weeksChallenge, context.t('sp.typeWeeks'),
            CupertinoIcons.calendar),
      ],
    );
  }

  Widget _frequencyPicker(BrandColors brand) {
    final selectedFg = foregroundOn(brand.accentDark);
    Widget opt(SavingFrequency f, String label) {
      final selected = _frequency == f;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _frequency = f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? brand.accentDark : Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            alignment: Alignment.center,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
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
          opt(SavingFrequency.daily, context.t('sp.daily')),
          opt(SavingFrequency.weekly, context.t('sp.weekly')),
          opt(SavingFrequency.monthly, context.t('sp.monthly')),
        ],
      ),
    );
  }

  Widget _dateTile({
    required String label,
    required String value,
    required VoidCallback onTap,
    VoidCallback? onClear,
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
              if (onClear != null) ...[
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: onClear,
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
}
