import 'package:flutter/widgets.dart';

/// Renders an amount string, replaced with bank-style asterisks when
/// `visible` is false. The currency symbol stays readable so layout
/// width is roughly the same and the user still sees which currency
/// the row represents.
///
/// Example: `RM 1,234.50` → `RM ****` when hidden.
///
/// Calculations elsewhere keep using the real number — this widget is
/// purely cosmetic.
class MaskedAmount extends StatelessWidget {
  final String visibleText;
  final bool visible;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Currency symbol prefix to keep visible while the rest is masked.
  /// Pass `''` if the visibleText already has no symbol.
  final String currencyPrefix;

  /// Mask character count (default 4 — `****`).
  final int maskLength;

  const MaskedAmount({
    super.key,
    required this.visibleText,
    required this.visible,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.currencyPrefix = '',
    this.maskLength = 4,
  });

  @override
  Widget build(BuildContext context) {
    final mask = '*' * maskLength;
    final display = visible
        ? visibleText
        : currencyPrefix.isEmpty
            ? mask
            : '$currencyPrefix $mask';
    return Text(
      display,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
