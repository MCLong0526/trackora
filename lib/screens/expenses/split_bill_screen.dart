import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/person.dart';
import '../../models/split_bill.dart';
import '../../screens/people/people_screen.dart';
import '../../theme/app_theme.dart';
import '../../widgets/person_avatar.dart';

// ── Design tokens (DESIGN.md aligned) ─────────────────────────────────────────
const _kPurple = Color(0xFF6B40A8);
const _kPurpleSoft = Color(0xFFF0EAFA); // parchment-equivalent for purple
const _kInk = Color(0xFF1D1D1F); // near-black ink
const _kInkMuted = Color(0xFF6E6E73); // muted / secondary text
const _kCanvas = Color(0xFFFFFFFF); // pure white canvas
const _kParchment = Color(0xFFF5F5F7); // apple parchment surface
const _kHairline = Color(0xFFE0E0E0); // hairline border
const _kRoundedLg = 18.0; // {rounded.lg} card radius
const _kRoundedSm = 8.0; // {rounded.sm} utility radius
const _kRoundedPill = 999.0; // {rounded.pill}

// Avatar colors now use brand pastels for visual consistency with the people list.

/// Result returned when user taps "Save & generate bill".
class SplitBillResult {
  final List<SplitMember> members;
  final SplitMode splitMode;
  final double totalAmount;

  const SplitBillResult({
    required this.members,
    required this.splitMode,
    required this.totalAmount,
  });
}

/// Full-screen sheet for configuring a split bill.
class SplitBillScreen extends ConsumerStatefulWidget {
  final double totalAmount;
  final String currencySymbol;
  final String expenseTitle;
  final List<SplitMember> initialMembers;
  final SplitMode initialSplitMode;

  const SplitBillScreen({
    super.key,
    required this.totalAmount,
    required this.currencySymbol,
    required this.expenseTitle,
    required this.initialMembers,
    this.initialSplitMode = SplitMode.equally,
  });

  @override
  ConsumerState<SplitBillScreen> createState() => _SplitBillScreenState();
}

class _SplitBillScreenState extends ConsumerState<SplitBillScreen> {
  late List<SplitMember> _members;
  late SplitMode _mode;
  late double _totalAmount;
  final _scrollCtrl = ScrollController();

  // Per-member controllers
  final Map<String, TextEditingController> _amountCtrls = {};
  final Map<String, TextEditingController> _percentCtrls = {};
  final Map<String, TextEditingController> _sharesCtrls = {};
  final Map<String, double> _percents = {}; // raw percent values 0-100
  final Map<String, double> _shares = {}; // raw share counts

  @override
  void initState() {
    super.initState();
    _mode = widget.initialSplitMode;
    _totalAmount = widget.totalAmount;
    _members = widget.initialMembers.isNotEmpty
        ? widget.initialMembers.map((m) => m.copyWith()).toList()
        : [
            SplitMember(
              id: DateTime.now().microsecondsSinceEpoch.toString(),
              name: 'You',
              colorIndex: 0,
              amount: _totalAmount,
              isPayer: true,
            ),
          ];
    if (_members.isNotEmpty && !_members.any((m) => m.isPayer)) {
      _members.first.isPayer = true;
    }
    _initRawValues();
    _recalculate();
  }

