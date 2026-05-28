import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../models/expense.dart';
import '../../services/i18n.dart';
import '../../services/prefs_service.dart';
import '../../services/money_format.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../expenses/add_edit_expense_screen.dart';

class CalendarScreen extends ConsumerStatefulWidget {
  const CalendarScreen({super.key});

  @override
  ConsumerState<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends ConsumerState<CalendarScreen> {
  late DateTime _month;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  void _prevMonth() {
    HapticFeedback.selectionClick();
    setState(() {
      _month = DateTime(_month.year, _month.month - 1, 1);
      _selectedDay = null;
    });
  }

  void _nextMonth() {
    HapticFeedback.selectionClick();
    setState(() {
      _month = DateTime(_month.year, _month.month + 1, 1);
      _selectedDay = null;
    });
  }

  Map<int, ({double expense, double income})> _computeDayTotals(
    List<Expense> expenses,
  ) {
    final map = <int, ({double expense, double income})>{};
    for (final e in expenses) {
      final day = e.date.day;
      final prev = map[day] ?? (expense: 0.0, income: 0.0);
      if (e.type.isOutflow) {
        map[day] = (expense: prev.expense + e.convertedAmount, income: prev.income);
      } else if (e.type.isInflow) {
        map[day] = (expense: prev.expense, income: prev.income + e.convertedAmount);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final allExpensesAsync = ref.watch(allExpensesProvider);
    final allExpenses = allExpensesAsync.valueOrNull ?? const <Expense>[];
    final isLoading = allExpensesAsync.isLoading && allExpenses.isEmpty;

    final monthExpenses = allExpenses.where((e) {
      return e.date.year == _month.year && e.date.month == _month.month;
    }).toList();

    final dayTotals = _computeDayTotals(monthExpenses);

    final selectedDayExpenses = _selectedDay == null
        ? const <Expense>[]
        : (allExpenses
              .where(
                (e) =>
                    e.date.year == _selectedDay!.year &&
                    e.date.month == _selectedDay!.month &&
                    e.date.day == _selectedDay!.day,
              )
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date)));

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.only(left: 12),
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: brand.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              CupertinoIcons.chevron_left,
              color: brand.ink,
              size: 18,
            ),
          ),
        ),
        title: Text(
          'Calendar',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: brand.ink,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Center(child: CupertinoActivityIndicator()),
                  ),
                _CalendarGrid(
                  month: _month,
                  dayTotals: dayTotals,
                  selectedDay: _selectedDay,
                  symbol: symbol,
                  onPrev: _prevMonth,
                  onNext: _nextMonth,
                  onDayTap: (day) {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _selectedDay = _selectedDay?.year == day.year &&
                              _selectedDay?.month == day.month &&
                              _selectedDay?.day == day.day
                          ? null
                          : day;
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (_selectedDay != null) ...[
                  _DayHeader(
                    day: _selectedDay!,
                    expenses: selectedDayExpenses,
                    symbol: symbol,
                  ),
                  const SizedBox(height: 10),
                  if (selectedDayExpenses.isEmpty)
                    _EmptyDayCard()
                  else
                    _DayRecordsList(
                      expenses: selectedDayExpenses,
                      symbol: symbol,
                      accounts: accounts,
                      onTapExpense: (expense) => Navigator.push(
                        context,
                        CupertinoPageRoute(
                          builder: (_) =>
                              AddEditExpenseScreen(expense: expense),
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                ] else ...[
                  _MonthSummary(
                    expenses: monthExpenses,
                    symbol: symbol,
                    brand: brand,
                  ),
                  const SizedBox(height: 16),
                ],
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 16, color: brand.ink),
      ),
    );
  }
}

// ── Calendar grid ──────────────────────────────────────────────

class _CalendarGrid extends StatelessWidget {
  final DateTime month;
  final Map<int, ({double expense, double income})> dayTotals;
  final DateTime? selectedDay;
  final String symbol;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final ValueChanged<DateTime> onDayTap;

