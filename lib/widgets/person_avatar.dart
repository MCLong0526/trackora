import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

const _pastelColors = [
  AppColors.lilac,
  AppColors.mint,
  AppColors.peach,
  AppColors.butter,
  AppColors.blush,
  AppColors.sky,
  AppColors.sage,
  AppColors.sand,
];

/// Deterministic 0-7 color index from [name].
int personColorIndex(String name) {
  if (name.isEmpty) return 0;
  return name.codeUnits.fold(0, (sum, c) => sum + c) % _pastelColors.length;
}

/// Background color for a person avatar.
Color personAvatarBg(int colorIndex) =>
    _pastelColors[colorIndex.clamp(0, _pastelColors.length - 1)];

/// Circular avatar showing up to 2 initials on a brand pastel background.
///
/// If [colorIndex] is omitted it is derived deterministically from [name]
/// so the same name always maps to the same color across the app.
class PersonAvatar extends StatelessWidget {
  final String name;
  final int? colorIndex;
  final String? emoji;
  final double size;

  const PersonAvatar({
    super.key,
    required this.name,
    this.colorIndex,
    this.emoji,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final idx = colorIndex ?? personColorIndex(name);
    final bg = personAvatarBg(idx);
    final hasEmoji = emoji != null && emoji!.isNotEmpty;
    final fs = hasEmoji
        ? (size * 0.52).clamp(12.0, 30.0)
        : (size * 0.38).clamp(11.0, 24.0);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        hasEmoji ? emoji! : _initials(name),
        style: TextStyle(
          fontSize: fs,
          fontWeight: hasEmoji ? FontWeight.normal : FontWeight.w600,
          color: brand.ink,
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
