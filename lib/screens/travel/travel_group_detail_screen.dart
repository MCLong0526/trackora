import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/travel_expense.dart';
import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'add_edit_travel_group_screen.dart';
import 'add_travel_expense_screen.dart';
import 'settlement_screen.dart';

class TravelGroupDetailScreen extends ConsumerStatefulWidget {
  final TravelGroup group;
  const TravelGroupDetailScreen({super.key, required this.group});

  @override
  ConsumerState<TravelGroupDetailScreen> createState() =>
      _TravelGroupDetailScreenState();
}

class _TravelGroupDetailScreenState
    extends ConsumerState<TravelGroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _deleteGroup() async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('travel.delete')),
        content: Text(context.t('travel.deleteConfirm')),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.t('common.delete')),
          ),
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.t('common.cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(travelGroupServiceProvider).deleteGroup(widget.group.id);
      if (mounted) {
        AppToast.show(
          context,
          context.t('travel.deleted'),
          type: AppToastType.success,
          icon: CupertinoIcons.checkmark_circle_fill,
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(
          context,
          context.t('travel.saveFailed'),
          type: AppToastType.error,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final membersAsync = ref.watch(travelGroupMembersProvider(widget.group.id));
    final expensesAsync =
        ref.watch(travelGroupExpensesProvider(widget.group.id));

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(widget.group.name),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.pencil),
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) =>
                    AddEditTravelGroupScreen(group: widget.group),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(CupertinoIcons.ellipsis_circle),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'delete',
                child: Text(
                  context.t('travel.delete'),
                  style: const TextStyle(color: Color(0xFFFF3B30)),
                ),
              ),
            ],
            onSelected: (v) {
              if (v == 'delete') _deleteGroup();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: context.t('travel.expenses')),
            Tab(text: context.t('travel.members')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // Tab 1: Expenses
          _ExpensesTab(
            group: widget.group,
            membersAsync: membersAsync,
            expensesAsync: expensesAsync,
          ),
          // Tab 2: Members
          _MembersTab(
            group: widget.group,
            membersAsync: membersAsync,
          ),
        ],
      ),
      floatingActionButton: expensesAsync.whenOrNull(
        data: (expenses) => membersAsync.whenOrNull(
          data: (members) => _buildFab(context, expenses, members),
        ),
      ),
    );
  }

  Widget _buildFab(
    BuildContext context,
    List<TravelExpense> expenses,
    List<TravelGroupMember> members,
  ) {
    final svc = ref.read(travelGroupServiceProvider);
    final settlement = svc.calculateSettlement(members, expenses);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Settle Up button
        FloatingActionButton.extended(
          heroTag: 'settle',
          onPressed: () => Navigator.push(
            context,
            CupertinoPageRoute(
              builder: (_) => SettlementScreen(
                group: widget.group,
                settlement: settlement,
              ),
            ),
          ),
          backgroundColor: const Color(0xFF34C759),
          icon: const Icon(CupertinoIcons.checkmark_seal, color: Colors.white),
          label: Text(
            context.t('travel.settle'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        const SizedBox(height: 10),
        // Add expense button
        FloatingActionButton(
          heroTag: 'add_expense',
          onPressed: members.isEmpty
              ? null
              : () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => AddTravelExpenseScreen(
                        group: widget.group,
                        members: members,
                      ),
                    ),
                  ),
          backgroundColor: const Color(0xFF3478F6),
          child: const Icon(CupertinoIcons.add, color: Colors.white),
        ),
      ],
    );
  }
}

// ── Expenses Tab ─────────────────────────────────────────────────────────────

class _ExpensesTab extends ConsumerWidget {
  final TravelGroup group;
  final AsyncValue<List<TravelGroupMember>> membersAsync;
  final AsyncValue<List<TravelExpense>> expensesAsync;

