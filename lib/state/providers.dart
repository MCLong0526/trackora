import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_config.dart';
import '../models/account.dart';
import '../models/borrow_lending.dart';
import '../models/expense.dart';
import '../models/installment.dart';
import '../models/app_user.dart';
import '../models/person.dart';
import '../models/precious_metal.dart';
import '../models/saving_plan.dart';
import '../repositories/account_repository.dart';
import '../repositories/borrow_lending_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/firebase_account_repository.dart';
import '../repositories/firebase_borrow_lending_repository.dart';
import '../repositories/firebase_expense_repository.dart';
import '../repositories/firebase_installment_repository.dart';
import '../repositories/firebase_person_repository.dart';
import '../repositories/firebase_precious_metal_repository.dart';
import '../repositories/firebase_saving_plan_repository.dart';
import '../repositories/installment_repository.dart';
import '../repositories/local_account_repository.dart';
import '../repositories/local_borrow_lending_repository.dart';
import '../repositories/local_expense_repository.dart';
import '../repositories/local_installment_repository.dart';
import '../repositories/local_person_repository.dart';
import '../repositories/local_precious_metal_repository.dart';
import '../repositories/local_saving_plan_repository.dart';
import '../repositories/person_repository.dart';
import '../repositories/precious_metal_repository.dart';
import '../repositories/saving_plan_repository.dart';
import '../services/auth_service.dart';
import '../services/borrow_lending_service.dart';
import '../services/currency_converter.dart';
import '../services/exchange_rate_service.dart';
import '../services/fx_preferences_service.dart';
import '../services/expense_service.dart';
import '../services/i18n.dart';
import '../services/installment_service.dart';
import '../services/person_service.dart';
import '../services/prefs_service.dart';
import '../services/saving_plan_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/travel_group_service.dart';
import '../services/watch_service.dart';
import '../services/widget_sync_service.dart';
import '../repositories/travel_group_repository.dart';
import '../repositories/local_travel_group_repository.dart';
import '../repositories/firebase_travel_group_repository.dart';
import '../models/travel_group.dart';
import '../models/travel_expense.dart';
import '../models/stock_investment.dart';
import '../repositories/stock_investment_repository.dart';
import '../repositories/firebase_stock_investment_repository.dart';
import '../services/stock_service.dart';

// ── Network connectivity ──────────────────────────────────────────────────────

/// Emits `true` when the device has internet, `false` when offline.
/// Starts with an immediate check, then streams changes.
final networkStatusProvider = StreamProvider<bool>((ref) async* {
  final initial = await Connectivity().checkConnectivity();
  yield initial.any((r) => r != ConnectivityResult.none);
  yield* Connectivity().onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});

/// `true` if the device currently has internet access.
final isOnlineProvider = Provider<bool>((ref) {
  return ref
      .watch(networkStatusProvider)
      .maybeWhen(
        data: (online) => online,
        orElse: () => true, // assume online until we know otherwise
      );
});

final authServiceProvider = Provider((_) => AuthService());

final accountRepositoryProvider = Provider<AccountRepository>((_) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalAccountRepository();
    case StorageMode.firebase:
      return FirebaseAccountRepository();
  }
});

/// Stream of all accounts for the active user.
final accountsProvider = StreamProvider.autoDispose<List<Account>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.read(accountRepositoryProvider).getAll(user.uid);
});
final expenseRepositoryProvider = Provider<ExpenseRepository>((_) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalExpenseRepository();
    case StorageMode.firebase:
      return FirebaseExpenseRepository();
  }
});
final installmentRepositoryProvider = Provider<InstallmentRepository>((_) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalInstallmentRepository();
    case StorageMode.firebase:
      return FirebaseInstallmentRepository();
  }
});
final expenseServiceProvider = Provider(
  (ref) => ExpenseService(ref.read(expenseRepositoryProvider)),
);
final installmentServiceProvider = Provider(
  (ref) => InstallmentService(
    repository: ref.read(installmentRepositoryProvider),
  ),
);

