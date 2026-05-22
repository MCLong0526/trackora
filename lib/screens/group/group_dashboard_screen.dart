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
import '../../widgets/profile_avatar_button.dart';
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
      child: CustomScrollView(
        slivers: [
          // Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
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
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Trackora',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: brand.ink,
                        ),
                      ),
                    ],
                  ),
                  const ProfileAvatarButton(),
                ],
              ),
            ),
          ),

          // Personal / Group toggle pill
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
              child: PersonalGroupToggle(brand: brand),
            ),
          ),

          if (groupsAsync.isLoading)
            const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            )
          else if (groups.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _NoGroupsView(brand: brand),
            )
          else ...[
            // Group switcher (if multiple groups)
            if (groups.length > 1)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: _GroupSwitcher(
                    brand: brand,
                    groups: groups,
                    activeGroupId:
                        activeGroupId ?? groups.first.id,
                    onSwitch: (id) =>
                        ref.read(activeGroupIdProvider.notifier).state = id,
                  ),
                ),
              ),

            if (activeGroup != null) ...[
              _GroupContentSliver(
                brand: brand,
                group: activeGroup,
                symbol: symbol,
                userId: user?.uid,
              ),
            ],
          ],

          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ),
    );
  }
}

// ── No groups view ───────────────────────────────────────────────────────────

class _NoGroupsView extends StatelessWidget {
  final BrandColors brand;
  const _NoGroupsView({required this.brand});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppActionBlue.color.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(CupertinoIcons.person_3_fill,
                color: AppActionBlue.color, size: 32),
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
            style: TextStyle(
              color: brand.inkSoft,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 32),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PillButton(
                brand: brand,
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
                brand: brand,
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
    );
  }
}

// ── Group content sliver ─────────────────────────────────────────────────────

class _GroupContentSliver extends ConsumerWidget {
  final BrandColors brand;
  final ExpenseGroup group;
  final String symbol;
  final String? userId;

