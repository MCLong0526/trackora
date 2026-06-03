import 'dart:math' show pi, cos, sin, Random;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/account.dart';
import '../models/expense.dart';
import '../models/group_expense_item.dart';
import '../models/precious_metal.dart';
import '../services/money_format.dart';
import '../services/prefs_service.dart';
import '../state/providers.dart';
import '../services/i18n.dart';
import '../theme/app_theme.dart';
import 'currency_picker.dart';
import 'masked_amount.dart';
import '../screens/accounts/add_edit_account_screen.dart';
import '../screens/expenses/add_edit_expense_screen.dart';
import 'app_toast.dart';

// Unified display representation for both personal and group transactions.
class _AccountTxn {
  final String title;
  final DateTime date;
  final double amount;
  final bool isInflow;
  final bool isGroup;
  final String? originalCurrency;

  const _AccountTxn({
    required this.title,
    required this.date,
    required this.amount,
    required this.isInflow,
    required this.isGroup,
    this.originalCurrency,
  });

  static _AccountTxn fromExpense(Expense e, String accountId) {
    final isTo = e.toAccountId == accountId;
    return _AccountTxn(
      title: e.note.isNotEmpty ? e.note : e.category,
      date: e.date,
      amount: e.amount,
      isInflow: e.type.isInflow || isTo,
      isGroup: false,
      originalCurrency: e.originalCurrency,
    );
  }

  static _AccountTxn fromGroupExpense(GroupExpenseItem g) {
    return _AccountTxn(
      title: g.description.isNotEmpty ? g.description : g.category,
      date: g.date,
      amount: g.amount,
      isInflow: false,
      isGroup: true,
    );
  }

  static _AccountTxn fromPreciousMetal(PreciousMetal m) {
    return _AccountTxn(
      title: '${m.metalType.label} ${m.action == MetalAction.buy ? 'Buy' : 'Sell'}',
      date: m.date,
      amount: m.totalAmount,
      isInflow: m.action == MetalAction.sell,
      isGroup: false,
    );
  }
}

const _kCustomLabel = 'Other / Custom';

// ── Pastel palette ────────────────────────────────────────────
typedef _Pal = ({
  Color a,
  Color b,
  Color ink,
  Color accent,
  String glyph,
  String labelKey
});

_Pal _paletteForAccountType(AccountType type) {
  switch (type) {
    case AccountType.bank:
      return (
        a: const Color(0xFFCFE0FF),
        b: const Color(0xFFA8C5F5),
        ink: const Color(0xFF1E3F8A),
        accent: const Color(0xFF3C6FE0),
        glyph: '◆',
        labelKey: 'account.palBank',
      );
    case AccountType.eWallet:
      return (
        a: const Color(0xFFD2F0DD),
        b: const Color(0xFFA8DDC0),
        ink: const Color(0xFF1B5A3D),
        accent: const Color(0xFF33A874),
        glyph: '◐',
        labelKey: 'account.palEWallet',
      );
    case AccountType.cash:
      return (
        a: const Color(0xFFFBE9C2),
        b: const Color(0xFFF2D38C),
        ink: const Color(0xFF7A5512),
        accent: const Color(0xFFC99838),
        glyph: '\$',
        labelKey: 'account.palCash',
      );
    case AccountType.creditCard:
      return (
        a: const Color(0xFFFCD7D7),
        b: const Color(0xFFF5B6B6),
        ink: const Color(0xFF922C2C),
        accent: const Color(0xFFCC4545),
        glyph: '✦',
        labelKey: 'account.palCredit',
      );
    case AccountType.loan:
      return (
        a: const Color(0xFFFFE3BC),
        b: const Color(0xFFFFCD83),
        ink: const Color(0xFF8A5A04),
        accent: const Color(0xFFE89A14),
        glyph: '▲',
        labelKey: 'account.palLoan',
      );
    case AccountType.mortgage:
      return (
        a: const Color(0xFFEDE5D8),
        b: const Color(0xFFD9CAAB),
        ink: const Color(0xFF6B4D2A),
        accent: const Color(0xFF9B7045),
        glyph: '⌂',
        labelKey: 'account.palMortgage',
      );
    case AccountType.bnpl:
      return (
        a: const Color(0xFFE4D7F5),
        b: const Color(0xFFCBB3E8),
        ink: const Color(0xFF5C3A9E),
        accent: const Color(0xFF8B5FD4),
        glyph: '⬡',
        labelKey: 'account.palBnpl',
      );
    case AccountType.otherLiability:
      return (
        a: const Color(0xFFFAD3D3),
        b: const Color(0xFFF0ADAD),
        ink: const Color(0xFF7A4040),
        accent: const Color(0xFFB55555),
        glyph: '−',
        labelKey: 'account.palDebt',
      );
    case AccountType.investment:
      return (
        a: const Color(0xFFD3F5E0),
        b: const Color(0xFFA8E8C2),
        ink: const Color(0xFF1A5E36),
        accent: const Color(0xFF2E9E5A),
        glyph: '▲',
        labelKey: 'account.palInvest',
      );
    case AccountType.savings:
      return (
        a: const Color(0xFFD0EEFF),
        b: const Color(0xFFA5D5F5),
        ink: const Color(0xFF1A4A6E),
        accent: const Color(0xFF2E7EB5),
        glyph: '◎',
        labelKey: 'account.palSavings',
      );
    case AccountType.crypto:
      return (
        a: const Color(0xFFFFE8CC),
        b: const Color(0xFFFFD099),
        ink: const Color(0xFF8A4E04),
        accent: const Color(0xFFE8820E),
        glyph: '◈',
        labelKey: 'account.palCrypto',
      );
    case AccountType.forex:
      return (
        a: const Color(0xFFEAD5FF),
        b: const Color(0xFFD0A8F5),
        ink: const Color(0xFF4E2A8A),
        accent: const Color(0xFF7F4FD4),
        glyph: '◇',
        labelKey: 'account.palForex',
      );
  }
}

// ── Public wrapper ────────────────────────────────────────────
/// Drop-in carousel section used on both AccountsScreen and AssetsScreen.
class AccountCarouselSection extends ConsumerWidget {
  final List<Account> accounts;
  final Map<String, double> balances;
  final List<Expense> allExpenses;
  final String symbol;
  final bool visible;

