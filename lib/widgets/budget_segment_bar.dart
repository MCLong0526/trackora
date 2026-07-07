import 'package:flutter/material.dart';

import '../services/money_format.dart';

/// Slice colour for a budget category: the category accent softened toward its
/// own pastel background so the bar matches the app's light category palette
/// instead of reading as a block of dark accents.
Color budgetSliceColor(Color accent, Color background) =>
    Color.lerp(accent, background, 0.4)!;

/// One coloured slice of a [BudgetSegmentBar] — a category's spend.
class BudgetSegment {
  final String name;
  final double amount;
  final Color color;
  const BudgetSegment({
    required this.name,
    required this.amount,
    required this.color,
  });
}

/// iOS-storage-style budget bar: a single rounded track filled with one
/// coloured slice per category, with the remaining budget shown in the empty
/// tail. When spend exceeds the budget the slices fill the whole bar (scaled to
/// total spend) so the category mix still reads.
class BudgetSegmentBar extends StatelessWidget {
  final List<BudgetSegment> segments;
  final double totalBudget;
  final double totalSpent;
  final String symbol;
  final double height;

  /// Tapped slice's category name. When null the bar isn't interactive.
  final void Function(String name)? onSegmentTap;

  const BudgetSegmentBar({
    super.key,
    required this.segments,
    required this.totalBudget,
    required this.totalSpent,
    required this.symbol,
    this.height = 30,
    this.onSegmentTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final over = totalSpent > totalBudget + 0.005;
    final remaining = totalBudget - totalSpent;
    final trackColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFE9E9EC);
    final remainingInk = isDark ? Colors.white : const Color(0xFF1C1C1E);

    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            // Over budget → scale slices to total spend so they fill the bar.
            final denom = over ? totalSpent : totalBudget;
            // Thin separator so adjacent slices in the same/similar colour stay
            // distinguishable (matches the iOS storage bar's hairline gaps).
            const sep = 1.5;
            final sepColor = isDark ? const Color(0xFF1C1C1E) : Colors.white;
            final drawn = segments.where((s) => s.amount > 0).toList();
            final slices = <Widget>[];
            double used = 0;
            if (denom > 0 && w > 0) {
              for (var i = 0; i < drawn.length; i++) {
                if (i > 0 && used + sep < w) {
                  slices.add(Container(width: sep, color: sepColor));
                  used += sep;
                }
                var segW = w * (drawn[i].amount / denom);
                if (used + segW > w) segW = w - used;
                if (segW <= 0.5) continue;
                used += segW;
                final name = drawn[i].name;
                Widget slice = Container(width: segW, color: drawn[i].color);
                if (onSegmentTap != null) {
                  slice = GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onSegmentTap!(name),
                    child: slice,
                  );
                }
                slices.add(slice);
                if (used >= w) break;
              }
            }
            final remainingW = w - used;
            return Stack(
              children: [
                Positioned.fill(child: Container(color: trackColor)),
                Row(children: slices),
                if (!over && remaining > 0 && remainingW > 44)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: remainingW,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        child: Text(
                          formatMoney(symbol, remaining),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: height >= 26 ? 13 : 11,
                            fontWeight: FontWeight.w700,
                            color: remainingInk,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
