import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/travel_expense.dart';
import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../services/travel_group_service.dart';
import '../../state/providers.dart';
import '../../widgets/animated_donut_chart.dart';
import '../../widgets/app_toast.dart';
import 'add_edit_travel_group_screen.dart';
import 'add_travel_expense_screen.dart';
import 'settlement_screen.dart';
import 'travel_categories.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _blue = Color(0xFF0066CC);
const _hairline = Color(0xFFE0E0E0);
const _parchment = Color(0xFFF5F5F7);
const _inkColor = Color(0xFF1D1D1F);
const _inkDark = Color(0xFFF2F2F4);
const _ink48 = Color(0xFF7A7A7A);
const _red = Color(0xFFFF3B30);
const _green = Color(0xFF28A968);

/// Primary text/icon ink resolved for the current brightness so content stays
/// legible in dark mode.
Color _ink(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? _inkDark : _inkColor;

const _memberBgs = [
  Color(0xFFE8E8EA), Color(0xFFDCDCE0), Color(0xFFD0D0D5),
  Color(0xFFC4C4CA), Color(0xFFB8B8BF),
];

// Default text color is left null so it inherits the ambient (theme-aware)
// ink — near-black in light mode, near-white in dark mode. Pass [color] to
// override (e.g. accent colors).
TextStyle _display(double sz, {double tracking = -0.374, double lh = 1.10, Color? color}) =>
    TextStyle(fontSize: sz, fontWeight: FontWeight.w600, letterSpacing: tracking, height: lh, color: color);

TextStyle _body(double sz, {FontWeight weight = FontWeight.w400, Color? color}) =>
    TextStyle(fontSize: sz, fontWeight: weight, color: color, height: 1.4);

TextStyle _eyebrow({Color? color}) =>
    TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, color: color ?? _ink48);

// ── Main screen ───────────────────────────────────────────────────────────────

class TravelGroupDetailScreen extends ConsumerStatefulWidget {
  final TravelGroup group;
  const TravelGroupDetailScreen({super.key, required this.group});

  @override
  ConsumerState<TravelGroupDetailScreen> createState() =>
      _TravelGroupDetailScreenState();
}

