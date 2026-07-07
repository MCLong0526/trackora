import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../app_config.dart';
import '../models/account.dart';
import '../models/monthly_budget.dart';
import '../models/borrow_lending.dart';
import '../models/custom_category.dart';
import '../models/expense.dart';
import '../models/installment.dart';
import '../models/app_user.dart';
import '../models/person.dart';
import '../models/split_bill.dart';
import '../models/precious_metal.dart';
import '../models/saving_plan.dart';
import '../repositories/account_repository.dart';
import '../repositories/borrow_lending_repository.dart';
import '../repositories/custom_category_repository.dart';
import '../repositories/expense_repository.dart';
import '../repositories/firebase_account_repository.dart';
import '../repositories/firebase_custom_category_repository.dart';
import '../repositories/firebase_borrow_lending_repository.dart';
import '../repositories/firebase_expense_repository.dart';
import '../repositories/firebase_installment_repository.dart';
import '../repositories/firebase_person_repository.dart';
import '../repositories/firebase_precious_metal_repository.dart';
import '../repositories/firebase_saving_plan_repository.dart';
import '../repositories/installment_repository.dart';
import '../repositories/local_account_repository.dart';
import '../repositories/local_storage.dart';
import '../repositories/local_borrow_lending_repository.dart';
import '../repositories/local_custom_category_repository.dart';
import '../repositories/local_expense_repository.dart';
import '../repositories/local_installment_repository.dart';
import '../repositories/local_person_repository.dart';
import '../repositories/local_precious_metal_repository.dart';
import '../repositories/local_saving_plan_repository.dart';
import '../repositories/local_split_bill_repository.dart';
import '../repositories/person_repository.dart';
import '../repositories/precious_metal_repository.dart';
import '../repositories/split_bill_repository.dart';
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
import '../theme/app_theme.dart';
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
import '../repositories/local_stock_investment_repository.dart';
import '../services/stock_service.dart';
import '../models/expense_group.dart';
import '../models/group_expense_item.dart';
import '../repositories/expense_group_repository.dart';
import '../repositories/firebase_expense_group_repository.dart';
import '../repositories/local_expense_group_repository.dart';
import '../services/expense_group_service.dart';

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

final accountRepositoryProvider = Provider<AccountRepository>((ref) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalAccountRepository();
    case StorageMode.firebase:
      final isOnline = ref.watch(isOnlineProvider);
      return isOnline ? FirebaseAccountRepository() : LocalAccountRepository();
  }
});

const _kAccountTypeOrder = {
  AccountType.bank: 0,
  AccountType.eWallet: 1,
  AccountType.cash: 2,
  AccountType.investment: 3,
  AccountType.savings: 4,
  AccountType.crypto: 5,
  AccountType.forex: 6,
  AccountType.creditCard: 7,
  AccountType.loan: 8,
  AccountType.mortgage: 9,
  AccountType.bnpl: 10,
  AccountType.otherLiability: 11,
};

int _compareAccounts(Account a, Account b) {
  final ta = _kAccountTypeOrder[a.type] ?? 99;
  final tb = _kAccountTypeOrder[b.type] ?? 99;
  if (ta != tb) return ta.compareTo(tb);
  return a.createdAt.compareTo(b.createdAt);
}

/// Stream of all accounts for the active user, sorted by type then createdAt.
final accountsProvider = StreamProvider.autoDispose<List<Account>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  final repo = ref.watch(accountRepositoryProvider);
  final stream = repo.getAll(user.uid).map((list) {
    final sorted = list.toList()..sort(_compareAccounts);
    return sorted;
  });
  // Mirror Firebase data to local Hive so accounts remain visible offline.
  if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
    return stream.asyncMap((items) async {
      final local = LocalAccountRepository();
      final pendingDeleteIds = SyncService.getEntityPendingDeleteIds(
        user.uid,
        'account',
      ).toSet();
      // Update local with current Firebase data (skip pending-deleted accounts).
      // Do NOT delete local-only entries here — they may be offline-created
      // accounts that haven't synced to Firebase yet.
      for (final a in items) {
        if (a.id.isNotEmpty && !pendingDeleteIds.contains(a.id)) {
          await local.update(user.uid, a);
        }
      }
      return pendingDeleteIds.isEmpty
          ? items
          : items.where((a) => !pendingDeleteIds.contains(a.id)).toList();
    });
  }
  return stream;
});
final expenseRepositoryProvider = Provider<ExpenseRepository>((ref) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalExpenseRepository();
    case StorageMode.firebase:
      final isOnline = ref.watch(isOnlineProvider);
      return isOnline ? FirebaseExpenseRepository() : LocalExpenseRepository();
  }
});
final installmentRepositoryProvider = Provider<InstallmentRepository>((ref) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalInstallmentRepository();
    case StorageMode.firebase:
      final isOnline = ref.watch(isOnlineProvider);
      return isOnline
          ? FirebaseInstallmentRepository()
          : LocalInstallmentRepository();
  }
});
final expenseServiceProvider = Provider(
  (ref) => ExpenseService(ref.watch(expenseRepositoryProvider)),
);
final installmentServiceProvider = Provider(
  (ref) =>
      InstallmentService(repository: ref.watch(installmentRepositoryProvider)),
);

