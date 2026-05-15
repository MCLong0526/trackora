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
          data: (groups) {
            if (groups.isEmpty) {
              return _EmptyState(
                onAdd: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => const AddEditTravelGroupScreen(),
                  ),
                ),
              );
            }
            return ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              itemCount: groups.length,
              itemBuilder: (context, i) => _GroupCard(
                group: groups[i],
                onTap: () => Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) =>
                        TravelGroupDetailScreen(group: groups[i]),
                  ),
                ),
              ),
            );
          },
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
    final dateFormat = DateFormat('MMM d, yyyy');
    final now = DateTime.now();
    final isOngoing = group.endDate == null || group.endDate!.isAfter(now);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
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
            // Icon
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: brand.sky,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                CupertinoIcons.airplane,
                color: Color(0xFF3478F6),
                size: 26,
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
                  Text(
                    '${group.memberIds.length} ${context.t('travel.members').toLowerCase()}',
                    style: TextStyle(
                      fontSize: 12,
                      color: brand.inkSoft,
                    ),
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

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

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
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: brand.sky,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                CupertinoIcons.airplane,
                color: Color(0xFF3478F6),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              context.t('travel.empty'),
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: brand.ink,
                letterSpacing: -0.4,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              context.t('travel.emptyHint'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                color: brand.inkSoft,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 28),
            CupertinoButton.filled(
              borderRadius: BorderRadius.circular(14),
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              onPressed: onAdd,
              child: Text(context.t('travel.createGroup')),
            ),
          ],
        ),
      ),
    );
  }
}
