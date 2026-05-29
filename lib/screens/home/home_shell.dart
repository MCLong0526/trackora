import 'dart:ui' show ImageFilter;

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
    with SingleTickerProviderStateMixin {
  int? _dragIndex;
  bool _isDragging = false;
  double _barWidth = 300;
  bool _initialized = false;

  late final AnimationController _ctrl;
  double _fromX = 0;
  double _toX = 0;
  Curve _curve = Curves.easeOutBack;

  static const _navPurple = AppActionBlue.color;
  static const _indicatorW = 48.0;
  static const _indicatorH = 28.0;
  static const _indicatorTop = 8.0;

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
    final itemW = _barWidth / 4;
    return (idx + 0.5) * itemW;
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
    final itemW = _barWidth / 4;
    if (x < 0) return 0;
    if (x < itemW) return 0;
    if (x < itemW * 2) return 1;
    if (x < itemW * 3) return 2;
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
                            _NavItem(
                              icon: CupertinoIcons.creditcard,
                              label: context.t('tab.money'),
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
    const purple = AppActionBlue.color;
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
