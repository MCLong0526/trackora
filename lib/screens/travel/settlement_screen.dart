import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../services/travel_group_service.dart';
import '../../theme/app_theme.dart';

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
    sb.writeln('🧾 ${group.name} — ${context.t('travel.settlement')}');
    sb.writeln('');
    sb.writeln('${context.t('travel.totalSpent')}: ${group.currency} ${fmt.format(settlement.totalSpent)}');
    sb.writeln('');
    for (final b in settlement.balances) {
      final sign = b.net >= 0 ? '+' : '';
      sb.writeln('${b.memberName}: $sign${fmt.format(b.net)}');
    }
    sb.writeln('');
    if (settlement.transactions.isEmpty) {
      sb.writeln('✅ ${context.t('travel.settled')}');
    } else {
      sb.writeln('${context.t('travel.settlement')}:');
      for (final tx in settlement.transactions) {
        sb.writeln('  ${tx.fromMemberName} → ${tx.toMemberName}: ${group.currency} ${fmt.format(tx.amount)}');
      }
    }
    return sb.toString();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.t('travel.settlement')),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.share),
            onPressed: () => Share.share(_buildShareText(context)),
            tooltip: context.t('travel.shareSettlement'),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
          children: [
            // Total spent hero
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF3478F6),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('travel.totalSpent'),
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${group.currency} ${fmt.format(settlement.totalSpent)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.8,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.name,
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Balances section
            _SectionHeader(context.t('travel.balances')),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: settlement.balances.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final b = entry.value;
                  final isPositive = b.net >= 0;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: isPositive
                                    ? const Color(0xFF34C759)
                                        .withValues(alpha: 0.15)
                                    : const Color(0xFFFF3B30)
                                        .withValues(alpha: 0.15),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  b.memberName.isNotEmpty
                                      ? b.memberName[0].toUpperCase()
                                      : '?',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                    color: isPositive
                                        ? const Color(0xFF34C759)
                                        : const Color(0xFFFF3B30),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    b.memberName,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: brand.ink,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        '${context.t('travel.paid')}: ${group.currency} ${fmt.format(b.totalPaid)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: brand.inkSoft,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '${context.t('travel.share')}: ${group.currency} ${fmt.format(b.totalShare)}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: brand.inkSoft,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(
                                  '${isPositive ? '+' : ''}${fmt.format(b.net)}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: isPositive
                                        ? const Color(0xFF34C759)
                                        : const Color(0xFFFF3B30),
                                  ),
                                ),
                                Text(
                                  isPositive
                                      ? context.t('travel.receives')
                                      : context.t('travel.owes'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: brand.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (idx < settlement.balances.length - 1)
                        Divider(
                          height: 1,
                          color: brand.divider,
                          indent: 16,
                          endIndent: 16,
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),

            const SizedBox(height: 24),

            // Transactions section
            _SectionHeader(context.t('travel.settle')),
            const SizedBox(height: 10),

            if (settlement.transactions.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    const Icon(
                      CupertinoIcons.checkmark_seal_fill,
                      color: Color(0xFF34C759),
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.t('travel.settled'),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t('travel.settledHint'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: brand.inkSoft,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: settlement.transactions.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final tx = entry.value;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFF9500)
                                      .withValues(alpha: 0.15),
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  CupertinoIcons.arrow_right,
                                  color: Color(0xFFFF9500),
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: RichText(
                                  text: TextSpan(
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: brand.ink,
                                    ),
                                    children: [
                                      TextSpan(
                                        text: tx.fromMemberName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      const TextSpan(text: ' pays '),
                                      TextSpan(
                                        text: tx.toMemberName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Text(
                                '${group.currency} ${fmt.format(tx.amount)}',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFFFF9500),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (idx < settlement.transactions.length - 1)
                          Divider(
                            height: 1,
                            color: brand.divider,
                            indent: 16,
                            endIndent: 16,
                          ),
                      ],
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF8E8E93),
        letterSpacing: 0.8,
      ),
    );
  }
}