final borrowLendingRepositoryProvider = Provider<BorrowLendingRepository>((
  ref,
) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalBorrowLendingRepository();
    case StorageMode.firebase:
      final isOnline = ref.watch(isOnlineProvider);
      return isOnline
          ? FirebaseBorrowLendingRepository()
          : LocalBorrowLendingRepository();
  }
});
final borrowLendingServiceProvider = Provider(
  (ref) => BorrowLendingService(ref.watch(borrowLendingRepositoryProvider)),
);

final savingPlanRepositoryProvider = Provider<SavingPlanRepository>((ref) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalSavingPlanRepository();
    case StorageMode.firebase:
      final isOnline = ref.watch(isOnlineProvider);
      return isOnline
          ? FirebaseSavingPlanRepository()
          : LocalSavingPlanRepository();
  }
});
final savingPlanServiceProvider = Provider(
  (ref) => SavingPlanService(ref.watch(savingPlanRepositoryProvider)),
);

final personRepositoryProvider = Provider<PersonRepository>((ref) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalPersonRepository();
    case StorageMode.firebase:
      final isOnline = ref.watch(isOnlineProvider);
      return isOnline ? FirebasePersonRepository() : LocalPersonRepository();
  }
});

final personServiceProvider = Provider(
  (ref) => PersonService(ref.watch(personRepositoryProvider)),
);

final peopleProvider = StreamProvider.autoDispose<List<Person>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  final stream = ref.watch(personServiceProvider).getAll(user.uid);
  if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
    return stream.asyncMap((items) async {
      final local = LocalPersonRepository();
      final deletedIds = SyncService.getEntityPendingDeleteIds(
        user.uid,
        'person',
      ).toSet();
      for (final p in items) {
        if (p.id.isNotEmpty && !deletedIds.contains(p.id)) {
          await local.update(user.uid, p);
        }
      }
      return deletedIds.isEmpty
          ? items
          : items.where((p) => !deletedIds.contains(p.id)).toList();
    });
  }
  return stream;
});

// ── Custom categories ─────────────────────────────────────────────────────
final customCategoryRepositoryProvider = Provider<CustomCategoryRepository>((
  ref,
) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalCustomCategoryRepository();
    case StorageMode.firebase:
      final isOnline = ref.watch(isOnlineProvider);
      return isOnline
          ? FirebaseCustomCategoryRepository()
          : LocalCustomCategoryRepository();
  }
});

/// Stream of all user-defined categories. Offline-aware: mirrors Firebase data
/// into Hive so categories stay available offline.
final customCategoriesProvider =
    StreamProvider.autoDispose<List<CustomCategory>>((ref) {
      final user = ref.watch(authStateProvider).valueOrNull;
      if (user == null) return Stream.value(const []);
      final stream = ref
          .watch(customCategoryRepositoryProvider)
          .getAll(user.uid);
      if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
        return stream.asyncMap((items) async {
          final local = LocalCustomCategoryRepository();
          final deletedIds = SyncService.getEntityPendingDeleteIds(
            user.uid,
            'category',
          ).toSet();
          for (final c in items) {
            if (c.id.isNotEmpty && !deletedIds.contains(c.id)) {
              await local.update(user.uid, c);
            }
          }
          return deletedIds.isEmpty
              ? items
              : items.where((c) => !deletedIds.contains(c.id)).toList();
        });
      }
      return stream;
    });

/// Keeps the global [styleFor] registry in sync with the user's custom
/// categories so their icon/colour resolve everywhere. Watch this once high in
/// the widget tree (see TrackoraApp).
final customCategoryStyleRegistryProvider = Provider<void>((ref) {
  final cats = ref.watch(customCategoriesProvider).valueOrNull ?? const [];
  setCustomCategoryStyles({
    for (final c in cats)
      c.name: customCategoryStyle(iconKey: c.iconKey, colorIndex: c.colorIndex),
  });
});

/// Custom category names for the given flow (income vs expense).
List<String> customCategoryNames(
  List<CustomCategory> cats, {
  required bool income,
}) => cats.where((c) => c.isIncome == income).map((c) => c.name).toList();