  const _CalendarGrid({
    required this.month,
    required this.dayTotals,
    required this.selectedDay,
    required this.symbol,
    required this.onPrev,
    required this.onNext,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final locale = Localizations.localeOf(context).toString();
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    // weekday: 1=Mon..7=Sun, we want Sun as first column (index 0)
    final leadingBlanks = firstWeekday % 7;

    // Jan 1 2023 is a Sunday; generate Sun–Sat abbreviations in current locale
    final weekdays = List.generate(
      7,
      (i) => DateFormat('EEE', locale).format(DateTime(2023, 1, i + 1)),
    );

    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
      child: Column(
        children: [
          // Month navigation header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NavButton(icon: CupertinoIcons.chevron_left, onTap: onPrev),
                Text(
                  DateFormat('MMMM yyyy', locale).format(month),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: brand.ink,
                  ),
                ),
                _NavButton(icon: CupertinoIcons.chevron_right, onTap: onNext),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Weekday header row
          Row(
            children: weekdays
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: brand.inkSoft,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          // Day rows
          LayoutBuilder(
            builder: (_, constraints) {
              final cellW = constraints.maxWidth / 7;
              // Height is ~1.3x width so there's space for amounts while staying compact
              final cellH = cellW * 1.3;
              final totalCells = leadingBlanks + daysInMonth;
              final rowCount = (totalCells / 7).ceil();
              final now = DateTime.now();

              return Column(
                children: List.generate(rowCount, (row) {
                  return Row(
                    children: List.generate(7, (col) {
                      final idx = row * 7 + col;
                      if (idx < leadingBlanks || idx >= totalCells) {
                        // Greyed-out blank placeholder
                        return SizedBox(width: cellW, height: cellH);
                      }
                      final dayNum = idx - leadingBlanks + 1;
                      final date = DateTime(month.year, month.month, dayNum);
                      final totals = dayTotals[dayNum];
                      final isSelected = selectedDay != null &&
                          selectedDay!.year == date.year &&
                          selectedDay!.month == date.month &&
                          selectedDay!.day == date.day;
                      final isToday = now.year == date.year &&
                          now.month == date.month &&
                          now.day == date.day;

                      return SizedBox(
                        width: cellW,
                        height: cellH,
                        child: _DayCell(
                          dayNum: dayNum,
                          date: date,
                          totals: totals,
                          isSelected: isSelected,
                          isToday: isToday,
                          symbol: symbol,
                          onTap: () => onDayTap(date),
                        ),
                      );
                    }),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DayCell extends StatelessWidget {
  final int dayNum;
  final DateTime date;
  final ({double expense, double income})? totals;
  final bool isSelected;
  final bool isToday;
  final String symbol;
  final VoidCallback onTap;

  const _DayCell({
    required this.dayNum,
    required this.date,
    required this.totals,
    required this.isSelected,
    required this.isToday,
    required this.symbol,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hasActivity =
        totals != null && (totals!.expense > 0 || totals!.income > 0);

    // Today: blue border ring, no fill; Selected: solid dark fill
    Color bgColor;
    Color dayColor;
    Border? border;

    if (isSelected) {
      bgColor = brand.accentDark;
      dayColor = Colors.white;
      border = null;
    } else if (isToday) {
      bgColor = Colors.transparent;
      dayColor = const Color(0xFF3D6FD4);
      border = Border.all(color: const Color(0xFF3D6FD4), width: 1.5);
    } else {
      bgColor = Colors.transparent;
      dayColor = brand.ink;
      border = null;
    }

    final expenseColor = isSelected ? Colors.white70 : AppColors.expense;
    final incomeColor = isSelected ? Colors.white70 : AppColors.income;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 3),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: border,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            const SizedBox(height: 6),
            Text(
              '$dayNum',
              style: TextStyle(
                fontSize: 14,
                fontWeight:
                    isToday || isSelected ? FontWeight.w800 : FontWeight.w600,
                color: dayColor,
              ),
            ),
            if (hasActivity) ...[
              const SizedBox(height: 1),
              if (totals!.expense > 0)
                Text(
                  '-${_compact(totals!.expense)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: expenseColor,
                  ),
                ),
              if (totals!.income > 0)
                Text(
                  '+${_compact(totals!.income)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: incomeColor,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _compact(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(0);
  }
}

// ── Day header ─────────────────────────────────────────────────

class _DayHeader extends StatelessWidget {
  final DateTime day;
  final List<Expense> expenses;
  final String symbol;

  const _DayHeader({
    required this.day,
    required this.expenses,
    required this.symbol,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final locale = Localizations.localeOf(context).toString();
    final expense = expenses
        .where((e) => e.type.isOutflow)
        .fold<double>(0, (s, e) => s + e.convertedAmount);
    final income = expenses
        .where((e) => e.type.isInflow)
        .fold<double>(0, (s, e) => s + e.convertedAmount);

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat('EEEE', locale).format(day),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: brand.inkSoft,
                ),
              ),
              Text(
                DateFormat('MMMM d, yyyy', locale).format(day),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: brand.ink,
                ),
              ),
            ],
          ),
        ),
        if (expenses.isNotEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (income > 0)
                Text(
                  '+${formatMoney(symbol, income)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.income,
                  ),
                ),
              if (expense > 0)
                Text(
                  '-${formatMoney(symbol, expense)}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.expense,
                  ),
                ),
            ],
          ),
      ],
    );
  }
}

// ── Day records list ───────────────────────────────────────────

class _DayRecordsList extends StatelessWidget {
  final List<Expense> expenses;
  final String symbol;
  final List<dynamic> accounts;
  final void Function(Expense) onTapExpense;

  const _DayRecordsList({
    required this.expenses,
    required this.symbol,
    required this.accounts,
    required this.onTapExpense,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          for (var i = 0; i < expenses.length; i++) ...[
            if (i > 0)
              Padding(
                padding: const EdgeInsets.only(left: 68),
                child: Container(height: 0.5, color: brand.divider),
              ),
            _RecordRow(
              expense: expenses[i],
              symbol: symbol,
              account: accounts
                  .where((a) => a.id == expenses[i].accountId)
                  .firstOrNull,
              onTap: () => onTapExpense(expenses[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordRow extends StatelessWidget {
  final Expense expense;
  final String symbol;
  final dynamic account;
  final VoidCallback onTap;

  const _RecordRow({
    required this.expense,
    required this.symbol,
    required this.account,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isIncome =
        expense.type == EntryType.income || expense.type == EntryType.receive;
    final isTransfer = expense.type == EntryType.transfer;

    final style = (isTransfer || expense.type == EntryType.receive)
        ? CategoryStyle(
            background: AppColors.blush,
            accent: AppColors.expense,
            icon: CupertinoIcons.arrow_right_arrow_left_circle_fill,
          )
        : styleFor(expense.category);

    final title = expense.note.trim().isEmpty
        ? context.categoryLabel(expense.category)
        : '${context.categoryLabel(expense.category)} · ${expense.note.trim()}';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: style.background,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(style.icon, size: 20, color: style.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                    ),
                  ),
                  if (account != null)
                    Text(
                      account.name as String,
                      style: TextStyle(
                        fontSize: 11,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Builder(builder: (ctx) {
              final hasFx = expense.originalCurrency != null &&
                  (expense.convertedAmount - expense.amount).abs() > 0.001;
              final displaySym = expense.originalCurrency != null
                  ? (kSupportedCurrencies[expense.originalCurrency!] ??
                      expense.originalCurrency!)
                  : symbol;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isIncome
                        ? formatMoney(displaySym, expense.amount, forceSign: true)
                        : formatMoney(displaySym, -expense.amount),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isIncome ? AppColors.income : brand.ink,
                    ),
                  ),
                  if (hasFx)
                    Text(
                      '≈ ${isIncome ? formatMoney(symbol, expense.convertedAmount, forceSign: true) : formatMoney(symbol, -expense.convertedAmount)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: brand.inkSoft,
                      ),
                    ),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────

class _EmptyDayCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(28),
      child: Center(
        child: Column(
          children: [
            Icon(
              CupertinoIcons.doc_text,
              size: 32,
              color: brand.inkSoft,
            ),
            const SizedBox(height: 10),
            Text(
              'No records for this day',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: brand.inkSoft,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Month summary (shown when no day selected) ─────────────────

class _MonthSummary extends StatelessWidget {
  final List<Expense> expenses;
  final String symbol;
  final BrandColors brand;

  const _MonthSummary({
    required this.expenses,
    required this.symbol,
    required this.brand,
  });

  @override
  Widget build(BuildContext context) {
    if (expenses.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.all(28),
        child: Center(
          child: Column(
            children: [
              Icon(CupertinoIcons.calendar_badge_plus,
                  size: 32, color: brand.inkSoft),
              const SizedBox(height: 10),
              Text(
                context.t('stats.noCalendarRecords'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: brand.inkSoft,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.t('stats.tapDayToSeeRecords'),
                style: TextStyle(fontSize: 12, color: brand.inkSoft),
              ),
            ],
          ),
        ),
      );
    }

    final totalExpense = expenses
        .where((e) => e.type.isOutflow)
        .fold<double>(0, (s, e) => s + e.convertedAmount);
    final totalIncome = expenses
        .where((e) => e.type.isInflow)
        .fold<double>(0, (s, e) => s + e.convertedAmount);

    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            child: _SummaryTile(
              label: context.t('common.expenses'),
              amount: formatMoney(symbol, totalExpense),
              color: AppColors.expense,
              icon: CupertinoIcons.arrow_down_circle_fill,
            ),
          ),
          Container(width: 1, height: 40, color: brand.divider),
          Expanded(
            child: _SummaryTile(
              label: context.t('expense.income'),
              amount: formatMoney(symbol, totalIncome),
              color: AppColors.income,
              icon: CupertinoIcons.arrow_up_circle_fill,
            ),
          ),
          Container(width: 1, height: 40, color: brand.divider),
          Expanded(
            child: _SummaryTile(
              label: context.t('common.net'),
              amount: formatMoney(symbol, totalIncome - totalExpense,
                  forceSign: true),
              color: totalIncome >= totalExpense
                  ? AppColors.income
                  : AppColors.expense,
              icon: CupertinoIcons.equal_circle_fill,
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  final String label;
  final String amount;
  final Color color;
  final IconData icon;

  const _SummaryTile({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: brand.inkSoft,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          amount,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: color,
          ),
        ),
      ],
    );
  }
}

// ── Calendar Modal Dialog ──────────────────────────────────────

class CalendarDialog extends ConsumerStatefulWidget {
  const CalendarDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const CalendarDialog(),
    );
  }

  @override
  ConsumerState<CalendarDialog> createState() => _CalendarDialogState();
}

class _CalendarDialogState extends ConsumerState<CalendarDialog> {
  late DateTime _month;
  DateTime? _selectedDay;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month, 1);
    _selectedDay = DateTime(now.year, now.month, now.day);
  }

  void _goToToday() {
    HapticFeedback.selectionClick();
    final now = DateTime.now();
    setState(() {
      _month = DateTime(now.year, now.month, 1);
      _selectedDay = DateTime(now.year, now.month, now.day);
    });
  }

  void _prevMonth() {
    HapticFeedback.selectionClick();
    setState(() {
      _month = DateTime(_month.year, _month.month - 1, 1);
      _selectedDay = null;
    });
  }

  void _nextMonth() {
    HapticFeedback.selectionClick();
    setState(() {
      _month = DateTime(_month.year, _month.month + 1, 1);
      _selectedDay = null;
    });
  }

  Map<int, ({bool hasExpense, bool hasIncome})> _computeDayDots(
    List<Expense> expenses,
  ) {
    final map = <int, ({bool hasExpense, bool hasIncome})>{};
    for (final e in expenses) {
      final day = e.date.day;
      final prev = map[day] ?? (hasExpense: false, hasIncome: false);
      if (e.type.isOutflow) {
        map[day] = (hasExpense: true, hasIncome: prev.hasIncome);
      } else if (e.type.isInflow) {
        map[day] = (hasExpense: prev.hasExpense, hasIncome: true);
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final allExpenses =
        ref.watch(allExpensesProvider).valueOrNull ?? const <Expense>[];
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';

    final monthExpenses = allExpenses
        .where(
          (e) => e.date.year == _month.year && e.date.month == _month.month,
        )
        .toList();
    final dayDots = _computeDayDots(monthExpenses);

    final selectedDayExpenses = _selectedDay == null
        ? const <Expense>[]
        : (allExpenses
              .where(
                (e) =>
                    e.date.year == _selectedDay!.year &&
                    e.date.month == _selectedDay!.month &&
                    e.date.day == _selectedDay!.day,
              )
              .toList()
            ..sort((a, b) => b.date.compareTo(a.date)));

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: 10),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: brand.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _DialogCalendarCard(
                        month: _month,
                        dayDots: dayDots,
                        selectedDay: _selectedDay,
                        recordCount: monthExpenses.length,
                        onPrev: _prevMonth,
                        onNext: _nextMonth,
                        onToday: _goToToday,
                        onDayTap: (day) {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedDay = day);
                        },
                      ),
                      const SizedBox(height: 16),
                      if (_selectedDay != null)
                        _DialogDaySection(
                          day: _selectedDay!,
                          expenses: selectedDayExpenses,
                          symbol: symbol,
                          accounts: accounts,
                          onAddExpense: () {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (_) => const AddEditExpenseScreen(),
                              ),
                            );
                          },
                          onTapExpense: (expense) {
                            Navigator.pop(context);
                            Navigator.push(
                              context,
                              CupertinoPageRoute(
                                builder: (_) =>
                                    AddEditExpenseScreen(expense: expense),
                              ),
                            );
                          },
                        ),
                      const SizedBox(height: 8),
                    ],
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

class _DialogCalendarCard extends StatelessWidget {
  final DateTime month;
  final Map<int, ({bool hasExpense, bool hasIncome})> dayDots;
  final DateTime? selectedDay;
  final int recordCount;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  final VoidCallback onToday;
  final ValueChanged<DateTime> onDayTap;

  const _DialogCalendarCard({
    required this.month,
    required this.dayDots,
    required this.selectedDay,
    required this.recordCount,
    required this.onPrev,
    required this.onNext,
    required this.onToday,
    required this.onDayTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;
    final firstWeekday = DateTime(month.year, month.month, 1).weekday;
    final leadingBlanks = firstWeekday % 7;
    const weekdays = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];

    return Container(
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Text(
                      DateFormat('MMMM yyyy').format(month),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: brand.ink,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: brand.inkSoft.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$recordCount',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: brand.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onToday,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    'Today',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: brand.ink,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: onPrev,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    CupertinoIcons.chevron_left,
                    size: 14,
                    color: brand.ink,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              GestureDetector(
                onTap: onNext,
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: brand.ink,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: weekdays
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: brand.inkSoft,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 6),
          LayoutBuilder(
            builder: (_, constraints) {
              final cellW = constraints.maxWidth / 7;
              final cellH = cellW * 1.15;
              final totalCells = leadingBlanks + daysInMonth;
              final rowCount = (totalCells / 7).ceil();
              final now = DateTime.now();

              return Column(
                children: List.generate(rowCount, (row) {
                  return Row(
                    children: List.generate(7, (col) {
                      final idx = row * 7 + col;
                      if (idx < leadingBlanks || idx >= totalCells) {
                        return SizedBox(width: cellW, height: cellH);
                      }
                      final dayNum = idx - leadingBlanks + 1;
                      final date =
                          DateTime(month.year, month.month, dayNum);
                      final dots = dayDots[dayNum];
                      final isSelected = selectedDay != null &&
                          selectedDay!.year == date.year &&
                          selectedDay!.month == date.month &&
                          selectedDay!.day == date.day;
                      final isToday = now.year == date.year &&
                          now.month == date.month &&
                          now.day == date.day;

                      return SizedBox(
                        width: cellW,
                        height: cellH,
                        child: _DotCell(
                          dayNum: dayNum,
                          dots: dots,
                          isSelected: isSelected,
                          isToday: isToday,
                          onTap: () => onDayTap(date),
                        ),
                      );
                    }),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _DotCell extends StatelessWidget {
  final int dayNum;
  final ({bool hasExpense, bool hasIncome})? dots;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  const _DotCell({
    required this.dayNum,
    required this.dots,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hasExpense = dots?.hasExpense ?? false;
    final hasIncome = dots?.hasIncome ?? false;

    final Color dayColor;
    final Color? circleColor;
    final Border? circleBorder;

    if (isSelected) {
      circleColor = brand.inkSoft.withValues(alpha: 0.18);
      dayColor = brand.ink;
      circleBorder = isToday
          ? Border.all(color: const Color(0xFF3D6FD4), width: 1.5)
          : null;
    } else if (isToday) {
      circleColor = null;
      dayColor = const Color(0xFF3D6FD4);
      circleBorder = Border.all(color: const Color(0xFF3D6FD4), width: 1.5);
    } else {
      circleColor = null;
      dayColor = brand.ink;
      circleBorder = null;
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: circleColor,
              shape: BoxShape.circle,
              border: circleBorder,
            ),
            child: Center(
              child: Text(
                '$dayNum',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: dayColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasIncome)
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.income,
                    shape: BoxShape.circle,
                  ),
                ),
              if (hasIncome && hasExpense) const SizedBox(width: 2),
              if (hasExpense)
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: AppColors.expense,
                    shape: BoxShape.circle,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DialogDaySection extends StatelessWidget {
  final DateTime day;
  final List<Expense> expenses;
  final String symbol;
  final List<dynamic> accounts;
  final VoidCallback onAddExpense;
  final void Function(Expense) onTapExpense;

  const _DialogDaySection({
    required this.day,
    required this.expenses,
    required this.symbol,
    required this.accounts,
    required this.onAddExpense,
    required this.onTapExpense,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final countLabel = expenses.isEmpty
        ? 'NO RECORDS'
        : '${expenses.length} ${expenses.length == 1 ? 'RECORD' : 'RECORDS'}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Text(
            '${DateFormat('EEEE, MMMM d').format(day).toUpperCase()} · $countLabel',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: brand.inkSoft,
              letterSpacing: 0.4,
            ),
          ),
        ),
        if (expenses.isNotEmpty)
          Container(
            decoration: BoxDecoration(
              color: brand.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                for (var i = 0; i < expenses.length; i++) ...[
                  if (i > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 46),
                      child: Container(height: 0.5, color: brand.divider),
                    ),
                  _DialogTransactionRow(
                    expense: expenses[i],
                    symbol: symbol,
                    account: accounts
                        .where((a) => a.id == expenses[i].accountId)
                        .firstOrNull,
                    onTap: () => onTapExpense(expenses[i]),
                  ),
                ],
              ],
            ),
          )
        else
          Container(
            decoration: BoxDecoration(
              color: brand.background,
              borderRadius: BorderRadius.circular(16),
            ),
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Center(
              child: Column(
                children: [
                  Icon(
                    CupertinoIcons.doc_text,
                    size: 28,
                    color: brand.inkSoft,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No records for this day',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: brand.inkSoft,
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: onAddExpense,
          behavior: HitTestBehavior.opaque,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            decoration: BoxDecoration(
              color: brand.background,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: brand.accentDark,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    CupertinoIcons.plus,
                    size: 14,
                    color: foregroundOn(brand.accentDark),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Add Entry',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _DialogTransactionRow extends StatelessWidget {
  final Expense expense;
  final String symbol;
  final dynamic account;
  final VoidCallback onTap;

  const _DialogTransactionRow({
    required this.expense,
    required this.symbol,
    required this.account,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isIncome =
        expense.type == EntryType.income || expense.type == EntryType.receive;
    final style =
        (expense.type == EntryType.transfer ||
                expense.type == EntryType.receive)
            ? CategoryStyle(
                background: AppColors.blush,
                accent: AppColors.expense,
                icon: CupertinoIcons.arrow_right_arrow_left_circle_fill,
              )
            : styleFor(expense.category);

    final timeStr = DateFormat('HH:mm').format(expense.date);
    final categoryLabel = context.categoryLabel(expense.category);

    final hasFx = expense.originalCurrency != null &&
        (expense.convertedAmount - expense.amount).abs() > 0.001;
    final displaySym = expense.originalCurrency != null
        ? (kSupportedCurrencies[expense.originalCurrency!] ??
            expense.originalCurrency!)
        : symbol;
    final amountStr = isIncome
        ? formatMoney(displaySym, expense.amount, forceSign: true)
        : formatMoney(displaySym, -expense.amount);
    final amountColor = isIncome ? AppColors.income : brand.ink;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: isIncome ? AppColors.income : style.accent,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              timeStr,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: brand.inkSoft,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                expense.note.trim().isEmpty
                    ? categoryLabel
                    : expense.note.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  amountStr,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: amountColor,
                  ),
                ),
                if (hasFx)
                  Text(
                    '≈ ${isIncome ? formatMoney(symbol, expense.convertedAmount, forceSign: true) : formatMoney(symbol, -expense.convertedAmount)}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: brand.inkSoft,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
