import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../repositories/firebase_expense_group_repository.dart';
import '../../repositories/local_expense_group_repository.dart';
import '../../services/i18n.dart';
import '../../services/sync_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/exchange_rate_sheet.dart';
import '../../widgets/fading_edge_list.dart';
import '../../widgets/personal_group_toggle.dart';
import '../../widgets/profile_avatar_button.dart';
import 'add_group_expense_screen.dart';
import 'create_group_screen.dart';
import 'group_invite_screen.dart';
import 'group_receipt_screen.dart';
import 'join_group_screen.dart';

class GroupDashboardScreen extends ConsumerStatefulWidget {
  const GroupDashboardScreen({super.key});

  @override
  ConsumerState<GroupDashboardScreen> createState() => _GroupDashboardScreenState();
}

class _GroupDashboardScreenState extends ConsumerState<GroupDashboardScreen> {
  double _scrollOffset = 0.0;

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollUpdateNotification || n is ScrollStartNotification) {
      final newOffset = n.metrics.pixels.clamp(0.0, 80.0);
      if ((newOffset - _scrollOffset).abs() > 0.5) {
        setState(() => _scrollOffset = newOffset);
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final groupsAsync = ref.watch(myGroupsProvider);
    final activeGroupId = ref.watch(activeGroupIdProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '';
    final user = ref.watch(authStateProvider).valueOrNull;

    final groups = groupsAsync.valueOrNull ?? const [];
    final visible = ref.watch(balanceVisibleProvider);

    if (activeGroupId == null && groups.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeGroupIdProvider.notifier).state = groups.first.id;
      });
    }

    final activeGroup = groups.cast<ExpenseGroup?>().firstWhere(
      (g) => g?.id == activeGroupId,
      orElse: () => groups.isNotEmpty ? groups.first : null,
    );

    final headerOpacity = (1.0 - _scrollOffset / 60.0).clamp(0.0, 1.0);

    return SafeArea(
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header (fades on scroll) ──────────────────────────
            Opacity(
              opacity: headerOpacity,
              child: Padding(
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
                        Text(
                          context.t('settings.appName'),
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                            letterSpacing: -0.5,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        GestureDetector(
                          onTap: () => ref
                              .read(balanceVisibleProvider.notifier)
                              .toggle(),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: brand.surface,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              visible
                                  ? CupertinoIcons.eye
                                  : CupertinoIcons.eye_slash,
                              size: 17,
                              color: brand.inkSoft,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const FxRateButton(),
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () =>
                              showGroupMenu(context, ref, activeGroup, user?.uid),
                          child: GroupAvatarPill(
                              group: activeGroup, userId: user?.uid),
                        ),
                        const SizedBox(width: 8),
                        const ProfileAvatarButton(),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // ── Segmented control ─────────────────────────────────
            if (groups.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: PersonalGroupToggle(brand: brand),
              ),

            // ── Scrollable body ───────────────────────────────────
            Expanded(
              child: Stack(
                children: [
                  groupsAsync.isLoading
                      ? const Center(child: CupertinoActivityIndicator())
                      : groups.isEmpty
                      ? _IntroView(brand: brand)
                      : GroupDashboardContent(
                          brand: brand,
                          group: activeGroup,
                          symbol: symbol,
                          userId: user?.uid,
                        ),
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: IgnorePointer(
                      child: Container(
                        height: 48,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [brand.background, brand.background.withValues(alpha: 0)],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Group avatar pair pill ───────────────────────────────────────────────────

class GroupAvatarPill extends ConsumerWidget {
  final ExpenseGroup? group;
  final String? userId;

  const GroupAvatarPill({super.key, required this.group, required this.userId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = group?.members.where((m) => m.uid == userId).firstOrNull;
    final partner = group?.members.where((m) => m.uid != userId).firstOrNull;
    final myLive = ref.watch(userNameProvider);
    final myInitial = myLive.isNotEmpty
        ? myLive.substring(0, 1).toUpperCase()
        : (me?.displayName.substring(0, 1) ?? 'Y').toUpperCase();
    final hasPartner = partner != null;
    final partnerLive = hasPartner
        ? (ref.watch(memberDisplayNameProvider(partner.uid)).valueOrNull ?? '')
        : null;
    final partnerInitial = hasPartner
        ? (partnerLive!.isNotEmpty ? partnerLive : partner.displayName)
              .substring(0, 1).toUpperCase()
        : null;

    return Container(
      padding: const EdgeInsets.fromLTRB(4, 4, 10, 4),
      decoration: BoxDecoration(
        color: context.brand.surface,
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
          if (hasPartner)
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
                      letter: partnerInitial!,
                      bg: const Color(0xFFD7F4E5),
                      fg: const Color(0xFF1FBE71),
                      size: 28,
                    ),
                  ),
                ],
              ),
            )
          else
            _MiniAvatar(
              letter: myInitial,
              bg: const Color(0xFFEAE3F8),
              fg: const Color(0xFF5A4AAB),
              size: 28,
            ),
          const SizedBox(width: 6),
          const Icon(
            CupertinoIcons.chevron_down,
            size: 13,
            color: Color(0xFF8E8E96),
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
        border: Border.all(color: context.brand.surface, width: 2),
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

// ── Coordinator for one-at-a-time group expense swipe ───────────────────────

class _GrpCoordinator extends ValueNotifier<String?> {
  _GrpCoordinator() : super(null);
  void openRow(String id) => value = id;
  void closeAll() => value = null;
}

// ── Group body (has group) ───────────────────────────────────────────────────

class GroupDashboardContent extends ConsumerStatefulWidget {
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
  ConsumerState<GroupDashboardContent> createState() => _GroupDashboardContentState();
}

class _GroupDashboardContentState extends ConsumerState<GroupDashboardContent> {
  final _coordinator = _GrpCoordinator();

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = widget.brand;
    final group = widget.group;
    final symbol = widget.symbol;
    final userId = widget.userId;
    if (group == null) {
      return _IntroView(brand: brand);
    }

    // Keep Firestore → local sync alive while this screen is visible.
    ref.watch(groupExpenseSyncProvider(group.id));

    final expensesAsync = ref.watch(groupExpensesProvider(group.id));
    final expenses = expensesAsync.valueOrNull ?? const [];
    final service = ref.read(expenseGroupServiceProvider);
    final balances = service.computeBalances(group.members, expenses);
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

    final me = group.members.where((m) => m.uid == userId).firstOrNull;
    final partner = group.members.where((m) => m.uid != userId).firstOrNull;
    final profileName = ref.watch(userNameProvider);
    final myDisplayName = profileName.isNotEmpty
        ? profileName
        : (me?.displayName ?? 'You');
    final myInitial = myDisplayName.substring(0, 1).toUpperCase();
    final partnerLive = partner != null
        ? (ref.watch(memberDisplayNameProvider(partner.uid)).valueOrNull ?? '')
        : '';
    final partnerName = partnerLive.isNotEmpty
        ? partnerLive
        : (partner?.displayName.isNotEmpty == true ? partner!.displayName : 'Partner');
    final partnerInitial = partnerName.substring(0, 1).toUpperCase();

    // Consumption = what each person actually owes/spent based on split,
    // not just who handed over the cash.
    // Formula: consumed = totalPaid − net  (net = totalPaid − splitAmount)
    final myPaid = myBalance?.totalPaid as double? ?? 0;
    final partnerPaid = partnerBalance?.totalPaid as double? ?? 0;
    final partnerNet = partnerBalance?.net as double? ?? 0;
    final mySpent = (myPaid - myNet).clamp(0.0, double.infinity);
    final partnerSpent = (partnerPaid - partnerNet).clamp(0.0, double.infinity);

    return FadingEdgeList(
      fadeColor: brand.background,
      child: ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
      children: [
        // ── Hero card ─────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(20, 20, 22, 22),
          decoration: BoxDecoration(
            color: brand.surface,
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
                        context.t('group.group'),
                        style: TextStyle(
                          color: brand.inkSoft,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        context.t('group.spent'),
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
                  color: brand.surface,
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
                            context.t('group.youSpent'),
                            style: TextStyle(
                              color: brand.inkSoft,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$symbol${mySpent.toStringAsFixed(2)}',
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
                            context
                                .t('group.spentBy')
                                .replaceAll('{name}', partnerName),
                            style: TextStyle(
                              color: brand.inkSoft,
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '$symbol${partnerSpent.toStringAsFixed(2)}',
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
                            ? context
                                .t('group.partnerOwesYou')
                                .replaceAll('{name}', partnerName)
                            : context
                                .t('group.youOwePartner')
                                .replaceAll('{name}', partnerName),
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

              const SizedBox(height: 14),

              // Generate Receipt — bottom of hero card
              GestureDetector(
                onTap: () => showGroupReceiptPicker(context, group),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.doc_text, color: brand.inkSoft, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        context.t('group.generateReceipt'),
                        style: TextStyle(
                          color: brand.ink,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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
            Text(
              context.t('group.activity'),
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: brand.ink,
                letterSpacing: -0.3,
              ),
            ),
            // Add Expense button
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => AddGroupExpenseScreen(group: group),
                ),
              ),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A6CFF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(CupertinoIcons.plus, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      context.t('group.addExpense'),
                      style: const TextStyle(
                        color: Colors.white,
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

        const SizedBox(height: 12),

        // Expense list card
        if (expenses.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: brand.surface,
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
                    context.t('group.noExpensesYet'),
                    style: TextStyle(color: brand.inkSoft, fontSize: 14),
                  ),
                ],
              ),
            ),
          )
        else
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _coordinator.closeAll,
            child: Container(
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(28),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
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
                      _SwipeableActivityRow(
                        brand: brand,
                        expense: expenses[i],
                        group: group,
                        members: group.members,
                        symbol: symbol,
                        userId: userId,
                        ref: ref,
                        coordinator: _coordinator,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),

        const SizedBox(height: 16),

        // Invite partner button (if only one member)
        if (group.members.length < 2)
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => GroupInviteScreen(group: group),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF1A6CFF).withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    CupertinoIcons.person_badge_plus,
                    color: Color(0xFF1A6CFF),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.t('group.invitePartner'),
                    style: const TextStyle(
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
    ),
    );
  }
}

// ── Swipeable activity row ────────────────────────────────────────────────────

class _SwipeableActivityRow extends StatefulWidget {
  final BrandColors brand;
  final GroupExpenseItem expense;
  final ExpenseGroup group;
  final List<GroupMember> members;
  final String symbol;
  final String? userId;
  final WidgetRef ref;
  final _GrpCoordinator coordinator;

  const _SwipeableActivityRow({
    required this.brand,
    required this.expense,
    required this.group,
    required this.members,
    required this.symbol,
    required this.userId,
    required this.ref,
    required this.coordinator,
  });

  @override
  State<_SwipeableActivityRow> createState() => _SwipeableActivityRowState();
}

class _SwipeableActivityRowState extends State<_SwipeableActivityRow>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _anim;

  static const double _rightWidth = 148.0; // Edit + Delete
  static const double _leftWidth = 80.0;   // Copy
  static const double _snapThreshold = 55.0;

  double _drag = 0.0;
  double _dragStartOffset = 0.0;
  int _dir = 0; // -1 left, 1 right, 0 neutral

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _anim = Tween<double>(begin: 0, end: 0).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    widget.coordinator.addListener(_onCoordChange);
  }

  @override
  void dispose() {
    widget.coordinator.removeListener(_onCoordChange);
    _ctrl.dispose();
    super.dispose();
  }

  void _onCoordChange() {
    if (widget.coordinator.value != widget.expense.id) {
      _close();
    }
  }

  void _animateTo(double target) {
    _anim = Tween<double>(begin: _anim.value, end: target)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward(from: 0);
  }

  void _close() => _animateTo(0);

  Future<void> _delete() async {
    _close();
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (_) => CupertinoAlertDialog(
        title: Text(context.t('group.deleteExpense')),
        content: Text(widget.expense.description),
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
    if (confirmed != true || !mounted) return;
    try {
      final isOnline = widget.ref.read(isOnlineProvider);
      final userId = widget.userId ?? '';

      // Always remove from local Hive immediately for instant UI update.
      await LocalExpenseGroupRepository().deleteExpense(
        widget.expense.groupId, widget.expense.id,
      );

      if (storageMode == StorageMode.firebase) {
        if (isOnline) {
          // Online: delete from Firebase directly.
          await FirebaseExpenseGroupRepository().deleteExpense(
            widget.expense.groupId, widget.expense.id,
          );
        } else if (userId.isNotEmpty) {
          // Offline: queue so it's deleted from Firebase on reconnect.
          await SyncService.markEntityPendingDelete(
            userId, 'group_expense',
            '${widget.expense.groupId}:${widget.expense.id}',
          );
        }
      }

      if (mounted) AppToast.show(context, context.t('group.expenseDeleted'));
    } catch (_) {
      if (mounted) {
        AppToast.show(context, context.t('group.failedToDeleteExpense'),
            type: AppToastType.error);
      }
    }
  }

  void _edit() {
    _close();
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => AddGroupExpenseScreen(group: widget.group, existing: widget.expense),
      ),
    );
  }

  void _duplicate() {
    _close();
    // Open the add expense form pre-filled with the existing expense's values
    // so the user can review/edit before saving (same UX as personal copy).
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => AddGroupExpenseScreen(
          group: widget.group,
          copyFrom: widget.expense,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: (_) {
        _ctrl.stop();
        _drag = _anim.value;
        _dragStartOffset = _drag;
        _dir = 0;
        widget.coordinator.openRow(widget.expense.id);
      },
      onHorizontalDragUpdate: (d) {
        if (_dir == 0) {
          if (d.delta.dx < 0) _dir = -1;
          if (d.delta.dx > 0) _dir = 1;
        }
        setState(() {
          _drag += d.delta.dx;
          _drag = _dir == -1
              ? _drag.clamp(-_rightWidth, 0.0)
              : _drag.clamp(0.0, _leftWidth);
        });
      },
      onHorizontalDragEnd: (d) {
        final vel = d.primaryVelocity ?? 0;
        final shouldOpen = _drag.abs() > _snapThreshold || vel.abs() > 300;
        final rightInvolved = _dragStartOffset < 0 || (_dir == -1 && _dragStartOffset == 0);
        if (rightInvolved) {
          shouldOpen ? _animateTo(-_rightWidth) : _animateTo(0);
        } else {
          // Left panel: snap open — user must tap the button to duplicate
          shouldOpen ? _animateTo(_leftWidth) : _animateTo(0);
        }
      },
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context2, unused) {
          final offset = _dir == 0 ? _drag : _anim.value;
          final copyOpacity = (offset / _leftWidth).clamp(0.0, 1.0);
          final rightOpacity = (-offset / _rightWidth).clamp(0.0, 1.0);
          return Stack(
            clipBehavior: Clip.none,
            children: [
              // Left action (copy) — same style as personal record
              Positioned(
                left: 16,
                top: 0,
                bottom: 0,
                width: _leftWidth - 8,
                child: Opacity(
                  opacity: copyOpacity,
                  child: GestureDetector(
                    onTap: () { _animateTo(0); _duplicate(); },
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.income,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(CupertinoIcons.doc_on_doc, color: Colors.white, size: 20),
                          const SizedBox(height: 4),
                          Text(context.t('metal.copy'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              // Right actions (edit + delete) — same style as personal record
              Positioned(
                right: 16,
                top: 0,
                bottom: 0,
                width: _rightWidth - 8,
                child: Opacity(
                  opacity: rightOpacity,
                  child: Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: _edit,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF5B8AF4),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(CupertinoIcons.pencil, color: Colors.white, size: 20),
                                const SizedBox(height: 4),
                                Text(context.t('common.edit'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: GestureDetector(
                          onTap: _delete,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.expense,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(CupertinoIcons.delete, color: Colors.white, size: 20),
                                const SizedBox(height: 4),
                                Text(context.t('common.delete'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Main content — slides with gesture
              Transform.translate(
                offset: Offset(_dir == 0 ? _drag : _anim.value, 0),
                child: _ActivityRow(
                  brand: widget.brand,
                  expense: widget.expense,
                  members: widget.members,
                  symbol: widget.symbol,
                  userId: widget.userId,
                  onTap: _edit,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Activity row ─────────────────────────────────────────────────────────────

class _ActivityRow extends ConsumerWidget {
  final BrandColors brand;
  final GroupExpenseItem expense;
  final List<GroupMember> members;
  final String symbol;
  final String? userId;
  final VoidCallback? onTap;

  const _ActivityRow({
    required this.brand,
    required this.expense,
    required this.members,
    required this.symbol,
    required this.userId,
    this.onTap,
  });

  String _fallbackName(String uid) {
    try {
      return members.firstWhere((m) => m.uid == uid).displayName;
    } catch (_) {
      return 'Someone';
    }
  }

  // Per-person share for [uid] — from splitPercents if set, else equal split.
  String _shareFor(String uid) {
    final total = expense.amount;
    final percents = expense.splitPercents;
    if (percents != null && percents.containsKey(uid)) {
      return '$symbol${(total * percents[uid]! / 100).toStringAsFixed(2)}';
    }
    if (expense.splitBetween.contains(uid) &&
        expense.splitBetween.isNotEmpty) {
      return '$symbol${(total / expense.splitBetween.length).toStringAsFixed(2)}';
    }
    return '${symbol}0.00';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Resolve live display names for every member in this expense's group.
    String resolveName(String uid) {
      final live = ref.watch(memberDisplayNameProvider(uid)).valueOrNull ?? '';
      return live.isNotEmpty ? live : _fallbackName(uid);
    }

    final isMine = expense.paidBy == userId;
    final dateStr = DateFormat('MMM d').format(expense.date);
    final catStyle = styleFor(expense.category);
    final payerName = resolveName(expense.paidBy);
    final payerInitial = payerName.substring(0, 1).toUpperCase();
    final payerIsMine = expense.paidBy == userId;
    final otherUid =
        members.where((m) => m.uid != userId).firstOrNull?.uid;

    // Short version of "You" label and other member's first name
    final myName = isMine ? context.t('group.you') : payerName.split(' ').first;
    final otherFirstName = otherUid != null ? resolveName(otherUid).split(' ').first : null;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Category icon tile
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: catStyle.background,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(catStyle.icon, color: catStyle.accent, size: 19),
          ),
          const SizedBox(width: 12),
          // Description + payer (takes remaining space)
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
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    // Payer mini avatar
                    Container(
                      width: 14,
                      height: 14,
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
                            fontSize: 8,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$myName · $dateStr',
                      style: TextStyle(color: brand.inkSoft, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Amount + split amounts (constrained width)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 130),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$symbol${expense.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    color: brand.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (otherFirstName != null && expense.splitBetween.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    '${context.t('group.you')} ${_shareFor(userId ?? '')}',
                    style: TextStyle(color: brand.inkSoft, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$otherFirstName ${_shareFor(otherUid!)}',
                    style: TextStyle(color: brand.inkSoft, fontSize: 10),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
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
              tileColor: selected ? const Color(0xFFE4ECFE) : ctx.brand.surface,
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
              context.t('group.generateReceiptTitle'),
              style: TextStyle(
                color: brand.ink,
                fontSize: 24,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              context.t('group.chooseReceiptType'),
              style: TextStyle(color: brand.inkSoft, fontSize: 14),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final pillWidth = (constraints.maxWidth - 8) / 2;
                  return SizedBox(
                    height: 44,
                    child: Stack(
                      children: [
                        AnimatedPositioned(
                          duration: const Duration(milliseconds: 250),
                          curve: Curves.easeInOut,
                          left: isDaily ? 0 : pillWidth,
                          top: 0,
                          bottom: 0,
                          width: pillWidth,
                          child: Container(
                            decoration: BoxDecoration(
                              color: brand.surface,
                              borderRadius: BorderRadius.circular(13),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 10,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            _PeriodTab(
                              label: context.t('group.daily'),
                              selected: isDaily,
                              onTap: () => setState(
                                  () => _period = GroupReceiptPeriod.day),
                            ),
                            _PeriodTab(
                              label: context.t('group.month'),
                              selected: !isDaily,
                              onTap: () => setState(
                                  () => _period = GroupReceiptPeriod.month),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
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
                  color: brand.surface,
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
                            isDaily
                                ? context.t('group.receiptDate')
                                : context.t('group.receiptMonth'),
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
                child: Text(
                  context.t('group.generateReceiptTitle'),
                  style: const TextStyle(
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
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Center(
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              style: TextStyle(
                color: selected
                    ? context.brand.ink
                    : const Color(0xFF8E8E96),
                fontSize: 15,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              child: Text(label),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final me = group.members.where((m) => m.uid == userId).firstOrNull;
    final partner = group.members.where((m) => m.uid != userId).firstOrNull;

    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
            (group.members.length == 1
                    ? context.t('group.memberCount')
                    : context.t('group.memberCountPlural'))
                .replaceAll('{count}', '${group.members.length}'),
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
          // Invite partner (only when group has no partner yet)
          if (group.members.length < 2) ...[
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: const Color(0xFF1A6CFF).withValues(alpha: isDark ? 0.25 : 0.10),
                borderRadius: BorderRadius.circular(14),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => GroupInviteScreen(group: group),
                    ),
                  );
                },
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.person_badge_plus,
                        size: 16, color: Color(0xFF1A6CFF)),
                    const SizedBox(width: 8),
                    Text(
                      context.t('group.invitePartner'),
                      style: const TextStyle(
                        color: Color(0xFF1A6CFF),
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],
          // When sole member: only show Delete (leaving = deleting anyway).
          // When multiple members: show Leave for everyone, Delete for owner.
          if (group.members.length > 1) ...[
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: const Color(0xFFD93025).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                onPressed: () async {
                  final confirmed = await showCupertinoDialog<bool>(
                    context: context,
                    builder: (dialogCtx) => CupertinoAlertDialog(
                      title: Text('${context.t('group.leaveGroup')}?'),
                      content: Text(context.t('group.leaveGroupConfirm')),
                      actions: [
                        CupertinoDialogAction(
                          isDestructiveAction: true,
                          onPressed: () => Navigator.pop(dialogCtx, true),
                          child: Text(context.t('group.leave')),
                        ),
                        CupertinoDialogAction(
                          onPressed: () => Navigator.pop(dialogCtx, false),
                          child: Text(context.t('common.cancel')),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && userId != null) {
                    void clearGroupState() {
                      ref
                          .read(removedExpenseGroupIdsProvider.notifier)
                          .state = {
                        ...ref.read(removedExpenseGroupIdsProvider),
                        group.id,
                      };
                      ref.read(activeGroupIdProvider.notifier).state = null;
                      ref.read(homeModeProvider.notifier).state =
                          HomeMode.personal;
                    }

                    try {
                      final isOnline = ref.read(isOnlineProvider);

                      // Always update local Hive immediately: removes userId
                      // and transfers ownership to the next member.
                      await LocalExpenseGroupRepository()
                          .removeMemberFromGroup(group.id, userId!);

                      if (isOnline) {
                        final service = ref.read(expenseGroupServiceProvider);
                        await service.leaveGroup(group.id, userId!);
                      } else if (storageMode == StorageMode.firebase) {
                        // Offline: queue leave for Firebase when reconnected.
                        await SyncService.markEntityPendingDelete(
                            userId!, 'group_leave', group.id);
                      }
                      clearGroupState();
                      if (context.mounted) {
                        Navigator.pop(context);
                        AppToast.show(context, context.t('group.leftGroup'));
                      }
                    } on FirebaseException catch (e) {
                      if (e.code == 'not-found' ||
                          e.code == 'permission-denied') {
                        clearGroupState();
                        if (context.mounted) {
                          Navigator.pop(context);
                          AppToast.show(context, context.t('group.leftGroup'));
                        }
                      } else {
                        if (context.mounted) {
                          AppToast.show(
                              context, context.t('group.failedToLeave'));
                        }
                      }
                    } catch (_) {
                      if (context.mounted) {
                        AppToast.show(
                            context, context.t('group.failedToLeave'));
                      }
                    }
                  }
                },
                child: Text(
                  context.t('group.leaveGroup'),
                  style: const TextStyle(
                    color: Color(0xFFD93025),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
          // Delete group button — owner only (or sole member)
          if (userId == group.createdBy || group.members.length == 1) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton(
                padding: const EdgeInsets.symmetric(vertical: 14),
                color: const Color(0xFFD93025).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                onPressed: () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialogCtx) => _DeleteGroupDialog(
                      groupName: group.name,
                    ),
                  );
                  if (confirmed == true) {
                    void clearGroupState() {
                      ref
                          .read(removedExpenseGroupIdsProvider.notifier)
                          .state = {
                        ...ref.read(removedExpenseGroupIdsProvider),
                        group.id,
                      };
                      ref.read(activeGroupIdProvider.notifier).state = null;
                      ref.read(homeModeProvider.notifier).state =
                          HomeMode.personal;
                    }

                    try {
                      final isOnline = ref.read(isOnlineProvider);

                      // Always clean up local Hive immediately.
                      await LocalExpenseGroupRepository().deleteGroup(group.id);

                      if (isOnline) {
                        final service = ref.read(expenseGroupServiceProvider);
                        await service.deleteGroup(group.id);
                      } else if (storageMode == StorageMode.firebase &&
                          userId != null) {
                        // Offline: queue Firebase deletion for when reconnected.
                        await SyncService.markEntityPendingDelete(
                            userId!, 'group_delete', group.id);
                      }
                      clearGroupState();
                      if (context.mounted) {
                        Navigator.pop(context);
                        AppToast.show(context, context.t('group.groupDeleted'));
                      }
                    } on FirebaseException catch (e) {
                      if (e.code == 'not-found' ||
                          e.code == 'permission-denied') {
                        // Group already gone from Firebase — treat as success.
                        clearGroupState();
                        if (context.mounted) {
                          Navigator.pop(context);
                          AppToast.show(
                              context, context.t('group.groupDeleted'));
                        }
                      } else {
                        if (context.mounted) {
                          AppToast.show(
                              context, context.t('group.failedToDelete'));
                        }
                      }
                    } catch (_) {
                      if (context.mounted) {
                        AppToast.show(
                            context, context.t('group.failedToDelete'));
                      }
                    }
                  }
                },
                child: Text(
                  context.t('group.deleteGroup'),
                  style: const TextStyle(
                    color: Color(0xFFD93025),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Animated delete-group confirmation dialog ─────────────────────────────────

class _DeleteGroupDialog extends StatefulWidget {
  final String groupName;
  const _DeleteGroupDialog({required this.groupName});

  @override
  State<_DeleteGroupDialog> createState() => _DeleteGroupDialogState();
}

class _DeleteGroupDialogState extends State<_DeleteGroupDialog>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _shake;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _shake = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: -8), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -8, end: 8), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 8, end: -6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: -6, end: 6), weight: 2),
      TweenSequenceItem(tween: Tween(begin: 6, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    _scale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.15), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 1.15, end: 1.0), weight: 1),
    ]).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    // Start animation shortly after showing
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Animated warning icon
            AnimatedBuilder(
              animation: _ctrl,
              builder: (_, child) => Transform.translate(
                offset: Offset(_shake.value, 0),
                child: Transform.scale(scale: _scale.value, child: child),
              ),
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: const Color(0xFFD93025).withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  CupertinoIcons.exclamationmark_triangle_fill,
                  color: Color(0xFFD93025),
                  size: 32,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.t('group.deleteGroup'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: context.brand.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('group.deleteGroupPermanent'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: context.brand.inkSoft,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: context.brand.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        context.t('common.cancel'),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.brand.ink,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(context, true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFD93025),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        context.t('common.delete'),
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
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

class _MemberRow extends ConsumerWidget {
  final GroupMember member;
  final bool isYou;
  const _MemberRow({required this.member, required this.isYou});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final liveFromProfile = isYou ? ref.watch(userNameProvider) : '';
    final liveFromFirestore = isYou
        ? ''
        : (ref.watch(memberDisplayNameProvider(member.uid)).valueOrNull ?? '');
    final displayName = liveFromProfile.isNotEmpty
        ? liveFromProfile
        : liveFromFirestore.isNotEmpty
            ? liveFromFirestore
            : member.displayName;

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
              displayName.substring(0, 1).toUpperCase(),
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
                    displayName,
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
                      child: Text(
                        context.t('group.you'),
                        style: const TextStyle(
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
                context.t('group.joined').replaceAll(
                    '{date}',
                    DateFormat('MMM d, yyyy').format(member.joinedAt)),
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
