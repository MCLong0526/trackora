import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/person.dart';
import '../../models/split_bill.dart';
import '../../state/providers.dart';
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
  final String userName;

  const SplitBillScreen({
    super.key,
    required this.totalAmount,
    required this.currencySymbol,
    required this.expenseTitle,
    required this.initialMembers,
    this.initialSplitMode = SplitMode.equally,
    this.userName = '',
  });

  @override
  ConsumerState<SplitBillScreen> createState() => _SplitBillScreenState();
}

class _SplitBillScreenState extends ConsumerState<SplitBillScreen> {
  late List<SplitMember> _members;
  late SplitMode _mode;
  late double _totalAmount;
  final _scrollCtrl = ScrollController();
  String? _justAddedId;

  // Per-member controllers
  final Map<String, TextEditingController> _amountCtrls = {};
  final Map<String, TextEditingController> _percentCtrls = {};
  final Map<String, TextEditingController> _sharesCtrls = {};
  final Map<String, double> _percents = {}; // raw percent values 0-100
  final Map<String, double> _shares = {}; // raw share counts

  /// IDs of members whose value was manually typed — they are never
  /// overwritten when another member's value changes.
  final Set<String> _lockedIds = {};

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
              name: widget.userName.isNotEmpty ? widget.userName : 'You',
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

  /// When user edits one member's amount, lock that member and distribute
  /// the remainder only among unlocked members.
  void _onAmountChanged(SplitMember edited, double newAmount) {
    setState(() {
      _lockedIds.add(edited.id);
      edited.amount = newAmount.clamp(0, double.infinity);
      final free = _members
          .where((m) => m.id != edited.id && !_lockedIds.contains(m.id))
          .toList();
      if (free.isEmpty) return;
      final lockedSum = _members
          .where((m) => _lockedIds.contains(m.id))
          .fold<double>(0, (s, m) => s + m.amount);
      final remaining = (_totalAmount - lockedSum).clamp(0.0, double.infinity);
      final each = remaining / free.length;
      for (final m in free) {
        m.amount = each;
        _amountCtrls[m.id]?.text = each.toStringAsFixed(2);
      }
    });
  }

