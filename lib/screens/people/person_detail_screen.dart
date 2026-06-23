import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/person.dart';
import '../../models/split_bill.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../services/prefs_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/person_avatar.dart';
import '../expenses/bill_detail_screen.dart';
import 'add_edit_person_screen.dart';

/// Contact detail: shows who the person is, how much they currently owe you
/// across split bills, and the related (still-pending) split transactions.
class PersonDetailScreen extends ConsumerWidget {
  final Person person;

  const PersonDetailScreen({super.key, required this.person});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final user = ref.watch(authStateProvider).valueOrNull;
    // Re-read the contact from the live provider so an edit (name / colour /
    // emoji) made on the edit screen is reflected here the moment we return.
    final people = ref.watch(peopleProvider).valueOrNull;
    final person = people?.cast<Person?>().firstWhere(
              (p) => p?.id == this.person.id,
              orElse: () => this.person,
            ) ??
        this.person;
    final bills = ref.watch(allSplitBillsProvider).valueOrNull ?? const [];
    final converter = ref.watch(currencyConverterProvider).valueOrNull;
    final baseCode = converter?.base ??
        ref.watch(currencyCodeProvider).valueOrNull ??
        'MYR';
    final symbol = kSupportedCurrencies[baseCode] ?? baseCode;

    final summary = personOwedSummary(
      bills,
      person,
      toBase: converter == null
          ? null
          : (amount, from) => converter.toBase(amount, from),
    );

    // Settled history: bills where this person was a debtor and has fully paid.
    final lowerName = person.name.trim().toLowerCase();
    final settled = <({SplitBill bill, SplitMember member})>[];
    for (final b in bills) {
      for (final m in b.members) {
        if (m.isPayer || m.status != SplitMemberStatus.paid) continue;
        final matches = (m.personId != null && m.personId == person.id) ||
            (m.personId == null && m.name.trim().toLowerCase() == lowerName);
        if (matches) settled.add((bill: b, member: m));
      }
    }
    settled.sort((a, b) => b.bill.date.compareTo(a.bill.date));

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text(
          person.name,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        actions: [
          IconButton(
            icon: Icon(CupertinoIcons.pencil, color: brand.ink),
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => AddEditPersonScreen(person: person),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            // Header
            Row(
              children: [
                PersonAvatar(
                  name: person.name,
                  colorIndex: person.colorIndex,
                  emoji: person.emoji,
                  size: 56,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        person.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        person.type.label,
                        style: TextStyle(fontSize: 13, color: brand.inkSoft),
                      ),
                      if (person.phone != null && person.phone!.isNotEmpty)
                        Text(
                          person.phone!,
                          style: TextStyle(fontSize: 13, color: brand.inkSoft),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            // Owes-you card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: summary.total > 0.005
                    ? AppColors.expense.withValues(alpha: 0.12)
                    : brand.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('split.owesYou').toUpperCase(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: brand.inkSoft,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    formatMoney(symbol, summary.total),
                    style: TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w700,
                      color: summary.total > 0.005
                          ? AppColors.expense
                          : brand.ink,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text(
              context.t('split.owedTransactions').toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: brand.inkSoft,
              ),
            ),
            const SizedBox(height: 10),
            if (summary.pending.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Center(
                  child: Text(
                    context.t('split.allSettledPerson'),
                    style: TextStyle(fontSize: 13, color: brand.inkSoft),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < summary.pending.length; i++) ...[
                      if (i > 0)
                        Divider(height: 0.5, indent: 16, color: brand.divider),
                      _BillRow(
                        title: summary.pending[i].bill.title,
                        dateStr: DateFormat('MMM d, yyyy')
                            .format(summary.pending[i].bill.date),
                        amountStr:
                            '${summary.pending[i].bill.currencySymbol} ${summary.pending[i].member.amount.toStringAsFixed(2)}',
                        onTap: user == null
                            ? null
                            : () async {
                                await Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (_) => BillDetailScreen(
                                      bill: summary.pending[i].bill,
                                      uid: user.uid,
                                    ),
                                  ),
                                );
                                ref.invalidate(allSplitBillsProvider);
                              },
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 22),
            // ── Settled records (history) ───────────────────────────────
            Text(
              context.t('split.settledTransactions').toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: brand.inkSoft,
              ),
            ),
            const SizedBox(height: 10),
            if (settled.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 16),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Center(
                  child: Text(
                    context.t('split.noSettledPerson'),
                    style: TextStyle(fontSize: 13, color: brand.inkSoft),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Column(
                  children: [
                    for (var i = 0; i < settled.length; i++) ...[
                      if (i > 0)
                        Divider(height: 0.5, indent: 16, color: brand.divider),
                      _BillRow(
                        title: settled[i].bill.title,
                        dateStr: DateFormat('MMM d, yyyy')
                            .format(settled[i].bill.date),
                        amountStr:
                            '${settled[i].bill.currencySymbol} ${settled[i].member.amount.toStringAsFixed(2)}',
                        accent: AppColors.income,
                        onTap: user == null
                            ? null
                            : () async {
                                await Navigator.push(
                                  context,
                                  CupertinoPageRoute(
                                    builder: (_) => BillDetailScreen(
                                      bill: settled[i].bill,
                                      uid: user.uid,
                                    ),
                                  ),
                                );
                                ref.invalidate(allSplitBillsProvider);
                              },
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _BillRow extends StatelessWidget {
  final String title;
  final String dateStr;
  final String amountStr;
  final VoidCallback? onTap;
  final Color accent;

  const _BillRow({
    required this.title,
    required this.dateStr,
    required this.amountStr,
    this.onTap,
    this.accent = AppColors.expense,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.card),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(CupertinoIcons.person_2_fill,
                  size: 16, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: brand.ink,
                    ),
                  ),
                  Text(dateStr,
                      style: TextStyle(fontSize: 12, color: brand.inkSoft)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              amountStr,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: accent,
              ),
            ),
            const SizedBox(width: 6),
            Icon(CupertinoIcons.chevron_right, size: 14, color: brand.inkSoft),
          ],
        ),
      ),
    );
  }
}
