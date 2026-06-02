import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/account.dart';
import '../../models/borrow_lending.dart' show BorrowLending, BorrowLendingStatus, BorrowLendingType;
import '../../models/expense.dart';
import '../../models/installment.dart' show Installment, InstallmentStatus;
import '../../models/precious_metal.dart';
import '../../models/saving_plan.dart' show SavingPlan, SavingPlanStatus;
import '../../models/stock_investment.dart';
import '../../models/travel_group.dart';
import '../../services/currency_converter.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../widgets/exchange_rate_sheet.dart';
import '../../widgets/masked_amount.dart';
import '../../widgets/profile_avatar_button.dart';
import '../borrow_lending/borrow_lending_screen.dart';
import '../group/group_dashboard_screen.dart';
import '../installments/installments_screen.dart';
import '../precious_metals/precious_metals_screen.dart';
import '../savings/saving_plans_screen.dart';
import '../stocks/stocks_screen.dart';
import '../travel/travel_groups_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _kCard = Colors.white;
const _kRadius = 20.0;
const _kGreen = Color(0xFF34C759);
const _kOrange = Color(0xFFF57C00);
const _kBlue = Color(0xFF1A6CFF);
const _kRed = Color(0xFFFF3B30);

class AssetsScreen extends ConsumerWidget {
  const AssetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final expenses = ref.watch(allExpensesProvider).valueOrNull ?? const <Expense>[];
    final savingPlans = ref.watch(savingPlansProvider).valueOrNull ?? const <SavingPlan>[];
    final borrowLending = ref.watch(borrowLendingProvider).valueOrNull ?? const <BorrowLending>[];
    final installments = ref.watch(installmentsProvider).valueOrNull ?? const <Installment>[];
    final metals = ref.watch(preciousMetalsProvider).valueOrNull ?? const <PreciousMetal>[];
    final stocks = ref.watch(stockInvestmentsProvider).valueOrNull ?? const <StockInvestment>[];
    final travelGroups = ref.watch(travelGroupsProvider).valueOrNull ?? const <TravelGroup>[];
    final expenseGroups = ref.watch(myGroupsProvider).valueOrNull ?? const [];
    final budget = ref.watch(budgetProvider).valueOrNull ?? 0.0;
    final selectedMonth = ref.watch(selectedMonthProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final visible = ref.watch(balanceVisibleProvider);
    final converter = ref.watch(currencyConverterProvider).valueOrNull;
    final mainCode = ref.watch(currencyCodeProvider).valueOrNull;

    final snapshot = _AssetSnapshot.build(
      accounts: accounts,
      expenses: expenses,
      savingPlans: savingPlans,
      borrowLending: borrowLending,
      installments: installments,
      converter: converter,
      mainCode: mainCode,
    );

    // Budget spent this month
    final monthExpenses = expenses.where((e) =>
        e.type == EntryType.expense &&
        e.date.year == selectedMonth.year &&
        e.date.month == selectedMonth.month &&
        e.category != 'Bills' &&
        !(e.note.contains('(installment)'))).toList();
    final monthlySpent = monthExpenses.fold<double>(0, (s, e) => s + e.convertedAmount);
    final budgetRemaining = budget - monthlySpent;

    // Savings total
    final totalSaved = snapshot.savingPlanSaved;
    final totalGoal = savingPlans
        .where((p) => p.status == SavingPlanStatus.active)
        .fold<double>(0, (s, p) => s + p.targetAmount);

    // Borrow & Lend net
    final borrowNet = snapshot.totalLent - snapshot.totalBorrowed;

    // Installments total remaining
    final installmentTotal = snapshot.installmentLiability ?? 0.0;
    final installmentCount = snapshot.activeInstallments.length;

    // Travel groups (no totalSpent on model — just show count)
    final latestGroup = travelGroups.isNotEmpty ? travelGroups.first : null;

    // Stocks total cost
    final stockTotal = stocks.fold<double>(0, (s, st) => s + st.totalCost);

    // Precious metals total value
    final metalsTotal = metals.fold<double>(0, (s, m) {
      final price = m.pricePerGram ?? 0.0;
      return s + m.weightGrams * price;
    });
    final metalsGrams = metals.fold<double>(0, (s, m) => s + m.weightGrams);

    return SafeArea(
      child: Column(
        children: [
          // ── Header ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    context.t('asset.title'),
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                ),
                const FxRateButton(),
                const SizedBox(width: 8),
                const ProfileAvatarButton(),
              ],
            ),
          ),

