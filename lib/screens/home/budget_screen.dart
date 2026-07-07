import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_config.dart';
import '../../models/account.dart';
import '../../models/category_catalog.dart';
import '../../models/expense.dart';
import '../../models/monthly_budget.dart';
import '../../models/precious_metal.dart';
import '../../models/stock_investment.dart';
import '../../repositories/local_expense_repository.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../services/prefs_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/account_carousel_section.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/exchange_rate_sheet.dart';
import '../../widgets/fading_edge_list.dart';
import '../../widgets/reorderable_tile_grid.dart';
import '../../widgets/section_card.dart';
import '../../widgets/sticky_header_scaffold.dart';
import '../borrow_lending/borrow_lending_screen.dart';
import '../installments/installments_screen.dart';
import '../investments/investment_screen.dart';
import '../people/people_screen.dart';
import '../savings/saving_plans_screen.dart';
import '../travel/travel_groups_screen.dart';
import '../group/create_group_screen.dart';
import '../group/group_dashboard_screen.dart';

/// Expense categories offered in the by-category budget editor: built-ins
/// followed by the user's custom expense categories (same set as the expense
/// picker uses).
List<String> _budgetCategories(WidgetRef ref) {
  final custom =
      ((ref.read(customCategoriesProvider).valueOrNull ?? const [])
              .where((c) => !c.isIncome)
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
          .map((c) => c.name)
          .toList();
  // Custom categories first (most-recently-added), then the built-ins —
  // matching the expense picker order.
  return [...custom, ...kDefaultExpenseCategories];
}

Future<void> showMonthlyBudgetEditor(
  BuildContext context,
  WidgetRef ref,
  double current,
  String symbol,
  String? userId,
) async {
  if (userId == null) return;
  // Await the saved config so previously-entered category amounts are
  // pre-filled (the provider may not be actively subscribed on this screen,
  // in which case `.valueOrNull` would be null).
  MonthlyBudget initial;
  try {
    initial = await ref.read(budgetConfigProvider.future);
  } catch (_) {
    initial = MonthlyBudget(total: current);
  }
  if (!context.mounted) return;
  final categories = _budgetCategories(ref);

  final result = await showModalBottomSheet<MonthlyBudget>(
    context: context,
    isScrollControlled: true,
    backgroundColor: context.brand.background,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (ctx) => _BudgetEditorSheet(
      initial: initial,
      symbol: symbol,
      categories: categories,
    ),
  );
  if (result != null) {
    try {
      await ref.read(expenseRepositoryProvider).setBudgetConfig(userId, result);
      // Mirror to local so budget is available offline.
      if (storageMode == StorageMode.firebase) {
        await LocalExpenseRepository().setBudgetConfig(userId, result);
      }
      if (context.mounted) {
        AppToast.show(
          context,
          context.t('budget.updated'),
          type: AppToastType.success,
        );
      }
    } catch (_) {
      if (context.mounted) {
        AppToast.show(
          context,
          context.t('budget.failedToSave'),
          type: AppToastType.error,
        );
      }
    }
  }
}

/// Budget editor with a Total / By-category toggle.
class _BudgetEditorSheet extends StatefulWidget {
  final MonthlyBudget initial;
  final String symbol;
  final List<String> categories;

  const _BudgetEditorSheet({
    required this.initial,
    required this.symbol,
    required this.categories,
  });

  @override
  State<_BudgetEditorSheet> createState() => _BudgetEditorSheetState();
}

class _BudgetEditorSheetState extends State<_BudgetEditorSheet> {
  late final TextEditingController _totalCtrl;
  late final Map<String, TextEditingController> _catCtrls;

  @override
  void initState() {
    super.initState();
    _totalCtrl = TextEditingController(
      text: widget.initial.effectiveTotal > 0
          ? _fmt(widget.initial.effectiveTotal)
          : '',
    );
    _catCtrls = {
      for (final c in widget.categories)
        c: TextEditingController(
          text: (widget.initial.categories[c] ?? 0) > 0
              ? _fmt(widget.initial.categories[c]!)
              : '',
        ),
    };
    for (final c in _catCtrls.values) {
      c.addListener(_onCategoryChanged);
    }
    _totalCtrl.addListener(_onTotalChanged);
  }

  @override
  void dispose() {
    _totalCtrl.dispose();
    for (final c in _catCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  static String _fmt(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

  double get _categoryTotal =>
      _catCtrls.values.fold(0.0, (s, c) => s + (double.tryParse(c.text) ?? 0));

  double get _typedTotal => double.tryParse(_totalCtrl.text) ?? 0;

  // When the categories add up to more than the entered total, the total grows
  // to match (the total can never be less than what's allocated).
  void _onCategoryChanged() {
    final sum = _categoryTotal;
    if (sum > _typedTotal) {
      final txt = _fmt(sum);
      if (_totalCtrl.text != txt) {
        _totalCtrl.value = TextEditingValue(
          text: txt,
          selection: TextSelection.collapsed(offset: txt.length),
        );
      }
    }
    setState(() {});
  }

  void _onTotalChanged() {
    // Live: as the user types the total, if it drops below what's allocated
    // across categories, reset the by-category section first (more friendly).
    _resetCategoriesIfBelowTotal();
    setState(() {});
  }

  // When the user manually sets a total below what's currently allocated across
  // categories, the by-category section is reset (cleared) so the total wins.
  void _resetCategoriesIfBelowTotal() {
    final typed = _typedTotal;
    if (typed <= 0 || typed >= _categoryTotal) return;
    for (final c in _catCtrls.values) {
      if (c.text.isNotEmpty) c.text = '';
    }
    setState(() {});
  }

  void _save() {
    _resetCategoriesIfBelowTotal();
    final map = <String, double>{};
    _catCtrls.forEach((k, c) {
      final v = double.tryParse(c.text) ?? 0;
      if (v > 0) map[k] = v;
    });
    final sum = map.values.fold(0.0, (s, v) => s + v);
    final typed = _typedTotal;
    Navigator.pop(
      context,
      MonthlyBudget(
        mode: map.isNotEmpty ? BudgetMode.category : BudgetMode.total,
        total: typed > sum ? typed : sum,
        categories: map,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final media = MediaQuery.of(context);
    return Padding(
      // Lift the whole sheet above the keyboard so the Save button is never
      // covered by the numpad.
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Column(
            // Min height: the sheet is only as tall as its content (the
            // category list is internally capped + scrollable), so it stays
            // compact instead of filling the screen.
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
              Text(
                context.t('budget.setMonthlyBudget'),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                context.t('budget.sheetSubtitle'),
                style: TextStyle(color: brand.inkSoft, fontSize: 12),
              ),
              const SizedBox(height: 16),
              // Overall total cap.
              _totalField(brand),
              const SizedBox(height: 8),
              _allocatedHint(brand),
              const SizedBox(height: 14),
              Text(
                context.t('budget.byCategoryTitle'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                  color: brand.inkSoft,
                ),
              ),
              const SizedBox(height: 8),
              // Cap the list to the space left after the keyboard / status bar
              // so the title never runs off the top; scrolls past the cap.
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: _listMaxHeight(context)),
                child: FadingEdgeList(
                  fadeColor: brand.background,
                  topHeight: 16,
                  bottomHeight: 24,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final cat in widget.categories)
                          _categoryRow(cat, brand),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _save,
                child: Text(context.t('common.save')),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _totalField(BrandColors brand) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Row(
        children: [
          Text(
            context.t('budget.totalLabel'),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: brand.ink,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _totalCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.right,
              textInputAction: TextInputAction.done,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                isDense: true,
                prefixText: '${widget.symbol} ',
                hintText: '0',
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _allocatedHint(BrandColors brand) {
    final alloc = _categoryTotal;
    final total = _typedTotal > alloc ? _typedTotal : alloc;
    return Text(
      context
          .t('budget.allocatedOf')
          .replaceAll('{alloc}', formatMoney(widget.symbol, alloc))
          .replaceAll('{total}', formatMoney(widget.symbol, total)),
      style: TextStyle(fontSize: 12, color: brand.inkSoft),
    );
  }

  // Available height for the category list given the current keyboard inset.
  double _listMaxHeight(BuildContext context) {
    final media = MediaQuery.of(context);
    // Fixed chrome above/below the list (handle, title, subtitle, toggle,
    // total card, Save) plus extra breathing room so the title sits well clear
    // of the status bar when the numpad is up.
    const fixedChrome = 430.0;
    final available =
        media.size.height -
        media.viewInsets.bottom -
        media.padding.top -
        fixedChrome;
    return available.clamp(110.0, media.size.height * 0.30);
  }

  Widget _categoryRow(String cat, BrandColors brand) {
    final s = styleFor(cat);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = isDark
        ? Color.lerp(s.accent, Colors.white, 0.5)!
        : s.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: s.background.withValues(alpha: isDark ? 0.22 : 1),
              shape: BoxShape.circle,
            ),
            child: Icon(s.icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              context.categoryLabel(cat),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: brand.ink,
              ),
            ),
          ),
          SizedBox(
            width: 120,
            child: TextField(
              controller: _catCtrls[cat],
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              textAlign: TextAlign.right,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                isDense: true,
                prefixText: '${widget.symbol} ',
                hintText: '0',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class BudgetScreen extends ConsumerStatefulWidget {
  const BudgetScreen({super.key});

  @override
  ConsumerState<BudgetScreen> createState() => _BudgetScreenState();
}

class _BudgetScreenState extends ConsumerState<BudgetScreen>
    with SingleTickerProviderStateMixin {
  // Long-press "edit mode" for rearranging the quick-action tiles, with the
  // iOS home-screen style jiggle while active.
  bool _hubEditMode = false;
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

  void _enterHubEdit() {
    if (_hubEditMode) return;
    HapticFeedback.mediumImpact();
    setState(() => _hubEditMode = true);
  }

  void _exitHubEdit() {
    if (!_hubEditMode) return;
    setState(() => _hubEditMode = false);
  }

  String _moduleLabel(BuildContext context, String id) => switch (id) {
    'installments' => context.t('budget.manageInstallments'),
    'borrowLending' => context.t('tools.borrowLending'),
    'savingPlans' => context.t('tools.savingPlans'),
    'monthlyBudget' => context.t('home.budget'),
    'people' => context.t('budget.people'),
    'travelGroups' => context.t('travel.title'),
    'investments' => context.t('budget.investments'),
    'groups' => context.t('budget.groupsLabel'),
    'expenseCycle' => context.t('budget.expenseCycle'),
    _ => id,
  };

  void _hideModule(String id) {
    HapticFeedback.selectionClick();
    ref.read(moneyHubVisibilityProvider.notifier).setVisible(id, false);
  }

  void _showAddModuleSheet(BuildContext context) {
    final visible = ref.read(moneyHubVisibilityProvider);
    final hidden = PrefsService.defaultMoneyHubModules
        .where((id) => !visible.contains(id))
        .toList(growable: false);
    if (hidden.isEmpty) return;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final brand = ctx.brand;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
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
                Text(
                  context.t('money.addModule'),
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                ),
                const SizedBox(height: 14),
                for (final id in hidden)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        HapticFeedback.selectionClick();
                        ref
                            .read(moneyHubVisibilityProvider.notifier)
                            .setVisible(id, true);
                        Navigator.pop(ctx);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: brand.surface,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _moduleLabel(context, id),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: brand.ink,
                                ),
                              ),
                            ),
                            Icon(
                              CupertinoIcons.add_circled_solid,
                              size: 22,
                              color: AppActionBlue.color,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Applies a remove-at-[from] / insert-at-[to] reorder of the visible
  /// [reorderableIds] back onto the full saved money-hub order, leaving any
  /// hidden modules in their existing slots.
  void _reorderHub(List<String> reorderableIds, int from, int to) {
    if (from == to) return;
    final reordered = [...reorderableIds];
    if (from < 0 || from >= reordered.length) return;
    final moved = reordered.removeAt(from);
    reordered.insert(to.clamp(0, reordered.length), moved);

    final full = [...ref.read(moneyHubOrderProvider)];
    final visible = reorderableIds.toSet();
    var next = 0;
    for (var i = 0; i < full.length && next < reordered.length; i++) {
      if (visible.contains(full[i])) full[i] = reordered[next++];
    }
    for (; next < reordered.length; next++) {
      if (!full.contains(reordered[next])) full.add(reordered[next]);
    }
    ref.read(moneyHubOrderProvider.notifier).setOrder(full);
    HapticFeedback.selectionClick();
  }

  /// Tile content for one quick-action. Rearrangeable modules jiggle while in
  /// edit mode; the drag handling itself lives in [ReorderableTileGrid].
  Widget _hubTile(_BudgetQuickItem item, bool canHide) {
    // Every tile is hideable; the hide badge sits on the icon corner inside the
    // button so it stays aligned. The badge is omitted on the last remaining
    // tile so at least one always stays. ('expenseCycle' stays pinned/
    // non-draggable via the grid's reorderableCount, but still jiggles + hides.)
    final button = _BudgetQuickButton(
      item: item,
      editMode: _hubEditMode,
      onHide: (_hubEditMode && canHide) ? () => _hideModule(item.id) : null,
    );
    if (!_hubEditMode) return button;
    return AnimatedBuilder(
      animation: _jiggleCtrl,
      builder: (_, child) {
        final dir = item.id.hashCode.isEven ? 1.0 : -1.0;
        final angle = 0.03 * dir * (_jiggleCtrl.value * 2 - 1);
        return Transform.rotate(angle: angle, child: child);
      },
      child: button,
    );
  }

  @override
  Widget build(BuildContext context) {
    final budget = ref.watch(budgetProvider).valueOrNull ?? 0.0;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final user = ref.watch(authStateProvider).valueOrNull;
    final visibleModules = ref.watch(moneyHubVisibilityProvider);

    // Open the budget popup when navigated from the home budget bar.
    final openPopup = ref.watch(openBudgetPopupProvider);
    if (openPopup) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref.read(openBudgetPopupProvider.notifier).state = false;
        showMonthlyBudgetEditor(context, ref, budget, symbol, user?.uid);
      });
    }
    // Accounts for carousel
    final accounts =
        ref.watch(accountsProvider).valueOrNull ?? const <Account>[];
    final allExpenses =
        ref.watch(allExpensesProvider).valueOrNull ?? const <Expense>[];
    final visible = ref.watch(balanceVisibleProvider);
    final groups = ref.watch(myGroupsProvider).valueOrNull ?? const [];

    final metals =
        ref.watch(preciousMetalsProvider).valueOrNull ??
        const <PreciousMetal>[];
    final stocks =
        ref.watch(stockInvestmentsProvider).valueOrNull ??
        const <StockInvestment>[];
    final converter = ref.watch(currencyConverterProvider).valueOrNull;
    // Account balances use the shared canonical calculation so Budget tallies
    // with Manage / Summary / Profile (includes metals & stocks).
    final accountBalances = computeAccountBalanceMap(
      accounts,
      allExpenses,
      metals: metals,
      stocks: stocks,
      toBase: converter == null
          ? null
          : (amt, code) => converter.toBase(amt, code),
    );

    // ── Quick-style button items — standard modules first, tools at end ─────────
    final someoneOwesYou = ref.watch(someoneOwesYouProvider);
    final quickItems = <_BudgetQuickItem>[
      if (visibleModules.contains('monthlyBudget'))
        _BudgetQuickItem(
          id: 'monthlyBudget',
          icon: CupertinoIcons.chart_pie_fill,
          iconBg: AppColors.lilac,
          iconColor: kCategoryStyles['Shopping']!.accent,
          label: context.t('budget.badgeBudget'),
          onTap: () =>
              showMonthlyBudgetEditor(context, ref, budget, symbol, user?.uid),
        ),
      if (visibleModules.contains('savingPlans'))
        _BudgetQuickItem(
          id: 'savingPlans',
          icon: CupertinoIcons.flag_fill,
          iconBg: const Color(0xFFE8F5E9),
          iconColor: const Color(0xFF34C759),
          label: context.t('budget.badgeSavings'),
          onTap: () => _push(context, const SavingPlansScreen()),
        ),
      if (visibleModules.contains('borrowLending'))
        _BudgetQuickItem(
          id: 'borrowLending',
          icon: CupertinoIcons.arrow_up_arrow_down,
          iconBg: const Color(0xFFFFF3E0),
          iconColor: const Color(0xFFF57C00),
          label: context.t('budget.badgeLending'),
          onTap: () => _push(context, const BorrowLendingScreen()),
        ),
      if (visibleModules.contains('installments'))
        _BudgetQuickItem(
          id: 'installments',
          icon: CupertinoIcons.bolt_fill,
          iconBg: const Color(0xFFFCE4EC),
          iconColor: const Color(0xFFE91E63),
          label: context.t('budget.badgeInstallments'),
          onTap: () => _push(context, const InstallmentsScreen()),
        ),
      if (visibleModules.contains('people'))
        _BudgetQuickItem(
          id: 'people',
          icon: CupertinoIcons.person_2_fill,
          iconBg: AppColors.lilac,
          iconColor: kCategoryStyles['Shopping']!.accent,
          label: context.t('budget.badgePeople'),
          showBadge: someoneOwesYou,
          onTap: () => _push(context, const PeopleScreen()),
        ),
      if (visibleModules.contains('travelGroups'))
        _BudgetQuickItem(
          id: 'travelGroups',
          icon: CupertinoIcons.airplane,
          iconBg: const Color(0xFFE3F2FD),
          iconColor: const Color(0xFF0066CC),
          label: context.t('travel.title'),
          onTap: () => _push(context, const TravelGroupsScreen()),
        ),
      if (visibleModules.contains('investments'))
        _BudgetQuickItem(
          id: 'investments',
          icon: CupertinoIcons.chart_bar_square_fill,
          iconBg: const Color(0xFFEDE7F6),
          iconColor: const Color(0xFF5856D6),
          label: context.t('budget.portfolio'),
          onTap: () => _push(context, const InvestmentScreen()),
        ),
      if (visibleModules.contains('groups'))
        _BudgetQuickItem(
          id: 'groups',
          icon: CupertinoIcons.person_2_fill,
          iconBg: const Color(0xFFEAE3F8),
          iconColor: const Color(0xFF5A4AAB),
          label: context.t('budget.groupsLabel'),
          onTap: () {
            HapticFeedback.selectionClick();
            if (groups.isEmpty) {
              Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => const CreateGroupScreen()),
              );
            } else {
              final activeGroupId = ref.read(activeGroupIdProvider);
              final activeGroup = groups.firstWhere(
                (g) => g.id == activeGroupId,
                orElse: () => groups.first,
              );
              final user = ref.read(authStateProvider).valueOrNull;
              showGroupMenu(context, ref, activeGroup, user?.uid);
            }
          },
        ),
      // ── Tools (pinned at the end, but hideable like the modules) ──────────
      if (visibleModules.contains('expenseCycle'))
        _BudgetQuickItem(
          id: 'expenseCycle',
          icon: CupertinoIcons.calendar_badge_plus,
          iconBg: AppColors.butter,
          iconColor: const Color(0xFFB8870A),
          label: context.t('budget.expenseCycle'),
          onTap: () => _showCycleSheet(context),
        ),
    ];

    // Order every visible tile (including 'expenseCycle') by the saved money-hub
    // order; tiles missing from the saved order are appended.
    final hubOrder = ref.watch(moneyHubOrderProvider);
    final byId = {for (final it in quickItems) it.id: it};
    final reorderableIds = <String>[
      for (final id in hubOrder)
        if (byId.containsKey(id)) id,
      for (final it in quickItems)
        if (!hubOrder.contains(it.id)) it.id,
    ];
    final orderedItems = [for (final id in reorderableIds) byId[id]!];
    final hasHidden = PrefsService.defaultMoneyHubModules.any(
      (id) => !visibleModules.contains(id),
    );

    return SafeArea(
      child: StickyHeaderScaffold(
        header: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.t('money.title'),
                  style: Theme.of(context).textTheme.displayMedium,
                ),
              ),
              Row(
                children: [
                  if (_hubEditMode) ...[
                    if (hasHidden) ...[
                      GlassCircleButton(
                        icon: CupertinoIcons.add,
                        onTap: () => _showAddModuleSheet(context),
                      ),
                      const SizedBox(width: 8),
                    ],
                    GlassCircleButton(
                      icon: CupertinoIcons.checkmark_alt,
                      onTap: _exitHubEdit,
                    ),
                  ] else
                    const FxRateButton(),
                ],
              ),
            ],
          ),
        ),
        bodyBuilder: (sc) => ListView(
          controller: sc,
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
          children: [
            const SizedBox(height: 16),

            // ── Accounts carousel (top section) ──────────────
            AccountCarouselSection(
              accounts: accounts,
              balances: accountBalances,
              allExpenses: allExpenses,
              symbol: symbol,
              visible: visible,
            ),

            const SizedBox(height: 16),

            // ── Quick-action card ─────────────────────────────
            if (orderedItems.isNotEmpty)
              Builder(
                builder: (ctx) {
                  final brand = ctx.brand;
                  return Container(
                    padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Always-visible affordance that tiles can be rearranged
                        // (Done lives in the header tick while editing).
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 4, 8),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                CupertinoIcons.arrow_up_arrow_down,
                                size: 12,
                                color: brand.inkSoft,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                context.t('budget.reorderHint'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: brand.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ReorderableTileGrid(
                          itemCount: orderedItems.length,
                          reorderableCount: reorderableIds.length,
                          columns: 3,
                          spacing: 0,
                          runSpacing: 4,
                          tileHeight: 84,
                          itemKeys: [for (final it in orderedItems) it.id],
                          itemBuilder: (_, i) => _hubTile(
                            orderedItems[i],
                            orderedItems.length > 1,
                          ),
                          feedbackBuilder: (_, i) =>
                              _BudgetQuickButton(item: orderedItems[i]),
                          onDragStart: _enterHubEdit,
                          onReorder: (from, to) =>
                              _reorderHub(reorderableIds, from, to),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ], // end ListView children
        ), // end ListView
      ), // end StickyHeaderScaffold
    );
  }

  static void _push(BuildContext context, Widget screen) {
    HapticFeedback.selectionClick();
    Navigator.push(context, CupertinoPageRoute(builder: (_) => screen));
  }

  static void _showCycleSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      isScrollControlled: true,
      builder: (_) => const _CycleSheetContent(),
    );
  }
}

// ── Expense Cycle sheet (accessible from Management grid) ─────────────────────

class _CycleSheetContent extends ConsumerWidget {
  const _CycleSheetContent();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final useCustom = ref.watch(useCustomCycleProvider);
    final cycleDay = ref.watch(cycleDayStartProvider);

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: brand.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
              child: Text(
                context.t('settings.customExpenseCycle'),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: AppColors.butter,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(
                      CupertinoIcons.calendar_badge_plus,
                      size: 16,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      context.t('settings.customExpenseCycleSub'),
                      style: TextStyle(fontSize: 14, color: brand.inkSoft),
                    ),
                  ),
                  CupertinoSwitch(
                    value: useCustom,
                    activeTrackColor: AppColors.income,
                    onChanged: (v) {
                      HapticFeedback.selectionClick();
                      ref.read(useCustomCycleProvider.notifier).set(v);
                    },
                  ),
                ],
              ),
            ),
            if (useCustom) ...[
              Container(
                height: 0.5,
                color: brand.divider,
                margin: const EdgeInsets.symmetric(horizontal: 14),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _pickCycleDay(context, ref, cycleDay, brand),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: AppColors.mint,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(
                            CupertinoIcons.number,
                            size: 16,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            context.t('settings.cycleStartsOnDay'),
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: brand.ink,
                            ),
                          ),
                        ),
                        Text(
                          '$cycleDay',
                          style: TextStyle(fontSize: 15, color: brand.inkSoft),
                        ),
                        const SizedBox(width: 6),
                        Icon(
                          CupertinoIcons.chevron_right,
                          size: 14,
                          color: brand.inkSoft,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _pickCycleDay(
    BuildContext context,
    WidgetRef ref,
    int current,
    BrandColors brand,
  ) async {
    int selected = current;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (ctx) => Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: brand.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.t('settings.cycleStartsOnDay'),
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(ctx),
                      child: Text(
                        context.t('budget.done'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF0066CC),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                height: 200,
                child: StatefulBuilder(
                  builder: (context, setLocal) => CupertinoPicker(
                    scrollController: FixedExtentScrollController(
                      initialItem: selected - 1,
                    ),
                    itemExtent: 40,
                    onSelectedItemChanged: (i) {
                      selected = i + 1;
                      ref.read(cycleDayStartProvider.notifier).set(selected);
                    },
                    children: List.generate(
                      28,
                      (i) => Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(fontSize: 18, color: brand.ink),
                        ),
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

// ── Budget quick-icon button ───────────────────────────────────

class _BudgetQuickItem {
  final String id;
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  /// Shows a small "attention" dot on the icon (e.g. People when someone owes
  /// the user), mirroring the split-bill badge in the activity list.
  final bool showBadge;

  const _BudgetQuickItem({
    required this.id,
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.label,
    required this.onTap,
    this.showBadge = false,
  });
}

class _BudgetQuickButton extends StatefulWidget {
  final _BudgetQuickItem item;
  final bool editMode;
  final VoidCallback? onHide;
  const _BudgetQuickButton({
    required this.item,
    this.editMode = false,
    this.onHide,
  });

  @override
  State<_BudgetQuickButton> createState() => _BudgetQuickButtonState();
}

class _BudgetQuickButtonState extends State<_BudgetQuickButton>
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

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveBg = isDark
        ? widget.item.iconColor.withValues(alpha: 0.18)
        : widget.item.iconBg;
    return GestureDetector(
      onTapDown: (_) => _press.reverse(),
      onTapUp: (_) {
        _press.forward();
        if (widget.editMode) return;
        HapticFeedback.selectionClick();
        widget.item.onTap();
      },
      onTapCancel: () => _press.forward(),
      child: ScaleTransition(
        scale: _press,
        child: SizedBox(
          height: 84,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: effectiveBg,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isDark
                          ? null
                          : [
                              BoxShadow(
                                color: widget.item.iconBg.withValues(
                                  alpha: 0.55,
                                ),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                    ),
                    child: Icon(
                      widget.item.icon,
                      color: widget.item.iconColor,
                      size: 22,
                    ),
                  ),
                  if (widget.item.showBadge && widget.onHide == null)
                    Positioned(
                      top: -3,
                      right: -3,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE8820E),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                      ),
                    ),
                  if (widget.onHide != null)
                    Positioned(
                      top: -5,
                      left: -5,
                      child: GestureDetector(
                        onTap: widget.onHide,
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: AppColors.expense,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(
                            CupertinoIcons.minus,
                            size: 10,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: brand.ink,
                  letterSpacing: -0.1,
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
