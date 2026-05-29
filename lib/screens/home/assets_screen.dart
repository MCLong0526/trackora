import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/account.dart';
import '../../models/borrow_lending.dart';
import '../../models/expense.dart';
import '../../models/installment.dart';
import '../../models/saving_plan.dart';
import '../../services/currency_converter.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../services/prefs_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/masked_amount.dart';
import '../../widgets/exchange_rate_sheet.dart';
import '../../widgets/profile_avatar_button.dart';
import '../../widgets/section_card.dart';

class AssetsScreen extends ConsumerStatefulWidget {
  const AssetsScreen({super.key});

  @override
  ConsumerState<AssetsScreen> createState() => _AssetsScreenState();
}

class _AssetsScreenState extends ConsumerState<AssetsScreen> {

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
    final isLoading =
        accountsAsync.maybeWhen(loading: () => true, orElse: () => false);

    return SafeArea(
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                const _Header(),
                const SizedBox(height: 18),
                if (isLoading && accounts.isEmpty)
                  const _LoadingCard()
                else ...[
                  // ── Net worth overview ─────────────────────────────────
                  _NetWorthCard(
                    snapshot: snapshot,
                    symbol: symbol,
                    visible: visible,
                    converter: converter,
                    mainCode: mainCode,
                  ),
                  if (snapshot.hasBorrowLend) ...[
                    const SizedBox(height: 20),
                    _SectionLabel(context.t('asset.moneyFlow')),
                    const SizedBox(height: 8),
                    _BorrowLendCard(
                      snapshot: snapshot,
                      symbol: symbol,
                      visible: visible,
                    ),
                  ],
                  if (snapshot.activeSavingPlans.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _SectionLabel(context.t('asset.savings')),
                    const SizedBox(height: 8),
                    _SavingPlansCard(
                      snapshot: snapshot,
                      symbol: symbol,
                      visible: visible,
                    ),
                  ],
                  if (snapshot.activeInstallments.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    _SectionLabel(context.t('asset.installments')),
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
        fontWeight: FontWeight.w600,
        letterSpacing: 0.6,
        color: context.brand.inkSoft,
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  const _Header();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final visible = ref.watch(balanceVisibleProvider);
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t('asset.title'),
                style: Theme.of(context).textTheme.displayMedium,
              ),
              const SizedBox(height: 2),
              Text(
                context.t('asset.subtitle'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: brand.inkSoft,
                ),
              ),
            ],
          ),
        ),
        GestureDetector(
          onTap: () => ref.read(balanceVisibleProvider.notifier).toggle(),
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: brand.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              visible ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
              size: 17,
              color: brand.inkSoft,
            ),
          ),
        ),
        const SizedBox(width: 8),
        const FxRateButton(),
        const SizedBox(width: 8),
        const ProfileAvatarButton(),
      ],
    );
  }
}

// ── Net Worth Hero Card ───────────────────────────────────────────────────────

class _NetWorthCard extends ConsumerStatefulWidget {
  final _AssetSnapshot snapshot;
  final String symbol;
  final bool visible;
  final CurrencyConverter? converter;
  final String? mainCode;

  const _NetWorthCard({
    required this.snapshot,
    required this.symbol,
    required this.visible,
    this.converter,
    this.mainCode,
  });

  @override
  ConsumerState<_NetWorthCard> createState() => _NetWorthCardState();
}

