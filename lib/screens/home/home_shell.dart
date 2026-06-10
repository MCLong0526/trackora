import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../onboarding/onboarding_screen.dart';
import '../settings/settings_screen.dart';
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
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _maybeShowOnboarding();
  }

  /// On the very first launch of a new account, run the full onboarding
  /// flow (display name, currency, language) followed by a quick tour.
  Future<void> _maybeShowOnboarding() async {
    final prefs = ref.read(prefsServiceProvider);
    final done = await prefs.isFirstLaunchDone();
    if (done || !mounted) return;
    await prefs.markFirstLaunchDone();
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).push(
        PageRouteBuilder<void>(
          fullscreenDialog: true,
          opaque: true,
          transitionDuration: const Duration(milliseconds: 320),
          pageBuilder: (_, _, _) => const OnboardingScreen(),
          transitionsBuilder: (_, anim, _, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(homeTabIndexProvider, (_, next) {
      if (next != _index) setState(() => _index = next);
    });
    final brand = context.brand;
    final offline = !(ref.watch(networkStatusProvider).valueOrNull ?? true);
    return Scaffold(
      backgroundColor: brand.background,
      // Stack-based floating nav: no bottomNavigationBar slot so Flutter never
      // injects a canvas-color background behind the pill.
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Strip bottom safe-area padding from screens so scroll content
          // fills all the way to the screen edge and is visible behind the pill.
          MediaQuery.removePadding(
            context: context,
            removeBottom: true,
            child: AnimatedSwitcher(
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
              child: KeyedSubtree(
                key: ValueKey(_index),
                child: _screens[_index],
              ),
            ),
          ),
          // Soft fade above the bar. Kept light on purpose: the glass needs
          // real content with contrast *behind* it to refract — fading it to
          // solid background would leave nothing for the "liquid" to bend.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: 130,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      brand.background.withValues(alpha: 0),
                      brand.background.withValues(alpha: 0.40),
                    ],
                    stops: const [0.0, 1.0],
                  ),
                ),
              ),
            ),
          ),
          // Floating glass pill — purely transparent outside the pill bounds.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _BottomBar(
              index: _index,
              offline: offline,
              onTap: (i) {
                if (i == _index) return;
                ref.read(homeTabIndexProvider.notifier).state = i;
                setState(() => _index = i);
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatefulWidget {
  final int index;
  final ValueChanged<int> onTap;
  final bool offline;
  const _BottomBar({
    required this.index,
    required this.onTap,
    required this.offline,
  });

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

  // Floating glass pill height. Fixed (not animated) so the LiquidGlass
  // geometry never regenerates per-frame — animating a glass shape can spike
  // memory due to a known Flutter texture-disposal bug (see package docs).
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

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPad),
      child: AnimatedBuilder(
        // Single builder listening to both animations
        animation: Listenable.merge([_pillCtrl, _glassCtrl]),
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_glassCtrl.value);
          const barH = _liquidH;
          final jelly = Curves.easeOut.transform(_dragStretch) * t;
          final lensBaseW = lerpDouble(_lensWBase, _lensWExpanded, t)!;
          final lensBaseH = lerpDouble(_lensHBase, _lensHExpanded, t)!;
          final lensW = lensBaseW + lerpDouble(0, 8, jelly)!;
          final lensH = lensBaseH - lerpDouble(0, 3, jelly)!;
          final cx = _currentX;

          // Stack with Clip.none allows circle to overflow bar bounds
          return SizedBox(
            height: barH,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // ── Layer 1: Liquid Glass bar ─────────────────────────────
                // Real shader refraction (liquid_glass_renderer) that bends the
                // content scrolling behind the bar — it samples Flutter's own
                // backdrop, which Apple's UIGlassEffect cannot (that only blurs
                // native UIKit views, and this screen is Flutter-drawn). The
                // squircle drop shadow is drawn here in Flutter.
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: const ShapeDecoration(
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.all(Radius.circular(36)),
                      ),
                      shadows: [
                        BoxShadow(
                          color: Color(0x1F000000),
                          blurRadius: 28,
                          offset: Offset(0, 10),
                        ),
                        BoxShadow(
                          color: Color(0x0D000000),
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: _GlassBar(isDark: isDark),
                  ),
                ),
                // Layer 2: the gliding selection capsule, behind the nav items.
                Positioned(
                  left: cx - lensW / 2,
                  top: (barH - lensH) / 2,
                  width: lensW,
                  height: lensH,
                  child: _GlideCapsule(
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
                              icon: CupertinoIcons.house,
                              activeIcon: CupertinoIcons.house_fill,
                              label: context.t('tab.home'),
                              selected: activeIndex == 0,
                              onTap: () => _handleTap(0),
                              isDark: isDark,
                              glassExpand: t,
                            ),
                            _NavItem(
                              icon: CupertinoIcons.chart_bar,
                              activeIcon: CupertinoIcons.chart_bar_fill,
                              label: context.t('tab.stats'),
                              selected: activeIndex == 1,
                              onTap: () => _handleTap(1),
                              isDark: isDark,
                              glassExpand: t,
                            ),
                            _NavItem(
                              icon: CupertinoIcons.creditcard,
                              activeIcon: CupertinoIcons.creditcard_fill,
                              label: context.t('tab.money'),
                              selected: activeIndex == 2,
                              onTap: () => _handleTap(2),
                              isDark: isDark,
                              glassExpand: t,
                            ),
                            _NavItem(
                              icon: CupertinoIcons.person_crop_circle,
                              activeIcon: CupertinoIcons.person_crop_circle_fill,
                              label: context.t('tab.profile'),
                              selected: activeIndex == 3,
                              onTap: () => _handleTap(3),
                              isDark: isDark,
                              glassExpand: t,
                              offlineBadge: widget.offline,
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
    );
  }
}

/// The bar's glass surface — real shader refraction via [LiquidGlass].
///
/// Unlike Apple's `UIGlassEffect` (which can only blur native UIKit views, not
/// Flutter-rendered content), this samples Flutter's own backdrop, so it
/// genuinely bends and blurs the dashboard/list scrolling behind the bar. A
/// crisp Flutter-drawn rim sits on top for the bright glass edge.
///
/// Purely decorative: touches are handled by the nav items layered on top.
class _GlassBar extends StatelessWidget {
  final bool isDark;
  const _GlassBar({required this.isDark});

  static const double _radius = 36;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: const BorderRadius.all(Radius.circular(_radius)),
          side: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.80),
            width: 1,
          ),
        ),
      ),
      child: LiquidGlass.withOwnLayer(
        shape: const LiquidRoundedSuperellipse(borderRadius: _radius),
        settings: LiquidGlassSettings(
          thickness: 20,
          blur: 7,
          refractiveIndex: 1.45,
          chromaticAberration: 0.015,
          lightIntensity: 0.85,
          ambientStrength: 0.15,
          saturation: 1.4,
          glassColor: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.white.withValues(alpha: 0.45),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon; // outline glyph, shown when inactive
  final IconData activeIcon; // filled glyph, shown when selected
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool isDark;
  final double glassExpand; // 0.0 = compact, 1.0 = liquid expanded
  final bool offlineBadge;

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.isDark,
    required this.glassExpand,
    this.offlineBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // Selected items use plain black / white (no accent tint) so they read
    // crisply on the neutral thumb — especially in dark mode.
    final color = selected
        ? (isDark ? Colors.white : Colors.black)
        : (isDark
              ? Colors.white.withValues(alpha: 0.50)
              : brand.ink.withValues(alpha: 0.45));
    final iconSz = lerpDouble(24.0, 25.0, glassExpand)!;
    final labelSz = lerpDouble(10.5, 11.0, glassExpand)!;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Springy pop + a crossfade morph from outline to filled glyph,
            // with an optional offline badge for the Profile tab.
            Stack(
              clipBehavior: Clip.none,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 1.0, end: selected ? 1.16 : 1.0),
                  duration: const Duration(milliseconds: 340),
                  curve: Curves.easeOutBack,
                  builder: (ctx, scale, child) =>
                      Transform.scale(scale: scale, child: child),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    child: Icon(
                      selected ? activeIcon : icon,
                      key: ValueKey(selected),
                      color: color,
                      size: iconSz,
                    ),
                  ),
                ),
                // Amber wifi-slash dot, matching the profile avatar's badge.
                if (offlineBadge)
                  Positioned(
                    right: -5,
                    top: -3,
                    child: Container(
                      width: 13,
                      height: 13,
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isDark
                              ? const Color(0xFF1C1C1E)
                              : Colors.white,
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        CupertinoIcons.wifi_slash,
                        size: 7,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
            SizedBox(height: lerpDouble(3.0, 4.0, glassExpand)!),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              style: TextStyle(
                fontSize: labelSz,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
                letterSpacing: selected ? 0.1 : 0,
              ),
              child: Text(label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
  }
}

/// The gliding selection indicator — a clean elevated "thumb" (iOS
/// segmented-control style) that springs between tabs with a soft branded
/// accent glow and a glassy top highlight. The width/height it is given
/// already squashes with travel (see `_BottomBar`); here it just leans subtly
/// in the direction of motion for a lively, tactile feel.
class _GlideCapsule extends StatelessWidget {
  final bool isDark;
  final double jelly;
  final double direction;

  const _GlideCapsule({
    required this.isDark,
    required this.jelly,
    required this.direction,
  });

  @override
  Widget build(BuildContext context) {
    // Neutral selection chip in the spirit of the WhatsApp reference: a flat,
    // soft grey capsule (no glow / no gloss) that simply glides between tabs.
    final radius = BorderRadius.circular(28);
    final lean = lerpDouble(0, 4, jelly)! * direction;

    return Transform.translate(
      offset: Offset(lean * 0.3, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          color: isDark
              ? Colors.white.withValues(alpha: 0.18)
              : Colors.black.withValues(alpha: 0.08),
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