  void _onPercentChanged(SplitMember edited, double newPct) {
    setState(() {
      _lockedIds.add(edited.id);
      _percents[edited.id] = newPct;
      edited.amount = _totalAmount * (newPct / 100.0);
      final free = _members
          .where((m) => m.id != edited.id && !_lockedIds.contains(m.id))
          .toList();
      if (free.isEmpty) return;
      final lockedSum = _members
          .where((m) => _lockedIds.contains(m.id))
          .fold<double>(0, (s, m) => s + (_percents[m.id] ?? 0));
      final remaining = (100.0 - lockedSum).clamp(0.0, 100.0);
      final each = remaining / free.length;
      for (final m in free) {
        _percents[m.id] = each;
        m.amount = _totalAmount * (each / 100.0);
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
      builder: (_) => _SplitBillAddPersonSheet(
        existingNames: _members.map((m) => m.name.toLowerCase()).toList(),
      ),
    );

    String? name;
    int? colorIdx;
    String? emoji;
    if (result is Person) {
      name = result.name;
      colorIdx = result.colorIndex;
      emoji = result.emoji;
    } else if (result is Map<String, dynamic>) {
      name = result['name'] as String?;
      colorIdx = result['colorIndex'] as int?;
      emoji = result['emoji'] as String?;
    }
    if (name == null || name.trim().isEmpty) return;

    // Prevent duplicate members
    if (_members.any((m) => m.name.toLowerCase() == name!.toLowerCase())) {
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() {
      final newId = DateTime.now().microsecondsSinceEpoch.toString();
      _justAddedId = newId;
      _members.add(
        SplitMember(
          id: newId,
          name: name!,
          colorIndex: colorIdx ?? personColorIndex(name),
          emoji: emoji,
          amount: 0,
        ),
      );
      _lockedIds.clear();
      final n = _members.length;
      final each = _totalAmount / n;
      for (final m in _members) {
        m.amount = each;
        _percents[m.id] = 100.0 / n;
        _shares[m.id] = 1.0;
        _amountCtrls[m.id]?.text = each.toStringAsFixed(2);
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
      _lockedIds.remove(m.id);
      _members.remove(m);
      _lockedIds.clear();
      final n = _members.length;
      if (n > 0) {
        final each = _totalAmount / n;
        for (final member in _members) {
          member.amount = each;
          _percents[member.id] = 100.0 / n;
          _shares[member.id] = 1.0;
          _amountCtrls[member.id]?.text = each.toStringAsFixed(2);
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
            return Padding(
              padding: const EdgeInsets.only(right: 20),
              child: isPayer ? _payerCard(m) : _nonPayerAvatarWithActions(m),
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
              emoji: m.emoji,
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

  Widget _nonPayerAvatarWithActions(SplitMember m) {
    return Column(
      children: [
        SizedBox(
          width: 58,
          height: 58,
          child: Stack(
            children: [
              Positioned(
                left: 4,
                top: 4,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    _setPayer(m);
                  },
                  child: PersonAvatar(
                    name: m.name,
                    colorIndex: m.colorIndex,
                    emoji: m.emoji,
                    size: 50,
                  ),
                ),
              ),
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    _removeMember(m);
                  },
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      CupertinoIcons.xmark,
                      size: 10,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
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
                  _lockedIds.clear();
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
              _MemberEntranceItem(
                key: ValueKey(_members[i].id),
                animate: _members[i].id == _justAddedId,
                child: _memberRow(_members[i], brand),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _memberRow(SplitMember m, BrandColors brand) {
    final isYou = m.isPayer;

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
              emoji: m.emoji,
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
                        m.name,
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
            _onAmountChanged(m, val);
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

// ── Animated entrance wrapper for new member rows ─────────────────────────────

class _MemberEntranceItem extends StatefulWidget {
  final bool animate;
  final Widget child;
  const _MemberEntranceItem({
    required this.animate,
    required this.child,
    super.key,
  });

  @override
  State<_MemberEntranceItem> createState() => _MemberEntranceItemState();
}

class _MemberEntranceItemState extends State<_MemberEntranceItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    if (widget.animate) {
      _ctrl.forward();
    } else {
      _ctrl.value = 1.0;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _slide, child: widget.child),
    );
  }
}

// ── Add person sheet with save-to-contacts toggle ─────────────────────────────

class _SplitBillAddPersonSheet extends ConsumerStatefulWidget {
  final List<String> existingNames;
  const _SplitBillAddPersonSheet({required this.existingNames});

  @override
  ConsumerState<_SplitBillAddPersonSheet> createState() =>
      _SplitBillAddPersonSheetState();
}

class _SplitBillAddPersonSheetState
    extends ConsumerState<_SplitBillAddPersonSheet> {
  final _nameCtrl = TextEditingController();
  final _searchCtrl = TextEditingController();
  bool _saveToContacts = false;
  bool _saving = false;
  bool _showNew = true; // toggle between new-name input and saved contacts

  @override
  void dispose() {
    _nameCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    if (widget.existingNames.contains(name.toLowerCase())) return;

    final colorIdx = personColorIndex(name);

    if (_saveToContacts) {
      setState(() => _saving = true);
      final user = ref.read(authStateProvider).valueOrNull;
      if (user != null) {
        try {
          final now = DateTime.now();
          final person = Person(
            id: DateTime.now().microsecondsSinceEpoch.toString(),
            name: name,
            type: PersonType.friend,
            colorIndex: colorIdx,
            createdAt: now,
            updatedAt: now,
          );
          await ref.read(personServiceProvider).add(user.uid, person);
          if (mounted) Navigator.pop(context, person);
        } catch (_) {
          if (mounted) setState(() => _saving = false);
        }
        return;
      }
      setState(() => _saving = false);
    }

    if (mounted) {
      Navigator.pop(context, {'name': name, 'colorIndex': colorIdx});
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final async = ref.watch(peopleProvider);
    final query = _searchCtrl.text.trim().toLowerCase();

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Container(
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: brand.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Text(
                    'Add Person',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                      letterSpacing: -0.374,
                    ),
                  ),
                  const Spacer(),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(context),
                    child: Text('Cancel', style: TextStyle(color: brand.inkSoft)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Tab row: New / From Contacts
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final pillW = constraints.maxWidth / 2;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeInOutCubic,
                          left: _showNew ? 0 : pillW,
                          top: 0,
                          bottom: 0,
                          width: pillW,
                          child: Container(
                            decoration: BoxDecoration(
                              color: brand.background,
                              borderRadius: BorderRadius.circular(AppRadius.chip - 2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 6,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _tabChip('New', _showNew, brand, () => setState(() => _showNew = true)),
                            _tabChip('From Contacts', !_showNew, brand, () => setState(() => _showNew = false)),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: _showNew
                    ? _newTabBody(brand)
                    : _contactsTabBody(brand, async, query),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _newTabBody(BrandColors brand) {
    return SizedBox(
      key: const ValueKey('new'),
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CupertinoTextField(
              controller: _nameCtrl,
              placeholder: 'Name',
              autofocus: false,
              textCapitalization: TextCapitalization.words,
              onChanged: (_) => setState(() {}),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(AppRadius.field),
              ),
              child: Row(
                children: [
                  TweenAnimationBuilder<Color?>(
                    duration: const Duration(milliseconds: 250),
                    tween: ColorTween(
                      begin: brand.inkSoft,
                      end: _saveToContacts ? brand.accentDark : brand.inkSoft,
                    ),
                    builder: (_, color, child) => Icon(
                      CupertinoIcons.person_crop_circle_fill,
                      size: 20,
                      color: color ?? brand.inkSoft,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Save to my contacts',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: brand.ink,
                      ),
                    ),
                  ),
                  CupertinoSwitch(
                    value: _saveToContacts,
                    activeTrackColor: brand.accentDark,
                    onChanged: (v) => setState(() => _saveToContacts = v),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GestureDetector(
              onTap: _saving || _nameCtrl.text.trim().isEmpty
                  ? null
                  : _submit,
              child: Container(
                height: 52,
                decoration: BoxDecoration(
                  color: _nameCtrl.text.trim().isEmpty
                      ? brand.ink.withValues(alpha: 0.2)
                      : brand.accentDark,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                alignment: Alignment.center,
                child: _saving
                    ? const CupertinoActivityIndicator()
                    : Text(
                        _saveToContacts
                            ? 'Add & Save to Contacts'
                            : 'Add Person',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _nameCtrl.text.trim().isEmpty
                              ? brand.inkSoft
                              : brand.background,
                        ),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _contactsTabBody(
    BrandColors brand,
    AsyncValue<List<Person>> async,
    String query,
  ) {
    return SizedBox(
      key: const ValueKey('contacts'),
      width: double.infinity,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CupertinoSearchTextField(
              controller: _searchCtrl,
              placeholder: 'Search contacts…',
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 8),
          async.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: CupertinoActivityIndicator(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Error: $e'),
            ),
            data: (all) {
              final filtered = query.isEmpty
                  ? all
                  : all
                      .where((p) =>
                          p.name.toLowerCase().contains(query) ||
                          (p.phone?.toLowerCase().contains(query) ?? false))
                      .toList();
              if (filtered.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  child: Text(
                    all.isEmpty ? 'No saved contacts yet.' : 'No matches.',
                    style: TextStyle(color: brand.inkSoft, fontSize: 13),
                  ),
                );
              }
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.38,
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  itemCount: filtered.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 6),
                  itemBuilder: (ctx, i) {
                    final p = filtered[i];
                    final alreadyAdded =
                        widget.existingNames.contains(p.name.toLowerCase());
                    return GestureDetector(
                      onTap: alreadyAdded
                          ? null
                          : () => Navigator.pop(context, p),
                      child: Opacity(
                        opacity: alreadyAdded ? 0.4 : 1.0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: brand.surface,
                            borderRadius:
                                BorderRadius.circular(AppRadius.card),
                          ),
                          child: Row(
                            children: [
                              PersonAvatar(
                                name: p.name,
                                colorIndex: p.colorIndex,
                                emoji: p.emoji,
                                size: 40,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.name,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: brand.ink,
                                      ),
                                    ),
                                    if (p.phone != null)
                                      Text(p.phone!,
                                          style: TextStyle(
                                              fontSize: 11,
                                              color: brand.inkSoft)),
                                  ],
                                ),
                              ),
                              if (alreadyAdded)
                                Text('Added',
                                    style: TextStyle(
                                        fontSize: 11, color: brand.inkSoft)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _tabChip(
      String label, bool selected, BrandColors brand, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              style: TextStyle(
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? brand.ink : brand.inkSoft,
              ),
              child: Text(label),
            ),
          ),
        ),
      ),
    );
  }
}
