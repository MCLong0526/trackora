import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../app_config.dart';
import '../models/app_user.dart';
import '../repositories/local_storage.dart';
import 'sync_service.dart';

// Thrown when the user's session is too old for a sensitive operation and
// re-authentication is required.
class ReauthRequiredException implements Exception {
  final String message;
  const ReauthRequiredException(this.message);
  @override
  String toString() => message;
}

class AuthService {
  FirebaseAuth get _auth => FirebaseAuth.instance;

  // The currently signed-in user, or the built-in local user in offline mode.
  AppUser? get currentUser {
    if (storageMode == StorageMode.local) return const AppUser.local();
    final user = _auth.currentUser;
    if (user == null) return null;
    return AppUser(uid: user.uid, email: user.email);
  }

  // Stream that emits the app-facing user whenever auth state changes.
  // Used by main.dart to navigate between signed-out and signed-in screens.
  Stream<AppUser?> get authStateChanges {
    if (storageMode == StorageMode.local) {
      return Stream.value(const AppUser.local());
    }
    return _auth.authStateChanges().map((user) {
      if (user == null) return null;
      return AppUser(uid: user.uid, email: user.email);
    });
  }

  // Creates a new account with email and password.
  // Throws FirebaseAuthException on failure (e.g. email already in use).
  Future<UserCredential> signUp({
    required String email,
    required String password,
  }) async {
    if (storageMode == StorageMode.local) {
      throw UnsupportedError('Sign up is only available in Firebase mode.');
    }
    return await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  // Signs in an existing user with email and password.
  // Throws FirebaseAuthException on failure (e.g. wrong password).
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    if (storageMode == StorageMode.local) {
      throw UnsupportedError('Sign in is only available in Firebase mode.');
    }
    return await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
  }

  // Signs out the current user.
  Future<void> signOut() async {
    if (storageMode == StorageMode.local) return;
    // Stop any in-flight upload for the outgoing user before tearing down
    // the auth session — otherwise a sync started under account A could
    // continue pushing to A's UID while account B is signing in, or worse,
    // race against B's first writes.
    SyncService.cancelInFlight();
    await _auth.signOut();
    // Also sign out of Google so the next login shows the account picker.
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}
  }

  /// Signs in with Google via Firebase Auth.
  /// Returns null if the user cancelled the flow.
  Future<UserCredential?> signInWithGoogle() async {
    if (storageMode == StorageMode.local) {
      throw UnsupportedError('Sign in is only available in Firebase mode.');
    }
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) return null;
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    return await _auth.signInWithCredential(credential);
  }

  /// Signs in with Apple via Firebase Auth.
  /// Returns null if the user cancelled the flow.
  Future<UserCredential?> signInWithApple() async {
    if (storageMode == StorageMode.local) {
      throw UnsupportedError('Sign in is only available in Firebase mode.');
    }
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );
    return await _auth.signInWithCredential(oauthCredential);
  }

  // ── Account deletion ────────────────────────────────────────────────────────

  /// Permanently deletes the Firebase Auth account and all associated data.
  ///
  /// Throws [FirebaseAuthException] with code `requires-recent-login` when the
  /// user's session is stale. In that case, call one of the reauth helpers
  /// ([reauthWithPassword], [reauthWithGoogle], [reauthWithApple]) and retry.
  Future<void> deleteAccount() async {
    if (storageMode == StorageMode.local) {
      throw UnsupportedError('Delete account is only available in Firebase mode.');
    }
    final user = _auth.currentUser;
    if (user == null) return;
    final uid = user.uid;

    // Cancel any in-flight sync before tearing down the account.
    SyncService.cancelInFlight();

    // Best-effort: wipe Firestore data first.
    try {
      await _deleteFirestoreData(uid);
    } catch (_) {
      // Non-fatal — proceed with auth deletion even if Firestore cleanup fails.
    }

    // Delete the Firebase Auth user. Throws requires-recent-login if session stale.
    await user.delete();

    // Also sign out of Google so next login shows the account picker.
    try {
      await GoogleSignIn().signOut();
    } catch (_) {}

    // Clear all local Hive data.
    await _clearLocalData();
  }

  /// Re-authenticates with email/password before [deleteAccount].
  Future<void> reauthWithPassword(String password) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const ReauthRequiredException('No signed-in user.');
    }
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw const ReauthRequiredException('Incorrect password.');
      }
      rethrow;
    }
  }

  /// Re-authenticates with Google before [deleteAccount].
  Future<void> reauthWithGoogle() async {
    final user = _auth.currentUser;
    if (user == null) throw const ReauthRequiredException('No signed-in user.');
    final googleUser = await GoogleSignIn().signIn();
    if (googleUser == null) throw const ReauthRequiredException('Cancelled.');
    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      accessToken: googleAuth.accessToken,
      idToken: googleAuth.idToken,
    );
    await user.reauthenticateWithCredential(credential);
  }

  /// Re-authenticates with Apple before [deleteAccount].
  Future<void> reauthWithApple() async {
    final user = _auth.currentUser;
    if (user == null) throw const ReauthRequiredException('No signed-in user.');
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
    );
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      accessToken: appleCredential.authorizationCode,
    );
    await user.reauthenticateWithCredential(oauthCredential);
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  Future<void> _deleteFirestoreData(String uid) async {
    final db = FirebaseFirestore.instance;
    const subcollections = [
      'expenses',
      'accounts',
      'installments',
      'borrowLending',
      'savingPlans',
      'people',
      'preciousMetals',
      'travelGroups',
      'meta',
    ];
    for (final sub in subcollections) {
      final ref = db.collection('users').doc(uid).collection(sub);
      await _batchDeleteCollection(db, ref);
    }
    // Delete top-level user document.
    await db.collection('users').doc(uid).delete();
  }

  Future<void> _batchDeleteCollection(
    FirebaseFirestore db,
    CollectionReference<Map<String, dynamic>> ref,
  ) async {
    QuerySnapshot snap;
    do {
      snap = await ref.limit(100).get();
      if (snap.docs.isEmpty) break;
      final batch = db.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } while (snap.docs.length >= 100);
  }

  Future<void> _clearLocalData() async {
    await LocalStorage.init();
    await Future.wait([
      LocalStorage.expenses.clear(),
      LocalStorage.accounts.clear(),
      LocalStorage.installments.clear(),
      LocalStorage.borrowLending.clear(),
      LocalStorage.savingPlans.clear(),
      LocalStorage.people.clear(),
      LocalStorage.preciousMetals.clear(),
      LocalStorage.travelGroups.clear(),
      LocalStorage.travelExpenses.clear(),
      LocalStorage.travelMembers.clear(),
      LocalStorage.splitBills.clear(),
      LocalStorage.pendingSync.clear(),
      LocalStorage.pendingDeletes.clear(),
      LocalStorage.meta.clear(),
    ]);
  }

  // ── Email change ─────────────────────────────────────────────────────────────

  /// Re-authenticates the current user with their password, then sends a
  /// verification link to [newEmail]. The email only changes after the user
  /// clicks the link in their new inbox.
  Future<void> changeEmail({
    required String currentPassword,
    required String newEmail,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const ReauthRequiredException('No signed-in user.');
    }
    // Re-authenticate so Firebase accepts the sensitive email-change operation.
    final credential = EmailAuthProvider.credential(
      email: user.email!,
      password: currentPassword,
    );
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw const ReauthRequiredException('Incorrect password.');
      }
      rethrow;
    }
    // Send verification email to new address; change takes effect after click.
    await user.verifyBeforeUpdateEmail(newEmail.trim());
  }
}
