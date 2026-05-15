import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/travel_expense.dart';
import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../widgets/app_toast.dart';
import 'add_edit_travel_group_screen.dart';
import 'add_travel_expense_screen.dart';
import 'settlement_screen.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _blue = Color(0xFF0066CC);
const _hairline = Color(0xFFE0E0E0);
const _parchment = Color(0xFFF5F5F7);
const _inkColor = Color(0xFF1D1D1F);
const _ink48 = Color(0xFF7A7A7A);
const _red = Color(0xFFFF3B30);

const _memberBgs = [
  Color(0xFFE8E8EA), Color(0xFFDCDCE0), Color(0xFFD0D0D5),
  Color(0xFFC4C4CA), Color(0xFFB8B8BF),
];

TextStyle _display(double size, {double tracking = -0.374, double lh = 1.10, Color? color}) =>
    TextStyle(fontSize: size, fontWeight: FontWeight.w600, letterSpacing: tracking, height: lh, color: color ?? _inkColor);

TextStyle _body(double size, {FontWeight weight = FontWeight.w400, Color? color}) =>
    TextStyle(fontSize: size, fontWeight: weight, color: color ?? _inkColor, height: 1.4);

TextStyle _eyebrow({Color? color}) => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.6,
      color: color ?? _ink48,
    );

// ── Screen ────────────────────────────────────────────────────────────────────

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
    _tabCtrl.addListener(() => setState(() {}));
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

  void _showMore() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) =>
                      AddEditTravelGroupScreen(group: widget.group),
                ),
              );
            },
            child: Text(context.t('common.edit')),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () {
              Navigator.pop(ctx);
              _deleteGroup();
            },
            child: Text(context.t('travel.delete')),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: Text(context.t('common.cancel')),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : _parchment;
    final membersAsync = ref.watch(travelGroupMembersProvider(widget.group.id));
    final expensesAsync = ref.watch(travelGroupExpensesProvider(widget.group.id));
    final members = membersAsync.valueOrNull ?? [];
    final expenses = expensesAsync.valueOrNull ?? [];
    final svc = ref.read(travelGroupServiceProvider);
    final settlement = svc.calculateSettlement(members, expenses);
    final dateFmt = DateFormat('MMM d');

    String dateRange = '';
    if (widget.group.startDate != DateTime(0)) {
      final s = dateFmt.format(widget.group.startDate);
      final e = widget.group.endDate != null
          ? dateFmt.format(widget.group.endDate!)
          : null;
      dateRange = e != null ? '$s – $e' : s;
    }

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ── Header ──────────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  _CircleBtn(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(CupertinoIcons.back,
                        size: 18, color: _inkColor),
                  ),
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          widget.group.name,
                          style: _display(17, tracking: -0.4),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (dateRange.isNotEmpty)
                          Text(dateRange,
                              style: _body(12, color: _ink48)),
                      ],
                    ),
                  ),
                  _CircleBtn(
                    onTap: _showMore,
                    child: const Icon(CupertinoIcons.ellipsis,
                        size: 16, color: _inkColor),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Segment control ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _SegmentControl(
              labels: [
                context.t('travel.expenses'),
                context.t('travel.members'),
              ],
              selected: _tabCtrl.index,
              onSelect: (i) => _tabCtrl.animateTo(i),
              isDark: isDark,
            ),
          ),
          const SizedBox(height: 4),

          // ── Body ─────────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _ExpensesTab(
                  group: widget.group,
                  membersAsync: membersAsync,
                  expensesAsync: expensesAsync,
                  settlement: settlement,
                  isDark: isDark,
                ),
                _MembersTab(
                  group: widget.group,
                  membersAsync: membersAsync,
                  isDark: isDark,
                ),
              ],
            ),
          ),
        ],
      ),

      // ── Bottom bar ────────────────────────────────────────────────────────
      bottomNavigationBar: _tabCtrl.index == 0
          ? _BottomBar(
              group: widget.group,
              members: members,
              expenses: expenses,
              settlement: settlement,
              isDark: isDark,
            )
          : null,
    );
  }
}

