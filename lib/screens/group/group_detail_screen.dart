import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'add_group_expense_screen.dart';
import 'group_invite_screen.dart';

class GroupDetailScreen extends ConsumerWidget {
  final ExpenseGroup group;

  const GroupDetailScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final expensesAsync = ref.watch(groupExpensesProvider(group.id));
    final user = ref.watch(authStateProvider).valueOrNull;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '';

    return Scaffold(
      backgroundColor: brand.background,
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            backgroundColor: brand.background,
            pinned: true,
            leading: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.pop(context),
              child: Icon(CupertinoIcons.chevron_back,
                  color: AppActionBlue.color, size: 20),
            ),
            title: Text(
              group.name,
              style: TextStyle(
                color: brand.ink,
                fontSize: 17,
                fontWeight: FontWeight.w600,
              ),
            ),
            centerTitle: true,
            actions: [
              CupertinoButton(
                padding: const EdgeInsets.only(right: 8),
                onPressed: () => _showOptions(context, ref, brand, user?.uid),
                child: Icon(CupertinoIcons.ellipsis_circle,
                    color: AppActionBlue.color, size: 22),
              ),
            ],
          ),

          expensesAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(child: CupertinoActivityIndicator()),
            ),
            error: (e, _) => SliverFillRemaining(
              child: Center(
                child: Text('Error loading expenses',
                    style: TextStyle(color: brand.inkSoft)),
              ),
            ),
            data: (expenses) {
              final service = ref.read(expenseGroupServiceProvider);
              final balances =
                  service.computeBalances(group.members, expenses);
              final settlements = service.computeSettlement(balances);
              final totalSpent = expenses.fold<double>(
                  0, (s, e) => s + e.amount);

              return SliverList(
                delegate: SliverChildListDelegate([
                  _SummaryHeader(
                    brand: brand,
                    group: group,
                    totalSpent: totalSpent,
                    symbol: symbol,
                    userId: user?.uid,
                    balances: balances,
                  ),

                  // Members section
                  _SectionHeader(
                      brand: brand, title: context.t('group.members')),
                  _MembersSection(
                      brand: brand,
                      balances: balances,
                      symbol: symbol,
                      userId: user?.uid),

                  // Settlement
                  if (settlements.isNotEmpty) ...[
                    _SectionHeader(
                        brand: brand,
                        title: context.t('travel.settlement')),
                    _SettlementSection(
                        brand: brand,
                        settlements: settlements,
                        symbol: symbol,
                        userId: user?.uid),
                  ],

                  // Expenses
                  _SectionHeader(
                    brand: brand,
                    title: context.t('travel.expenses'),
                    action: TextButton.icon(
                      onPressed: () => _addExpense(context, ref),
                      icon: const Icon(CupertinoIcons.add,
                          color: AppActionBlue.color, size: 16),
                      label: Text(
                        context.t('group.addExpense'),
                        style: const TextStyle(
                            color: AppActionBlue.color, fontSize: 14),
                      ),
                    ),
                  ),
                  if (expenses.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 24),
                      child: Center(
                        child: Text(
                          context.t('travel.noExpenses'),
                          style: TextStyle(
                              color: brand.inkSoft, fontSize: 14),
                        ),
                      ),
                    )
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _ExpensesCard(
                        brand: brand,
                        expenses: expenses,
                        members: group.members,
                        symbol: symbol,
                        userId: user?.uid,
                        onEdit: (e) => _editExpense(context, e),
                        onDelete: (e) => _deleteExpense(context, ref, e),
                      ),
                    ),
                  const SizedBox(height: 48),
                ]),
              );
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addExpense(context, ref),
        backgroundColor: AppActionBlue.color,
        child: const Icon(CupertinoIcons.add, color: Colors.white),
      ),
    );
  }

  void _addExpense(BuildContext context, WidgetRef ref) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => AddGroupExpenseScreen(group: group),
      ),
    );
  }

  void _editExpense(BuildContext context, GroupExpenseItem expense) {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) =>
            AddGroupExpenseScreen(group: group, existing: expense),
      ),
    );
  }

  Future<void> _deleteExpense(
      BuildContext context, WidgetRef ref, GroupExpenseItem expense) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(context.t('group.deleteExpense')),
        content: Text(expense.description),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.t('common.cancel')),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.t('common.delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      try {
        await ref.read(expenseGroupServiceProvider)
            .deleteExpense(expense.groupId, expense.id);
        if (context.mounted) AppToast.show(context, 'Expense deleted');
      } catch (e) {
        if (context.mounted) AppToast.show(context, 'Failed to delete');
      }
    }
  }

  void _showOptions(
      BuildContext context, WidgetRef ref, BrandColors brand, String? userId) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => GroupInviteScreen(group: group),
                ),
              );
            },
            child: Text(context.t('group.inviteMembers')),
          ),
          if (userId == group.createdBy)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () async {
                Navigator.pop(context);
                final confirmed = await showCupertinoDialog<bool>(
                  context: context,
                  builder: (_) => CupertinoAlertDialog(
                    title: Text(context.t('group.deleteGroup')),
                    content: const Text(
                        'This will remove all expenses. This cannot be undone.'),
                    actions: [
                      CupertinoDialogAction(
                        isDefaultAction: true,
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(context.t('common.cancel')),
                      ),
                      CupertinoDialogAction(
                        isDestructiveAction: true,
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(context.t('common.delete')),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) {
                  try {
                    await ref
                        .read(expenseGroupServiceProvider)
                        .deleteGroup(group.id);
                    ref.read(activeGroupIdProvider.notifier).state = null;
                    ref.read(homeModeProvider.notifier).state =
                        HomeMode.personal;
                    if (context.mounted) Navigator.pop(context);
                  } catch (e) {
                    if (context.mounted) {
                      AppToast.show(context, 'Failed to delete group');
                    }
                  }
                }
              },
              child: Text(context.t('group.deleteGroup')),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(context.t('common.cancel')),
        ),
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _SummaryHeader extends StatelessWidget {
  final BrandColors brand;
  final ExpenseGroup group;
  final double totalSpent;
  final String symbol;
  final String? userId;
  final List balances;

  const _SummaryHeader({
    required this.brand,
    required this.group,
    required this.totalSpent,
    required this.symbol,
    required this.userId,
    required this.balances,
  });

  @override
  Widget build(BuildContext context) {
    final myBalance = balances.cast<dynamic>().firstWhere(
          (b) => b.uid == userId,
          orElse: () => null,
        );
    final myNet = myBalance?.net as double? ?? 0;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('group.totalSpent'),
                  style: TextStyle(
                      color: brand.inkSoft, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '$symbol${totalSpent.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          if (userId != null) ...[
            Container(
              height: 44,
              width: 1,
              color: brand.divider,
              margin: const EdgeInsets.symmetric(horizontal: 16),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    myNet >= 0 ? 'You\'re owed' : context.t('group.youOwe'),
                    style: TextStyle(
                        color: brand.inkSoft, fontSize: 12),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$symbol${myNet.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      color: myNet >= 0 ? Colors.green : Colors.red,
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final BrandColors brand;
  final String title;
  final Widget? action;

  const _SectionHeader({
    required this.brand,
    required this.title,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 16, 6),
      child: Row(
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              color: brand.inkSoft,
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const Spacer(),
          ?action,
        ],
      ),
    );
  }
}

class _MembersSection extends StatelessWidget {
  final BrandColors brand;
  final List balances;
  final String symbol;
  final String? userId;

  const _MembersSection({
    required this.brand,
    required this.balances,
    required this.symbol,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < balances.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 16,
                  color: brand.divider),
            _MemberRow(
              brand: brand,
              balance: balances[i],
              symbol: symbol,
              isMe: balances[i].uid == userId,
            ),
          ],
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final BrandColors brand;
  final dynamic balance;
  final String symbol;
  final bool isMe;

  const _MemberRow({
    required this.brand,
    required this.balance,
    required this.symbol,
    required this.isMe,
  });

  @override
  Widget build(BuildContext context) {
    final net = balance.net as double;
    final name =
        (balance.displayName as String) + (isMe ? ' (you)' : '');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppActionBlue.color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                (balance.displayName as String)
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(
                  color: AppActionBlue.color,
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    style: TextStyle(
                      color: brand.ink,
                      fontSize: 15,
                      fontWeight:
                          isMe ? FontWeight.w600 : FontWeight.w400,
                    )),
                Text(
                  'Paid $symbol${(balance.totalPaid as double).toStringAsFixed(2)}',
                  style: TextStyle(
                      color: brand.inkSoft, fontSize: 12),
                ),
              ],
            ),
          ),
          Text(
            net == 0
                ? context.t('group.settled')
                : net > 0
                    ? '+$symbol${net.toStringAsFixed(2)}'
                    : '-$symbol${net.abs().toStringAsFixed(2)}',
            style: TextStyle(
              color: net == 0
                  ? brand.inkSoft
                  : net > 0
                      ? Colors.green
                      : Colors.red,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _SettlementSection extends StatelessWidget {
  final BrandColors brand;
  final List settlements;
  final String symbol;
  final String? userId;

  const _SettlementSection({
    required this.brand,
    required this.settlements,
    required this.symbol,
    required this.userId,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (final tx in settlements) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        (tx.fromName as String).substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          color: Colors.red,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                            color: brand.ink, fontSize: 14),
                        children: [
                          TextSpan(
                            text: tx.fromUid == userId
                                ? 'You'
                                : tx.fromName as String,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600),
                          ),
                          const TextSpan(text: ' → '),
                          TextSpan(
                            text: tx.toUid == userId
                                ? 'you'
                                : tx.toName as String,
                          ),
                        ],
                      ),
                    ),
                  ),
                  Text(
                    '$symbol${(tx.amount as double).toStringAsFixed(2)}',
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpensesCard extends StatelessWidget {
  final BrandColors brand;
  final List<GroupExpenseItem> expenses;
  final List<GroupMember> members;
  final String symbol;
  final String? userId;
  final void Function(GroupExpenseItem) onEdit;
  final void Function(GroupExpenseItem) onDelete;

  const _ExpensesCard({
    required this.brand,
    required this.expenses,
    required this.members,
    required this.symbol,
    required this.userId,
    required this.onEdit,
    required this.onDelete,
  });

  String _memberName(String uid) {
    try {
      return members.firstWhere((m) => m.uid == uid).displayName;
    } catch (_) {
      return uid;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (int i = 0; i < expenses.length; i++) ...[
            if (i > 0)
              Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: 16,
                  color: brand.divider),
            _ExpenseRow(
              brand: brand,
              expense: expenses[i],
              paidByName: _memberName(expenses[i].paidBy),
              symbol: symbol,
              userId: userId,
              onEdit: () => onEdit(expenses[i]),
              onDelete: () => onDelete(expenses[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final BrandColors brand;
  final GroupExpenseItem expense;
  final String paidByName;
  final String symbol;
  final String? userId;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExpenseRow({
    required this.brand,
    required this.expense,
    required this.paidByName,
    required this.symbol,
    required this.userId,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isMine = expense.paidBy == userId;
    final dateStr = DateFormat('MMM d').format(expense.date);
    final perPerson = expense.splitBetween.isEmpty
        ? 0.0
        : expense.amount / expense.splitBetween.length;

    return GestureDetector(
      onLongPress: () => _showMenu(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: brand.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Text(
                  _categoryEmoji(expense.category),
                  style: const TextStyle(fontSize: 20),
                ),
              ),
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
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$dateStr · Paid by ${isMine ? 'you' : paidByName}',
                    style: TextStyle(
                        color: brand.inkSoft, fontSize: 12),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$symbol${expense.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (expense.splitBetween.isNotEmpty)
                  Text(
                    '$symbol${perPerson.toStringAsFixed(2)}/each',
                    style: TextStyle(
                        color: brand.inkSoft, fontSize: 11),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMenu(BuildContext context) {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(context);
              onEdit();
            },
            child: Text(context.t('common.edit')),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(context);
              onDelete();
            },
            child: Text(context.t('common.delete')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(context),
          child: Text(context.t('common.cancel')),
        ),
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
