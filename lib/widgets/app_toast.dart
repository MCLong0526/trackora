import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

enum AppToastType { success, error, info }

class AppToast {
  static void show(
    BuildContext context,
    String message, {
    AppToastType type = AppToastType.info,
    IconData? icon,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _AppToastWidget(
        message: message,
        type: type,
        icon: icon,
        onDone: () => entry.remove(),
      ),
    );
    overlay.insert(entry);
  }
}

class _AppToastWidget extends StatefulWidget {
  final String message;
  final AppToastType type;
  final IconData? icon;
  final VoidCallback onDone;

  const _AppToastWidget({
    required this.message,
    required this.type,
    required this.icon,
    required this.onDone,
  });

  @override
  State<_AppToastWidget> createState() => _AppToastWidgetState();
}

class _AppToastWidgetState extends State<_AppToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _fade;
  late Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _ctrl.forward();
    Future<void>.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) _ctrl.reverse().then((_) => widget.onDone());
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand = context.brand;

    final (accent, iconData) = switch (widget.type) {
      AppToastType.success => (
          AppColors.income,
          widget.icon ?? CupertinoIcons.checkmark_circle_fill,
        ),
      AppToastType.error => (
          AppColors.expense,
          widget.icon ?? CupertinoIcons.xmark_circle_fill,
        ),
      AppToastType.info => (
          brand.accentDark,
          widget.icon ?? CupertinoIcons.info_circle_fill,
        ),
    };

    final topPad = MediaQuery.viewPaddingOf(context).top;
    return Positioned(
      top: topPad + 12,
      left: 24,
      right: 24,
      child: IgnorePointer(
        child: FadeTransition(
          opacity: _fade,
          child: SlideTransition(
            position: _slide,
            child: Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    constraints: const BoxConstraints(maxWidth: 360),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.13)
                          : Colors.black.withValues(alpha: 0.07),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.white.withValues(alpha: 0.85),
                        width: 0.7,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(iconData, color: accent, size: 17),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            widget.message,
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.black,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              decoration: TextDecoration.none,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
