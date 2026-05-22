import 'package:flutter/material.dart';
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
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () =>
                  ref.read(homeModeProvider.notifier).state = HomeMode.personal,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: mode == HomeMode.personal
                      ? brand.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: mode == HomeMode.personal
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    context.t('group.personal'),
                    style: TextStyle(
                      color: mode == HomeMode.personal
                          ? brand.ink
                          : brand.inkSoft,
                      fontSize: 13,
                      fontWeight: mode == HomeMode.personal
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () =>
                  ref.read(homeModeProvider.notifier).state = HomeMode.group,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: mode == HomeMode.group
                      ? brand.surface
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: mode == HomeMode.group
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    context.t('group.group'),
                    style: TextStyle(
                      color: mode == HomeMode.group
                          ? brand.ink
                          : brand.inkSoft,
                      fontSize: 13,
                      fontWeight: mode == HomeMode.group
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
