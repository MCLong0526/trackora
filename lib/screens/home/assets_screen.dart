import 'dart:math' as math;

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
import '../expenses/add_edit_expense_screen.dart';
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

    // Balances for credit card display
    final balances = _computeBalances(accounts, expenses);

    // Credit card accounts
    final creditCards = accounts.where((a) => a.type == AccountType.creditCard).toList();

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
                // ── Top row: Net Worth + Budget/Savings ────────
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Net Worth card (left, 2/3 width)
                      Expanded(
                        flex: 2,
                        child: _NetWorthCard(
                          snapshot: snapshot,
                          symbol: symbol,
                          visible: visible,
                        ),
                      ),
                      const SizedBox(width: 10),
                      // Budget + Savings (right, 1/3 width)
                      Expanded(
                        flex: 1,
                        child: Column(
                          children: [
                            Expanded(
                              child: _MiniCard(
                                icon: CupertinoIcons.timer,
                                iconBg: const Color(0xFFFFF3E0),
                                iconColor: _kOrange,
                                title: 'Budget',
                                amount: budget > 0
                                    ? formatMoney(symbol, budgetRemaining)
                                    : '—',
                                subtitle: budget > 0
                                    ? 'left this month'
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
                            const SizedBox(height: 10),
                            Expanded(
                              child: _MiniCard(
                                icon: CupertinoIcons.flag_fill,
                                iconBg: const Color(0xFFE8F5E9),
                                iconColor: _kGreen,
                                title: 'Savings',
                                amount: formatMoney(symbol, totalSaved),
                                subtitle: totalGoal > 0
                                    ? '${savingPlans.where((p) => p.status == SavingPlanStatus.active).length} of ${formatMoney(symbol, totalGoal)} goal'
                                    : 'no active plans',
                                subtitleColor: totalSaved > 0 ? _kGreen : _kOrange,
                                visible: visible,
                                onTap: () => _push(context, const SavingPlansScreen()),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 10),

                // ── Middle grid: Borrow & Lend | Installments | Travel ─
                Row(
                  children: [
                    Expanded(
                      child: _GridCard(
                        icon: CupertinoIcons.arrow_up_arrow_down,
                        iconBg: const Color(0xFFFFF3E0),
                        iconColor: _kOrange,
                        title: 'Borrow & Lend',
                        amount: formatMoney(symbol, borrowNet.abs()),
                        subtitle: borrowNet >= 0 ? 'net owed to you' : 'you owe, net',
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
                        subtitleColor: const Color(0xFF8E8E96),
                        visible: visible,
                        onTap: () => _push(context, const InstallmentsScreen()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _GridCard(
                        icon: CupertinoIcons.airplane,
                        iconBg: const Color(0xFFE3F2FD),
                        iconColor: _kBlue,
                        title: 'Travel Group',
                        amount: '${travelGroups.length}',
                        subtitle: latestGroup?.name ?? (travelGroups.isEmpty ? 'no trips' : '${travelGroups.length} trips'),
                        subtitleColor: const Color(0xFF8E8E96),
                        visible: visible,
                        onTap: () => _push(context, const TravelGroupsScreen()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                // ── Bottom grid: Stocks | Precious Metal ──────────
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

                // ── Credit Card section ────────────────────────────
                if (creditCards.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _CreditCardSection(
                    creditCards: creditCards,
                    balances: balances,
                    symbol: symbol,
                    visible: visible,
                  ),
                ],
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

// ── Credit Card section ───────────────────────────────────────────────────────

class _CreditCardSection extends StatelessWidget {
  final List<Account> creditCards;
  final Map<String, double> balances;
  final String symbol;
  final bool visible;

  const _CreditCardSection({
    required this.creditCards,
    required this.balances,
    required this.symbol,
    required this.visible,
  });

  @override
  Widget build(BuildContext ctx) {
    return Column(
      children: [
        for (final card in creditCards) ...[
          _CreditCardTile(
            card: card,
            balance: balances[card.id] ?? 0,
            symbol: symbol,
            visible: visible,
            onPay: () => _openPaySheet(ctx, card),
          ),
          if (card != creditCards.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  void _openPaySheet(BuildContext ctx, Account card) {
    HapticFeedback.selectionClick();
    Navigator.push(
      ctx,
      CupertinoPageRoute(
        builder: (_) => AddEditExpenseScreen(
          initialType: EntryType.transfer,
          initialToAccountId: card.id,
        ),
      ),
    );
  }
}

// ── Single credit card tile ───────────────────────────────────────────────────

class _CreditCardTile extends StatelessWidget {
  final Account card;
  final double balance;
  final String symbol;
  final bool visible;
  final VoidCallback onPay;

  const _CreditCardTile({
    required this.card,
    required this.balance,
    required this.symbol,
    required this.visible,
    required this.onPay,
  });

  @override
  Widget build(BuildContext context) {
    // Credit card has a negative balance when in use (debt)
    final isDebt = balance < 0;
    final displayBalance = balance.abs();

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: _kCard,
        borderRadius: BorderRadius.circular(_kRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: icon + type label + card name
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: isDebt
                      ? const Color(0xFFFFEEEE)
                      : const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  CupertinoIcons.creditcard_fill,
                  size: 16,
                  color: isDebt ? _kRed : _kGreen,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CREDIT CARD',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF8E8E96),
                        letterSpacing: 0.5,
                      ),
                    ),
                    Text(
                      card.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B0B0F),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Balance row
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDebt ? 'Amount owed' : 'Credit balance',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8E8E96),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    MaskedAmount(
                      visibleText: '${isDebt ? '−' : ''}${formatMoney(symbol, displayBalance)}',
                      visible: visible,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: isDebt ? _kRed : _kGreen,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ],
                ),
              ),
              // Pay Card button
              GestureDetector(
                onTap: onPay,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDebt
                        ? const Color(0xFF1A6CFF)
                        : const Color(0xFFE8F5E9),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        CupertinoIcons.arrow_up_circle_fill,
                        size: 15,
                        color: isDebt ? Colors.white : _kGreen,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Pay Card',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: isDebt ? Colors.white : _kGreen,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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

  @override
  Widget build(BuildContext context) {
    final netWorth = snapshot.netWorth;
    final totalOwn = snapshot.totalAssets;
    final totalOwe = snapshot.totalLiabilities;
    final total = totalOwn + totalOwe;
    final ownedPct = total > 0 ? (totalOwn / total).clamp(0.0, 1.0) : 1.0;
    final ownedPctInt = (ownedPct * 100).round();

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
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
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
                'TOTAL NET WORTH',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF8E8E96),
                  letterSpacing: 0.5,
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
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0B0B0F),
              letterSpacing: -0.5,
            ),
          ),

          const SizedBox(height: 16),

          // Donut chart + legend
          Row(
            children: [
              // Donut
              SizedBox(
                width: 80,
                height: 80,
                child: CustomPaint(
                  painter: _DonutPainter(ownedPct: ownedPct),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$ownedPctInt%',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF0B0B0F)),
                        ),
                        const Text('OWNED', style: TextStyle(fontSize: 7, fontWeight: FontWeight.w600, color: Color(0xFF8E8E96), letterSpacing: 0.3)),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(width: 14),

              // Legend
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: _kGreen, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('You own', style: TextStyle(fontSize: 11, color: Color(0xFF5B5B66))),
                      ],
                    ),
                    const SizedBox(height: 2),
                    MaskedAmount(
                      visibleText: formatMoney(symbol, totalOwn),
                      visible: visible,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0B0B0F)),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: _kRed, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        const Text('You owe', style: TextStyle(fontSize: 11, color: Color(0xFF5B5B66))),
                      ],
                    ),
                    const SizedBox(height: 2),
                    MaskedAmount(
                      visibleText: formatMoney(symbol, totalOwe),
                      visible: visible,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0B0B0F)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Donut painter ─────────────────────────────────────────────────────────────

class _DonutPainter extends CustomPainter {
  final double ownedPct; // 0.0–1.0

  const _DonutPainter({required this.ownedPct});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 6;
    const strokeWidth = 10.0;

    final bgPaint = Paint()
      ..color = const Color(0xFFF2F1F6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final ownPaint = Paint()
      ..color = _kGreen
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final owePaint = Paint()
      ..color = _kRed
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final rect = Rect.fromCircle(center: center, radius: radius);
    const startAngle = -math.pi / 2;

    // Background track
    canvas.drawArc(rect, 0, 2 * math.pi, false, bgPaint);

    // Green arc (owned)
    if (ownedPct > 0) {
      canvas.drawArc(rect, startAngle, 2 * math.pi * ownedPct, false, ownPaint);
    }
    // Red arc (owed)
    if (ownedPct < 1) {
      canvas.drawArc(
        rect,
        startAngle + 2 * math.pi * ownedPct,
        2 * math.pi * (1 - ownedPct),
        false,
        owePaint,
      );
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.ownedPct != ownedPct;
}

// ── Mini card (Budget, Savings) ───────────────────────────────────────────────

class _MiniCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String amount;
  final String subtitle;
  final Color subtitleColor;
  final bool visible;
  final VoidCallback onTap;

  const _MiniCard({
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
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
        decoration: BoxDecoration(
          color: _kCard,
          borderRadius: BorderRadius.circular(_kRadius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: iconColor, size: 15),
            ),
            const SizedBox(height: 8),
            Text(title, style: const TextStyle(fontSize: 11, color: Color(0xFF8E8E96), fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            visible
                ? Text(amount, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF0B0B0F)), maxLines: 1, overflow: TextOverflow.ellipsis)
                : const Text('••••', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF8E8E96))),
            const SizedBox(height: 2),
            Text(subtitle, style: TextStyle(fontSize: 10, color: subtitleColor, fontWeight: FontWeight.w500), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

// ── Grid card (3-col) ─────────────────────────────────────────────────────────

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
