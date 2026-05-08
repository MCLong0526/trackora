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
import '../models/saving_plan.dart';
import '../repositories/account_repository.dart';
import '../repositories/borrow_lending_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/firebase_borrow_lending_repository.dart';
import '../repositories/firebase_expense_repository.dart';
import '../repositories/firebase_installment_repository.dart';
import '../repositories/firebase_person_repository.dart';
import '../repositories/firebase_saving_plan_repository.dart';
import '../repositories/installment_repository.dart';
import '../repositories/local_account_repository.dart';
import '../repositories/local_borrow_lending_repository.dart';
import '../repositories/local_expense_repository.dart';
import '../repositories/local_installment_repository.dart';
import '../repositories/local_person_repository.dart';
import '../repositories/local_saving_plan_repository.dart';
import '../repositories/person_repository.dart';
import '../repositories/saving_plan_repository.dart';
import '../services/auth_service.dart';
import '../services/borrow_lending_service.dart';
import '../services/expense_service.dart';
import '../services/i18n.dart';
import '../services/installment_service.dart';
import '../services/person_service.dart';
import '../services/prefs_service.dart';
import '../services/saving_plan_service.dart';
import '../services/storage_service.dart';
import '../services/sync_service.dart';
import '../services/watch_service.dart';
import '../services/widget_sync_service.dart';

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
  return ref.watch(networkStatusProvider).maybeWhen(
    data: (online) => online,
    orElse: () => true, // assume online until we know otherwise
  );
});

final authServiceProvider = Provider((_) => AuthService());

final accountRepositoryProvider = Provider<AccountRepository>(
  (_) => LocalAccountRepository(),
);

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
    expenses: ref.read(expenseRepositoryProvider),
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
    final pendingCount =
        ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
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
    final pendingCount =
        ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;
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
/// Inflows: income + receive. Outflows: expense + transfer.
final savingsProvider = Provider.autoDispose<double>((ref) {
  final all = ref.watch(allExpensesProvider).valueOrNull ?? const [];
  final opening = ref.watch(openingSavingsProvider).valueOrNull ?? 0.0;
  double inflow = 0;
  double outflow = 0;
  for (final e in all) {
    if (e.type.isInflow) {
      inflow += e.amount;
    } else {
      outflow += e.amount;
    }
  }
  return opening + inflow - outflow;
});

/// Total balance = sum of all account opening balances adjusted by transactions.
/// Account-to-account transfers credit the destination account without
/// double-counting as income/expense.
final totalAccountBalanceProvider = Provider.autoDispose<double>((ref) {
  final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
  final all = ref.watch(allExpensesProvider).valueOrNull ?? const [];
  if (accounts.isEmpty) return ref.watch(savingsProvider);

  final balances = <String, double>{};
  for (final a in accounts) {
    balances[a.id] = a.openingBalance;
  }
  for (final e in all) {
    final aid = e.accountId;
    if (aid != null && balances.containsKey(aid)) {
      if (e.type.isInflow) {
        balances[aid] = (balances[aid] ?? 0) + e.amount;
      } else {
        balances[aid] = (balances[aid] ?? 0) - e.amount;
      }
    }
    final toId = e.toAccountId;
    if (toId != null && balances.containsKey(toId)) {
      balances[toId] = (balances[toId] ?? 0) + e.amount;
    }
  }
  return balances.values.fold<double>(0, (s, v) => s + v);
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
  BalanceVisibilityNotifier(this._prefs) : super(false) {
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