final borrowLendingRepositoryProvider = Provider<BorrowLendingRepository>((_) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalBorrowLendingRepository();
    case StorageMode.firebase:
      return FirebaseBorrowLendingRepository();
  }
});
final borrowLendingServiceProvider = Provider(
  (ref) => BorrowLendingService(ref.read(borrowLendingRepositoryProvider)),
);

final savingPlanRepositoryProvider = Provider<SavingPlanRepository>((_) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalSavingPlanRepository();
    case StorageMode.firebase:
      return FirebaseSavingPlanRepository();
  }
});
final savingPlanServiceProvider = Provider(
  (ref) => SavingPlanService(ref.read(savingPlanRepositoryProvider)),
);

final personRepositoryProvider = Provider<PersonRepository>((_) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalPersonRepository();
    case StorageMode.firebase:
      return FirebasePersonRepository();
  }
});

final personServiceProvider = Provider(
  (ref) => PersonService(ref.read(personRepositoryProvider)),
);

final peopleProvider = StreamProvider.autoDispose<List<Person>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.read(personServiceProvider).getAll(user.uid);
});

/// Stream of all borrow / lending records for the active user.
final borrowLendingProvider = StreamProvider.autoDispose<List<BorrowLending>>((
  ref,
) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.read(borrowLendingServiceProvider).getAll(user.uid);
});

/// Stream of all saving plans for the active user.
final savingPlansProvider = StreamProvider.autoDispose<List<SavingPlan>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.read(savingPlanServiceProvider).getAll(user.uid);
});
final storageServiceProvider = Provider((_) => StorageService());
final prefsServiceProvider = Provider((_) => PrefsService());
final widgetSyncServiceProvider = Provider((_) => WidgetSyncService());
final watchServiceProvider = Provider((_) => WatchService());

final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.read(authServiceProvider).authStateChanges,
);

final selectedMonthProvider = StateProvider<DateTime>((_) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

final expensesProvider = StreamProvider.autoDispose<List<Expense>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  final month = ref.watch(selectedMonthProvider);
  if (storageMode == StorageMode.firebase) {
    final isOnline = ref.watch(isOnlineProvider);
    final pendingCount = ref.watch(pendingExpenseChangeCountProvider);
    // Use local Hive when offline or while pending entries are being synced
    // so newly-created offline entries appear immediately without flicker.
    if (!isOnline || pendingCount > 0) {
      return LocalExpenseRepository().getExpenses(user.uid, month: month);
    }
  }
  return ref
      .read(expenseRepositoryProvider)
      .getExpenses(user.uid, month: month);
});

/// All expenses across all months — used for lifetime savings totals.
final allExpensesProvider = StreamProvider.autoDispose<List<Expense>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  if (storageMode == StorageMode.firebase) {
    final isOnline = ref.watch(isOnlineProvider);
    final pendingCount = ref.watch(pendingExpenseChangeCountProvider);
    if (!isOnline || pendingCount > 0) {
      return LocalExpenseRepository().getAllExpenses(user.uid);
    }
  }
  return ref.read(expenseRepositoryProvider).getAllExpenses(user.uid);
});

/// Pre-app savings the user manually entered (opening balance).
final openingSavingsProvider = StreamProvider.autoDispose<double>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(0.0);
  if (storageMode == StorageMode.firebase) {
    final isOnline = ref.watch(isOnlineProvider);
    if (!isOnline) {
      return LocalExpenseRepository().getOpeningSavings(user.uid);
    }
  }
  return ref.read(expenseRepositoryProvider).getOpeningSavings(user.uid);
});

/// Current savings = opening balance + (lifetime inflows − lifetime outflows).
/// Uses baseCurrencyAmount for multi-currency entries; falls back to amount.
final savingsProvider = Provider.autoDispose<double>((ref) {
  final all = ref.watch(allExpensesProvider).valueOrNull ?? const [];
  final opening = ref.watch(openingSavingsProvider).valueOrNull ?? 0.0;
  double inflow = 0;
  double outflow = 0;
  for (final e in all) {
    final amt = e.convertedAmount;
    if (e.type.isInflow) {
      inflow += amt;
    } else {
      outflow += amt;
    }
  }
  return opening + inflow - outflow;
});

