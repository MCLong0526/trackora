import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../widgets/app_toast.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _blue = Color(0xFF0066CC);
const _hairline = Color(0xFFE0E0E0);
const _parchment = Color(0xFFF5F5F7);
const _inkColor = Color(0xFF1D1D1F);
const _ink80 = Color(0xFF333333);
const _ink48 = Color(0xFF7A7A7A);
const _ink24 = Color(0x3D1D1D1F);
const _memberBgs = [
  Color(0xFFE8E8EA), Color(0xFFDCDCE0), Color(0xFFD0D0D5),
  Color(0xFFC4C4CA), Color(0xFFB8B8BF),
];

TextStyle _display(double size, {double tracking = -0.374, double lh = 1.10}) =>
    TextStyle(fontSize: size, fontWeight: FontWeight.w600, letterSpacing: tracking, height: lh, color: _inkColor);

TextStyle _body(double size, {int weight = 400, Color? color}) =>
    TextStyle(fontSize: size, fontWeight: FontWeight.values[weight ~/ 100], letterSpacing: -0.374, height: 1.47, color: color ?? _inkColor);

TextStyle _eyebrow({Color color = _ink48}) =>
    TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: color);

// ── Model for a pending traveler (before the group is saved) ──────────────────

class _Traveler {
  final String name;
  final String? email;
  final bool isYou;
  const _Traveler({required this.name, this.email, this.isYou = false});
}