// ── Split bills (for the Contacts "owes you" view) ────────────────────────
/// All split bills for the active user — local-first, merged with Firestore
/// when online. One bill per expense, keeping whichever copy was updated most
/// recently so a just-saved local edit isn't masked by a not-yet-propagated
/// remote copy (the cause of "owes you" amounts only updating after a restart).
final allSplitBillsProvider = FutureProvider.autoDispose<List<SplitBill>>((
  ref,
) async {
  // Re-fetch whenever the local split-bills box changes (a bill saved while
  // adding an expense), so the People page shows new "owes you" amounts
  // immediately instead of only after an app restart.
  ref.watch(splitBillsBoxTickProvider);
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return const [];
  final local = await LocalSplitBillRepository().getAllSplitBills(user.uid);
  if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
    try {
      final remote = await SplitBillRepository()
          .watchSplitBills(user.uid)
          .first;
      // Merge remote first, then local, keeping the most recently updated copy
      // per expense. Local edits carry a fresh updatedAt, so they win over the
      // stale remote value while Firestore is still catching up.
      final byExpense = <String, SplitBill>{};
      for (final b in [...remote, ...local]) {
        final existing = byExpense[b.expenseId];
        if (existing == null || !b.updatedAt.isBefore(existing.updatedAt)) {
          byExpense[b.expenseId] = b;
        }
      }
      return byExpense.values.toList();
    } catch (_) {}
  }
  return local;
});

/// What a person still owes across all split bills.
class PersonOwedSummary {
  /// Total outstanding (in base currency when [toBase] is supplied, else raw).
  final double total;

  /// Bills where this person is still an unpaid debtor.
  final List<({SplitBill bill, SplitMember member})> pending;

  const PersonOwedSummary(this.total, this.pending);
}

PersonOwedSummary personOwedSummary(
  List<SplitBill> bills,
  Person person, {
  double Function(double amount, String fromCode)? toBase,
}) {
  double total = 0;
  final pending = <({SplitBill bill, SplitMember member})>[];
  final lowerName = person.name.trim().toLowerCase();
  for (final b in bills) {
    for (final m in b.members) {
      if (m.isPayer || m.status == SplitMemberStatus.paid) continue;
      final matches =
          (m.personId != null && m.personId == person.id) ||
          (m.personId == null && m.name.trim().toLowerCase() == lowerName);
      if (!matches) continue;
      pending.add((bill: b, member: m));
      total += toBase != null ? toBase(m.amount, b.currency) : m.amount;
    }
  }
  return PersonOwedSummary(total, pending);
}

/// Ticks whenever the local split-bills Hive box changes (a bill saved,
/// updated or deleted). Widgets that read split state synchronously — e.g. the
/// activity-list split badge — watch this so they rebuild the instant a bill is
/// written, without waiting for a provider invalidation or a page change.
final splitBillsBoxTickProvider = StreamProvider.autoDispose<int>((ref) {
  if (!Hive.isBoxOpen(LocalStorage.splitBillsBoxName)) {
    return const Stream<int>.empty();
  }
  return LocalStorage.splitBills.watch().map((_) => 0);
});

/// True when at least one person still owes the user across any split bill.
/// Drives the "owed" badge on the People tile in the Manage hub.
final someoneOwesYouProvider = Provider.autoDispose<bool>((ref) {
  final bills = ref.watch(allSplitBillsProvider).valueOrNull ?? const [];
  for (final b in bills) {
    for (final m in b.members) {
      if (!m.isPayer && m.status != SplitMemberStatus.paid) return true;
    }
  }
  return false;
});

/// Stream of all borrow / lending records for the active user.
final borrowLendingProvider = StreamProvider.autoDispose<List<BorrowLending>>((
  ref,
) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  final stream = ref.watch(borrowLendingServiceProvider).getAll(user.uid);
  if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
    return stream.asyncMap((items) async {
      final local = LocalBorrowLendingRepository();
      final deletedIds = SyncService.getEntityPendingDeleteIds(
        user.uid,
        'bl',
      ).toSet();
      for (final r in items) {
        if (r.id.isNotEmpty && !deletedIds.contains(r.id)) {
          await local.update(user.uid, r);
        }
      }
      return deletedIds.isEmpty
          ? items
          : items.where((r) => !deletedIds.contains(r.id)).toList();
    });
  }
  return stream;
});

/// Stream of all saving plans for the active user.
final savingPlansProvider = StreamProvider.autoDispose<List<SavingPlan>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  final stream = ref.watch(savingPlanServiceProvider).getAll(user.uid);
  if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
    return stream.asyncMap((items) async {
      final local = LocalSavingPlanRepository();
      final deletedIds = SyncService.getEntityPendingDeleteIds(
        user.uid,
        'plan',
      ).toSet();
      for (final p in items) {
        if (p.id.isNotEmpty && !deletedIds.contains(p.id)) {
          await local.update(user.uid, p);
        }
      }
      return deletedIds.isEmpty
          ? items
          : items.where((p) => !deletedIds.contains(p.id)).toList();
    });
  }
  return stream;
});
final storageServiceProvider = Provider((_) => StorageService());
final prefsServiceProvider = Provider((_) => PrefsService());
final widgetSyncServiceProvider = Provider((_) => WidgetSyncService());
final watchServiceProvider = Provider((_) => WatchService());

// ── Display name ─────────────────────────────────────────────────────────────