/// Returns the amount to apply to an account's balance for a given expense.
/// If the expense currency matches the account currency, use the raw amount.
/// If they differ, use convertedAmount (base-currency equivalent) so RM
/// accounts aren't credited/debited at the wrong exchange rate.
double _effectiveAmount(Expense expense, String? accountCurrencyCode) {
  if (expense.originalCurrency == accountCurrencyCode) return expense.amount;
  return expense.convertedAmount;
}

/// Per-account raw balance map (in each account's own currency).
Map<String, double> computeAccountBalanceMap(
  List<Account> accounts,
  List<Expense> all,
) {
  final currencyCodes = <String, String?>{
    for (final a in accounts) a.id: a.currencyCode,
  };
  final balances = <String, double>{};
  for (final a in accounts) {
    balances[a.id] = a.openingBalance;
  }
  for (final e in all) {
    final aid = e.accountId;
    if (aid != null && balances.containsKey(aid)) {
      final amt = _effectiveAmount(e, currencyCodes[aid]);
      if (e.type.isInflow) {
        balances[aid] = (balances[aid] ?? 0) + amt;
      } else {
        balances[aid] = (balances[aid] ?? 0) - amt;
      }
    }
    final toId = e.toAccountId;
    if (toId != null && balances.containsKey(toId)) {
      balances[toId] =
          (balances[toId] ?? 0) + _effectiveAmount(e, currencyCodes[toId]);
    }
  }
  return balances;
}

/// Total balance = sum of all account balances converted to user's main currency.
/// Uses frozen baseCurrencyAmount on expenses where available; falls back to
/// live converter for account opening-balance differences.
final totalAccountBalanceProvider = Provider.autoDispose<double>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
  final all = ref.watch(allExpensesProvider).valueOrNull ?? const [];
  if (accounts.isEmpty) return ref.watch(savingsProvider);

  final converter = ref.watch(currencyConverterProvider).valueOrNull;
  final mainCode = converter?.base;
  final balances = computeAccountBalanceMap(accounts, all);

  double total = 0;
  for (final a in accounts) {
    final bal = balances[a.id] ?? 0;
    final acctCurrency = a.currencyCode ?? mainCode;
    if (converter != null && acctCurrency != null && acctCurrency != mainCode) {
      total += converter.toBase(bal, acctCurrency);
    } else {
      total += bal;
    }
  }
  return total;
});

final installmentsProvider = StreamProvider.autoDispose<List<Installment>>((
  ref,
) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value([]);
  return ref.read(installmentServiceProvider).getAll(user.uid);
});

final budgetProvider = StreamProvider.autoDispose<double>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(0.0);
  if (storageMode == StorageMode.firebase) {
    final isOnline = ref.watch(isOnlineProvider);
    if (!isOnline) {
      return LocalExpenseRepository().getMonthlyBudget(user.uid);
    }
  }
  return ref.read(expenseRepositoryProvider).getMonthlyBudget(user.uid);
});

final currencySymbolProvider = FutureProvider<String>(
  (ref) => ref.read(prefsServiceProvider).currencySymbol(),
);

final currencyCodeProvider = FutureProvider<String>(
  (ref) => ref.read(prefsServiceProvider).currencyCode(),
);

final exchangeRateServiceProvider = Provider((_) => ExchangeRateService());

/// FX preferences (starred / hidden currencies) — synced to Firestore.
final fxPreferencesProvider = StreamProvider<FxPreferences>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const FxPreferences());
  return FxPreferencesService(FirebaseFirestore.instance, user.uid).stream();
});

/// Live FX rates keyed by currency code (relative to user's main currency).
final ratesProvider = FutureProvider.autoDispose<Map<String, double>>((
  ref,
) async {
  final base = await ref.watch(currencyCodeProvider.future);
  return ref.read(exchangeRateServiceProvider).getRates(base);
});

/// Synchronous converter backed by currently loaded rates.
final currencyConverterProvider = FutureProvider.autoDispose<CurrencyConverter>(
  (ref) async {
    final base = await ref.watch(currencyCodeProvider.future);
    final rates = await ref.watch(ratesProvider.future);
    return CurrencyConverter(base, rates);
  },
);

