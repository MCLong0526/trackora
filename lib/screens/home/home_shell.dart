import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/i18n.dart';
import '../../services/prefs_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import 'assets_screen.dart';
import 'dashboard_screen.dart';
import 'statistics_screen.dart';
import 'budget_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _index = 0;

  static const _screens = <Widget>[
    _HomeTabWrapper(),
    StatisticsScreen(),
    BudgetScreen(),
    AssetsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _maybeShowFirstLaunchCurrencyPicker();
  }

  Future<void> _maybeShowFirstLaunchCurrencyPicker() async {
    final prefs = ref.read(prefsServiceProvider);
    final done = await prefs.isFirstLaunchDone();
    if (done || !mounted) return;
    await prefs.markFirstLaunchDone();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final currentCode = await prefs.currencyCode();
      if (!mounted) return;
      await _showFirstLaunchCurrencySheet(currentCode);
    });
  }

  Future<void> _showFirstLaunchCurrencySheet(String currentCode) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _FirstLaunchCurrencySheet(
        currentCode: currentCode,
        onPicked: (code) async {
          final sym = kSupportedCurrencies[code] ?? code;
          await ref.read(prefsServiceProvider).setCurrency(code, sym);
          ref.invalidate(currencySymbolProvider);
          ref.invalidate(currencyCodeProvider);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(homeTabIndexProvider, (_, next) {
      if (next != _index) setState(() => _index = next);
    });
    final brand = context.brand;
    return Scaffold(
      backgroundColor: brand.background,
      extendBody: true,
      bottomNavigationBar: _BottomBar(
        index: _index,
        onTap: (i) {
          if (i == _index) return;
          ref.read(homeTabIndexProvider.notifier).state = i;
          setState(() => _index = i);
        },
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, animation) {
          final isEntering = child.key == ValueKey(_index);
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOut,
            ),
            child: ScaleTransition(
              scale: Tween<double>(
                begin: isEntering ? 0.97 : 1.02,
                end: 1.0,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ),
              ),
              child: child,
            ),
          );
        },
        child: KeyedSubtree(key: ValueKey(_index), child: _screens[_index]),
      ),
    );
  }
}

class _BottomBar extends StatefulWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.index, required this.onTap});

  @override
  State<_BottomBar> createState() => _BottomBarState();
}

class _BottomBarState extends State<_BottomBar> with TickerProviderStateMixin {
  int? _dragIndex;
  bool _isDragging = false;
  bool _isTouching = false;
  double _barWidth = 300;
  double? _touchX;
  double _dragStretch = 0;
  double _dragDirection = 0;
  bool _initialized = false;
  // Pill slide animation
  late final AnimationController _pillCtrl;
  double _fromX = 0;
  double _toX = 0;
  Curve _curve = Curves.easeOutBack;

  // Liquid glass expand animation while the finger is on the bar.
  late final AnimationController _glassCtrl;

  // Floating glass pill height; it only grows subtly while touched.
  static const _compactH = 64.0;
  static const _liquidH = 68.0;
  // Selected capsule size: covers both icon and label, then jelly-stretches.
  static const _lensWBase = 82.0;
  static const _lensHBase = 56.0;
  static const _lensWExpanded = 94.0;
  static const _lensHExpanded = 62.0;

  @override
  void initState() {
    super.initState();
    _pillCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _glassCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
  }

  @override
  void didUpdateWidget(_BottomBar old) {
    super.didUpdateWidget(old);
    if (!_isDragging && old.index != widget.index) {
      _animateToTab(widget.index, fast: false);
    }
  }

  @override
  void dispose() {
    _pillCtrl.dispose();
    _glassCtrl.dispose();
    super.dispose();
  }

  double _tabCenterX(int idx) => (_barWidth / 4) * (idx + 0.5);

  double get _currentX {
    if (_isTouching && _touchX != null) return _clampBubbleX(_touchX!);
    final t = _curve.transform(_pillCtrl.value.clamp(0.0, 1.0));
    return _fromX + (_toX - _fromX) * t;
  }