          // ── Body ──────────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
              children: [
                // ── Net Worth (full width) ─────────────────────
                _NetWorthCard(
                  snapshot: snapshot,
                  symbol: symbol,
                  visible: visible,
                ),

                const SizedBox(height: 10),

                // ── Row 1: Budget | Savings ────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _GridCard(
                        icon: CupertinoIcons.chart_pie_fill,
                        iconBg: const Color(0xFFF3EEFF),
                        iconColor: const Color(0xFF8B5CF6),
                        title: 'Budget',
                        amount: budget > 0 ? formatMoney(symbol, budgetRemaining) : '—',
                        subtitle: budget > 0
                            ? budgetRemaining >= 0 ? 'left this month' : 'over budget'
                            : 'not set',
                        subtitleColor: budget > 0 && budgetRemaining > 0
                            ? _kGreen
                            : budget > 0
                                ? _kRed
                                : const Color(0xFF8E8E96),
                        visible: visible,
                        onTap: () {},
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GridCard(
                        icon: CupertinoIcons.flag_fill,
                        iconBg: const Color(0xFFE8F5E9),
                        iconColor: _kGreen,
                        title: 'Savings',
                        amount: formatMoney(symbol, totalSaved),
                        subtitle: totalGoal > 0
                            ? '${savingPlans.where((p) => p.status == SavingPlanStatus.active).length} of ${formatMoney(symbol, totalGoal)}'
                            : 'no active plans',
                        subtitleColor: totalSaved > 0 ? _kGreen : _kOrange,
                        visible: visible,
                        onTap: () => _push(context, const SavingPlansScreen()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Row 2: Borrow & Lend | Installments ───────
                Row(
                  children: [
                    Expanded(
                      child: _GridCard(
                        icon: CupertinoIcons.arrow_up_arrow_down,
                        iconBg: const Color(0xFFFFF3E0),
                        iconColor: _kOrange,
                        title: 'Borrow & Lend',
                        amount: formatMoney(symbol, borrowNet.abs()),
                        subtitle: borrowNet >= 0 ? 'owed to you' : 'you owe, net',
                        subtitleColor: borrowNet >= 0 ? _kGreen : _kOrange,
                        visible: visible,
                        onTap: () => _push(context, const BorrowLendingScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GridCard(
                        icon: CupertinoIcons.bolt_fill,
                        iconBg: const Color(0xFFFCE4EC),
                        iconColor: const Color(0xFFE91E63),
                        title: 'Installments',
                        amount: formatMoney(symbol, installmentTotal),
                        subtitle: installmentCount > 0 ? '$installmentCount plans' : 'none active',
                        subtitleColor: installmentCount > 0
                            ? const Color(0xFFE91E63)
                            : const Color(0xFF8E8E96),
                        visible: visible,
                        onTap: () => _push(context, const InstallmentsScreen()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Row 3: Travel Group | Groups ───────────────
                Row(
                  children: [
                    Expanded(
                      child: _GridCard(
                        icon: CupertinoIcons.airplane,
                        iconBg: const Color(0xFFE3F2FD),
                        iconColor: _kBlue,
                        title: 'Travel Group',
                        amount: travelGroups.length.toString(),
                        subtitle: latestGroup?.name ?? (travelGroups.isEmpty ? 'no trips' : '${travelGroups.length} trips'),
                        subtitleColor: travelGroups.isNotEmpty ? _kBlue : const Color(0xFF8E8E96),
                        visible: visible,
                        onTap: () => _push(context, const TravelGroupsScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GridCard(
                        icon: CupertinoIcons.person_3_fill,
                        iconBg: const Color(0xFFE8F0FE),
                        iconColor: const Color(0xFF1967D2),
                        title: 'Groups',
                        amount: expenseGroups.length.toString(),
                        subtitle: expenseGroups.isEmpty
                            ? 'no groups'
                            : expenseGroups.length == 1
                                ? '1 group'
                                : '${expenseGroups.length} groups',
                        subtitleColor: expenseGroups.isNotEmpty
                            ? const Color(0xFF1967D2)
                            : const Color(0xFF8E8E96),
                        visible: visible,
                        onTap: () => _push(context, const GroupDashboardScreen()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Row 4: Stocks | Precious Metal ─────────────
                Row(
                  children: [
                    Expanded(
                      child: _GridCard(
                        icon: CupertinoIcons.chart_bar_square_fill,
                        iconBg: const Color(0xFFEDE7F6),
                        iconColor: const Color(0xFF5856D6),
                        title: 'Stocks',
                        amount: formatMoney(symbol, stockTotal),
                        subtitle: stocks.isEmpty ? 'no positions' : '${stocks.length} positions',
                        subtitleColor: stocks.isNotEmpty ? _kGreen : const Color(0xFF8E8E96),
                        visible: visible,
                        onTap: () => _push(context, const StocksScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GridCard(
                        icon: CupertinoIcons.circle_grid_hex_fill,
                        iconBg: const Color(0xFFFFF8E1),
                        iconColor: const Color(0xFFFFA000),
                        title: 'Precious Metal',
                        amount: formatMoney(symbol, metalsTotal),
                        subtitle: metalsGrams > 0 ? '${metalsGrams.toStringAsFixed(1)}g' : 'no holdings',
                        subtitleColor: metalsGrams > 0 ? _kOrange : const Color(0xFF8E8E96),
                        visible: visible,
                        onTap: () => _push(context, const PreciousMetalsScreen()),
                      ),
                    ),
                  ],
                ),

              ],
            ),
          ),
        ],
      ),
    );
  }

  static void _push(BuildContext context, Widget screen) {
    HapticFeedback.selectionClick();
    Navigator.push(context, CupertinoPageRoute(builder: (_) => screen));
  }
}



// ── Net Worth card ────────────────────────────────────────────────────────────

class _NetWorthCard extends StatelessWidget {
  final _AssetSnapshot snapshot;
  final String symbol;
  final bool visible;

  const _NetWorthCard({
    required this.snapshot,
    required this.symbol,
    required this.visible,
  });

  void _showPopup(BuildContext context, {required bool isAssets}) {
    HapticFeedback.selectionClick();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _NetWorthDetailSheet(
        snapshot: snapshot,
        symbol: symbol,
        visible: visible,
        showAssets: isAssets,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final netWorth = snapshot.netWorth;
    final totalOwn = snapshot.totalAssets;
    final totalOwe = snapshot.totalLiabilities;
    final total = totalOwn + totalOwe;
    final ownedPct = total > 0 ? (totalOwn / total).clamp(0.0, 1.0) : 1.0;
    final ownedPctInt = (ownedPct * 100).round();
    final owedPctInt = 100 - ownedPctInt;

    final healthLabel = ownedPct >= 0.8
        ? 'Healthy'
        : ownedPct >= 0.5
            ? 'Fair'
            : 'At risk';
    final healthColor = ownedPct >= 0.8
        ? _kGreen
        : ownedPct >= 0.5
            ? _kOrange
            : _kRed;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(_kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              const Text(
                'NET WORTH',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8E8E96),
                  letterSpacing: 0.6,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: healthColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(width: 6, height: 6, decoration: BoxDecoration(color: healthColor, shape: BoxShape.circle)),
                    const SizedBox(width: 4),
                    Text(healthLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: healthColor)),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Net worth amount
          MaskedAmount(
            visibleText: formatMoney(symbol, netWorth),
            visible: visible,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0B0B0F),
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 14),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: Row(
                children: [
                  Flexible(
                    flex: ownedPctInt,
                    child: Container(color: _kGreen),
                  ),
                  Flexible(
                    flex: owedPctInt > 0 ? owedPctInt : 0,
                    child: Container(color: _kRed),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 6),

          Text(
            '$ownedPctInt% assets · $owedPctInt% liabilities',
            style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E96), fontWeight: FontWeight.w500),
          ),

          const SizedBox(height: 14),

          // Divider
          Container(height: 1, color: const Color(0xFFF0F0F5)),

          const SizedBox(height: 12),

          // Assets row (tappable)
          GestureDetector(
            onTap: () => _showPopup(context, isAssets: true),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: _kGreen, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Assets',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF5B5B66)),
                ),
                const Spacer(),
                MaskedAmount(
                  visibleText: formatMoney(symbol, totalOwn),
                  visible: visible,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0B0B0F),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(CupertinoIcons.chevron_right, size: 12, color: Color(0xFFB0B0B8)),
              ],
            ),
          ),

          const SizedBox(height: 10),

          // Liabilities row (tappable)
          GestureDetector(
            onTap: () => _showPopup(context, isAssets: false),
            behavior: HitTestBehavior.opaque,
            child: Row(
              children: [
                Container(
                  width: 8, height: 8,
                  decoration: const BoxDecoration(color: _kRed, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Liabilities',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Color(0xFF5B5B66)),
                ),
                const Spacer(),
                MaskedAmount(
                  visibleText: formatMoney(symbol, totalOwe),
                  visible: visible,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0B0B0F),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(CupertinoIcons.chevron_right, size: 12, color: Color(0xFFB0B0B8)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Net Worth detail popup sheet ──────────────────────────────────────────────

class _NetWorthDetailSheet extends StatelessWidget {
  final _AssetSnapshot snapshot;
  final String symbol;
  final bool visible;
  final bool showAssets;

  const _NetWorthDetailSheet({
    required this.snapshot,
    required this.symbol,
    required this.visible,
    required this.showAssets,
  });

  @override
  Widget build(BuildContext context) {
    final isAssets = showAssets;
    final accentColor = isAssets ? _kGreen : _kRed;
    final title = isAssets ? 'Assets Breakdown' : 'Liabilities Breakdown';
    final total = isAssets ? snapshot.totalAssets : snapshot.totalLiabilities;

    final assetRows = <({String label, double amount, IconData icon, Color bg, Color color})>[];

    if (isAssets) {
      for (final a in snapshot.accounts) {
        final base = a.balance;
        if (!a.account.type.isLiability && base > 0) {
          assetRows.add((
            label: a.account.name,
            amount: base,
            icon: _iconForType(a.account.type),
            bg: _bgForType(a.account.type),
            color: _colorForType(a.account.type),
          ));
        }
      }
      if (snapshot.totalLent > 0) {
        assetRows.add((
          label: 'Lent Out',
          amount: snapshot.totalLent,
          icon: CupertinoIcons.arrow_up_right_circle_fill,
          bg: const Color(0xFFE8F5E9),
          color: _kGreen,
        ));
      }
    } else {
      for (final a in snapshot.accounts) {
        final base = a.balance;
        if (a.account.type.isLiability && base < 0) {
          assetRows.add((
            label: a.account.name,
            amount: base.abs(),
            icon: _iconForType(a.account.type),
            bg: _bgForType(a.account.type),
            color: _colorForType(a.account.type),
          ));
        } else if (!a.account.type.isLiability && base < 0) {
          assetRows.add((
            label: a.account.name,
            amount: base.abs(),
            icon: _iconForType(a.account.type),
            bg: const Color(0xFFFEE2E2),
            color: _kRed,
          ));
        }
      }
      if (snapshot.totalBorrowed > 0) {
        assetRows.add((
          label: 'Borrowed',
          amount: snapshot.totalBorrowed,
          icon: CupertinoIcons.arrow_down_left_circle_fill,
          bg: const Color(0xFFFEE2E2),
          color: _kRed,
        ));
      }
      if ((snapshot.installmentLiability ?? 0) > 0) {
        assetRows.add((
          label: 'Installments',
          amount: snapshot.installmentLiability!,
          icon: CupertinoIcons.bolt_fill,
          bg: const Color(0xFFFCE4EC),
          color: const Color(0xFFE91E63),
        ));
      }
    }

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 18),
              decoration: BoxDecoration(
                color: const Color(0xFFE0E0E6),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title + total
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF0B0B0F)),
              ),
              const Spacer(),
              MaskedAmount(
                visibleText: formatMoney(symbol, total),
                visible: visible,
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: accentColor),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (assetRows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(
                'Nothing to show',
                style: TextStyle(fontSize: 14, color: Colors.grey[500]),
              ),
            )
          else
            for (int i = 0; i < assetRows.length; i++) ...[
              if (i > 0) Divider(height: 1, color: Colors.grey[100]),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: assetRows[i].bg,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(assetRows[i].icon, size: 16, color: assetRows[i].color),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        assetRows[i].label,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF0B0B0F)),
                      ),
                    ),
                    MaskedAmount(
                      visibleText: formatMoney(symbol, assetRows[i].amount),
                      visible: visible,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0B0B0F)),
                    ),
                  ],
                ),
              ),
            ],
        ],
      ),
    );
  }

  IconData _iconForType(AccountType? type) {
    switch (type) {
      case AccountType.cash:       return CupertinoIcons.money_dollar_circle_fill;
      case AccountType.creditCard: return CupertinoIcons.creditcard_fill;
      case AccountType.savings:    return CupertinoIcons.lock_shield_fill;
      default:                     return CupertinoIcons.building_2_fill;
    }
  }

  Color _bgForType(AccountType? type) {
    switch (type) {
      case AccountType.bank:       return const Color(0xFFDBEAFE);
      case AccountType.eWallet:    return const Color(0xFFEDE9FE);
      case AccountType.cash:       return const Color(0xFFDCFCE7);
      case AccountType.savings:    return const Color(0xFFCFFAFE);
      case AccountType.creditCard: return const Color(0xFFFEE2E2);
      case AccountType.investment: return const Color(0xFFFEF3C7);
      default:                     return const Color(0xFFF3F4F6);
    }
  }

  Color _colorForType(AccountType? type) {
    switch (type) {
      case AccountType.bank:       return const Color(0xFF2563EB);
      case AccountType.eWallet:    return const Color(0xFF7C3AED);
      case AccountType.cash:       return const Color(0xFF16A34A);
      case AccountType.savings:    return const Color(0xFF0891B2);
      case AccountType.creditCard: return const Color(0xFFDC2626);
      case AccountType.investment: return const Color(0xFFD97706);
      default:                     return const Color(0xFF6B7280);
    }
  }
}

// ── Grid card (2-col) ─────────────────────────────────────────────────────────

class _GridCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String amount;
  final String subtitle;
  final Color subtitleColor;
  final bool visible;
  final VoidCallback onTap;