/// Persisted theme-mode selection (system / light / dark). Reads on app
/// start and writes whenever the user changes the picker in Settings.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._prefs) : super(ThemeMode.system) {
    _load();
  }

  final PrefsService _prefs;

  Future<void> _load() async {
    state = await _prefs.themeMode();
  }

  Future<void> set(ThemeMode mode) async {
    state = mode;
    await _prefs.setThemeMode(mode);
  }
}

final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>(
  (ref) => ThemeModeNotifier(ref.read(prefsServiceProvider)),
);

/// Persisted app-language selection. `system` (default) uses whatever
/// locale the device reports.
class LocaleNotifier extends StateNotifier<AppLocale> {
  LocaleNotifier(this._prefs) : super(AppLocale.system) {
    _load();
  }
  final PrefsService _prefs;

  Future<void> _load() async {
    state = await _prefs.appLocale();
  }

  Future<void> set(AppLocale locale) async {
    state = locale;
    await _prefs.setAppLocale(locale);
  }
}

final localeProvider = StateNotifierProvider<LocaleNotifier, AppLocale>(
  (ref) => LocaleNotifier(ref.read(prefsServiceProvider)),
);

/// Bank-style hide/show for the headline balance. `true` = readable,
/// `false` = masked as `RM ****`. Persisted via `PrefsService` so the
/// choice survives restart. Calculations are unaffected.
class BalanceVisibilityNotifier extends StateNotifier<bool> {
  BalanceVisibilityNotifier(this._prefs) : super(true) {
    _load();
  }
  final PrefsService _prefs;

  Future<void> _load() async {
    state = await _prefs.balanceVisible();
  }

  Future<void> set(bool value) async {
    state = value;
    await _prefs.setBalanceVisible(value);
  }

  Future<void> toggle() => set(!state);
}

final balanceVisibleProvider =
    StateNotifierProvider<BalanceVisibilityNotifier, bool>(
      (ref) => BalanceVisibilityNotifier(ref.read(prefsServiceProvider)),
    );

/// When true, installments are excluded from the liabilities total in the
/// net worth card. Setting is persisted to Firestore users/{uid}/settings/general.
class ExcludeInstallmentsNotifier extends StateNotifier<bool> {
  ExcludeInstallmentsNotifier(this._db, this._userId) : super(false) {
    if (_userId != null) _load();
  }

  final FirebaseFirestore? _db;
  final String? _userId;

  DocumentReference<Map<String, dynamic>>? get _doc => _userId == null
      ? null
      : _db!
            .collection('users')
            .doc(_userId)
            .collection('settings')
            .doc('general');

  Future<void> _load() async {
    try {
      final snap = await _doc!.get();
      if (snap.exists && mounted) {
        state = (snap.data()?['excludeInstallments'] as bool?) ?? false;
      }
    } catch (_) {}
  }

  Future<void> set(bool value) async {
    state = value;
    try {
      await _doc?.set({'excludeInstallments': value}, SetOptions(merge: true));
    } catch (_) {}
  }
}

final excludeInstallmentsProvider =
    StateNotifierProvider.autoDispose<ExcludeInstallmentsNotifier, bool>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  return ExcludeInstallmentsNotifier(
    user != null ? FirebaseFirestore.instance : null,
    user?.uid,
  );
});

class VisibilitySetNotifier extends StateNotifier<Set<String>> {
  VisibilitySetNotifier({
    required PrefsService prefs,
    required Set<String> initial,
    required Future<Set<String>> Function(PrefsService prefs) load,
    required Future<void> Function(PrefsService prefs, Set<String> ids) save,
  }) : _prefs = prefs,
       _save = save,
       super(initial) {
    _load(load);
  }

  final PrefsService _prefs;
  final Future<void> Function(PrefsService prefs, Set<String> ids) _save;

  Future<void> _load(
    Future<Set<String>> Function(PrefsService prefs) load,
  ) async {
    state = await load(_prefs);
  }

  Future<void> setVisible(String id, bool visible) async {
    final next = {...state};
    if (visible) {
      next.add(id);
    } else if (next.length > 1) {
      next.remove(id);
    }
    state = next;
    await _save(_prefs, next);
  }
}

class HomeCardOrderNotifier extends StateNotifier<List<String>> {
  final PrefsService _prefs;

