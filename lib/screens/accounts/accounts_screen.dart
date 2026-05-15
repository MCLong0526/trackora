import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/account.dart';
import '../../models/expense.dart';
import '../../models/precious_metal.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/account_carousel_section.dart';
import '../../widgets/masked_amount.dart';
import '../precious_metals/precious_metals_screen.dart';

// ── AccountsScreen ────────────────────────────────────────────
class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final accountsAsync = ref.watch(accountsProvider);
    final allExpensesAsync = ref.watch(allExpensesProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final visible = ref.watch(balanceVisibleProvider);
    final metals =
        ref.watch(preciousMetalsProvider).valueOrNull ?? const <PreciousMetal>[];

    final accounts = accountsAsync.valueOrNull ?? const <Account>[];
    final allExpenses = allExpensesAsync.valueOrNull ?? const <Expense>[];
    final balances = _computeBalances(accounts, allExpenses);

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        title: Text(context.t('account.title')),
        actions: [
          IconButton(
            icon: Icon(
              visible ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
              size: 22,
            ),
            onPressed: () =>
                ref.read(balanceVisibleProvider.notifier).toggle(),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.add, size: 22),
            onPressed: () => showAddAccountSheet(context),
          ),
        ],
      ),
      body: SafeArea(
        child: CustomScrollView(
          clipBehavior: Clip.none,
          slivers: [
            if (accounts.isEmpty)
              SliverToBoxAdapter(child: _empty(context, brand))
            else
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: AccountCarouselSection(
                    accounts: accounts,
                    balances: balances,
                    allExpenses: allExpenses,
                    symbol: symbol,
                    visible: visible,
                  ),
                ),
              ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
                child: Text(
                  context.t('account.preciousMetals'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: brand.inkSoft,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              sliver: SliverToBoxAdapter(
                child: _PreciousMetalsCard(
                  metals: metals,
                  symbol: symbol,
                  visible: visible,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Map<String, double> _computeBalances(
    List<Account> accounts,
    List<Expense> expenses,
  ) {
    final balances = <String, double>{};
    for (final a in accounts) {
      balances[a.id] = a.openingBalance;
    }
    for (final e in expenses) {
      final aid = e.accountId;
      if (aid != null && balances.containsKey(aid)) {
        balances[aid] = (balances[aid] ?? 0) +
            (e.type.isInflow ? e.amount : -e.amount);
      }
      final toId = e.toAccountId;
      if (toId != null && balances.containsKey(toId)) {
        balances[toId] = (balances[toId] ?? 0) + e.amount;
      }
    }
    return balances;
  }

  Widget _empty(BuildContext context, BrandColors brand) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: AppColors.sky,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                CupertinoIcons.creditcard,
                size: 30,
                color: AppActionBlue.color,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.t('account.noAccounts'),
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: brand.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.t('account.noAccountsHint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: brand.inkSoft),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(CupertinoIcons.add, size: 18),
              label: Text(context.t('account.addAccount')),
              onPressed: () => showAddAccountSheet(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Precious Metals Card ──────────────────────────────────────
class _PreciousMetalsCard extends StatelessWidget {
  final List<PreciousMetal> metals;
  final String symbol;
  final bool visible;

  const _PreciousMetalsCard({
    required this.metals,
    required this.symbol,
    required this.visible,
  });

  Map<MetalType, double> get _holdings {
    final map = <MetalType, double>{};
    for (final m in metals) {
      final cur = map[m.metalType] ?? 0.0;
      map[m.metalType] = m.action == MetalAction.buy
          ? cur + m.weightGrams
          : cur - m.weightGrams;
    }
    return map;
  }

  double get _totalValue {
    double t = 0;
    for (final m in metals) {
      t += m.action == MetalAction.buy ? m.totalAmount : -m.totalAmount;
    }
    return t.abs();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final holdings = _holdings;
    final goldGrams = holdings[MetalType.gold] ?? 0.0;
    final silverGrams = holdings[MetalType.silver] ?? 0.0;

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        CupertinoPageRoute(builder: (_) => const PreciousMetalsScreen()),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(18),
          ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3C4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                CupertinoIcons.circle_grid_hex_fill,
                size: 22,
                color: Color(0xFFD4AF37),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.t('account.preciousMetals'),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (metals.isEmpty)
                    Text(
                      context.t('account.tapToTrack'),
                      style: TextStyle(fontSize: 12, color: brand.inkSoft),
                    )
                  else
                    Wrap(
                      spacing: 10,
                      children: [
                        if (goldGrams != 0)
                          _MetalChip(
                            label: '${goldGrams.toStringAsFixed(2)}g Gold',
                            color: const Color(0xFFD4AF37),
                            bg: const Color(0xFFFFF3C4),
                          ),
                        if (silverGrams != 0)
                          _MetalChip(
                            label: '${silverGrams.toStringAsFixed(2)}g Silver',
                            color: const Color(0xFF9BA5B0),
                            bg: const Color(0xFFECEDF0),
                          ),
                      ],
                    ),
                ],
              ),
            ),
            if (metals.isNotEmpty) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  MaskedAmount(
                    visibleText: formatMoney(symbol, _totalValue),
                    visible: visible,
                    currencyPrefix: symbol,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: brand.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${metals.length} record${metals.length == 1 ? '' : 's'}',
                    style: TextStyle(fontSize: 11, color: brand.inkSoft),
                  ),
                ],
              ),
              const SizedBox(width: 6),
            ],
            Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: brand.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

class _MetalChip extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;

  const _MetalChip({required this.label, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Public helpers ────────────────────────────────────────────
double computeAccountBalance(Account account, List<Expense> expenses) {
  double balance = account.openingBalance;
  for (final e in expenses) {
    if (e.accountId == account.id) {
      if (e.type.isInflow) {
        balance += e.amount;
      } else {
        balance -= e.amount;
      }
    }
    if (e.toAccountId == account.id) {
      balance += e.amount;
    }
  }
  return balance;
}

double computeTotalAccountBalance(
  List<Account> accounts,
  List<Expense> expenses,
) {
  return accounts.fold<double>(
    0,
    (sum, a) => sum + computeAccountBalance(a, expenses),
  );
}
