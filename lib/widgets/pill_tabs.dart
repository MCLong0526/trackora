import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class PillTabs extends StatelessWidget {
  final List<String> tabs;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const PillTabs({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final selectedFg = brand.accentDark.computeLuminance() < 0.5
        ? Colors.white
        : Colors.black;
    return Wrap(
      spacing: 10,
      children: List.generate(tabs.length, (i) {
        final selected = i == selectedIndex;
        return GestureDetector(
          onTap: () => onChanged(i),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
            decoration: BoxDecoration(
              color: selected ? brand.accentDark : brand.surface,
              borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
            child: Text(
              tabs[i],
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? selectedFg : brand.ink,
              ),
            ),
          ),
        );
      }),
    );
  }
}