  const _GroupContentSliver({
    required this.brand,
    required this.group,
    required this.symbol,
    required this.userId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final expensesAsync = ref.watch(groupExpensesProvider(group.id));
    final expenses = expensesAsync.valueOrNull ?? const [];
    final service = ref.read(expenseGroupServiceProvider);
    final balances = service.computeBalances(group.members, expenses);
    final myBalance = balances
        .cast<dynamic>()
        .firstWhere((b) => b.uid == userId, orElse: () => null);
    final myNet = myBalance?.net as double? ?? 0;
    final totalSpent =
        expenses.fold<double>(0, (s, e) => s + e.amount);

    return SliverList(
      delegate: SliverChildListDelegate([
        // Group summary card
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: GestureDetector(
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => GroupDetailScreen(group: group),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppActionBlue.color,
                    AppActionBlue.color.withValues(alpha: 0.75),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Icon(CupertinoIcons.chevron_right,
                          color: Colors.white70, size: 16),
                    ],
                  ),
                  const SizedBox(height: 4),
                  // Member avatars
                  Row(
                    children: [
                      ...group.members.take(5).map((m) => Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(right: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.3),
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.5)),
                            ),
                            child: Center(
                              child: Text(
                                m.displayName.substring(0, 1).toUpperCase(),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )),
                      if (group.members.length > 5)
                        Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '+${group.members.length - 5}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                      const SizedBox(width: 6),
                      Text(
                        '${group.members.length} ${context.t('group.members').toLowerCase()}',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.t('group.totalSpent'),
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 11),
                            ),
                            Text(
                              '$symbol${totalSpent.toStringAsFixed(2)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (userId != null)
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                myNet >= 0
                                    ? context.t('group.yourShare')
                                    : context.t('group.youOwe'),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 11),
                              ),
                              Text(
                                '$symbol${myNet.abs().toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),

        // Action buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _OutlineButton(
                  brand: brand,
                  icon: CupertinoIcons.plus,
                  label: context.t('group.addExpense'),
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => AddGroupExpenseScreen(group: group),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OutlineButton(
                  brand: brand,
                  icon: CupertinoIcons.person_badge_plus,
                  label: context.t('group.inviteMembers'),
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => GroupInviteScreen(group: group),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Recent expenses
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.t('group.recentExpenses'),
                style: TextStyle(
                  color: brand.ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
              GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => GroupDetailScreen(group: group),
                  ),
                ),
                child: Text(
                  context.t('group.viewAll'),
                  style: const TextStyle(
                    color: AppActionBlue.color,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),

        if (expenses.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  context.t('travel.noExpenses'),
                  style:
                      TextStyle(color: brand.inkSoft, fontSize: 14),
                ),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            child: Container(
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  for (int i = 0;
                      i < expenses.take(5).length;
                      i++) ...[
                    if (i > 0)
                      Divider(
                          height: 1,
                          thickness: 0.5,
                          indent: 16,
                          color: brand.divider),
                    _RecentExpenseRow(
                      brand: brand,
                      expense: expenses[i],
                      members: group.members,
                      symbol: symbol,
                      userId: userId,
                    ),
                  ],
                ],
              ),
            ),
          ),

        // Join or create another group
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: _OutlineButton(
                  brand: brand,
                  icon: CupertinoIcons.plus_circle,
                  label: context.t('group.createGroup'),
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const CreateGroupScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _OutlineButton(
                  brand: brand,
                  icon: CupertinoIcons.arrow_right_circle,
                  label: context.t('group.joinGroup'),
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                        builder: (_) => const JoinGroupScreen()),
                  ),
                ),
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _RecentExpenseRow extends StatelessWidget {
  final BrandColors brand;
  final GroupExpenseItem expense;
  final List<GroupMember> members;
  final String symbol;
  final String? userId;

  const _RecentExpenseRow({
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

  @override
  Widget build(BuildContext context) {
    final isMine = expense.paidBy == userId;
    final dateStr = DateFormat('MMM d').format(expense.date);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Text(
            _categoryEmoji(expense.category),
            style: const TextStyle(fontSize: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.description,
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$dateStr · ${isMine ? 'You' : _memberName(expense.paidBy)}',
                  style: TextStyle(
                      color: brand.inkSoft, fontSize: 12),
                ),
              ],
            ),
          ),
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

  String _categoryEmoji(String cat) {
    return switch (cat) {
      'Food' => '🍜',
      'Groceries' => '🛒',
      'Transport' => '🚗',
      'Shopping' => '🛍️',
      'Entertainment' => '🎬',
      'Health' => '💊',
      'Bills' => '📄',
      _ => '💰',
    };
  }
}

// ── Group switcher ───────────────────────────────────────────────────────────

class _GroupSwitcher extends StatelessWidget {
  final BrandColors brand;
  final List<ExpenseGroup> groups;
  final String activeGroupId;
  final void Function(String) onSwitch;

  const _GroupSwitcher({
    required this.brand,
    required this.groups,
    required this.activeGroupId,
    required this.onSwitch,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (_, i) {
          final g = groups[i];
          final selected = g.id == activeGroupId;
          return GestureDetector(
            onTap: () => onSwitch(g.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? AppActionBlue.color
                    : brand.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: selected
                      ? AppActionBlue.color
                      : brand.divider.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                g.name,
                style: TextStyle(
                  color: selected ? Colors.white : brand.ink,
                  fontSize: 13,
                  fontWeight:
                      selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// ── Helper widgets ───────────────────────────────────────────────────────────

class _PillButton extends StatelessWidget {
  final BrandColors brand;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PillButton({
    required this.brand,
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
          color: AppActionBlue.color,
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

class _OutlineButton extends StatelessWidget {
  final BrandColors brand;
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _OutlineButton({
    required this.brand,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: brand.divider.withValues(alpha: 0.4),
            width: 0.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: AppActionBlue.color, size: 16),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: AppActionBlue.color,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
