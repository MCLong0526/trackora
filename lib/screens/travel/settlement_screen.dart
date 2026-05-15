import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../services/travel_group_service.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _blue = Color(0xFF0066CC);
const _hairline = Color(0xFFE0E0E0);
const _parchment = Color(0xFFF5F5F7);
const _inkColor = Color(0xFF1D1D1F);
const _ink48 = Color(0xFF7A7A7A);
const _positiveColor = Color(0xFF28A968);
const _negativeColor = Color(0xFFFF3B30);

const _memberBgs = [
  Color(0xFFE8E8EA), Color(0xFFDCDCE0), Color(0xFFD0D0D5),
  Color(0xFFC4C4CA), Color(0xFFB8B8BF),
];

TextStyle _display(double size,
        {double tracking = -0.374, double lh = 1.10, Color? color}) =>
    TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: tracking,
        height: lh,
        color: color ?? _inkColor);

TextStyle _body(double size,
        {FontWeight weight = FontWeight.w400, Color? color}) =>
    TextStyle(
        fontSize: size,
        fontWeight: weight,
        color: color ?? _inkColor,
        height: 1.4);

TextStyle _eyebrow({Color? color}) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: color ?? _ink48,
    );

// ── Screen ────────────────────────────────────────────────────────────────────

class SettlementScreen extends StatelessWidget {
  final TravelGroup group;
  final TravelSettlement settlement;

  const SettlementScreen({
    super.key,
    required this.group,
    required this.settlement,
  });

  String _buildShareText(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final sb = StringBuffer();
    sb.writeln('${group.name} — ${context.t('travel.settlement')}');
    sb.writeln('');
    sb.writeln(
        '${context.t('travel.totalSpent')}: ${group.currency} ${fmt.format(settlement.totalSpent)}');
    sb.writeln('');
    for (final b in settlement.balances) {
      final sign = b.net >= 0 ? '+' : '';
      sb.writeln(
          '${b.memberName}: $sign${fmt.format(b.net)}');
    }
    sb.writeln('');
    if (settlement.transactions.isEmpty) {
      sb.writeln(context.t('travel.settled'));
    } else {
      sb.writeln('${context.t('travel.settlement')}:');
      for (final tx in settlement.transactions) {
        sb.writeln(
            '  ${tx.fromMemberName} → ${tx.toMemberName}: ${group.currency} ${fmt.format(tx.amount)}');
      }
    }
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : _parchment;
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  _CircleBtn(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(CupertinoIcons.back,
                        size: 18, color: _inkColor),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        context.t('travel.settlement'),
                        style: _body(17, weight: FontWeight.w600),
                      ),
                    ),
                  ),
                  _CircleBtn(
                    onTap: () => Share.share(_buildShareText(context)),
                    child: const Icon(CupertinoIcons.share,
                        size: 16, color: _inkColor),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              children: [
                // Total hero card
                Container(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: border, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.name,
                        style: _eyebrow(color: _blue),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.t('travel.totalSpent').toUpperCase(),
                        style: _eyebrow(),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${group.currency} ${fmt.format(settlement.totalSpent)}',
                        style: _display(36, tracking: -1.0),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Balances
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    context.t('travel.balances').toUpperCase(),
                    style: _eyebrow(),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: border, width: 0.5),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Column(
                      children: settlement.balances.asMap().entries.map((e) {
                        final idx = e.key;
                        final b = e.value;
                        final isPositive = b.net >= 0;
                        final isLast =
                            idx == settlement.balances.length - 1;
                        final memberBg =
                            _memberBgs[idx % _memberBgs.length];
                        final initial = b.memberName.isNotEmpty
                            ? b.memberName[0].toUpperCase()
                            : '?';

                        return Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(
                                  20, 14, 20, 14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: memberBg,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: Text(initial,
                                          style: _body(16,
                                              weight: FontWeight.w700,
                                              color: _inkColor)),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(b.memberName,
                                            style: _body(15,
                                                weight: FontWeight.w500)),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${context.t('travel.paid')}: ${group.currency} ${fmt.format(b.totalPaid)}  ·  ${context.t('travel.share')}: ${group.currency} ${fmt.format(b.totalShare)}',
                                          style: _body(11,
                                              color: _ink48),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        '${isPositive ? '+' : ''}${fmt.format(b.net)}',
                                        style: _body(15,
                                            weight: FontWeight.w700,
                                            color: isPositive
                                                ? _positiveColor
                                                : _negativeColor),
                                      ),
                                      Container(
                                        margin:
                                            const EdgeInsets.only(top: 3),
                                        padding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 7,
                                                vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isPositive
                                              ? _positiveColor.withValues(
                                                  alpha: 0.10)
                                              : _negativeColor.withValues(
                                                  alpha: 0.10),
                                          borderRadius:
                                              BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          isPositive
                                              ? context.t('travel.receives')
                                              : context.t('travel.owes'),
                                          style: _eyebrow(
                                              color: isPositive
                                                  ? _positiveColor
                                                  : _negativeColor),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (!isLast)
                              Divider(
                                  height: 1,
                                  color: border,
                                  indent: 20,
                                  endIndent: 20),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Transactions
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 10),
                  child: Text(
                    context.t('travel.settle').toUpperCase(),
                    style: _eyebrow(),
                  ),
                ),

                if (settlement.transactions.isEmpty)
                  // Settled state
                  Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: border, width: 0.5),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: _positiveColor.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            CupertinoIcons.checkmark_seal_fill,
                            color: _positiveColor,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 14),
                        Text(context.t('travel.settled'),
                            style: _display(20, tracking: -0.4),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 6),
                        Text(context.t('travel.settledHint'),
                            style: _body(14, color: _ink48),
                            textAlign: TextAlign.center),
                      ],
                    ),
                  )
                else
                  Container(
                    decoration: BoxDecoration(
                      color: surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: border, width: 0.5),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Column(
                        children:
                            settlement.transactions.asMap().entries.map((e) {
                          final idx = e.key;
                          final tx = e.value;
                          final isLast =
                              idx == settlement.transactions.length - 1;

                          return Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                    20, 14, 20, 14),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 38,
                                      height: 38,
                                      decoration: BoxDecoration(
                                        color: _blue.withValues(alpha: 0.08),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        CupertinoIcons.arrow_right,
                                        color: _blue,
                                        size: 16,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: RichText(
                                        text: TextSpan(
                                          style: _body(15),
                                          children: [
                                            TextSpan(
                                              text: tx.fromMemberName,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600),
                                            ),
                                            const TextSpan(text: ' → '),
                                            TextSpan(
                                              text: tx.toMemberName,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${group.currency} ${fmt.format(tx.amount)}',
                                      style: _body(15,
                                          weight: FontWeight.w700,
                                          color: _blue),
                                    ),
                                  ],
                                ),
                              ),
                              if (!isLast)
                                Divider(
                                    height: 1,
                                    color: border,
                                    indent: 70,
                                    endIndent: 20),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),

                const SizedBox(height: 28),

                // Share pill
                GestureDetector(
                  onTap: () => Share.share(_buildShareText(context)),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      border: Border.all(color: _blue, width: 1.5),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.share,
                            color: _blue, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          context.t('travel.shareSettlement'),
                          style: _body(16,
                              weight: FontWeight.w600, color: _blue),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Circle button ─────────────────────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _CircleBtn({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : _inkColor.withValues(alpha: 0.06),
          shape: BoxShape.circle,
        ),
        child: Center(child: child),
      ),
    );
  }
}
