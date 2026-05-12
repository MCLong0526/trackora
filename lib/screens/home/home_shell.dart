import 'dart:ui' show lerpDouble;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
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
          _screens[_index],
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
        onTap: (i) => setState(() => _index = i),
      ),
    );
  }
}

// ── Animated vertical speed-dial FAB ─────────────────────────────────────────
//
// Five actions listed vertically above the FAB — from bottom to top:
//   Expense → Income → Receive → Transfer → Scan receipt
//
// Each item = [label pill] [circle icon], right-aligned to the stack.
// Items slide up 22 px and fade in with a cascading stagger.

class _DialItem {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color iconBg;
  final VoidCallback onTap;

  const _DialItem({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.iconBg,
    required this.onTap,
  });
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
  static const double _stackW = 220;
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
          child: AnimatedRotation(
            turns: _open ? 0.125 : 0,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeInOut,
            child: const Icon(
              CupertinoIcons.add,
              size: 26,
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
      width: _stackW,
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
  late final List<Animation<double>> _fades;
  late final List<Animation<double>> _moves;

  static const double _stackW = _AddFabState._stackW;
  static const double _itemH = 56;
  static const double _itemGap = 8;
  static const double _bottomGap = 88;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fades = List.generate(2, (i) {
      final t0 = i * 0.10;
      return CurvedAnimation(
        parent: _ctrl,
        curve: Interval(t0, (t0 + 0.60).clamp(0.0, 1.0), curve: Curves.easeOut),
      );
    });
    _moves = List.generate(2, (i) {
      final t0 = i * 0.10;
      return CurvedAnimation(
        parent: _ctrl,
        curve: Interval(
          t0,
          (t0 + 0.72).clamp(0.0, 1.0),
          curve: Curves.easeOutCubic,
        ),
      );
    });
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

  List<_DialItem> _buildItems() => [
    _DialItem(
      icon: CupertinoIcons.camera_fill,
      label: 'Scan Receipt',
      iconColor: const Color(0xFF6366F1),
      iconBg: const Color(0xFFE0E7FF),
      onTap: widget.onScanReceipt,
    ),
    _DialItem(
      icon: CupertinoIcons.plus_rectangle_fill,
      label: 'Create Entry',
      iconColor: const Color(0xFF22C55E),
      iconBg: const Color(0xFFDCFCE7),
      onTap: widget.onManualEntry,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenW = MediaQuery.sizeOf(context).width;
    final right = ((screenW - _stackW) / 2).clamp(16.0, double.infinity);
    final items = _buildItems();

    return Positioned.fill(
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (context, _) {
          return IgnorePointer(
            ignoring: !widget.open,
            child: Stack(
              children: [
                for (var i = 0; i < items.length; i++)
                  Positioned(
                    right: right,
                    bottom: _bottomGap + i * (_itemH + _itemGap),
                    child: Transform.translate(
                      offset: Offset(0, lerpDouble(22, 0, _moves[i].value)!),
                      child: FadeTransition(
                        opacity: _fades[i],
                        child: _ListDialItem(
                          icon: items[i].icon,
                          label: items[i].label,
                          iconColor: items[i].iconColor,
                          iconBg: items[i].iconBg,
                          isDark: isDark,
                          onTap: items[i].onTap,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// Item widget: [white label pill] [colored circle icon], right-aligned
class _ListDialItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color iconColor;
  final Color iconBg;
  final bool isDark;
  final VoidCallback onTap;

  const _ListDialItem({
    required this.icon,
    required this.label,
    required this.iconColor,
    required this.iconBg,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final pillBg = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final pillText = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final circleBg = isDark ? const Color(0xFF1C1C1E) : iconBg;

    return CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      pressedOpacity: 0.68,
      onPressed: onTap,
      child: SizedBox(
        height: _SpeedDialOverlayState._itemH,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Label pill
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              decoration: BoxDecoration(
                color: pillBg,
                borderRadius: BorderRadius.circular(100),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.09),
                    blurRadius: 18,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: pillText,
                  letterSpacing: 0,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Colored circle
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: circleBg,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: iconColor.withValues(alpha: isDark ? 0.28 : 0.20),
                    blurRadius: 14,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
          ],
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        border: Border(top: BorderSide(color: brand.divider)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              _NavItem(
                icon: CupertinoIcons.house_fill,
                label: context.t('tab.home'),
                selected: index == 0,
                onTap: () => onTap(0),
              ),
              _NavItem(
                icon: CupertinoIcons.chart_bar_alt_fill,
                label: context.t('tab.stats'),
                selected: index == 1,
                onTap: () => onTap(1),
              ),
              const SizedBox(width: 64),
              _NavItem(
                icon: CupertinoIcons.creditcard,
                label: 'Funds',
                selected: index == 2,
                onTap: () => onTap(2),
              ),
              _NavItem(
                icon: CupertinoIcons.chart_pie_fill,
                label: context.t('tab.assets'),
                selected: index == 3,
                onTap: () => onTap(3),
              ),
            ],
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
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