// ── Screen ────────────────────────────────────────────────────────────────────

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
  late String _selectedCurrency;
  late DateTime _startDate;
  DateTime? _endDate;
  bool _saving = false;
  final List<_Traveler> _travelers = [];

  bool get _isEdit => widget.group != null;

  @override
  void initState() {
    super.initState();
    if (_isEdit) {
      _nameCtrl.text = widget.group!.name;
      _selectedCurrency = widget.group!.currency;
      _startDate = widget.group!.startDate;
      _endDate = widget.group!.endDate;
    } else {
      _startDate = DateTime.now();
      _selectedCurrency = 'MYR';
      // Current user is always first
      _travelers.add(const _Traveler(name: 'You', isYou: true));
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    FocusScope.of(context).unfocus();
    final picked = await showCupertinoModalPopup<DateTime?>(
      context: context,
      builder: (ctx) => _DatePickerSheet(
        initial: isStart ? _startDate : (_endDate ?? _startDate),
        minimumDate: isStart ? null : _startDate,
      ),
    );
    _keepKeyboardDown();
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate != null && _endDate!.isBefore(picked)) _endDate = null;
      } else {
        _endDate = picked;
      }
    });
  }

  void _showCurrencyPicker() async {
    FocusScope.of(context).unfocus();
    final picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => _CurrencyPickerSheet(selected: _selectedCurrency),
    );
    if (picked != null) setState(() => _selectedCurrency = picked);
    _keepKeyboardDown();
  }

  // Keep the keyboard down after a popup closes. A modal route restores focus
  // to the previously focused field *after* it pops, so a synchronous unfocus
  // gets overridden — unfocus on the next frame instead so it sticks.
  void _keepKeyboardDown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) FocusScope.of(context).unfocus();
    });
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final currency = _selectedCurrency;
    if (name.isEmpty) {
      AppToast.show(context, context.t('travel.saveFailed'), type: AppToastType.error);
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
          currency: currency,
          startDate: _startDate,
          endDate: _endDate,
          updatedAt: DateTime.now(),
        );
        await svc.updateGroup(updated);
        if (mounted) {
          AppToast.show(context, context.t('travel.updated'),
              type: AppToastType.success, icon: CupertinoIcons.checkmark_circle_fill);
          Navigator.pop(context);
        }
      } else {
        final groupId = await svc.createGroup(
          userId: user.uid,
          name: name,
          currency: currency,
          startDate: _startDate,
          endDate: _endDate,
        );
        final createdGroup = TravelGroup(
          id: groupId, name: name,
          currency: currency,
          startDate: _startDate, endDate: _endDate,
          ownerId: user.uid, memberIds: [user.uid],
          createdAt: DateTime.now(), updatedAt: DateTime.now(),
        );
        // Add creator as first member (avoid duplicate if already added)
        final myName = ref.read(userNameProvider).isNotEmpty
            ? ref.read(userNameProvider)
            : (user.email?.split('@').first ?? 'Me');
        await svc.addMember(
          groupId: groupId,
          group: createdGroup,
          name: myName,
          userId: user.uid,
          email: user.email,
        );
        // Add extra travelers
        for (final t in _travelers.where((t) => !t.isYou)) {
          await svc.addMember(
            groupId: groupId,
            group: createdGroup,
            name: t.name,
            email: t.email,
          );
        }
        if (mounted) {
          AppToast.show(context, context.t('travel.created'),
              type: AppToastType.success, icon: CupertinoIcons.checkmark_circle_fill);
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, context.t('travel.saveFailed'), type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showAddTravelerSheet() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => _AddTravelerSheet(
        onAdd: (name, email) {
          setState(() {
            _travelers.add(_Traveler(name: name, email: email?.isEmpty == true ? null : email));
          });
          Navigator.pop(ctx);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : _parchment;
    final dateFormat = DateFormat('MMM d, yyyy');
    final dayFormat = DateFormat('EEEE');

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Scaffold(
      backgroundColor: bg,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            // ── Pull indicator ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 0),
              child: Center(
                child: Container(
                  width: 40, height: 5,
                  decoration: BoxDecoration(
                    color: _ink24, borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
            ),

            // ── Header row ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 0),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Text('Cancel',
                        style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w400,
                          letterSpacing: -0.2,
                          color: _isEdit ? _blue : _blue,
                        )),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        _isEdit ? context.t('travel.edit') : 'New Trip',
                        style: _body(17, weight: 600),
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox(
                            width: 44,
                            child: CupertinoActivityIndicator(),
                          )
                        : Text(
                            _isEdit ? context.t('common.save') : 'Create',
                            style: TextStyle(
                              fontSize: 17, fontWeight: FontWeight.w600,
                              letterSpacing: -0.2,
                              color: _nameCtrl.text.trim().isEmpty ? _ink24 : _blue,
                            ),
                          ),
                  ),
                ],
              ),
            ),

            // ── Scrollable form ──────────────────────────────────────────
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Hero
                  Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 28),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Plan the trip.\nWe\'ll do the math.',
                          style: _display(40, tracking: -1.0, lh: 1.05),
                        ),
                        const SizedBox(height: 14),
                        Text(
                          'Name it, set the dates, and pick who\'s coming. Everyone on Trackora syncs automatically.',
                          style: _body(17, color: _ink80),
                        ),
                      ],
                    ),
                  ),

                  // ── Trip name ──────────────────────────────────────────
                  _FormSectionLabel('TRIP NAME'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                    child: _FormCard(
                      isDark: isDark,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 4),
                        child: TextField(
                          controller: _nameCtrl,
                          autofocus: false,
                          textCapitalization: TextCapitalization.words,
                          style: _body(17, weight: 600),
                          decoration: InputDecoration(
                            hintText: 'e.g. Bali Trip',
                            hintStyle: _body(17, weight: 600, color: _ink24),
                            border: InputBorder.none,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                    ),
                  ),

                  // ── Currency ───────────────────────────────────────────
                  _FormSectionLabel('CURRENCY'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                    child: _FormCard(
                      isDark: isDark,
                      child: _FormRow(
                        label: 'Currency',
                        value: _selectedCurrency,
                        sub: _kCurrencyNames[_selectedCurrency],
                        isDark: isDark,
                        last: true,
                        onTap: _showCurrencyPicker,
                      ),
                    ),
                  ),

                  // ── Dates ──────────────────────────────────────────────
                  _FormSectionLabel('DATES'),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                    child: _FormCard(
                      isDark: isDark,
                      child: Column(
                        children: [
                          _FormRow(
                            label: 'Start',
                            value: dateFormat.format(_startDate),
                            sub: dayFormat.format(_startDate),
                            isDark: isDark,
                            last: false,
                            onTap: () => _pickDate(isStart: true),
                          ),
                          _FormRow(
                            label: 'End',
                            value: _endDate != null
                                ? dateFormat.format(_endDate!)
                                : 'Optional',
                            sub: _endDate != null ? dayFormat.format(_endDate!) : null,
                            isDark: isDark,
                            last: true,
                            onTap: () => _pickDate(isStart: false),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // ── Travelers ──────────────────────────────────────────
                  if (!_isEdit) ...[
                    _FormSectionLabel(
                      'TRAVELERS · ${_travelers.length}',
                      right: '+ Add',
                      onRight: _showAddTravelerSheet,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                      child: _FormCard(
                        isDark: isDark,
                        child: Column(
                          children: _travelers.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final t = entry.value;
                            return _TravelerRow(
                              traveler: t,
                              index: idx,
                              last: idx == _travelers.length - 1,
                              isDark: isDark,
                              onRemove: t.isYou
                                  ? null
                                  : () => setState(() => _travelers.removeAt(idx)),
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  ],

                  // ── Disclaimer ─────────────────────────────────────────
                  if (!_isEdit)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                      child: Text(
                        'An invite code is generated when you create the trip. Mates not yet on Trackora can join later — their share is held against their name until then.',
                        style: _body(13, color: _ink48),
                      ),
                    ),

                  // ── Create CTA ─────────────────────────────────────────
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 48),
                    child: Center(
                      child: _Pressable(
                        onTap: _saving ? null : _save,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 28, vertical: 13),
                          decoration: BoxDecoration(
                            color: _blue,
                            borderRadius: BorderRadius.circular(9999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_saving)
                                const SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      color: Colors.white, strokeWidth: 2),
                                )
                              else ...[
                                const Icon(CupertinoIcons.checkmark,
                                    color: Colors.white, size: 16),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                _isEdit ? context.t('common.save') : 'Create trip',
                                style: const TextStyle(
                                  fontSize: 17, fontWeight: FontWeight.w400,
                                  letterSpacing: -0.2, color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
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
}

// ── Traveler row ──────────────────────────────────────────────────────────────

class _TravelerRow extends StatelessWidget {
  final _Traveler traveler;
  final int index;
  final bool last;
  final bool isDark;
  final VoidCallback? onRemove;

  const _TravelerRow({
    required this.traveler,
    required this.index,
    required this.last,
    required this.isDark,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final divider = isDark ? const Color(0xFF3A3A3C) : _hairline;
    final bg = _memberBgs[index % _memberBgs.length];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: bg, shape: BoxShape.circle,
                  border: traveler.isYou
                      ? Border.all(color: _blue, width: 1.5)
                      : Border.all(color: _hairline, width: 0.5),
                ),
                child: Center(
                  child: Text(
                    traveler.name[0].toUpperCase(),
                    style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w600, color: _inkColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Name + subtitle
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(traveler.name, style: _body(15, weight: 600)),
                    if (traveler.email != null)
                      Text(traveler.email!, style: _body(13, color: _ink48)),
                    if (traveler.isYou)
                      Text('Trip owner', style: _body(13, color: _ink48)),
                  ],
                ),
              ),
              // Badge
              if (traveler.isYou)
                Text('YOU',
                    style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: _blue, letterSpacing: 0.4,
                    ))
              else if (onRemove != null)
                GestureDetector(
                  onTap: onRemove,
                  child: const Icon(CupertinoIcons.minus_circle,
                      size: 20, color: _ink48),
                ),
            ],
          ),
        ),
        if (!last)
          Divider(height: 1, thickness: 1, color: divider, indent: 20, endIndent: 20),
      ],
    );
  }
}

// ── Reusable form components ──────────────────────────────────────────────────

class _FormSectionLabel extends StatelessWidget {
  final String label;
  final String? right;
  final VoidCallback? onRight;
  const _FormSectionLabel(this.label, {this.right, this.onRight});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: _eyebrow()),
          if (right != null)
            GestureDetector(
              onTap: onRight,
              child: Text(right!,
                  style: const TextStyle(
                    fontSize: 14, color: _blue,
                    fontWeight: FontWeight.w400, letterSpacing: -0.2,
                  )),
            ),
        ],
      ),
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
    final divider = isDark ? const Color(0xFF3A3A3C) : _hairline;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: divider, width: 1),
      ),
      child: child,
    );
  }
}

