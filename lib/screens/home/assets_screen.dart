import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/account.dart';
import '../../models/borrow_lending.dart';
import '../../models/expense.dart';
import '../../models/installment.dart';
import '../../models/saving_plan.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/masked_amount.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/section_card.dart';
import '../accounts/accounts_screen.dart';
import '../accounts/add_edit_account_screen.dart';

class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {
  final _expanded = <AccountType, bool>{
    AccountType.bank: false,
    AccountType.eWallet: false,
    AccountType.cash: false,
    AccountType.creditCard: false,
    AccountType.loan: false,
    AccountType.mortgage: false,
    AccountType.bnpl: false,
    AccountType.otherLiability: false,
  };

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(accountsProvider);
    final expensesAsync = ref.watch(allExpensesProvider);
    final savingPlansAsync = ref.watch(savingPlansProvider);
    final borrowLendingAsync = ref.watch(borrowLendingProvider);
    final installmentsAsync = ref.watch(installmentsProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final visible = ref.watch(balanceVisibleProvider);

    final accounts = accountsAsync.valueOrNull ?? const <Account>[];
    final expenses = expensesAsync.valueOrNull ?? const <Expense>[];
    final savingPlans = savingPlansAsync.valueOrNull ?? const <SavingPlan>[];
    final borrowLending =
        borrowLendingAsync.valueOrNull ?? const <BorrowLending>[];
    final installments =
        installmentsAsync.valueOrNull ?? const <Installment>[];

    final snapshot = _AssetSnapshot.build(
      accounts: accounts,
      expenses: expenses,
      savingPlans: savingPlans,
      borrowLending: borrowLending,
      installments: installments,
    );
    final isLoading =
        accountsAsync.maybeWhen(loading: () => true, orElse: () => false);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                _Header(
                  onAddAccount: () =>
                      _push(context, const AddEditAccountScreen()),
                ),
                const SizedBox(height: 18),
                if (isLoading && accounts.isEmpty)
                  const _LoadingCard()
                else ...[
                  _NetWorthCard(
                    snapshot: snapshot,
                    symbol: symbol,
                    visible: visible,
                  ),
                  const SizedBox(height: 20),
                  if (accounts.isEmpty)
                    _EmptyAccounts(
                      onTap: () => _push(context, const AddEditAccountScreen()),
                    )
                  else ...[
                    _SectionLabel('Accounts'),
                    const SizedBox(height: 8),
                    _AccountsCard(
                      snapshot: snapshot,
                      symbol: symbol,
                      visible: visible,
                      expanded: _expanded,
                      onToggle: (type) => setState(
                        () => _expanded[type] = !(_expanded[type] ?? false),
                      ),
                      onAccountTap: (item) => _push(
                        context,
                        AddEditAccountScreen(account: item.account),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _ManageRow(
                      onManage: () => _push(context, const AccountsScreen()),
                      onAdd: () => _push(context, const AddEditAccountScreen()),
                    ),
                  ],
                  if (snapshot.hasBorrowLend) ...[
                    const SizedBox(height: 20),
                    _SectionLabel('Money Flow'),
                    const SizedBox(height: 8),
                    _BorrowLendCard(
                      snapshot: snapshot,
                      symbol: symbol,
                      visible: visible,
                    ),
                  ],
                  if (snapshot.activeSavingPlans.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _SectionLabel('Savings'),
                    const SizedBox(height: 8),
                    _SavingPlansCard(
                      snapshot: snapshot,
                      symbol: symbol,
                      visible: visible,
                    ),
                  ],
                  if (snapshot.activeInstallments.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _SectionLabel('Installments'),
                    const SizedBox(height: 8),
                    _InstallmentsCard(
                      snapshot: snapshot,
                      symbol: symbol,
                      visible: visible,
                    ),
                  ],
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w800,
        letterSpacing: 0.6,
        color: context.brand.inkSoft,
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  final VoidCallback onAddAccount;
  const _Header({required this.onAddAccount});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assets',
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 2),
              Text(
                'Your complete financial picture',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: brand.inkSoft,
                ),
              ),
            ],
          ),
        ),
        const ProfileAvatarButton(),
      ],
    );
  }
}

