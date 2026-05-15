import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
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

class TravelGroupsScreen extends ConsumerWidget {
  const TravelGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : _parchment;
    final async = ref.watch(travelGroupsProvider);

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

class _Body extends StatelessWidget {
  final List<TravelGroup> groups;
  final bool isDark;
  const _Body({required this.groups, required this.isDark});

  @override
  Widget build(BuildContext context) {
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
                  _PillGhost(label: 'Join with code', onTap: () {}),
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

class _TripCardActive extends StatelessWidget {
  final TravelGroup group;
  final bool isDark;
  final VoidCallback onOpen;

  const _TripCardActive({
    required this.group,
    required this.isDark,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('MMM d');
    final fmtFull = DateFormat('MMM d, yyyy');
    final now = DateTime.now();
    final startedDaysAgo = now.difference(group.startDate).inDays;
    final totalDays = group.endDate != null
        ? group.endDate!.difference(group.startDate).inDays + 1
        : null;
    final dayLabel = totalDays != null
        ? 'day ${startedDaysAgo + 1} of $totalDays'
        : 'day ${startedDaysAgo + 1}';
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
              ' · ${group.memberIds.length} travelers',
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
                      RichText(
                        text: TextSpan(
                          style: _display(32, tracking: -0.6, lh: 1.05),
                          children: [
                            TextSpan(
                              text: '${group.currency} ',
                              style: _body(17, color: _ink80),
                            ),
                            const TextSpan(text: '—'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _MemberStack(memberIds: group.memberIds, size: 32),
              ],
            ),

            // Hairline divider
            const SizedBox(height: 22),
            Divider(height: 1, thickness: 1, color: isDark ? const Color(0xFF3A3A3C) : _hairline),
            const SizedBox(height: 18),

            // Balance line
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Open to see balance', style: _body(15, color: _ink80)),
                const Icon(CupertinoIcons.chevron_right, size: 14, color: _ink24),
              ],
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

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
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
    return GestureDetector(
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
    return GestureDetector(
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
    return GestureDetector(
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