  const _GridCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.amount,
    required this.subtitle,
    required this.subtitleColor,
    required this.visible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(_kRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(9)),
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E96), fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 2),
            visible
                ? Text(amount, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0B0B0F)), maxLines: 1, overflow: TextOverflow.ellipsis)
                : const Text('••••', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF8E8E96))),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 10, color: subtitleColor, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ── Full-width card ───────────────────────────────────────────────────────────

// ── Asset snapshot (computation) ──────────────────────────────────────────────

class _AssetSnapshot {
  final List<_AccountAsset> accounts;
  final double netWorth;
  final double totalAssets;
  final double totalLiabilities;
  final double totalLent;
  final double totalBorrowed;
  final List<SavingPlan> activeSavingPlans;
  final double savingPlanSaved;
  final List<Installment> activeInstallments;
  final double? installmentLiability;
  final double weeklyChange;
  final bool hasMultiCurrency;

  bool get hasBorrowLend => totalLent > 0 || totalBorrowed > 0;

  const _AssetSnapshot({
    required this.accounts,
    required this.netWorth,
    required this.totalAssets,
    required this.totalLiabilities,
    required this.totalLent,
    required this.totalBorrowed,
    required this.activeSavingPlans,
    required this.savingPlanSaved,
    required this.activeInstallments,
    required this.installmentLiability,
    required this.weeklyChange,
    this.hasMultiCurrency = false,
  });