class UserNameNotifier extends StateNotifier<String> {
  UserNameNotifier(this._prefs, this._ref) : super('') {
    // Reload name whenever the authenticated user changes so names don't
    // bleed between accounts when one user logs out and another logs in.
    _ref.listen<AsyncValue<AppUser?>>(authStateProvider, (previous, next) {
      final prevUid = previous?.valueOrNull?.uid;
      final nextUid = next.valueOrNull?.uid;
      if (prevUid != nextUid) {
        if (nextUid == null) {
          state = ''; // signed out — clear immediately
        } else {
          state = ''; // clear stale name before loading new user's name
          _load(nextUid);
        }
      }
    });
    // Initial load for the current user (if already signed in at startup).
    final uid = _ref.read(authStateProvider).valueOrNull?.uid;
    if (uid != null) _load(uid);
  }

  final PrefsService _prefs;
  final Ref _ref;

  Future<void> _load(String uid) async {
    // Try user-specific local cache first for instant display.
    final local = await _prefs.userNameForUid(uid);
    if (local.isNotEmpty && mounted) state = local;
    // Always sync from Firestore as the source of truth.
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .get();
      final remote = doc.data()?['displayName'] as String?;
      if (remote != null && remote.trim().isNotEmpty && mounted) {
        state = remote.trim();
        await _prefs.setUserNameForUid(uid, remote.trim());
        return;
      }
    } catch (_) {}
    // Fallback for accounts created before the name was persisted to Firestore:
    // recover it from the Firebase Auth profile (set at signup via
    // updateDisplayName) and backfill Firestore so it becomes the source of
    // truth going forward.
    if (state.isEmpty) {
      final authUser = FirebaseAuth.instance.currentUser;
      final authName = authUser?.displayName?.trim() ?? '';
      if (authUser?.uid == uid && authName.isNotEmpty) {
        if (mounted) state = authName;
        await _prefs.setUserNameForUid(uid, authName);
        try {
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'displayName': authName,
          }, SetOptions(merge: true));
        } catch (_) {}
      }
    }
  }

  Future<void> set(String name) async {
    state = name.trim();
    // Prefer the gated app user, but fall back to the raw Firebase user: at
    // signup the email isn't verified yet, so authStateProvider is still null —
    // without this fallback the name set during signup is never persisted.
    final uid =
        _ref.read(authStateProvider).valueOrNull?.uid ??
        FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      await _prefs.setUserNameForUid(uid, name.trim());
      try {
        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'displayName': name.trim(),
        }, SetOptions(merge: true));
      } catch (_) {}
    }
  }
}

final userNameProvider = StateNotifierProvider<UserNameNotifier, String>(
  (ref) => UserNameNotifier(ref.read(prefsServiceProvider), ref),
);

/// Live display name for any user UID, read from `users/{uid}/displayName`.
/// Falls back to an empty string if the document doesn't exist or has no name.
final memberDisplayNameProvider = StreamProvider.family
    .autoDispose<String, String>((ref, uid) {
      return FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .snapshots()
          .map(
            (snap) => (snap.data()?['displayName'] as String?)?.trim() ?? '',
          );
    });

final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.read(authServiceProvider).authStateChanges,
);

final selectedMonthProvider = StateProvider<DateTime>((_) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, 1);
});

/// Controls which HomeShell tab is shown (0=Home, 1=Stats, 2=Budget, 3=Assets).
final homeTabIndexProvider = StateProvider<int>((_) => 0);

/// When true, BudgetScreen opens the monthly budget popup on its next build.
final openBudgetPopupProvider = StateProvider<bool>((_) => false);

/// When true, StatisticsScreen jumps to the Month tab and scrolls to the
/// Monthly Budget card on its next build, then resets itself to false. Set by
/// the home spending card's budget tap.
final statsFocusBudgetProvider = StateProvider<bool>((_) => false);

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

/// Amount of a stock transaction map (qty × price), in the tx's own currency.
double stockTxnAmount(Map<String, dynamic> tx) {
  final qty = (tx['qty'] as num?)?.toDouble() ?? 0;
  final price = (tx['price'] as num?)?.toDouble() ?? 0;
  return qty * price;
}

