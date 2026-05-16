import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../widgets/app_toast.dart';
import 'add_edit_travel_group_screen.dart';
import 'travel_group_detail_screen.dart';

// ── Design tokens (travel-apple.jsx) ─────────────────────────────────────────
const _blue = Color(0xFF0066CC);
const _hairline = Color(0xFFE0E0E0);
const _parchment = Color(0xFFF5F5F7);
const _inkColor = Color(0xFF1D1D1F);
const _ink80 = Color(0xFF333333);
const _ink48 = Color(0xFF7A7A7A);
const _ink24 = Color(0x3D1D1D1F);
// Achromatic member fills
const _memberBgs = [
  Color(0xFFE8E8EA), Color(0xFFDCDCE0), Color(0xFFD0D0D5),
  Color(0xFFC4C4CA), Color(0xFFB8B8BF),
];

TextStyle _display(double size, {double tracking = -0.374, double lh = 1.10, Color? color}) =>
    TextStyle(fontSize: size, fontWeight: FontWeight.w600, letterSpacing: tracking, height: lh, color: color ?? _inkColor);

TextStyle _body(double size, {int weight = 400, Color? color}) =>
    TextStyle(fontSize: size, fontWeight: FontWeight.values[weight ~/ 100], letterSpacing: -0.374, height: 1.47, color: color ?? _inkColor);

TextStyle _eyebrow({Color color = _ink48}) =>
    TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.6, height: 1.3, color: color);

// ── Main screen ───────────────────────────────────────────────────────────────

class TravelGroupsScreen extends ConsumerStatefulWidget {
  const TravelGroupsScreen({super.key});

  @override
  ConsumerState<TravelGroupsScreen> createState() => _TravelGroupsScreenState();
}

class _TravelGroupsScreenState extends ConsumerState<TravelGroupsScreen> {
  String? _lastProcessedUid;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : _parchment;
    final async = ref.watch(travelGroupsProvider);

    // Auto-join email-invited groups whenever a new user signs in.
    ref.listen(authStateProvider, (previous, next) {
      final user = next.valueOrNull;
      if (user == null || user.uid == _lastProcessedUid) return;
      _lastProcessedUid = user.uid;
      if ((user.email ?? '').isEmpty) return;
      ref.read(travelGroupServiceProvider).processEmailInvites(
        userEmail: user.email!,
        userId: user.uid,
        userName: user.email!.split('@').first,
      );
    });

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => _ErrorBody(error: e),
          data: (groups) => _Body(groups: groups, isDark: isDark),
        ),
      ),
    );
  }
}

class _ErrorBody extends StatelessWidget {
  final Object error;
  const _ErrorBody({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(CupertinoIcons.exclamationmark_triangle, size: 40, color: _ink48),
            const SizedBox(height: 12),
            Text('${context.t('common.error')}: $error',
                textAlign: TextAlign.center,
                style: _body(15, color: _ink48)),
          ],
        ),
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  final List<TravelGroup> groups;
  final bool isDark;
  const _Body({required this.groups, required this.isDark});

