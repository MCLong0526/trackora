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
import '../../widgets/personal_group_toggle.dart';
import 'add_group_expense_screen.dart';
import 'create_group_screen.dart';
import 'group_invite_screen.dart';
import 'group_receipt_screen.dart';
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
                GestureDetector(
                  onTap: () =>
                      showGroupMenu(context, ref, activeGroup, user?.uid),
                  child: GroupAvatarPill(group: activeGroup, userId: user?.uid),
                ),
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
                : GroupDashboardContent(
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

class GroupAvatarPill extends StatelessWidget {
  final ExpenseGroup? group;
  final String? userId;

  const GroupAvatarPill({super.key, required this.group, required this.userId});

  @override
  Widget build(BuildContext context) {
    final me = group?.members.where((m) => m.uid == userId).firstOrNull;
    final partner = group?.members.where((m) => m.uid != userId).firstOrNull;
    final myInitial = (me?.displayName.substring(0, 1) ?? 'Y').toUpperCase();
    final partnerInitial = (partner?.displayName.substring(0, 1) ?? 'J')
        .toUpperCase();

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
              child: const Icon(
                CupertinoIcons.person_2_fill,
                color: Color(0xFF1A6CFF),
                size: 28,
              ),
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
                      builder: (_) => const CreateGroupScreen(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                _PillButton(
                  label: context.t('group.joinGroup'),
                  icon: CupertinoIcons.arrow_right_circle,
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(builder: (_) => const JoinGroupScreen()),
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

class GroupDashboardContent extends ConsumerWidget {
  final BrandColors brand;
  final ExpenseGroup? group;
  final String symbol;
  final String? userId;

  const GroupDashboardContent({
    super.key,
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
    final myBalance = balances.cast<dynamic>().firstWhere(
      (b) => b.uid == userId,
      orElse: () => null,
    );
    final partnerBalance = balances.cast<dynamic>().firstWhere(
      (b) => b.uid != userId,
      orElse: () => null,
    );
    final myNet = myBalance?.net as double? ?? 0;
    final totalSpent = expenses.fold<double>(0, (s, e) => s + e.amount);

    final me = group!.members.where((m) => m.uid == userId).firstOrNull;
    final partner = group!.members.where((m) => m.uid != userId).firstOrNull;
    final myInitial = (me?.displayName.substring(0, 1) ?? 'Y').toUpperCase();
    final partnerInitial = (partner?.displayName.substring(0, 1) ?? 'J')
        .toUpperCase();
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
                    horizontal: 14,
                    vertical: 10,
                  ),
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
                      horizontal: 14,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A6CFF),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.plus,
                          color: Colors.white,
                          size: 14,
                        ),
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
                  onTap: () => showGroupReceiptPicker(context, group!),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          CupertinoIcons.doc_text,
                          color: brand.inkSoft,
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Generate Receipt',
                          style: TextStyle(
                            color: brand.ink,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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
                  Icon(
                    CupertinoIcons.square_list,
                    color: brand.inkSoft,
                    size: 32,
                  ),
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
                  Icon(
                    CupertinoIcons.person_badge_plus,
                    color: Color(0xFF1A6CFF),
                    size: 16,
                  ),
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

  String _memberInitial(String uid) =>
      _memberName(uid).substring(0, 1).toUpperCase();

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
            child: Icon(
              _categoryIcon(expense.category),
              color: catColor,
              size: 20,
            ),
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
                  style: TextStyle(color: brand.inkSoft, fontSize: 12),
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

// ── Group menu ───────────────────────────────────────────────────────────────

void showGroupMenu(
  BuildContext context,
  WidgetRef ref,
  ExpenseGroup? group,
  String? userId,
) {
  if (group == null) return;
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (_) => _GroupMenuSheet(group: group, userId: userId),
  );
}

void showGroupReceiptPicker(BuildContext context, ExpenseGroup group) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ReceiptPickerSheet(group: group),
  );
}

class _ReceiptPickerSheet extends StatefulWidget {
  final ExpenseGroup group;

  const _ReceiptPickerSheet({required this.group});

  @override
  State<_ReceiptPickerSheet> createState() => _ReceiptPickerSheetState();
}

class _ReceiptPickerSheetState extends State<_ReceiptPickerSheet> {
  GroupReceiptPeriod _period = GroupReceiptPeriod.month;
  DateTime _selectedDate = DateTime.now();

  DateTime get _selectedMonth =>
      DateTime(_selectedDate.year, _selectedDate.month);

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickMonth() async {
    final now = DateTime.now();
    final months = List.generate(24, (i) => DateTime(now.year, now.month - i));
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      backgroundColor: context.brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: ListView.separated(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          itemBuilder: (_, i) {
            final month = months[i];
            final selected =
                month.year == _selectedMonth.year &&
                month.month == _selectedMonth.month;
            return ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              tileColor: selected ? const Color(0xFFE4ECFE) : Colors.white,
              title: Text(
                DateFormat('MMMM yyyy').format(month),
                style: TextStyle(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              trailing: selected
                  ? const Icon(
                      CupertinoIcons.check_mark_circled_solid,
                      color: Color(0xFF1A6CFF),
                    )
                  : null,
              onTap: () => Navigator.pop(ctx, month),
            );
          },
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemCount: months.length,
        ),
      ),
    );
    if (picked != null && mounted) {
      setState(() => _selectedDate = picked);
    }
  }

  void _generate() {
    Navigator.pop(context);
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => GroupReceiptScreen(
          group: widget.group,
          period: _period,
          selectedDate: _period == GroupReceiptPeriod.day
              ? _selectedDate
              : _selectedMonth,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDaily = _period == GroupReceiptPeriod.day;
    return Container(
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFD1D1D6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Generate receipt',
              style: TextStyle(
                color: brand.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Choose a daily or monthly group receipt.',
              style: TextStyle(color: brand.inkSoft, fontSize: 14),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  _PeriodTab(
                    label: 'Daily',
                    selected: isDaily,
                    onTap: () =>
                        setState(() => _period = GroupReceiptPeriod.day),
                  ),
                  _PeriodTab(
                    label: 'Month',
                    selected: !isDaily,
                    onTap: () =>
                        setState(() => _period = GroupReceiptPeriod.month),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: isDaily ? _pickDate : _pickMonth,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 15,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: const Color(0xFFE4ECFE),
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: const Icon(
                        CupertinoIcons.calendar,
                        color: Color(0xFF1A6CFF),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isDaily ? 'Receipt date' : 'Receipt month',
                            style: TextStyle(
                              color: brand.inkSoft,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isDaily
                                ? DateFormat(
                                    'd MMMM yyyy',
                                  ).format(_selectedDate)
                                : DateFormat(
                                    'MMMM yyyy',
                                  ).format(_selectedMonth),
                            style: TextStyle(
                              color: brand.ink,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      CupertinoIcons.chevron_down,
                      color: brand.inkSoft,
                      size: 16,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 15),
                color: const Color(0xFF1A6CFF),
                borderRadius: BorderRadius.circular(18),
                onPressed: _generate,
                child: const Text(
                  'Generate receipt',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PeriodTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _PeriodTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(13),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              color: selected
                  ? const Color(0xFF0B0B0F)
                  : const Color(0xFF8E8E96),
              fontSize: 15,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _GroupMenuSheet extends ConsumerWidget {
  final ExpenseGroup group;
  final String? userId;
  const _GroupMenuSheet({required this.group, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final me = group.members.where((m) => m.uid == userId).firstOrNull;
    final partner = group.members.where((m) => m.uid != userId).firstOrNull;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(bottom: 16),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: brand.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Group name
          Text(
            group.name,
            style: TextStyle(
              color: brand.ink,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${group.members.length} member${group.members.length == 1 ? '' : 's'}',
            style: TextStyle(color: brand.inkSoft, fontSize: 13),
          ),
          const SizedBox(height: 20),
          // Member list
          if (me != null) _MemberRow(member: me, isYou: true),
          if (partner != null) ...[
            const SizedBox(height: 8),
            _MemberRow(member: partner, isYou: false),
          ],
          const SizedBox(height: 20),
          // Leave group button
          SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 14),
              color: const Color(0xFFFFEEEE),
              borderRadius: BorderRadius.circular(14),
              onPressed: () async {
                // Show dialog FIRST while sheet context is still valid
                final confirmed = await showCupertinoDialog<bool>(
                  context: context,
                  builder: (dialogCtx) => CupertinoAlertDialog(
                    title: const Text('Leave group?'),
                    content: const Text(
                      'You will lose access to this group\'s expenses.',
                    ),
                    actions: [
                      CupertinoDialogAction(
                        isDestructiveAction: true,
                        onPressed: () =>
                            Navigator.pop(dialogCtx, true),
                        child: const Text('Leave'),
                      ),
                      CupertinoDialogAction(
                        onPressed: () =>
                            Navigator.pop(dialogCtx, false),
                        child: const Text('Cancel'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && userId != null) {
                  // Close the bottom sheet after confirmation
                  if (context.mounted) Navigator.pop(context);
                  try {
                    final service = ref.read(expenseGroupServiceProvider);
                    await service.leaveGroup(group.id, userId!);
                    ref.read(activeGroupIdProvider.notifier).state = null;
                    ref.read(homeModeProvider.notifier).state =
                        HomeMode.personal;
                    if (context.mounted) {
                      AppToast.show(context, 'Left group');
                    }
                  } catch (e) {
                    if (context.mounted) {
                      AppToast.show(context, 'Failed to leave group');
                    }
                  }
                }
              },
              child: const Text(
                'Leave group',
                style: TextStyle(
                  color: Color(0xFFD93025),
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  final GroupMember member;
  final bool isYou;
  const _MemberRow({required this.member, required this.isYou});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: isYou ? const Color(0xFFEAE3F8) : const Color(0xFFD7F4E5),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              member.displayName.substring(0, 1).toUpperCase(),
              style: TextStyle(
                color: isYou
                    ? const Color(0xFF5A4AAB)
                    : const Color(0xFF1FBE71),
                fontSize: 16,
                fontWeight: FontWeight.w700,
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
                    member.displayName,
                    style: TextStyle(
                      color: brand.ink,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isYou) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAE3F8),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: const Text(
                        'You',
                        style: TextStyle(
                          color: Color(0xFF5A4AAB),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              Text(
                'Joined ${DateFormat('MMM d, yyyy').format(member.joinedAt)}',
                style: TextStyle(color: brand.inkSoft, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Pill button ───────────────────────────────────────────────────────────────

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