/// Per-account raw balance map (in each account's own currency).
///
/// This is the single source of truth for account balances — every screen
/// (Manage, Summary, Profile, Home total) must use it so the numbers tally.
/// It applies, per account:
///  • opening balance,
///  • expenses (income +, expense/transfer −) and transfers in (toAccountId +),
///  • precious-metal buys/sells that have NO linked expense (those that do are
///    already counted via that expense — avoids double-counting),
///  • stock buys/sells paid from the account (stocks never create a linked
///    expense, so they must be applied here).
///
/// [toBase] converts an amount from a given currency code to the user's base
/// currency. It is required for correct stock handling when a stock trade was
/// made in a currency different from the account's (e.g. a USD stock bought
/// from an MYR account) — without it, foreign amounts would be subtracted at
/// their raw face value.
Map<String, double> computeAccountBalanceMap(
  List<Account> accounts,
  List<Expense> all, {
  List<PreciousMetal> metals = const [],
  List<StockInvestment> stocks = const [],
  List<GroupExpenseItem> groupExpenses = const [],
  double Function(double amount, String fromCode)? toBase,
}) {
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
  for (final m in metals) {
    final aid = m.accountId;
    if (aid != null &&
        balances.containsKey(aid) &&
        (m.expenseId == null || m.expenseId!.isEmpty)) {
      balances[aid] =
          (balances[aid] ?? 0) +
          (m.action == MetalAction.sell ? m.totalAmount : -m.totalAmount);
    }
  }
  for (final s in stocks) {
    for (final tx in s.transactions) {
      final aid = tx['accountId'] as String?;
      if (aid == null || !balances.containsKey(aid)) continue;
      final raw = stockTxnAmount(tx);
      final txCur = tx['currency'] as String?;
      final acctCur = currencyCodes[aid];
      // Apply in the account's currency: use the raw amount only when the
      // trade is in the same currency, otherwise convert to base (mirrors how
      // expenses are applied via convertedAmount).
      final amt = (txCur == null || txCur == acctCur || toBase == null)
          ? raw
          : toBase(raw, txCur);
      final isSell = (tx['type'] as String?) == 'sell';
      balances[aid] = (balances[aid] ?? 0) + (isSell ? amt : -amt);
    }
  }
  // Group expenses: deduct from the account used by the payer.
  for (final g in groupExpenses) {
    final aid = g.paidByAccountId;
    if (aid == null || !balances.containsKey(aid)) continue;
    balances[aid] = (balances[aid] ?? 0) - g.amount;
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
  final metals = ref.watch(preciousMetalsProvider).valueOrNull ?? const [];
  final stocks = ref.watch(stockInvestmentsProvider).valueOrNull ?? const [];
  final balances = computeAccountBalanceMap(
    accounts,
    all,
    metals: metals,
    stocks: stocks,
    toBase: converter == null
        ? null
        : (amt, code) => converter.toBase(amt, code),
  );

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
  final stream = ref.watch(installmentServiceProvider).getAll(user.uid);
  if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
    return stream.asyncMap((items) async {
      final local = LocalInstallmentRepository();
      final deletedIds = SyncService.getEntityPendingDeleteIds(
        user.uid,
        'inst',
      ).toSet();
      for (final i in items) {
        if (i.id.isNotEmpty && !deletedIds.contains(i.id)) {
          await local.update(user.uid, i);
        }
      }
      return deletedIds.isEmpty
          ? items
          : items.where((i) => !deletedIds.contains(i.id)).toList();
    });
  }
  return stream;
});

final budgetProvider = StreamProvider.autoDispose<double>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(0.0);
  if (storageMode == StorageMode.firebase) {
    final isOnline = ref.watch(isOnlineProvider);
    if (!isOnline) {
      return LocalExpenseRepository().getMonthlyBudget(user.uid);
    }
    // Mirror Firebase budget to local so it's available offline
    return FirebaseExpenseRepository().getMonthlyBudget(user.uid).asyncMap((
      amount,
    ) async {
      await LocalExpenseRepository().setMonthlyBudget(user.uid, amount);
      return amount;
    });
  }
  return ref.watch(expenseRepositoryProvider).getMonthlyBudget(user.uid);
});

/// Full budget config (total vs by-category) for the active user. Offline-aware,
/// mirroring [budgetProvider]'s Firebase→local fallback.
final budgetConfigProvider = StreamProvider.autoDispose<MonthlyBudget>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const MonthlyBudget());
  if (storageMode == StorageMode.firebase) {
    final isOnline = ref.watch(isOnlineProvider);
    if (!isOnline) {
      return LocalExpenseRepository().getBudgetConfig(user.uid);
    }
    return FirebaseExpenseRepository().getBudgetConfig(user.uid).asyncMap((
      cfg,
    ) async {
      await LocalExpenseRepository().setBudgetConfig(user.uid, cfg);
      return cfg;
    });
  }
  return ref.watch(expenseRepositoryProvider).getBudgetConfig(user.uid);
});