  void _showJoinWithCodeSheet(BuildContext context, WidgetRef ref) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => _JoinWithCodeSheet(ref: ref),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final active = groups.where((g) => g.endDate == null || g.endDate!.isAfter(now)).toList();
    final past = groups.where((g) => g.endDate != null && !g.endDate!.isAfter(now)).toList();

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ── Top utility row ───────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _CircleBtn(
                onTap: () => Navigator.pop(context),
                child: const Icon(CupertinoIcons.back, size: 16, color: _inkColor),
              ),
              _CircleBtn(
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    fullscreenDialog: true,
                    builder: (_) => const AddEditTravelGroupScreen(),
                  ),
                ),
                child: const Icon(CupertinoIcons.add, size: 18, color: _inkColor),
              ),
            ],
          ),
        ),

        // ── Hero ─────────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                groups.isEmpty
                    ? 'Travel'.toUpperCase()
                    : 'TRAVEL · ${groups.length} ${groups.length == 1 ? 'TRIP' : 'TRIPS'}',
                style: _eyebrow(color: _blue),
              ),
              const SizedBox(height: 10),
              Text(
                'Trips that\nbalance themselves.',
                style: _display(40, tracking: -1.0, lh: 1.07),
              ),
              const SizedBox(height: 14),
              Text(
                'Log who paid and who shared each bill —\nwe\'ll close the loop at the end of the trip.',
                style: _body(17, color: _ink80),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  _PillPrimary(
                    label: 'New trip',
                    onTap: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                        fullscreenDialog: true,
                        builder: (_) => const AddEditTravelGroupScreen(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _PillGhost(
                    label: 'Join with code',
                    onTap: () => _showJoinWithCodeSheet(context, ref),
                  ),
                ],
              ),
            ],
          ),
        ),

        // ── Active trips ──────────────────────────────────────────────────
        if (active.isNotEmpty) ...[
          _SectionLabel(label: 'ACTIVE'),
          ...active.map((g) => Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                child: _TripCardActive(
                  group: g,
                  isDark: isDark,
                  onOpen: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => TravelGroupDetailScreen(group: g),
                    ),
                  ),
                ),
              )),
        ],

        // ── Past trips ────────────────────────────────────────────────────
        if (past.isNotEmpty) ...[
          _SectionLabel(label: 'SETTLING & PAST'),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
            child: _TripListCard(
              trips: past,
              isDark: isDark,
              onTap: (g) => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => TravelGroupDetailScreen(group: g),
                ),
              ),
            ),
          ),
        ],

        // ── Empty state ───────────────────────────────────────────────────
        if (groups.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 40),
            child: _EmptyHint(isDark: isDark),
          ),

        const SizedBox(height: 40),
      ],
    );
  }
}

// ── Active trip card ──────────────────────────────────────────────────────────

class _TripCardActive extends ConsumerWidget {
  final TravelGroup group;
  final bool isDark;
  final VoidCallback onOpen;

  const _TripCardActive({
    required this.group,
    required this.isDark,
    required this.onOpen,
  });