  double _clampBubbleX(double x) {
    final inset = _lensWBase / 2;
    return x.clamp(inset, _barWidth - inset).toDouble();
  }

  void _animateToTab(int idx, {required bool fast}) {
    final targetX = _tabCenterX(idx);
    _fromX = _currentX;
    _toX = targetX;
    _curve = fast ? Curves.easeOutCubic : Curves.easeOutBack;
    _pillCtrl
      ..stop()
      ..duration = fast
          ? const Duration(milliseconds: 150)
          : const Duration(milliseconds: 420)
      ..value = 0
      ..forward();
  }

  int _indexFromLocalX(double x) {
    final itemW = _barWidth / 4;
    if (x < 0) return 0;
    for (var i = 0; i < 4; i++) {
      if (x < itemW * (i + 1)) return i;
    }
    return 3;
  }

  void _touchGlass(double localX) {
    final idx = _indexFromLocalX(localX);
    final deltaIndex = idx - widget.index;
    _animateToTab(idx, fast: false);
    setState(() {
      _isTouching = true;
      _touchX = null;
      _dragIndex = idx;
      _dragStretch = deltaIndex == 0 ? 0 : 0.3;
      _dragDirection = deltaIndex == 0 ? 0 : deltaIndex.sign.toDouble();
    });
    HapticFeedback.lightImpact();
    _glassCtrl.animateTo(
      1.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _handleTap(int idx) {
    final deltaIndex = idx - widget.index;
    setState(() {
      _isTouching = true;
      _isDragging = false;
      _touchX = null;
      _dragIndex = idx;
      _dragDirection = deltaIndex == 0 ? 0 : deltaIndex.sign.toDouble();
      _dragStretch = deltaIndex == 0 ? 0 : 0.55;
    });
    _glassCtrl.animateTo(
      1.0,
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
    );
    _animateToTab(idx, fast: false);
    widget.onTap(idx);
    Future<void>.delayed(const Duration(milliseconds: 260), () {
      if (!mounted || _isDragging) return;
      _collapseGlass();
    });
  }

  void _collapseGlass() {
    final settledX = _currentX;
    setState(() {
      _isTouching = false;
      _isDragging = false;
      _dragIndex = null;
      _touchX = null;
      _dragStretch = 0;
      _dragDirection = 0;
    });
    _fromX = settledX;
    _toX = _tabCenterX(widget.index);
    _curve = Curves.easeOutBack;
    _pillCtrl
      ..stop()
      ..duration = const Duration(milliseconds: 460)
      ..value = 0
      ..forward();
    _glassCtrl.animateTo(
      0.0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  void _moveTouch(double localX, {required bool isDrag}) {
    final idx = _indexFromLocalX(localX);
    final changedTab = idx != _dragIndex;
    final previousX = _touchX ?? localX;
    final deltaX = localX - previousX;
    setState(() {
      _isDragging = isDrag;
      _isTouching = true;
      _touchX = localX;
      _dragIndex = idx;
      _dragDirection = deltaX == 0 ? _dragDirection : deltaX.sign;
      _dragStretch = (deltaX.abs() / 24).clamp(0.0, 1.0);
    });
    if (changedTab) {
      HapticFeedback.selectionClick();
      widget.onTap(idx);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeIndex = _isTouching
        ? (_dragIndex ?? widget.index)
        : widget.index;

    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final bottomPad = safeBottom > 0
        ? (safeBottom * 0.52).roundToDouble() + 8.0
        : 16.0;

    return Material(
      color: Colors.transparent,
      child: Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPad),
      child: AnimatedBuilder(
        // Single builder listening to both animations
        animation: Listenable.merge([_pillCtrl, _glassCtrl]),
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_glassCtrl.value);
          final barH = lerpDouble(_compactH, _liquidH, t)!;
          final jelly = Curves.easeOut.transform(_dragStretch) * t;
          final lensBaseW = lerpDouble(_lensWBase, _lensWExpanded, t)!;
          final lensBaseH = lerpDouble(_lensHBase, _lensHExpanded, t)!;
          final lensW = lensBaseW + lerpDouble(0, 8, jelly)!;
          final lensH = lensBaseH - lerpDouble(0, 3, jelly)!;
          final cx = _currentX;
          final blurSigma = lerpDouble(24.0, 36.0, t)!;
          // Dark mode: rich dark frosted glass matching WhatsApp reference
          final bgTopAlpha = isDark
              ? lerpDouble(0.12, 0.16, t)!
              : lerpDouble(0.42, 0.50, t)!;
          final bgBotAlpha = isDark
              ? lerpDouble(0.06, 0.09, t)!
              : lerpDouble(0.28, 0.34, t)!;
          final borderAlpha = isDark
              ? lerpDouble(0.20, 0.28, t)!
              : lerpDouble(0.68, 0.82, t)!;
          final shadowAlpha = isDark
              ? lerpDouble(0.26, 0.34, t)!
              : lerpDouble(0.08, 0.12, t)!;
          final specularPeak = isDark
              ? lerpDouble(0.22, 0.32, t)!
              : lerpDouble(0.48, 0.62, t)!;

          // Stack with Clip.none allows circle to overflow bar bounds
          return SizedBox(
            height: barH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // ── Layer 1: Glass bar background (clipped pill) ──────────
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(36),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(
                        sigmaX: blurSigma,
                        sigmaY: blurSigma,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(alpha: bgTopAlpha),
                              Colors.white.withValues(alpha: bgBotAlpha),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(36),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: borderAlpha),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: shadowAlpha,
                              ),
                              blurRadius: lerpDouble(24.0, 34.0, t)!,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: shadowAlpha * 0.45,
                              ),
                              blurRadius: lerpDouble(7.0, 10.0, t)!,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Stack(
                          children: [
                            // Specular highlight line at top edge
                            Positioned(
                              top: 0,
                              left: 12,
                              right: 12,
                              height: 1.0,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [
                                      Colors.transparent,
                                      Colors.white.withValues(
                                        alpha: specularPeak - 0.08,
                                      ),
                                      Colors.white.withValues(
                                        alpha: specularPeak,
                                      ),
                                      Colors.white.withValues(
                                        alpha: specularPeak - 0.08,
                                      ),
                                      Colors.transparent,
                                    ],
                                    stops: const [0.0, 0.2, 0.5, 0.8, 1.0],
                                  ),
                                  borderRadius: BorderRadius.circular(1),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                // Layer 2: glass lens indicator, behind nav items and allowed
                // to overflow the bar like the WhatsApp reference.
                Positioned(
                  left: cx - lensW / 2,
                  top: (barH - lensH) / 2 - lerpDouble(0, 2, t)!,
                  width: lensW,
                  height: lensH,
                  child: _LiquidGlassLens(
                    progress: t,
                    isDark: isDark,
                    jelly: jelly,
                    direction: _dragDirection,
                  ),
                ),
                // ── Layer 3: Nav items + gestures (renders above circle) ──────
                LayoutBuilder(
                  builder: (ctx, constraints) {
                    _barWidth = constraints.maxWidth;
                    if (!_initialized) {
                      _fromX = _tabCenterX(widget.index);
                      _toX = _fromX;
                      _initialized = true;
                    }
                    return Listener(
                      onPointerDown: (event) =>
                          _touchGlass(event.localPosition.dx),
                      onPointerMove: (event) =>
                          _moveTouch(event.localPosition.dx, isDrag: true),
                      onPointerUp: (_) {
                        if (_isDragging) _collapseGlass();
                      },
                      onPointerCancel: (_) => _collapseGlass(),
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onHorizontalDragStart: (d) {
                          HapticFeedback.mediumImpact();
                          _moveTouch(d.localPosition.dx, isDrag: true);
                        },
                        onHorizontalDragUpdate: (d) {
                          if (!_isDragging) return;
                          _moveTouch(d.localPosition.dx, isDrag: true);
                        },
                        onHorizontalDragEnd: (_) {
                          _collapseGlass();
                        },
                        onHorizontalDragCancel: () {
                          _collapseGlass();
                        },
                        child: Row(
                          children: [
                            _NavItem(
                              icon: CupertinoIcons.house_fill,
                              label: context.t('tab.home'),
                              selected: activeIndex == 0,
                              onTap: () => _handleTap(0),
                              isDark: isDark,
                              glassExpand: t,
                            ),
                            _NavItem(
                              icon: CupertinoIcons.chart_bar_alt_fill,
                              label: context.t('tab.stats'),
                              selected: activeIndex == 1,
                              onTap: () => _handleTap(1),
                              isDark: isDark,
                              glassExpand: t,
                            ),
                            _NavItem(
                              icon: CupertinoIcons.creditcard,
                              label: context.t('tab.money'),
                              selected: activeIndex == 2,
                              onTap: () => _handleTap(2),
                              isDark: isDark,
                              glassExpand: t,
                            ),
                            _NavItem(
                              icon: CupertinoIcons.chart_pie_fill,
                              label: context.t('tab.assets'),
                              selected: activeIndex == 3,
                              onTap: () => _handleTap(3),
                              isDark: isDark,
                              glassExpand: t,
                            ),
                          ],
                        ),
                      ), // GestureDetector
                    ); // Listener
                  },
                ),
              ],
            ),
          );
        },
      ),
    ));
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final double glassExpand; // 0.0 = compact, 1.0 = liquid expanded

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
    required this.glassExpand,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    const accent = AppActionBlue.color;
    final iconColor = selected
        ? accent
        : (isDark
              ? Colors.white.withValues(alpha: 0.48)
              : brand.ink.withValues(alpha: 0.38));
    final labelColor = selected
        ? accent
        : (isDark
              ? Colors.white.withValues(alpha: 0.42)
              : brand.ink.withValues(alpha: 0.36));
    final iconSz = lerpDouble(25.0, 26.0, glassExpand)!;
    final labelSz = lerpDouble(10.5, 11.0, glassExpand)!;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 1.0, end: selected ? 1.08 : 1.0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              builder: (ctx, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: Icon(
                  icon,
                  key: ValueKey(selected),
                  color: iconColor,
                  size: iconSz,
                ),
              ),
            ),
            SizedBox(height: lerpDouble(3.0, 4.0, glassExpand)!),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: labelSz,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: labelColor,
                letterSpacing: 0,
              ),
              child: Text(label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiquidGlassLens extends StatelessWidget {
  final double progress;
  final bool isDark;
  final double jelly;
  final double direction;

  const _LiquidGlassLens({
    required this.progress,
    required this.isDark,
    required this.jelly,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    final rimOpacity = lerpDouble(0.0, 1.0, t)!;
    final blur = lerpDouble(22.0, 34.0, t)!;
    final radiusValue = lerpDouble(999, 30, t)!;
    final radius = BorderRadius.circular(radiusValue);
    final glowShift = lerpDouble(0, 6, jelly)! * direction;
    final tintTop = isDark
        ? lerpDouble(0.22, 0.30, t)!
        : lerpDouble(0.70, 0.82, t)!;
    final tintBottom = isDark
        ? lerpDouble(0.12, 0.18, t)!
        : lerpDouble(0.50, 0.60, t)!;

    return Transform.translate(
      offset: Offset(glowShift * 0.16, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: isDark
                    ? lerpDouble(0.20, 0.30, t)!
                    : lerpDouble(0.06, 0.11, t)!,
              ),
              blurRadius: lerpDouble(12, 20, t)!,
              offset: Offset(0, lerpDouble(3, 7, t)!),
            ),
            BoxShadow(
              color: Colors.white.withValues(
                alpha: isDark
                    ? lerpDouble(0.10, 0.16, t)!
                    : lerpDouble(0.34, 0.48, t)!,
              ),
              blurRadius: lerpDouble(5, 8, t)!,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: radius,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: tintTop),
                        Colors.white.withValues(alpha: tintBottom),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: isDark
                            ? lerpDouble(0.28, 0.42, t)!
                            : lerpDouble(0.78, 0.94, t)!,
                      ),
                      width: lerpDouble(0.8, 1.1, t)!,
                    ),
                  ),
                ),
              ),
            ),
            CustomPaint(
              painter: _LiquidGlassRimPainter(
                opacity: rimOpacity,
                isDark: isDark,
                cornerRadius: radiusValue,
                jelly: jelly,
                direction: direction,
              ),
            ),
            Positioned(
              left: 12 + glowShift.clamp(-3.0, 3.0),
              top: 8,
              right: 14 - glowShift.clamp(-3.0, 3.0),
              height: 13,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.0),
                        Colors.white.withValues(
                          alpha: lerpDouble(0.08, 0.22, t)!,
                        ),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 8,
              right: 8,
              bottom: 5,
              height: 8,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    gradient: LinearGradient(
                      begin: direction >= 0
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      end: direction >= 0
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      colors: [
                        const Color(0xFF4FE6FF).withValues(alpha: 0.0),
                        const Color(0xFF4FE6FF).withValues(alpha: 0.18 * t),
                        const Color(0xFFFFD15C).withValues(alpha: 0.15 * t),
                        const Color(0xFF7C4DFF).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiquidGlassRimPainter extends CustomPainter {
  final double opacity;
  final bool isDark;
  final double cornerRadius;
  final double jelly;
  final double direction;

  const _LiquidGlassRimPainter({
    required this.opacity,
    required this.isDark,
    required this.cornerRadius,
    required this.jelly,
    required this.direction,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final rect = Offset.zero & size;
    final stroke = size.shortestSide * 0.035;
    final horizontalInset = lerpDouble(0, 3.5, jelly)!;
    final rimRect = rect.deflate(stroke / 2);
    final squishRect = Rect.fromLTWH(
      rimRect.left + horizontalInset,
      rimRect.top,
      rimRect.width - horizontalInset * 2,
      rimRect.height,
    );
    final rimRRect = RRect.fromRectAndRadius(
      squishRect,
      Radius.circular(cornerRadius),
    );

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..shader = SweepGradient(
        startAngle: direction >= 0 ? -0.9 : -1.15,
        endAngle: direction >= 0 ? 5.55 : 5.25,
        colors: [
          Colors.transparent,
          const Color(0xFF4FE6FF).withValues(alpha: 0.68 * opacity),
          Colors.white.withValues(alpha: (isDark ? 0.88 : 0.96) * opacity),
          const Color(0xFFFFD15C).withValues(alpha: 0.66 * opacity),
          const Color(0xFF7C4DFF).withValues(alpha: 0.54 * opacity),
          Colors.transparent,
        ],
        stops: const [0.00, 0.12, 0.22, 0.58, 0.76, 1.00],
      ).createShader(rect);
    canvas.drawRRect(rimRRect, rimPaint);

    final innerRRect = RRect.fromRectAndRadius(
      squishRect.deflate(size.shortestSide * 0.08),
      Radius.circular(cornerRadius * 0.78),
    );
    final innerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.52
      ..color = Colors.white.withValues(alpha: 0.11 * opacity);
    canvas.drawRRect(innerRRect, innerPaint);

    final causticPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 0.62
      ..strokeCap = StrokeCap.round
      ..color = Colors.white.withValues(alpha: 0.26 * opacity);
    canvas.drawArc(
      squishRect.deflate(size.shortestSide * 0.10),
      direction >= 0 ? -1.84 : -1.62,
      1.08 + (jelly * 0.24),
      false,
      causticPaint,
    );
    canvas.drawArc(
      squishRect.deflate(size.shortestSide * 0.08),
      direction >= 0 ? 1.00 : 1.18,
      0.92 + (jelly * 0.18),
      false,
      causticPaint..color = Colors.black.withValues(alpha: 0.08 * opacity),
    );
  }

  @override
  bool shouldRepaint(covariant _LiquidGlassRimPainter oldDelegate) {
    return oldDelegate.opacity != opacity ||
        oldDelegate.isDark != isDark ||
        oldDelegate.cornerRadius != cornerRadius ||
        oldDelegate.jelly != jelly ||
        oldDelegate.direction != direction;
  }
}

// ── First-launch currency picker ─────────────────────────────────────────────

class _FirstLaunchCurrencySheet extends StatefulWidget {
  final String currentCode;
  final Future<void> Function(String code) onPicked;

  const _FirstLaunchCurrencySheet({
    required this.currentCode,
    required this.onPicked,
  });

  @override
  State<_FirstLaunchCurrencySheet> createState() =>
      _FirstLaunchCurrencySheetState();
}

class _FirstLaunchCurrencySheetState extends State<_FirstLaunchCurrencySheet> {
  late String _selected;
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = widget.currentCode;
  }

  Future<void> _confirm() async {
    setState(() => _saving = true);
    await widget.onPicked(_selected);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final entries = kSupportedCurrencies.entries
        .where(
          (e) =>
              _query.isEmpty ||
              e.key.toLowerCase().contains(_query.toLowerCase()) ||
              e.value.toLowerCase().contains(_query.toLowerCase()),
        )
        .toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 0),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.80,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: brand.inkSoft.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: brand.accentDark.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          CupertinoIcons.money_dollar_circle_fill,
                          color: brand.accentDark,
                          size: 28,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Choose your currency',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: brand.ink,
                        letterSpacing: -0.374,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'You can always change this later in Settings.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: brand.inkSoft,
                        height: 1.47,
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Search field
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: brand.background,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.search,
                            size: 16,
                            color: brand.inkSoft,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              onChanged: (v) => setState(() => _query = v),
                              style: TextStyle(fontSize: 15, color: brand.ink),
                              decoration: InputDecoration(
                                hintText: context.t('common.searchCurrency'),
                                hintStyle: TextStyle(
                                  color: brand.inkSoft,
                                  fontSize: 15,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
              // Currency list
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final code = entries[i].key;
                    final sym = entries[i].value;
                    final selected = code == _selected;
                    return GestureDetector(
                      onTap: () => setState(() => _selected = code),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 120),
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: selected
                              ? brand.accentDark.withValues(alpha: 0.10)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: selected
                                ? brand.accentDark.withValues(alpha: 0.35)
                                : Colors.transparent,
                            width: 1.2,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: selected
                                    ? brand.accentDark.withValues(alpha: 0.15)
                                    : brand.background,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                sym,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: selected
                                      ? brand.accentDark
                                      : brand.ink,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                code,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                  color: brand.ink,
                                ),
                              ),
                            ),
                            if (selected)
                              Icon(
                                CupertinoIcons.check_mark_circled_solid,
                                size: 20,
                                color: brand.accentDark,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              // Confirm button
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                child: SizedBox(
                  height: 50,
                  child: TextButton(
                    onPressed: _saving ? null : _confirm,
                    style: TextButton.styleFrom(
                      backgroundColor: brand.accentDark,
                      foregroundColor: Colors.white,
                      shape: const StadiumBorder(),
                    ),
                    child: _saving
                        ? const CupertinoActivityIndicator(color: Colors.white)
                        : Text(
                            'Continue with ${kSupportedCurrencies[_selected] ?? _selected}  $_selected',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 17,
                            ),
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Home tab wrapper ─────────────────────────────────────────────────────────
// Always renders DashboardScreen — it handles both personal and group mode
// in-place via PersonalGroupToggle, keeping the header stable.

class _HomeTabWrapper extends StatelessWidget {
  const _HomeTabWrapper();

  @override
  Widget build(BuildContext context) => const DashboardScreen();
}
