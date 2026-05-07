// ─────────────────────────────────────────────────────────────
// lib/services/auth_service.dart
// Wraps Firebase Auth methods (sign up, sign in, sign out).
// All screens talk to this service instead of Firebase directly.
// ─────────────────────────────────────────────────────────────

import 'package:firebase_auth/firebase_auth.dart';

import '../app_config.dart';
import '../models/app_user.dart';

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
    await _auth.signOut();
  }

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