  void _showMembersPopup(BuildContext context, List<TravelGroupMember> members,
      TravelGroup group, bool isDark) {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => _MembersPopup(members: members, group: group, isDark: isDark),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmt = DateFormat('MMM d');
    final fmtFull = DateFormat('MMM d, yyyy');
    final amtFmt = NumberFormat('#,##0.00');
    final now = DateTime.now();
    final startedDaysAgo = now.difference(group.startDate).inDays;
    final totalDays = group.endDate != null
        ? group.endDate!.difference(group.startDate).inDays + 1
        : null;
    final dayLabel = totalDays != null
        ? 'day ${startedDaysAgo + 1} of $totalDays'
        : 'day ${startedDaysAgo + 1}';

    // Live data
    final membersAsync = ref.watch(travelGroupMembersProvider(group.id));
    final expensesAsync = ref.watch(travelGroupExpensesProvider(group.id));
    final user = ref.watch(authStateProvider).valueOrNull;

    final members = membersAsync.valueOrNull ?? [];
    final expenses = expensesAsync.valueOrNull ?? [];
    final memberCount = members.isNotEmpty ? members.length : group.memberIds.length;
    final totalSpent = expenses.fold(0.0, (s, e) => s + e.amountInGroupCurrency);
    final hasForeign = expenses.any((e) => e.currencyCode != null && e.currencyCode != group.currency);

    // Current user's balance
    final svc = ref.read(travelGroupServiceProvider);
    final settlement = svc.calculateSettlement(members, expenses);

    String? myMemberId;
    for (final m in members) {
      if (m.userId == user?.uid) { myMemberId = m.id; break; }
    }

    double? myNet;
    if (myMemberId != null) {
      for (final b in settlement.balances) {
        if (b.memberId == myMemberId) { myNet = b.net; break; }
      }
    }

    final balanceText = myNet == null
        ? 'Tap to see balance'
        : myNet > 0.005
            ? 'Others owe you: ${group.currency} ${amtFmt.format(myNet)}'
            : myNet < -0.005
                ? 'You owe: ${group.currency} ${amtFmt.format(myNet.abs())}'
                : 'All settled up!';
    final balanceColor = myNet == null
        ? _ink80
        : myNet > 0.005
            ? const Color(0xFF28A968)
            : myNet < -0.005
                ? const Color(0xFFFF3B30)
                : _ink48;

    return _Card(
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Active badge
            Row(
              children: [
                Container(
                  width: 6, height: 6,
                  decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('Active · $dayLabel'.toUpperCase(), style: _eyebrow(color: _blue)),
              ],
            ),
            const SizedBox(height: 10),

            // Trip name
            Text(group.name, style: _display(34, tracking: -0.8, lh: 1.10)),
            const SizedBox(height: 4),

            // Dates + travelers
            Text(
              '${fmt.format(group.startDate)}'
              '${group.endDate != null ? ' – ${fmtFull.format(group.endDate!)}' : ''}'
              ' · $memberCount travelers',
              style: _body(15, color: _ink80),
            ),

            const SizedBox(height: 22),

            // Trip total + avatars row
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('TRIP TOTAL', style: _eyebrow()),
                      const SizedBox(height: 4),
                      expensesAsync.isLoading
                          ? const CupertinoActivityIndicator()
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (hasForeign)
                                  Text(
                                    'Est.',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 0.2,
                                      color: isDark
                                          ? const Color(0xFF8E8E93)
                                          : const Color(0xFF8E8E93),
                                    ),
                                  ),
                                Text(
                                  '${group.currency} ${amtFmt.format(totalSpent)}',
                                  style: _display(28, tracking: -0.6, lh: 1.05),
                                ),
                              ],
                            ),
                    ],
                  ),
                ),
                _Pressable(
                  onTap: members.isNotEmpty
                      ? () => _showMembersPopup(context, members, group, isDark)
                      : onOpen,
                  child: members.isNotEmpty
                      ? _LiveMemberStack(members: members, size: 32)
                      : _MemberStack(memberIds: group.memberIds, size: 32),
                ),
              ],
            ),

            // Hairline divider
            const SizedBox(height: 22),
            Divider(height: 1, thickness: 1,
                color: isDark ? const Color(0xFF3A3A3C) : _hairline),
            const SizedBox(height: 18),

            // Balance line
            GestureDetector(
              onTap: onOpen,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(balanceText,
                      style: _body(15, color: balanceColor)),
                  const Icon(CupertinoIcons.chevron_right, size: 14, color: _ink24),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // CTA pills
            Row(
              children: [
                _PillPrimary(label: 'Open trip', onTap: onOpen),
                const SizedBox(width: 10),
                _PillGhost(label: 'Settle up', onTap: onOpen),
              ],
            ),

            // Invite code row
            if (group.inviteCode != null && group.inviteCode!.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: isDark ? const Color(0xFF3A3A3C) : _hairline),
              const SizedBox(height: 12),
              _InviteCodeRow(group: group, isDark: isDark),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Past trips list card ──────────────────────────────────────────────────────

class _TripListCard extends StatelessWidget {
  final List<TravelGroup> trips;
  final bool isDark;
  final void Function(TravelGroup) onTap;

  const _TripListCard({
    required this.trips,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _Card(
      isDark: isDark,
      child: Column(
        children: trips.asMap().entries.map((entry) {
          final idx = entry.key;
          final g = entry.value;
          return _TripListRow(
            group: g,
            last: idx == trips.length - 1,
            isDark: isDark,
            onTap: () => onTap(g),
          );
        }).toList(),
      ),
    );
  }
}

// ── Invite code row (handles share + clipboard with feedback) ─────────────────

class _InviteCodeRow extends StatefulWidget {
  final TravelGroup group;
  final bool isDark;
  const _InviteCodeRow({required this.group, required this.isDark});

  @override
  State<_InviteCodeRow> createState() => _InviteCodeRowState();
}

class _InviteCodeRowState extends State<_InviteCodeRow> {
  Future<void> _share() async {
    final code = widget.group.inviteCode!;
    final msg = 'Join "${widget.group.name}" on Trackora! Use invite code: $code';
    try {
      final box = context.findRenderObject() as RenderBox?;
      await Share.share(
        msg,
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
    } catch (_) {}
  }

  Future<void> _copy() async {
    final code = widget.group.inviteCode!;
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    AppToast.show(context, 'Code copied!',
        type: AppToastType.success,
        icon: CupertinoIcons.doc_on_clipboard_fill);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _share,
      onLongPress: _copy,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(CupertinoIcons.link, size: 11, color: _blue),
                const SizedBox(width: 4),
                Text(widget.group.inviteCode!,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.8,
                        color: _blue)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text('Tap to share · hold to copy', style: _eyebrow(color: _ink48)),
        ],
      ),
    );
  }
}

