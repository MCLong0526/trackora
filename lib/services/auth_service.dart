// ─────────────────────────────────────────────────────────────
// lib/services/auth_service.dart
// Wraps Firebase Auth methods (sign up, sign in, sign out).
// All screens talk to this service instead of Firebase directly.
// ─────────────────────────────────────────────────────────────

import 'package:firebase_auth/firebase_auth.dart';

import '../app_config.dart';
import '../models/app_user.dart';

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
}
