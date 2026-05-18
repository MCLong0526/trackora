import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../app_config.dart';
import '../firebase_options.dart';
import '../models/expense.dart';
import '../repositories/firebase_account_repository.dart';
import '../repositories/firebase_borrow_lending_repository.dart';
import '../repositories/firebase_expense_repository.dart';
import '../repositories/firebase_installment_repository.dart';
import '../repositories/firebase_precious_metal_repository.dart';
import '../repositories/firebase_saving_plan_repository.dart';
import '../repositories/local_account_repository.dart';
import '../repositories/local_borrow_lending_repository.dart';
import '../repositories/local_expense_repository.dart';
import '../repositories/local_installment_repository.dart';
import '../repositories/local_precious_metal_repository.dart';
import '../repositories/local_saving_plan_repository.dart';
import '../repositories/local_split_bill_repository.dart';
import '../repositories/local_storage.dart';
import '../repositories/split_bill_repository.dart';
import 'storage_service.dart';

enum SyncState { idle, syncing, success, failed }

class SyncService {
  static bool _firebaseReady = storageMode == StorageMode.firebase;

  /// Monotonically-increasing token. Bumped on logout / user-switch so any
  /// in-flight `_uploadAll` aborts before continuing to push the previous
  /// user's data into a different account.
  static int _syncEpoch = 0;

  /// Cancels any in-flight sync. Call on logout so pending uploads from
  /// account A do not land in account B after a user-switch.
  static void cancelInFlight() {
    _syncEpoch++;
  }

