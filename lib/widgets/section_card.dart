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

/// iOS-26-style frosted circular toolbar button. Used for *every* top-right
/// header action (FX, manage, eye, back…) so they all share one colour, size
/// and shape — translucent fill + hairline edge + soft lift.
class GlassCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double size;
  final double? iconSize;
  final Color? foreground;

  const GlassCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size = 40,
    this.iconSize,
    this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.62),
          shape: BoxShape.circle,
          border: Border.all(
            color: isDark
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.80),
            width: 0.8,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Icon(
          icon,
          size: iconSize ?? size * 0.46,
          color: foreground ?? brand.ink.withValues(alpha: 0.78),
        ),
      ),
    );
  }
}