// ── Segment control ───────────────────────────────────────────────────────────

class _SegmentControl extends StatelessWidget {
  final List<String> labels;
  final int selected;
  final void Function(int) onSelect;
  final bool isDark;

  const _SegmentControl({
    required this.labels,
    required this.selected,
    required this.onSelect,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final trackColor =
        isDark ? const Color(0xFF2C2C2E) : const Color(0xFFE0E0E0);

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: BorderRadius.circular(11),
      ),
      child: Row(
        children: labels.asMap().entries.map((e) {
          final isSelected = e.key == selected;
          final surfaceColor =
              isDark ? const Color(0xFF3A3A3C) : Colors.white;
          return Expanded(
            child: GestureDetector(
              onTap: () => onSelect(e.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 7),
                decoration: BoxDecoration(
                  color: isSelected ? surfaceColor : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          )
                        ]
                      : null,
                ),
                child: Text(
                  e.value,
                  textAlign: TextAlign.center,
                  style: _body(
                    13,
                    weight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: isSelected ? _inkColor : _ink48,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ── Bottom bar ────────────────────────────────────────────────────────────────

class _BottomBar extends StatelessWidget {
  final TravelGroup group;
  final List<TravelGroupMember> members;
  final List<TravelExpense> expenses;
  final dynamic settlement;
  final bool isDark;

  const _BottomBar({
    required this.group,
    required this.members,
    required this.expenses,
    required this.settlement,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final safeBottom = MediaQuery.of(context).padding.bottom;
    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 10, 20, 10 + safeBottom),
      decoration: BoxDecoration(
        color: surface,
        border: Border(top: BorderSide(color: border, width: 0.5)),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: members.isEmpty
                  ? null
                  : () => Navigator.push(
                        context,
                        CupertinoPageRoute(
                          fullscreenDialog: true,
                          builder: (_) => AddTravelExpenseScreen(
                            group: group,
                            members: members,
                          ),
                        ),
                      ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: members.isEmpty
                      ? _blue.withValues(alpha: 0.4)
                      : _blue,
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.add,
                        color: Colors.white, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      context.t('travel.addExpense'),
                      style: _body(15,
                          weight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => SettlementScreen(
                    group: group,
                    settlement: settlement,
                  ),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border.all(color: _blue, width: 1.5),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.checkmark_seal,
                        color: _blue, size: 15),
                    const SizedBox(width: 6),
                    Text(
                      context.t('travel.settle'),
                      style: _body(15,
                          weight: FontWeight.w600, color: _blue),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Expenses Tab ──────────────────────────────────────────────────────────────

class _ExpensesTab extends ConsumerWidget {
  final TravelGroup group;
  final AsyncValue<List<TravelGroupMember>> membersAsync;
  final AsyncValue<List<TravelExpense>> expensesAsync;
  final dynamic settlement;
  final bool isDark;

  const _ExpensesTab({
    required this.group,
    required this.membersAsync,
    required this.expensesAsync,
    required this.settlement,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
              group: group, members: members, isDark: isDark);
        }

        final grouped = <String, List<TravelExpense>>{};
        final dateFmt = DateFormat('MMM d, yyyy');
        for (final e in expenses) {
          grouped.putIfAbsent(dateFmt.format(e.date), () => []).add(e);
        }

        final paidMap = <String, double>{};
        for (final e in expenses) {
          paidMap[e.paidByMemberId] =
              (paidMap[e.paidByMemberId] ?? 0) + e.amount;
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 120),
          children: [
            // Total card
            _TotalCard(
              currency: group.currency,
              totalSpent: totalSpent,
              memberCount: members.length,
              fmt: fmt,
              isDark: isDark,
            ),
            const SizedBox(height: 20),

            // WHO PAID
            if (members.isNotEmpty && totalSpent > 0) ...[
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 10),
                child: Text(
                  context.t('travel.whoPaid').toUpperCase(),
                  style: _eyebrow(),
                ),
              ),
              _Card(
                isDark: isDark,
                child: Column(
                  children: members.asMap().entries.map((entry) {
                    final m = entry.value;
                    final paid = paidMap[m.id] ?? 0;
                    final ratio = totalSpent > 0 ? paid / totalSpent : 0.0;
                    final isLast = entry.key == members.length - 1;
                    return _WhoPaidRow(
                      member: m,
                      paid: paid,
                      ratio: ratio,
                      currency: group.currency,
                      fmt: fmt,
                      isLast: isLast,
                      isDark: isDark,
                    );
                  }).toList(),
                ),
              ),
              const SizedBox(height: 20),
            ],

            // EXPENSES grouped by date
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                context.t('travel.expenses').toUpperCase(),
                style: _eyebrow(),
              ),
            ),
            ...grouped.entries.map((entry) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8),
                        child: Text(entry.key,
                            style: _body(12,
                                weight: FontWeight.w500, color: _ink48)),
                      ),
                      _Card(
                        isDark: isDark,
                        child: Column(
                          children: entry.value.asMap().entries.map((e) {
                            final idx = e.key;
                            final expense = e.value;
                            final paidBy =
                                memberMap[expense.paidByMemberId];
                            final isLast =
                                idx == entry.value.length - 1;
                            return _ExpenseRow(
                              expense: expense,
                              paidByName: paidBy?.name ?? '—',
                              currency: group.currency,
                              fmt: fmt,
                              isLast: isLast,
                              isDark: isDark,
                              onTap: () => Navigator.push(
                                context,
                                CupertinoPageRoute(
                                  fullscreenDialog: true,
                                  builder: (_) => AddTravelExpenseScreen(
                                    group: group,
                                    members:
                                        membersAsync.valueOrNull ?? [],
                                    expense: expense,
                                  ),
                                ),
                              ),
                              onDelete: () =>
                                  _confirmDelete(context, ref, expense),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                )),
          ],
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    TravelExpense expense,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('travel.deleteExpense')),
        content: Text(context.t('travel.deleteExpenseConfirm')),
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
  }
}

// ── Members Tab ───────────────────────────────────────────────────────────────

class _MembersTab extends ConsumerWidget {
  final TravelGroup group;
  final AsyncValue<List<TravelGroupMember>> membersAsync;
  final bool isDark;

  const _MembersTab({
    required this.group,
    required this.membersAsync,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return membersAsync.when(
      loading: () => const Center(child: CupertinoActivityIndicator()),
      error: (e, _) => Center(child: Text('${context.t('common.error')}: $e')),
      data: (members) => ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
        children: [
          _Card(
            isDark: isDark,
            child: Column(
              children: [
                ...members.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final m = entry.value;
                  final isOwner =
                      m.userId != null && m.userId == group.ownerId;
                  final isLast = idx == members.length - 1 && !true;
                  return Column(
                    children: [
                      _MemberRow(
                        member: m,
                        isOwner: isOwner,
                        index: idx,
                        isDark: isDark,
                        onDelete: isOwner
                            ? null
                            : () => _confirmRemove(context, ref, m),
                      ),
                      if (!isLast)
                        Divider(
                          height: 1,
                          color: isDark
                              ? const Color(0xFF3A3A3C)
                              : _hairline,
                          indent: 20,
                          endIndent: 20,
                        ),
                    ],
                  );
                }),
                // Divider before Add member
                Divider(
                  height: 1,
                  color: isDark ? const Color(0xFF3A3A3C) : _hairline,
                  indent: 20,
                  endIndent: 20,
                ),
                // Add member row
                GestureDetector(
                  onTap: () => _showAddMember(context, ref, members),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: _blue.withValues(alpha: 0.10),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(CupertinoIcons.add,
                              color: _blue, size: 16),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          context.t('travel.addMember'),
                          style: _body(15,
                              weight: FontWeight.w500, color: _blue),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    TravelGroupMember m,
  ) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(context.t('travel.removeMember')),
        content: Text(context.t('travel.removeMemberConfirm')),
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
      await ref
          .read(travelGroupServiceProvider)
          .removeMember(group.id, group, m.id, m.userId);
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
  }

  void _showAddMember(
    BuildContext context,
    WidgetRef ref,
    List<TravelGroupMember> existing,
  ) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => _AddMemberSheet(
        group: group,
        isDark: isDark,
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

// ── Reusable widgets ──────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final bool isDark;

  const _Card({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: child,
      ),
    );
  }
}

class _CircleBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _CircleBtn({required this.child, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : _inkColor.withValues(alpha: 0.06),
          shape: BoxShape.circle,
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _TotalCard extends StatelessWidget {
  final String currency;
  final double totalSpent;
  final int memberCount;
  final NumberFormat fmt;
  final bool isDark;

  const _TotalCard({
    required this.currency,
    required this.totalSpent,
    required this.memberCount,
    required this.fmt,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;
    final perPerson =
        memberCount > 0 ? totalSpent / memberCount : totalSpent;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.t('travel.totalSpent').toUpperCase(),
            style: _eyebrow(color: _ink48),
          ),
          const SizedBox(height: 6),
          Text(
            '$currency ${fmt.format(totalSpent)}',
            style: _display(34, tracking: -1.0),
          ),
          if (memberCount > 1) ...[
            const SizedBox(height: 10),
            Divider(color: border, height: 1),
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '$currency ${fmt.format(perPerson)}',
                  style: _body(14,
                      weight: FontWeight.w500, color: _ink48),
                ),
                Text(
                  ' · ${context.t('travel.perPerson')}',
                  style: _body(14, color: _ink48),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _WhoPaidRow extends StatelessWidget {
  final TravelGroupMember member;
  final double paid;
  final double ratio;
  final String currency;
  final NumberFormat fmt;
  final bool isLast;
  final bool isDark;

  const _WhoPaidRow({
    required this.member,
    required this.paid,
    required this.ratio,
    required this.currency,
    required this.fmt,
    required this.isLast,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final divider =
        isDark ? const Color(0xFF3A3A3C) : _hairline;
    final initial =
        member.name.isNotEmpty ? member.name[0].toUpperCase() : '?';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE8E8EA),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(initial,
                          style: _body(13,
                              weight: FontWeight.w700,
                              color: _inkColor)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(member.name,
                        style: _body(14, weight: FontWeight.w500)),
                  ),
                  Text(
                    '$currency ${fmt.format(paid)}',
                    style: _body(14, weight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: ratio.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: _blue.withValues(alpha: 0.10),
                  valueColor: const AlwaysStoppedAnimation(_blue),
                ),
              ),
            ],
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: divider, indent: 20, endIndent: 20),
      ],
    );
  }
}

class _ExpenseRow extends StatelessWidget {
  final TravelExpense expense;
  final String paidByName;
  final String currency;
  final NumberFormat fmt;
  final bool isLast;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ExpenseRow({
    required this.expense,
    required this.paidByName,
    required this.currency,
    required this.fmt,
    required this.isLast,
    required this.isDark,
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

  static const _categoryColors = <String, Color>{
    'food': Color(0xFFFF9500),
    'transport': Color(0xFF3478F6),
    'accommodation': Color(0xFF5856D6),
    'activities': Color(0xFFFF2D55),
    'shopping': Color(0xFF34C759),
    'general': Color(0xFF8E8E93),
  };

  @override
  Widget build(BuildContext context) {
    final divider =
        isDark ? const Color(0xFF3A3A3C) : _hairline;
    final catColor =
        _categoryColors[expense.category] ?? const Color(0xFF8E8E93);
    final dateFmt = DateFormat('MMM d');

    return Column(
      children: [
        Dismissible(
          key: Key(expense.id),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            color: _red.withValues(alpha: 0.08),
            child: const Icon(CupertinoIcons.delete, color: _red, size: 20),
          ),
          confirmDismiss: (_) async {
            onDelete();
            return false;
          },
          child: GestureDetector(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: catColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Icon(
                      _categoryIcons[expense.category] ??
                          CupertinoIcons.square_grid_2x2_fill,
                      color: catColor,
                      size: 17,
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
                          style: _body(15, weight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${context.t('travel.paid')} by $paidByName · ${dateFmt.format(expense.date)}',
                          style: _body(12, color: _ink48),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '$currency ${fmt.format(expense.amount)}',
                    style: _body(15, weight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (!isLast)
          Divider(height: 1, color: divider, indent: 70, endIndent: 20),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  final TravelGroupMember member;
  final bool isOwner;
  final int index;
  final bool isDark;
  final VoidCallback? onDelete;

  const _MemberRow({
    required this.member,
    required this.isOwner,
    required this.index,
    required this.isDark,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final bg = _memberBgs[index % _memberBgs.length];
    final initial =
        member.name.isNotEmpty ? member.name[0].toUpperCase() : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Center(
              child: Text(initial,
                  style: _body(16,
                      weight: FontWeight.w700, color: _inkColor)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(member.name,
                        style: _body(15, weight: FontWeight.w500)),
                    if (isOwner) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _blue.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text('Owner',
                            style: _eyebrow(color: _blue)),
                      ),
                    ],
                  ],
                ),
                if (member.email != null && member.email!.isNotEmpty)
                  Text(member.email!,
                      style: _body(12, color: _ink48)),
              ],
            ),
          ),
          if (onDelete != null)
            GestureDetector(
              onTap: onDelete,
              child: const Icon(CupertinoIcons.minus_circle,
                  color: _ink48, size: 22),
            ),
        ],
      ),
    );
  }
}

class _EmptyExpenses extends StatelessWidget {
  final TravelGroup group;
  final List<TravelGroupMember> members;
  final bool isDark;

  const _EmptyExpenses({
    required this.group,
    required this.members,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: _blue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(CupertinoIcons.doc_text,
                  color: _blue, size: 34),
            ),
            const SizedBox(height: 18),
            Text(context.t('travel.noExpenses'),
                style: _display(20, tracking: -0.4),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(context.t('travel.noExpensesHint'),
                style: _body(15, color: _ink48),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

// ── Add member sheet ──────────────────────────────────────────────────────────

class _AddMemberSheet extends StatefulWidget {
  final TravelGroup group;
  final bool isDark;
  final Future<void> Function(String name, String? email) onAdd;

  const _AddMemberSheet({
    required this.group,
    required this.isDark,
    required this.onAdd,
  });

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
    final surface =
        widget.isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final bg =
        widget.isDark ? const Color(0xFF1C1C1E) : _parchment;
    final border =
        widget.isDark ? const Color(0xFF3A3A3C) : _hairline;

    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      decoration: BoxDecoration(
        color: surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pull indicator
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Text(context.t('travel.addMember'),
                  style: _display(22, tracking: -0.4)),
              const SizedBox(height: 20),

              // Name field
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border, width: 0.5),
                ),
                child: TextField(
                  controller: _nameCtrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    hintText: context.t('travel.memberName'),
                    border: InputBorder.none,
                    hintStyle: _body(16, color: _ink48),
                  ),
                  style: _body(16),
                ),
              ),
              const SizedBox(height: 10),

              // Email field
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 4),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: border, width: 0.5),
                ),
                child: TextField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    hintText: context.t('travel.memberEmail'),
                    border: InputBorder.none,
                    hintStyle: _body(16, color: _ink48),
                  ),
                  style: _body(16),
                ),
              ),
              const SizedBox(height: 20),

              // Add button
              GestureDetector(
                onTap: _saving
                    ? null
                    : () async {
                        final name = _nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        setState(() => _saving = true);
                        await widget.onAdd(
                            name, _emailCtrl.text.trim());
                        if (mounted) setState(() => _saving = false);
                      },
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    color: _saving
                        ? _blue.withValues(alpha: 0.5)
                        : _blue,
                    borderRadius: BorderRadius.circular(9999),
                  ),
                  child: Center(
                    child: _saving
                        ? const CupertinoActivityIndicator(
                            color: Colors.white)
                        : Text(
                            context.t('common.add'),
                            style: _body(16,
                                weight: FontWeight.w600,
                                color: Colors.white),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
