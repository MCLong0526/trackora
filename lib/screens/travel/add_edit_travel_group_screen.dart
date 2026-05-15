import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

class AddEditTravelGroupScreen extends ConsumerStatefulWidget {
  final TravelGroup? group;
  const AddEditTravelGroupScreen({super.key, this.group});

  @override
  ConsumerState<AddEditTravelGroupScreen> createState() =>
      _AddEditTravelGroupScreenState();
}

class _AddEditTravelGroupScreenState
    extends ConsumerState<AddEditTravelGroupScreen> {
  final _nameCtrl = TextEditingController();
  final _currencyCtrl = TextEditingController();
  late DateTime _startDate;
  DateTime? _endDate;
  bool _saving = false;

  bool get _isEdit => widget.group != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameCtrl.text = widget.group!.name;
      _currencyCtrl.text = widget.group!.currency;
      _startDate = widget.group!.startDate;
      _endDate = widget.group!.endDate;
    } else {
      _startDate = DateTime.now();
      _currencyCtrl.text = 'USD';
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _currencyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showCupertinoModalPopup<DateTime?>(
      context: context,
      builder: (ctx) => _DatePickerSheet(
        initial: isStart ? _startDate : (_endDate ?? _startDate),
        minimumDate: isStart ? null : _startDate,
      ),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) {
          _endDate = null;
        }
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final currency = _currencyCtrl.text.trim().toUpperCase();

    if (name.isEmpty) {
      AppToast.show(
        context,
        context.t('travel.saveFailed'),
        type: AppToastType.error,
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user == null) throw Exception('Not authenticated');

      final svc = ref.read(travelGroupServiceProvider);

      if (_isEdit) {
        final updated = widget.group!.copyWith(
          name: name,
          currency: currency.isEmpty ? 'USD' : currency,
          startDate: _startDate,
          endDate: _endDate,
          updatedAt: DateTime.now(),
        );
        await svc.updateGroup(updated);
        if (mounted) {
          AppToast.show(
            context,
            context.t('travel.updated'),
            type: AppToastType.success,
            icon: CupertinoIcons.checkmark_circle_fill,
          );
          Navigator.pop(context);
        }
      } else {
        await svc.createGroup(
          userId: user.uid,
          name: name,
          currency: currency.isEmpty ? 'USD' : currency,
          startDate: _startDate,
          endDate: _endDate,
        );
        if (mounted) {
          AppToast.show(
            context,
            context.t('travel.created'),
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
          _isEdit ? context.t('travel.edit') : context.t('travel.new'),
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
            _SectionLabel(context.t('travel.fieldName').toUpperCase()),
            _InputCard(
              child: TextField(
                controller: _nameCtrl,
                autofocus: !_isEdit,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  hintText: context.t('travel.fieldName'),
                  border: InputBorder.none,
                  hintStyle: TextStyle(color: brand.inkSoft),
                ),
                style: TextStyle(color: brand.ink, fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(context.t('travel.fieldCurrency').toUpperCase()),
            _InputCard(
              child: TextField(
                controller: _currencyCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 10,
                decoration: InputDecoration(
                  hintText: context.t('travel.currencyHint'),
                  border: InputBorder.none,
                  counterText: '',
                  hintStyle: TextStyle(color: brand.inkSoft),
                ),
                style: TextStyle(color: brand.ink, fontSize: 16),
              ),
            ),
            const SizedBox(height: 20),
            _SectionLabel(context.t('travel.tripDates').toUpperCase()),
            Container(
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _DateRow(
                    label: context.t('travel.fieldStartDate'),
                    value: dateFormat.format(_startDate),
                    onTap: () => _pickDate(isStart: true),
                    brand: brand,
                    showDivider: true,
                  ),
                  _DateRow(
                    label: context.t('travel.fieldEndDate'),
                    value: _endDate != null
                        ? dateFormat.format(_endDate!)
                        : '—',
                    onTap: () => _pickDate(isStart: false),
                    brand: brand,
                    showDivider: false,
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

class _DateRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onTap;
  final BrandColors brand;
  final bool showDivider;

  const _DateRow({
    required this.label,
    required this.value,
    required this.onTap,
    required this.brand,
    required this.showDivider,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(fontSize: 16, color: brand.ink),
                ),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    color: const Color(0xFF3478F6),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showDivider)
          Divider(height: 1, color: brand.divider, indent: 16, endIndent: 16),
      ],
    );
  }
}

class _DatePickerSheet extends StatefulWidget {
  final DateTime initial;
  final DateTime? minimumDate;
  const _DatePickerSheet({required this.initial, this.minimumDate});

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
              minimumDate: widget.minimumDate,
              onDateTimeChanged: (dt) => setState(() => _picked = dt),
            ),
          ),
        ],
      ),
    );
  }
}
