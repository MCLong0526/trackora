import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../app_config.dart';
import '../firebase_options.dart';
import '../repositories/firebase_account_repository.dart';
import '../repositories/firebase_borrow_lending_repository.dart';
import '../repositories/firebase_expense_repository.dart';
import '../repositories/firebase_installment_repository.dart';
import '../repositories/firebase_saving_plan_repository.dart';
import '../repositories/local_account_repository.dart';
import '../repositories/local_borrow_lending_repository.dart';
import '../repositories/local_expense_repository.dart';
import '../repositories/local_installment_repository.dart';
import '../repositories/local_saving_plan_repository.dart';

enum SyncState { idle, syncing, success, failed }

class SyncService {
  static bool _firebaseReady = storageMode == StorageMode.firebase;

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
      await _uploadAll(localUserId, uid);
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

  Future<void> _uploadAll(String fromUid, String toUid) async {
    final db = FirebaseFirestore.instance;

    // ── Expenses ──────────────────────────────────────────────────────────
    final localExpenses = LocalExpenseRepository();
    final fbExpenses = FirebaseExpenseRepository(firestore: db);
    final expenses = await localExpenses.getAllExpenses(fromUid).first;
    for (final e in expenses) {
      await fbExpenses.upsertExpense(toUid, e);
    }

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
      await fbAccounts.upsert(toUid, a);
    }

    // ── Installments ─────────────────────────────────────────────────────
    final localInstallments = LocalInstallmentRepository();
    final fbInstallments = FirebaseInstallmentRepository(firestore: db);
    final installments = await localInstallments.getAll(fromUid).first;
    for (final i in installments) {
      if (i.id.isEmpty) continue;
      await fbInstallments.upsert(toUid, i);
    }

    // ── Saving Plans ─────────────────────────────────────────────────────
    final localPlans = LocalSavingPlanRepository();
    final fbPlans = FirebaseSavingPlanRepository();
    final plans = await localPlans.getAll(fromUid).first;
    for (final p in plans) {
      if (p.id.isEmpty) continue;
      await fbPlans.upsertById(toUid, p);
    }

    // ── Borrow / Lending ─────────────────────────────────────────────────
    final localBL = LocalBorrowLendingRepository();
    final fbBL = FirebaseBorrowLendingRepository();
    final blRecords = await localBL.getAll(fromUid).first;
    for (final r in blRecords) {
      if (r.id.isEmpty) continue;
        await fbBL.upsertById(toUid, r);
    }
  }
}
