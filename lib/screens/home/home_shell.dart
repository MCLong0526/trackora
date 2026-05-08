import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/i18n.dart';
import '../../theme/app_theme.dart';
import '../expenses/add_edit_expense_screen.dart';
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
    DashboardScreen(),
    StatisticsScreen(),
    BudgetScreen(),
    AssetsScreen(),
  ];

  static const _navPurple = Color(0xFF6366F1);

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Scaffold(
      backgroundColor: brand.background,
      body: _screens[_index],
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 60,
            height: 60,
            child: FloatingActionButton(
              backgroundColor: _navPurple,
              elevation: 0,
              shape: const CircleBorder(),
              onPressed: () {
                Navigator.push(
                  context,
                  CupertinoPageRoute(
                    builder: (_) => const AddEditExpenseScreen(),
                  ),
                );
              },
              child: const Icon(
                CupertinoIcons.add,
                size: 26,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: brand.inkSoft,
            ),
          ),
        ],
      ),
      bottomNavigationBar: _BottomBar(
        index: _index,
        onTap: (i) => setState(() => _index = i),
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
