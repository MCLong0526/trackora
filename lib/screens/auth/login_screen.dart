import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

import '../../services/auth_service.dart';
import '../../services/biometric_service.dart';
import '../../services/i18n.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import '../../widgets/app_toast.dart';
import '../home/home_shell.dart';
import 'signup_screen.dart';
import 'welcome_screen.dart';

const Color _kPrimary = Color(0xFF0066CC);
const String _kRememberedEmail = 'remembered_email';
const String _kRememberMe = 'remember_me';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _biometricService = BiometricService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = true;
  String? _errorMessage;

  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  String? _biometricEmail;
  bool _biometricInProgress = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final rememberedEmail = prefs.getString(_kRememberedEmail) ?? '';
    final rememberMe = prefs.getBool(_kRememberMe) ?? true;

    final biometricAvailable = await _biometricService.isAvailable();
    final biometricEnabled = await _biometricService.isEnabled();
    final biometricEmail = await _biometricService.storedEmail();

    if (mounted) {
      setState(() {
        _emailController.text = rememberedEmail;
        _rememberMe = rememberMe;
        _biometricAvailable = biometricAvailable;
        _biometricEnabled = biometricEnabled;
        _biometricEmail = biometricEmail;
      });
    }
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      await _authService.signIn(email: email, password: password);

      // Enforce email verification before letting the user into the app.
      // The auth stream already withholds an unverified user, so there is no
      // flash of the home screen here — we just surface a popup and sign out.
      final verified = await _authService.reloadAndCheckEmailVerified();
      if (!verified) {
        if (mounted) {
          setState(() => _isLoading = false);
          await _showVerifyEmailRequired();
        }
        await _authService.signOut();
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      if (_rememberMe) {
        await prefs.setString(_kRememberedEmail, email);
      } else {
        await prefs.remove(_kRememberedEmail);
      }
      await prefs.setBool(_kRememberMe, _rememberMe);

      // Store credentials in secure keychain so biometric unlock can
      // re-authenticate silently on subsequent cold starts.
      if (_biometricAvailable) {
        await _biometricService.enable(email, password);
      }
      _goHome();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyError(e.code);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _biometricSignIn() async {
    // Prevent duplicate concurrent biometric prompts.
    if (_biometricInProgress || _isLoading) return;
    _biometricInProgress = true;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // Safety timeout: always clear loading after 15 seconds if stuck.
    Timer? safetyTimer;
    safetyTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _isLoading) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Sign in timed out. Please try again.';
        });
      }
    });

    try {
      final success = await _biometricService.authenticate();
      if (!success) {
        safetyTimer.cancel();
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'Biometric authentication failed. Please use your password.';
          });
        }
        return;
      }

      // Check if Firebase session is still valid (e.g. brief window between
      // app cold-start and the auth stream emitting the cached user).
      final existingUser = FirebaseAuth.instance.currentUser;
      if (existingUser != null) {
        try {
          await existingUser.reload();
          await existingUser.getIdToken(true);
        } catch (_) {
          // Token refresh failed — fall through to credential re-sign-in.
        }
        final stillValid = FirebaseAuth.instance.currentUser != null;
        if (stillValid) {
          safetyTimer.cancel();
          _goHome();
          return;
        }
      }

      // Session expired or no cached session — re-authenticate silently with
      // stored credentials from the iOS Keychain.
      final creds = await _biometricService.getStoredCredentials();
      if (creds == null) {
        safetyTimer.cancel();
        if (mounted) {
          setState(() {
            _isLoading = false;
            _errorMessage =
                'No saved credentials found. Sign in once with your password to enable Face ID.';
          });
        }
        return;
      }

      await _authService.signIn(email: creds.email, password: creds.password);
      safetyTimer.cancel();
      _goHome();
    } on FirebaseAuthException catch (e) {
      safetyTimer.cancel();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage =
              e.code == 'wrong-password' || e.code == 'invalid-credential'
                  ? 'Your password changed. Sign in with your password once to re-enable Face ID.'
                  : _friendlyError(e.code);
        });
      }
    } catch (e) {
      safetyTimer.cancel();
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Sign in failed. Please use your password.';
        });
      }
    } finally {
      _biometricInProgress = false;
    }
  }

  Future<void> _googleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await _authService.signInWithGoogle();
      if (result == null) {
        if (mounted) setState(() => _isLoading = false);
      } else {
        _goHome();
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = _friendlyError(e.code);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        final msg = e.toString();
        setState(() {
          _errorMessage = (msg.contains('canceled') || msg.contains('cancelled'))
              ? null
              : 'Google sign-in failed. Please try again.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _appleSignIn() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final result = await _authService.signInWithApple();
      if (result == null) {
        if (mounted) setState(() => _isLoading = false);
      } else {
        _goHome();
      }
    } on SignInWithAppleAuthorizationException catch (e) {
      // DIAGNOSTIC (temporary): surface the real reason while debugging.
      debugPrint('Apple sign-in — NATIVE error: ${e.code} — ${e.message}');
      if (mounted) {
        setState(() {
          _errorMessage = e.code == AuthorizationErrorCode.canceled
              ? null
              : 'Apple (native) failed: ${e.code.name} — ${e.message}';
          _isLoading = false;
        });
      }
    } on FirebaseAuthException catch (e) {
      // DIAGNOSTIC (temporary): surface the real Firebase code/message.
      debugPrint('Apple sign-in — FIREBASE error: ${e.code} — ${e.message}');
      if (mounted) {
        setState(() {
          _errorMessage = 'Apple (Firebase) failed: ${e.code} — ${e.message}';
          _isLoading = false;
        });
      }
    } catch (e) {
      // DIAGNOSTIC (temporary): surface any other error.
      debugPrint('Apple sign-in — OTHER error: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Apple sign-in failed: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _goHome() {
    if (!mounted) return;
    AppToast.show(
      context,
      context.t('auth.signedInSuccess'),
      type: AppToastType.success,
      icon: CupertinoIcons.checkmark_seal_fill,
    );
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeShell()),
      (route) => false,
    );
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No account found with this email.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect password. Please try again.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled.';
      case 'too-many-requests':
        return 'Too many failed attempts. Please try again later.';
      default:
        return 'Sign in failed. Please try again.';
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  _BackButton(onTap: () {
                    if (Navigator.canPop(context)) {
                      Navigator.pop(context);
                    } else {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const WelcomeScreen()),
                      );
                    }
                  }),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        context.t('auth.welcomeBack'),
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.t('auth.signIn'),
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w600,
                          color: brand.ink,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 36),
                      _FieldLabel('EMAIL'),
                      const SizedBox(height: 6),
                      _EmailField(controller: _emailController),
                      const SizedBox(height: 20),
                      _FieldLabel('PASSWORD'),
                      const SizedBox(height: 6),
                      _PasswordField(
                        controller: _passwordController,
                        obscure: _obscurePassword,
                        onToggle: () => setState(
                          () => _obscurePassword = !_obscurePassword,
                        ),
                        onSubmitted: (_) => _signIn(),
                        validator: (v) => (v == null || v.isEmpty)
                            ? context.t('auth.enterPassword')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _PrimaryCheckbox(
                            value: _rememberMe,
                            onChanged: (v) =>
                                setState(() => _rememberMe = v ?? true),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            context.t('auth.rememberMe'),
                            style: TextStyle(
                              fontSize: 14,
                              color: brand.ink,
                            ),
                          ),
                          const Spacer(),
                          TextButton(
                            onPressed: _showForgotPassword,
                            style: TextButton.styleFrom(
                              padding: EdgeInsets.zero,
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: Text(
                              context.t('auth.forgotPassword'),
                              style: const TextStyle(
                                color: _kPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 16),
                        _ErrorBanner(message: _errorMessage!),
                      ],
                      const SizedBox(height: 28),
                      _PrimaryButton(
                        label: context.t('auth.signIn'),
                        isLoading: _isLoading,
                        onPressed: _signIn,
                      ),
                      if (_biometricAvailable && _biometricEnabled) ...[
                        const SizedBox(height: 12),
                        _BiometricButton(
                          email: _biometricEmail,
                          onTap: _biometricSignIn,
                          isLoading: _isLoading,
                        ),
                      ],
                      const SizedBox(height: 24),
                      _OrDivider(),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _SocialButton(
                              label: 'Apple',
                              isApple: true,
                              isLoading: _isLoading,
                              onPressed: _appleSignIn,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _SocialButton(
                              label: 'Google',
                              isApple: false,
                              isLoading: _isLoading,
                              onPressed: _googleSignIn,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${context.t('auth.newToApp')} ',
                            style: const TextStyle(
                              color: AppColors.inkSoft,
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const SignupScreen(),
                              ),
                            ),
                            child: Text(
                              context.t('auth.createAccountFlat'),
                              style: const TextStyle(
                                color: _kPrimary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showVerifyEmailRequired() {
    return showAppDialog(
      context: context,
      icon: CupertinoIcons.envelope_badge_fill,
      title: context.t('auth.verifyEmailTitle'),
      message: context.t('auth.verifyEmailRequired'),
      actions: [
        AppDialogAction(
          label: context.t('auth.resendEmail'),
          onTap: () async {
            try {
              await _authService.resendVerificationEmail();
              if (mounted) {
                AppToast.show(
                  context,
                  context.t('auth.verifyEmailResent'),
                  type: AppToastType.success,
                );
              }
            } on VerificationResendLimitException {
              if (mounted) {
                AppToast.show(
                  context,
                  context.t('auth.resendLimitReached'),
                  type: AppToastType.info,
                );
              }
            } catch (_) {
              if (mounted) {
                AppToast.show(
                  context,
                  context.t('auth.resendFailed'),
                  type: AppToastType.error,
                );
              }
            }
          },
        ),
        AppDialogAction(
          label: context.t('common.ok'),
          isPrimary: true,
        ),
      ],
    );
  }

  void _showForgotPassword() {
    final emailCtrl = TextEditingController(text: _emailController.text.trim());
    final resetTitle = context.t('auth.resetPassword');
    final cancelLabel = context.t('common.cancel');
    final sendLabel = context.t('auth.send');
    final sentMsg = context.t('auth.resetEmailSent');
    final failedMsg = context.t('auth.resetEmailFailed');
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(resetTitle),
        content: Padding(
          padding: const EdgeInsets.only(top: 12),
          child: CupertinoTextField(
            controller: emailCtrl,
            placeholder: 'Email address',
            keyboardType: TextInputType.emailAddress,
          ),
        ),
        actions: [
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: Text(cancelLabel),
          ),
          CupertinoDialogAction(
            onPressed: () async {
              Navigator.pop(ctx);
              try {
                await FirebaseAuth.instance.sendPasswordResetEmail(
                  email: emailCtrl.text.trim(),
                );
                if (mounted) {
                  AppToast.show(
                    context,
                    sentMsg,
                    type: AppToastType.success,
                  );
                }
              } catch (_) {
                if (mounted) {
                  AppToast.show(
                    context,
                    failedMsg,
                    type: AppToastType.error,
                  );
                }
              }
            },
            child: Text(sendLabel),
          ),
        ],
      ),
    );
  }
}

// ─── Widgets ──────────────────────────────────────────────────────────────────

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          ),
        child: Icon(
          CupertinoIcons.chevron_left,
          size: 18,
          color: context.brand.ink,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 1.2,
        color: AppColors.inkSoft,
      ),
    );
  }
}