  factory _AssetSnapshot.build({
    required List<Account> accounts,
    required List<Expense> expenses,
    required List<SavingPlan> savingPlans,
    required List<BorrowLending> borrowLending,
    required List<Installment> installments,
    CurrencyConverter? converter,
    String? mainCode,
  }) {
    final balances = _computeBalances(accounts, expenses);

    double toBase(Account a, double bal) {
      final code = a.currencyCode ?? mainCode;
      if (converter != null && code != null && code != mainCode) {
        return converter.toBase(bal, code);
      }
      return bal;
    }

    double accountAssetsSum = 0;
    double accountLiabilitiesSum = 0;
    bool multiCurrency = false;

    for (final account in accounts) {
      if (account.currencyCode != null && account.currencyCode != mainCode) {
        multiCurrency = true;
      }
      final bal = balances[account.id] ?? 0;
      final baseBal = toBase(account, bal);
      if (account.type.isLiability) {
        if (baseBal < 0) accountLiabilitiesSum += baseBal.abs();
        if (baseBal > 0) accountAssetsSum += baseBal;
      } else {
        if (baseBal >= 0) {
          accountAssetsSum += baseBal;
        } else {
          accountLiabilitiesSum += baseBal.abs();
        }
      }
    }

    final accountAssets = <_AccountAsset>[
      for (final account in accounts)
        _AccountAsset(account: account, balance: balances[account.id] ?? 0),
    ]..sort((a, b) => b.balance.compareTo(a.balance));

    final activeLending = borrowLending.where(
      (r) =>
          !r.cancelled &&
          r.status != BorrowLendingStatus.settled &&
          r.remaining > 0,
    );
    final totalLent = activeLending
        .where((r) => r.type == BorrowLendingType.lent)
        .fold<double>(0, (sum, r) => sum + r.remaining);
    final totalBorrowed = activeLending
        .where((r) => r.type == BorrowLendingType.borrowed)
        .fold<double>(0, (sum, r) => sum + r.remaining);

    final activeSavings = savingPlans
        .where((p) => p.status == SavingPlanStatus.active)
        .toList(growable: false);
    final savingPlanSaved =
        activeSavings.fold<double>(0, (sum, p) => sum + p.currentAmount);

    final activeInstallments = installments
        .where((i) => i.status == InstallmentStatus.active)
        .toList(growable: false);

    double? installmentLiability;
    for (final inst in activeInstallments) {
      final rem = inst.totalRemaining;
      if (rem != null) {
        installmentLiability = (installmentLiability ?? 0) + rem;
      }
    }

    final totalAssets = accountAssetsSum + totalLent;
    final totalLiabilities = accountLiabilitiesSum + totalBorrowed +
        (installmentLiability ?? 0);
    final netWorth = totalAssets - totalLiabilities;

    // Weekly change
    final weekStart = DateTime.now().subtract(const Duration(days: 7));
    double weeklyChange = 0;
    for (final e in expenses) {
      if (e.date.isAfter(weekStart)) {
        if (e.type == EntryType.income || e.type == EntryType.receive) {
          weeklyChange += e.convertedAmount;
        } else if (e.type == EntryType.expense) {
          weeklyChange -= e.convertedAmount;
        }
      }
    }

    return _AssetSnapshot(
      accounts: accountAssets,
      netWorth: netWorth,
      totalAssets: totalAssets,
      totalLiabilities: totalLiabilities,
      totalLent: totalLent,
      totalBorrowed: totalBorrowed,
      activeSavingPlans: activeSavings,
      savingPlanSaved: savingPlanSaved,
      activeInstallments: activeInstallments,
      installmentLiability: installmentLiability,
      weeklyChange: weeklyChange,
      hasMultiCurrency: multiCurrency,
    );
  }
}

