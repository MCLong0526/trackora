import 'package:flutter/widgets.dart';

/// Wraps a scrollable [child] (typically a `ListView`) with gradient fade
/// edges that blend into [fadeColor] — usually the screen background.
///
/// The top fade only appears once the list has been scrolled away from the
/// very top, so it never covers the first item while at rest (the original
/// problem this widget solves). The bottom fade is always present; because it
/// is painted in the background colour it is invisible over empty space and
/// only "softens" content that overflows past the bottom edge.
///
/// Uses a [NotificationListener] rather than owning a [ScrollController], so it
/// can wrap any existing scrollable without re-wiring its controller.
class FadingEdgeList extends StatefulWidget {
  /// The scrollable content (e.g. a `ListView`, `CustomScrollView`, ...).
  final Widget child;

  /// Colour the edges fade into — pass the screen background.
  final Color fadeColor;

  /// Height of the top fade band.
  final double topHeight;

  /// Height of the bottom fade band.
  final double bottomHeight;

  const FadingEdgeList({
    super.key,
    required this.child,
    required this.fadeColor,
    this.topHeight = 20,
    this.bottomHeight = 48,
  });

  @override
  State<FadingEdgeList> createState() => _FadingEdgeListState();
}

class _FadingEdgeListState extends State<FadingEdgeList> {
  bool _atTop = true;

  bool _onScroll(ScrollNotification n) {
    // Ignore nested horizontal scrollables (e.g. carousels) — only the main
    // vertical list should drive the top fade.
    if (n.metrics.axis != Axis.vertical) return false;
    final atTop = n.metrics.pixels <= n.metrics.minScrollExtent + 1;
    if (atTop != _atTop) setState(() => _atTop = atTop);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.fadeColor;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: _onScroll,
          child: widget.child,
        ),
        // Top fade — only once scrolled away from the top.
        if (!_atTop)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: widget.topHeight,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [c, c.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
        // Bottom fade — always; invisible over empty background.
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: widget.bottomHeight,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [c, c.withValues(alpha: 0)],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
