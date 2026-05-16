import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/split_bill.dart';
import '../../theme/app_theme.dart';

const _kPurple = Color(0xFF6B40A8);
const _kPurpleLight = Color(0xFFF0EAFA);

const _kAvatarColors = [
  Color(0xFF6B40A8),
  Color(0xFF2A82B4),
  Color(0xFFC0833A),
  Color(0xFF2A8C52),
  Color(0xFFB23A4A),
  Color(0xFFE8820E),
  Color(0xFF5C6ABE),
];

Color _avatarColor(int colorIndex) =>
    _kAvatarColors[colorIndex % _kAvatarColors.length];

/// Result returned when user taps "Save & generate bill".
class SplitBillResult {
  final List<SplitMember> members;
  final SplitMode splitMode;

  const SplitBillResult({required this.members, required this.splitMode});
}

/// Full-screen sheet for configuring a split bill.
class SplitBillScreen extends StatefulWidget {
  final double totalAmount;
  final String currencySymbol;
  final String expenseTitle;
  final List<SplitMember> initialMembers;

  const SplitBillScreen({
    super.key,
    required this.totalAmount,
    required this.currencySymbol,
    required this.expenseTitle,
    required this.initialMembers,
  });

  @override
  State<SplitBillScreen> createState() => _SplitBillScreenState();
}

class _SplitBillScreenState extends State<SplitBillScreen> {
  late List<SplitMember> _members;
  SplitMode _mode = SplitMode.equally;

  // Controllers for Amount mode — keyed by member id
  final Map<String, TextEditingController> _amountCtrls = {};
  // Controllers for Percent mode — keyed by member id
  final Map<String, TextEditingController> _percentCtrls = {};
  // Controllers for Shares mode — keyed by member id (stores share count as string)
  final Map<String, TextEditingController> _sharesCtrls = {};
  // Raw percent values per member (0-100)
  final Map<String, double> _percents = {};
  // Raw shares per member (integer-like)
  final Map<String, double> _shares = {};

  @override
  void initState() {
    super.initState();
    if (widget.initialMembers.isEmpty) {
      _members = [
        SplitMember(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          name: 'You',
          colorIndex: 0,
          amount: widget.totalAmount,
          isPayer: true,
        ),
      ];
    } else {
      _members = List.from(widget.initialMembers);
    }
    _initControllers();
    _recalculate();
  }

  void _initControllers() {
    for (final m in _members) {
      _percents[m.id] = _members.isNotEmpty ? 100.0 / _members.length : 100.0;
      _shares[m.id] = 1.0;
    }
  }

  @override
  void dispose() {
    for (final c in _amountCtrls.values) c.dispose();
    for (final c in _percentCtrls.values) c.dispose();
    for (final c in _sharesCtrls.values) c.dispose();
    super.dispose();
  }

  // ─── Recalculation ────────────────────────────────────────────────────────────

  void _recalculate() {
    if (_members.isEmpty) return;
    final n = _members.length;

    switch (_mode) {
      case SplitMode.equally:
        final each = widget.totalAmount / n;
        for (final m in _members) {
          m.amount = each;
          _percents[m.id] = 100.0 / n;
          _shares[m.id] = 1.0;
        }

      case SplitMode.amount:
        // Amounts are user-driven; don't overwrite on recalculate unless new member
        for (final m in _members) {
          if (!_amountCtrls.containsKey(m.id)) {
            final init = (widget.totalAmount / n).toStringAsFixed(2);
            _amountCtrls[m.id] = TextEditingController(text: init);
            m.amount = double.tryParse(init) ?? 0;
          }
        }

      case SplitMode.percent:
        // Init percent controllers for new members
        for (final m in _members) {
          _percents.putIfAbsent(m.id, () => 100.0 / n);
          if (!_percentCtrls.containsKey(m.id)) {
            final pct = _percents[m.id]!;
            _percentCtrls[m.id] =
                TextEditingController(text: pct.toStringAsFixed(1));
          }
        }
        // Compute amounts from percents
        for (final m in _members) {
          final pct = _percents[m.id] ?? 0;
          m.amount = widget.totalAmount * (pct / 100.0);
        }

      case SplitMode.shares:
        // Init shares controllers for new members
        for (final m in _members) {
          _shares.putIfAbsent(m.id, () => 1.0);
          if (!_sharesCtrls.containsKey(m.id)) {
            _sharesCtrls[m.id] =
                TextEditingController(text: _shares[m.id]!.toStringAsFixed(0));
          }
        }
        final totalShares =
            _shares.values.fold<double>(0, (s, v) => s + v);
        for (final m in _members) {
          final memberShares = _shares[m.id] ?? 1.0;
          m.amount = totalShares > 0
              ? widget.totalAmount * (memberShares / totalShares)
              : 0;
        }
    }
  }

