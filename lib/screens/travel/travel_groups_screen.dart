import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/travel_group.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import 'add_edit_travel_group_screen.dart';
import 'travel_group_detail_screen.dart';

class TravelGroupsScreen extends ConsumerWidget {
  const TravelGroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final async = ref.watch(travelGroupsProvider);

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(context.t('travel.title')),
        actions: [
          IconButton(
            icon: const Icon(CupertinoIcons.add),
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => const AddEditTravelGroupScreen(),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(
            child: Text('${context.t('common.error')}: $e'),
          ),
          data: (groups) => _Body(groups: groups),
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final List<TravelGroup> groups;
  const _Body({required this.groups});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
      children: [
        // Hero section
        _HeroSection(),
        const SizedBox(height: 20),

        // CTA buttons
        Row(
          children: [
            Expanded(
              child: _CTAButton(
                label: context.t('travel.newTrip'),
                icon: CupertinoIcons.add,
                filled: true,
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => const AddEditTravelGroupScreen(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _CTAButton(
                label: context.t('travel.joinCode'),
                icon: CupertinoIcons.link,
                filled: false,
                onTap: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 28),

        if (groups.isEmpty)
          _EmptyHint()
        else ...[
          Text(
            'YOUR TRIPS',
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF8E8E93),
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 10),
          ...groups.map((g) => _GroupCard(
                group: g,
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => TravelGroupDetailScreen(group: g),
                  ),
                ),
              )),
        ],
      ],
    );
  }
}

class _HeroSection extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.t('travel.tripsHero'),
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: brand.ink,
            letterSpacing: -0.5,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.t('travel.tripsHeroSub'),
          style: TextStyle(
            fontSize: 15,
            color: brand.inkSoft,
            height: 1.4,
          ),
        ),
      ],
    );
  }
}

class _CTAButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool filled;
  final VoidCallback onTap;

  const _CTAButton({
    required this.label,
    required this.icon,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    const blue = Color(0xFF3478F6);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: filled
              ? blue
              : (isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : brand.surface),
          borderRadius: BorderRadius.circular(16),
          border: filled
              ? null
              : Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : brand.divider,
                  width: 1,
                ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: filled ? Colors.white : blue,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: filled ? Colors.white : blue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final TravelGroup group;
  final VoidCallback onTap;

  const _GroupCard({required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final dateFormat = DateFormat('MMM d');
    final now = DateTime.now();
    final isOngoing = group.endDate == null || group.endDate!.isAfter(now);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : brand.divider,
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            // Airplane icon badge
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: brand.sky,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                CupertinoIcons.airplane,
                color: Color(0xFF3478F6),
                size: 24,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          group.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                            letterSpacing: -0.3,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _StatusBadge(isOngoing: isOngoing, context: context),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${group.currency} · ${dateFormat.format(group.startDate)}'
                    '${group.endDate != null ? ' – ${dateFormat.format(group.endDate!)}' : ''}',
                    style: TextStyle(
                      fontSize: 13,
                      color: brand.inkSoft,
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Member avatars
                  Row(
                    children: [
                      _MemberAvatars(count: group.memberIds.length),
                      const SizedBox(width: 6),
                      Text(
                        '${group.memberIds.length} ${context.t('travel.members').toLowerCase()}',
                        style: TextStyle(
                          fontSize: 12,
                          color: brand.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              CupertinoIcons.chevron_right,
              color: brand.inkSoft,
              size: 16,
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberAvatars extends StatelessWidget {
  final int count;
  const _MemberAvatars({required this.count});

  @override
  Widget build(BuildContext context) {
    final n = count.clamp(0, 3);
    const colors = [Color(0xFF3478F6), Color(0xFF34C759), Color(0xFF5856D6)];
    return SizedBox(
      width: n * 16.0 + 4,
      height: 20,
      child: Stack(
        children: List.generate(n, (i) {
          return Positioned(
            left: i * 14.0,
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: colors[i % colors.length].withValues(alpha: 0.2),
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black
                      : Colors.white,
                  width: 1.5,
                ),
              ),
              child: Icon(
                CupertinoIcons.person_fill,
                size: 10,
                color: colors[i % colors.length],
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final bool isOngoing;
  final BuildContext context;
  const _StatusBadge({required this.isOngoing, required this.context});

  @override
  Widget build(BuildContext _) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOngoing
            ? const Color(0xFF34C759).withValues(alpha: 0.15)
            : const Color(0xFF8E8E93).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isOngoing
            ? context.t('travel.ongoing')
            : context.t('travel.ended'),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isOngoing
              ? const Color(0xFF34C759)
              : const Color(0xFF8E8E93),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: brand.sky,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                CupertinoIcons.airplane,
                color: Color(0xFF3478F6),
                size: 36,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.t('travel.empty'),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: brand.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('travel.emptyHint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: brand.inkSoft,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