class _EmailField extends StatelessWidget {
  final TextEditingController controller;
  const _EmailField({required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.emailAddress,
      textInputAction: TextInputAction.next,
      style: TextStyle(fontSize: 15, color: context.brand.ink),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        prefixIcon:
            const Icon(CupertinoIcons.mail, size: 18, color: AppColors.inkSoft),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: _kPrimary, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: (v) {
        if (v == null || v.trim().isEmpty) return context.t('auth.enterEmail');
        if (!v.contains('@')) return context.t('auth.validEmail');
        return null;
      },
    );
  }
}

class _PasswordField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final VoidCallback onToggle;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;

  const _PasswordField({
    required this.controller,
    required this.obscure,
    required this.onToggle,
    this.onSubmitted,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: TextInputAction.done,
      onFieldSubmitted: onSubmitted,
      style: TextStyle(fontSize: 15, color: context.brand.ink),
      decoration: InputDecoration(
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        prefixIcon:
            const Icon(CupertinoIcons.lock, size: 18, color: AppColors.inkSoft),
        suffixIcon: GestureDetector(
          onTap: onToggle,
          child: Icon(
            obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
            size: 18,
            color: AppColors.inkSoft,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: const BorderSide(color: _kPrimary, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.white,
      ),
      validator: validator,
    );
  }
}

class _PrimaryCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  const _PrimaryCheckbox({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: Checkbox(
        value: value,
        onChanged: onChanged,
        activeColor: _kPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        side: BorderSide(color: AppColors.divider, width: 1.5),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.blush,
        borderRadius: BorderRadius.circular(AppRadius.field),
      ),
      child: Text(
        message,
        style: const TextStyle(color: AppColors.expense, fontSize: 13),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final bool isLoading;
  final VoidCallback onPressed;

  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: _kPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          elevation: 0,
        ),
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : Text(label),
      ),
    );
  }
}