  // ─── Member management ────────────────────────────────────────────────────────

  void _addPerson() async {
    String name = '';
    await showCupertinoDialog<void>(
      context: context,
      builder: (ctx) {
        return CupertinoAlertDialog(
          title: const Text('Add person'),
          content: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: CupertinoTextField(
              placeholder: 'Name',
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              onChanged: (v) => name = v,
            ),
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final newId = DateTime.now().microsecondsSinceEpoch.toString();
    setState(() {
      _members.add(SplitMember(
        id: newId,
        name: trimmed,
        colorIndex: _members.length % _kAvatarColors.length,
        amount: 0,
      ));
      // Reset percents/shares equally for new member
      final n = _members.length;
      for (final m in _members) {
        _percents[m.id] = 100.0 / n;
        _shares[m.id] = 1.0;
        // Reset controllers so they reflect new equal split
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
      // Re-equalise percents/shares
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

  // ─── Computed values ──────────────────────────────────────────────────────────

  double get _payerShare {
    return _members.where((m) => m.isPayer).firstOrNull?.amount ?? 0;
  }

  double get _owedAmount => widget.totalAmount - _payerShare;

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    return Scaffold(
      backgroundColor: brand.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(brand),
            Expanded(
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                behavior: HitTestBehavior.translucent,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _heroCard(),
                      const SizedBox(height: 24),
                      _paidBySection(brand),
                      const SizedBox(height: 24),
                      _splitBetweenSection(brand),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _saveButton(),
    );
  }

  // ─── Header ───────────────────────────────────────────────────────────────────

  Widget _buildHeader(BrandColors brand) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: brand.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(CupertinoIcons.xmark, size: 17, color: brand.ink),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Split bill',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                Text(
                  '${widget.expenseTitle.isEmpty ? "Expense" : widget.expenseTitle} · ${widget.currencySymbol} ${widget.totalAmount.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 13, color: brand.inkSoft),
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

  Widget _heroCard() {
    final debtors = _members.where((m) => !m.isPayer).toList();
    final countOwing = debtors.length;
    final amountEach =
        countOwing > 0 ? _owedAmount / countOwing : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _kPurpleLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
                  fontWeight: FontWeight.w700,
                  color: _kPurple,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                _owedAmount.toStringAsFixed(2),
                style: const TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w700,
                  color: _kPurple,
                  letterSpacing: -1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            countOwing > 0
                ? 'You paid ${widget.currencySymbol} ${widget.totalAmount.toStringAsFixed(2)} · '
                    '$countOwing ${countOwing == 1 ? "mate owes" : "mates owe"} you '
                    '${widget.currencySymbol} ${amountEach.toStringAsFixed(2)} each'
                : 'You paid ${widget.currencySymbol} ${widget.totalAmount.toStringAsFixed(2)} · add mates to split',
            style: const TextStyle(fontSize: 13, color: _kPurple),
          ),
        ],
      ),
    );
  }

  // ─── Paid by section ─────────────────────────────────────────────────────────

  Widget _paidBySection(BrandColors brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PAID BY',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF8E8E93),
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(16),
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
                    padding: const EdgeInsets.only(right: 16),
                    child: isPayer
                        ? _payerCard(m, brand)
                        : _nonPayerAvatar(m, brand),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ],
    );
  }

  Widget _payerCard(SplitMember m, BrandColors brand) {
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(
            color: _kPurpleLight,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _kPurple, width: 2),
          ),
          child: Center(
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: _avatarColor(m.colorIndex),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  m.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'You',
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: _kPurple,
          ),
        ),
      ],
    );
  }

  Widget _nonPayerAvatar(SplitMember m, BrandColors brand) {
    return Column(
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: _avatarColor(m.colorIndex),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              m.initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          m.name.split(' ').first,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: brand.inkSoft,
          ),
        ),
      ],
    );
  }

  // ─── Split between section ────────────────────────────────────────────────────

  Widget _splitBetweenSection(BrandColors brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'SPLIT BETWEEN · ${_members.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
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
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _kPurple,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _modeTabBar(brand),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.card),
            child: Column(
              children: _buildMemberRows(brand),
            ),
          ),
        ),
      ],
    );
  }

  Widget _modeTabBar(BrandColors brand) {
    final modes = SplitMode.values;
    final labels = ['Equally', 'Amount', 'Percent', 'Shares'];
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(12),
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
                  // Don't clear controllers — preserve user input across tab switches
                  _recalculate();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? _kPurple : brand.inkSoft,
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

  List<Widget> _buildMemberRows(BrandColors brand) {
    final divider = Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 62),
      color: brand.divider,
    );
    final rows = <Widget>[];
    for (int i = 0; i < _members.length; i++) {
      if (i > 0) rows.add(divider);
      rows.add(_memberRow(_members[i], brand));
    }
    return rows;
  }

  Widget _memberRow(SplitMember m, BrandColors brand) {
    final isYou = m.name == 'You' && m.isPayer;

    return Dismissible(
      key: ValueKey(m.id),
      direction:
          m.isPayer ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.withValues(alpha: 0.1),
        child: const Icon(CupertinoIcons.trash, color: Colors.red, size: 20),
      ),
      onDismissed: (_) => _removeMember(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: _avatarColor(m.colorIndex),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  m.initials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
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
                  Row(
                    children: [
                      Text(
                        isYou ? 'You' : m.name,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (isYou) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: _kPurpleLight,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'YOU',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
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
                    style:
                        TextStyle(fontSize: 12, color: brand.inkSoft),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            // Checkmark circle
            Container(
              width: 24,
              height: 24,
              decoration: const BoxDecoration(
                color: _kPurple,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                CupertinoIcons.checkmark,
                size: 13,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 10),
            // Amount / editable field
            _amountWidget(m, brand),
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
        final total =
            _shares.values.fold<double>(0, (s, v) => s + v);
        final pct = total > 0 ? (myShares / total * 100) : 0.0;
        return '${myShares.toStringAsFixed(0)} share${myShares != 1 ? 's' : ''} · ${pct.toStringAsFixed(0)}%';
    }
  }

  Widget _amountWidget(SplitMember m, BrandColors brand) {
    switch (_mode) {
      case SplitMode.equally:
        return Text(
          '${widget.currencySymbol} ${m.amount.toStringAsFixed(2)}',
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600),
        );

      case SplitMode.amount:
        final ctrl = _amountCtrls.putIfAbsent(
          m.id,
          () => TextEditingController(
              text: m.amount.toStringAsFixed(2)),
        );
        return SizedBox(
          width: 90,
          child: CupertinoTextField(
            controller: ctrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            placeholder: '0.00',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w600),
            decoration: BoxDecoration(
              color: _kPurpleLight,
              borderRadius: BorderRadius.circular(8),
            ),
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            prefix: Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                widget.currencySymbol,
                style: TextStyle(fontSize: 13, color: brand.inkSoft),
              ),
            ),
            onChanged: (v) {
              final val = double.tryParse(v) ?? 0;
              setState(() => m.amount = val);
            },
          ),
        );

      case SplitMode.percent:
        final ctrl = _percentCtrls.putIfAbsent(
          m.id,
          () => TextEditingController(
              text: (_percents[m.id] ?? 0).toStringAsFixed(1)),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 72,
              child: CupertinoTextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                placeholder: '0',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                decoration: BoxDecoration(
                  color: _kPurpleLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5),
                suffix: const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Text('%',
                      style: TextStyle(
                          fontSize: 13, color: _kPurple)),
                ),
                onChanged: (v) {
                  final val = double.tryParse(v) ?? 0;
                  setState(() {
                    _percents[m.id] = val;
                    m.amount =
                        widget.totalAmount * (val / 100.0);
                  });
                },
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.currencySymbol} ${m.amount.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 12, color: brand.inkSoft),
            ),
          ],
        );

      case SplitMode.shares:
        final ctrl = _sharesCtrls.putIfAbsent(
          m.id,
          () => TextEditingController(
              text: (_shares[m.id] ?? 1).toStringAsFixed(0)),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(
              width: 72,
              child: CupertinoTextField(
                controller: ctrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.right,
                placeholder: '1',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600),
                decoration: BoxDecoration(
                  color: _kPurpleLight,
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 5),
                suffix: Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text('sh',
                      style: TextStyle(
                          fontSize: 12, color: brand.inkSoft)),
                ),
                onChanged: (v) {
                  final val = double.tryParse(v) ?? 1;
                  setState(() {
                    _shares[m.id] = val;
                    // Recompute all amounts from shares
                    final total = _shares.values
                        .fold<double>(0, (s, v) => s + v);
                    for (final member in _members) {
                      final memberShares =
                          _shares[member.id] ?? 1.0;
                      member.amount = total > 0
                          ? widget.totalAmount *
                              (memberShares / total)
                          : 0;
                    }
                  });
                },
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '${widget.currencySymbol} ${m.amount.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 12, color: brand.inkSoft),
            ),
          ],
        );
    }
  }

  // ─── Save button ──────────────────────────────────────────────────────────────

  Widget _saveButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            FocusScope.of(context).unfocus();
            Navigator.pop(
              context,
              SplitBillResult(members: _members, splitMode: _mode),
            );
          },
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(CupertinoIcons.checkmark_circle_fill,
                    color: Colors.white, size: 20),
                SizedBox(width: 10),
                Text(
                  'Save & generate bill',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.1,
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
