import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../models/expense.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/masked_amount.dart';
import '../../widgets/section_card.dart';
import 'add_edit_account_screen.dart';

class AccountsScreen extends ConsumerWidget {
  const AccountsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final accountsAsync = ref.watch(accountsProvider);
    final allExpensesAsync = ref.watch(allExpensesProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final visible = ref.watch(balanceVisibleProvider);

    final accounts = accountsAsync.valueOrNull ?? const <Account>[];
    final allExpenses = allExpensesAsync.valueOrNull ?? const <Expense>[];

    final balances = _computeBalances(accounts, allExpenses);
    final totalBalance = balances.values.fold<double>(0, (s, v) => s + v);

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        title: const Text('Accounts'),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.add, size: 22),
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => const AddEditAccountScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: accounts.isEmpty
            ? _empty(context, brand)
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: _TotalCard(
                        symbol: symbol,
                        total: totalBalance,
                        visible: visible,
                        ref: ref,
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                    sliver: SliverList.separated(
                      itemCount: accounts.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        final account = accounts[i];
                        final balance = balances[account.id] ?? 0.0;
                        return _AccountCard(
                          account: account,
                          balance: balance,
                          symbol: symbol,
                          visible: visible,
                          onTap: () => Navigator.push(
                            ctx,
                            CupertinoPageRoute(
                              builder: (_) =>
                                  AddEditAccountScreen(account: account),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 40)),
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
        if (e.type.isInflow) {
          balances[aid] = (balances[aid] ?? 0) + e.amount;
        } else {
          balances[aid] = (balances[aid] ?? 0) - e.amount;
        }
      }
      // Credit destination for account-to-account transfers
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
                color: Color(0xFF2A6FB5),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No accounts yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: brand.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Add a bank, e-wallet, or cash account to start tracking your money.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: brand.inkSoft),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(CupertinoIcons.add, size: 18),
              label: const Text('Add Account'),
              onPressed: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => const AddEditAccountScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String symbol;
  final double total;
  final bool visible;
  final WidgetRef ref;

  const _TotalCard({
    required this.symbol,
    required this.total,
    required this.visible,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SectionCard(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'TOTAL BALANCE',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: brand.inkSoft,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () =>
                    ref.read(balanceVisibleProvider.notifier).toggle(),
                behavior: HitTestBehavior.opaque,
                child: Icon(
                  visible ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  size: 20,
                  color: brand.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          MaskedAmount(
            visibleText: formatMoney(symbol, total),
            visible: visible,
            currencyPrefix: symbol,
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w900,
              color: total >= 0 ? brand.ink : AppColors.expense,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Across all accounts',
            style: TextStyle(fontSize: 12, color: brand.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  final Account account;
  final double balance;
  final String symbol;
  final bool visible;
  final VoidCallback onTap;

  const _AccountCard({
    required this.account,
    required this.balance,
    required this.symbol,
    required this.visible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final style = _styleFor(account.type);
    final icon = _iconFor(account.type);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF6366F1).withValues(alpha: 0.05),
              blurRadius: 12,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: style.bg,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, size: 22, color: style.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    account.type.label,
                    style: TextStyle(
                      fontSize: 12,
                      color: brand.inkSoft,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MaskedAmount(
                  visibleText: formatMoney(symbol, balance),
                  visible: visible,
                  currencyPrefix: symbol,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: balance >= 0 ? brand.ink : AppColors.expense,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('MMM d').format(account.createdAt),
                  style: TextStyle(fontSize: 11, color: brand.inkSoft),
                ),
              ],
            ),
            const SizedBox(width: 6),
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

  ({Color bg, Color accent}) _styleFor(AccountType type) {
    switch (type) {
      case AccountType.bank:
        return (bg: AppColors.sky, accent: const Color(0xFF2A6FB5));
      case AccountType.eWallet:
        return (bg: AppColors.mint, accent: const Color(0xFF1F7A60));
      case AccountType.cash:
        return (bg: AppColors.butter, accent: const Color(0xFFA0801C));
    }
  }

  IconData _iconFor(AccountType type) {
    switch (type) {
      case AccountType.bank:
        return CupertinoIcons.building_2_fill;
      case AccountType.eWallet:
        return CupertinoIcons.device_phone_portrait;
      case AccountType.cash:
        return CupertinoIcons.money_dollar_circle_fill;
    }
  }
}

/// Public helper to compute a single account's balance from a list of expenses.
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
    // Credit this account when it is the destination of an account-to-account transfer
    if (e.toAccountId == account.id) {
      balance += e.amount;
    }
  }
  return balance;
}

/// Compute total balance across all accounts.
double computeTotalAccountBalance(
  List<Account> accounts,
  List<Expense> expenses,
) {
  return accounts.fold<double>(
    0,
    (sum, a) => sum + computeAccountBalance(a, expenses),
  );
}
