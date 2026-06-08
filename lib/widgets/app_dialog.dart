import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// A single action button in an [showAppDialog].
class AppDialogAction {
  final String label;

  /// Optional side-effect run when tapped. It is awaited *before* the dialog
  /// closes, so async work (e.g. resending an email) completes while the
  /// dialog is still on screen.
  final FutureOr<void> Function()? onTap;
  final bool isPrimary;
  final bool isDestructive;

  const AppDialogAction({
    required this.label,
    this.onTap,
    this.isPrimary = false,
    this.isDestructive = false,
  });
}

/// Shows a premium, iOS-style dialog with a scale + fade entrance animation —
/// a branded replacement for [CupertinoAlertDialog].
Future<void> showAppDialog({
  required BuildContext context,
  required String title,
  required String message,
  IconData icon = CupertinoIcons.checkmark_seal_fill,
  Color accent = const Color(0xFF0066CC),
  List<AppDialogAction> actions = const [],
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black.withValues(alpha: 0.40),
    transitionDuration: const Duration(milliseconds: 320),
    pageBuilder: (ctx, a1, a2) => const SizedBox.shrink(),
    transitionBuilder: (ctx, anim, secondary, child) {
      final v = anim.value.clamp(0.0, 1.0);
      final scale = 0.82 + 0.18 * Curves.easeOutBack.transform(v);
      return Opacity(
        opacity: Curves.easeOut.transform(v),
        child: Transform.scale(
          scale: scale,
          child: _AppDialogBody(
            title: title,
            message: message,
            icon: icon,
            accent: accent,
            actions: actions,
          ),
        ),
      );
    },
  );
}

class _AppDialogBody extends StatelessWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color accent;
  final List<AppDialogAction> actions;

  const _AppDialogBody({
    required this.title,
    required this.message,
    required this.icon,
    required this.accent,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Material(
          color: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 340),
            child: Container(
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 40,
                    offset: const Offset(0, 18),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
                    child: Column(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: accent, size: 26),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          title,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          message,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.4,
                            color: brand.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (actions.isNotEmpty) ...[
                    Divider(height: 1, thickness: 1, color: brand.divider),
                    IntrinsicHeight(
                      child: Row(
                        children: [
                          for (var i = 0; i < actions.length; i++) ...[
                            if (i > 0)
                              VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: brand.divider,
                              ),
                            Expanded(child: _ActionButton(action: actions[i], accent: accent)),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final AppDialogAction action;
  final Color accent;
  const _ActionButton({required this.action, required this.accent});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final color = action.isDestructive
        ? AppColors.expense
        : (action.isPrimary ? accent : brand.inkSoft);
    return InkWell(
      onTap: () async {
        // Await any side-effect before dismissing so async work (e.g. resend)
        // finishes while the dialog is still in the tree.
        await action.onTap?.call();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 15),
        child: Center(
          child: Text(
            action.label,
            style: TextStyle(
              fontSize: 16,
              fontWeight: action.isPrimary ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ),
      ),
    );
  }
}