  Future<void> _ensureFirebase() async {
    if (_firebaseReady) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _firebaseReady = true;
    } catch (_) {
      // Already initialized (e.g. called twice)
      _firebaseReady = true;
    }
  }

  /// Signs in (or creates) a Firebase account with [email]/[password] and
  /// syncs all local Hive data to Firestore under that user's UID.
  /// Calls [onState] each time the state changes.
  Future<void> signInAndSync({
    required String email,
    required String password,
    required void Function(SyncState) onState,
  }) async {
    onState(SyncState.syncing);
    try {
      await _ensureFirebase();
      final auth = FirebaseAuth.instance;
      UserCredential cred;
      try {
        cred = await auth.signInWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
      } on FirebaseAuthException catch (e) {
        if (e.code == 'user-not-found' || e.code == 'invalid-credential') {
          cred = await auth.createUserWithEmailAndPassword(
            email: email.trim(),
            password: password,
          );
        } else {
          rethrow;
        }
      }
      final uid = cred.user!.uid;
      // Migrate any data from the built-in offline user (local-mode only)
      // first, then push this user's own UID-scoped local cache.
      // Local repos filter by `userId`, so foreign-uid rows are never read.
      await _uploadAll(localUserId, uid);
      await _uploadAll(uid, uid);
      onState(SyncState.success);
    } catch (_) {
      onState(SyncState.failed);
      rethrow;
    }
  }

  /// Re-syncs using the currently signed-in Firebase user.
  /// Throws if no user is authenticated.
  Future<void> syncIfAuthenticated({
    required void Function(SyncState) onState,
  }) async {
    onState(SyncState.syncing);
    try {
      await _ensureFirebase();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        onState(SyncState.failed);
        throw Exception('Not signed in to Firebase.');
      }
      await _uploadAll(localUserId, user.uid);
      onState(SyncState.success);
    } catch (_) {
      onState(SyncState.failed);
      rethrow;
    }
  }

  /// Returns the currently authenticated Firebase user email, or null.
  Future<String?> currentFirebaseEmail() async {
    try {
      await _ensureFirebase();
      return FirebaseAuth.instance.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  // ── Pending offline sync tracking ─────────────────────────────────────────
  //
  // Each pending list is keyed `pending:{ownerUid}` and stores entries shaped
  // `{id, ownerUid}` so we can verify ownership before pushing to Firestore.
  // Older builds stored a `List<String>` of bare ids; readers tolerate both
  // shapes for back-compat and treat string entries as owned by the list's
  // own uid (which is correct because the list itself is uid-keyed).

  static String _pendingKey(String userId) => 'pending:$userId';

  /// Marks [expenseId] as needing sync to Firebase, owned by [userId].
  Future<void> markPending(String userId, String expenseId) async {
    await LocalStorage.init();
    final key = _pendingKey(userId);
    final entries = _readPendingEntries(key);
    if (entries.any((e) => e['id'] == expenseId)) return;
    entries.add({'id': expenseId, 'ownerUid': userId});
    await LocalStorage.pendingSync.put(key, entries);
  }

  /// Removes [expenseId] from the pending set for [userId].
  Future<void> clearPending(String userId, String expenseId) async {
    await LocalStorage.init();
    final key = _pendingKey(userId);
    final entries = _readPendingEntries(key);
    entries.removeWhere((e) => e['id'] == expenseId);
    await LocalStorage.pendingSync.put(key, entries);
  }

  /// Clears all pending entries for [userId].
  Future<void> clearAllPending(String userId) async {
    await LocalStorage.init();
    await LocalStorage.pendingSync.delete(_pendingKey(userId));
  }

  /// Returns the count of pending offline entries for [userId].
  Future<int> pendingCount(String userId) async {
    await LocalStorage.init();
    return _readPendingEntries(_pendingKey(userId)).length;
  }

  // ── Pending offline delete tracking ──────────────────────────────────────

  static String _pendingDeleteKey(String userId) => 'pending_delete:$userId';
  static String _deletedTombstoneKey(String userId) =>
      'deleted_expenses:$userId';

  /// Marks [expenseId] as needing deletion from Firebase, owned by [userId].
  Future<void> markPendingDelete(String userId, String expenseId) async {
    await LocalStorage.init();
    final key = _pendingDeleteKey(userId);
    final ids = _readPendingDeleteIds(key);
    if (!ids.contains(expenseId)) ids.add(expenseId);
    await LocalStorage.pendingDeletes.put(key, ids);
    await _rememberDeletedExpense(userId, expenseId);
  }

  /// Removes [expenseId] from the pending-delete set for [userId].
  Future<void> clearPendingDelete(String userId, String expenseId) async {
    await LocalStorage.init();
    final key = _pendingDeleteKey(userId);
    final ids = _readPendingDeleteIds(key);
    ids.remove(expenseId);
    await LocalStorage.pendingDeletes.put(key, ids);
  }

  /// Clears all pending-delete entries for [userId].
  Future<void> clearAllPendingDeletes(String userId) async {
    await LocalStorage.init();
    await LocalStorage.pendingDeletes.delete(_pendingDeleteKey(userId));
  }

  Future<void> _rememberDeletedExpense(String userId, String expenseId) async {
    final key = _deletedTombstoneKey(userId);
    final raw = LocalStorage.pendingDeletes.get(key, defaultValue: <dynamic>[]);
    final ids = raw is List ? raw.whereType<String>().toSet() : <String>{};
    ids.add(expenseId);
    await LocalStorage.pendingDeletes.put(key, ids.toList());
  }

  Set<String> _deletedExpenseIds(String userId) {
    final raw = LocalStorage.pendingDeletes.get(
      _deletedTombstoneKey(userId),
      defaultValue: <dynamic>[],
    );
    return raw is List ? raw.whereType<String>().toSet() : <String>{};
  }

  List<String> _readPendingDeleteIds(String key) {
    final raw = LocalStorage.pendingDeletes.get(key, defaultValue: <dynamic>[]);
    if (raw is! List) return [];
    return raw.whereType<String>().toList();
  }

  /// Returns the list of expense ids pending deletion for [userId].
  List<String> getPendingDeleteIds(String userId) {
    return _readPendingDeleteIds(_pendingDeleteKey(userId));
  }

  Future<int> pendingDeleteCount(String userId) async {
    await LocalStorage.init();
    return _readPendingDeleteIds(_pendingDeleteKey(userId)).length;
  }

  Stream<int> pendingDeleteCountStream(String userId) async* {
    await LocalStorage.init();
    final key = _pendingDeleteKey(userId);
    yield _readPendingDeleteIds(key).length;
    yield* LocalStorage.pendingDeletes
        .watch(key: key)
        .map<int>((_) => _readPendingDeleteIds(key).length);
  }

  /// Stream of pending count changes.
  Stream<int> pendingCountStream(String userId) async* {
    await LocalStorage.init();
    final key = _pendingKey(userId);
    yield _countFromBox(key);
    yield* LocalStorage.pendingSync
        .watch(key: key)
        .map<int>((_) => _countFromBox(key));
  }

  int _countFromBox(String key) {
    return _readPendingEntries(key).length;
  }

  /// Normalises stored entries to `[{id, ownerUid}, ...]`. Tolerates the
  /// legacy `List<String>` shape by attributing those ids to the list's uid
  /// (parsed from the key). Drops malformed values.
  List<Map<String, String>> _readPendingEntries(String key) {
    final raw = LocalStorage.pendingSync.get(key, defaultValue: <dynamic>[]);
    if (raw is! List) return [];
    final ownerFromKey = key.startsWith('pending:')
        ? key.substring('pending:'.length)
        : '';
    final out = <Map<String, String>>[];
    for (final item in raw) {
      if (item is String && item.isNotEmpty) {
        out.add({'id': item, 'ownerUid': ownerFromKey});
      } else if (item is Map) {
        final id = item['id'];
        final owner = item['ownerUid'];
        if (id is String && id.isNotEmpty) {
          out.add({
            'id': id,
            'ownerUid': owner is String && owner.isNotEmpty
                ? owner
                : ownerFromKey,
          });
        }
      }
    }
    return out;
  }

  /// Syncs pending local entries to Firebase, then clears the pending set.
  /// No-op if no user is authenticated or there are no pending entries.
  Future<void> syncPendingIfAuthenticated({
    required String localUserId,
    required void Function(SyncState) onState,
  }) async {
    try {
      await _ensureFirebase();
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        onState(SyncState.success);
        return;
      }
      // Hard guard: only ever flush a pending queue into the account that
      // owns it. Prevents account A's offline writes from being uploaded
      // to account B after a logout / user-switch.
      if (localUserId != user.uid) {
        dev.log(
          '[SYNC] Skipping pending flush: queue owner ($localUserId) '
          '!= current Firebase uid (${user.uid}).',
          name: 'SyncService',
        );
        onState(SyncState.success);
        return;
      }
      final count = await pendingCount(localUserId);
      final deleteIds = getPendingDeleteIds(localUserId);
      if (count == 0 && deleteIds.isEmpty) {
        await _refreshLocalExpenseMirror(user.uid);
        onState(SyncState.success);
        return;
      }
      onState(SyncState.syncing);
      if (deleteIds.isNotEmpty) {
        final db = FirebaseFirestore.instance;
        final fbExpenses = FirebaseExpenseRepository(firestore: db);
        for (final id in deleteIds) {
          try {
            await fbExpenses.deleteExpense(user.uid, id);
            await clearPendingDelete(localUserId, id);
          } catch (_) {}
        }
      }
      if (count > 0) await _uploadPendingExpenses(localUserId, user.uid);
      await _refreshLocalExpenseMirror(user.uid);
      onState(SyncState.success);
    } catch (e, st) {
      dev.log(
        '[SYNC] syncPendingIfAuthenticated failed: $e',
        name: 'SyncService',
        error: e,
        stackTrace: st,
      );
      onState(SyncState.failed);
    }
  }

  Future<void> deleteExpense({
    required String userId,
    required String expenseId,
    required bool isOnline,
  }) async {
    await LocalStorage.init();
    await _rememberDeletedExpense(userId, expenseId);
    await clearPending(userId, expenseId);
    await LocalExpenseRepository().deleteExpense(userId, expenseId);

    if (!isOnline) {
      await markPendingDelete(userId, expenseId);
      return;
    }

    try {
      await FirebaseExpenseRepository().deleteExpense(userId, expenseId);
      await clearPendingDelete(userId, expenseId);
    } catch (_) {
      await markPendingDelete(userId, expenseId);
    }
  }

  Future<void> _uploadPendingExpenses(String fromUid, String toUid) async {
    final localExpenses = LocalExpenseRepository();
    final fbExpenses = FirebaseExpenseRepository();
    final storage = StorageService();
    final entries = _readPendingEntries(_pendingKey(fromUid));
    final deletedIds = _deletedExpenseIds(fromUid)
      ..addAll(_readPendingDeleteIds(_pendingDeleteKey(fromUid)));

    for (final entry in entries) {
      final id = entry['id'];
      if (id == null || deletedIds.contains(id)) {
        await clearPending(fromUid, id ?? '');
        continue;
      }
      var expense = await localExpenses.getExpenseById(fromUid, id);
      if (expense == null) {
        await clearPending(fromUid, id);
        continue;
      }
      try {
        final url = expense.receiptUrl;
        if (url != null &&
            !StorageService.isRemote(url) &&
            !StorageService.isFirebasePath(url)) {
          final localFile = await StorageService.resolveLocal(url);
          if (localFile != null) {
            final supabaseUrl = await storage.saveReceipt(toUid, localFile);
            expense = expense.copyWith(receiptUrl: supabaseUrl);
            await localExpenses.upsertExpense(fromUid, expense);
          }
        }
        await fbExpenses.upsertExpense(toUid, expense);
        await clearPending(fromUid, id);
      } catch (e, st) {
        dev.log(
          '[SYNC] Failed to upload pending expense $id: $e',
          name: 'SyncService',
          error: e,
          stackTrace: st,
        );
      }
    }
  }

  Future<void> _downloadExpensesToLocal(String uid) async {
    final pendingIds = _readPendingEntries(
      _pendingKey(uid),
    ).map((e) => e['id']).whereType<String>().toSet();
    final pendingDeleteIds = _readPendingDeleteIds(
      _pendingDeleteKey(uid),
    ).toSet();
    final deletedIds = _deletedExpenseIds(uid)..addAll(pendingDeleteIds);
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('expenses')
        .get();
    final remote = <Expense>[];
    for (final doc in snap.docs) {
      if (deletedIds.contains(doc.id)) continue;
      remote.add(Expense.fromMap(doc.data(), id: doc.id));
    }
    await LocalExpenseRepository().replaceAllExpenses(
      uid,
      remote,
      preserveIds: pendingIds,
    );
    for (final id in pendingDeleteIds) {
      await LocalExpenseRepository().deleteExpense(uid, id);
    }
  }

  Future<void> _refreshLocalExpenseMirror(String uid) async {
    try {
      await _downloadExpensesToLocal(uid);
    } catch (e, st) {
      dev.log(
        '[SYNC] Local expense mirror refresh failed: $e',
        name: 'SyncService',
        error: e,
        stackTrace: st,
      );
    }
  }

  Future<void> _uploadAll(String fromUid, String toUid) async {
    final db = FirebaseFirestore.instance;
    final epoch = _syncEpoch;

    // After a logout / user-switch, _syncEpoch is bumped. Bail if we no
    // longer match the current Firebase user — this stops a partially-run
    // sync from continuing to push the previous user's data after switch.
    bool stillCurrent() {
      if (epoch != _syncEpoch) return false;
      final cur = FirebaseAuth.instance.currentUser;
      if (cur == null) return false;
      return cur.uid == toUid;
    }

    // ── Expenses ──────────────────────────────────────────────────────────
    final localExpenses = LocalExpenseRepository();
    final fbExpenses = FirebaseExpenseRepository(firestore: db);
    final storage = StorageService();
    final expenses = await localExpenses.getAllExpenses(fromUid).first;
    for (var e in expenses) {
      if (!stillCurrent()) return;
      try {
        // Upload any locally-cached receipt to Supabase before syncing.
        final url = e.receiptUrl;
        if (url != null &&
            !StorageService.isRemote(url) &&
            !StorageService.isFirebasePath(url)) {
          try {
            final localFile = await StorageService.resolveLocal(url);
            if (localFile != null) {
              final supabaseUrl = await storage.saveReceipt(toUid, localFile);
              e = e.copyWith(receiptUrl: supabaseUrl);
              // Update local copy so re-syncs don't re-upload.
              await localExpenses.upsertExpense(fromUid, e);
              dev.log(
                '[SYNC] Receipt uploaded for expense ${e.id}: $supabaseUrl',
                name: 'SyncService',
              );
            }
          } catch (uploadErr) {
            dev.log(
              '[SYNC] Receipt upload failed for expense ${e.id}: $uploadErr — syncing without receipt URL.',
              name: 'SyncService',
              error: uploadErr,
            );
            e = e.copyWith(receiptUrl: null);
          }
        }
        await fbExpenses.upsertExpense(toUid, e);
      } catch (itemErr, itemSt) {
        dev.log(
          '[SYNC] Skipping expense ${e.id} due to error: $itemErr',
          name: 'SyncService',
          error: itemErr,
          stackTrace: itemSt,
        );
      }
    }

    if (!stillCurrent()) return;

    // ── Budget & Opening Savings meta ────────────────────────────────────
    final budget = await localExpenses.getMonthlyBudget(fromUid).first;
    if (budget > 0) await fbExpenses.setMonthlyBudget(toUid, budget);
    final savings = await localExpenses.getOpeningSavings(fromUid).first;
    if (savings != 0) await fbExpenses.setOpeningSavings(toUid, savings);

    // ── Accounts ─────────────────────────────────────────────────────────
    final localAccounts = LocalAccountRepository();
    final fbAccounts = FirebaseAccountRepository(firestore: db);
    final accounts = await localAccounts.getAll(fromUid).first;
    for (final a in accounts) {
      if (!stillCurrent()) return;
      await fbAccounts.upsert(toUid, a);
    }

    // ── Installments ─────────────────────────────────────────────────────
    final localInstallments = LocalInstallmentRepository();
    final fbInstallments = FirebaseInstallmentRepository(firestore: db);
    final installments = await localInstallments.getAll(fromUid).first;
    for (final i in installments) {
      if (i.id.isEmpty) continue;
      if (!stillCurrent()) return;
      await fbInstallments.upsert(toUid, i);
    }

    // ── Saving Plans ─────────────────────────────────────────────────────
    final localPlans = LocalSavingPlanRepository();
    final fbPlans = FirebaseSavingPlanRepository();
    final plans = await localPlans.getAll(fromUid).first;
    for (final p in plans) {
      if (p.id.isEmpty) continue;
      if (!stillCurrent()) return;
      await fbPlans.upsertById(toUid, p);
    }

    // ── Borrow / Lending ─────────────────────────────────────────────────
    final localBL = LocalBorrowLendingRepository();
    final fbBL = FirebaseBorrowLendingRepository();
    final blRecords = await localBL.getAll(fromUid).first;
    for (final r in blRecords) {
      if (r.id.isEmpty) continue;
      if (!stillCurrent()) return;
      await fbBL.upsertById(toUid, r);
    }

    // ── Precious Metals ──────────────────────────────────────────────────
    final localMetals = LocalPreciousMetalRepository();
    final fbMetals = FirebasePreciousMetalRepository();
    final metals = await localMetals.getAll(fromUid).first;
    for (final m in metals) {
      if (m.id.isEmpty) continue;
      if (!stillCurrent()) return;
      await fbMetals.upsertById(toUid, m);
    }

    // ── Split Bills ───────────────────────────────────────────────────────────
    final localSplitBills = LocalSplitBillRepository();
    final fbSplitBills = SplitBillRepository();
    final splitBills = await localSplitBills.getAllSplitBills(fromUid);
    for (final sb in splitBills) {
      if (sb.id.isEmpty || sb.expenseId.isEmpty) continue;
      if (!stillCurrent()) return;
      try {
        await fbSplitBills.saveSplitBill(toUid, sb);
      } catch (sbErr) {
        dev.log(
          '[SYNC] Skipping split bill ${sb.id}: $sbErr',
          name: 'SyncService',
          error: sbErr,
        );
      }
    }
  }
}
