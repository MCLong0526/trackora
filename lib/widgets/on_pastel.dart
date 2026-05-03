import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Forces all *inherited* text and icon colors inside [child] to the
/// light-mode ink palette so content sitting on the brand pastel cards
/// (mint, lilac, peach, butter, blush, sky, sage, sand) stays readable in
/// both light and dark themes.
///
/// Only inherited colors are overridden — widgets that pass an explicit
/// color (e.g. `style: TextStyle(color: AppColors.expense)`) keep theirs.
class OnPastel extends StatelessWidget {
  final Widget child;
  const OnPastel({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final adjusted = base.textTheme.apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    );
    return Theme(
      data: base.copyWith(
        textTheme: adjusted,
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: AppColors.ink),
        child: IconTheme.merge(
          data: const IconThemeData(color: AppColors.ink),
          child: child,
        ),
      ),
    );
  }
}