/// Spending per category for the current budget cycle, in base currency, for
/// expense-type entries only. Used by the by-category budget UI.
final categorySpendThisCycleProvider =
    Provider.autoDispose<Map<String, double>>((ref) {
      // Follow the custom expense cycle when set; otherwise the calendar month.
      final cycleRange = ref.watch(cycleDateRangeProvider);
      final List<Expense> expenses;
      if (cycleRange != null) {
        final all = ref.watch(allExpensesProvider).valueOrNull ?? const [];
        expenses = all.where((e) {
          final d = DateTime(e.date.year, e.date.month, e.date.day);
          return !d.isBefore(cycleRange.start) &&
              d.isBefore(cycleRange.endExclusive);
        }).toList();
      } else {
        expenses = ref.watch(expensesProvider).valueOrNull ?? const [];
      }
      final converter = ref.watch(currencyConverterProvider).valueOrNull;
      // Net out money repaid on split bills: the origin expense is recorded at
      // the full total, but a debtor's repayment isn't the user's own spending.
      final bills = ref.watch(allSplitBillsProvider).valueOrNull ?? const [];
      final billByExpenseId = {for (final b in bills) b.expenseId: b};
      final out = <String, double>{};
      for (final e in expenses) {
        if (e.type != EntryType.expense) continue;
        var amt = converter == null
            ? e.amount
            : (e.baseCurrencyAmount ??
                  converter.toBase(
                    e.amount,
                    e.originalCurrency ?? converter.base,
                  ));
        final bill = billByExpenseId[e.id];
        if (bill != null && bill.totalAmount > 0 && bill.collected > 0) {
          // collected is proportional to the expense amount in whatever
          // currency `amt` is measured, so scale by amt / totalAmount.
          amt = (amt - bill.collected * (amt / bill.totalAmount))
              .clamp(0.0, double.infinity);
        }
        out[e.category] = (out[e.category] ?? 0) + amt;
      }
      return out;
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

class StatsCardOrderNotifier extends StateNotifier<List<String>> {
  final PrefsService _prefs;

  StatsCardOrderNotifier(this._prefs)
    : super(PrefsService.defaultStatsCardOrder) {
    _load();
  }

  Future<void> _load() async {
    state = await _prefs.statsCardOrder();
  }

  Future<void> setOrder(List<String> order) async {
    state = order;
    await _prefs.setStatsCardOrder(order);
  }
}

final statsCardOrderProvider =
    StateNotifierProvider<StatsCardOrderNotifier, List<String>>(
      (ref) => StatsCardOrderNotifier(ref.read(prefsServiceProvider)),
    );

/// Stats report cards the user has hidden. Persisted; a card renders only when
/// its data is available *and* its id is not in this set.
class StatsHiddenCardsNotifier extends StateNotifier<Set<String>> {
  final PrefsService _prefs;

  StatsHiddenCardsNotifier(this._prefs) : super(const {}) {
    _load();
  }

  Future<void> _load() async {
    state = await _prefs.statsHiddenCards();
  }

  Future<void> hide(String id) async {
    if (state.contains(id)) return;
    state = {...state, id};
    await _prefs.setStatsHiddenCards(state);
  }

  Future<void> show(String id) async {
    if (!state.contains(id)) return;
    final next = {...state}..remove(id);
    state = next;
    await _prefs.setStatsHiddenCards(next);
  }
}

final statsHiddenCardsProvider =
    StateNotifierProvider<StatsHiddenCardsNotifier, Set<String>>(
      (ref) => StatsHiddenCardsNotifier(ref.read(prefsServiceProvider)),
    );

class MoneyHubOrderNotifier extends StateNotifier<List<String>> {
  final PrefsService _prefs;

  MoneyHubOrderNotifier(this._prefs)
    : super(PrefsService.defaultMoneyHubOrder) {
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

final preciousMetalRepositoryProvider = Provider<PreciousMetalRepository>((
  ref,
) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalPreciousMetalRepository();
    case StorageMode.firebase:
      final isOnline = ref.watch(isOnlineProvider);
      return isOnline
          ? FirebasePreciousMetalRepository()
          : LocalPreciousMetalRepository();
  }
});

/// Stream of all precious metal transactions for the active user.
/// Uses ref.watch so it re-subscribes whenever connectivity changes
/// (online→Firebase, offline→local Hive). Mirrors Firebase data into
/// local Hive while online so records survive an offline transition.
final preciousMetalsProvider = StreamProvider.autoDispose<List<PreciousMetal>>((
  ref,
) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  final stream = ref.watch(preciousMetalRepositoryProvider).getAll(user.uid);
  if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
    return stream.asyncMap((items) async {
      final local = LocalPreciousMetalRepository();
      final deletedIds = SyncService.getEntityPendingDeleteIds(
        user.uid,
        'metal',
      ).toSet();
      for (final m in items) {
        if (m.id.isNotEmpty && !deletedIds.contains(m.id)) {
          await local.update(user.uid, m);
        }
      }
      return deletedIds.isEmpty
          ? items
          : items.where((m) => !deletedIds.contains(m.id)).toList();
    });
  }
  return stream;
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

final travelGroupRepositoryProvider = Provider<TravelGroupRepository>((ref) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalTravelGroupRepository();
    case StorageMode.firebase:
      final isOnline = ref.watch(isOnlineProvider);
      return isOnline
          ? FirebaseTravelGroupRepository()
          : LocalTravelGroupRepository();
  }
});

final travelGroupServiceProvider = Provider<TravelGroupService>((ref) {
  return TravelGroupService(ref.watch(travelGroupRepositoryProvider));
});

