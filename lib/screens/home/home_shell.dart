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
      body: AnimatedSwitcher(
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
      bottomNavigationBar: _BottomBar(
        index: _index,
        onTap: (i) {
          if (i == _index) return;
          ref.read(homeTabIndexProvider.notifier).state = i;
          setState(() => _index = i);
        },
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
    with TickerProviderStateMixin {
  int? _dragIndex;
  bool _isDragging = false;
  double _barWidth = 300;
  bool _initialized = false;
  // Pill slide animation
  late final AnimationController _pillCtrl;
  double _fromX = 0;
  double _toX = 0;
  Curve _curve = Curves.easeOutBack;

  // Liquid glass expand animation (long press)
  late final AnimationController _glassCtrl;

  // Default compact height; modest bar grow on long press
  static const _compactH = 56.0;
  static const _liquidH = 66.0;
  // Circle indicator diameters: base (contained) → expanded (overflows bar)
  static const _circleDBase = 52.0;
  static const _circleDExpanded = 90.0;

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
    final t = _curve.transform(_pillCtrl.value.clamp(0.0, 1.0));
    return _fromX + (_toX - _fromX) * t;
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

  int? _indexFromLocalX(double x) {
    final itemW = _barWidth / 4;
    if (x < 0) return 0;
    for (var i = 0; i < 4; i++) {
      if (x < itemW * (i + 1)) return i;
    }
    return 3;
  }

  void _expandGlass() {
    HapticFeedback.lightImpact();
    _glassCtrl.animateTo(
      1.0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _collapseGlass() {
    _glassCtrl.animateTo(
      0.0,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeInCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeIndex =
        _isDragging ? (_dragIndex ?? widget.index) : widget.index;

    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    final bottomPad =
        safeBottom > 0 ? (safeBottom * 0.52).roundToDouble() : 10.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 6, 16, bottomPad),
      child: AnimatedBuilder(
        // Single builder listening to both animations
        animation: Listenable.merge([_pillCtrl, _glassCtrl]),
        builder: (context, _) {
          final t = Curves.easeOutCubic.transform(_glassCtrl.value);
          final barH = lerpDouble(_compactH, _liquidH, t)!;
          // Circle grows from base (fits inside bar) → expanded (overflows bar)
          final circleD = lerpDouble(_circleDBase, _circleDExpanded, t)!;
          final cx = _currentX;
          final blurSigma = lerpDouble(20.0, 44.0, t)!;
          // Dark mode: rich dark frosted glass matching WhatsApp reference
          final bgTopAlpha = isDark
              ? lerpDouble(0.15, 0.26, t)!
              : lerpDouble(0.74, 0.92, t)!;
          final bgBotAlpha = isDark
              ? lerpDouble(0.07, 0.14, t)!
              : lerpDouble(0.56, 0.74, t)!;
          final borderAlpha = isDark
              ? lerpDouble(0.18, 0.32, t)!
              : lerpDouble(0.80, 0.96, t)!;
          final shadowAlpha = isDark
              ? lerpDouble(0.40, 0.60, t)!
              : lerpDouble(0.07, 0.15, t)!;
          final specularPeak = isDark
              ? lerpDouble(0.22, 0.44, t)!
              : lerpDouble(0.62, 0.92, t)!;

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
                          sigmaX: blurSigma, sigmaY: blurSigma),
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
                            color:
                                Colors.white.withValues(alpha: borderAlpha),
                            width: 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: shadowAlpha),
                              blurRadius: lerpDouble(26.0, 52.0, t)!,
                              offset: const Offset(0, 10),
                            ),
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: shadowAlpha * 0.45),
                              blurRadius: lerpDouble(8.0, 16.0, t)!,
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
                                          alpha: specularPeak - 0.08),
                                      Colors.white
                                          .withValues(alpha: specularPeak),
                                      Colors.white.withValues(
                                          alpha: specularPeak - 0.08),
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
                // ── Layer 2: Circle indicator (behind nav items, can overflow) ──
                Positioned(
                  left: cx - circleD / 2,
                  top: (barH - circleD) / 2,
                  width: circleD,
                  height: circleD,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // Dark: medium-dark disc matching WhatsApp (lighter than bar, darker than icons)
                      // Light: crisp white disc
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: isDark
                            ? [
                                Colors.white.withValues(
                                    alpha: lerpDouble(0.26, 0.40, t)!),
                                Colors.white.withValues(
                                    alpha: lerpDouble(0.12, 0.22, t)!),
                              ]
                            : [
                                Colors.white.withValues(
                                    alpha: lerpDouble(0.94, 1.0, t)!),
                                Colors.white.withValues(
                                    alpha: lerpDouble(0.66, 0.82, t)!),
                              ],
                      ),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(
                                alpha: lerpDouble(0.18, 0.38, t)!)
                            : Colors.white.withValues(
                                alpha: lerpDouble(0.92, 1.0, t)!),
                        width: isDark ? lerpDouble(0.6, 1.2, t)! : 0.8,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.white.withValues(
                            alpha: isDark
                                ? lerpDouble(0.14, 0.28, t)!
                                : lerpDouble(0.60, 0.80, t)!,
                          ),
                          blurRadius: 6,
                          offset: const Offset(0, -1),
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: isDark
                                ? lerpDouble(0.30, 0.50, t)!
                                : lerpDouble(0.08, 0.18, t)!,
                          ),
                          blurRadius: lerpDouble(8.0, 20.0, t)!,
                          offset: const Offset(0, 3),
                        ),
                        if (t > 0.05)
                          BoxShadow(
                            color: AppActionBlue.color
                                .withValues(alpha: lerpDouble(0.0, 0.28, t)!),
                            blurRadius: lerpDouble(0.0, 22.0, t)!,
                            spreadRadius: lerpDouble(0.0, 2.0, t)!,
                          ),
                      ],
                    ),
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
                    // Listener fires immediately on pointer down/up (no delay)
                    return Listener(
                      onPointerDown: (_) => _expandGlass(),
                      onPointerUp: (_) => _collapseGlass(),
                      onPointerCancel: (_) => _collapseGlass(),
                      child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onHorizontalDragStart: (d) {
                        final idx =
                            _indexFromLocalX(d.localPosition.dx);
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
                        final idx =
                            _indexFromLocalX(d.localPosition.dx);
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
                      child: Row(
                        children: [
                          _NavItem(
                            icon: CupertinoIcons.house_fill,
                            label: context.t('tab.home'),
                            selected: activeIndex == 0,
                            onTap: () => widget.onTap(0),
                            isDark: isDark,
                            glassExpand: t,
                          ),
                          _NavItem(
                            icon: CupertinoIcons.chart_bar_alt_fill,
                            label: context.t('tab.stats'),
                            selected: activeIndex == 1,
                            onTap: () => widget.onTap(1),
                            isDark: isDark,
                            glassExpand: t,
                          ),
                          _NavItem(
                            icon: CupertinoIcons.creditcard,
                            label: context.t('tab.money'),
                            selected: activeIndex == 2,
                            onTap: () => widget.onTap(2),
                            isDark: isDark,
                            glassExpand: t,
                          ),
                          _NavItem(
                            icon: CupertinoIcons.chart_pie_fill,
                            label: context.t('tab.assets'),
                            selected: activeIndex == 3,
                            onTap: () => widget.onTap(3),
                            isDark: isDark,
                            glassExpand: t,
                          ),
                        ],
                      ),
                    ),  // GestureDetector
                    );  // Listener
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
    final iconSz = lerpDouble(21.0, 22.0, glassExpand)!;
    final labelSz = lerpDouble(9.5, 10.5, glassExpand)!;

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
            SizedBox(height: lerpDouble(2.0, 3.0, glassExpand)!),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize: labelSz,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: labelColor,
                letterSpacing: selected ? -0.1 : 0,
              ),
              child: Text(label, maxLines: 1),
            ),
          ],
        ),
      ),
    );
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
        .where((e) =>
            _query.isEmpty ||
            e.key.toLowerCase().contains(_query.toLowerCase()) ||
            e.value.toLowerCase().contains(_query.toLowerCase()))
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
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: brand.background,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.search,
                              size: 16, color: brand.inkSoft),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              onChanged: (v) => setState(() => _query = v),
                              style: TextStyle(
                                  fontSize: 15, color: brand.ink),
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
                            horizontal: 14, vertical: 12),
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
