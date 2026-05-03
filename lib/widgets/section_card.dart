import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'on_pastel.dart';

/// A rounded surface card.
///
/// When a custom [color] is provided AND that color is a light pastel
/// (luminance > 0.5), the child is automatically wrapped in [OnPastel]
/// so inherited text/icon colors stay dark — even in dark mode where
/// the default text color would otherwise be white. Pass
/// `pastel: false` to opt out for explicitly-coloured dark cards (e.g.
/// the Total Balance hero).
class SectionCard extends StatelessWidget {
  final Widget child;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool? pastel;

  const SectionCard({
    super.key,
    required this.child,
    this.color,
    this.padding = const EdgeInsets.all(20),
    this.radius = AppRadius.card,
    this.onTap,
    this.pastel,
  });

  bool _shouldForceDarkInk(Color bg) {
    if (pastel != null) return pastel!;
    return bg.computeLuminance() > 0.55;
  }

  @override
  Widget build(BuildContext context) {
    final bg = color ?? context.brand.surface;
    final content = _shouldForceDarkInk(bg) ? OnPastel(child: child) : child;
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: content,
    );
    if (onTap == null) return card;
    return GestureDetector(onTap: onTap, child: card);
  }
}

class CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final Color? background;
  final Color? foreground;
  final double size;

  const CircleIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.background,
    this.foreground,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background ?? brand.surface,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: foreground ?? brand.ink),
      ),
    );
  }
}
