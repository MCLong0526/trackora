import 'dart:convert';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

// Thrown when the per-day verification-email resend cap has been reached.
class VerificationResendLimitException implements Exception {
  final int maxPerDay;
  const VerificationResendLimitException(this.maxPerDay);
  @override
  String toString() => 'Resend limit of $maxPerDay per day reached.';
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
      // Require a verified email before the app treats the account as signed
      // in. OAuth providers (Google / Apple) report emailVerified == true, so
      // they pass through unaffected; only unverified email/password accounts
      // are held back until they confirm their address.
      if (!user.emailVerified) return null;
      return AppUser(uid: user.uid, email: user.email);
    });
  }

  /// Whether the currently signed-in Firebase user has a verified email.
  bool get isEmailVerified =>
      storageMode == StorageMode.local || (_auth.currentUser?.emailVerified ?? false);

  /// Max verification-email resends allowed per calendar day.
  static const int maxVerificationResendsPerDay = 3;
  static const _kVerifyResendCount = 'verify_resend_count';
  static const _kVerifyResendDate = 'verify_resend_date';

  /// Resends the verification email to the currently signed-in user, capped at
  /// [maxVerificationResendsPerDay] per calendar day (the count resets the next
  /// day). Returns the number of resends still available today *after* this
  /// one.
  ///
  /// Throws [VerificationResendLimitException] when today's cap is already
  /// reached, or [FirebaseAuthException] when there is no signed-in user or the
  /// send itself fails — callers should surface these instead of swallowing
  /// them, so a failed/throttled send is never reported as success.
  Future<int> resendVerificationEmail() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now();
    final today = '${now.year}-'
        '${now.month.toString().padLeft(2, '0')}-'
        '${now.day.toString().padLeft(2, '0')}';
    // A new day resets the counter.
    var count = prefs.getString(_kVerifyResendDate) == today
        ? (prefs.getInt(_kVerifyResendCount) ?? 0)
        : 0;

    if (count >= maxVerificationResendsPerDay) {
      throw const VerificationResendLimitException(maxVerificationResendsPerDay);
    }

    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'no-current-user',
        message: 'You need to sign in again before resending.',
      );
    }
    // Let any FirebaseAuthException (e.g. too-many-requests) propagate so the
    // caller can tell the user the truth. Only count a successful send.
    await user.sendEmailVerification();

    count += 1;
    await prefs.setInt(_kVerifyResendCount, count);
    await prefs.setString(_kVerifyResendDate, today);
    return maxVerificationResendsPerDay - count;
  }

  /// Reloads the current user from the server and returns whether their email
  /// is now verified. Used at login to enforce verification before entry.
  Future<bool> reloadAndCheckEmailVerified() async {
    final user = _auth.currentUser;
    if (user == null) return false;
    await user.reload();
    return _auth.currentUser?.emailVerified ?? false;
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
    // Firebase validates the Apple identity token against a nonce: send the
    // SHA-256 of a random nonce to Apple, then hand Firebase the raw value.
    // (Apple's authorizationCode is NOT an OAuth access token — passing it as
    // one makes Firebase reject the credential with `invalid-credential`.)
    // DIAGNOSTIC (temporary): proves the corrected build is actually running.
    debugPrint('🍎 Apple sign-in: nonce flow active (idToken + rawNonce, no accessToken)');
    final rawNonce = _generateNonce();
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: _sha256OfString(rawNonce),
    );
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
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
    final rawNonce = _generateNonce();
    final appleCredential = await SignInWithApple.getAppleIDCredential(
      scopes: [
        AppleIDAuthorizationScopes.email,
        AppleIDAuthorizationScopes.fullName,
      ],
      nonce: _sha256OfString(rawNonce),
    );
    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCredential.identityToken,
      rawNonce: rawNonce,
    );
    await user.reauthenticateWithCredential(oauthCredential);
  }

  // ── Private helpers ──────────────────────────────────────────────────────────

  /// A cryptographically-random nonce string for Apple sign-in.
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  String _sha256OfString(String input) =>
      sha256.convert(utf8.encode(input)).toString();

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
      LocalStorage.stockInvestments.clear(),
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