final travelGroupsProvider = StreamProvider.autoDispose<List<TravelGroup>>((
  ref,
) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value(const []);
  final stream = ref.watch(travelGroupServiceProvider).getGroups(user.uid);
  if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
    return stream.asyncMap((groups) async {
      final local = LocalTravelGroupRepository();
      final deletedIds = SyncService.getEntityPendingDeleteIds(
        user.uid,
        'tg',
      ).toSet();
      for (final g in groups) {
        if (g.id.isNotEmpty && !deletedIds.contains(g.id)) {
          await local.updateGroup(g);
        }
      }
      return deletedIds.isEmpty
          ? groups
          : groups.where((g) => !deletedIds.contains(g.id)).toList();
    });
  }
  return stream;
});

final travelGroupMembersProvider = StreamProvider.autoDispose
    .family<List<TravelGroupMember>, String>((ref, groupId) {
      final stream = ref
          .watch(travelGroupRepositoryProvider)
          .getMembers(groupId);
      if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
        return stream.asyncMap((members) async {
          final local = LocalTravelGroupRepository();
          for (final m in members) {
            if (m.id.isNotEmpty) await local.updateMember(groupId, m);
          }
          return members;
        });
      }
      return stream;
    });

final travelGroupExpensesProvider = StreamProvider.autoDispose
    .family<List<TravelExpense>, String>((ref, groupId) {
      final stream = ref
          .watch(travelGroupRepositoryProvider)
          .getExpenses(groupId);
      if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
        return stream.asyncMap((expenses) async {
          final local = LocalTravelGroupRepository();
          // Remove local expenses no longer in Firebase (deletions).
          final localExpenses = await local.getExpenses(groupId).first;
          final firebaseIds = expenses.map((e) => e.id).toSet();
          for (final le in localExpenses) {
            if (le.id.isNotEmpty && !firebaseIds.contains(le.id)) {
              await local.deleteExpense(groupId, le.id);
            }
          }
          // Update local with current Firebase data.
          for (final e in expenses) {
            if (e.id.isNotEmpty) await local.updateExpense(groupId, e);
          }
          return expenses;
        });
      }
      return stream;
    });

// ── Custom Expense Cycle ──────────────────────────────────────────────────────

class UseCustomCycleNotifier extends StateNotifier<bool> {
  UseCustomCycleNotifier(this._prefs) : super(false) {
    _load();
  }
  final PrefsService _prefs;
  Future<void> _load() async {
    state = await _prefs.useCustomCycle();
  }

  Future<void> set(bool value) async {
    state = value;
    await _prefs.setUseCustomCycle(value);
  }
}

final useCustomCycleProvider =
    StateNotifierProvider<UseCustomCycleNotifier, bool>(
      (ref) => UseCustomCycleNotifier(ref.read(prefsServiceProvider)),
    );

class CycleDayStartNotifier extends StateNotifier<int> {
  CycleDayStartNotifier(this._prefs) : super(1) {
    _load();
  }
  final PrefsService _prefs;
  Future<void> _load() async {
    state = await _prefs.cycleDayStart();
  }

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
  ref,
) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalStockInvestmentRepository();
    case StorageMode.firebase:
      final isOnline = ref.watch(isOnlineProvider);
      return isOnline
          ? FirebaseStockInvestmentRepository()
          : LocalStockInvestmentRepository();
  }
});

final stockServiceProvider = Provider((_) => StockService());

/// Stream of all stock investments for the active user.
/// Uses ref.watch so it re-subscribes on connectivity changes and mirrors
/// Firebase data to local Hive while online for offline availability.
final stockInvestmentsProvider =
    StreamProvider.autoDispose<List<StockInvestment>>((ref) {
      final user = ref.watch(authStateProvider).valueOrNull;
      if (user == null) return Stream.value(const []);
      final stream = ref
          .watch(stockInvestmentRepositoryProvider)
          .getAll(user.uid);
      if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
        return stream.asyncMap((items) async {
          final local = LocalStockInvestmentRepository();
          final deletedIds = SyncService.getEntityPendingDeleteIds(
            user.uid,
            'stock',
          ).toSet();
          for (final s in items) {
            if (s.id.isNotEmpty && !deletedIds.contains(s.id)) {
              await local.update(user.uid, s);
            }
          }
          return deletedIds.isEmpty
              ? items
              : items.where((s) => !deletedIds.contains(s.id)).toList();
        });
      }
      return stream;
    });

// ── Expense Groups ────────────────────────────────────────────────────────────

enum HomeMode { personal, group }

final homeModeProvider = StateProvider<HomeMode>((_) => HomeMode.personal);

final activeGroupIdProvider = StateProvider<String?>((_) => null);

final removedExpenseGroupIdsProvider = StateProvider<Set<String>>(
  (_) => const <String>{},
);

