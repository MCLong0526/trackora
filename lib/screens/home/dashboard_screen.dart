import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/expense.dart';
import '../../models/expense_group.dart';
import '../../models/installment.dart';
import '../../models/precious_metal.dart';
import '../../models/stock_investment.dart';
import '../../repositories/local_expense_repository.dart';
import '../../repositories/local_precious_metal_repository.dart';
import '../../repositories/local_split_bill_repository.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../services/prefs_service.dart';
import '../../services/split_settlement_service.dart';
import '../../services/sync_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/expense_card.dart';
import '../../widgets/month_filter_bar.dart';
import '../../widgets/exchange_rate_sheet.dart';
import '../../widgets/reorderable_tile_grid.dart';
import '../../widgets/section_card.dart';
import '../../widgets/sticky_header_scaffold.dart';
import '../expenses/add_edit_expense_screen.dart';
import '../expenses/import_receipt_screen.dart';
import '../precious_metals/precious_metals_screen.dart';
import '../stocks/stock_detail_screen.dart';
import '../travel/travel_groups_screen.dart';
import '../../widgets/personal_group_toggle.dart';
import 'calendar_screen.dart';
import '../group/group_dashboard_screen.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final selectedMonth = ref.watch(selectedMonthProvider);
    final expensesAsync = ref.watch(expensesProvider);
    final allExpensesAsync = ref.watch(allExpensesProvider);
    final budgetAsync = ref.watch(budgetProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final appLocale = ref.watch(localeProvider);
    final user = ref.watch(authStateProvider).valueOrNull;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final allMetals =
        ref.watch(preciousMetalsProvider).valueOrNull ?? const <PreciousMetal>[];
    final allStocks = ref.watch(stockInvestmentsProvider).valueOrNull ??
        const <StockInvestment>[];
    final mode = ref.watch(homeModeProvider);
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const [];
    final hasGroups = groups.isNotEmpty;
    final activeGroupId = ref.watch(activeGroupIdProvider);
    final isGroupMode = mode == HomeMode.group && hasGroups;
    final activeGroup = groups.cast<ExpenseGroup?>().firstWhere(
      (g) => g?.id == activeGroupId,
      orElse: () => groups.isNotEmpty ? groups.first : null,
    );

    if (groups.isEmpty && mode == HomeMode.group) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeGroupIdProvider.notifier).state = null;
        ref.read(homeModeProvider.notifier).state = HomeMode.personal;
      });
    } else if (activeGroupId == null && groups.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeGroupIdProvider.notifier).state = groups.first.id;
      });
    } else if (activeGroupId != null &&
        groups.isNotEmpty &&
        activeGroup?.id != activeGroupId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        ref.read(activeGroupIdProvider.notifier).state = activeGroup?.id;
      });
    }

    final cycleRange = ref.watch(cycleDateRangeProvider);
    final visible = ref.watch(balanceVisibleProvider);
    final budget = budgetAsync.valueOrNull ?? 0;
    final monthExpenses = expensesAsync.valueOrNull ?? const <Expense>[];
    final allExpenses = allExpensesAsync.valueOrNull ?? const <Expense>[];
    final monthExpenseOnly = monthExpenses
        .where((e) => e.type == EntryType.expense)
        .toList();

    // If custom cycle is active, filter allExpenses by cycle range for totals.
    final List<Expense> cycleExpenseOnly;
    if (cycleRange != null) {
      cycleExpenseOnly = allExpenses.where((e) {
        if (e.type != EntryType.expense) return false;
        final d = DateTime(e.date.year, e.date.month, e.date.day);
        return !d.isBefore(cycleRange.start) &&
            d.isBefore(cycleRange.endExclusive);
      }).toList();
    } else {
      cycleExpenseOnly = monthExpenseOnly;
    }

    final monthSpent = cycleExpenseOnly.fold<double>(
      0,
      (s, e) => s + e.convertedAmount,
    );
    final hasForeignExpense = cycleExpenseOnly.any(
      (e) => e.baseCurrencyAmount != null,
    );

    final List<Expense> cycleAll = cycleRange != null
        ? allExpenses.where((e) {
            final d = DateTime(e.date.year, e.date.month, e.date.day);
            return !d.isBefore(cycleRange.start) &&
                d.isBefore(cycleRange.endExclusive);
          }).toList()
        : monthExpenses;

    final budgetableSpent = cycleAll
        .where(
          (e) =>
              e.type == EntryType.expense &&
              e.category != 'Bills' &&
              !e.note.contains('(installment)'),
        )
        .fold<double>(0, (s, e) => s + e.convertedAmount);

    final totalBalance = ref.watch(totalAccountBalanceProvider);

    // Unpaid installments for current cycle month
    final allInstallments = ref.watch(installmentsProvider).valueOrNull ?? [];
    final now = DateTime.now();
    final cycleMonthDate =
        cycleRange?.start ?? DateTime(now.year, now.month, 1);
    final unpaidInstallments = allInstallments.where((inst) {
      if (inst.status != InstallmentStatus.active) return false;
      return !inst.isPaidIn(cycleMonthDate);
    }).toList();
    final todayStart = DateTime(now.year, now.month, now.day);
    final weekStart = todayStart.subtract(Duration(days: now.weekday - 1));
    double todaySpent = 0;
    double weekSpent = 0;
    int todayCount = 0;
    for (final e in allExpenses) {
      if (e.type != EntryType.expense) continue;
      if (!e.date.isBefore(todayStart)) {
        todaySpent += e.convertedAmount;
        todayCount++;
      }
      if (!e.date.isBefore(weekStart)) weekSpent += e.convertedAmount;
    }

    final sortedRecent = [...allExpenses]
      ..sort((a, b) => b.date.compareTo(a.date));

    // Build a combined activity list for the selected month: expenses +
    // precious metal buy/sell + stock buy/sell, sorted by date (newest first).
    bool inSelectedMonth(DateTime d) =>
        d.year == selectedMonth.year && d.month == selectedMonth.month;
    final activityItems = <_ActivityItem>[
      for (final e in monthExpenses) _ActivityItem.expense(e),
      for (final m in allMetals)
        if (inSelectedMonth(m.date)) _ActivityItem.metal(m),
      for (final s in allStocks)
        for (final tx in s.transactions)
          if (_stockTxnDate(tx) != null && inSelectedMonth(_stockTxnDate(tx)!))
            _ActivityItem.stock(s, tx),
    ]..sort((a, b) => b.date.compareTo(a.date));

    ref
        .read(widgetSyncServiceProvider)
        .push(
          currencySymbol: symbol,
          monthSpent: monthSpent,
          monthBudget: budget,
          savings: totalBalance,
          upcomingInstallments: unpaidInstallments.length.toDouble(),
          budgetableSpent: budgetableSpent,
          localeCode: appLocale.encode(),
          todaySpent: todaySpent,
          todayCount: todayCount,
          weekSpent: weekSpent,
          accounts: accounts,
          recentExpenses: sortedRecent.take(5).toList(),
        );

    return SafeArea(
      child: StickyHeaderScaffold(
        header: Padding(
          padding: EdgeInsets.fromLTRB(20, 12, 20, hasGroups ? 4 : 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        DateFormat('EEEE').format(DateTime.now()),
                        style: TextStyle(
                          color: brand.inkSoft,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Trackora',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: brand.ink,
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      GlassCircleButton(
                        icon: visible
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        onTap: () =>
                            ref.read(balanceVisibleProvider.notifier).toggle(),
                      ),
                      const SizedBox(width: 8),
                      const FxRateButton(),
                      if (isGroupMode) ...[
                        const SizedBox(width: 10),
                        GestureDetector(
                          onTap: () => showGroupMenu(
                            context,
                            ref,
                            activeGroup,
                            user?.uid,
                          ),
                          child: GroupAvatarPill(
                            group: activeGroup,
                            userId: user?.uid,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              if (hasGroups) ...[
                const SizedBox(height: 8),
                PersonalGroupToggle(brand: brand),
              ],
            ],
          ),
        ),
        bodyBuilder: (sc) => CustomScrollView(
          controller: sc,
          slivers: [
          if (isGroupMode)
            SliverFillRemaining(
              hasScrollBody: true,
              child: GroupDashboardContent(
                brand: brand,
                group: activeGroup,
                symbol: symbol,
                userId: user?.uid,
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  10,
                  20,
                  cycleRange != null ? 4 : 12,
                ),
                child: _HomeOverviewCard(
                  symbol: symbol,
                  monthSpent: monthSpent,
                  budget: budget,
                  budgetSpent: budgetableSpent,
                  selectedMonth: selectedMonth,
                  hasForeignExpense: hasForeignExpense,
                ),
              ),
            ),

            if (cycleRange != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        context.t('home.cycleLabel').replaceAll(
                          '{range}',
                          '${DateFormat('d MMM').format(cycleRange.start)} – ${DateFormat('d MMM').format(cycleRange.endExclusive.subtract(const Duration(days: 1)))}',
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: brand.inkSoft,
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 10, 24, 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.t('home.activity'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => CalendarDialog.show(context),
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        children: [
                          Icon(
                            CupertinoIcons.calendar,
                            size: 14,
                            color: brand.accentDark,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            context.t('stats.calendar'),
                            style: TextStyle(
                              fontSize: 13,
                              color: brand.accentDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            SliverToBoxAdapter(
              child: MonthFilterBar(
                selectedMonth: selectedMonth,
                onMonthSelected: (m) =>
                    ref.read(selectedMonthProvider.notifier).state = m,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            if (activityItems.isEmpty)
              SliverToBoxAdapter(child: _empty(context))
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _CoordinatedList(
                    builder: (coordinator) => GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => coordinator.value = null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: brand.surface,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Column(
                            children: [
                              for (
                                var i = 0;
                                i < activityItems.length.clamp(0, 5);
                                i++
                              ) ...[
                                if (i > 0)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 70),
                                    child: Container(
                                      height: 0.5,
                                      color: brand.divider,
                                    ),
                                  ),
                                Builder(
                                  builder: (ctx) {
                                    final item = activityItems[i];
                                    final expense = item.expense;
                                    if (expense == null) {
                                      // Precious metal or stock transaction row.
                                      return _AssetActivityRow(
                                        item: item,
                                        symbol: symbol,
                                      );
                                    }
                                    final acct = accounts
                                        .where((a) => a.id == expense.accountId)
                                        .firstOrNull;
                                    return ExpenseCard(
                                      key: ValueKey(expense.id),
                                      coordinator: coordinator,
                                      rowId: expense.id,
                                      expense: expense,
                                      currencySymbol: symbol,
                                      account: acct,
                                      flat: true,
                                      hasSplitBill:
                                          user != null &&
                                          LocalSplitBillRepository.hasSplitBillSync(
                                            user.uid,
                                            expense.id,
                                          ),
                                      splitUnsettledCount: user == null
                                          ? 0
                                          : LocalSplitBillRepository
                                              .unsettledCountSync(
                                                  user.uid, expense.id),
                                      onTap: () => Navigator.push(
                                        context,
                                        CupertinoPageRoute(
                                          builder: (_) => AddEditExpenseScreen(
                                            expense: expense,
                                          ),
                                        ),
                                      ),
                                      onEdit: () => Navigator.push(
                                        context,
                                        CupertinoPageRoute(
                                          builder: (_) => AddEditExpenseScreen(
                                            expense: expense,
                                          ),
                                        ),
                                      ),
                                      onDelete: () async {
                                        if (user == null) return;
                                        final uid = user.uid;
                                        try {
                                          final isOnline = storageMode ==
                                                  StorageMode.firebase &&
                                              ref.read(isOnlineProvider);
                                          await SplitSettlementService
                                              .revertIfSettlement(
                                            uid: uid,
                                            expenseId: expense.id,
                                            isOnline: isOnline,
                                          );
                                          // If this is a split-bill source,
                                          // remove its bill + collected
                                          // settlement "receive" expenses too.
                                          await SplitSettlementService
                                              .deleteBillForSourceExpense(
                                            uid: uid,
                                            expenseId: expense.id,
                                            isOnline: isOnline,
                                          );
                                          if (storageMode == StorageMode.firebase) {
                                            await SyncService().deleteExpense(
                                              userId: uid,
                                              expenseId: expense.id,
                                              isOnline: isOnline,
                                            );
                                          } else {
                                            await LocalExpenseRepository()
                                                .deleteExpense(uid, expense.id);
                                          }
                                          ref.invalidate(allSplitBillsProvider);
                                          if (!context.mounted) return;
                                          AppToast.show(
                                            context,
                                            context.t('expense.entryDeleted'),
                                            type: AppToastType.info,
                                            icon: CupertinoIcons.trash,
                                          );
                                        } catch (_) {
                                          if (!context.mounted) return;
                                          AppToast.show(
                                            context,
                                            context.t('common.error'),
                                            type: AppToastType.error,
                                            icon: CupertinoIcons
                                                .exclamationmark_circle_fill,
                                          );
                                        }
                                      },
                                      onCopy: () => _copyRecord(context, expense),
                                    );
                                  },
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (activityItems.length > 5)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: GestureDetector(
                      onTap: () => _showAllBillsSheet(
                        context,
                        activityItems,
                        symbol,
                        selectedMonth,
                      ),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: brand.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${context.t('home.allBills')} · ${activityItems.length} ${context.t('common.entries')}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: brand.accentDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ],
        ),  // end CustomScrollView
      ),   // end StickyHeaderScaffold
    );
  }

  Widget _empty(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
      child: SectionCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: AppColors.sand,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(CupertinoIcons.tray, color: AppColors.inkSoft),
            ),
            const SizedBox(height: 12),
            Text(
              context.t('home.noEntriesThisMonth'),
              style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink),
            ),
            const SizedBox(height: 4),
            Text(
              context.t('home.addFirstExpense'),
              style: TextStyle(color: brand.inkSoft, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  void _copyRecord(BuildContext context, Expense original) {
    AppToast.show(
      context,
      context.t('metal.copiedToast'),
      type: AppToastType.info,
      icon: CupertinoIcons.doc_on_doc,
    );
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => AddEditExpenseScreen(copyFrom: original),
      ),
    );
  }

  void _showAllBillsSheet(
    BuildContext context,
    List<_ActivityItem> items,
    String symbol,
    DateTime month,
  ) {
    final sorted = [...items]..sort((a, b) => b.date.compareTo(a.date));
    final total = sorted
        .where((i) => i.expense?.type == EntryType.expense)
        .fold<double>(0, (s, i) => s + i.expense!.convertedAmount);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(ctx).height * 0.85,
          ),
          child: _AllBillsSheet(
            items: sorted,
            total: total,
            symbol: symbol,
            month: month,
          ),
        ),
      ),
    );
  }
}

// ── Activity item (union: expense / metal / stock) ─────────────

DateTime? _stockTxnDate(Map<String, dynamic> tx) {
  final raw = tx['date'];
  if (raw is String) {
    try {
      return DateTime.parse(raw);
    } catch (_) {
      return null;
    }
  }
  if (raw is int) return DateTime.fromMillisecondsSinceEpoch(raw);
  if (raw is DateTime) return raw;
  return null;
}

/// A single row in the dashboard activity list. Holds exactly one of an
/// [Expense], a [PreciousMetal], or a stock investment transaction.
class _ActivityItem {
  final Expense? expense;
  final PreciousMetal? metal;
  final StockInvestment? stock;
  final Map<String, dynamic>? stockTxn;
  final DateTime date;

  const _ActivityItem._({
    this.expense,
    this.metal,
    this.stock,
    this.stockTxn,
    required this.date,
  });

  factory _ActivityItem.expense(Expense e) =>
      _ActivityItem._(expense: e, date: e.date);

  factory _ActivityItem.metal(PreciousMetal m) =>
      _ActivityItem._(metal: m, date: m.date);

  factory _ActivityItem.stock(StockInvestment s, Map<String, dynamic> tx) =>
      _ActivityItem._(
        stock: s,
        stockTxn: tx,
        date: _stockTxnDate(tx) ?? s.updatedAt,
      );
}

// ── Asset activity row (precious metal / stock buy-sell) ───────
class _AssetActivityRow extends ConsumerWidget {
  final _ActivityItem item;
  final String symbol;

  const _AssetActivityRow({required this.item, required this.symbol});

  void _openEdit(BuildContext context) {
    final metal = item.metal;
    if (metal != null) {
      showMetalEditSheet(context, metal);
    } else {
      Navigator.push(
        context,
        CupertinoPageRoute(builder: (_) => StockDetailScreen(stock: item.stock!)),
      );
    }
  }

  Future<void> _deleteMetal(
    BuildContext context,
    WidgetRef ref,
    PreciousMetal metal,
  ) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    try {
      // Always remove from local Hive immediately so the UI updates offline.
      await LocalPreciousMetalRepository().delete(user.uid, metal.id);
      await ref.read(preciousMetalRepositoryProvider).delete(user.uid, metal.id);
      if (storageMode == StorageMode.firebase &&
          !ref.read(isOnlineProvider)) {
        // Offline: queue the Firestore delete so it syncs on reconnect.
        await SyncService.markEntityPendingDelete(user.uid, 'metal', metal.id);
      }
      // Also remove the linked expense entry, if any.
      if (metal.expenseId != null && metal.expenseId!.isNotEmpty) {
        await LocalExpenseRepository()
            .deleteExpense(user.uid, metal.expenseId!);
        if (storageMode == StorageMode.firebase) {
          await SyncService().deleteExpense(
            userId: user.uid,
            expenseId: metal.expenseId!,
            isOnline: ref.read(isOnlineProvider),
          );
        }
      }
      ref.invalidate(preciousMetalsProvider);
      if (!context.mounted) return;
      AppToast.show(
        context,
        context.t('metal.deletedToast'),
        type: AppToastType.info,
        icon: CupertinoIcons.trash,
      );
    } catch (_) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        context.t('common.error'),
        type: AppToastType.error,
        icon: CupertinoIcons.exclamationmark_circle_fill,
      );
    }
  }

  void _showActions(BuildContext context, WidgetRef ref) {
    HapticFeedback.mediumImpact();
    final metal = item.metal;
    showCupertinoModalPopup<void>(
      context: context,
      builder: (sheetCtx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(sheetCtx);
              _openEdit(context);
            },
            child: Text(context.t('common.edit')),
          ),
          if (metal != null)
            CupertinoActionSheetAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(sheetCtx);
                _deleteMetal(context, ref, metal);
              },
              child: Text(context.t('common.delete')),
            ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(sheetCtx),
          child: Text(context.t('common.cancel')),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final metal = item.metal;
    final stock = item.stock;

    late final String title;
    late final IconData icon;
    late final Color iconBg;
    late final Color iconColor;
    late final bool isInflow;
    late final double amount;
    // For stocks the transaction amount is in the stock's own currency
    // (e.g. USD), not the user's base currency. [amountSymbol] is the symbol
    // to render the amount with; [estBase] is the converted estimate in the
    // base currency (null when no conversion is needed/available).
    String amountSymbol = symbol;
    double? estBase;

    if (metal != null) {
      final isSell = metal.action == MetalAction.sell;
      title =
          '${metal.metalType.label} ${isSell ? context.t('metal.sell') : context.t('metal.buy')}';
      icon = CupertinoIcons.circle_grid_hex_fill;
      iconBg = metal.metalType.bgColor;
      iconColor = metal.metalType.primaryColor;
      isInflow = isSell;
      amount = metal.totalAmount;
    } else {
      final tx = item.stockTxn!;
      final isSell = tx['type'] == 'sell';
      final qty = (tx['qty'] as num?)?.toDouble() ?? 0.0;
      final price = (tx['price'] as num?)?.toDouble() ?? 0.0;
      title =
          '${stock!.symbol} ${isSell ? context.t('metal.sell') : context.t('metal.buy')}';
      icon = CupertinoIcons.chart_bar_alt_fill;
      iconBg = AppColors.sky;
      iconColor = const Color(0xFF2A6FB5);
      isInflow = isSell;
      amount = qty * price;
      // Show the amount in the stock's native currency, and an estimated
      // value in the user's base currency underneath.
      final txCurrency =
          (tx['currency'] as String?) ?? stock.currency ?? '';
      if (txCurrency.isNotEmpty) {
        amountSymbol = kSupportedCurrencies[txCurrency] ?? txCurrency;
      }
      final converter = ref.watch(currencyConverterProvider).valueOrNull;
      if (converter != null &&
          txCurrency.isNotEmpty &&
          txCurrency != converter.base) {
        estBase = converter.toBase(amount, txCurrency);
      }
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(item.date.year, item.date.month, item.date.day);
    final dateStr = d == today
        ? context.t('home.today')
        : d == yesterday
            ? context.t('home.yesterday')
            : DateFormat('MMM d').format(item.date);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        _openEdit(context);
      },
      onLongPress: () => _showActions(context, ref),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 20, color: iconColor),
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
                      fontWeight: FontWeight.w600,
                      color: brand.ink,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    dateStr,
                    style: TextStyle(
                      fontSize: 12,
                      color: brand.inkSoft,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isInflow
                      ? formatMoney(amountSymbol, amount, forceSign: true)
                      : formatMoney(amountSymbol, -amount),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isInflow ? brand.income : brand.ink,
                  ),
                ),
                if (estBase != null)
                  Text(
                    '≈ ${formatMoney(symbol, estBase)} ${context.t('common.est')}',
                    style: TextStyle(
                      fontSize: 11,
                      color: brand.inkSoft,
                      fontWeight: FontWeight.w400,
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

// ── Home overview card ─────────────────────────────────────────

class _HomeOverviewCard extends ConsumerWidget {
  final String symbol;
  final double monthSpent;
  final double budget;
  final double budgetSpent;
  final DateTime selectedMonth;
  final bool hasForeignExpense;

  const _HomeOverviewCard({
    required this.symbol,
    required this.monthSpent,
    required this.budget,
    required this.budgetSpent,
    required this.selectedMonth,
    required this.hasForeignExpense,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visible = ref.watch(balanceVisibleProvider);
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final budgetProgress = budget > 0
        ? (budgetSpent / budget).clamp(0.0, 1.0)
        : 0.0;

    final topBg = isDark ? const Color(0xFF201E2C) : brand.surface;
    final topInk = brand.ink;
    final topSoft = brand.inkSoft;
    final statPillBg = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.62);

    const firstCardShadow = <BoxShadow>[];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SpendingOverviewCard(
          visible: visible,
          onToggleVisibility: () =>
              ref.read(balanceVisibleProvider.notifier).toggle(),
          selectedMonth: selectedMonth,
          symbol: symbol,
          monthSpent: monthSpent,
          background: topBg,
          ink: topInk,
          soft: topSoft,
          statPillBg: statPillBg,
          shadows: firstCardShadow,
          isDark: isDark,
          hasForeignExpense: hasForeignExpense,
          budget: budget,
          budgetSpent: budgetSpent,
          budgetProgress: budgetProgress,
          onBudgetTap: () {
            ref.read(homeTabIndexProvider.notifier).state = 2;
            ref.read(openBudgetPopupProvider.notifier).state = true;
          },
        ),
        const SizedBox(height: 12),
        const _QuickAddCard(),
      ],
    );
  }
}

class _SpendingOverviewCard extends StatelessWidget {
  final bool visible;
  final VoidCallback onToggleVisibility;
  final DateTime selectedMonth;
  final String symbol;
  final double monthSpent;
  final Color background;
  final Color ink;
  final Color soft;
  final Color statPillBg;
  final List<BoxShadow> shadows;
  final bool isDark;
  final bool hasForeignExpense;
  final double budget;
  final double budgetSpent;
  final double budgetProgress;
  final VoidCallback? onBudgetTap;

  const _SpendingOverviewCard({
    required this.visible,
    required this.onToggleVisibility,
    required this.selectedMonth,
    required this.symbol,
    required this.monthSpent,
    required this.background,
    required this.ink,
    required this.soft,
    required this.statPillBg,
    required this.shadows,
    required this.isDark,
    required this.hasForeignExpense,
    this.budget = 0,
    this.budgetSpent = 0,
    this.budgetProgress = 0,
    this.onBudgetTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final hasBudget = budget > 0;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(24),
        boxShadow: shadows,
      ),
      child: Stack(
        children: [
          Positioned(
            right: 56,
            top: 12,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: 0.34,
                child: Container(
                  width: 98,
                  height: 120,
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : brand.inkSoft.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(28),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -2,
            top: 54,
            child: IgnorePointer(
              child: Transform.rotate(
                angle: -0.16,
                child: Container(
                  width: 86,
                  height: 88,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: isDark ? 0.05 : 0.40),
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _MonthChip(month: selectedMonth, ink: ink, isDark: isDark),
                    const Spacer(),
                    Semantics(
                      button: true,
                      label: visible
                          ? context.t('home.hideBalance')
                          : context.t('home.showBalance'),
                      child: GestureDetector(
                        onTap: onToggleVisibility,
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 2,
                            vertical: 4,
                          ),
                          child: Text(
                            context.t('home.spent'),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: soft,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _HeroAmount(
                  visible: visible,
                  symbol: symbol,
                  amount: monthSpent,
                  ink: ink,
                  soft: soft,
                  hasForeign: hasForeignExpense,
                ),
                if (hasBudget) ...[
                  const SizedBox(height: 10),
                  _InlineBudgetBar(
                    visible: visible,
                    symbol: symbol,
                    budget: budget,
                    budgetSpent: budgetSpent,
                    budgetProgress: budgetProgress,
                    ink: ink,
                    soft: soft,
                    isDark: isDark,
                    onTap: onBudgetTap,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  final DateTime month;
  final Color ink;
  final bool isDark;

  const _MonthChip({
    required this.month,
    required this.ink,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: isDark ? 0.10 : 0.78),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(CupertinoIcons.calendar, size: 12, color: ink),
          const SizedBox(width: 6),
          Text(
            DateFormat('MMM yyyy').format(month),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: ink,
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroAmount extends StatelessWidget {
  final bool visible;
  final String symbol;
  final double amount;
  final Color ink;
  final Color soft;
  final bool hasForeign;

  const _HeroAmount({
    required this.visible,
    required this.symbol,
    required this.amount,
    required this.ink,
    required this.soft,
    this.hasForeign = false,
  });

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      return Text(
        '$symbol ****',
        style: TextStyle(
          fontSize: 42,
          fontWeight: FontWeight.w700,
          color: ink,
          height: 1,
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        if (hasForeign) ...[
          Text(
            context.t('common.est'),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              color: soft,
              letterSpacing: -0.12,
              height: 1,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Text(
          symbol,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: soft,
            height: 1,
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            formatMoney('', amount).trim(),
            style: TextStyle(
              fontSize: 48,
              fontWeight: FontWeight.w700,
              color: ink,
              height: 0.96,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
          ),
        ),
      ],
    );
  }
}

// ── Inline budget bar (inside spending card) ──────────────────

class _InlineBudgetBar extends StatelessWidget {
  final bool visible;
  final String symbol;
  final double budget;
  final double budgetSpent;
  final double budgetProgress;
  final Color ink;
  final Color soft;
  final bool isDark;
  final VoidCallback? onTap;

  const _InlineBudgetBar({
    required this.visible,
    required this.symbol,
    required this.budget,
    required this.budgetSpent,
    required this.budgetProgress,
    required this.ink,
    required this.soft,
    required this.isDark,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final overspent = budgetSpent > budget;
    final barColor = overspent ? AppColors.expense : AppColors.income;
    final pct = (budgetProgress * 100).clamp(0.0, 100.0);
    final remaining = budget - budgetSpent;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: barColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                context.t('home.budget'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: soft,
                ),
              ),
              const SizedBox(width: 4),
              if (onTap != null)
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 9,
                  color: soft.withValues(alpha: 0.7),
                ),
              const Spacer(),
              Text(
                visible
                    ? overspent
                        ? '-${formatMoney(symbol, -remaining)}  ·  ${pct.toStringAsFixed(0)}%'
                        : '${formatMoney(symbol, remaining)} ${context.t('common.left')}  ·  ${pct.toStringAsFixed(0)}%'
                    : '$symbol ****',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: overspent ? AppColors.expense : soft,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.0, end: budgetProgress),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeOutCubic,
            builder: (context, animatedProgress, _) => ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(
                children: [
                  Container(
                    height: 4,
                    width: double.infinity,
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : barColor.withValues(alpha: 0.15),
                  ),
                  FractionallySizedBox(
                    widthFactor: animatedProgress.clamp(0.0, 1.0),
                    child: Container(
                      height: 4,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Quick add card ──────────────────────────────────────────────

class _QuickAddCard extends ConsumerStatefulWidget {
  const _QuickAddCard();

  @override
  ConsumerState<_QuickAddCard> createState() => _QuickAddCardState();
}

class _QuickAddCardState extends ConsumerState<_QuickAddCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  bool _editMode = false;
  late final AnimationController _jiggleCtrl;

  @override
  void initState() {
    super.initState();
    _jiggleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _jiggleCtrl.dispose();
    super.dispose();
  }

  List<_QuickItem> _allItems(bool isDark) => [
    _QuickItem(
      icon: CupertinoIcons.minus,
      labelKey: 'expense.expense',
      iconBg: isDark ? const Color(0xFF7C3AED).withValues(alpha: 0.22) : const Color(0xFFEFEBFF),
      iconColor: const Color(0xFF7C3AED),
      pageBuilder: () => const AddEditExpenseScreen(initialType: EntryType.expense),
    ),
    _QuickItem(
      icon: CupertinoIcons.plus,
      labelKey: 'expense.income',
      iconBg: isDark ? const Color(0xFF22C55E).withValues(alpha: 0.20) : const Color(0xFFE8FBF0),
      iconColor: const Color(0xFF22C55E),
      pageBuilder: () => const AddEditExpenseScreen(initialType: EntryType.income),
    ),
    _QuickItem(
      icon: CupertinoIcons.arrow_right_arrow_left,
      labelKey: 'expense.transfer',
      iconBg: isDark ? const Color(0xFFEF4444).withValues(alpha: 0.18) : const Color(0xFFFFEEEE),
      iconColor: const Color(0xFFEF4444),
      pageBuilder: () => const AddEditExpenseScreen(initialType: EntryType.transfer),
    ),
    _QuickItem(
      icon: CupertinoIcons.arrow_down_circle,
      labelKey: 'expense.receive',
      iconBg: isDark ? const Color(0xFF7C3AED).withValues(alpha: 0.22) : const Color(0xFFEFEBFF),
      iconColor: const Color(0xFF7C3AED),
      pageBuilder: () => const AddEditExpenseScreen(initialType: EntryType.receive),
    ),
    _QuickItem(
      icon: CupertinoIcons.viewfinder,
      labelKey: 'home.scanReceipt',
      iconBg: isDark ? const Color(0xFFF97316).withValues(alpha: 0.18) : const Color(0xFFFFF3E8),
      iconColor: const Color(0xFFF97316),
      pageBuilder: () => const ImportReceiptScreen(openCamera: true),
    ),
    _QuickItem(
      icon: CupertinoIcons.person_2,
      labelKey: 'travel.groupTrip',
      iconBg: isDark ? const Color(0xFFE86E2C).withValues(alpha: 0.18) : const Color(0xFFFFF0E8),
      iconColor: const Color(0xFFE86E2C),
      pageBuilder: () => const TravelGroupsScreen(),
    ),
  ];

  // Move the action at position [from] to position [to] within the saved
  // order, using remove-at/insert-at semantics shared with the grid.
  void _reorder(int from, int to) {
    if (from == to) return;
    final order = List<int>.from(ref.read(quickAddOrderProvider));
    if (from < 0 || from >= order.length) return;
    final moved = order.removeAt(from);
    order.insert(to.clamp(0, order.length), moved);
    ref.read(quickAddOrderProvider.notifier).setOrder(order);
    HapticFeedback.selectionClick();
  }

  // Tile content for one action; jiggles while in edit mode (drag handling
  // lives in [ReorderableTileGrid]).
  Widget _quickTile(_QuickItem item, int i) {
    final button = _QuickAddButton(item: item);
    if (!_editMode) return button;
    return AnimatedBuilder(
      animation: _jiggleCtrl,
      builder: (_, child) {
        final dir = i.isEven ? 1.0 : -1.0;
        final angle = 0.03 * dir * (_jiggleCtrl.value * 2 - 1);
        return Transform.rotate(angle: angle, child: child);
      },
      child: button,
    );
  }

  // The floating widget shown under the finger while dragging an action.
  Widget _dragFeedback(_QuickItem item, double width, BrandColors brand) {
    return Material(
      color: Colors.transparent,
      child: SizedBox(
        width: width,
        height: 82,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: item.iconBg,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Icon(item.icon, color: item.iconColor, size: 21),
            ),
            const SizedBox(height: 6),
            Text(
              context.t(item.labelKey),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: brand.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final order = ref.watch(quickAddOrderProvider);
    final all = _allItems(isDark);
    final ordered = order.map((i) => all[i]).toList();

    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onTap: () {
        HapticFeedback.selectionClick();
        if (_editMode) {
          setState(() => _editMode = false);
        } else {
          setState(() => _expanded = !_expanded);
        }
      },
      child: Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                context.t('quickAdd.title'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
          // Rearrange affordance — kept identical to the Manage page: same
          // hint/active text plus a Done button while reordering.
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            alignment: Alignment.topLeft,
            child: _expanded
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 0, 0),
                    child: Row(
                      children: [
                        Icon(
                          _editMode
                              ? CupertinoIcons.checkmark_circle_fill
                              : CupertinoIcons.arrow_up_arrow_down,
                          size: 12,
                          color: _editMode
                              ? AppActionBlue.color
                              : brand.inkSoft,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          _editMode
                              ? context.t('budget.reorderActive')
                              : context.t('budget.reorderHint'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _editMode
                                ? AppActionBlue.color
                                : brand.inkSoft,
                          ),
                        ),
                        const Spacer(),
                        if (_editMode)
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _editMode = false);
                            },
                            child: Text(
                              context.t('budget.done'),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppActionBlue.color,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (ctx, constraints) {
              const tileH = 82.0;
              const gap = 10.0;
              final cellW = (constraints.maxWidth - gap * 2) / 3;
              final rows = ((ordered.length - 1) ~/ 3) + 1;
              final fullHeight = rows * tileH + (rows - 1) * gap;
              // Collapsed shows only the first row; expanding reveals the rest
              // and unlocks drag-to-rearrange.
              return AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: SizedBox(
                  height: _expanded ? fullHeight : tileH,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: fullHeight,
                      maxHeight: fullHeight,
                      child: ReorderableTileGrid(
                        itemCount: ordered.length,
                        columns: 3,
                        spacing: gap,
                        runSpacing: gap,
                        tileHeight: tileH,
                        enabled: _expanded,
                        itemKeys: order,
                        itemBuilder: (_, i) => _quickTile(ordered[i], i),
                        feedbackBuilder: (_, i) =>
                            _dragFeedback(ordered[i], cellW, brand),
                        onDragStart: () {
                          HapticFeedback.mediumImpact();
                          if (!_editMode) setState(() => _editMode = true);
                        },
                        onReorder: _reorder,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 6),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 20),
              child: AnimatedRotation(
                turns: _expanded ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                child: Icon(
                  CupertinoIcons.chevron_down,
                  size: 14,
                  color: brand.inkSoft,
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

class _QuickItem {
  final IconData icon;
  final String labelKey;
  final Color iconBg;
  final Color iconColor;
  final Widget Function() pageBuilder;

  const _QuickItem({
    required this.icon,
    required this.labelKey,
    required this.iconBg,
    required this.iconColor,
    required this.pageBuilder,
  });
}

class _QuickAddButton extends StatefulWidget {
  final _QuickItem item;

  const _QuickAddButton({required this.item});

  @override
  State<_QuickAddButton> createState() => _QuickAddButtonState();
}

class _QuickAddButtonState extends State<_QuickAddButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      lowerBound: 0.94,
      upperBound: 1.0,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  void _navigate() {
    Navigator.push(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (ctx, anim, secAnim) => widget.item.pageBuilder(),
        transitionDuration: const Duration(milliseconds: 340),
        reverseTransitionDuration: const Duration(milliseconds: 260),
        transitionsBuilder: (ctx, animation, secAnim, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.88, end: 1.0).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTapDown: (_) => _press.reverse(),
      onTapUp: (_) {
        _press.forward();
        _navigate();
      },
      onTapCancel: () => _press.forward(),
      child: ScaleTransition(
        scale: _press,
        child: SizedBox(
          height: 82,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: widget.item.iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  widget.item.icon,
                  color: widget.item.iconColor,
                  size: 21,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.t(widget.item.labelKey),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
                ),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── All Activity bottom sheet ──────────────────────────────────

class _AllBillsSheet extends ConsumerStatefulWidget {
  final List<_ActivityItem> items;
  final double total;
  final String symbol;
  final DateTime month;

  const _AllBillsSheet({
    required this.items,
    required this.total,
    required this.symbol,
    required this.month,
  });

  @override
  ConsumerState<_AllBillsSheet> createState() => _AllBillsSheetState();
}

class _AllBillsSheetState extends ConsumerState<_AllBillsSheet> {
  final _coordinator = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _coordinator.dispose();
    super.dispose();
  }

  Future<void> _deleteExpense(BuildContext context, Expense expense) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    final uid = user.uid;
    try {
      final isOnline =
          storageMode == StorageMode.firebase && ref.read(isOnlineProvider);
      // If this is a split-bill settlement record, revert the member to owing.
      await SplitSettlementService.revertIfSettlement(
        uid: uid,
        expenseId: expense.id,
        isOnline: isOnline,
      );
      // If this is a split-bill source, remove its bill + collected settlement
      // "receive" expenses too.
      await SplitSettlementService.deleteBillForSourceExpense(
        uid: uid,
        expenseId: expense.id,
        isOnline: isOnline,
      );
      if (storageMode == StorageMode.firebase) {
        await SyncService().deleteExpense(
          userId: uid,
          expenseId: expense.id,
          isOnline: isOnline,
        );
      } else {
        await LocalExpenseRepository().deleteExpense(uid, expense.id);
      }
      ref.invalidate(allSplitBillsProvider);
      if (!context.mounted) return;
      AppToast.show(
        context,
        context.t('expense.entryDeleted'),
        type: AppToastType.info,
        icon: CupertinoIcons.trash,
      );
    } catch (_) {
      if (!context.mounted) return;
      AppToast.show(
        context,
        context.t('common.error'),
        type: AppToastType.error,
        icon: CupertinoIcons.exclamationmark_circle_fill,
      );
    }
  }

  void _copyRecord(BuildContext context, Expense original) {
    AppToast.show(
      context,
      context.t('metal.copiedToast'),
      type: AppToastType.info,
      icon: CupertinoIcons.doc_on_doc,
    );
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => AddEditExpenseScreen(copyFrom: original),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: brand.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.t('home.activity'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('MMMM yyyy').format(widget.month),
                      style: TextStyle(
                        fontSize: 12,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              CircleIconButton(
                icon: CupertinoIcons.xmark,
                size: 34,
                background: brand.surface,
                foreground: brand.ink,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    formatMoney(widget.symbol, widget.total),
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${widget.items.length} ${widget.items.length == 1 ? context.t('common.entry') : context.t('common.entries')}',
                  style: TextStyle(
                    fontSize: 12,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: NotificationListener<ScrollNotification>(
              onNotification: (_) {
                _coordinator.value = null;
                return false;
              },
              child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _coordinator.value = null,
              child: Container(
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: widget.items.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 70),
                      child: Container(height: 0.5, color: brand.divider),
                    ),
                    itemBuilder: (ctx, i) {
                      final item = widget.items[i];
                      final expense = item.expense;
                      if (expense == null) {
                        // Precious metal or stock transaction row.
                        return _AssetActivityRow(
                          item: item,
                          symbol: widget.symbol,
                        );
                      }
                      final acct = accounts
                          .where((a) => a.id == expense.accountId)
                          .firstOrNull;
                      return ExpenseCard(
                        key: ValueKey(expense.id),
                        coordinator: _coordinator,
                        rowId: expense.id,
                        expense: expense,
                        currencySymbol: widget.symbol,
                        account: acct,
                        flat: true,
                        onTap: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) =>
                                AddEditExpenseScreen(expense: expense),
                          ),
                        ),
                        onEdit: () => Navigator.push(
                          context,
                          CupertinoPageRoute(
                            builder: (_) =>
                                AddEditExpenseScreen(expense: expense),
                          ),
                        ),
                        onDelete: () => _deleteExpense(context, expense),
                        onCopy: () => _copyRecord(context, expense),
                      );
                    },
                  ),
                ),
              ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoordinatedList extends StatefulWidget {
  final Widget Function(ValueNotifier<String?> coordinator) builder;
  const _CoordinatedList({required this.builder});

  @override
  State<_CoordinatedList> createState() => _CoordinatedListState();
}

class _CoordinatedListState extends State<_CoordinatedList> {
  final _coord = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _coord.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_coord);
}