class _TravelGroupDetailScreenState
    extends ConsumerState<TravelGroupDetailScreen> {

  Future<void> _deleteGroup() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('travel.delete')),
        content: Text(context.t('travel.deleteConfirm')),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('common.delete')),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('common.cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(travelGroupServiceProvider).deleteGroup(widget.group.id);
      if (mounted) {
        AppToast.show(context, context.t('travel.deleted'),
            type: AppToastType.success, icon: CupertinoIcons.checkmark_circle_fill);
        Navigator.pop(context);
      }
    } catch (_) {
      if (mounted) AppToast.show(context, context.t('travel.saveFailed'), type: AppToastType.error);
    }
  }

  void _showMore(List<TravelGroupMember> members) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final cardBg = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7);
    final border = isDark ? const Color(0xFF48484A) : _hairline;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Material(
        type: MaterialType.transparency,
        child: Container(
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle
                  Center(
                    child: Container(
                      width: 36, height: 4,
                      margin: const EdgeInsets.only(bottom: 24),
                      decoration: BoxDecoration(
                        color: border, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  // Actions card
                  Container(
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        _Pressable(
                          onTap: () {
                            Navigator.pop(ctx);
                            Navigator.push(context, CupertinoPageRoute(
                              builder: (_) => AddEditTravelGroupScreen(group: widget.group),
                            ));
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            child: Row(
                              children: [
                                Icon(CupertinoIcons.pencil, color: _ink(context), size: 20),
                                const SizedBox(width: 12),
                                Text(context.t('common.edit'),
                                    style: _body(17)),
                                const Spacer(),
                                Icon(CupertinoIcons.chevron_right,
                                    color: _ink48, size: 14),
                              ],
                            ),
                          ),
                        ),
                        Divider(height: 0.5, thickness: 0.5, color: border, indent: 16),
                        _Pressable(
                          onTap: () { Navigator.pop(ctx); _deleteGroup(); },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                            child: Row(
                              children: [
                                Icon(CupertinoIcons.trash, color: _red, size: 20),
                                const SizedBox(width: 12),
                                Text(context.t('travel.delete'),
                                    style: _body(17, color: _red)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  // Cancel button
                  _Pressable(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Text(context.t('common.cancel'),
                            style: _body(17, weight: FontWeight.w600)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showMembersSheet(List<TravelGroupMember> members, bool isDark) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => _MembersSheet(
        group: widget.group,
        members: members,
        isDark: isDark,
      ),
    );
  }

  Future<void> _confirmDelete(TravelExpense expense) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('travel.deleteExpense')),
        content: Text(context.t('travel.deleteExpenseConfirm')),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('common.delete')),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('common.cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(travelGroupServiceProvider).deleteExpense(widget.group.id, expense.id);
      if (mounted) AppToast.show(context, context.t('travel.expenseDeleted'), type: AppToastType.success);
    } catch (_) {
      if (mounted) AppToast.show(context, context.t('travel.saveFailed'), type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : _parchment;

    final membersAsync = ref.watch(travelGroupMembersProvider(widget.group.id));
    final expensesAsync = ref.watch(travelGroupExpensesProvider(widget.group.id));
    final user = ref.watch(authStateProvider).valueOrNull;

    final members = membersAsync.valueOrNull ?? [];
    final expenses = expensesAsync.valueOrNull ?? [];
    final svc = ref.read(travelGroupServiceProvider);
    final settlement = svc.calculateSettlement(members, expenses);

    // Find current user's member record and balance
    TravelGroupMember? myMember;
    for (final m in members) {
      if (m.userId == user?.uid) { myMember = m; break; }
    }
    final myMemberId = myMember?.id ?? '';

    MemberBalance? myBalance;
    for (final b in settlement.balances) {
      if (b.memberId == myMemberId) { myBalance = b; break; }
    }

    final fmt = NumberFormat('#,##0.00');
    final totalSpent = expenses.fold<double>(0.0, (s, e) => s + e.amountInGroupCurrency);
    final memberMap = {for (final m in members) m.id: m};

    // Estimated value in the user's main currency, shown when the trip's
    // currency differs from the user's base currency.
    final converter = ref.watch(currencyConverterProvider).valueOrNull;
    final mainCode = converter?.base;
    final showMainEst = converter != null &&
        mainCode != null &&
        mainCode != widget.group.currency;
    String? mainEst(double amountInGroupCurrency) => showMainEst
        ? '≈ $mainCode ${fmt.format(converter.toBase(amountInGroupCurrency, widget.group.currency))} est.'
        : null;

    // Day info
    final now = DateTime.now();
    final dayNum = now.difference(widget.group.startDate).inDays + 1;
    final totalDays = widget.group.endDate != null
        ? widget.group.endDate!.difference(widget.group.startDate).inDays + 1
        : null;
    final dayLabel = totalDays != null ? 'DAY $dayNum OF $totalDays' : 'DAY $dayNum';

    // Date range display
    final dateFmt = DateFormat('MMM d');
    final fullDateFmt = DateFormat('MMM d, yyyy');
    final s = dateFmt.format(widget.group.startDate);
    final e = widget.group.endDate != null ? fullDateFmt.format(widget.group.endDate!) : null;
    final dateRange = e != null ? '$s – $e' : s;

    // Group expenses by date (newest first)
    final grouped = <String, List<TravelExpense>>{};
    for (final ex in expenses) {
      final key = DateFormat('yyyy-MM-dd').format(ex.date);
      grouped.putIfAbsent(key, () => []).add(ex);
    }
    final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ── Nav bar ────────────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  _CircleBtn(
                    onTap: () => Navigator.pop(context),
                    child: Icon(CupertinoIcons.back, size: 18, color: _ink(context)),
                  ),
                  const Spacer(),
                  _CircleBtn(
                    onTap: () => _showMore(members),
                    child: Icon(CupertinoIcons.ellipsis, size: 16, color: _ink(context)),
                  ),
                ],
              ),
            ),
          ),

          // ── Scrollable body ────────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                // ── Trip header ──────────────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 16, 22, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          width: 6, height: 6,
                          decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Text('ACTIVE · $dayLabel', style: _eyebrow(color: _blue)),
                      ]),
                      const SizedBox(height: 8),
                      Text(widget.group.name,
                          style: _display(34, tracking: -0.8)),
                      const SizedBox(height: 4),
                      Text(
                        '$dateRange · ${members.length} travelers',
                        style: _body(14, color: _ink48),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // ── Stats row: Trip Total | You're Owed ──────────────────────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: Row(
                    children: [
                      Expanded(
                        child: _StatsCard(
                          label: 'TRIP TOTAL',
                          value: '${widget.group.currency} ${fmt.format(totalSpent)}',
                          valueColor: null,
                          isDark: isDark,
                          sub: mainEst(totalSpent),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _StatsCard(
                          label: myBalance == null
                              ? 'BALANCE'
                              : myBalance.net >= 0
                                  ? "YOU'RE OWED"
                                  : 'YOU OWE',
                          value: myBalance == null
                              ? '—'
                              : '${myBalance.net >= 0 ? '+' : ''}${widget.group.currency} ${fmt.format(myBalance.net.abs())}',
                          valueColor: myBalance == null
                              ? null
                              : myBalance.net >= 0 ? _green : _red,
                          isDark: isDark,
                          sub: myBalance == null ? null : mainEst(myBalance.net.abs()),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // ── WHO PAID section ─────────────────────────────────────────
                if (members.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 0, 22, 10),
                    child: Row(
                      children: [
                        Text(
                          'WHO PAID · ${members.length} TRAVELERS',
                          style: _eyebrow(),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _showMembersSheet(members, isDark),
                          child: Text('See all',
                              style: _body(13, color: _blue)),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _Card(
                      isDark: isDark,
                      child: Column(
                        children: members.asMap().entries.map((entry) {
                          final idx = entry.key;
                          final m = entry.value;
                          final paid = settlement.balances
                              .where((b) => b.memberId == m.id)
                              .fold(0.0, (_, b) => b.totalPaid);
                          final ratio = totalSpent > 0 ? (paid / totalSpent).clamp(0.0, 1.0) : 0.0;
                          return _WhoPaidRow(
                            member: m,
                            paid: paid,
                            ratio: ratio,
                            currency: widget.group.currency,
                            fmt: fmt,
                            isLast: idx == members.length - 1,
                            isDark: isDark,
                            isMe: m.id == myMemberId,
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── BY CATEGORY chart ────────────────────────────────────────
                if (!expensesAsync.isLoading && expenses.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(26, 0, 22, 10),
                    child: Text('BY CATEGORY', style: _eyebrow()),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    child: _CategoryChart(
                      expenses: expenses,
                      currency: widget.group.currency,
                      fmt: fmt,
                      isDark: isDark,
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                // ── Expense list grouped by date ─────────────────────────────
                if (expensesAsync.isLoading)
                  const Center(child: CupertinoActivityIndicator())
                else if (expenses.isEmpty)
                  _EmptyExpenses(group: widget.group, members: members, isDark: isDark)
                else
                  ...sortedKeys.map((dateKey) {
                    final dayExpenses = grouped[dateKey]!;
                    final dt = DateFormat('yyyy-MM-dd').parse(dateKey);
                    final isToday = dateKey == DateFormat('yyyy-MM-dd').format(now);
                    final isYesterday = dateKey == DateFormat('yyyy-MM-dd').format(
                        now.subtract(const Duration(days: 1)));
                    final dayHeader = isToday
                        ? 'TODAY · ${DateFormat('EEE MMM d').format(dt).toUpperCase()}'
                        : isYesterday
                            ? 'YESTERDAY · ${DateFormat('EEE MMM d').format(dt).toUpperCase()}'
                            : DateFormat('EEE MMM d, yyyy').format(dt).toUpperCase();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(26, 0, 22, 10),
                          child: Row(
                            children: [
                              Text(dayHeader, style: _eyebrow()),
                              const Spacer(),
                              Text('Filter',
                                  style: _body(13, color: _blue)),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
                          child: _Card(
                            isDark: isDark,
                            child: Column(
                              children: dayExpenses.asMap().entries.map((e) {
                                final idx = e.key;
                                final expense = e.value;
                                final paidBy = memberMap[expense.paidByMemberId];

                                // Per-expense balance line (always in group currency)
                                String balanceText = '';
                                Color balanceColor = _green;
                                if (myMemberId.isNotEmpty) {
                                  final splitCnt = expense.splitAmong.length;
                                  final rate = expense.exchangeRate ?? 1.0;
                                  final convertedTotal = expense.amountInGroupCurrency;
                                  // Convert per-member split to group currency
                                  final myShareConverted = expense.splitAmounts?[myMemberId] != null
                                      ? expense.splitAmounts![myMemberId]! * rate
                                      : (splitCnt > 0 ? convertedTotal / splitCnt : 0.0);
                                  if (expense.paidByMemberId == myMemberId) {
                                    final lent = convertedTotal -
                                        (expense.splitAmong.contains(myMemberId) ? myShareConverted : 0.0);
                                    if (lent > 0.005) {
                                      balanceText = 'you lent +${widget.group.currency} ${fmt.format(lent)}';
                                    }
                                  } else if (expense.splitAmong.contains(myMemberId)) {
                                    balanceText = 'you owe ${widget.group.currency} ${fmt.format(myShareConverted)}';
                                    balanceColor = _red;
                                  }
                                }

                                final paidByIsMe = expense.paidByMemberId == myMemberId;
                                final payerName = paidByIsMe ? 'You' : (paidBy?.name ?? '—');
                                final splitCnt = expense.splitAmong.length;
                                final splitLabel = splitCnt > 0
                                    ? '$payerName paid · split $splitCnt ways'
                                    : '$payerName paid';

                                return _ExpenseRow(
                                  expense: expense,
                                  currency: widget.group.currency,
                                  fmt: fmt,
                                  splitLabel: splitLabel,
                                  balanceText: balanceText,
                                  balanceColor: balanceColor,
                                  mainCurrencyEst: mainEst(expense.amountInGroupCurrency),
                                  isLast: idx == dayExpenses.length - 1,
                                  isDark: isDark,
                                  onTap: () => Navigator.push(
                                    context,
                                    CupertinoPageRoute(
                                      fullscreenDialog: true,
                                      builder: (_) => AddTravelExpenseScreen(
                                        group: widget.group,
                                        members: members,
                                        expense: expense,
                                      ),
                                    ),
                                  ),
                                  onDelete: () => _confirmDelete(expense),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
              ],
            ),
          ),
        ],
      ),

      // ── Bottom bar ────────────────────────────────────────────────────────
      bottomNavigationBar: _BottomBar(
        group: widget.group,
        members: members,
        expenses: expenses,
        settlement: settlement,
        isDark: isDark,
      ),
    );
  }
}

// ── Stats card ─────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool isDark;
  final String? sub;

  const _StatsCard({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.isDark,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _eyebrow()),
          const SizedBox(height: 6),
          Text(
            value,
            style: _display(20, tracking: -0.4, color: valueColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(
              sub!,
              style: _body(11, color: _ink48),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }
}

// ── By-category chart ─────────────────────────────────────────────────────────

class _CategoryChart extends StatelessWidget {
  final List<TravelExpense> expenses;
  final String currency;
  final NumberFormat fmt;
  final bool isDark;

  const _CategoryChart({
    required this.expenses,
    required this.currency,
    required this.fmt,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final totals = <String, double>{};
    for (final e in expenses) {
      totals[e.category] =
          (totals[e.category] ?? 0) + e.amountInGroupCurrency;
    }
    final entries = totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const SizedBox.shrink();
    final total = entries.fold<double>(0, (s, e) => s + e.value);
    final segments = [
      for (final e in entries)
        DonutSegment(value: e.value, color: travelCatColor(e.key)),
    ];

    return _Card(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(
          children: [
            AnimatedDonutChart(
              segments: segments,
              size: 104,
              strokeWidth: 20,
              centerChild: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${entries.length}', style: _display(18, tracking: -0.3)),
                  Text('cats', style: _body(10, color: _ink48)),
                ],
              ),
            ),
            const SizedBox(width: 18),
            Expanded(
              child: Column(
                children: [
                  for (final e in entries.take(5))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 22,
                            height: 22,
                            decoration: BoxDecoration(
                              color: travelCatColor(e.key).withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(7),
                            ),
                            child: Icon(travelCatIcon(e.key),
                                size: 12, color: travelCatColor(e.key)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              travelCatLabel(e.key),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: _body(13, weight: FontWeight.w500),
                            ),
                          ),
                          Text(
                            '${total > 0 ? (e.value / total * 100).round() : 0}%',
                            style: _body(12, color: _ink48),
                          ),
                        ],
                      ),
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

// ── Who Paid row ──────────────────────────────────────────────────────────────

class _WhoPaidRow extends StatelessWidget {
  final TravelGroupMember member;
  final double paid;
  final double ratio;
  final String currency;
  final NumberFormat fmt;
  final bool isLast;
  final bool isDark;
  final bool isMe;

  const _WhoPaidRow({
    required this.member,
    required this.paid,
    required this.ratio,
    required this.currency,
    required this.fmt,
    required this.isLast,
    required this.isDark,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final divider = isDark ? const Color(0xFF3A3A3C) : _hairline;
    final initial = member.name.isNotEmpty ? member.name[0].toUpperCase() : '?';
    final avatarBg = _memberBgs[member.name.hashCode.abs() % _memberBgs.length];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
          child: Row(
            children: [
              // Avatar
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: avatarBg,
                  shape: BoxShape.circle,
                  border: isMe ? Border.all(color: _blue, width: 1.5) : null,
                ),
                child: Center(child: Text(initial,
                    style: _body(13, weight: FontWeight.w700))),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(isMe ? 'You' : member.name,
                          style: _body(14, weight: FontWeight.w500)),
                      if (isMe) ...[
                        const SizedBox(width: 5),
                        Text('YOU',
                            style: TextStyle(
                              fontSize: 10, fontWeight: FontWeight.w600,
                              color: _blue, letterSpacing: 0.4,
                            )),
                      ],
                    ]),
                    const SizedBox(height: 5),
                    _AnimatedProgressBar(
                      value: ratio,
                      foreground: _blue,
                      background: _blue.withValues(alpha: 0.10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text('$currency ${fmt.format(paid)}',
                  style: _body(14, weight: FontWeight.w600)),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: divider, indent: 18, endIndent: 18),
      ],
    );
  }
}

// ── Expense row ───────────────────────────────────────────────────────────────

class _ExpenseRow extends StatelessWidget {
  final TravelExpense expense;
  final String currency;
  final NumberFormat fmt;
  final String splitLabel;
  final String balanceText;
  final Color balanceColor;
  final String? mainCurrencyEst;
  final bool isLast;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ExpenseRow({
    required this.expense,
    required this.currency,
    required this.fmt,
    required this.splitLabel,
    required this.balanceText,
    required this.balanceColor,
    this.mainCurrencyEst,
    required this.isLast,
    required this.isDark,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final divider = isDark ? const Color(0xFF3A3A3C) : _hairline;
    final catColor = travelCatColor(expense.category);

    return Column(
      children: [
        Dismissible(
          key: Key(expense.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: _red.withValues(alpha: 0.08),
            child: const Icon(CupertinoIcons.delete, color: _red, size: 20),
          ),
          confirmDismiss: (_) async { onDelete(); return false; },
          child: GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Category icon
                  Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      travelCatIcon(expense.category),
                      color: catColor, size: 17,
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Description + split label
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          expense.description.isNotEmpty
                              ? expense.description
                              : expense.category,
                          style: _body(15, weight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(splitLabel,
                            style: _body(12, color: _ink48),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Amount + balance
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('${expense.currencyCode ?? currency} ${fmt.format(expense.amount)}',
                          style: _body(15, weight: FontWeight.w600)),
                      // Estimated value in the group's currency when the
                      // expense was recorded in a different currency.
                      if (expense.currencyCode != null &&
                          expense.currencyCode != currency) ...[
                        const SizedBox(height: 2),
                        Text('≈ $currency ${fmt.format(expense.amountInGroupCurrency)} est.',
                            style: _body(11, color: _ink48)),
                      ],
                      // Estimated value in the user's main currency when the
                      // trip currency differs from it.
                      if (mainCurrencyEst != null) ...[
                        const SizedBox(height: 2),
                        Text(mainCurrencyEst!,
                            style: _body(11, color: _ink48)),
                      ],
                      if (balanceText.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(balanceText,
                            style: _body(12, color: balanceColor)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: divider, indent: 68, endIndent: 18),
      ],
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final TravelGroup group;
  final List<TravelGroupMember> members;
  final List<TravelExpense> expenses;
  final dynamic settlement;
  final bool isDark;

  const _BottomBar({
    required this.group,
    required this.members,
    required this.expenses,
    required this.settlement,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(18, 10, 18, 10 + safeBottom),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1C1C1E) : Colors.white).withValues(alpha: 0.85),
            border: Border(top: BorderSide(color: border, width: 0.5)),
          ),
          child: Row(
            children: [
              Expanded(
                child: _Pressable(
                  onTap: members.isEmpty
                      ? null
                      : () => Navigator.push(
                            context,
                            CupertinoPageRoute(
                              fullscreenDialog: true,
                              builder: (_) => AddTravelExpenseScreen(
                                group: group,
                                members: members,
                              ),
                            ),
                          ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: members.isEmpty ? _blue.withValues(alpha: 0.4) : _blue,
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.add, color: Colors.white, size: 15),
                        const SizedBox(width: 6),
                        Text(context.t('travel.addExpense'),
                            style: _body(15, weight: FontWeight.w600, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Pressable(
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => SettlementScreen(
                        group: group,
                        settlement: settlement,
                        members: members,
                        expenses: expenses,
                      ),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      border: Border.all(color: _blue, width: 1.5),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(CupertinoIcons.checkmark_seal, color: _blue, size: 15),
                        const SizedBox(width: 6),
                        Text(context.t('travel.settle'),
                            style: _body(15, weight: FontWeight.w600, color: _blue)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Members sheet ─────────────────────────────────────────────────────────────

class _MembersSheet extends ConsumerStatefulWidget {
  final TravelGroup group;
  final List<TravelGroupMember> members;
  final bool isDark;

  const _MembersSheet({
    required this.group,
    required this.members,
    required this.isDark,
  });

  @override
  ConsumerState<_MembersSheet> createState() => _MembersSheetState();
}

class _MembersSheetState extends ConsumerState<_MembersSheet> {
  final _nameCtrl  = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _adding = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _addMember() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _adding = true);
    try {
      await ref.read(travelGroupServiceProvider).addMember(
        groupId: widget.group.id,
        group: widget.group,
        name: name,
        email: _emailCtrl.text.trim().isEmpty ? null : _emailCtrl.text.trim(),
      );
      _nameCtrl.clear();
      _emailCtrl.clear();
      if (mounted) {
        AppToast.show(context, context.t('travel.memberAdded'),
            type: AppToastType.success, icon: CupertinoIcons.checkmark_circle_fill);
      }
    } catch (_) {
      if (mounted) AppToast.show(context, context.t('travel.saveFailed'), type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<void> _removeMember(TravelGroupMember m) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('travel.removeMember')),
        content: Text(context.t('travel.removeMemberConfirm')),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('common.delete')),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('common.cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(travelGroupServiceProvider)
          .removeMember(widget.group.id, widget.group, m.id, m.userId);
      if (mounted) AppToast.show(context, context.t('travel.memberRemoved'), type: AppToastType.success);
    } catch (_) {
      if (mounted) AppToast.show(context, context.t('travel.saveFailed'), type: AppToastType.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final surface = widget.isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final bg = widget.isDark ? const Color(0xFF1C1C1E) : _parchment;
    final border = widget.isDark ? const Color(0xFF3A3A3C) : _hairline;
    final membersLive = ref.watch(travelGroupMembersProvider(widget.group.id)).valueOrNull
        ?? widget.members;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.80,
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                        color: border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Row(
                  children: [
                    Text(context.t('travel.members'),
                        style: _display(20, tracking: -0.4)),
                    const Spacer(),
                    Text('${membersLive.length} members', style: _body(13, color: _ink48)),
                  ],
                ),
                if (widget.group.inviteCode != null && widget.group.inviteCode!.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: () {
                      final code = widget.group.inviteCode!;
                      final msg = 'Join "${widget.group.name}" on Trackora! Use code: $code';
                      Share.share(msg);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(CupertinoIcons.link, size: 14, color: _blue),
                          const SizedBox(width: 6),
                          Text('Code: ${widget.group.inviteCode}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                  letterSpacing: 1.5, color: _blue)),
                          const SizedBox(width: 8),
                          const Icon(CupertinoIcons.share, size: 14, color: _blue),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                // Member list (scrollable)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 240),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: membersLive.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: border, indent: 18, endIndent: 18),
                    itemBuilder: (_, i) {
                      final m = membersLive[i];
                      final isOwner = m.userId != null && m.userId == widget.group.ownerId;
                      final initial = m.name.isNotEmpty ? m.name[0].toUpperCase() : '?';
                      final avatarBg = _memberBgs[i % _memberBgs.length];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(color: avatarBg, shape: BoxShape.circle),
                              child: Center(child: Text(initial,
                                  style: _body(14, weight: FontWeight.w700))),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(m.name, style: _body(15, weight: FontWeight.w500)),
                                    if (isOwner) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _blue.withValues(alpha: 0.10),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text('Owner',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _blue)),
                                      ),
                                    ],
                                  ]),
                                  if (m.email != null && m.email!.isNotEmpty)
                                    Text(m.email!, style: _body(12, color: _ink48)),
                                ],
                              ),
                            ),
                            if (!isOwner)
                              GestureDetector(
                                onTap: () => _removeMember(m),
                                child: const Icon(CupertinoIcons.minus_circle,
                                    color: _ink48, size: 22),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                // Add member fields
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _nameCtrl,
                    textCapitalization: TextCapitalization.words,
                    decoration: InputDecoration(
                      hintText: context.t('travel.memberName'),
                      border: InputBorder.none,
                      hintStyle: _body(15, color: _ink48),
                    ),
                    style: _body(15),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: border, width: 0.5),
                  ),
                  child: TextField(
                    controller: _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: context.t('travel.memberEmail'),
                      border: InputBorder.none,
                      hintStyle: _body(15, color: _ink48),
                    ),
                    style: _body(15),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: GestureDetector(
                    onTap: _adding ? null : _addMember,
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: _adding ? _blue.withValues(alpha: 0.5) : _blue,
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Center(
                        child: _adding
                            ? const CupertinoActivityIndicator(color: Colors.white)
                            : Text(context.t('common.add'),
                                style: _body(16, weight: FontWeight.w600, color: Colors.white)),
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

// ── Empty expenses ────────────────────────────────────────────────────────────

class _EmptyExpenses extends StatelessWidget {
  final TravelGroup group;
  final List<TravelGroupMember> members;
  final bool isDark;

  const _EmptyExpenses({
    required this.group,
    required this.members,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(CupertinoIcons.doc_text, color: _blue, size: 34),
            ),
            const SizedBox(height: 18),
            Text(context.t('travel.noExpenses'),
                style: _display(20, tracking: -0.4), textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(context.t('travel.noExpensesHint'),
                style: _body(15, color: _ink48), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const _Card({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 0.5),
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(20), child: child),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _CircleBtn({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return _Pressable(
      onTap: onTap,
      child: Container(
        width: 36, height: 36,
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
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) { if (widget.onTap != null) _ctrl.forward(); },
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

// ── Animated progress bar ─────────────────────────────────────────────────────

class _AnimatedProgressBar extends StatefulWidget {
  final double value;
  final Color foreground;
  final Color background;
  const _AnimatedProgressBar({
    required this.value,
    required this.foreground,
    required this.background,
  });

  @override
  State<_AnimatedProgressBar> createState() => _AnimatedProgressBarState();
}

class _AnimatedProgressBarState extends State<_AnimatedProgressBar>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _anim = Tween(begin: 0.0, end: widget.value).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    WidgetsBinding.instance.addPostFrameCallback((_) => _ctrl.forward());
  }

  @override
  void didUpdateWidget(_AnimatedProgressBar old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _anim = Tween(begin: _anim.value, end: widget.value).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
      _ctrl
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, _) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          value: _anim.value,
          minHeight: 4,
          backgroundColor: widget.background,
          valueColor: AlwaysStoppedAnimation(widget.foreground),
        ),
      ),
    );
  }
}