final expenseGroupRepositoryProvider = Provider<ExpenseGroupRepository>((ref) {
  switch (storageMode) {
    case StorageMode.local:
      return LocalExpenseGroupRepository();
    case StorageMode.firebase:
      final isOnline = ref.watch(isOnlineProvider);
      return isOnline
          ? FirebaseExpenseGroupRepository()
          : LocalExpenseGroupRepository();
  }
});

final expenseGroupServiceProvider = Provider<ExpenseGroupService>((ref) {
  return ExpenseGroupService(ref.watch(expenseGroupRepositoryProvider));
});

final myGroupsProvider = StreamProvider.autoDispose<List<ExpenseGroup>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  // Reset the removed-group filter whenever the logged-in user changes so
  // that a previous user's "left group" filter doesn't bleed into another
  // user's session on the same device.
  ref.listen(authStateProvider, (prev, next) {
    final prevUid = prev?.valueOrNull?.uid;
    final nextUid = next.valueOrNull?.uid;
    if (prevUid != nextUid) {
      ref.read(removedExpenseGroupIdsProvider.notifier).state = const {};
    }
  });
  final removedGroupIds = ref.watch(removedExpenseGroupIdsProvider);
  if (user == null) return Stream.value(const []);
  // Pending offline group-delete and group-leave IDs — filter these out so
  // the UI immediately hides them even before the Firebase sync runs.
  final pendingDeletes = SyncService.getEntityPendingDeleteIds(
    user.uid,
    'group_delete',
  ).toSet();
  final pendingLeaves = SyncService.getEntityPendingDeleteIds(
    user.uid,
    'group_leave',
  ).toSet();
  final stream = ref
      .watch(expenseGroupServiceProvider)
      .getGroups(user.uid)
      .map(
        (groups) => groups
            .where((g) => !removedGroupIds.contains(g.id))
            .where((g) => !pendingDeletes.contains(g.id))
            .where((g) => !pendingLeaves.contains(g.id))
            .toList(),
      );
  if (storageMode == StorageMode.firebase && ref.watch(isOnlineProvider)) {
    return stream.asyncMap((groups) async {
      final local = LocalExpenseGroupRepository();
      // Only write to Hive groups that are still active for this user.
      for (final g in groups) {
        if (g.id.isNotEmpty) await local.updateGroup(g);
      }
      return groups;
    });
  }
  return stream;
});

final activeGroupProvider = StreamProvider.autoDispose<ExpenseGroup?>((ref) {
  final groupId = ref.watch(activeGroupIdProvider);
  if (groupId == null) return Stream.value(null);
  final groups = ref.watch(myGroupsProvider).valueOrNull ?? const [];
  return Stream.value(
    groups.cast<ExpenseGroup?>().firstWhere(
      (g) => g?.id == groupId,
      orElse: () => null,
    ),
  );
});

// Always stream from local Hive — works offline and updates instantly on save.
final groupExpensesProvider =
    StreamProvider.family<List<GroupExpenseItem>, String>((ref, groupId) {
      return LocalExpenseGroupRepository().getExpenses(groupId);
    });

// ── Quick Add order ──────────────────────────────────────────────────────────

class QuickAddOrderNotifier extends StateNotifier<List<int>> {
  final PrefsService _prefs;

  QuickAddOrderNotifier(this._prefs)
    : super(PrefsService.defaultQuickAddOrder) {
    _load();
  }

  Future<void> _load() async {
    final order = await _prefs.quickAddOrder();
    if (mounted) state = order;
  }

  Future<void> setOrder(List<int> order) async {
    state = order;
    await _prefs.setQuickAddOrder(order);
  }
}

final quickAddOrderProvider =
    StateNotifierProvider<QuickAddOrderNotifier, List<int>>(
      (ref) => QuickAddOrderNotifier(ref.read(prefsServiceProvider)),
    );

// Background sync: pushes Firestore data into local Hive so partners'
// expenses become visible without restarting the app.
final groupExpenseSyncProvider = StreamProvider.family
    .autoDispose<void, String>((ref, groupId) {
      if (storageMode != StorageMode.firebase) return Stream.value(null);
      final user = ref.watch(authStateProvider).valueOrNull;
      final firebaseRepo = FirebaseExpenseGroupRepository();
      final localRepo = LocalExpenseGroupRepository();
      return firebaseRepo.getExpenses(groupId).asyncMap((expenses) async {
        // Tombstone: skip any expense the user deleted offline so Firebase
        // doesn't re-create it in local Hive before sync has pushed the delete.
        final uid = user?.uid ?? '';
        final pendingDeletes = uid.isNotEmpty
            ? SyncService.getEntityPendingDeleteIds(
                uid,
                'group_expense',
              ).toSet()
            : const <String>{};
        for (final e in expenses) {
          if (pendingDeletes.contains('$groupId:${e.id}')) continue;
          try {
            await localRepo.addExpense(e);
          } catch (_) {}
        }
      });
    });
