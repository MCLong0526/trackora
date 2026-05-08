import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../screens/settings/settings_screen.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';

class ProfileAvatarButton extends ConsumerWidget {
  final double size;

  const ProfileAvatarButton({super.key, this.size = 40});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final user = ref.watch(authStateProvider).valueOrNull;
    final email = user?.email?.trim() ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : null;

    return Tooltip(
      message: 'Profile & settings',
      child: Semantics(
        button: true,
        label: 'Open profile and settings',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: AppColors.lilac,
              shape: BoxShape.circle,
              border: Border.all(
                color: brand.surface.withValues(alpha: 0.75),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: initial == null
                ? const Icon(
                    CupertinoIcons.person_crop_circle,
                    size: 21,
                    color: AppColors.ink,
                  )
                : Text(
                    initial,
                    style: TextStyle(
                      fontSize: size * 0.38,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
