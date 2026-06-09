import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/saving_plan.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

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
  final _periodsCtrl = TextEditingController();
  final _totalDays = TextEditingController(text: '30');
  final _totalWeeks = TextEditingController(text: '12');
  final _note = TextEditingController();

  SavingPlanType _type = SavingPlanType.flexible;
  SavingFrequency _frequency = SavingFrequency.monthly;
  DateTime _startDate = DateTime.now();
  DateTime? _endDate;
  bool _saving = false;
  bool _success = false;

  // Auto-fill state for Fixed tab
  bool _periodsIsAuto = true;
  bool _contribIsAuto = false;
  bool _isUpdating = false;

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
      // Pre-fill periods from endDate for fixed plans
      if (p.type == SavingPlanType.fixed && p.endDate != null) {
        final computed = _periodsFromDates(p.startDate, p.endDate!, p.frequency ?? SavingFrequency.monthly);
        if (computed > 0) {
          _periodsCtrl.text = '$computed';
          _periodsIsAuto = false;
        }
      }
    }

    _target.addListener(_onTargetChanged);
    _contribution.addListener(_onContributionChanged);
    _periodsCtrl.addListener(_onPeriodsChanged);
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _contribution.dispose();
    _periodsCtrl.dispose();
    _totalDays.dispose();
    _totalWeeks.dispose();
    _note.dispose();
    super.dispose();
  }

  // ── Auto-fill logic ──────────────────────────────────────────

  /// When the target amount changes we keep the per-period contribution the
  /// user entered fixed and recompute the number of periods (e.g. raising the
  /// target from 2000 → 4000 at 200/period takes the periods from 10 → 20).
  /// Only if there is no contribution do we instead recompute the
  /// contribution from the existing periods.
  void _onTargetChanged() {
    if (_isUpdating) return;
    final contribution = double.tryParse(_contribution.text.trim());
    final periods = int.tryParse(_periodsCtrl.text.trim());
    if (contribution != null && contribution > 0) {
      _periodsIsAuto = true;
      _contribIsAuto = false;
    } else if (periods != null && periods > 0) {
      _contribIsAuto = true;
      _periodsIsAuto = false;
    }
    _recalculateFixed();
  }

  void _onContributionChanged() {
    if (_isUpdating) return;
    if (_contribution.text.trim().isEmpty) {
      // User cleared the field — reset flags but do NOT auto-refill it.
      _contribIsAuto = false;
      _periodsIsAuto = false;
      setState(() => _endDate = null);
      return;
    }
    // User typed a value — periods will now be auto-computed.
    _contribIsAuto = false;
    _periodsIsAuto = true;
    _recalculateFixed();
  }

  void _onPeriodsChanged() {
    if (_isUpdating) return;
    if (_periodsCtrl.text.trim().isEmpty) {
      _periodsIsAuto = true;
      _contribIsAuto = false;
      setState(() => _endDate = null);
      return;
    }
    // User typed periods — contribution will now be auto-computed.
    _periodsIsAuto = false;
    _contribIsAuto = true;
    _recalculateFixed();
  }

  void _recalculateFixed() {
    if (_isUpdating || _type != SavingPlanType.fixed) return;
    _isUpdating = true;
    try {
      final target = double.tryParse(_target.text.trim());
      final contribution = double.tryParse(_contribution.text.trim());
      final periods = int.tryParse(_periodsCtrl.text.trim());

      DateTime? newEndDate = _endDate;

      if (_periodsIsAuto &&
          target != null && target > 0 &&
          contribution != null && contribution > 0) {
        // Compute periods from target ÷ contribution.
        final p = (target / contribution).ceil();
        _periodsCtrl.text = '$p';
        newEndDate = _computeEndDate(p);
      } else if (_contribIsAuto &&
          target != null && target > 0 &&
          periods != null && periods > 0) {
        // Compute contribution from target ÷ periods.
        _contribution.text = (target / periods).toStringAsFixed(2);
        newEndDate = _computeEndDate(periods);
      } else if (periods != null && periods > 0 &&
          contribution != null && contribution > 0) {
        // Both user-entered — just keep end date in sync.
        newEndDate = _computeEndDate(periods);
      }

      if (newEndDate != _endDate) {
        setState(() => _endDate = newEndDate);
      }
    } finally {
      _isUpdating = false;
    }
  }

  DateTime _computeEndDate(int periods) {
    return switch (_frequency) {
      SavingFrequency.daily => _startDate.add(Duration(days: periods)),
      SavingFrequency.weekly => _startDate.add(Duration(days: periods * 7)),
      SavingFrequency.monthly => DateTime(
          _startDate.year,
          _startDate.month + periods,
          _startDate.day,
        ),
    };
  }

  int _periodsFromDates(DateTime start, DateTime end, SavingFrequency freq) {
    return switch (freq) {
      SavingFrequency.daily => end.difference(start).inDays,
      SavingFrequency.weekly => (end.difference(start).inDays / 7).round(),
      SavingFrequency.monthly =>
        (end.year - start.year) * 12 + (end.month - start.month),
    };
  }

  String _periodsLabel() => switch (_frequency) {
        SavingFrequency.daily => 'Days',
        SavingFrequency.weekly => 'Weeks',
        SavingFrequency.monthly => 'Months',
      };

  // ── Date picker ──────────────────────────────────────────────

  Future<void> _pickDate({required bool start}) async {
    FocusScope.of(context).unfocus();
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
                    // Recompute end date when start changes if periods set
                    final p = int.tryParse(_periodsCtrl.text.trim());
                    if (p != null && p > 0 && _type == SavingPlanType.fixed) {
                      _endDate = _computeEndDate(p);
                    }
                  } else {
                    _endDate = temp;
                    // When end date is manually set, compute periods
                    if (_type == SavingPlanType.fixed) {
                      final p = _periodsFromDates(_startDate, temp, _frequency);
                      if (p > 0) {
                        _periodsIsAuto = false;
                        _periodsCtrl.text = '$p';
                      }
                    }
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
    if (mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) FocusScope.of(context).unfocus();
      });
    }
  }

  // ── Save ─────────────────────────────────────────────────────

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
      if (mounted) {
        setState(() {
          _saving = false;
          _success = true;
        });
        AppToast.show(
          context,
          _isEdit ? 'Plan updated' : 'Plan created',
          type: AppToastType.success,
        );
        await Future.delayed(const Duration(milliseconds: 600));
        if (mounted) Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) {
        AppToast.show(context, context.t('common.saveFailed'),
            type: AppToastType.error);
        setState(() => _saving = false);
      }
    }
  }

  // ── Build ────────────────────────────────────────────────────

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
                // Type-specific fields with smooth crossfade
                AnimatedSize(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    switchInCurve: Curves.easeOut,
                    switchOutCurve: Curves.easeIn,
                    transitionBuilder: (child, anim) =>
                        FadeTransition(opacity: anim, child: child),
                    child: Column(
                      key: ValueKey(_type),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_type == SavingPlanType.fixed) ...[
                          TextFormField(
                            controller: _contribution,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration: InputDecoration(
                              labelText: context.t('sp.fieldContribution'),
                              prefixText: '$symbol  ',
                              suffixText: _contribIsAuto &&
                                      _contribution.text.isNotEmpty
                                  ? 'auto'
                                  : null,
                              suffixStyle: TextStyle(
                                  fontSize: 11, color: brand.accentDark),
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
                          TextFormField(
                            controller: _periodsCtrl,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText:
                                  'Number of ${_periodsLabel()}',
                              hintText: 'e.g. 12',
                              suffixText: _periodsIsAuto &&
                                      _periodsCtrl.text.isNotEmpty
                                  ? 'auto'
                                  : null,
                              suffixStyle: TextStyle(
                                  fontSize: 11, color: brand.accentDark),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_type == SavingPlanType.daysChallenge) ...[
                          TextFormField(
                            controller: _totalDays,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.t('sp.fieldDays'),
                              hintText: '30',
                            ),
                            validator: (v) {
                              if (_type != SavingPlanType.daysChallenge) {
                                return null;
                              }
                              final n = int.tryParse((v ?? '').trim());
                              if (n == null || n <= 0) {
                                return context.t('sp.invalidDays');
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_type == SavingPlanType.weeksChallenge) ...[
                          TextFormField(
                            controller: _totalWeeks,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.t('sp.fieldWeeks'),
                              hintText: '12',
                            ),
                            validator: (v) {
                              if (_type != SavingPlanType.weeksChallenge) {
                                return null;
                              }
                              final n = int.tryParse((v ?? '').trim());
                              if (n == null || n <= 0) {
                                return context.t('sp.invalidWeeks');
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 12),
                        ],
                      ],
                    ),
                  ),
                ),
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
                  onClear: _endDate == null
                      ? null
                      : () => setState(() {
                            _endDate = null;
                            if (_type == SavingPlanType.fixed) {
                              _periodsCtrl.clear();
                              _periodsIsAuto = true;
                            }
                          }),
                  isAutoFilled: _type == SavingPlanType.fixed &&
                      _endDate != null &&
                      (_periodsIsAuto || _contribIsAuto),
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
                TweenAnimationBuilder<Color?>(
                  tween: ColorTween(
                    begin: _success
                        ? Theme.of(context).colorScheme.primary
                        : null,
                    end: _success
                        ? const Color(0xFF34C759)
                        : Theme.of(context).colorScheme.primary,
                  ),
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  builder: (ctx, color, _) => FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: color),
                    onPressed: (_saving || _success) ? null : _save,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: _success
                          ? const Icon(
                              CupertinoIcons.checkmark_alt,
                              size: 20,
                              color: Colors.white,
                              key: ValueKey('success'),
                            )
                          : _saving
                              ? const SizedBox(
                                  key: ValueKey('loading'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  _isEdit
                                      ? context.t('common.update')
                                      : context.t('common.save'),
                                  key: const ValueKey('label'),
                                ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Type selector ────────────────────────────────────────────

  Widget _typeSelector(BrandColors brand) {
    final selectedFg = foregroundOn(brand.accentDark);
    final types = <(SavingPlanType, String, IconData)>[
      (SavingPlanType.fixed, context.t('sp.typeFixed'),
          CupertinoIcons.calendar_badge_plus),
      (SavingPlanType.flexible, context.t('sp.typeFlexible'),
          CupertinoIcons.drop_fill),
    ];
    final selectedIdx = types.indexWhere((t) => t.$1 == _type);

    double selectorW = 0;
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (selectorW == 0) return;
        const padding = 4.0;
        const tabCount = 2;
        final segW = (selectorW - padding * 2) / tabCount;
        final newIdx =
            ((details.localPosition.dx - padding) / segW).floor().clamp(0, tabCount - 1);
        const tabTypes = [SavingPlanType.fixed, SavingPlanType.flexible];
        final newType = tabTypes[newIdx];
        if (newType == _type) return;
        HapticFeedback.selectionClick();
        setState(() {
          _type = newType;
          if (newType == SavingPlanType.fixed) {
            _periodsIsAuto = true;
            _contribIsAuto = false;
            _recalculateFixed();
          }
        });
      },
      behavior: HitTestBehavior.translucent,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          selectorW = constraints.maxWidth;
          final segW = (constraints.maxWidth - 8) / 2;
          return Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(14),
            ),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              if (selectedIdx >= 0)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  left: selectedIdx * segW,
                  top: 0,
                  bottom: 0,
                  width: segW,
                  child: Container(
                    decoration: BoxDecoration(
                      color: brand.accentDark,
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (final (type, label, icon) in types)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (_type == type) return;
                          FocusScope.of(context).unfocus();
                          setState(() => _type = type);
                          // Reset auto-fill when switching type
                          if (type == SavingPlanType.fixed) {
                            _periodsIsAuto = true;
                            _contribIsAuto = false;
                            _recalculateFixed();
                          }
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: const Duration(milliseconds: 200),
                                child: Icon(
                                  icon,
                                  key: ValueKey(type == _type),
                                  size: 18,
                                  color: type == _type
                                      ? selectedFg
                                      : brand.ink,
                                ),
                              ),
                              const SizedBox(height: 5),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: type == _type
                                      ? selectedFg
                                      : brand.ink,
                                ),
                                child: Text(label),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
      ),
    );
  }

  // ── Frequency picker with sliding pill ───────────────────────

  Widget _frequencyPicker(BrandColors brand) {
    final selectedFg = foregroundOn(brand.accentDark);
    final freqs = <(SavingFrequency, String)>[
      (SavingFrequency.daily, context.t('sp.daily')),
      (SavingFrequency.weekly, context.t('sp.weekly')),
      (SavingFrequency.monthly, context.t('sp.monthly')),
    ];
    final selectedIdx = freqs.indexWhere((f) => f.$1 == _frequency);

    double pickerW = 0;
    return GestureDetector(
      onHorizontalDragUpdate: (details) {
        if (pickerW == 0 || _type != SavingPlanType.fixed) return;
        const padding = 4.0;
        const tabCount = 3;
        final segW = (pickerW - padding * 2) / tabCount;
        final newIdx =
            ((details.localPosition.dx - padding) / segW).floor().clamp(0, tabCount - 1);
        const freqs = [
          SavingFrequency.daily,
          SavingFrequency.weekly,
          SavingFrequency.monthly,
        ];
        final newFreq = freqs[newIdx];
        if (newFreq == _frequency) return;
        HapticFeedback.selectionClick();
        setState(() {
          _frequency = newFreq;
          _recalculateFixed();
        });
      },
      behavior: HitTestBehavior.translucent,
      child: LayoutBuilder(
      builder: (ctx, constraints) {
        pickerW = constraints.maxWidth;
        final segW = (constraints.maxWidth - 8) / 3;
        return Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              if (selectedIdx >= 0)
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  left: selectedIdx * segW,
                  top: 0,
                  bottom: 0,
                  width: segW,
                  child: Container(
                    decoration: BoxDecoration(
                      color: brand.accentDark,
                      borderRadius:
                          BorderRadius.circular(AppRadius.chip - 2),
                    ),
                  ),
                ),
              Row(
                children: [
                  for (final (f, label) in freqs)
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          if (_frequency == f) return;
                          setState(() => _frequency = f);
                          // Update periods label and recompute end date
                          _recalculateFixed();
                        },
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 10),
                          alignment: Alignment.center,
                          child: AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeInOut,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _frequency == f
                                  ? selectedFg
                                  : brand.ink,
                            ),
                            child: Text(label),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
      ),
    );
  }

  // ── Date tile ────────────────────────────────────────────────

  Widget _dateTile({
    required String label,
    required String value,
    required VoidCallback onTap,
    VoidCallback? onClear,
    bool isAutoFilled = false,
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
              Text(
                value,
                style: TextStyle(
                  color: isAutoFilled ? brand.accentDark : brand.inkSoft,
                  fontSize: 14,
                ),
              ),
              if (isAutoFilled) ...[
                const SizedBox(width: 4),
                Text(
                  'auto',
                  style: TextStyle(
                    fontSize: 10,
                    color: brand.accentDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
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