class _NetWorthCardState extends ConsumerState<_NetWorthCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = brand.surface;
    final ink = brand.ink;
    final soft = brand.inkSoft;
    final excludeInstallments = ref.watch(excludeInstallmentsProvider);
    final installmentAdj = excludeInstallments
        ? (widget.snapshot.installmentLiability ?? 0)
        : 0.0;
    final adjLiabilities = widget.snapshot.totalLiabilities - installmentAdj;
    final netWorth = widget.snapshot.totalAssets - adjLiabilities;
    final netColor = netWorth < 0 ? AppColors.expense : ink;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: SectionCard(
          color: bg,
          pastel: !isDark,
          radius: 26,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top row: label + account count
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.chart_pie_fill, size: 10, color: soft),
                  const SizedBox(width: 4),
                  Text(
                    context.t('asset.netWorth'),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.7,
                      color: soft,
                    ),
                  ),
                  if (widget.snapshot.hasMultiCurrency) ...[
                    const SizedBox(width: 4),
                    Text(
                      '(est.)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: soft,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '${widget.snapshot.accounts.length} account${widget.snapshot.accounts.length == 1 ? '' : 's'}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: soft,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Animated net worth amount
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: netWorth),
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeOutCubic,
                builder: (_, value, _) => MaskedAmount(
                  visibleText: formatMoney(widget.symbol, value),
                  visible: widget.visible,
                  currencyPrefix: widget.symbol,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w700,
                    color: netColor,
                    height: 1.0,
                    letterSpacing: -1,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // Asset/liability split bar
              _AssetLiabilityBar(
                totalAssets: widget.snapshot.totalAssets,
                totalLiabilities: adjLiabilities,
              ),
              const SizedBox(height: 6),
              // Split labels
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
                        context.t('asset.assets'),
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
                        context.t('asset.liabilities'),
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
              const SizedBox(height: 12),
              Container(height: 0.5, color: soft.withValues(alpha: 0.18)),
              const SizedBox(height: 12),
              // Assets & Liabilities tiles
              Row(
                children: [
                  Expanded(
                    child: _WorthTile(
                      label: context.t('asset.assets'),
                      value: widget.snapshot.totalAssets,
                      symbol: widget.symbol,
                      visible: widget.visible,
                      color: AppColors.income,
                      icon: CupertinoIcons.arrow_up_right,
                      isDark: isDark,
                      onTap: () => _showBreakdown(
                        context,
                        title: context.t('asset.assets'),
                        color: AppColors.income,
                        icon: CupertinoIcons.arrow_up_right,
                        items: _buildAssetItems(widget.snapshot, context, widget.converter, widget.mainCode),
                        total: widget.snapshot.totalAssets,
                        symbol: widget.symbol,
                        visible: widget.visible,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _WorthTile(
                      label: context.t('asset.liabilities'),
                      value: adjLiabilities,
                      symbol: widget.symbol,
                      visible: widget.visible,
                      color: AppColors.expense,
                      icon: CupertinoIcons.arrow_down_right,
                      isDark: isDark,
                      onTap: () => _showBreakdown(
                        context,
                        title: context.t('asset.liabilities'),
                        color: AppColors.expense,
                        icon: CupertinoIcons.arrow_down_right,
                        items: _buildLiabilityItems(widget.snapshot, context, widget.converter, widget.mainCode),
                        total: widget.snapshot.totalLiabilities,
                        symbol: widget.symbol,
                        visible: widget.visible,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AssetLiabilityBar extends StatelessWidget {
  final double totalAssets;
  final double totalLiabilities;
  const _AssetLiabilityBar({
    required this.totalAssets,
    required this.totalLiabilities,
  });

  @override
  Widget build(BuildContext context) {
    final total = totalAssets + totalLiabilities;
    final assetRatio = total > 0 ? (totalAssets / total).clamp(0.0, 1.0) : 1.0;
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
                fontWeight: FontWeight.w700,
                color: brand.ink,
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
              label: context.t('asset.youLent'),
              sublabel: context.t('asset.othersOweYou'),
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
              label: context.t('asset.youOwe'),
              sublabel: context.t('asset.youBorrowed'),
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
                fontWeight: FontWeight.w600,
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
            fontWeight: FontWeight.w700,
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
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: kCategoryStyles['Groceries']!.accent,
                ),
              ),
              const SizedBox(width: 2),
              Text(
                ' ${context.t('asset.savedLabel')}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: kCategoryStyles['Groceries']!.accent,
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
                  fontWeight: FontWeight.w600,
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
              valueColor: AlwaysStoppedAnimation(kCategoryStyles['Groceries']!.accent),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${(progress * 100).round()}% ${context.t('asset.savedLabel')}',
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
                    fontWeight: FontWeight.w700,
                    color: AppColors.expense,
                  ),
                ),
                const SizedBox(width: 2),
                Text(
                  ' ${context.t('asset.remaining')}',
                  style: const TextStyle(
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
                  fontWeight: FontWeight.w600,
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
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                  ),
                ),
                Text(
                  context.t('asset.perMonth'),
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
                  visibleText: '${formatMoney(symbol, remaining)} ${context.t('asset.remaining')}',
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
            context.t('asset.loadingAccounts'),
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

  /// Whether any account uses a different currency (for "(est.)" label).
  final bool hasMultiCurrency;

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

    // Convert a per-account balance to base currency for totals
    double toBase(Account a, double bal) {
      final code = a.currencyCode ?? mainCode;
      if (converter != null && code != null && code != mainCode) {
        return converter.toBase(bal, code);
      }
      return bal;
    }

    // Split account balances into assets vs liabilities:
    // - Asset accounts (bank/eWallet/cash): positive = asset, negative = liability
    // - Liability accounts (creditCard/loan/etc): negative = liability (never asset)
    double accountAssetsSum = 0;
    double accountLiabilitiesSum = 0;
    for (final account in accounts) {
      final bal = balances[account.id] ?? 0;
      final baseBal = toBase(account, bal);
      if (account.type.isLiability) {
        if (baseBal < 0) accountLiabilitiesSum += baseBal.abs();
        // Positive balance on liability account (overpaid) counts as asset credit
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
          weeklyChange += e.convertedAmount;
        } else if (e.type == EntryType.expense) {
          weeklyChange -= e.convertedAmount;
        }
      }
    }

    final hasMultiCurrency = accounts.any(
      (a) => a.currencyCode != null && a.currencyCode != mainCode,
    );

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
      hasMultiCurrency: hasMultiCurrency,
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

// ── Breakdown sheet helpers ───────────────────────────────────────────────────

class _BreakdownItem {
  final String name;
  final String type;
  final double amount;
  final String? originalCurrencyCode;
  final double? estAmount;

  const _BreakdownItem({
    required this.name,
    required this.type,
    required this.amount,
    this.originalCurrencyCode,
    this.estAmount,
  });
}

_BreakdownItem _accountItem(
  _AccountAsset a,
  String type,
  CurrencyConverter? converter,
  String? mainCode, {
  bool abs = false,
}) {
  final bal = abs ? a.balance.abs() : a.balance;
  final code = a.account.currencyCode;
  final isForeign = code != null && code != mainCode;
  final est = (isForeign && converter != null) ? converter.toBase(bal, code) : null;
  return _BreakdownItem(
    name: a.account.name,
    type: type,
    amount: bal,
    originalCurrencyCode: isForeign ? code : null,
    estAmount: est,
  );
}

List<_BreakdownItem> _buildAssetItems(
  _AssetSnapshot snapshot,
  BuildContext context,
  CurrencyConverter? converter,
  String? mainCode,
) {
  final items = <_BreakdownItem>[];
  for (final a in snapshot.accounts) {
    if (!a.account.type.isLiability && a.balance > 0) {
      items.add(_accountItem(a, a.account.type.label, converter, mainCode));
    }
  }
  for (final a in snapshot.accounts) {
    if (a.account.type.isLiability && a.balance > 0) {
      items.add(_accountItem(a, '${a.account.type.label} (overpaid)', converter, mainCode));
    }
  }
  if (snapshot.totalLent > 0) {
    items.add(_BreakdownItem(
      name: context.t('asset.outstandingLending'),
      type: 'Lending',
      amount: snapshot.totalLent,
    ));
  }
  return items;
}

List<_BreakdownItem> _buildLiabilityItems(
  _AssetSnapshot snapshot,
  BuildContext context,
  CurrencyConverter? converter,
  String? mainCode,
) {
  final items = <_BreakdownItem>[];
  for (final a in snapshot.accounts) {
    if (a.account.type.isLiability && a.balance < 0) {
      items.add(_accountItem(a, a.account.type.label, converter, mainCode, abs: true));
    }
  }
  for (final a in snapshot.accounts) {
    if (!a.account.type.isLiability && a.balance < 0) {
      items.add(_accountItem(a, '${a.account.type.label} (negative)', converter, mainCode, abs: true));
    }
  }
  if (snapshot.totalBorrowed > 0) {
    items.add(_BreakdownItem(
      name: context.t('asset.outstandingBorrowing'),
      type: 'Borrowing',
      amount: snapshot.totalBorrowed,
    ));
  }
  if (snapshot.installmentLiability != null && snapshot.installmentLiability! > 0) {
    items.add(_BreakdownItem(
      name: context.t('asset.installmentsRemaining'),
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

class _BreakdownSheet extends ConsumerStatefulWidget {
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
  ConsumerState<_BreakdownSheet> createState() => _BreakdownSheetState();
}

class _BreakdownSheetState extends ConsumerState<_BreakdownSheet> {
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final excludeInstallments = ref.watch(excludeInstallmentsProvider);

    final hasInstallments =
        widget.items.any((i) => i.type == 'Installments');
    final displayItems = excludeInstallments
        ? widget.items.where((i) => i.type != 'Installments').toList()
        : widget.items;
    final displayTotal =
        displayItems.fold(0.0, (s, i) => s + i.amount);

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
                          color: widget.color
                              .withValues(alpha: isDark ? 0.18 : 0.12),
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Icon(widget.icon, size: 17, color: widget.color),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${displayItems.length} source${displayItems.length == 1 ? '' : 's'}',
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
                        visibleText: formatMoney(widget.symbol, displayTotal),
                        visible: widget.visible,
                        currencyPrefix: widget.symbol,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: widget.color,
                        ),
                      ),
                    ],
                  ),
                  // Exclude installments toggle (only for liabilities sheet)
                  if (hasInstallments) ...[
                    const SizedBox(height: 14),
                    Container(height: 1, color: brand.divider),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.t('stats.excludeFixed'),
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: brand.inkSoft,
                            ),
                          ),
                        ),
                        CupertinoSwitch(
                          value: excludeInstallments,
                          onChanged: (v) => ref
                              .read(excludeInstallmentsProvider.notifier)
                              .set(v),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                  ] else
                    const SizedBox(height: 18),
                  if (displayItems.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          context.t('asset.nothingHere'),
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
                          for (var i = 0; i < displayItems.length; i++) ...[
                            if (i > 0)
                              Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: brand.divider),
                            _BreakdownRow(
                              item: displayItems[i],
                              symbol: widget.symbol,
                              visible: widget.visible,
                              color: widget.color,
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
    final hasForeign = item.originalCurrencyCode != null && item.estAmount != null;
    final displaySym = hasForeign
        ? (kSupportedCurrencies[item.originalCurrencyCode!] ?? item.originalCurrencyCode!)
        : symbol;
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              MaskedAmount(
                visibleText: formatMoney(displaySym, item.amount),
                visible: visible,
                currencyPrefix: displaySym,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              if (hasForeign)
                Text(
                  'est. $symbol ${item.estAmount!.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: brand.inkSoft,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
