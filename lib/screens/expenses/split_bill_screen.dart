import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/split_bill.dart';
import '../../theme/app_theme.dart';

const _kPurple = Color(0xFF6B40A8);

const _kAvatarColors = [
  Color(0xFF6B40A8),
  Color(0xFF1F7A60),
  Color(0xFF2A6FB5),
  Color(0xFFB23A4A),
  Color(0xFFA0801C),
  Color(0xFFE8820E),
  Color(0xFF5C3A9E),
];

Color _avatarColor(int colorIndex) => _kAvatarColors[colorIndex % _kAvatarColors.length];

/// Result returned when user taps "Save & generate bill".
class SplitBillResult {
  final List<SplitMember> members;
  final SplitMode splitMode;

  const SplitBillResult({required this.members, required this.splitMode});
}

/// Full-screen bottom sheet for configuring a split bill.
/// Push with [Navigator.push] or present as modal.
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

  // For Amount/Percent/Shares modes: controllers keyed by member id
  final Map<String, TextEditingController> _customControllers = {};

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
    _recalculate();
  }

  @override
  void dispose() {
    for (final c in _customControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(SplitMember m, String defaultValue) {
    return _customControllers.putIfAbsent(
      m.id,
      () => TextEditingController(text: defaultValue),
    );
  }

  void _recalculate() {
    if (_members.isEmpty) return;
    final n = _members.length;
    switch (_mode) {
      case SplitMode.equally:
        final each = widget.totalAmount / n;
        for (final m in _members) {
          m.amount = each;
        }
      case SplitMode.amount:
        // leave amounts as-is (user sets them)
        break;
      case SplitMode.percent:
        final equalPct = 100.0 / n;
        for (final m in _members) {
          m.amount = widget.totalAmount * (equalPct / 100.0);
        }
      case SplitMode.shares:
        final eachShare = widget.totalAmount / n;
        for (final m in _members) {
          m.amount = eachShare;
        }
    }
  }

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
              onPressed: () {
                Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      _members.add(SplitMember(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        name: trimmed,
        colorIndex: _members.length % _kAvatarColors.length,
        amount: 0,
      ));
      _recalculate();
    });
  }

  void _removeMember(SplitMember m) {
    if (m.isPayer) return; // can't remove payer
    setState(() {
      _customControllers.remove(m.id)?.dispose();
      _members.remove(m);
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

  double get _payerShare {
    final payer = _members.where((m) => m.isPayer).firstOrNull;
    return payer?.amount ?? 0;
  }

  double get _owedAmount => widget.totalAmount - _payerShare;

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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _heroCard(),
                    const SizedBox(height: 24),
                    _paidBySection(brand),
                    const SizedBox(height: 24),
                    _splitBetweenSection(brand),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _saveButton(),
    );
  }

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
                  '${widget.expenseTitle} · ${widget.currencySymbol} ${widget.totalAmount.toStringAsFixed(2)}',
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

  Widget _heroCard() {
    final debtors = _members.where((m) => !m.isPayer).toList();
    final countOwing = debtors.length;
    final amountEach = countOwing > 0 ? _owedAmount / countOwing : 0.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B52BE), Color(0xFF5A32A3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
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
              color: Colors.white70,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${widget.currencySymbol} ${_owedAmount.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'You paid ${widget.currencySymbol} ${widget.totalAmount.toStringAsFixed(2)} · '
            '${countOwing > 0 ? "$countOwing ${countOwing == 1 ? "mate owes" : "mates owe"} you ${widget.currencySymbol} ${amountEach.toStringAsFixed(2)} each" : "no mates added yet"}',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
        ],
      ),
    );
  }

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
        SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _members.length,
            itemBuilder: (context, i) {
              final m = _members[i];
              final isPayer = m.isPayer;
              return GestureDetector(
                onTap: () {
                  HapticFeedback.selectionClick();
                  _setPayer(m);
                },
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Column(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _avatarColor(m.colorIndex),
                          shape: BoxShape.circle,
                          border: isPayer
                              ? Border.all(color: _kPurple, width: 2.5)
                              : null,
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
                      const SizedBox(height: 4),
                      Text(
                        m.isPayer && m.name == 'You' ? 'You' : m.name.split(' ').first,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: isPayer ? FontWeight.w700 : FontWeight.w500,
                          color: isPayer ? _kPurple : brand.inkSoft,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _splitBetweenSection(BrandColors brand) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
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
        // Mode tab bar
        _modeTabBar(brand),
        const SizedBox(height: 12),
        // Member rows
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
      height: 36,
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: List.generate(modes.length, (i) {
          final isSelected = modes[i] == _mode;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _mode = modes[i];
                  _customControllers.clear();
                  _recalculate();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isSelected ? _kPurple : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : brand.inkSoft,
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
    final isYou = m.isPayer && m.name == 'You';

    Widget amountWidget;
    switch (_mode) {
      case SplitMode.equally:
        amountWidget = Text(
          '${widget.currencySymbol} ${m.amount.toStringAsFixed(2)}',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: _kPurple,
          ),
        );
      case SplitMode.amount:
        final ctrl = _controllerFor(m, m.amount.toStringAsFixed(2));
        amountWidget = SizedBox(
          width: 90,
          child: CupertinoTextField(
            controller: ctrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _kPurple),
            decoration: const BoxDecoration(),
            onChanged: (v) {
              final val = double.tryParse(v) ?? 0;
              setState(() => m.amount = val);
            },
          ),
        );
      case SplitMode.percent:
        final totalShares = _members.length;
        final pct = totalShares > 0 ? (100.0 / totalShares) : 0.0;
        amountWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${pct.toStringAsFixed(1)}%',
              style: TextStyle(fontSize: 12, color: brand.inkSoft),
            ),
            Text(
              '${widget.currencySymbol} ${m.amount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _kPurple),
            ),
          ],
        );
      case SplitMode.shares:
        amountWidget = Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '1 share',
              style: TextStyle(fontSize: 12, color: brand.inkSoft),
            ),
            Text(
              '${widget.currencySymbol} ${m.amount.toStringAsFixed(2)}',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: _kPurple),
            ),
          ],
        );
    }

    return Dismissible(
      key: ValueKey(m.id),
      direction: m.isPayer ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red.shade100,
        child: const Icon(CupertinoIcons.trash, color: Colors.red),
      ),
      onDismissed: (_) => _removeMember(m),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
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
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isYou ? 'You (payer)' : m.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: brand.ink,
                    ),
                  ),
                  Text(
                    _mode == SplitMode.equally
                        ? '${(100.0 / _members.length).toStringAsFixed(1)}% of total'
                        : _modeLabel(),
                    style: TextStyle(fontSize: 12, color: brand.inkSoft),
                  ),
                ],
              ),
            ),
            if (m.isPayer)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(CupertinoIcons.checkmark_alt, size: 16, color: _kPurple),
              ),
            amountWidget,
          ],
        ),
      ),
    );
  }

  String _modeLabel() {
    switch (_mode) {
      case SplitMode.equally:
        return 'Equal split';
      case SplitMode.amount:
        return 'Custom amount';
      case SplitMode.percent:
        return 'By percentage';
      case SplitMode.shares:
        return 'By shares';
    }
  }

  Widget _saveButton() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.mediumImpact();
            Navigator.pop(
              context,
              SplitBillResult(members: _members, splitMode: _mode),
            );
          },
          child: Container(
            height: 56,
            decoration: BoxDecoration(
              color: _kPurple,
              borderRadius: BorderRadius.circular(28),
            ),
            child: const Center(
              child: Text(
                'Save & generate bill',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
