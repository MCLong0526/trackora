import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Wraps a screen in a sticky header + scrollable body pattern.
///
/// The header stays pinned at the top. When the body is scrolled past
/// the top edge a thin divider line fades in beneath the header,
/// visually separating it from the content below (iOS-style).
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
  bool _scrolled = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  void _onScroll() {
    final scrolled = _scrollController.offset > 0;
    if (scrolled != _scrolled) setState(() => _scrolled = scrolled);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: brand.background,
            border: Border(
              bottom: BorderSide(
                color: isDark
                    ? Colors.white.withValues(alpha: _scrolled ? 0.09 : 0.0)
                    : Colors.black.withValues(alpha: _scrolled ? 0.07 : 0.0),
                width: 0.5,
              ),
            ),
          ),
          child: widget.header,
        ),
        Expanded(child: widget.bodyBuilder(_scrollController)),
      ],
    );
  }
}
