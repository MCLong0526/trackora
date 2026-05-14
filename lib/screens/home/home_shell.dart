import 'dart:ui' show ImageFilter, lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/i18n.dart';
import '../../theme/app_theme.dart';
import '../expenses/add_edit_expense_screen.dart';
import '../expenses/import_receipt_screen.dart';
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
  bool _fabOpen = false;
  final _fabKey = GlobalKey<_AddFabState>();

  static const _screens = <Widget>[
    DashboardScreen(),
    StatisticsScreen(),
    BudgetScreen(),
    AssetsScreen(),
  ];

  static const _navPurple = Color(0xFF6366F1);

  void _openManualEntry() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => const AddEditExpenseScreen(),
      ),
    );
  }

  void _openCameraOcr() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => const ImportReceiptScreen(openCamera: true),
      ),
    );
  }

  void _runAddAction(VoidCallback action) {
    _fabKey.currentState?._close();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Scaffold(
      backgroundColor: brand.background,
      body: Stack(
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            transitionBuilder: (child, animation) {
              final isEntering = child.key == ValueKey(_index);
              return FadeTransition(
                opacity: CurvedAnimation(
                    parent: animation, curve: Curves.easeInOut),
                child: ScaleTransition(
                  scale: Tween<double>(
                    begin: isEntering ? 0.97 : 1.02,
                    end: 1.0,
                  ).animate(CurvedAnimation(
                      parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              );
            },
            child: KeyedSubtree(
              key: ValueKey(_index),
              child: _screens[_index],
            ),
          ),
          // Full-screen backdrop — dims content when speed-dial is open
          IgnorePointer(
            ignoring: !_fabOpen,
            child: AnimatedOpacity(
              opacity: _fabOpen ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOut,
              child: GestureDetector(
                onTap: () => _fabKey.currentState?._close(),
                child: Container(color: Colors.black.withValues(alpha: 0.45)),
              ),
            ),
          ),
          _SpeedDialOverlay(
            open: _fabOpen,
            onManualEntry: () => _runAddAction(_openManualEntry),
            onScanReceipt: () => _runAddAction(_openCameraOcr),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: _AddFab(
        key: _fabKey,
        brand: brand,
        onOpenChanged: (v) => setState(() => _fabOpen = v),
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        onTap: (i) {
          if (i == _index) return;
          setState(() => _index = i);
        },
      ),
    );
  }
}

class _AddFab extends StatefulWidget {
  final BrandColors brand;
  final ValueChanged<bool>? onOpenChanged;

  const _AddFab({super.key, required this.brand, this.onOpenChanged});

  @override
  State<_AddFab> createState() => _AddFabState();
}

class _AddFabState extends State<_AddFab> {
  bool _open = false;

  static const _navPurple = Color(0xFF6366F1);
  static const double _stackH = 80;

  void _toggle() {
    if (_open) {
      _close();
    } else {
      setState(() => _open = true);
      widget.onOpenChanged?.call(true);
    }
  }

  void _close() {
    if (!_open) return;
    setState(() => _open = false);
    widget.onOpenChanged?.call(false);
  }

  Widget _fabColumn() => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      SizedBox(
        width: 60,
        height: 60,
        child: FloatingActionButton(
          backgroundColor: _navPurple,
          elevation: _open ? 6 : 0,
          shape: const CircleBorder(),
          onPressed: _toggle,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => ScaleTransition(
              scale: anim,
              child: FadeTransition(opacity: anim, child: child),
            ),
            child: Icon(
              _open ? CupertinoIcons.xmark : CupertinoIcons.add,
              key: ValueKey(_open),
              size: 24,
              color: Colors.white,
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      Text(
        'Add',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: widget.brand.inkSoft,
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      height: _stackH,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // FAB — anchored to bottom-centre of the fixed-size box
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Center(child: _fabColumn()),
          ),
        ],
      ),
    );
  }
}

class _SpeedDialOverlay extends StatefulWidget {
  final bool open;
  final VoidCallback onManualEntry;
  final VoidCallback onScanReceipt;

  const _SpeedDialOverlay({
    required this.open,
    required this.onManualEntry,
    required this.onScanReceipt,
  });

  @override
  State<_SpeedDialOverlay> createState() => _SpeedDialOverlayState();
}

class _SpeedDialOverlayState extends State<_SpeedDialOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _fadeLeft;
  late final Animation<double> _moveLeft;
  late final Animation<double> _fadeRight;
  late final Animation<double> _moveRight;

  static const double _bottomGap = 78;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _fadeLeft = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    );
    _moveLeft = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.0, 0.75, curve: Curves.easeOutBack),
    );
    _fadeRight = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.08, 0.72, curve: Curves.easeOut),
    );
    _moveRight = CurvedAnimation(
      parent: _ctrl,
      curve: const Interval(0.08, 0.80, curve: Curves.easeOutBack),
    );
    if (widget.open) _ctrl.value = 1;
  }

  @override
  void didUpdateWidget(covariant _SpeedDialOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open == oldWidget.open) return;
    if (widget.open) {
      _ctrl.forward();
    } else {
      _ctrl.reverse();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) => IgnorePointer(
          ignoring: !widget.open,
          child: Stack(
            children: [
              Positioned(
                left: 16,
                right: 16,
                bottom: _bottomGap,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // ── Create Entry (primary purple) ──────────────────
                    Transform.rotate(
                      angle: -0.07,
                      child: Transform.translate(
                        offset: Offset(0, lerpDouble(30, 0, _moveLeft.value)!),
                        child: Transform.scale(
                          scale: lerpDouble(0.75, 1.0, _moveLeft.value)!,
                          alignment: Alignment.bottomCenter,
                          child: FadeTransition(
                            opacity: _fadeLeft,
                            child: _HorizDialPill(
                              icon: CupertinoIcons.add,
                              label: 'Create Entry',
                              isPrimary: true,
                              isDark: isDark,
                              onTap: widget.onManualEntry,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // ── Scan Receipt (secondary white/glass) ───────────
                    Transform.rotate(
                      angle: 0.07,
                      child: Transform.translate(
                        offset: Offset(0, lerpDouble(30, 0, _moveRight.value)!),
                        child: Transform.scale(
                          scale: lerpDouble(0.75, 1.0, _moveRight.value)!,
                          alignment: Alignment.bottomCenter,
                          child: FadeTransition(
                            opacity: _fadeRight,
                            child: _HorizDialPill(
                              icon: CupertinoIcons.camera_fill,
                              label: 'Scan Receipt',
                              isPrimary: false,
                              isDark: isDark,
                              onTap: widget.onScanReceipt,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Horizontal pill: [circle-icon] [label]
// isPrimary → purple filled; !isPrimary → white/glass
class _HorizDialPill extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool isPrimary;
  final bool isDark;
  final VoidCallback onTap;

  const _HorizDialPill({
    required this.icon,
    required this.label,
    required this.isPrimary,
    required this.isDark,
    required this.onTap,
  });

  @override
  State<_HorizDialPill> createState() => _HorizDialPillState();
}

class _HorizDialPillState extends State<_HorizDialPill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      lowerBound: 0.93,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  static const _purple = Color(0xFF6366F1);

  @override
  Widget build(BuildContext context) {
    final pillBg = widget.isPrimary
        ? _purple
        : (widget.isDark ? const Color(0xFF2C2C2E) : Colors.white);
    final labelColor = widget.isPrimary
        ? Colors.white
        : (widget.isDark ? Colors.white : const Color(0xFF1C1C1E));
    final iconBg = widget.isPrimary
        ? Colors.white.withValues(alpha: 0.22)
        : (widget.isDark
            ? Colors.white.withValues(alpha: 0.10)
            : const Color(0xFFF0F0F5));
    final iconColor = widget.isPrimary ? Colors.white : _purple;

    return GestureDetector(
      onTapDown: (_) => _press.reverse(),
      onTapUp: (_) {
        _press.forward();
        widget.onTap();
      },
      onTapCancel: () => _press.forward(),
      child: ScaleTransition(
        scale: _press,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(100),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(100),
                border: Border.all(
                  color: widget.isPrimary
                      ? Colors.white.withValues(alpha: 0.18)
                      : Colors.white
                          .withValues(alpha: widget.isDark ? 0.12 : 0.7),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color: widget.isPrimary
                        ? _purple.withValues(alpha: 0.32)
                        : Colors.black
                            .withValues(alpha: widget.isDark ? 0.25 : 0.10),
                    blurRadius: widget.isPrimary ? 20 : 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: iconBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(widget.icon, color: iconColor, size: 16),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    widget.label,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: labelColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
        ),
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

class _BottomBarState extends State<_BottomBar>
    with SingleTickerProviderStateMixin {
  int? _dragIndex;
  bool _isDragging = false;
  double _barWidth = 300;
  bool _initialized = false;

  late final AnimationController _ctrl;
  double _fromX = 0;
  double _toX = 0;
  Curve _curve = Curves.easeOutBack;

  static const _navPurple = Color(0xFF6366F1);
  // Matches the original NavItem pill: icon(20) + 14px H-pad each side
  static const _indicatorW = 48.0;
  // Height reduced to 28 so the pill clears the label below the icon
  // Column: icon(20)+gap(3)+label(10)=33 → bar top inset≈15.5 → label starts at 38.5
  // Pill top=8, height=28 → pill bottom=36, label start=38.5 → 2.5px clear
  static const _indicatorH = 28.0;
  static const _indicatorTop = 8.0;
  // gap width reserved for the center FAB
  static const _fabGap = 64.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
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
    _ctrl.dispose();
    super.dispose();
  }

  double _tabCenterX(int idx) {
    final itemW = (_barWidth - _fabGap) / 4;
    return idx < 2
        ? (idx + 0.5) * itemW
        : (idx + 0.5) * itemW + _fabGap;
  }

  double get _currentX {
    final t = _curve.transform(_ctrl.value.clamp(0.0, 1.0));
    return _fromX + (_toX - _fromX) * t;
  }

  void _animateToTab(int idx, {required bool fast}) {
    final targetX = _tabCenterX(idx);
    _fromX = _currentX;
    _toX = targetX;
    _curve = fast ? Curves.easeOutCubic : Curves.easeOutBack;
    _ctrl.stop();
    _ctrl.duration = fast
        ? const Duration(milliseconds: 180)
        : const Duration(milliseconds: 380);
    _ctrl.value = 0;
    _ctrl.forward();
  }

  int? _indexFromLocalX(double x) {
    final itemW = (_barWidth - _fabGap) / 4;
    if (x < 0) return 0;
    if (x < itemW) return 0;
    if (x < itemW * 2) return 1;
    if (x < itemW * 2 + _fabGap) return null; // FAB gap — excluded
    if (x < itemW * 3 + _fabGap) return 2;
    return 3;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeIndex =
        _isDragging ? (_dragIndex ?? widget.index) : widget.index;

    // Position the floating pill slightly above the home-indicator area for
    // balanced safe-area spacing.
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final bottomPad = safeBottom > 0 ? (safeBottom * 0.52).roundToDouble() : 10.0;
    return Padding(
        padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPad),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              height: 64,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.52)
                    : Colors.white.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.10)
                      : Colors.white.withValues(alpha: 0.60),
                  width: 0.8,
                ),
                boxShadow: [
                  BoxShadow(
                    color:
                        Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                    blurRadius: 32,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _barWidth = constraints.maxWidth;
                  // One-time init of indicator without triggering rebuild
                  if (!_initialized) {
                    _fromX = _tabCenterX(widget.index);
                    _toX = _fromX;
                    _initialized = true;
                  }
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onHorizontalDragStart: (d) {
                      final idx = _indexFromLocalX(d.localPosition.dx);
                      if (idx == null) return;
                      HapticFeedback.mediumImpact();
                      setState(() {
                        _isDragging = true;
                        _dragIndex = idx;
                      });
                      widget.onTap(idx);
                      _animateToTab(idx, fast: true);
                    },
                    onHorizontalDragUpdate: (d) {
                      if (!_isDragging) return;
                      final idx = _indexFromLocalX(d.localPosition.dx);
                      if (idx == null || idx == _dragIndex) return;
                      HapticFeedback.selectionClick();
                      setState(() => _dragIndex = idx);
                      widget.onTap(idx);
                      _animateToTab(idx, fast: true);
                    },
                    onHorizontalDragEnd: (_) {
                      if (!_isDragging) return;
                      setState(() {
                        _isDragging = false;
                        _dragIndex = null;
                      });
                      _animateToTab(widget.index, fast: false);
                    },
                    onHorizontalDragCancel: () {
                      if (!_isDragging) return;
                      setState(() {
                        _isDragging = false;
                        _dragIndex = null;
                      });
                      _animateToTab(widget.index, fast: false);
                    },
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // Single animated indicator pill — replaces NavItem's
                        // built-in pill. Slides smoothly to the active tab.
                        AnimatedBuilder(
                          animation: _ctrl,
                          builder: (context, _) {
                            final cx = _currentX;
                            return Positioned(
                              left: cx - _indicatorW / 2,
                              top: _indicatorTop,
                              width: _indicatorW,
                              height: _indicatorH,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 160),
                                decoration: BoxDecoration(
                                  // Same alpha as original NavItem pill
                                  color: _navPurple.withValues(
                                    alpha: _isDragging ? 0.19 : 0.13,
                                  ),
                                  // Same radius as original NavItem pill
                                  borderRadius: BorderRadius.circular(16),
                                  border: _isDragging
                                      ? Border.all(
                                          color: _navPurple.withValues(
                                              alpha: 0.30),
                                          width: 0.8,
                                        )
                                      : null,
                                  boxShadow: _isDragging
                                      ? [
                                          BoxShadow(
                                            color: _navPurple.withValues(
                                                alpha: 0.22),
                                            blurRadius: 12,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                        // Nav items row
                        Row(
                          children: [
                            _NavItem(
                              icon: CupertinoIcons.house_fill,
                              label: context.t('tab.home'),
                              selected: activeIndex == 0,
                              onTap: () => widget.onTap(0),
                            ),
                            _NavItem(
                              icon: CupertinoIcons.chart_bar_alt_fill,
                              label: context.t('tab.stats'),
                              selected: activeIndex == 1,
                              onTap: () => widget.onTap(1),
                            ),
                            const SizedBox(width: _fabGap),
                            _NavItem(
                              icon: CupertinoIcons.creditcard,
                              label: 'Funds',
                              selected: activeIndex == 2,
                              onTap: () => widget.onTap(2),
                            ),
                            _NavItem(
                              icon: CupertinoIcons.chart_pie_fill,
                              label: context.t('tab.assets'),
                              selected: activeIndex == 3,
                              onTap: () => widget.onTap(3),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    const purple = _HomeShellState._navPurple;
    final color = selected ? purple : brand.inkSoft;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // No pill here — the sliding overlay indicator handles selection
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 3),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: color,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}
