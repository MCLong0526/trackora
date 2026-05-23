import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/personal_group_toggle.dart';
import 'add_group_expense_screen.dart';
import 'create_group_screen.dart';
import 'group_detail_screen.dart';
import 'group_invite_screen.dart';
import 'join_group_screen.dart';

class GroupDashboardScreen extends ConsumerWidget {
  const GroupDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final groupsAsync = ref.watch(myGroupsProvider);
    final activeGroupId = ref.watch(activeGroupIdProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '';
    final user = ref.watch(authStateProvider).valueOrNull;

    final groups = groupsAsync.valueOrNull ?? const [];

    // Auto-select first group if active is null
    if (activeGroupId == null && groups.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeGroupIdProvider.notifier).state = groups.first.id;
      });
    }

    final activeGroup = groups.cast<ExpenseGroup?>().firstWhere(
          (g) => g?.id == activeGroupId,
          orElse: () => groups.isNotEmpty ? groups.first : null,
        );

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      DateFormat('EEEE').format(DateTime.now()),
                      style: TextStyle(
                        color: brand.inkSoft,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Trackora',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF0B0B0F),
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
                // Group avatar pair pill
                if (activeGroup != null)
                  _GroupAvatarPill(group: activeGroup, userId: user?.uid)
                else
                  _GroupAvatarPill(group: null, userId: user?.uid),
              ],
            ),
          ),

          // ── Segmented control ─────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: PersonalGroupToggle(brand: brand),
          ),

          // ── Scrollable body ───────────────────────────────────
          Expanded(
            child: groupsAsync.isLoading
                ? const Center(child: CupertinoActivityIndicator())
                : groups.isEmpty
                    ? _IntroView(brand: brand)
                    : _GroupBody(
                        brand: brand,
                        group: activeGroup,
                        symbol: symbol,
                        userId: user?.uid,
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Group avatar pair pill ───────────────────────────────────────────────────

class _GroupAvatarPill extends StatelessWidget {
  final ExpenseGroup? group;
  final String? userId;

  const _GroupAvatarPill({required this.group, required this.userId});

  @override
  Widget build(BuildContext context) {
    final me = group?.members.where((m) => m.uid == userId).firstOrNull;
    final partner =
        group?.members.where((m) => m.uid != userId).firstOrNull;
    final myInitial =
        (me?.displayName.substring(0, 1) ?? 'Y').toUpperCase();
    final partnerInitial =
        (partner?.displayName.substring(0, 1) ?? 'J').toUpperCase();

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Overlapping avatars
          SizedBox(
            width: 46,
            height: 28,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  child: _MiniAvatar(
                    letter: myInitial,
                    bg: const Color(0xFFEAE3F8),
                    fg: const Color(0xFF5A4AAB),
                    size: 28,
                  ),
                ),
                Positioned(
                  left: 18,
                  child: _MiniAvatar(
                    letter: partnerInitial,
                    bg: const Color(0xFFD7F4E5),
                    fg: const Color(0xFF1FBE71),
                    size: 28,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            CupertinoIcons.chevron_down,
            size: 13,
            color: const Color(0xFF8E8E96),
          ),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final String letter;
  final Color bg;
  final Color fg;
  final double size;

  const _MiniAvatar({
    required this.letter,
    required this.bg,
    required this.fg,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: bg,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
      ),
      child: Center(
        child: Text(
          letter,
          style: TextStyle(
            color: fg,
            fontSize: size * 0.38,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

// ── Intro view (no group) ────────────────────────────────────────────────────

class _IntroView extends StatelessWidget {
  final BrandColors brand;
  const _IntroView({required this.brand});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF1A6CFF).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(CupertinoIcons.person_2_fill,
                  color: Color(0xFF1A6CFF), size: 28),
            ),
            const SizedBox(height: 16),
            Text(
              context.t('group.noGroups'),
              style: TextStyle(
                color: brand.ink,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('group.createFirst'),
              textAlign: TextAlign.center,
              style: TextStyle(color: brand.inkSoft, fontSize: 14),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _PillButton(
                  label: context.t('group.createGroup'),
                  icon: CupertinoIcons.plus,
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const CreateGroupScreen()),
                  ),
                ),
                const SizedBox(width: 12),
                _PillButton(
                  label: context.t('group.joinGroup'),
                  icon: CupertinoIcons.arrow_right_circle,
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const JoinGroupScreen()),
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

// ── Group body (has group) ───────────────────────────────────────────────────

class _GroupBody extends ConsumerWidget {
  final BrandColors brand;
  final ExpenseGroup? group;
  final String symbol;
  final String? userId;

  const _GroupBody({
    required this.brand,
    required this.group,
    required this.symbol,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (group == null) {
      return _IntroView(brand: brand);
    }

    final expensesAsync = ref.watch(groupExpensesProvider(group!.id));
    final expenses = expensesAsync.valueOrNull ?? const [];
    final service = ref.read(expenseGroupServiceProvider);
    final balances = service.computeBalances(group!.members, expenses);
    final myBalance = balances
        .cast<dynamic>()
        .firstWhere((b) => b.uid == userId, orElse: () => null);
    final partnerBalance = balances
        .cast<dynamic>()
        .firstWhere((b) => b.uid != userId, orElse: () => null);
    final myNet = myBalance?.net as double? ?? 0;
    final totalSpent = expenses.fold<double>(0, (s, e) => s + e.amount);

    final me = group!.members.where((m) => m.uid == userId).firstOrNull;
    final partner =
        group!.members.where((m) => m.uid != userId).firstOrNull;
    final myInitial =
        (me?.displayName.substring(0, 1) ?? 'Y').toUpperCase();
    final partnerInitial =
        (partner?.displayName.substring(0, 1) ?? 'J').toUpperCase();
    final partnerName = partner?.displayName ?? 'Partner';
    final myPaid = myBalance?.totalPaid as double? ?? 0;
    final partnerPaid = partnerBalance?.totalPaid as double? ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
      children: [
        // ── Hero card ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 22, 22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Month label + Group + Spent
              Row(
                children: [
                  Expanded(
                    child: Text(
                      DateFormat('MMMM yyyy').format(DateTime.now()),
                      style: TextStyle(
                        color: brand.inkSoft,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'Group',
                        style: TextStyle(
                          color: brand.inkSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        'Spent',
                        style: TextStyle(
                          color: brand.inkSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // Large amount
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    symbol,
                    style: TextStyle(
                      color: brand.inkSoft,
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    NumberFormat('#,##0.00').format(totalSpent),
                    style: TextStyle(
                      color: brand.ink,
                      fontSize: 50,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      height: 1,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Who paid row
              Container(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    _MiniAvatar(
                      letter: myInitial,
                      bg: const Color(0xFFEAE3F8),
                      fg: const Color(0xFF5A4AAB),
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'You paid',
                            style: TextStyle(
                              color: brand.inkSoft,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$symbol${myPaid.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: brand.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 1,
                      height: 32,
                      color: brand.divider,
                      margin: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    _MiniAvatar(
                      letter: partnerInitial,
                      bg: const Color(0xFFD7F4E5),
                      fg: const Color(0xFF1FBE71),
                      size: 28,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$partnerName paid',
                            style: TextStyle(
                              color: brand.inkSoft,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$symbol${partnerPaid.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: brand.ink,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Balance chip
              if (myNet.abs() > 0.005)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: myNet > 0
                        ? const Color(0xFFD7F4E5)
                        : const Color(0xFFFBE5C9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        myNet > 0
                            ? '$partnerName owes you  '
                            : 'You owe $partnerName  ',
                        style: TextStyle(
                          color: myNet > 0
                              ? const Color(0xFF1FBE71)
                              : const Color(0xFFF0A33A),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        '$symbol${myNet.abs().toStringAsFixed(2)}',
                        style: TextStyle(
                          color: myNet > 0
                              ? const Color(0xFF1FBE71)
                              : const Color(0xFFF0A33A),
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                )
              else if (totalSpent > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD7F4E5),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Text(
                    'All settled up',
                    style: TextStyle(
                      color: Color(0xFF1FBE71),
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        // ── Activity section ───────────────────────────────────
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Activity',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Color(0xFF0B0B0F),
                letterSpacing: -0.3,
              ),
            ),
            Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => AddGroupExpenseScreen(group: group!),
                    ),
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A6CFF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(CupertinoIcons.plus,
                            color: Colors.white, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Add',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => GroupDetailScreen(group: group!),
                    ),
                  ),
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      CupertinoIcons.calendar,
                      color: brand.inkSoft,
                      size: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        const SizedBox(height: 12),

        // Expense list card
        if (expenses.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Center(
              child: Column(
                children: [
                  Icon(CupertinoIcons.square_list,
                      color: brand.inkSoft, size: 32),
                  const SizedBox(height: 8),
                  Text(
                    'No expenses yet',
                    style: TextStyle(color: brand.inkSoft, fontSize: 14),
                  ),
                ],
              ),
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(28),
            ),
            child: Column(
              children: [
                for (int i = 0; i < expenses.take(10).length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: 1,
                      thickness: 0.5,
                      indent: 74,
                      endIndent: 18,
                      color: brand.divider,
                    ),
                  _ActivityRow(
                    brand: brand,
                    expense: expenses[i],
                    members: group!.members,
                    symbol: symbol,
                    userId: userId,
                  ),
                ],
              ],
            ),
          ),

        const SizedBox(height: 16),

        // Invite partner button (if only one member)
        if (group!.members.length < 2)
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => GroupInviteScreen(group: group!),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF1A6CFF).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(CupertinoIcons.person_badge_plus,
                      color: Color(0xFF1A6CFF), size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Invite partner',
                    style: TextStyle(
                      color: Color(0xFF1A6CFF),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ── Activity row ─────────────────────────────────────────────────────────────

class _ActivityRow extends StatelessWidget {
  final BrandColors brand;
  final GroupExpenseItem expense;
  final List<GroupMember> members;
  final String symbol;
  final String? userId;

  const _ActivityRow({
    required this.brand,
    required this.expense,
    required this.members,
    required this.symbol,
    required this.userId,
  });

  String _memberName(String uid) {
    try {
      return members.firstWhere((m) => m.uid == uid).displayName;
    } catch (_) {
      return 'Someone';
    }
  }

  String _memberInitial(String uid) => _memberName(uid).substring(0, 1).toUpperCase();

  Color _categoryColor(String cat) {
    return switch (cat) {
      'Food' => const Color(0xFFF0A33A),
      'Groceries' => const Color(0xFF1FBE71),
      'Transport' => const Color(0xFF1A6CFF),
      'Shopping' => const Color(0xFFF47A85),
      'Entertainment' => const Color(0xFF9F8DDB),
      'Health' => const Color(0xFFFF6B6B),
      'Bills' => const Color(0xFF8E8E96),
      _ => const Color(0xFF1A6CFF),
    };
  }

  IconData _categoryIcon(String cat) {
    return switch (cat) {
      'Food' => CupertinoIcons.flame_fill,
      'Groceries' => CupertinoIcons.cart_fill,
      'Transport' => CupertinoIcons.car_fill,
      'Shopping' => CupertinoIcons.bag_fill,
      'Entertainment' => CupertinoIcons.tv_fill,
      'Health' => CupertinoIcons.heart_fill,
      'Bills' => CupertinoIcons.doc_fill,
      _ => CupertinoIcons.money_dollar_circle_fill,
    };
  }

  @override
  Widget build(BuildContext context) {
    final isMine = expense.paidBy == userId;
    final dateStr = DateFormat('MMM d').format(expense.date);
    final catColor = _categoryColor(expense.category);
    final payerInitial = _memberInitial(expense.paidBy);
    final payerIsMine = expense.paidBy == userId;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          // Category icon tile
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: catColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(_categoryIcon(expense.category),
                color: catColor, size: 20),
          ),
          const SizedBox(width: 14),
          // Description + payer
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        expense.description,
                        style: TextStyle(
                          color: brand.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // Payer mini avatar
                    Container(
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        color: payerIsMine
                            ? const Color(0xFFEAE3F8)
                            : const Color(0xFFD7F4E5),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          payerInitial,
                          style: TextStyle(
                            color: payerIsMine
                                ? const Color(0xFF5A4AAB)
                                : const Color(0xFF1FBE71),
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${isMine ? 'You' : _memberName(expense.paidBy)} paid · $dateStr',
                  style: TextStyle(
                    color: brand.inkSoft,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$symbol${expense.amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: brand.ink,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper widgets ───────────────────────────────────────────────────────────

class _PillButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PillButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF1A6CFF),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