class _TripListRow extends StatelessWidget {
  final TravelGroup group;
  final bool last;
  final bool isDark;
  final VoidCallback onTap;

  const _TripListRow({
    required this.group,
    required this.last,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d');
    final dividerColor = isDark ? const Color(0xFF3A3A3C) : _hairline;

    return _Pressable(
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(group.name,
                              style: _body(17, weight: 600, color: _inkColor)),
                          const SizedBox(width: 6),
                          Text(
                            '· SETTLED',
                            style: _eyebrow(color: _ink48),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${fmt.format(group.startDate)}'
                        '${group.endDate != null ? ' – ${fmt.format(group.endDate!)}' : ''}',
                        style: _body(13, color: _ink48),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text('All clear', style: _body(13, color: _ink48)),
                const SizedBox(width: 8),
                const Icon(CupertinoIcons.chevron_right, size: 12, color: _ink24),
              ],
            ),
          ),
          if (!last)
            Divider(
              height: 1, thickness: 1, color: dividerColor,
              indent: 22, endIndent: 22,
            ),
        ],
      ),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyHint extends StatelessWidget {
  final bool isDark;
  const _EmptyHint({required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final divider = isDark ? const Color(0xFF3A3A3C) : _hairline;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: divider, width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('NO TRIPS YET', style: _eyebrow()),
          const SizedBox(height: 12),
          Text(
            'Create a group to track\nshared travel expenses.',
            textAlign: TextAlign.center,
            style: _body(17, color: _ink80),
          ),
        ],
      ),
    );
  }
}

// ── Reusable components ───────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  final bool isDark;
  const _Card({required this.child, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final divider = isDark ? const Color(0xFF3A3A3C) : _hairline;
    return Container(
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: divider, width: 1),
      ),
      child: child,
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
      child: Text(label, style: _eyebrow()),
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
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final divider = isDark ? const Color(0xFF3A3A3C) : _hairline;
    return _Pressable(
      onTap: onTap,
      child: Container(
        width: 40, height: 40,
        decoration: BoxDecoration(
          color: surface, shape: BoxShape.circle,
          border: Border.all(color: divider, width: 1),
        ),
        child: Center(child: child),
      ),
    );
  }
}

class _PillPrimary extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PillPrimary({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
        decoration: BoxDecoration(
          color: _blue,
          borderRadius: BorderRadius.circular(9999),
        ),
        child: Text(label,
            style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w400,
              letterSpacing: -0.2, color: Colors.white,
            )),
      ),
    );
  }
}

class _PillGhost extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PillGhost({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return _Pressable(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(21, 10, 21, 10),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(9999),
          border: Border.all(color: _blue, width: 1),
        ),
        child: Text(label,
            style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w400,
              letterSpacing: -0.2, color: _blue,
            )),
      ),
    );
  }
}

// ── Live member avatar stack (shows initials) ─────────────────────────────────

class _LiveMemberStack extends StatelessWidget {
  final List<TravelGroupMember> members;
  final double size;
  const _LiveMemberStack({required this.members, this.size = 28});