  const AccountCarouselSection({
    super.key,
    required this.accounts,
    required this.balances,
    required this.allExpenses,
    required this.symbol,
    required this.visible,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (accounts.isEmpty) {
      final brand = context.brand;
      return GestureDetector(
        onTap: () => showAddAccountSheet(context),
        child: Container(
          height: 110,
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppActionBlue.color.withValues(alpha: 0.25),
              width: 1.5,
              strokeAlign: BorderSide.strokeAlignInside,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppActionBlue.color.withValues(alpha: 0.10),
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.creditcard, size: 18, color: AppActionBlue.color),
              ),
              const SizedBox(height: 8),
              Text(
                context.t('account.addAccount'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppActionBlue.color,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Watch group expenses for the active group (if any).
    final groupId = ref.watch(activeGroupIdProvider);
    final currentUser = ref.watch(authStateProvider).valueOrNull;
    final groupExpenses = groupId != null
        ? (ref.watch(groupExpensesProvider(groupId)).valueOrNull ?? const <GroupExpenseItem>[])
        : const <GroupExpenseItem>[];
    // Only show group expenses where the current user is the payer and used an account.
    final myGroupExpenses = groupExpenses
        .where((e) =>
            e.paidByAccountId != null &&
            (currentUser == null || e.paidBy == currentUser.uid))
        .toList();

    final preciousMetals =
        ref.watch(preciousMetalsProvider).valueOrNull ?? const <PreciousMetal>[];

    return LayoutBuilder(
      builder: (ctx, constraints) => _AccountCarousel(
        accounts: accounts,
        balances: balances,
        allExpenses: allExpenses,
        groupExpenses: myGroupExpenses,
        preciousMetals: preciousMetals,
        symbol: symbol,
        visible: visible,
        availableWidth: constraints.maxWidth,
      ),
    );
  }
}

// ── Carousel ──────────────────────────────────────────────────
class _AccountCarousel extends StatefulWidget {
  final List<Account> accounts;
  final Map<String, double> balances;
  final List<Expense> allExpenses;
  final List<GroupExpenseItem> groupExpenses;
  final List<PreciousMetal> preciousMetals;
  final String symbol;
  final bool visible;
  final double availableWidth;

  const _AccountCarousel({
    required this.accounts,
    required this.balances,
    required this.allExpenses,
    required this.groupExpenses,
    required this.preciousMetals,
    required this.symbol,
    required this.visible,
    required this.availableWidth,
  });

  @override
  State<_AccountCarousel> createState() => _AccountCarouselState();
}

class _AccountCarouselState extends State<_AccountCarousel>
    with SingleTickerProviderStateMixin {
  int _activeIndex = 0;
  bool _isFlipped = false;
  late final AnimationController _flipCtrl;
  late final Animation<double> _flipAnim;
  String? _focusAccountId;

  static const double _cardW = 280.0;
  static const double _cardH = 184.0;
  static const double _cardHFlipped = 420.0;
  static const double _cardSpacing = 270.0;
  static const _springCurve = Cubic(0.34, 1.36, 0.64, 1.0);

  @override
  void initState() {
    super.initState();
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _flipAnim = CurvedAnimation(
      parent: _flipCtrl,
      curve: Curves.easeInOutQuart,
    );
  }

  @override
  void didUpdateWidget(_AccountCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_focusAccountId != null) {
      final idx = widget.accounts.indexWhere((a) => a.id == _focusAccountId);
      if (idx >= 0) {
        _activeIndex = idx;
        _focusAccountId = null;
      }
    }
    if (widget.accounts.isNotEmpty &&
        _activeIndex >= widget.accounts.length) {
      _activeIndex = widget.accounts.length - 1;
      if (_isFlipped) {
        _flipCtrl.reverse();
        _isFlipped = false;
      }
    }
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  void _goTo(int i) {
    if (i == _activeIndex) return;
    if (_isFlipped) {
      _flipCtrl.reverse();
      setState(() {
        _isFlipped = false;
        _activeIndex = i;
      });
    } else {
      setState(() => _activeIndex = i);
    }
  }

  void _toggleFlip() {
    if (_isFlipped) {
      _flipCtrl.reverse();
    } else {
      _flipCtrl.forward();
    }
    setState(() => _isFlipped = !_isFlipped);
  }

  void _unflip() {
    _flipCtrl.reverse();
    setState(() => _isFlipped = false);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final centerX = (widget.availableWidth - _cardW) / 2;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (v < -200 && _activeIndex < widget.accounts.length - 1) {
          _goTo(_activeIndex + 1);
        } else if (v > 200 && _activeIndex > 0) {
          _goTo(_activeIndex - 1);
        }
      },
      child: Column(
        children: [
          // ── Cards ─────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 560),
            curve: Curves.easeInOutCubic,
            height: _isFlipped ? _cardHFlipped + 20 : _cardH + 20,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (final i in (List.generate(
                  widget.accounts.length,
                  (idx) => idx,
                )..sort((a, b) => a == _activeIndex
                      ? 1
                      : b == _activeIndex
                          ? -1
                          : 0)))
                  _buildCard(i, centerX),
              ],
            ),
          ),

          // ── Pagination dots ────────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            child: _isFlipped
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(
                        widget.accounts.length,
                        (i) {
                          final active = i == _activeIndex;
                          return GestureDetector(
                            onTap: () => _goTo(i),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin:
                                  const EdgeInsets.symmetric(horizontal: 3),
                              width: active ? 22 : 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: active
                                    ? brand.ink
                                    : brand.inkSoft.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
          ),

          // ── Add Account button ─────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeInOutCubic,
            child: _isFlipped
                ? const SizedBox.shrink()
                : Padding(
                    padding:
                        const EdgeInsets.fromLTRB(20, 12, 20, 4),
                    child: _AddAccountButton(
                      onTap: () => showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        useSafeArea: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _AddAccountSheet(),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard(int i, double centerX) {
    final offset = i - _activeIndex;
    final absOffset = offset.abs();
    final isCenter = offset == 0;
    final isOther = _isFlipped && !isCenter;

    final tx = offset * _cardSpacing;
    final scale = isCenter ? 1.0 : 0.86;
    final opacity = absOffset > 2
        ? 0.0
        : isOther
            ? 0.0
            : (isCenter ? 1.0 : 0.38);
    final fanDeg = offset * -8.0;

    final account = widget.accounts[i];
    final balance = widget.balances[account.id] ?? 0.0;
    final pal = _paletteForAccountType(account.type);

    // Merge personal + group + precious metal transactions for this account.
    final personalTxns = widget.allExpenses
        .where((e) => e.accountId == account.id || e.toAccountId == account.id)
        .map((e) => _AccountTxn.fromExpense(e, account.id))
        .toList();
    final groupTxns = widget.groupExpenses
        .where((e) => e.paidByAccountId == account.id)
        .map(_AccountTxn.fromGroupExpense)
        .toList();
    final metalTxns = widget.preciousMetals
        .where((m) => m.accountId == account.id)
        .map(_AccountTxn.fromPreciousMetal)
        .toList();
    final allTxns = [...personalTxns, ...groupTxns, ...metalTxns]
      ..sort((a, b) => b.date.compareTo(a.date));

    return AnimatedPositioned(
      key: ValueKey(account.id),
      duration: const Duration(milliseconds: 480),
      curve: _springCurve,
      left: centerX + tx,
      top: 10,
      width: _cardW,
      height: isCenter && _isFlipped ? _cardHFlipped : _cardH,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 320),
        opacity: opacity,
        child: AnimatedScale(
          duration: const Duration(milliseconds: 480),
          curve: _springCurve,
          scale: scale,
          child: GestureDetector(
            onTap: isCenter ? _toggleFlip : () => _goTo(i),
            child: _FlipCard(
              account: account,
              balance: balance,
              symbol: widget.symbol,
              visible: widget.visible,
              pal: pal,
              isCenter: isCenter,
              flipAnim: _flipAnim,
              fanDeg: fanDeg,
              recentTxns: allTxns.take(3).toList(),
              allTxns: allTxns,
              onClose: _unflip,
              onEdit: () async {
                final accountId = account.id;
                await Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => AddEditAccountScreen(account: account),
                  ),
                );
                if (!mounted) return;
                setState(() {
                  final idx = widget.accounts.indexWhere((a) => a.id == accountId);
                  if (idx >= 0) {
                    _activeIndex = idx;
                  } else {
                    _focusAccountId = accountId;
                  }
                });
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ── Flip Card ─────────────────────────────────────────────────
class _FlipCard extends StatelessWidget {
  final Account account;
  final double balance;
  final String symbol;
  final bool visible;
  final _Pal pal;
  final bool isCenter;
  final Animation<double> flipAnim;
  final double fanDeg;
  final List<_AccountTxn> recentTxns;
  final List<_AccountTxn> allTxns;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  const _FlipCard({
    required this.account,
    required this.balance,
    required this.symbol,
    required this.visible,
    required this.pal,
    required this.isCenter,
    required this.flipAnim,
    required this.fanDeg,
    required this.recentTxns,
    required this.allTxns,
    required this.onClose,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (!isCenter) {
      final fanRad = fanDeg * pi / 180;
      return Transform(
        transform: Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(fanRad),
        alignment: Alignment.center,
        child: _CardFront(
          account: account,
          balance: balance,
          symbol: symbol,
          visible: visible,
          pal: pal,
          showFlipHint: false,
        ),
      );
    }

    return AnimatedBuilder(
      animation: flipAnim,
      builder: (context, _) {
        final angle = flipAnim.value * pi;
        final showFront = angle < pi / 2;
        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001)
            ..rotateY(angle),
          alignment: Alignment.center,
          child: showFront
              ? _CardFront(
                  account: account,
                  balance: balance,
                  symbol: symbol,
                  visible: visible,
                  pal: pal,
                  showFlipHint: true,
                )
              : Transform(
                  transform: Matrix4.identity()..rotateY(pi),
                  alignment: Alignment.center,
                  child: _CardBack(
                    account: account,
                    balance: balance,
                    symbol: symbol,
                    visible: visible,
                    pal: pal,
                    recentTxns: recentTxns,
                    allTxns: allTxns,
                    onClose: onClose,
                    onEdit: onEdit,
                  ),
                ),
        );
      },
    );
  }
}

// ── Card Front ────────────────────────────────────────────────
class _CardFront extends ConsumerWidget {
  final Account account;
  final double balance;
  final String symbol;
  final bool visible;
  final _Pal pal;
  final bool showFlipHint;

  const _CardFront({
    required this.account,
    required this.balance,
    required this.symbol,
    required this.visible,
    required this.pal,
    required this.showFlipHint,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isNeg = balance < 0;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [pal.a, pal.b],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          const BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
          BoxShadow(
            color: pal.b.withValues(alpha: 0.55),
            blurRadius: 24,
            spreadRadius: -2,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 40,
            spreadRadius: -4,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          Positioned(
            right: -70,
            top: -70,
            child: Container(
              width: 180,
              height: 180,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: pal.accent.withValues(alpha: 0.10),
              ),
            ),
          ),
          Positioned(
            right: -40,
            top: -40,
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: pal.accent.withValues(alpha: 0.22),
                  width: 1.5,
                ),
              ),
            ),
          ),
          Positioned(
            right: -20,
            bottom: -54,
            child: Text(
              pal.glyph,
              style: TextStyle(
                fontSize: 170,
                fontWeight: FontWeight.w900,
                color: pal.accent.withValues(alpha: 0.10),
                height: 1,
              ),
            ),
          ),
          Positioned(
            top: -40,
            left: -20,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.45),
                    Colors.white.withValues(alpha: 0),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: account type + name — flexible so balance always fits
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t(pal.labelKey),
                            style: TextStyle(
                              fontSize: 9,
                              letterSpacing: 1.3,
                              color: pal.ink.withValues(alpha: 0.60),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            account.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: pal.ink,
                              letterSpacing: -0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Right: date + eye toggle + balance — always shows fully
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              DateFormat('MMM d').format(account.createdAt),
                              style: TextStyle(
                                fontSize: 9,
                                letterSpacing: 1.2,
                                color: pal.ink.withValues(alpha: 0.55),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () => ref.read(balanceVisibleProvider.notifier).toggle(),
                              child: Icon(
                                visible ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                                size: 13,
                                color: pal.ink.withValues(alpha: 0.55),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        _AccountBalanceDisplay(
                          account: account,
                          balance: balance,
                          mainSymbol: symbol,
                          visible: visible,
                          pal: pal,
                          isNeg: isNeg,
                        ),
                      ],
                    ),
                  ],
                ),
                const Spacer(),
                if (showFlipHint)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        context.t(account.type.labelKey),
                        style: TextStyle(
                          fontSize: 11,
                          color: pal.ink.withValues(alpha: 0.70),
                        ),
                      ),
                      Text(
                        context.t('account.tapToFlip'),
                        style: TextStyle(
                          fontSize: 10,
                          color: pal.ink.withValues(alpha: 0.55),
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
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
}

// ── Account Balance Display (handles multi-currency) ──────────
class _AccountBalanceDisplay extends ConsumerWidget {
  final Account account;
  final double balance;
  final String mainSymbol;
  final bool visible;
  final _Pal pal;
  final bool isNeg;
  final double fontSize;

  const _AccountBalanceDisplay({
    required this.account,
    required this.balance,
    required this.mainSymbol,
    required this.visible,
    required this.pal,
    required this.isNeg,
    this.fontSize = 19,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mainCode = ref.watch(currencyCodeProvider).valueOrNull;
    final acctCode = account.currencyCode;
    final acctSymbol = acctCode != null
        ? (kSupportedCurrencies[acctCode] ?? acctCode)
        : mainSymbol;
    final isForeign = acctCode != null && acctCode != mainCode;

    final converter = ref.watch(currencyConverterProvider).valueOrNull;
    final estimatedBase = isForeign && converter != null
        ? converter.toBase(balance, acctCode)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // FittedBox lets the balance shrink to fit without overflowing the card
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: MaskedAmount(
              visibleText: formatMoney(acctSymbol, balance),
              visible: visible,
              currencyPrefix: acctSymbol,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.w700,
                color: isNeg ? AppColors.expense : pal.ink,
                letterSpacing: -0.2,
              ),
            ),
          ),
        ),
        if (isForeign && estimatedBase != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: MaskedAmount(
                visibleText: '≈ ${formatMoney(mainSymbol, estimatedBase)}',
                visible: visible,
                currencyPrefix: mainSymbol,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: pal.ink.withValues(alpha: 0.55),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Card Back ─────────────────────────────────────────────────
class _CardBack extends StatelessWidget {
  final Account account;
  final double balance;
  final String symbol;
  final bool visible;
  final _Pal pal;
  final List<_AccountTxn> recentTxns;
  final List<_AccountTxn> allTxns;
  final VoidCallback onClose;
  final VoidCallback onEdit;

  const _CardBack({
    required this.account,
    required this.balance,
    required this.symbol,
    required this.visible,
    required this.pal,
    required this.recentTxns,
    required this.allTxns,
    required this.onClose,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    final isNeg = balance < 0;
    final acctCode = account.currencyCode;
    final acctSymbol = acctCode != null
        ? (kSupportedCurrencies[acctCode] ?? acctCode)
        : symbol;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [pal.b, pal.a],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          const BoxShadow(
            color: Color(0x0D000000),
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
          BoxShadow(
            color: pal.b.withValues(alpha: 0.55),
            blurRadius: 24,
            spreadRadius: -2,
            offset: const Offset(0, 12),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 40,
            spreadRadius: -4,
            offset: const Offset(0, 20),
          ),
        ],
      ),
      clipBehavior: Clip.hardEdge,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.t(pal.labelKey),
                  style: TextStyle(
                    fontSize: 11,
                    letterSpacing: 1.3,
                    color: pal.ink.withValues(alpha: 0.70),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                GestureDetector(
                  onTap: onClose,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.55),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '✕',
                      style: TextStyle(
                        fontSize: 12,
                        color: pal.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              account.name,
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: pal.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${context.t('account.balance')} · ${DateFormat('MMM d').format(account.createdAt)}',
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1.2,
                color: pal.ink.withValues(alpha: 0.60),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            _AccountBalanceDisplay(
              account: account,
              balance: balance,
              mainSymbol: symbol,
              visible: visible,
              pal: pal,
              isNeg: isNeg,
              fontSize: 24,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _EditPill(ink: pal.ink, onTap: onEdit),
                if (account.type == AccountType.creditCard && balance < 0) ...[
                  const SizedBox(width: 8),
                  _PayCardPill(
                    amount: balance.abs(),
                    accountId: account.id,
                    ink: pal.ink,
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  context.t('account.recent'),
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.2,
                    color: pal.ink.withValues(alpha: 0.70),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (allTxns.isNotEmpty)
                  GestureDetector(
                    onTap: () => _showAllTransactions(context, acctSymbol),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.40),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        context.t('account.viewAll'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: pal.ink,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            if (recentTxns.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  context.t('account.noRecentActivity'),
                  style: TextStyle(
                    fontSize: 12,
                    color: pal.ink.withValues(alpha: 0.55),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.30),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: recentTxns.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final txn = entry.value;
                    final isLast = idx == recentTxns.length - 1;
                    final txnSym = txn.originalCurrency != null
                        ? (kSupportedCurrencies[txn.originalCurrency!] ?? txn.originalCurrency!)
                        : acctSymbol;
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        if (txn.isGroup) ...[
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: pal.accent.withValues(alpha: 0.18),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              context.t('common.group'),
                                              style: TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: pal.accent,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 5),
                                        ],
                                        Expanded(
                                          child: Text(
                                            txn.title,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500,
                                              color: pal.ink,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      DateFormat('MMM d').format(txn.date),
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: pal.ink.withValues(alpha: 0.55),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                txn.isInflow
                                    ? '+${formatMoney(txnSym, txn.amount)}'
                                    : '−${formatMoney(txnSym, txn.amount)}',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: txn.isInflow
                                      ? const Color(0xFF1B8A4A)
                                      : pal.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!isLast)
                          Container(
                            height: 0.5,
                            margin: const EdgeInsets.symmetric(horizontal: 12),
                            color: pal.ink.withValues(alpha: 0.10),
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

  void _showAllTransactions(BuildContext context, String acctSymbol) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (_) => _AllTransactionsSheet(
        account: account,
        allTxns: allTxns,
        acctSymbol: acctSymbol,
        pal: pal,
      ),
    );
  }
}

// ── All Transactions Sheet ─────────────────────────────────────
class _AllTransactionsSheet extends StatefulWidget {
  final Account account;
  final List<_AccountTxn> allTxns;
  final String acctSymbol;
  final _Pal pal;

  const _AllTransactionsSheet({
    required this.account,
    required this.allTxns,
    required this.acctSymbol,
    required this.pal,
  });

  @override
  State<_AllTransactionsSheet> createState() => _AllTransactionsSheetState();
}

class _AllTransactionsSheetState extends State<_AllTransactionsSheet> {
  bool _showPersonal = true;
  bool _showGroup = true;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final filtered = widget.allTxns.where((t) {
      if (t.isGroup && !_showGroup) return false;
      if (!t.isGroup && !_showPersonal) return false;
      return true;
    }).toList();

    return Container(
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: brand.inkSoft.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.account.name,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '${widget.allTxns.length} ${context.t('account.transactions')}',
                        style: TextStyle(fontSize: 13, color: brand.inkSoft),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: brand.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(CupertinoIcons.xmark, size: 14, color: brand.ink),
                  ),
                ),
              ],
            ),
          ),
          // Filter pills
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
            child: Row(
              children: [
                _FilterPill(
                  label: context.t('common.personal'),
                  active: _showPersonal,
                  color: widget.pal.accent,
                  onTap: () => setState(() => _showPersonal = !_showPersonal),
                ),
                const SizedBox(width: 8),
                _FilterPill(
                  label: context.t('common.group'),
                  active: _showGroup,
                  color: const Color(0xFF6B40A8),
                  onTap: () => setState(() => _showGroup = !_showGroup),
                ),
              ],
            ),
          ),
          // Transaction list
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Text(
                      context.t('account.noTransactions'),
                      style: TextStyle(color: brand.inkSoft, fontSize: 15),
                      textAlign: TextAlign.center,
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: brand.divider,
                      indent: 56,
                    ),
                    itemBuilder: (ctx, i) {
                      final txn = filtered[i];
                      final txnSym = txn.originalCurrency != null
                          ? (kSupportedCurrencies[txn.originalCurrency!] ?? txn.originalCurrency!)
                          : widget.acctSymbol;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            // Icon circle
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: txn.isGroup
                                    ? const Color(0xFF6B40A8).withValues(alpha: 0.12)
                                    : (txn.isInflow
                                        ? AppColors.income.withValues(alpha: 0.12)
                                        : widget.pal.accent.withValues(alpha: 0.12)),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                txn.isGroup
                                    ? CupertinoIcons.person_2_fill
                                    : (txn.isInflow
                                        ? CupertinoIcons.arrow_down_left
                                        : CupertinoIcons.arrow_up_right),
                                size: 16,
                                color: txn.isGroup
                                    ? const Color(0xFF6B40A8)
                                    : (txn.isInflow ? AppColors.income : widget.pal.accent),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      if (txn.isGroup) ...[
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF6B40A8).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: Text(
                                            context.t('common.group'),
                                            style: const TextStyle(
                                              fontSize: 9,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFF6B40A8),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                      ],
                                      Flexible(
                                        child: Text(
                                          txn.title,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: brand.ink,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    DateFormat('MMM d, yyyy').format(txn.date),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: brand.inkSoft,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              txn.isInflow
                                  ? '+${formatMoney(txnSym, txn.amount)}'
                                  : '−${formatMoney(txnSym, txn.amount)}',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: txn.isInflow
                                    ? AppColors.income
                                    : brand.ink,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Filter pill ───────────────────────────────────────────────
class _FilterPill extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.14) : brand.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: active ? color.withValues(alpha: 0.40) : brand.divider,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: active ? color : brand.inkSoft,
          ),
        ),
      ),
    );
  }
}

// ── Edit pill ─────────────────────────────────────────────────
class _EditPill extends StatelessWidget {
  final Color ink;
  final VoidCallback? onTap;

  const _EditPill({required this.ink, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.pencil, size: 14, color: ink),
            const SizedBox(width: 6),
            Text(
              context.t('account.editAccount'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Pay Card pill (credit cards with negative balance) ─────────
class _PayCardPill extends StatelessWidget {
  final double amount;
  final String accountId;
  final Color ink;

  const _PayCardPill({required this.amount, required this.accountId, required this.ink});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        Navigator.push(
          context,
          CupertinoPageRoute(
            builder: (_) => AddEditExpenseScreen(
              initialType: EntryType.transfer,
              initialToAccountId: accountId,
              initialAmount: amount,
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          color: AppColors.expense.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(22),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.creditcard_fill, size: 14, color: AppColors.expense),
            const SizedBox(width: 6),
            Text(
              context.t('account.payCard'),
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: AppColors.expense,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add Account button ────────────────────────────────────────
class _AddAccountButton extends StatefulWidget {
  final VoidCallback onTap;
  const _AddAccountButton({required this.onTap});

  @override
  State<_AddAccountButton> createState() => _AddAccountButtonState();
}

class _AddAccountButtonState extends State<_AddAccountButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: AppActionBlue.color,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(CupertinoIcons.add, color: Colors.white, size: 17),
              const SizedBox(width: 7),
              Text(
                context.t('account.addAccount'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Add Account types ─────────────────────────────────────────
class _AType {
  final String labelKey;
  final String subKey;
  final AccountType type;
  final IconData icon;
  final String defaultName;

  const _AType({
    required this.labelKey,
    required this.subKey,
    required this.type,
    required this.icon,
    required this.defaultName,
  });
}

const _kAddTypes = [
  _AType(
    labelKey: 'account.typeBank',
    subKey: 'account.typeBankSub',
    type: AccountType.bank,
    icon: PhosphorIconsFill.bank,
    defaultName: 'New Bank Account',
  ),
  _AType(
    labelKey: 'account.typeEWallet',
    subKey: 'account.typeEWalletSub',
    type: AccountType.eWallet,
    icon: PhosphorIconsFill.deviceMobile,
    defaultName: 'New e-Wallet',
  ),
  _AType(
    labelKey: 'account.typeCash',
    subKey: 'account.typeCashSub',
    type: AccountType.cash,
    icon: PhosphorIconsFill.currencyDollar,
    defaultName: 'Cash',
  ),
  _AType(
    labelKey: 'account.typeCreditCard',
    subKey: 'account.typeCreditCardSub',
    type: AccountType.creditCard,
    icon: CupertinoIcons.creditcard_fill,
    defaultName: 'New Credit Card',
  ),
];

const _kOtherTypes = [
  _AType(
    labelKey: 'account.typeInvestment',
    subKey: 'account.typeInvestmentSub',
    type: AccountType.investment,
    icon: PhosphorIconsFill.chartLineUp,
    defaultName: 'Investment Account',
  ),
  _AType(
    labelKey: 'account.typeSavings',
    subKey: 'account.typeSavingsSub',
    type: AccountType.savings,
    icon: PhosphorIconsFill.piggyBank,
    defaultName: 'Savings Account',
  ),
  _AType(
    labelKey: 'account.typeCrypto',
    subKey: 'account.typeCryptoSub',
    type: AccountType.crypto,
    icon: PhosphorIconsFill.currencyBtc,
    defaultName: 'Crypto Wallet',
  ),
  _AType(
    labelKey: 'account.typeForex',
    subKey: 'account.typeForexSub',
    type: AccountType.forex,
    icon: PhosphorIconsFill.globe,
    defaultName: 'Forex Account',
  ),
  _AType(
    labelKey: 'account.typeLoan',
    subKey: 'account.typeLoanSub',
    type: AccountType.loan,
    icon: PhosphorIconsFill.receipt,
    defaultName: 'Loan',
  ),
  _AType(
    labelKey: 'account.typeMortgage',
    subKey: 'account.typeMortgageSub',
    type: AccountType.mortgage,
    icon: CupertinoIcons.house_fill,
    defaultName: 'Mortgage',
  ),
  _AType(
    labelKey: 'account.typeBnpl',
    subKey: 'account.typeBnplSub',
    type: AccountType.bnpl,
    icon: CupertinoIcons.cart_fill,
    defaultName: 'BNPL Account',
  ),
  _AType(
    labelKey: 'account.typeOtherDebt',
    subKey: 'account.typeOtherDebtSub',
    type: AccountType.otherLiability,
    icon: CupertinoIcons.minus_circle_fill,
    defaultName: 'Other Debt',
  ),
];

const _kConfettiColors = [
  AppActionBlue.color,
  Color(0xFF33B07A),
  Color(0xFFE89A14),
  Color(0xFFD94747),
  Color(0xFF7A56C5),
];

// Public helper to show the Add Account sheet from any screen.
void showAddAccountSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _AddAccountSheet(),
  );
}

// ── Add Account sheet ─────────────────────────────────────────
class _AddAccountSheet extends ConsumerStatefulWidget {
  const _AddAccountSheet();

  @override
  ConsumerState<_AddAccountSheet> createState() => _AddAccountSheetState();
}

class _AddAccountSheetState extends ConsumerState<_AddAccountSheet>
    with TickerProviderStateMixin {
  int _step = 0;
  _AType? _selectedType;
  AccountType _swatchColor = AccountType.bank;
  final _nameCtrl = TextEditingController();
  final _balanceCtrl = TextEditingController();
  bool _success = false;
  bool _saving = false;
  double _animatedBalance = 0;
  String _currencyCode = 'MYR';

  late final AnimationController _tileCtrl;
  late final AnimationController _stepCtrl;
  late final AnimationController _confettiCtrl;
  late final Animation<double> _confettiAnim;

  @override
  void initState() {
    super.initState();
    _tileCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();

    _stepCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _confettiAnim = CurvedAnimation(
      parent: _confettiCtrl,
      curve: const Cubic(0.2, 0.7, 0.3, 1.0),
    );

    _balanceCtrl.addListener(() {
      final v = double.tryParse(_balanceCtrl.text) ?? 0.0;
      setState(() => _animatedBalance = v);
    });

    PrefsService().currencyCode().then((c) {
      if (mounted) setState(() => _currencyCode = c);
    });
  }

  @override
  void dispose() {
    _tileCtrl.dispose();
    _stepCtrl.dispose();
    _confettiCtrl.dispose();
    _nameCtrl.dispose();
    _balanceCtrl.dispose();
    super.dispose();
  }

  // Staggered tile animation
  Animation<double> _tileAnim(int i) {
    final start = i * 0.10;
    final end = (start + 0.60).clamp(0.0, 1.0);
    return CurvedAnimation(
      parent: _tileCtrl,
      curve: Interval(start, end,
          curve: const Cubic(0.34, 1.56, 0.64, 1.0)),
    );
  }

  void _selectType(_AType t) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedType = t;
      _swatchColor = t.type;
      _nameCtrl.clear();
      _balanceCtrl.clear();
      _animatedBalance = 0;
      _success = false;
    });
    Future.delayed(const Duration(milliseconds: 60), () {
      if (mounted) {
        setState(() => _step = 1);
        _stepCtrl.forward(from: 0);
      }
    });
  }

  void _goBack() {
    HapticFeedback.selectionClick();
    _stepCtrl.reverse().then((_) {
      if (mounted) setState(() => _step = 0);
    });
  }

  Future<void> _submit() async {
    if (_saving || _success) return;
    HapticFeedback.mediumImpact();
    setState(() => _saving = true);

    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) {
      setState(() => _saving = false);
      return;
    }
    final repo = ref.read(accountRepositoryProvider);
    final t = _selectedType!;
    final rawBalance = double.tryParse(_balanceCtrl.text) ?? 0.0;
    final opening = t.type.isLiability ? -rawBalance.abs() : rawBalance;
    final name = _nameCtrl.text.trim().isEmpty ? t.defaultName : _nameCtrl.text.trim();

    try {
      await repo.add(
        user.uid,
        Account(
          id: '',
          name: name,
          type: t.type,
          openingBalance: opening,
          currencyCode: _currencyCode,
          createdAt: DateTime.now(),
        ),
      );
      if (mounted) {
        // Force a refresh so the new account shows immediately (critical for
        // offline adds where the Hive watch stream may not auto-trigger).
        ref.invalidate(accountsProvider);
        setState(() {
          _saving = false;
          _success = true;
        });
        _confettiCtrl.forward(from: 0);
        AppToast.show(context, 'Account added', type: AppToastType.success);
        await Future.delayed(const Duration(milliseconds: 1400));
        if (mounted) Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = _paletteForAccountType(_swatchColor);
    final brand = context.brand;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: brand.inkSoft.withValues(alpha: 0.25),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Nav bar
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
            child: Row(
              children: [
                AnimatedOpacity(
                  opacity: _step == 1 ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: _step == 1 ? _goBack : null,
                    child: Icon(CupertinoIcons.chevron_left,
                        size: 22, color: brand.ink),
                  ),
                ),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Text(
                      _step == 0 ? context.t('account.addAccount') : context.t('account.accountDetails'),
                      key: ValueKey(_step),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 38),
              ],
            ),
          ),
          // Step indicator
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 3,
                    decoration: BoxDecoration(
                      color: brand.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 320),
                    height: 3,
                    decoration: BoxDecoration(
                      color: _step >= 1
                          ? brand.accent
                          : brand.inkSoft.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Steps — intrinsic height with AnimatedSwitcher
          Flexible(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 480),
            switchInCurve: const Cubic(0.34, 1.36, 0.64, 1.0),
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) {
              final isNew = child.key == ValueKey(_step);
              final slide = Tween<Offset>(
                begin: Offset(isNew ? 0.3 : -0.3, 0),
                end: Offset.zero,
              ).animate(anim);
              return FadeTransition(
                opacity: anim,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: _step == 0
                ? _Step1(
                    key: const ValueKey(0),
                    tileAnim: _tileAnim,
                    onSelect: _selectType,
                  )
                : _Step2(
                    key: const ValueKey(1),
                    selectedType: _selectedType!,
                    swatchColor: _swatchColor,
                    pal: pal,
                    nameCtrl: _nameCtrl,
                    balanceCtrl: _balanceCtrl,
                    animatedBalance: _animatedBalance,
                    success: _success,
                    saving: _saving,
                    confettiAnim: _confettiAnim,
                    currencyCode: _currencyCode,
                    onSwatchChanged: (t) =>
                        setState(() => _swatchColor = t),
                    onCurrencyChanged: (c) =>
                        setState(() => _currencyCode = c),
                    onSubmit: _submit,
                  ),
          ),
          ),
          const SizedBox(height: 20),
        ],
      ),
      ),
    );
  }
}

// ── Step 1: type selection ────────────────────────────────────
class _Step1 extends StatelessWidget {
  final Animation<double> Function(int) tileAnim;
  final ValueChanged<_AType> onSelect;

  const _Step1({super.key, required this.tileAnim, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            context.t('account.whatType'),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.4,
              color: brand.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.t('account.chooseOne'),
            style: TextStyle(fontSize: 13, color: brand.inkSoft),
          ),
          const SizedBox(height: 18),
          // 2×2 grid
          Row(
            children: [
              for (int i = 0; i < 2; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 0 ? 6 : 0),
                    child: _TileCard(
                      aType: _kAddTypes[i],
                      anim: tileAnim(i),
                      onTap: () => onSelect(_kAddTypes[i]),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int i = 2; i < 4; i++)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(right: i == 2 ? 6 : 0),
                    child: _TileCard(
                      aType: _kAddTypes[i],
                      anim: tileAnim(i),
                      onTap: () => onSelect(_kAddTypes[i]),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Other row
          AnimatedBuilder(
            animation: tileAnim(4),
            builder: (ctx, child) {
              final v = tileAnim(4).value;
              return Opacity(
                opacity: v.clamp(0.0, 1.0),
                child: Transform.scale(scale: 0.5 + 0.5 * v, child: child),
              );
            },
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                HapticFeedback.selectionClick();
                showModalBottomSheet<_AType>(
                  context: context,
                  backgroundColor: Colors.transparent,
                  isScrollControlled: true,
                  builder: (_) => const _OtherTypesSheet(),
                ).then((t) {
                  if (t != null) onSelect(t);
                });
              },
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: brand.background,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        CupertinoIcons.ellipsis_circle_fill,
                        size: 18,
                        color: brand.inkSoft,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t('account.otherTypes'),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: brand.ink,
                            ),
                          ),
                          Text(
                            '8 extra categories',
                            style: TextStyle(
                              fontSize: 11,
                              color: brand.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(CupertinoIcons.chevron_right,
                        size: 14,
                        color: brand.inkSoft),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ── Other Types Sheet ─────────────────────────────────────────
class _OtherTypesSheet extends StatelessWidget {
  const _OtherTypesSheet();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: brand.inkSoft.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.t('account.otherTypes'),
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -0.4,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.t('account.extra8'),
                          style: TextStyle(
                            fontSize: 13,
                            color: brand.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: brand.inkSoft.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        CupertinoIcons.xmark,
                        size: 13,
                        color: brand.inkSoft,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // List
            Container(
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: _kOtherTypes.asMap().entries.map((entry) {
                  final i = entry.key;
                  final t = entry.value;
                  final pal = _paletteForAccountType(t.type);
                  final isLast = i == _kOtherTypes.length - 1;
                  return Column(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.vertical(
                          top: i == 0 ? const Radius.circular(16) : Radius.zero,
                          bottom: isLast ? const Radius.circular(16) : Radius.zero,
                        ),
                        onTap: () {
                          HapticFeedback.selectionClick();
                          Navigator.pop(context, t);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [pal.a, pal.b],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  borderRadius: BorderRadius.circular(11),
                                ),
                                child: Icon(t.icon, size: 18, color: pal.ink),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.t(t.labelKey),
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600,
                                        color: brand.ink,
                                      ),
                                    ),
                                    const SizedBox(height: 1),
                                    Text(
                                      context.t(t.subKey),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: brand.inkSoft,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                CupertinoIcons.chevron_right,
                                size: 13,
                                color: brand.inkSoft,
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (!isLast)
                        Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 70,
                          color: brand.divider,
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

// ── Tile card ─────────────────────────────────────────────────
class _TileCard extends StatefulWidget {
  final _AType aType;
  final Animation<double> anim;
  final VoidCallback onTap;

  const _TileCard({
    required this.aType,
    required this.anim,
    required this.onTap,
  });

  @override
  State<_TileCard> createState() => _TileCardState();
}

class _TileCardState extends State<_TileCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final pal = _paletteForAccountType(widget.aType.type);
    return AnimatedBuilder(
      animation: widget.anim,
      builder: (ctx, child) {
        final v = widget.anim.value;
        final rotDeg = (1 - v) * -10.0;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform(
            transform: Matrix4.identity()
              ..scaleByDouble(0.5 + 0.5 * v, 0.5 + 0.5 * v, 1.0, 1.0)
              ..rotateZ(rotDeg * pi / 180),
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.94 : 1.0,
          duration: const Duration(milliseconds: 120),
          child: Container(
            height: 140,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [pal.a, pal.b],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: pal.b.withValues(alpha: 0.45),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                // Circle accent bg
                Positioned(
                  right: -10,
                  top: -10,
                  child: Container(
                    width: 90,
                    height: 90,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: pal.accent.withValues(alpha: 0.14),
                    ),
                  ),
                ),
                // Watermark glyph
                Positioned(
                  right: -10,
                  bottom: -28,
                  child: Text(
                    pal.glyph,
                    style: TextStyle(
                      fontSize: 110,
                      fontWeight: FontWeight.w900,
                      color: pal.accent.withValues(alpha: 0.15),
                      height: 1,
                    ),
                  ),
                ),
                // Shine
                Positioned(
                  top: -30,
                  left: -20,
                  child: Container(
                    width: 130,
                    height: 130,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.55),
                          Colors.white.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                // Content
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(widget.aType.icon,
                          size: 26, color: pal.ink),
                      const Spacer(),
                      Text(
                        context.t(widget.aType.labelKey),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.2,
                          color: pal.ink,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        context.t(widget.aType.subKey),
                        style: TextStyle(
                          fontSize: 11,
                          color: pal.ink.withValues(alpha: 0.65),
                        ),
                      ),
                    ],
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

// ── Step 2: details form ──────────────────────────────────────
class _Step2 extends StatefulWidget {
  final _AType selectedType;
  final AccountType swatchColor;
  final _Pal pal;
  final TextEditingController nameCtrl;
  final TextEditingController balanceCtrl;
  final double animatedBalance;
  final bool success;
  final bool saving;
  final Animation<double> confettiAnim;
  final ValueChanged<AccountType> onSwatchChanged;
  final ValueChanged<String> onCurrencyChanged;
  final String currencyCode;
  final VoidCallback onSubmit;

  const _Step2({
    super.key,
    required this.selectedType,
    required this.swatchColor,
    required this.pal,
    required this.nameCtrl,
    required this.balanceCtrl,
    required this.animatedBalance,
    required this.success,
    required this.saving,
    required this.confettiAnim,
    required this.currencyCode,
    required this.onSwatchChanged,
    required this.onCurrencyChanged,
    required this.onSubmit,
  });

  @override
  State<_Step2> createState() => _Step2State();
}

class _Step2State extends State<_Step2> {
  String? _selectedProvider;
  bool _useCustomName = false;

  bool get _hasProviderList =>
      widget.selectedType.type == AccountType.bank ||
      widget.selectedType.type == AccountType.eWallet;

  List<String> get _providerList =>
      widget.selectedType.type == AccountType.bank
          ? kCommonBanks
          : kCommonWallets;

  @override
  void didUpdateWidget(_Step2 old) {
    super.didUpdateWidget(old);
    if (old.selectedType.type != widget.selectedType.type) {
      setState(() {
        _selectedProvider = null;
        _useCustomName = false;
      });
    }
  }

  void _showProviderPicker() {
    final label = widget.selectedType.type == AccountType.bank
        ? 'Select Bank'
        : 'Select E-Wallet';
    final allProviders = List<String>.from(_providerList);
    final brand = context.brand;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(builder: (ctx, setSheet) {
          final filtered = query.isEmpty
              ? allProviders
              : allProviders
                  .where((p) => p.toLowerCase().contains(query.toLowerCase()))
                  .toList();
          return Container(
            decoration: BoxDecoration(
              color: brand.background,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: MediaQuery.of(ctx).size.height * 0.70,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 10),
                        width: 36, height: 4,
                        decoration: BoxDecoration(
                          color: brand.inkSoft.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: Container(
                        height: 40,
                        decoration: BoxDecoration(
                          color: brand.surface,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TextField(
                          autofocus: false,
                          onChanged: (v) => setSheet(() => query = v),
                          style: TextStyle(fontSize: 14, color: brand.ink),
                          decoration: InputDecoration(
                            hintText: 'Search…',
                            hintStyle: TextStyle(
                                color: brand.inkSoft,
                                fontSize: 14),
                            prefixIcon: Icon(CupertinoIcons.search,
                                size: 16,
                                color: brand.inkSoft),
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => Divider(
                          height: 1,
                          color: brand.divider,
                        ),
                        itemBuilder: (_, index) {
                          final p = filtered[index];
                          final isCustom = p == _kCustomLabel;
                          final isSelected = isCustom
                              ? _useCustomName
                              : _selectedProvider == p && !_useCustomName;
                          return ListTile(
                            leading: isCustom
                                ? Icon(CupertinoIcons.pencil,
                                    size: 18,
                                    color: brand.inkSoft)
                                : Icon(
                                    widget.selectedType.icon,
                                    size: 18,
                                    color: widget.pal.accent,
                                  ),
                            title: Text(
                              isCustom ? context.t('account.typeOtherCustom') : p,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: brand.ink,
                              ),
                            ),
                            trailing: isSelected
                                ? Icon(CupertinoIcons.checkmark_alt,
                                    color: AppActionBlue.color)
                                : null,
                            onTap: () {
                              setState(() {
                                _selectedProvider = p;
                                _useCustomName = isCustom;
                                if (!isCustom) {
                                  widget.nameCtrl.text = p;
                                } else {
                                  widget.nameCtrl.clear();
                                }
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        });
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final displayName = widget.nameCtrl.text.isEmpty
        ? widget.selectedType.defaultName
        : widget.nameCtrl.text;

    return GestureDetector(
      onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
      behavior: HitTestBehavior.translucent,
      child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Live preview card ─────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 360),
            height: 168,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [widget.pal.a, widget.pal.b],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: widget.pal.b.withValues(alpha: 0.55),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            clipBehavior: Clip.hardEdge,
            child: Stack(
              children: [
                Positioned(
                  right: -70,
                  top: -70,
                  child: Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: widget.pal.accent.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                Positioned(
                  right: -20,
                  bottom: -54,
                  child: Text(
                    widget.pal.glyph,
                    style: TextStyle(
                      fontSize: 180,
                      fontWeight: FontWeight.w900,
                      color: widget.pal.accent.withValues(alpha: 0.08),
                      height: 1,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t(widget.pal.labelKey),
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.3,
                          color: widget.pal.ink.withValues(alpha: 0.60),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        displayName,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: widget.pal.ink,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const Spacer(),
                      Text(
                        context.t('account.balance'),
                        style: TextStyle(
                          fontSize: 10,
                          letterSpacing: 1.3,
                          color: widget.pal.ink.withValues(alpha: 0.60),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      TweenAnimationBuilder<double>(
                        tween: Tween(begin: 0, end: widget.animatedBalance),
                        duration: const Duration(milliseconds: 360),
                        curve: Curves.easeOutCubic,
                        builder: (ctx, v, _) {
                          final sym = kSupportedCurrencies[widget.currencyCode] ?? widget.currencyCode;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                NumberFormat.currency(
                                  symbol: '$sym ',
                                  decimalDigits: 2,
                                ).format(v),
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w700,
                                  color: widget.pal.ink,
                                  letterSpacing: -0.4,
                                ),
                              ),
                              Consumer(builder: (ctx, ref, _) {
                                final mainCode = ref.watch(currencyCodeProvider).valueOrNull ?? 'MYR';
                                final converter = ref.watch(currencyConverterProvider).valueOrNull;
                                if (widget.currencyCode == mainCode || converter == null || v <= 0) {
                                  return const SizedBox.shrink();
                                }
                                final mainSym = kSupportedCurrencies[mainCode] ?? mainCode;
                                final est = converter.toBase(v, widget.currencyCode);
                                return Text(
                                  'est. $mainSym ${est.toStringAsFixed(2)}',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: widget.pal.ink.withValues(alpha: 0.55),
                                  ),
                                );
                              }),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),
          Text(
            'Fill in the details below',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: brand.inkSoft,
            ),
          ),
          const SizedBox(height: 14),

          // ── Form fields ──────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                // Provider picker row (bank / e-wallet only)
                if (_hasProviderList) ...[
                  InkWell(
                    borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(16)),
                    onTap: _showProviderPicker,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: widget.pal.accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(widget.selectedType.icon,
                                size: 15, color: widget.pal.accent),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              widget.selectedType.type == AccountType.bank
                                  ? 'BANK'
                                  : 'E-WALLET',
                              style: TextStyle(
                                fontSize: 11,
                                letterSpacing: 0.5,
                                color: brand.inkSoft,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            _useCustomName
                                ? 'Custom'
                                : (_selectedProvider ??
                                    (widget.selectedType.type ==
                                            AccountType.bank
                                        ? 'Select bank'
                                        : 'Select e-wallet')),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                              color: _selectedProvider != null
                                  ? brand.ink
                                  : brand.inkSoft.withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(CupertinoIcons.chevron_right,
                              size: 13,
                              color: brand.inkSoft),
                        ],
                      ),
                    ),
                  ),
                  // Custom name field — only when "Other / Custom" selected
                  if (_useCustomName) ...[
                    Divider(
                        height: 1,
                        thickness: 0.5,
                        color: brand.divider,
                        indent: 16),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'NAME',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 0.5,
                              color: brand.inkSoft,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          TextField(
                            controller: widget.nameCtrl,
                            autofocus: true,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: brand.ink,
                            ),
                            decoration: InputDecoration(
                              hintText: widget.selectedType.defaultName,
                              hintStyle: TextStyle(
                                color: brand.inkSoft.withValues(alpha: 0.5),
                                fontWeight: FontWeight.w500,
                              ),
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ] else ...[
                  // Free name field for non-provider types
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'NAME',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.5,
                            color: brand.inkSoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextField(
                          controller: widget.nameCtrl,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: brand.ink,
                          ),
                          decoration: InputDecoration(
                            hintText: widget.selectedType.defaultName,
                            hintStyle: TextStyle(
                              color: brand.inkSoft.withValues(alpha: 0.5),
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                Divider(
                    height: 1,
                    thickness: 0.5,
                    color: brand.divider,
                    indent: 16),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.t('account.startingBalance'),
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 0.5,
                          color: brand.inkSoft,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            kSupportedCurrencies[widget.currencyCode] ?? widget.currencyCode,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: brand.inkSoft,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: TextField(
                              controller: widget.balanceCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: brand.ink,
                              ),
                              decoration: InputDecoration(
                                hintText: '0.00',
                                hintStyle: TextStyle(
                                  color: brand.inkSoft,
                                  fontWeight: FontWeight.w500,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Divider(
                    height: 1,
                    thickness: 0.5,
                    color: brand.divider,
                    indent: 16),
                // Currency picker row
                InkWell(
                  onTap: () => showCurrencyPickerSheet(
                    context,
                    current: widget.currencyCode,
                    onPicked: widget.onCurrencyChanged,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      children: [
                        Text(
                          'CURRENCY',
                          style: TextStyle(
                            fontSize: 11,
                            letterSpacing: 0.5,
                            color: brand.inkSoft,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${kSupportedCurrencies[widget.currencyCode] ?? widget.currencyCode} (${widget.currencyCode})',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: brand.ink,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(CupertinoIcons.chevron_right, size: 13, color: brand.inkSoft),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ── CTA button + confetti ─────────────────────────
          Stack(
            clipBehavior: Clip.none,
            children: [
              // Confetti pieces
              if (widget.success)
                ...List.generate(12, (i) {
                  final angle =
                      (i / 12) * 2 * pi + (Random().nextDouble() * 0.35);
                  final dist = 60 + Random().nextDouble() * 50;
                  final cx = cos(angle) * dist;
                  final cy = sin(angle) * dist;
                  final cr = Random().nextDouble() * 2 * pi;
                  final c = _kConfettiColors[i % 5];
                  return AnimatedBuilder(
                    animation: widget.confettiAnim,
                    builder: (ctx, _) {
                      final v = widget.confettiAnim.value;
                      return Positioned(
                        left: (MediaQuery.of(ctx).size.width - 40) / 2 +
                            cx * v -
                            4,
                        top: 24 + cy * v - 4,
                        child: Opacity(
                          opacity: (1 - v).clamp(0.0, 1.0),
                          child: Transform.rotate(
                            angle: cr * v,
                            child: Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: c,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }),
              // Button
              GestureDetector(
                onTap: widget.onSubmit,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 320),
                  height: 52,
                  decoration: BoxDecoration(
                    color: widget.success
                        ? const Color(0xFF1B8A4A)
                        : AppActionBlue.color,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Center(
                    child: widget.success
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration:
                                    const Duration(milliseconds: 480),
                                curve: const Cubic(0.34, 1.56, 0.64, 1.0),
                                builder: (ctx, v, _) => Transform.scale(
                                  scale: v,
                                  child: Container(
                                    width: 24,
                                    height: 24,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                    child: Center(
                                      child: CustomPaint(
                                        size: const Size(14, 14),
                                        painter: _TickPainter(
                                          progress: v,
                                          color: const Color(0xFF1B8A4A),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                context.t('account.addAccount'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                            ],
                          )
                        : widget.saving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : Text(
                                context.t('account.addAccount'),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: -0.2,
                                ),
                              ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

}

// ── Tick painter (animates stroke-dashoffset) ─────────────────
class _TickPainter extends CustomPainter {
  final double progress;
  final Color color;

  const _TickPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Checkmark path: (25%, 50%) → (45%, 70%) → (75%, 30%)
    final p1 = Offset(size.width * 0.2, size.height * 0.5);
    final p2 = Offset(size.width * 0.45, size.height * 0.72);
    final p3 = Offset(size.width * 0.78, size.height * 0.28);

    final total = (p2 - p1).distance + (p3 - p2).distance;
    final drawn = total * progress;

    if (drawn <= 0) return;

    final firstLeg = (p2 - p1).distance;
    if (drawn <= firstLeg) {
      final t = drawn / firstLeg;
      canvas.drawLine(p1, Offset.lerp(p1, p2, t)!, paint);
    } else {
      canvas.drawLine(p1, p2, paint);
      final remaining = drawn - firstLeg;
      final secondLeg = (p3 - p2).distance;
      final t = (remaining / secondLeg).clamp(0.0, 1.0);
      canvas.drawLine(p2, Offset.lerp(p2, p3, t)!, paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) =>
      old.progress != progress || old.color != color;
}