class _FormRow extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final bool last;
  final bool isDark;
  final VoidCallback onTap;

  const _FormRow({
    required this.label,
    required this.value,
    this.sub,
    required this.last,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final divider = isDark ? const Color(0xFF3A3A3C) : _hairline;
    return Column(
      children: [
        GestureDetector(
          onTap: onTap,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            child: Row(
              children: [
                Text(label, style: _body(15, weight: 500)),
                const Spacer(),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(value, style: _body(15, weight: 600)),
                    if (sub != null)
                      Text(sub!, style: _body(12, color: _ink48)),
                  ],
                ),
                const SizedBox(width: 8),
                const Icon(CupertinoIcons.chevron_right, size: 12, color: _ink24),
              ],
            ),
          ),
        ),
        if (!last)
          Divider(height: 1, thickness: 1, color: divider, indent: 20, endIndent: 20),
      ],
    );
  }
}

// ── Add traveler sheet ────────────────────────────────────────────────────────

class _AddTravelerSheet extends StatefulWidget {
  final void Function(String name, String? email) onAdd;
  const _AddTravelerSheet({required this.onAdd});

  @override
  State<_AddTravelerSheet> createState() => _AddTravelerSheetState();
}

class _AddTravelerSheetState extends State<_AddTravelerSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;

    return Material(
      type: MaterialType.transparency,
      child: Container(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 5,
                  decoration: BoxDecoration(
                    color: _ink24, borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Add Traveler', style: _body(18, weight: 700)),
              const SizedBox(height: 16),
              _SheetField(ctrl: _nameCtrl, hint: 'Name', autofocus: false, isDark: isDark),
              const SizedBox(height: 10),
              _SheetField(
                ctrl: _emailCtrl, hint: 'Email (optional)',
                isDark: isDark,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () {
                    final name = _nameCtrl.text.trim();
                    if (name.isEmpty) return;
                    widget.onAdd(name, _emailCtrl.text.trim());
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: _blue,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Center(
                      child: Text('Add',
                          style: _body(17, weight: 400, color: Colors.white)),
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

class _SheetField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final bool autofocus;
  final bool isDark;
  final TextInputType? keyboardType;

  const _SheetField({
    required this.ctrl,
    required this.hint,
    required this.isDark,
    this.autofocus = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final bg = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
      child: TextField(
        controller: ctrl,
        autofocus: autofocus,
        keyboardType: keyboardType,
        textCapitalization: TextCapitalization.words,
        style: _body(16),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: _body(16, color: _ink48),
          border: InputBorder.none,
        ),
      ),
    );
  }
}

// ── Currency data ─────────────────────────────────────────────────────────────

const _kCurrencies = [
  'MYR', 'USD', 'EUR', 'GBP', 'SGD', 'AUD', 'JPY', 'CNY',
  'HKD', 'KRW', 'TWD', 'THB', 'IDR', 'PHP', 'VND', 'INR',
  'CAD', 'CHF', 'NZD', 'SEK', 'NOK', 'DKK', 'AED', 'SAR',
  'QAR', 'KWD', 'BHD', 'OMR', 'EGP', 'ZAR', 'TRY', 'BRL',
  'MXN', 'PKR', 'BDT', 'LKR', 'NPR',
];

const _kCurrencyNames = {
  'MYR': 'Malaysian Ringgit',    'USD': 'US Dollar',
  'EUR': 'Euro',                 'GBP': 'British Pound',
  'SGD': 'Singapore Dollar',    'AUD': 'Australian Dollar',
  'JPY': 'Japanese Yen',        'CNY': 'Chinese Yuan',
  'HKD': 'Hong Kong Dollar',    'KRW': 'South Korean Won',
  'TWD': 'Taiwan Dollar',       'THB': 'Thai Baht',
  'IDR': 'Indonesian Rupiah',   'PHP': 'Philippine Peso',
  'VND': 'Vietnamese Dong',     'INR': 'Indian Rupee',
  'CAD': 'Canadian Dollar',     'CHF': 'Swiss Franc',
  'NZD': 'New Zealand Dollar',  'SEK': 'Swedish Krona',
  'NOK': 'Norwegian Krone',     'DKK': 'Danish Krone',
  'AED': 'UAE Dirham',          'SAR': 'Saudi Riyal',
  'QAR': 'Qatari Riyal',        'KWD': 'Kuwaiti Dinar',
  'BHD': 'Bahraini Dinar',      'OMR': 'Omani Rial',
  'EGP': 'Egyptian Pound',      'ZAR': 'South African Rand',
  'TRY': 'Turkish Lira',        'BRL': 'Brazilian Real',
  'MXN': 'Mexican Peso',        'PKR': 'Pakistani Rupee',
  'BDT': 'Bangladeshi Taka',    'LKR': 'Sri Lankan Rupee',
  'NPR': 'Nepalese Rupee',
};

// ── Currency picker sheet ─────────────────────────────────────────────────────

class _CurrencyPickerSheet extends StatefulWidget {
  final String selected;
  const _CurrencyPickerSheet({required this.selected});

  @override
  State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  late String _query;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query = '';
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final divider = isDark ? const Color(0xFF3A3A3C) : _hairline;
    final searchBg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);

    final filtered = _query.isEmpty
        ? _kCurrencies
        : _kCurrencies
            .where((c) =>
                c.toLowerCase().contains(_query.toLowerCase()) ||
                (_kCurrencyNames[c] ?? '').toLowerCase().contains(_query.toLowerCase()))
            .toList();

    return Material(
      type: MaterialType.transparency,
      child: Container(
      height: MediaQuery.of(context).size.height * 0.72,
      decoration: BoxDecoration(
        color: surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 40, height: 5,
              decoration: BoxDecoration(color: _ink24, borderRadius: BorderRadius.circular(100)),
            ),
          ),
          const SizedBox(height: 14),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Row(
              children: [
                Text('Currency', style: _body(18, weight: 600)),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(fontSize: 16, color: _blue, letterSpacing: -0.2)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          // Search
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: searchBg, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  const Icon(CupertinoIcons.search, size: 16, color: _ink48),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      style: _body(15),
                      decoration: InputDecoration(
                        hintText: 'Search currency…',
                        hintStyle: _body(15, color: _ink48),
                        border: InputBorder.none,
                        isDense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Divider(height: 1, thickness: 1, color: divider),
          // List
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: filtered.length,
              separatorBuilder: (ctx, i) =>
                  Divider(height: 1, thickness: 1, color: divider, indent: 22, endIndent: 22),
              itemBuilder: (_, i) {
                final code = filtered[i];
                final name = _kCurrencyNames[code] ?? code;
                final isSelected = code == widget.selected;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => Navigator.pop(context, code),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(code, style: _body(16, weight: 600)),
                              Text(name, style: _body(13, color: _ink48)),
                            ],
                          ),
                        ),
                        if (isSelected)
                          const Icon(CupertinoIcons.checkmark, size: 16, color: _blue),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      ),
    );
  }
}

// ── Date picker sheet ──────────────────────────────────────────────────────────

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    return Container(
      height: 320,
      color: surface,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              CupertinoButton(
                child: Text(
                  context.t('common.cancel'),
                  style: const TextStyle(color: _ink48),
                ),
                onPressed: () => Navigator.pop(context),
              ),
              CupertinoButton(
                child: Text(context.t('common.done'),
                    style: const TextStyle(color: _blue)),
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