  @override
  Widget build(BuildContext context) {
    final shown = members.take(4).toList();
    final more = members.length - shown.length;
    final totalWidth = shown.length * (size - 8) + 8.0 + (more > 0 ? (size - 8) : 0);
    return SizedBox(
      width: totalWidth,
      height: size,
      child: Stack(
        children: [
          ...shown.asMap().entries.map((e) {
            final m = e.value;
            final bg = _memberBgs[e.key % _memberBgs.length];
            final initial = m.name.isNotEmpty ? m.name[0].toUpperCase() : '?';
            return Positioned(
              left: e.key * (size - 8),
              child: Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  color: bg, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text(initial,
                      style: TextStyle(
                        fontSize: size * 0.36, fontWeight: FontWeight.w700, color: _inkColor)),
                ),
              ),
            );
          }),
          if (more > 0)
            Positioned(
              left: shown.length * (size - 8),
              child: Container(
                width: size, height: size,
                decoration: BoxDecoration(
                  color: _memberBgs.last, shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: Center(
                  child: Text('+$more',
                      style: TextStyle(
                        fontSize: size * 0.34, fontWeight: FontWeight.w600, color: _inkColor)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Members popup (from trip list card avatar tap) ────────────────────────────

class _MembersPopup extends StatelessWidget {
  final List<TravelGroupMember> members;
  final TravelGroup group;
  final bool isDark;

  const _MembersPopup({
    required this.members,
    required this.group,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;
    final bg = isDark ? const Color(0xFF1C1C1E) : _parchment;

    return Material(
      type: MaterialType.transparency,
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.6,
        ),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 36, height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                        color: border, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                // Header
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(group.name, style: _display(20, tracking: -0.4)),
                          const SizedBox(height: 2),
                          Text('${members.length} travelers',
                              style: _eyebrow(color: _ink48)),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: bg, shape: BoxShape.circle,
                        ),
                        child: const Icon(CupertinoIcons.xmark, size: 14, color: _ink48),
                      ),
                    ),
                  ],
                ),
                if (group.inviteCode != null && group.inviteCode!.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  GestureDetector(
                    onTap: () {
                      Navigator.pop(context);
                      // Re-open join sheet via parent handled elsewhere; just show code
                    },
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(CupertinoIcons.link, size: 14, color: _blue),
                          const SizedBox(width: 8),
                          Text('Invite code: ',
                              style: _body(13, color: _ink48)),
                          Text(group.inviteCode!,
                              style: _body(13, weight: 700,
                                  color: _blue).copyWith(letterSpacing: 2)),
                          const Spacer(),
                          const Icon(CupertinoIcons.doc_on_clipboard, size: 14, color: _blue),
                        ],
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // Member list
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: members.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: border, indent: 52),
                    itemBuilder: (_, i) {
                      final m = members[i];
                      final initial = m.name.isNotEmpty ? m.name[0].toUpperCase() : '?';
                      final avatarBg = _memberBgs[i % _memberBgs.length];
                      final isOwner = m.userId != null && m.userId == group.ownerId;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Row(
                          children: [
                            Container(
                              width: 40, height: 40,
                              decoration: BoxDecoration(
                                color: avatarBg, shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(initial,
                                    style: _body(16, weight: 700)),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(children: [
                                    Text(m.name,
                                        style: _body(15, weight: 500)),
                                    if (isOwner) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 5, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: _blue.withValues(alpha: 0.10),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text('Owner',
                                            style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600,
                                                color: _blue)),
                                      ),
                                    ],
                                  ]),
                                  if (m.email != null && m.email!.isNotEmpty)
                                    Text(m.email!,
                                        style: _body(12, color: _ink48)),
                                ],
                              ),
                            ),
                            if (m.userId != null)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF28A968).withValues(alpha: 0.10),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 6, height: 6,
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF28A968),
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Text('Live',
                                        style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: Color(0xFF28A968))),
                                  ],
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
          ),
        ),
      ),
    );
  }
}

// ── Join with code sheet ──────────────────────────────────────────────────────

class _JoinWithCodeSheet extends ConsumerStatefulWidget {
  final WidgetRef ref;
  const _JoinWithCodeSheet({required this.ref});