  HomeCardOrderNotifier(this._prefs) : super(PrefsService.defaultHomeCards) {
    _load();
  }

  Future<void> _load() async {
    state = await _prefs.homeCardOrder();
  }

  Future<void> setOrder(List<String> order) async {
    state = order;
    await _prefs.setHomeCardOrder(order);
  }
}

final homeCardOrderProvider =
    StateNotifierProvider<HomeCardOrderNotifier, List<String>>(
      (ref) => HomeCardOrderNotifier(ref.read(prefsServiceProvider)),
    );

class MoneyHubOrderNotifier extends StateNotifier<List<String>> {
  final PrefsService _prefs;

  MoneyHubOrderNotifier(this._prefs) : super(PrefsService.defaultMoneyHubOrder) {
    _load();
  }

  Future<void> _load() async {
    state = await _prefs.moneyHubOrder();
  }

  Future<void> setOrder(List<String> order) async {
    state = order;
    await _prefs.setMoneyHubOrder(order);
  }
}

final moneyHubOrderProvider =
    StateNotifierProvider<MoneyHubOrderNotifier, List<String>>(
      (ref) => MoneyHubOrderNotifier(ref.read(prefsServiceProvider)),
    );

final homeCardVisibilityProvider =
    StateNotifierProvider<VisibilitySetNotifier, Set<String>>(
      (ref) => VisibilitySetNotifier(
        prefs: ref.read(prefsServiceProvider),
        initial: PrefsService.defaultHomeCards.toSet(),
        load: (prefs) => prefs.visibleHomeCards(),
        save: (prefs, ids) => prefs.setVisibleHomeCards(ids),
      ),
    );

final moneyHubVisibilityProvider =
    StateNotifierProvider<VisibilitySetNotifier, Set<String>>(
      (ref) => VisibilitySetNotifier(
        prefs: ref.read(prefsServiceProvider),
        initial: PrefsService.defaultMoneyHubModules.toSet(),
        load: (prefs) => prefs.visibleMoneyHubModules(),
        save: (prefs, ids) => prefs.setVisibleMoneyHubModules(ids),
      ),
    );

final statsSectionsVisibilityProvider =
    StateNotifierProvider<VisibilitySetNotifier, Set<String>>(
      (ref) => VisibilitySetNotifier(
        prefs: ref.read(prefsServiceProvider),
        initial: PrefsService.defaultStatsSections.toSet(),
        load: (prefs) => prefs.visibleStatsSections(),
        save: (prefs, ids) => prefs.setVisibleStatsSections(ids),
      ),
    );

/// Live count of locally-saved offline entries awaiting cloud sync.
final pendingSyncCountProvider = StreamProvider.autoDispose<int>((ref) {
  if (storageMode != StorageMode.firebase) return Stream.value(0);
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(0);
  return SyncService().pendingCountStream(user.uid);
});

final pendingDeleteCountProvider = StreamProvider.autoDispose<int>((ref) {
  if (storageMode != StorageMode.firebase) return Stream.value(0);
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(0);
  return SyncService().pendingDeleteCountStream(user.uid);
});

final pendingExpenseChangeCountProvider = Provider.autoDispose<int>((ref) {
  final pendingWrites = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
  final pendingDeletes = ref.watch(pendingDeleteCountProvider).valueOrNull ?? 0;
  return pendingWrites + pendingDeletes;
});

final preciousMetalRepositoryProvider = Provider<PreciousMetalRepository>((_) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalPreciousMetalRepository();
    case StorageMode.firebase:
      return FirebasePreciousMetalRepository();
  }
});

/// Stream of all precious metal transactions for the active user.
final preciousMetalsProvider = StreamProvider.autoDispose<List<PreciousMetal>>((
  ref,
) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.read(preciousMetalRepositoryProvider).getAll(user.uid);
});

/// Watches for offline→online transitions and automatically uploads pending
/// entries. Must be watched by a long-lived widget (TrackoraApp) to stay active.
final autoSyncProvider = Provider<void>((ref) {
  if (storageMode != StorageMode.firebase) return;
  ref.listen<AsyncValue<bool>>(networkStatusProvider, (prev, next) {
    final wasOffline = prev?.valueOrNull == false;
    final isNowOnline = next.valueOrNull == true;
    if (!wasOffline || !isNowOnline) return;
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return;
    SyncService().syncPendingIfAuthenticated(
      localUserId: user.uid,
      onState: (_) {},
    );
  });
});

