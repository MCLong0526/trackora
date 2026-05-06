import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';

class MonthFilterBar extends StatelessWidget {
  final DateTime selectedMonth;
  final ValueChanged<DateTime> onMonthSelected;

  const MonthFilterBar({
    super.key,
    required this.selectedMonth,
    required this.onMonthSelected,
  });

  List<DateTime> _months() {
    final now = DateTime.now();
    return List.generate(13, (i) {
      return DateTime(now.year, now.month - i, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final months = _months();
    final formatter = DateFormat('MMM');
    final brand = context.brand;

    return SizedBox(
      height: 38,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: months.length,
        itemBuilder: (context, index) {
          final month = months[index];
          final isSelected =
              month.year == selectedMonth.year &&
              month.month == selectedMonth.month;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onMonthSelected(month),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: isSelected ? brand.accentDark : brand.surface,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  formatter.format(month),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? (brand.accentDark.computeLuminance() < 0.5
                              ? Colors.white
                              : Colors.black)
                        : brand.ink,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