  const _ExpensesTab({
    required this.group,
    required this.membersAsync,
    required this.expensesAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;

    return expensesAsync.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => Center(child: Text('${context.t('common.error')}: $e')),
      data: (expenses) {
        final members = membersAsync.valueOrNull ?? [];
        final memberMap = {for (final m in members) m.id: m};
        final fmt = NumberFormat('#,##0.00');
        final totalSpent =
            expenses.fold<double>(0, (sum, e) => sum + e.amount);

        if (expenses.isEmpty) {
          return _EmptyExpenses(
            group: group,
            members: members,
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: [
            // Summary card
            _SummaryCard(
              currency: group.currency,
              totalSpent: totalSpent,
              expenseCount: expenses.length,
              fmt: fmt,
              brand: brand,
            ),
            const SizedBox(height: 20),

            // Expenses list
            const _SectionHeader('EXPENSES'),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: expenses.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final expense = entry.value;
                  final paidBy = memberMap[expense.paidByMemberId];
                  return Column(
                    children: [
                      _ExpenseTile(
                        expense: expense,
                        paidByName: paidBy?.name ?? '—',
                        currency: group.currency,
                        fmt: fmt,
                        brand: brand,
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) => AddTravelExpenseScreen(
                              group: group,
                              members: members,
                              expense: expense,
                            ),
                          ),
                        ),
                        onDelete: () async {
                          final confirmed = await showCupertinoDialog<bool>(
                            context: context,
                            builder: (ctx) => CupertinoAlertDialog(
                              title: Text(
                                  context.t('travel.deleteExpense')),
                              content: Text(
                                  context.t('travel.deleteExpenseConfirm')),
                              actions: [
                                CupertinoDialogAction(
                                  isDestructiveAction: true,
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: Text(context.t('common.delete')),
                                ),
                                CupertinoDialogAction(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: Text(context.t('common.cancel')),
                                ),
                              ],
                            ),
                          );
                          if (confirmed != true) return;
                          try {
                            await ref
                                .read(travelGroupServiceProvider)
                                .deleteExpense(group.id, expense.id);
                            if (context.mounted) {
                              AppToast.show(
                                context,
                                context.t('travel.expenseDeleted'),
                                type: AppToastType.success,
                              );
                            }
                          } catch (_) {
                            if (context.mounted) {
                              AppToast.show(
                                context,
                                context.t('travel.saveFailed'),
                                type: AppToastType.error,
                              );
                            }
                          }
                        },
                      ),
                      if (idx < expenses.length - 1)
                        Divider(
                          height: 1,
                          color: brand.divider,
                          indent: 16,
                          endIndent: 16,
                        ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String currency;
  final double totalSpent;
  final int expenseCount;
  final NumberFormat fmt;
  final BrandColors brand;

  const _SummaryCard({
    required this.currency,
    required this.totalSpent,
    required this.expenseCount,
    required this.fmt,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.t('travel.totalSpent'),
                  style: TextStyle(
                    fontSize: 13,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '$currency ${fmt.format(totalSpent)}',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                    letterSpacing: -0.6,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: brand.sky,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$expenseCount ${context.t('common.entries')}',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF3478F6),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  final TravelExpense expense;
  final String paidByName;
  final String currency;
  final NumberFormat fmt;
  final BrandColors brand;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ExpenseTile({
    required this.expense,
    required this.paidByName,
    required this.currency,
    required this.fmt,
    required this.brand,
    required this.onTap,
    required this.onDelete,
  });

  static const _categoryIcons = <String, IconData>{
    'food': CupertinoIcons.cart_fill,
    'transport': CupertinoIcons.car_fill,
    'accommodation': CupertinoIcons.house_fill,
    'activities': CupertinoIcons.star_fill,
    'shopping': CupertinoIcons.bag_fill,
    'general': CupertinoIcons.square_grid_2x2_fill,
  };

  static const _categoryColors = {
    'food': Color(0xFFFF9500),
    'transport': Color(0xFF3478F6),
    'accommodation': Color(0xFF5856D6),
    'activities': Color(0xFFFF2D55),
    'shopping': Color(0xFF34C759),
    'general': Color(0xFF8E8E93),
  };

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM d');
    final catColor = _categoryColors[expense.category] ?? const Color(0xFF8E8E93);

    return Dismissible(
      key: Key(expense.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B30).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(0),
        ),
        child: const Icon(CupertinoIcons.delete, color: Color(0xFFFF3B30)),
      ),
      confirmDismiss: (_) async {
        onDelete();
        return false;
      },
      child: GestureDetector(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: catColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _categoryIcons[expense.category] ??
                      CupertinoIcons.circle_grid_hex_fill,
                  color: catColor,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      expense.description.isNotEmpty
                          ? expense.description
                          : expense.category,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: brand.ink,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${context.t('travel.paid')} by $paidByName · ${dateFormat.format(expense.date)} · ${expense.splitAmong.length} people',
                      style: TextStyle(fontSize: 12, color: brand.inkSoft),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$currency ${fmt.format(expense.amount)}',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyExpenses extends StatelessWidget {
  final TravelGroup group;
  final List<TravelGroupMember> members;

  const _EmptyExpenses({required this.group, required this.members});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 70,
              height: 70,
              decoration: BoxDecoration(
                color: brand.butter,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                CupertinoIcons.doc_text,
                color: Color(0xFFFF9500),
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.t('travel.noExpenses'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: brand.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('travel.noExpensesHint'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: brand.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Members Tab ──────────────────────────────────────────────────────────────

class _MembersTab extends ConsumerWidget {
  final TravelGroup group;
  final AsyncValue<List<TravelGroupMember>> membersAsync;

  const _MembersTab({required this.group, required this.membersAsync});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;

    return membersAsync.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => Center(child: Text('${context.t('common.error')}: $e')),
      data: (members) {
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Container(
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                children: [
                  ...members.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final m = entry.value;
                    return Column(
                      children: [
                        _MemberTile(
                          member: m,
                          group: group,
                          brand: brand,
                          onDelete: () async {
                            final confirmed =
                                await showCupertinoDialog<bool>(
                              context: context,
                              builder: (ctx) => CupertinoAlertDialog(
                                title: Text(
                                    context.t('travel.removeMember')),
                                content: Text(
                                    context.t('travel.removeMemberConfirm')),
                                actions: [
                                  CupertinoDialogAction(
                                    isDestructiveAction: true,
                                    onPressed: () =>
                                        Navigator.pop(ctx, true),
                                    child:
                                        Text(context.t('common.delete')),
                                  ),
                                  CupertinoDialogAction(
                                    onPressed: () =>
                                        Navigator.pop(ctx, false),
                                    child:
                                        Text(context.t('common.cancel')),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed != true) return;
                            try {
                              await ref
                                  .read(travelGroupServiceProvider)
                                  .removeMember(
                                    group.id,
                                    group,
                                    m.id,
                                    m.userId,
                                  );
                              if (context.mounted) {
                                AppToast.show(
                                  context,
                                  context.t('travel.memberRemoved'),
                                  type: AppToastType.success,
                                );
                              }
                            } catch (_) {
                              if (context.mounted) {
                                AppToast.show(
                                  context,
                                  context.t('travel.saveFailed'),
                                  type: AppToastType.error,
                                );
                              }
                            }
                          },
                        ),
                        if (idx < members.length - 1)
                          Divider(
                            height: 1,
                            color: brand.divider,
                            indent: 16,
                            endIndent: 16,
                          ),
                      ],
                    );
                  }),
                  // Add member row
                  Divider(
                    height: 1,
                    color: brand.divider,
                    indent: 16,
                    endIndent: 16,
                  ),
                  InkWell(
                    onTap: () => _showAddMemberSheet(context, ref, members),
                    borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3478F6)
                                  .withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              CupertinoIcons.add,
                              color: Color(0xFF3478F6),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            context.t('travel.addMember'),
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF3478F6),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  void _showAddMemberSheet(
    BuildContext context,
    WidgetRef ref,
    List<TravelGroupMember> existingMembers,
  ) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => _AddMemberSheet(
        group: group,
        onAdd: (name, email) async {
          try {
            await ref.read(travelGroupServiceProvider).addMember(
              groupId: group.id,
              group: group,
              name: name,
              email: email?.isEmpty == true ? null : email,
            );
            if (ctx.mounted) {
              Navigator.pop(ctx);
              AppToast.show(
                context,
                context.t('travel.memberAdded'),
                type: AppToastType.success,
                icon: CupertinoIcons.checkmark_circle_fill,
              );
            }
          } catch (_) {
            if (ctx.mounted) {
              AppToast.show(
                context,
                context.t('travel.saveFailed'),
                type: AppToastType.error,
              );
            }
          }
        },
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final TravelGroupMember member;
  final TravelGroup group;
  final BrandColors brand;
  final VoidCallback onDelete;

  const _MemberTile({
    required this.member,
    required this.group,
    required this.brand,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isOwner =
        member.userId != null && member.userId == group.ownerId;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: brand.lilac,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                member.name.isNotEmpty
                    ? member.name[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF5856D6),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      member.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: brand.ink,
                      ),
                    ),
                    if (isOwner) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF3478F6)
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text(
                          'Owner',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF3478F6),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (member.email != null && member.email!.isNotEmpty)
                  Text(
                    member.email!,
                    style: TextStyle(fontSize: 12, color: brand.inkSoft),
                  ),
              ],
            ),
          ),
          if (!isOwner)
            IconButton(
              icon: Icon(
                CupertinoIcons.minus_circle,
                color: brand.inkSoft,
                size: 22,
              ),
              onPressed: onDelete,
            ),
        ],
      ),
    );
  }
}

class _AddMemberSheet extends StatefulWidget {
  final TravelGroup group;
  final Future<void> Function(String name, String? email) onAdd;

  const _AddMemberSheet({required this.group, required this.onAdd});

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: brand.divider,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                context.t('travel.addMember'),
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                ),
              ),
              const SizedBox(height: 16),
              _InputField(
                ctrl: _nameCtrl,
                hint: context.t('travel.memberName'),
                brand: brand,
                autofocus: true,
              ),
              const SizedBox(height: 10),
              _InputField(
                ctrl: _emailCtrl,
                hint: context.t('travel.memberEmail'),
                brand: brand,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: CupertinoButton.filled(
                  borderRadius: BorderRadius.circular(14),
                  onPressed: _saving
                      ? null
                      : () async {
                          final name = _nameCtrl.text.trim();
                          if (name.isEmpty) return;
                          setState(() => _saving = true);
                          await widget.onAdd(
                            name,
                            _emailCtrl.text.trim(),
                          );
                          if (mounted) setState(() => _saving = false);
                        },
                  child: _saving
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : Text(context.t('common.add')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController ctrl;
  final String hint;
  final BrandColors brand;
  final bool autofocus;
  final TextInputType? keyboardType;

  const _InputField({
    required this.ctrl,
    required this.hint,
    required this.brand,
    this.autofocus = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : const Color(0xFFF2F2F7),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: ctrl,
        autofocus: autofocus,
        keyboardType: keyboardType,
        textCapitalization: TextCapitalization.words,
        decoration: InputDecoration(
          hintText: hint,
          border: InputBorder.none,
          hintStyle: TextStyle(color: brand.inkSoft),
        ),
        style: TextStyle(color: brand.ink, fontSize: 16),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFF8E8E93),
        letterSpacing: 0.8,
      ),
    );
  }
}