  void _initRawValues() {
    final n = _members.length;
    final amountTotal = _totalAmount > 0
        ? _totalAmount
        : _members.fold<double>(0, (s, m) => s + m.amount);
    final defaultPercent = n > 0 ? 100.0 / n : 100.0;
    for (final m in _members) {
      final derivedPercent = amountTotal > 0
          ? (m.amount / amountTotal * 100.0).clamp(0.0, 100.0).toDouble()
          : defaultPercent;
      _percents[m.id] = derivedPercent;
      _shares[m.id] = m.amount > 0 ? m.amount : 1.0;
    }
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    for (final c in _amountCtrls.values) {
      c.dispose();
    }
    for (final c in _percentCtrls.values) {
      c.dispose();
    }
    for (final c in _sharesCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ─── Recalculation ────────────────────────────────────────────────────────────

  void _recalculate() {
    if (_members.isEmpty) return;
    final n = _members.length;

    switch (_mode) {
      case SplitMode.equally:
        final each = _totalAmount / n;
        for (final m in _members) {
          m.amount = each;
          _percents[m.id] = 100.0 / n;
          _shares[m.id] = 1.0;
        }

      case SplitMode.amount:
        for (final m in _members) {
          if (!_amountCtrls.containsKey(m.id)) {
            final seed = m.amount > 0 ? m.amount : _totalAmount / n;
            final val = seed.toStringAsFixed(2);
            _amountCtrls[m.id] = TextEditingController(text: val);
            m.amount = double.tryParse(val) ?? 0;
          }
        }

      case SplitMode.percent:
        for (final m in _members) {
          _percents.putIfAbsent(m.id, () => 100.0 / n);
          final p = _percents[m.id]!;
          if (!_percentCtrls.containsKey(m.id)) {
            _percentCtrls[m.id] = TextEditingController(
              text: p.toStringAsFixed(1),
            );
          }
          m.amount = _totalAmount * (p / 100.0);
        }

      case SplitMode.shares:
        for (final m in _members) {
          _shares.putIfAbsent(m.id, () => 1.0);
          if (!_sharesCtrls.containsKey(m.id)) {
            _sharesCtrls[m.id] = TextEditingController(
              text: (_shares[m.id]!).toStringAsFixed(0),
            );
          }
        }
        final totalShares = _shares.values.fold<double>(0, (s, v) => s + v);
        for (final m in _members) {
          final ms = _shares[m.id] ?? 1.0;
          m.amount = totalShares > 0 ? _totalAmount * (ms / totalShares) : 0;
        }
    }
  }

  /// When user edits one member's percent, distribute the remainder equally
  /// among all other members and refresh their controllers.
  void _onPercentChanged(SplitMember edited, double newPct) {
    setState(() {
      _percents[edited.id] = newPct;
      edited.amount = _totalAmount * (newPct / 100.0);

      final others = _members.where((m) => m.id != edited.id).toList();
      if (others.isEmpty) return;
      final remaining = (100.0 - newPct).clamp(0.0, 100.0);
      final each = remaining / others.length;
      for (final m in others) {
        _percents[m.id] = each;
        m.amount = _totalAmount * (each / 100.0);
        // Refresh controller text
        _percentCtrls[m.id]?.text = each.toStringAsFixed(1);
      }
    });
  }

  /// When user edits shares, recompute all amounts from ratio.
  void _onSharesChanged(SplitMember edited, double newShares) {
    setState(() {
      _shares[edited.id] = newShares;
      final total = _shares.values.fold<double>(0, (s, v) => s + v);
      for (final m in _members) {
        final ms = _shares[m.id] ?? 1.0;
        m.amount = total > 0 ? _totalAmount * (ms / total) : 0;
      }
    });
  }

  // ─── Member management ────────────────────────────────────────────────────────

  void _addPerson() async {
    final result = await showModalBottomSheet<dynamic>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PersonOrNamePickerSheet(),
    );

    String? name;
    int? colorIdx;
    if (result is Person) {
      name = result.name;
      colorIdx = result.colorIndex;
    } else if (result is String && result.trim().isNotEmpty) {
      name = result.trim();
      colorIdx = personColorIndex(name);
    }
    if (name == null) return;

    // Prevent duplicate members
    if (_members.any((m) => m.name.toLowerCase() == name!.toLowerCase())) {
      return;
    }

    setState(() {
      final newId = DateTime.now().microsecondsSinceEpoch.toString();
      _members.add(
        SplitMember(
          id: newId,
          name: name!,
          colorIndex: colorIdx ?? personColorIndex(name),
          amount: 0,
        ),
      );
      final n = _members.length;
      for (final m in _members) {
        _percents[m.id] = 100.0 / n;
        _shares[m.id] = 1.0;
        _percentCtrls[m.id]?.text = (100.0 / n).toStringAsFixed(1);
        _sharesCtrls[m.id]?.text = '1';
      }
      _recalculate();
    });
  }

  void _removeMember(SplitMember m) {
    if (m.isPayer) return;
    setState(() {
      _amountCtrls.remove(m.id)?.dispose();
      _percentCtrls.remove(m.id)?.dispose();
      _sharesCtrls.remove(m.id)?.dispose();
      _percents.remove(m.id);
      _shares.remove(m.id);
      _members.remove(m);
      // Re-equalise after removal
      final n = _members.length;
      if (n > 0) {
        for (final member in _members) {
          _percents[member.id] = 100.0 / n;
          _shares[member.id] = 1.0;
          _percentCtrls[member.id]?.text = (100.0 / n).toStringAsFixed(1);
          _sharesCtrls[member.id]?.text = '1';
        }
      }
      _recalculate();
    });
  }

  void _setPayer(SplitMember m) {
    setState(() {
      for (final member in _members) {
        member.isPayer = member.id == m.id;
      }
    });
  }

  // ─── Edit total amount ────────────────────────────────────────────────────────

  void _editTotalAmount() async {
    final ctrl = TextEditingController(text: _totalAmount.toStringAsFixed(2));
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Edit total amount'),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            autofocus: false,
            textInputAction: TextInputAction.done,
            prefix: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                widget.currencySymbol,
                style: const TextStyle(color: _kInkMuted),
              ),
            ),
          ),
        ),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              final v = double.tryParse(ctrl.text);
              if (v != null && v > 0) {
                setState(() {
                  _totalAmount = v;
                  // Clear all controllers so recalculate seeds fresh values
                  for (final c in _amountCtrls.values) {
                    c.dispose();
                  }
                  _amountCtrls.clear();
                  for (final c in _percentCtrls.values) {
                    c.dispose();
                  }
                  _percentCtrls.clear();
                  for (final c in _sharesCtrls.values) {
                    c.dispose();
                  }
                  _sharesCtrls.clear();
                  _recalculate();
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  // ─── Computed values ──────────────────────────────────────────────────────────

  double get _payerShare =>
      _members.where((m) => m.isPayer).firstOrNull?.amount ?? 0;

  double get _owedAmount => _totalAmount - _payerShare;

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final keyboardH = MediaQuery.of(context).viewInsets.bottom;
    final canvasColor = isDark ? brand.surface : _kCanvas;
    final parchmentColor = isDark ? brand.background : _kParchment;

    return Scaffold(
      backgroundColor: parchmentColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(brand, canvasColor),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                behavior: HitTestBehavior.translucent,
                child: SingleChildScrollView(
                  controller: _scrollCtrl,
                  // Add keyboard height so nothing hides behind keyboard
                  padding: EdgeInsets.fromLTRB(20, 0, 20, keyboardH + 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 20),
                      _heroCard(isDark),
                      const SizedBox(height: 28),
                      _sectionLabel('PAID BY'),
                      const SizedBox(height: 12),
                      _paidByCard(canvasColor),
                      const SizedBox(height: 28),
                      _splitBetweenHeader(),
                      const SizedBox(height: 12),
                      _modeTabBar(parchmentColor, canvasColor),
                      const SizedBox(height: 12),
                      _memberList(canvasColor, brand),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _saveButton(keyboardH),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────────

  Widget _buildHeader(BrandColors brand, Color canvasColor) {
    return Container(
      color: canvasColor,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _kParchment,
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.xmark, size: 16, color: _kInk),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Split bill',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    color: _kInk,
                    letterSpacing: -0.374,
                  ),
                ),
                Text(
                  '${widget.expenseTitle.isEmpty ? "Expense" : widget.expenseTitle} · '
                  '${widget.currencySymbol} ${_totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _kInkMuted,
                    letterSpacing: -0.12,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Hero card ────────────────────────────────────────────────────────────────

  Widget _heroCard(bool isDark) {
    final debtors = _members.where((m) => !m.isPayer).toList();
    final countOwing = debtors.length;
    final amountEach = countOwing > 0 ? _owedAmount / countOwing : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: _kPurpleSoft,
        borderRadius: BorderRadius.circular(_kRoundedLg),
        border: Border.all(color: _kPurple.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Total bill row — prominently editable
          GestureDetector(
            onTap: _editTotalAmount,
            child: Row(
              children: [
                const Text(
                  'TOTAL BILL',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _kPurple,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '${widget.currencySymbol} ${_totalAmount.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _kPurple,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: _kPurple.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(_kRoundedPill),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.pencil,
                        size: 10,
                        color: _kPurple,
                      ),
                      SizedBox(width: 3),
                      Text(
                        'Edit',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _kPurple,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const Text(
            "YOU'LL BE OWED",
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: _kPurple,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                widget.currencySymbol,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                  color: _kPurple,
                  letterSpacing: -0.374,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _owedAmount.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 44,
                  fontWeight: FontWeight.w600,
                  color: _kPurple,
                  letterSpacing: -1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            countOwing > 0
                ? '$countOwing ${countOwing == 1 ? "mate owes" : "mates owe"} you '
                      '${widget.currencySymbol} ${amountEach.toStringAsFixed(2)} each'
                : 'Add mates to split the bill',
            style: const TextStyle(
              fontSize: 14,
              color: _kPurple,
              letterSpacing: -0.224,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Section label ────────────────────────────────────────────────────────────

  Widget _sectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: _kInkMuted,
        letterSpacing: 1,
      ),
    );
  }

  // ─── Paid by card ─────────────────────────────────────────────────────────────

  Widget _paidByCard(Color canvasColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: canvasColor,
        borderRadius: BorderRadius.circular(_kRoundedLg),
        border: Border.all(color: _kHairline),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _members.map((m) {
            final isPayer = m.isPayer;
            return GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _setPayer(m);
              },
              child: Padding(
                padding: const EdgeInsets.only(right: 20),
                child: isPayer ? _payerCard(m) : _nonPayerAvatar(m),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _payerCard(SplitMember m) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: _kPurpleSoft,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kPurple, width: 2),
          ),
          child: Center(
            child: PersonAvatar(
              name: m.name,
              colorIndex: m.colorIndex,
              size: 50,
            ),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'You',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _kPurple,
            letterSpacing: -0.12,
          ),
        ),
      ],
    );
  }

  Widget _nonPayerAvatar(SplitMember m) {
    return Column(
      children: [
        PersonAvatar(
          name: m.name,
          colorIndex: m.colorIndex,
          size: 50,
        ),
        const SizedBox(height: 6),
        Text(
          m.name.split(' ').first,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _kInkMuted,
            letterSpacing: -0.12,
          ),
        ),
      ],
    );
  }

  // ─── Split between header ─────────────────────────────────────────────────────

  Widget _splitBetweenHeader() {
    return Row(
      children: [
        Text(
          'SPLIT BETWEEN · ${_members.length}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _kInkMuted,
            letterSpacing: 1,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: _addPerson,
          child: const Row(
            children: [
              Icon(CupertinoIcons.plus, size: 14, color: _kPurple),
              SizedBox(width: 4),
              Text(
                'Add person',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: _kPurple,
                  letterSpacing: -0.224,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Mode tab bar ─────────────────────────────────────────────────────────────

  Widget _modeTabBar(Color parchmentColor, Color canvasColor) {
    final modes = SplitMode.values;
    final labels = ['Equally', 'Amount', 'Percent', 'Shares'];
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: parchmentColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kHairline),
      ),
      child: Row(
        children: List.generate(modes.length, (i) {
          final isSelected = modes[i] == _mode;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                FocusScope.of(context).unfocus();
                setState(() {
                  _mode = modes[i];
                  _recalculate();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isSelected ? canvasColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 6,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isSelected ? _kPurple : _kInkMuted,
                      letterSpacing: -0.12,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ─── Member list ──────────────────────────────────────────────────────────────

  Widget _memberList(Color canvasColor, BrandColors brand) {
    final hairline = Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 62),
      color: _kHairline,
    );
    return Container(
      decoration: BoxDecoration(
        color: canvasColor,
        borderRadius: BorderRadius.circular(_kRoundedLg),
        border: Border.all(color: _kHairline),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kRoundedLg),
        child: Column(
          children: [
            for (int i = 0; i < _members.length; i++) ...[
              if (i > 0) hairline,
              _memberRow(_members[i], brand),
            ],
          ],
        ),
      ),
    );
  }

  Widget _memberRow(SplitMember m, BrandColors brand) {
    final isYou = m.name == 'You' && m.isPayer;

    return Dismissible(
      key: ValueKey(m.id),
      direction: m.isPayer
          ? DismissDirection.none
          : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.withValues(alpha: 0.08),
        child: const Icon(CupertinoIcons.trash, color: Colors.red, size: 18),
      ),
      onDismissed: (_) => _removeMember(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            PersonAvatar(
              name: m.name,
              colorIndex: m.colorIndex,
              size: 42,
            ),
            const SizedBox(width: 14),
            // Name + subtitle
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isYou ? 'You' : m.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _kInk,
                          letterSpacing: -0.374,
                        ),
                      ),
                      if (isYou) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _kPurpleSoft,
                            borderRadius: BorderRadius.circular(_kRoundedSm),
                          ),
                          child: const Text(
                            'YOU',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _kPurple,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _subtitleFor(m),
                    style: const TextStyle(
                      fontSize: 12,
                      color: _kInkMuted,
                      letterSpacing: -0.12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Purple filled checkmark
            Container(
              width: 22,
              height: 22,
              decoration: const BoxDecoration(
                color: _kPurple,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.checkmark,
                size: 12,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            // Amount / editable field
            _amountWidget(m),
          ],
        ),
      ),
    );
  }

  String _subtitleFor(SplitMember m) {
    switch (_mode) {
      case SplitMode.equally:
        final pct = _members.isNotEmpty ? 100.0 / _members.length : 0.0;
        return '${pct.toStringAsFixed(0)}% of total';
      case SplitMode.amount:
        return 'Custom amount';
      case SplitMode.percent:
        final pct = _percents[m.id] ?? 0;
        return '${pct.toStringAsFixed(1)}% of total';
      case SplitMode.shares:
        final myShares = _shares[m.id] ?? 1;
        final total = _shares.values.fold<double>(0, (s, v) => s + v);
        final pct = total > 0 ? (myShares / total * 100) : 0.0;
        return '${myShares.toStringAsFixed(0)} share${myShares != 1 ? 's' : ''} · ${pct.toStringAsFixed(0)}%';
    }
  }

  Widget _amountWidget(SplitMember m) {
    switch (_mode) {
      case SplitMode.equally:
        return Text(
          '${widget.currencySymbol} ${m.amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _kInk,
            letterSpacing: -0.374,
          ),
        );

      case SplitMode.amount:
        final ctrl = _amountCtrls.putIfAbsent(
          m.id,
          () => TextEditingController(text: m.amount.toStringAsFixed(2)),
        );
        return _inputField(
          ctrl: ctrl,
          width: 96,
          prefix: widget.currencySymbol,
          onChanged: (v) {
            final val = double.tryParse(v) ?? 0;
            setState(() => m.amount = val);
          },
        );

      case SplitMode.percent:
        final ctrl = _percentCtrls.putIfAbsent(
          m.id,
          () => TextEditingController(
            text: (_percents[m.id] ?? 0).toStringAsFixed(1),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _inputField(
              ctrl: ctrl,
              width: 72,
              suffix: '%',
              onChanged: (v) {
                final val = double.tryParse(v) ?? 0;
                _onPercentChanged(m, val.clamp(0, 100));
              },
            ),
            const SizedBox(height: 3),
            Text(
              '${widget.currencySymbol} ${m.amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 11,
                color: _kInkMuted,
                letterSpacing: -0.12,
              ),
            ),
          ],
        );

      case SplitMode.shares:
        final ctrl = _sharesCtrls.putIfAbsent(
          m.id,
          () => TextEditingController(
            text: (_shares[m.id] ?? 1).toStringAsFixed(0),
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _inputField(
              ctrl: ctrl,
              width: 68,
              suffix: 'sh',
              onChanged: (v) {
                final val = double.tryParse(v) ?? 1;
                _onSharesChanged(m, val.clamp(0.01, 9999));
              },
            ),
            const SizedBox(height: 3),
            Text(
              '${widget.currencySymbol} ${m.amount.toStringAsFixed(2)}',
              style: const TextStyle(
                fontSize: 11,
                color: _kInkMuted,
                letterSpacing: -0.12,
              ),
            ),
          ],
        );
    }
  }

  Widget _inputField({
    required TextEditingController ctrl,
    required double width,
    String? prefix,
    String? suffix,
    required ValueChanged<String> onChanged,
  }) {
    return SizedBox(
      width: width,
      height: 36,
      child: CupertinoTextField(
        controller: ctrl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        textInputAction: TextInputAction.done,
        textAlign: TextAlign.right,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: _kInk,
          letterSpacing: -0.224,
        ),
        decoration: BoxDecoration(
          color: _kParchment,
          borderRadius: BorderRadius.circular(_kRoundedSm),
          border: Border.all(color: _kHairline),
        ),
        padding: EdgeInsets.only(
          left: prefix != null ? 2 : 8,
          right: suffix != null ? 2 : 8,
          top: 8,
          bottom: 8,
        ),
        prefix: prefix != null
            ? Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Text(
                  prefix,
                  style: const TextStyle(fontSize: 12, color: _kInkMuted),
                ),
              )
            : null,
        suffix: suffix != null
            ? Padding(
                padding: const EdgeInsets.only(right: 7),
                child: Text(
                  suffix,
                  style: const TextStyle(fontSize: 12, color: _kInkMuted),
                ),
              )
            : null,
        onChanged: onChanged,
      ),
    );
  }

  // ─── Save button ──────────────────────────────────────────────────────────────

  Widget _saveButton(double keyboardH) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          8,
          20,
          keyboardH > 0 ? keyboardH + 8 : 20,
        ),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            FocusScope.of(context).unfocus();
            Navigator.pop(
              context,
              SplitBillResult(
                members: _members,
                splitMode: _mode,
                totalAmount: _totalAmount,
              ),
            );
          },
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: _kInk,
              borderRadius: BorderRadius.circular(_kRoundedPill),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  CupertinoIcons.checkmark_circle_fill,
                  color: Colors.white,
                  size: 20,
                ),
                SizedBox(width: 10),
                Text(
                  'Save & generate bill',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                    letterSpacing: -0.374,
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
