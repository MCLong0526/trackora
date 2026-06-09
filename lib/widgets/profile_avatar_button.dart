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
    final offline = !(ref.watch(networkStatusProvider).valueOrNull ?? true);

    final avatar = Container(
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
    );

    return Tooltip(
      message: offline ? 'Offline — changes sync when reconnected' : 'Profile & settings',
      child: Semantics(
        button: true,
        label: offline
            ? 'Open profile and settings, currently offline'
            : 'Open profile and settings',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.push(
              context,
              CupertinoPageRoute(builder: (_) => const SettingsScreen()),
            );
          },
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              // Offline status badge — a small amber dot with a wifi-slash,
              // ringed in the surface colour so it reads on any background.
              if (offline)
                Positioned(
                  right: -1,
                  bottom: -1,
                  child: Container(
                    width: size * 0.42,
                    height: size * 0.42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B),
                      shape: BoxShape.circle,
                      border: Border.all(color: brand.surface, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      CupertinoIcons.wifi_slash,
                      size: size * 0.2,
                      color: Colors.white,
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