  @override
  ConsumerState<_JoinWithCodeSheet> createState() => _JoinWithCodeSheetState();
}

class _JoinWithCodeSheetState extends ConsumerState<_JoinWithCodeSheet> {
  final _codeCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeCtrl.text.trim().toUpperCase();
    if (code.length < 4) return;
    setState(() => _loading = true);
    try {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user == null) throw Exception('Not signed in');
      final svc = ref.read(travelGroupServiceProvider);
      final userName = user.email?.split('@').first ?? 'Me';
      await svc.joinByCode(
        code: code,
        userId: user.uid,
        userName: userName,
        userEmail: user.email,
      );
      if (mounted) {
        AppToast.show(context, 'Joined trip!',
            type: AppToastType.success, icon: CupertinoIcons.checkmark_circle_fill);
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context,
            e.toString().contains('Invalid') ? 'Invalid code. Please check and try again.' : 'Failed to join trip.',
            type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final bg = isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7);
    final border = isDark ? const Color(0xFF3A3A3C) : _hairline;
    final codeVal = _codeCtrl.text.trim();

    return Material(
      type: MaterialType.transparency,
      child: Container(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 16, 22, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40, height: 5,
                    decoration: BoxDecoration(
                      color: border, borderRadius: BorderRadius.circular(100)),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Join a Trip', style: _body(18, weight: 700, color: _inkColor)),
                const SizedBox(height: 6),
                Text('Enter the 6-character invite code shared by the trip organiser.',
                    style: _body(14, color: _ink48)),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  decoration: BoxDecoration(
                    color: bg, borderRadius: BorderRadius.circular(14)),
                  child: TextField(
                    controller: _codeCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.characters,
                    maxLength: 8,
                    style: _body(20, weight: 600, color: _inkColor),
                    decoration: InputDecoration(
                      hintText: 'e.g. AB12CD',
                      hintStyle: _body(20, weight: 600, color: _ink48),
                      border: InputBorder.none,
                      counterText: '',
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _join(),
                  ),
                ),
                const SizedBox(height: 20),
                _Pressable(
                  onTap: (codeVal.length >= 4 && !_loading) ? _join : null,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: (codeVal.length >= 4 && !_loading) ? _blue : _blue.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(9999),
                    ),
                    child: Center(
                      child: _loading
                          ? const CupertinoActivityIndicator(color: Colors.white)
                          : Text('Join trip',
                              style: _body(16, weight: 600, color: Colors.white)),
                    ),
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

// ── Press animation wrapper ───────────────────────────────────────────────────

class _Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const _Pressable({required this.child, this.onTap});

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 100));
    _scale = Tween(begin: 1.0, end: 0.95).animate(
        CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) { if (widget.onTap != null) _ctrl.forward(); },
      onTapUp: (_) => _ctrl.reverse(),
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(scale: _scale, child: widget.child),
    );
  }
}

class _MemberStack extends StatelessWidget {
  final List<String> memberIds;
  final double size;

  const _MemberStack({
    required this.memberIds,
    this.size = 28,
  });

  @override
  Widget build(BuildContext context) {
    final shown = memberIds.take(4).toList();
    final more = memberIds.length - shown.length;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: shown.length * (size - 8) + 8.0 + (more > 0 ? (size - 8) : 0),
          height: size,
          child: Stack(
            children: [
              ...shown.asMap().entries.map((e) {
                final bg = _memberBgs[e.key % _memberBgs.length];
                return Positioned(
                  left: e.key * (size - 8),
                  child: Container(
                    width: size, height: size,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        '?',
                        style: TextStyle(
                          fontSize: size * 0.36,
                          fontWeight: FontWeight.w600,
                          color: _inkColor,
                        ),
                      ),
                    ),
                  ),
                );
              }),
              if (more > 0)
                Positioned(
                  left: shown.length * (size - 8),
                  child: Container(
                    width: size, height: size,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F5F7),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: Center(
                      child: Text(
                        '+$more',
                        style: TextStyle(
                          fontSize: size * 0.34,
                          fontWeight: FontWeight.w600,
                          color: _inkColor,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
