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
/// Set [animated] to true to make the emoji continuously pulse (scale 0.92↔1.08).
class PersonAvatar extends StatefulWidget {
  final String name;
  final int? colorIndex;
  final String? emoji;
  final double size;
  final bool animated;

  const PersonAvatar({
    super.key,
    required this.name,
    this.colorIndex,
    this.emoji,
    this.size = 40,
    this.animated = false,
  });

  @override
  State<PersonAvatar> createState() => _PersonAvatarState();
}

class _PersonAvatarState extends State<PersonAvatar>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<double>? _scale;

  @override
  void initState() {
    super.initState();
    _setupAnimation();
  }

  @override
  void didUpdateWidget(PersonAvatar old) {
    super.didUpdateWidget(old);
    if (old.animated != widget.animated || old.emoji != widget.emoji) {
      _ctrl?.dispose();
      _ctrl = null;
      _scale = null;
      _setupAnimation();
    }
  }

  void _setupAnimation() {
    final hasEmoji = widget.emoji != null && widget.emoji!.isNotEmpty;
    if (widget.animated && hasEmoji) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 2000),
      )..repeat(reverse: true);
      _scale = Tween<double>(begin: 0.92, end: 1.08).animate(
        CurvedAnimation(parent: _ctrl!, curve: Curves.easeInOut),
      );
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final idx = widget.colorIndex ?? personColorIndex(widget.name);
    final bg = personAvatarBg(idx);
    final hasEmoji = widget.emoji != null && widget.emoji!.isNotEmpty;
    final fs = hasEmoji
        ? (widget.size * 0.52).clamp(12.0, 30.0)
        : (widget.size * 0.38).clamp(11.0, 24.0);

    Widget content = Text(
      hasEmoji ? widget.emoji! : _initials(widget.name),
      style: TextStyle(
        fontSize: fs,
        fontWeight: hasEmoji ? FontWeight.normal : FontWeight.w600,
        color: brand.ink,
      ),
    );

    if (_scale != null) {
      content = ScaleTransition(scale: _scale!, child: content);
    }

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: content,
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