class _BiometricButton extends StatelessWidget {
  final String? email;
  final VoidCallback onTap;
  final bool isLoading;
  const _BiometricButton({
    this.email,
    required this.onTap,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: OutlinedButton.icon(
        style: OutlinedButton.styleFrom(
          foregroundColor: _kPrimary,
          side: const BorderSide(color: _kPrimary, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.chip),
          ),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        onPressed: isLoading ? null : onTap,
        icon: const Icon(Icons.face_retouching_natural, size: 22),
        label: Text(
          email != null
              ? 'Sign in as ${email!.split('@').first}'
              : 'Sign in with Face ID',
        ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Divider(color: AppColors.divider, thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            context.t('auth.continueWith'),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              color: AppColors.inkSoft,
            ),
          ),
        ),
        Expanded(child: Divider(color: AppColors.divider, thickness: 1)),
      ],
    );
  }
}

class _SocialButton extends StatelessWidget {
  final String label;
  final bool isApple;
  final bool isLoading;
  final VoidCallback onPressed;

  const _SocialButton({
    required this.label,
    required this.isApple,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: context.brand.ink,
        side: BorderSide(color: AppColors.divider),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
      ),
      onPressed: isLoading ? null : onPressed,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isApple ? Icons.apple : Icons.g_mobiledata_rounded,
            size: isApple ? 20 : 26,
            color: context.brand.ink,
          ),
          const SizedBox(width: 8),
          Text(label),
        ],
      ),
    );
  }
}