class _AccountAsset {
  final Account account;
  final double balance;
  const _AccountAsset({required this.account, required this.balance});
}

// ── Balance computation ───────────────────────────────────────────────────────

double _effectiveAmountForAccount(Expense expense, String? accountCurrencyCode) {
  if (expense.originalCurrency == accountCurrencyCode) return expense.amount;
  return expense.convertedAmount;
}

Map<String, double> _computeBalances(
  List<Account> accounts,
  List<Expense> expenses,
) {
  final currencyCodes = <String, String?>{
    for (final a in accounts) a.id: a.currencyCode,
  };
  final balances = <String, double>{
    for (final a in accounts) a.id: a.openingBalance,
  };
  for (final expense in expenses) {
    final from = expense.accountId;
    if (from != null && balances.containsKey(from)) {
      final amt = _effectiveAmountForAccount(expense, currencyCodes[from]);
      if (expense.type.isInflow) {
        balances[from] = (balances[from] ?? 0) + amt;
      } else {
        balances[from] = (balances[from] ?? 0) - amt;
      }
    }
    final to = expense.toAccountId;
    if (to != null && balances.containsKey(to)) {
      balances[to] = (balances[to] ?? 0) +
          _effectiveAmountForAccount(expense, currencyCodes[to]);
    }
  }
  return balances;
}