// ── Travel Groups ─────────────────────────────────────────────────────────────

final travelGroupRepositoryProvider = Provider<TravelGroupRepository>((_) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalTravelGroupRepository();
    case StorageMode.firebase:
      return FirebaseTravelGroupRepository();
  }
});

final travelGroupServiceProvider = Provider<TravelGroupService>((ref) {
  return TravelGroupService(ref.read(travelGroupRepositoryProvider));
});

final travelGroupsProvider = StreamProvider.autoDispose<List<TravelGroup>>((
  ref,
) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  return ref.read(travelGroupRepositoryProvider).getGroups(user.uid);
});

final travelGroupMembersProvider = StreamProvider.autoDispose
    .family<List<TravelGroupMember>, String>((ref, groupId) {
      return ref.read(travelGroupRepositoryProvider).getMembers(groupId);
    });

final travelGroupExpensesProvider = StreamProvider.autoDispose
    .family<List<TravelExpense>, String>((ref, groupId) {
      return ref.read(travelGroupRepositoryProvider).getExpenses(groupId);
    });

// ── Custom Expense Cycle ──────────────────────────────────────────────────────

class UseCustomCycleNotifier extends StateNotifier<bool> {
  UseCustomCycleNotifier(this._prefs) : super(false) {
    _load();
  }
  final PrefsService _prefs;
  Future<void> _load() async { state = await _prefs.useCustomCycle(); }
  Future<void> set(bool value) async {
    state = value;
    await _prefs.setUseCustomCycle(value);
  }
}

final useCustomCycleProvider = StateNotifierProvider<UseCustomCycleNotifier, bool>(
  (ref) => UseCustomCycleNotifier(ref.read(prefsServiceProvider)),
);

class CycleDayStartNotifier extends StateNotifier<int> {
  CycleDayStartNotifier(this._prefs) : super(1) {
    _load();
  }
  final PrefsService _prefs;
  Future<void> _load() async { state = await _prefs.cycleDayStart(); }
  Future<void> set(int day) async {
    state = day.clamp(1, 28);
    await _prefs.setCycleDayStart(day);
  }
}

final cycleDayStartProvider = StateNotifierProvider<CycleDayStartNotifier, int>(
  (ref) => CycleDayStartNotifier(ref.read(prefsServiceProvider)),
);

/// Date range for the current custom expense cycle.
/// Returns null when custom cycle is disabled (calendar month is used).
class CycleDateRange {
  final DateTime start;
  final DateTime endExclusive;
  const CycleDateRange({required this.start, required this.endExclusive});
}

final cycleDateRangeProvider = Provider.autoDispose<CycleDateRange?>((ref) {
  final useCustom = ref.watch(useCustomCycleProvider);
  if (!useCustom) return null;
  final startDay = ref.watch(cycleDayStartProvider).clamp(1, 28);
  final now = DateTime.now();
  final DateTime cycleStart;
  if (now.day >= startDay) {
    cycleStart = DateTime(now.year, now.month, startDay);
  } else {
    cycleStart = DateTime(now.year, now.month - 1, startDay);
  }
  final cycleEnd = DateTime(cycleStart.year, cycleStart.month + 1, startDay);
  return CycleDateRange(start: cycleStart, endExclusive: cycleEnd);
});

// ── Stock Investments ─────────────────────────────────────────────────────────

final stockInvestmentRepositoryProvider = Provider<StockInvestmentRepository>((
  _,
) {
  return FirebaseStockInvestmentRepository();
});

final stockServiceProvider = Provider((_) => StockService());

/// Stream of all stock investments for the active user.
final stockInvestmentsProvider =
    StreamProvider.autoDispose<List<StockInvestment>>((ref) {
      final user = ref.watch(authStateProvider).valueOrNull;
      if (user == null) return Stream.value(const []);
      return ref.read(stockInvestmentRepositoryProvider).getAll(user.uid);
    });
