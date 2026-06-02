import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Wraps a screen in a sticky header + scrollable body pattern.
///
/// The header stays pinned at the top. As the user scrolls, a gradient
/// fades in at the top of the body so content vanishes softly behind
/// the header edge instead of cutting off at a hard line.
class StickyHeaderScaffold extends StatefulWidget {
  final Widget header;
  final Widget Function(ScrollController controller) bodyBuilder;

  const StickyHeaderScaffold({
    super.key,
    required this.header,
    required this.bodyBuilder,
  });

  @override
  State<StickyHeaderScaffold> createState() => _StickyHeaderScaffoldState();
}

class _StickyHeaderScaffoldState extends State<StickyHeaderScaffold> {
  final _scrollController = ScrollController();
  double _fadeRatio = 0.0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final ratio = (_scrollController.offset / 24.0).clamp(0.0, 1.0);
    if (ratio != _fadeRatio) setState(() => _fadeRatio = ratio);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.header,
        Expanded(
          child: Stack(
            children: [
              widget.bodyBuilder(_scrollController),
              // Gradient fade — content dissolves into the header colour as it scrolls up
              if (_fadeRatio > 0)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: IgnorePointer(
                    child: Container(
                      height: 32,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            brand.background.withValues(alpha: _fadeRatio),
                            brand.background.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
