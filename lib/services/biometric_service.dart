import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricService {
  static const _kBiometricEnabled = 'biometric_enabled';
  static const _kBiometricEmail = 'biometric_email';
  static const _kSecureEmail = 'trackora_secure_email';
  static const _kSecurePassword = 'trackora_secure_password';

  final _auth = LocalAuthentication();
  final _secureStorage = const FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  Future<bool> isAvailable() async {
    try {
      return await _auth.canCheckBiometrics || await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kBiometricEnabled) ?? false;
  }

  Future<String?> storedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_kBiometricEmail);
  }

  /// Call after successful email/password sign-in to enable biometrics.
  /// Stores credentials securely in the OS keychain so biometric unlock
  /// can re-authenticate even after a cold start.
  Future<void> enable(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricEnabled, true);
    await prefs.setString(_kBiometricEmail, email);
    await _secureStorage.write(key: _kSecureEmail, value: email);
    await _secureStorage.write(key: _kSecurePassword, value: password);
  }

  /// Returns stored credentials if available, null otherwise.
  Future<({String email, String password})?> getStoredCredentials() async {
    try {
      final email = await _secureStorage.read(key: _kSecureEmail);
      final password = await _secureStorage.read(key: _kSecurePassword);
      if (email != null && password != null) {
        return (email: email, password: password);
      }
    } catch (_) {}
    return null;
  }

  /// Call on logout to clear biometric preference and stored credentials.
  Future<void> disable() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBiometricEnabled);
    await prefs.remove(_kBiometricEmail);
    await _secureStorage.delete(key: _kSecureEmail);
    await _secureStorage.delete(key: _kSecurePassword);
  }

  /// Prompt the user with a biometric challenge.
  /// Returns true if authentication succeeded.
  /// Times out after 60 seconds to prevent infinite loading.
  Future<bool> authenticate() async {
    try {
      return await _auth
          .authenticate(
            localizedReason: 'Sign in to Trackora',
            options: const AuthenticationOptions(
              stickyAuth: true,
              biometricOnly: false,
            ),
          )
          .timeout(const Duration(seconds: 60), onTimeout: () => false);
    } catch (_) {
      return false;
    }
  }
}