// ── Net Worth Hero Card ───────────────────────────────────────────────────────

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
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF201E2C) : const Color(0xFFEDE9FF);
    final ink = isDark ? brand.ink : const Color(0xFF111028);
    final soft = isDark ? brand.inkSoft : const Color(0xFF686176);
    final netWorth = snapshot.netWorth;
    final netColor = netWorth < 0 ? AppColors.expense : ink;

    return SectionCard(
      color: bg,
      pastel: !isDark,
      radius: 26,
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top row: NET WORTH label
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.chart_pie_fill,
                    size: 11,
                    color: soft,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    'NET WORTH',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.7,
                      color: soft,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Large net worth amount
          MaskedAmount(
            visibleText: formatMoney(symbol, netWorth),
            visible: visible,
            currencyPrefix: symbol,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 40,
              fontWeight: FontWeight.w900,
              color: netColor,
              height: 1.0,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            '${snapshot.accounts.length} account${snapshot.accounts.length == 1 ? '' : 's'} tracked',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: soft,
            ),
          ),
          const SizedBox(height: 20),
          // Asset/liability split bar
          _AssetLiabilityBar(snapshot: snapshot),
          const SizedBox(height: 8),
          // Small split labels
          Row(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.income,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Assets',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: soft,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Liabilities',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: soft,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: AppColors.expense,
                      shape: BoxShape.circle,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Subtle divider
          Container(
            height: 0.5,
            color: soft.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 16),
          // Assets & Liabilities tiles
          Row(
            children: [
              Expanded(
                child: _WorthTile(
                  label: 'Assets',
                  value: snapshot.totalAssets,
                  symbol: symbol,
                  visible: visible,
                  color: AppColors.income,
                  icon: CupertinoIcons.arrow_up_right,
                  isDark: isDark,
                  onTap: () => _showBreakdown(
                    context,
                    title: 'Assets',
                    color: AppColors.income,
                    icon: CupertinoIcons.arrow_up_right,
                    items: _buildAssetItems(snapshot),
                    total: snapshot.totalAssets,
                    symbol: symbol,
                    visible: visible,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _WorthTile(
                  label: 'Liabilities',
                  value: snapshot.totalLiabilities,
                  symbol: symbol,
                  visible: visible,
                  color: AppColors.expense,
                  icon: CupertinoIcons.arrow_down_right,
                  isDark: isDark,
                  onTap: () => _showBreakdown(
                    context,
                    title: 'Liabilities',
                    color: AppColors.expense,
                    icon: CupertinoIcons.arrow_down_right,
                    items: _buildLiabilityItems(snapshot),
                    total: snapshot.totalLiabilities,
                    symbol: symbol,
                    visible: visible,
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

class _AssetLiabilityBar extends StatelessWidget {
  final _AssetSnapshot snapshot;
  const _AssetLiabilityBar({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final total = snapshot.totalAssets + snapshot.totalLiabilities;
    final assetRatio = total > 0 ? (snapshot.totalAssets / total).clamp(0.0, 1.0) : 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 7,
            width: constraints.maxWidth,
            child: Row(
              children: [
                Expanded(
                  flex: (assetRatio * 100).round(),
                  child: Container(color: AppColors.income),
                ),
                if (assetRatio < 1.0)
                  Expanded(
                    flex: ((1 - assetRatio) * 100).round(),
                    child: Container(color: AppColors.expense),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WorthTile extends StatelessWidget {
  final String label;
  final double value;
  final String symbol;
  final bool visible;
  final Color color;
  final IconData icon;
  final bool isDark;
  final VoidCallback? onTap;

  const _WorthTile({
    required this.label,
    required this.value,
    required this.symbol,
    required this.visible,
    required this.color,
    required this.icon,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.07)
              : Colors.white.withValues(alpha: 0.54),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 11, color: color),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
                if (onTap != null)
                  Icon(CupertinoIcons.chevron_right, size: 10, color: color.withValues(alpha: 0.6)),
              ],
            ),
            const SizedBox(height: 6),
            MaskedAmount(
              visibleText: formatMoney(symbol, value),
              visible: visible,
              currencyPrefix: symbol,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: brand.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Accounts Card (all types grouped in one card) ─────────────────────────────

class _AccountsCard extends StatelessWidget {
  final _AssetSnapshot snapshot;
  final String symbol;
  final bool visible;
  final Map<AccountType, bool> expanded;
  final ValueChanged<AccountType> onToggle;
  final ValueChanged<_AccountAsset> onAccountTap;

  const _AccountsCard({
    required this.snapshot,
    required this.symbol,
    required this.visible,
    required this.expanded,
    required this.onToggle,
    required this.onAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final types = AccountType.values
        .where((t) => snapshot.typeAccounts(t).isNotEmpty)
        .toList();

    return SectionCard(
      radius: 22,
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (var ti = 0; ti < types.length; ti++) ...[
            if (ti > 0)
              Divider(height: 1, thickness: 1, color: brand.divider),
            _AccountTypeSection(
              type: types[ti],
              accounts: snapshot.typeAccounts(types[ti]),
              typeTotal: snapshot.typeTotal(types[ti]),
              symbol: symbol,
              visible: visible,
              expanded: expanded[types[ti]] ?? false,
              onToggle: () => onToggle(types[ti]),
              onAccountTap: onAccountTap,
            ),
          ],
        ],
      ),
    );
  }
}

class _AccountTypeSection extends StatelessWidget {
  final AccountType type;
  final List<_AccountAsset> accounts;
  final double typeTotal;
  final String symbol;
  final bool visible;
  final bool expanded;
  final VoidCallback onToggle;
  final ValueChanged<_AccountAsset> onAccountTap;

  const _AccountTypeSection({
    required this.type,
    required this.accounts,
    required this.typeTotal,
    required this.symbol,
    required this.visible,
    required this.expanded,
    required this.onToggle,
    required this.onAccountTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final style = _styleFor(type);

    return Column(
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: style.bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(_iconFor(type), size: 16, color: style.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    type.label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: brand.ink,
                    ),
                  ),
                ),
                MaskedAmount(
                  visibleText: formatMoney(symbol, typeTotal),
                  visible: visible,
                  currencyPrefix: symbol,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: typeTotal < 0 ? AppColors.expense : brand.ink,
                  ),
                ),
                const SizedBox(width: 6),
                AnimatedRotation(
                  turns: expanded ? 0 : -0.25,
                  duration: const Duration(milliseconds: 200),
                  child: Icon(
                    CupertinoIcons.chevron_down,
                    size: 13,
                    color: brand.inkSoft,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded) ...[
          Divider(height: 1, thickness: 1, color: brand.divider),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: Column(
              children: [
                for (var i = 0; i < accounts.length; i++) ...[
                  _AccountRow(
                    item: accounts[i],
                    symbol: symbol,
                    visible: visible,
                    onTap: () => onAccountTap(accounts[i]),
                  ),
                  if (i < accounts.length - 1)
                    Divider(
                      height: 16,
                      thickness: 1,
                      color: brand.divider.withValues(alpha: 0.5),
                    ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _AccountRow extends StatelessWidget {
  final _AccountAsset item;
  final String symbol;
  final bool visible;
  final VoidCallback onTap;

  const _AccountRow({
    required this.item,
    required this.symbol,
    required this.visible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(
              child: Text(
                item.account.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
                ),
              ),
            ),
            const SizedBox(width: 12),
            MaskedAmount(
              visibleText: formatMoney(symbol, item.balance),
              visible: visible,
              currencyPrefix: symbol,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: item.balance < 0 ? AppColors.expense : brand.ink,
              ),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right, size: 12, color: brand.inkSoft),
          ],
        ),
      ),
    );
  }
}

// ── Manage Row ────────────────────────────────────────────────────────────────

class _ManageRow extends StatelessWidget {
  final VoidCallback onManage;
  final VoidCallback onAdd;

  const _ManageRow({required this.onManage, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      children: [
        Expanded(
          child: _ActionButton(
            icon: CupertinoIcons.add_circled,
            label: 'Add Account',
            color: brand.accentDark,
            onTap: onAdd,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _ActionButton(
            icon: CupertinoIcons.list_bullet,
            label: 'Manage',
            color: brand.inkSoft,
            onTap: onManage,
          ),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Borrow / Lend Card ────────────────────────────────────────────────────────

class _BorrowLendCard extends StatelessWidget {
  final _AssetSnapshot snapshot;
  final String symbol;
  final bool visible;

  const _BorrowLendCard({
    required this.snapshot,
    required this.symbol,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          Expanded(
            child: _FlowTile(
              label: 'You Lent',
              sublabel: 'Others owe you',
              value: snapshot.totalLent,
              symbol: symbol,
              visible: visible,
              color: AppColors.income,
              icon: CupertinoIcons.arrow_up_right,
            ),
          ),
          Container(
            width: 1,
            height: 56,
            color: context.brand.divider,
            margin: const EdgeInsets.symmetric(horizontal: 12),
          ),
          Expanded(
            child: _FlowTile(
              label: 'You Owe',
              sublabel: 'You borrowed',
              value: snapshot.totalBorrowed,
              symbol: symbol,
              visible: visible,
              color: AppColors.expense,
              icon: CupertinoIcons.arrow_down_right,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlowTile extends StatelessWidget {
  final String label;
  final String sublabel;
  final double value;
  final String symbol;
  final bool visible;
  final Color color;
  final IconData icon;

  const _FlowTile({
    required this.label,
    required this.sublabel,
    required this.value,
    required this.symbol,
    required this.visible,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        MaskedAmount(
          visibleText: formatMoney(symbol, value),
          visible: visible,
          currencyPrefix: symbol,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w900,
            color: brand.ink,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          sublabel,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: brand.inkSoft,
          ),
        ),
      ],
    );
  }
}

// ── Saving Plans Card ─────────────────────────────────────────────────────────

class _SavingPlansCard extends StatelessWidget {
  final _AssetSnapshot snapshot;
  final String symbol;
  final bool visible;

  const _SavingPlansCard({
    required this.snapshot,
    required this.symbol,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final plans = snapshot.activeSavingPlans;

    return SectionCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${plans.length} active plan${plans.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: brand.inkSoft,
                  ),
                ),
              ),
              MaskedAmount(
                visibleText: formatMoney(symbol, snapshot.savingPlanSaved),
                visible: visible,
                currencyPrefix: symbol,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF1F7A60),
                ),
              ),
              const SizedBox(width: 2),
              const Text(
                ' saved',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F7A60),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < plans.length; i++) ...[
            _SavingPlanRow(plan: plans[i], symbol: symbol, visible: visible),
            if (i < plans.length - 1) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: brand.divider),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _SavingPlanRow extends StatelessWidget {
  final SavingPlan plan;
  final String symbol;
  final bool visible;

  const _SavingPlanRow({
    required this.plan,
    required this.symbol,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final progress = plan.progress;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                plan.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: brand.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            MaskedAmount(
              visibleText:
                  '${formatMoney(symbol, plan.currentAmount)} / ${formatMoney(symbol, plan.targetAmount)}',
              visible: visible,
              currencyPrefix: symbol,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: brand.inkSoft,
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: progress),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => LinearProgressIndicator(
              value: value,
              minHeight: 5,
              backgroundColor: brand.divider,
              valueColor: const AlwaysStoppedAnimation(Color(0xFF1F7A60)),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(progress * 100).round()}% saved',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: brand.inkSoft,
          ),
        ),
      ],
    );
  }
}

// ── Installments Card ─────────────────────────────────────────────────────────

class _InstallmentsCard extends StatelessWidget {
  final _AssetSnapshot snapshot;
  final String symbol;
  final bool visible;

  const _InstallmentsCard({
    required this.snapshot,
    required this.symbol,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final items = snapshot.activeInstallments;
    final totalRemaining = snapshot.installmentLiability;

    return SectionCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${items.length} active plan${items.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: brand.inkSoft,
                  ),
                ),
              ),
              if (totalRemaining != null) ...[
                MaskedAmount(
                  visibleText: formatMoney(symbol, totalRemaining),
                  visible: visible,
                  currencyPrefix: symbol,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w900,
                    color: AppColors.expense,
                  ),
                ),
                const SizedBox(width: 2),
                const Text(
                  ' remaining',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.expense,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < items.length; i++) ...[
            _InstallmentRow(
              item: items[i],
              symbol: symbol,
              visible: visible,
            ),
            if (i < items.length - 1) ...[
              const SizedBox(height: 10),
              Divider(height: 1, color: brand.divider),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ),
    );
  }
}

class _InstallmentRow extends StatelessWidget {
  final Installment item;
  final String symbol;
  final bool visible;

  const _InstallmentRow({
    required this.item,
    required this.symbol,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final remaining = item.totalRemaining;
    final progress = item.progress;
    final hasProgress = item.totalMonths != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: brand.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                MaskedAmount(
                  visibleText: formatMoney(symbol, item.amount),
                  visible: visible,
                  currencyPrefix: symbol,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: brand.ink,
                  ),
                ),
                Text(
                  'per month',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: brand.inkSoft,
                  ),
                ),
              ],
            ),
          ],
        ),
        if (hasProgress) ...[
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 500),
              curve: Curves.easeOutCubic,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: brand.divider,
                valueColor: AlwaysStoppedAnimation(AppColors.expense),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text(
                '${item.paidCount} / ${item.totalMonths} months paid',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: brand.inkSoft,
                ),
              ),
              if (remaining != null) ...[
                const Spacer(),
                MaskedAmount(
                  visibleText: '${formatMoney(symbol, remaining)} left',
                  visible: visible,
                  currencyPrefix: symbol,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.expense,
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

// ── Empty / Loading ───────────────────────────────────────────────────────────

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SectionCard(
      radius: 22,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      child: Row(
        children: [
          const CupertinoActivityIndicator(),
          const SizedBox(width: 12),
          Text(
            'Loading accounts…',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: brand.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyAccounts extends StatelessWidget {
  final VoidCallback onTap;
  const _EmptyAccounts({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return SectionCard(
      radius: 22,
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppColors.sky,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(
              CupertinoIcons.creditcard,
              size: 26,
              color: Color(0xFF2A6FB5),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No accounts yet',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: brand.ink,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Add bank, e-wallet, or cash accounts\nto track your net worth.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: brand.inkSoft,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onTap,
            icon: const Icon(CupertinoIcons.add, size: 16),
            label: const Text('Add Account'),
          ),
        ],
      ),
    );
  }
}

// ── Data model ────────────────────────────────────────────────────────────────

class _AssetSnapshot {
  final List<_AccountAsset> accounts;
  final double netWorth;

  /// Total assets: positive asset account balances + unsettled lending.
  final double totalAssets;

  /// Total liabilities: negative account balances (all types) +
  /// borrowed money + installment remaining amounts.
  final double totalLiabilities;

  /// Unsettled money lent to others (receivable) — included in totalAssets.
  final double totalLent;

  /// Unsettled money borrowed from others (payable) — included in totalLiabilities.
  final double totalBorrowed;

  final List<SavingPlan> activeSavingPlans;
  final double savingPlanSaved;

  /// Active installments with known remaining amounts treated as liabilities.
  final List<Installment> activeInstallments;

  /// Total remaining for fixed-term active installments (null if all lifetime).
  final double? installmentLiability;

  /// Net income - expense change over the past 7 days.
  final double weeklyChange;

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
  });

  factory _AssetSnapshot.build({
    required List<Account> accounts,
    required List<Expense> expenses,
    required List<SavingPlan> savingPlans,
    required List<BorrowLending> borrowLending,
    required List<Installment> installments,
  }) {
    final balances = _computeBalances(accounts, expenses);

    // Split account balances into assets vs liabilities:
    // - Asset accounts (bank/eWallet/cash): positive = asset, negative = liability
    // - Liability accounts (creditCard/loan/etc): negative = liability (never asset)
    double accountAssetsSum = 0;
    double accountLiabilitiesSum = 0;
    for (final account in accounts) {
      final bal = balances[account.id] ?? 0;
      if (account.type.isLiability) {
        if (bal < 0) accountLiabilitiesSum += bal.abs();
        // Positive balance on liability account (overpaid) counts as asset credit
        if (bal > 0) accountAssetsSum += bal;
      } else {
        if (bal >= 0) {
          accountAssetsSum += bal;
        } else {
          accountLiabilitiesSum += bal.abs();
        }
      }
    }

    final accountAssets = <_AccountAsset>[
      for (final account in accounts)
        _AccountAsset(
          account: account,
          balance: balances[account.id] ?? 0,
        ),
    ]..sort((a, b) => b.balance.compareTo(a.balance));

    // Borrow/lending: only unsettled, non-cancelled records.
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

    final active = savingPlans
        .where((p) => p.status == SavingPlanStatus.active)
        .toList(growable: false);
    final planSaved =
        active.fold<double>(0, (sum, p) => sum + p.currentAmount);

    final activeInstallments = installments
        .where((i) => i.status == InstallmentStatus.active)
        .toList(growable: false);

    // Sum remaining for fixed-term installments; ignore lifetime ones.
    double? installmentLiability;
    for (final inst in activeInstallments) {
      final rem = inst.totalRemaining;
      if (rem != null) {
        installmentLiability = (installmentLiability ?? 0) + rem;
      }
    }

    // Comprehensive totals including borrow/lending and installments
    final totalAssets = accountAssetsSum + totalLent;
    final totalLiabilities =
        accountLiabilitiesSum + totalBorrowed + (installmentLiability ?? 0);
    final netWorth = totalAssets - totalLiabilities;

    // Weekly change: net income - expense for the past 7 days (no transfers)
    final weekStart = DateTime.now().subtract(const Duration(days: 7));
    var weeklyChange = 0.0;
    for (final e in expenses) {
      if (e.date.isAfter(weekStart)) {
        if (e.type == EntryType.income || e.type == EntryType.receive) {
          weeklyChange += e.amount;
        } else if (e.type == EntryType.expense) {
          weeklyChange -= e.amount;
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
      activeSavingPlans: active,
      savingPlanSaved: planSaved,
      activeInstallments: activeInstallments,
      installmentLiability: installmentLiability,
      weeklyChange: weeklyChange,
    );
  }

  List<_AccountAsset> typeAccounts(AccountType type) =>
      accounts.where((a) => a.account.type == type).toList(growable: false);

  double typeTotal(AccountType type) =>
      typeAccounts(type).fold<double>(0, (sum, a) => sum + a.balance);

  bool get hasBorrowLend => totalLent > 0 || totalBorrowed > 0;
}

class _AccountAsset {
  final Account account;
  final double balance;
  const _AccountAsset({required this.account, required this.balance});
}

// ── Helpers ───────────────────────────────────────────────────────────────────

Map<String, double> _computeBalances(
  List<Account> accounts,
  List<Expense> expenses,
) {
  final balances = <String, double>{
    for (final a in accounts) a.id: a.openingBalance,
  };
  for (final expense in expenses) {
    final from = expense.accountId;
    if (from != null && balances.containsKey(from)) {
      if (expense.type.isInflow) {
        balances[from] = (balances[from] ?? 0) + expense.amount;
      } else {
        balances[from] = (balances[from] ?? 0) - expense.amount;
      }
    }
    final to = expense.toAccountId;
    if (to != null && balances.containsKey(to)) {
      balances[to] = (balances[to] ?? 0) + expense.amount;
    }
  }
  return balances;
}

({Color bg, Color accent}) _styleFor(AccountType type) {
  switch (type) {
    case AccountType.bank:
      return (bg: AppColors.sky, accent: const Color(0xFF2A6FB5));
    case AccountType.eWallet:
      return (bg: AppColors.mint, accent: const Color(0xFF1F7A60));
    case AccountType.cash:
      return (bg: AppColors.butter, accent: const Color(0xFFA0801C));
    case AccountType.creditCard:
      return (bg: AppColors.blush, accent: const Color(0xFFB03060));
    case AccountType.loan:
      return (bg: AppColors.peach, accent: const Color(0xFF9C4A1A));
    case AccountType.mortgage:
      return (bg: AppColors.sand, accent: const Color(0xFF6B4D2A));
    case AccountType.bnpl:
      return (bg: AppColors.lilac, accent: const Color(0xFF5C3A9E));
    case AccountType.otherLiability:
      return (bg: AppColors.blush, accent: const Color(0xFF7A4040));
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
    case AccountType.creditCard:
      return CupertinoIcons.creditcard_fill;
    case AccountType.loan:
      return CupertinoIcons.doc_text_fill;
    case AccountType.mortgage:
      return CupertinoIcons.house_fill;
    case AccountType.bnpl:
      return CupertinoIcons.cart_fill;
    case AccountType.otherLiability:
      return CupertinoIcons.minus_circle_fill;
  }
}

void _push(BuildContext context, Widget screen) {
  HapticFeedback.selectionClick();
  Navigator.push(context, CupertinoPageRoute(builder: (_) => screen));
}

// ── Breakdown sheet helpers ───────────────────────────────────────────────────

class _BreakdownItem {
  final String name;
  final String type;
  final double amount;

  const _BreakdownItem({
    required this.name,
    required this.type,
    required this.amount,
  });
}

List<_BreakdownItem> _buildAssetItems(_AssetSnapshot snapshot) {
  final items = <_BreakdownItem>[];
  for (final a in snapshot.accounts) {
    if (!a.account.type.isLiability && a.balance > 0) {
      items.add(_BreakdownItem(
        name: a.account.name,
        type: a.account.type.label,
        amount: a.balance,
      ));
    }
  }
  for (final a in snapshot.accounts) {
    if (a.account.type.isLiability && a.balance > 0) {
      items.add(_BreakdownItem(
        name: a.account.name,
        type: '${a.account.type.label} (overpaid)',
        amount: a.balance,
      ));
    }
  }
  if (snapshot.totalLent > 0) {
    items.add(_BreakdownItem(
      name: 'Outstanding Lending',
      type: 'Lending',
      amount: snapshot.totalLent,
    ));
  }
  return items;
}

List<_BreakdownItem> _buildLiabilityItems(_AssetSnapshot snapshot) {
  final items = <_BreakdownItem>[];
  for (final a in snapshot.accounts) {
    if (a.account.type.isLiability && a.balance < 0) {
      items.add(_BreakdownItem(
        name: a.account.name,
        type: a.account.type.label,
        amount: a.balance.abs(),
      ));
    }
  }
  for (final a in snapshot.accounts) {
    if (!a.account.type.isLiability && a.balance < 0) {
      items.add(_BreakdownItem(
        name: a.account.name,
        type: '${a.account.type.label} (negative)',
        amount: a.balance.abs(),
      ));
    }
  }
  if (snapshot.totalBorrowed > 0) {
    items.add(_BreakdownItem(
      name: 'Outstanding Borrowing',
      type: 'Borrowing',
      amount: snapshot.totalBorrowed,
    ));
  }
  if (snapshot.installmentLiability != null && snapshot.installmentLiability! > 0) {
    items.add(_BreakdownItem(
      name: 'Installments Remaining',
      type: 'Installments',
      amount: snapshot.installmentLiability!,
    ));
  }
  return items;
}

void _showBreakdown(
  BuildContext context, {
  required String title,
  required Color color,
  required IconData icon,
  required List<_BreakdownItem> items,
  required double total,
  required String symbol,
  required bool visible,
}) {
  HapticFeedback.selectionClick();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _BreakdownSheet(
      title: title,
      color: color,
      icon: icon,
      items: items,
      total: total,
      symbol: symbol,
      visible: visible,
    ),
  );
}

class _BreakdownSheet extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final List<_BreakdownItem> items;
  final double total;
  final String symbol;
  final bool visible;

  const _BreakdownSheet({
    required this.title,
    required this.color,
    required this.icon,
    required this.items,
    required this.total,
    required this.symbol,
    required this.visible,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: EdgeInsets.only(top: MediaQuery.of(context).padding.top + 40),
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 16),
            decoration: BoxDecoration(
              color: brand.divider,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: isDark ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(icon, size: 17, color: color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            Text(
                              '${items.length} source${items.length == 1 ? '' : 's'}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: brand.inkSoft,
                              ),
                            ),
                          ],
                        ),
                      ),
                      MaskedAmount(
                        visibleText: formatMoney(symbol, total),
                        visible: visible,
                        currencyPrefix: symbol,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: color,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (items.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Nothing here yet',
                          style: TextStyle(
                            fontSize: 14,
                            color: brand.inkSoft,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    )
                  else
                    SectionCard(
                      radius: 20,
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, thickness: 1, color: brand.divider),
                            _BreakdownRow(
                              item: items[i],
                              symbol: symbol,
                              visible: visible,
                              color: color,
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  final _BreakdownItem item;
  final String symbol;
  final bool visible;
  final Color color;

  const _BreakdownRow({
    required this.item,
    required this.symbol,
    required this.visible,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 13, 16, 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.type,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: brand.inkSoft,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          MaskedAmount(
            visibleText: formatMoney(symbol, item.amount),
            visible: visible,
            currencyPrefix: symbol,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
