import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/i18n.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';

class PersonalGroupToggle extends ConsumerWidget {
  final BrandColors brand;
  const PersonalGroupToggle({super.key, required this.brand});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(homeModeProvider);
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const [];
    final hasGroup = groups.isNotEmpty;
    final memberCount = hasGroup ? groups.first.members.length : 0;
    final isPersonal = mode == HomeMode.personal;

    return GestureDetector(
      onHorizontalDragEnd: (details) {
        final v = details.primaryVelocity ?? 0;
        if (v < -100 && isPersonal) {
          HapticFeedback.selectionClick();
          ref.read(homeModeProvider.notifier).state = HomeMode.group;
        } else if (v > 100 && !isPersonal) {
          HapticFeedback.selectionClick();
          ref.read(homeModeProvider.notifier).state = HomeMode.personal;
        }
      },
      child: Container(
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFEFEFF4),
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.all(4),
      child: Stack(
        children: [
          // Sliding white pill indicator
          AnimatedAlign(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeInOut,
            alignment:
                isPersonal ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Tab buttons row (sits on top of the pill)
          Row(
            children: [
              // Personal tab
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ref.read(homeModeProvider.notifier).state =
                        HomeMode.personal;
                  },
                  child: SizedBox(
                    height: double.infinity,
                    child: Center(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 200),
                        style: TextStyle(
                          color: isPersonal
                              ? const Color(0xFF0B0B0F)
                              : const Color(0xFF8E8E96),
                          fontSize: 14,
                          fontWeight: isPersonal
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                        child: Text(context.t('group.personal')),
                      ),
                    ),
                  ),
                ),
              ),

              // Group tab
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticFeedback.selectionClick();
                    ref.read(homeModeProvider.notifier).state = HomeMode.group;
                  },
                  child: SizedBox(
                    height: double.infinity,
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (hasGroup) ...[
                            // Mini avatar — 1 circle if solo, 2 if paired
                            SizedBox(
                              width: memberCount > 1 ? 28 : 16,
                              height: 20,
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 0,
                                    child: Container(
                                      width: 16,
                                      height: 16,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEAE3F8),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                  ),
                                  if (memberCount > 1)
                                    Positioned(
                                      left: 10,
                                      child: Container(
                                        width: 16,
                                        height: 16,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFD7F4E5),
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                            color: Colors.white,
                                            width: 1.5,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 4),
                          ],
                          AnimatedDefaultTextStyle(
                            duration: const Duration(milliseconds: 200),
                            style: TextStyle(
                              color: !isPersonal
                                  ? const Color(0xFF0B0B0F)
                                  : const Color(0xFF8E8E96),
                              fontSize: 14,
                              fontWeight: !isPersonal
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                            ),
                            child: Text(context.t('group.group')),
                          ),
                        ],
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
