import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/auth_service.dart';
import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_dialog.dart';
import 'login_screen.dart';
import 'welcome_screen.dart';

const Color _kPrimary = Color(0xFF0066CC);

class SignupScreen extends ConsumerStatefulWidget {
  const SignupScreen({super.key});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _agreedToTerms = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  int _passwordStrength(String password) {
    if (password.isEmpty) return 0;
    int score = 0;
    if (password.length >= 8) score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (password.contains(RegExp(r'[!@#\$%^&*]'))) score++;
    return score;
  }

  String _strengthLabel(int strength) {
    switch (strength) {
      case 0:
      case 1:
        return 'Weak';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      default:
        return 'Strong';
    }
  }

  Color _strengthColor(int strength) {
    switch (strength) {
      case 0:
      case 1:
        return const Color(0xFFE96B6B);
      case 2:
        return const Color(0xFFF5A623);
      default:
        return const Color(0xFF59C28A);
    }
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToTerms) {
      setState(
        () => _errorMessage = 'Please agree to the Terms and Privacy Policy.',
      );
      return;
    }
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final name = _nameController.text.trim();
      final credential = await _authService.signUp(
        email: email,
        password: password,
      );
      // Persist the entered name as the app-wide display name (used across
      // settings, receipts, splits) and on the Firebase profile.
      await credential.user?.updateDisplayName(name);
      if (name.isNotEmpty) {
        await ref.read(userNameProvider.notifier).set(name);
      }
      // Send a verification email (branded via Firebase console template).
      // Best-effort: never let it block or fail the signup flow.
      try {
        await credential.user?.sendEmailVerification();
      } catch (_) {}
      // Require the user to verify their email before they can sign in. Show a
      // popup, then sign out so the verification gate keeps them on the login
      // screen until they confirm their address. Biometrics are enabled later,
      // on the first verified login, rather than for an unverified account.
      if (mounted) {
        setState(() => _isLoading = false);
        await _showVerifyEmailDialog(email);
      }
      await _authService.signOut();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
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
        setState(() {
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _showVerifyEmailDialog(String email) {
    return showAppDialog(
      context: context,
      icon: CupertinoIcons.envelope_badge_fill,
      title: context.t('auth.verifyEmailTitle'),
      message: context.t('auth.verifyEmailBody').replaceAll('{email}', email),
      actions: [
        AppDialogAction(
          label: context.t('common.ok'),
          isPrimary: true,
        ),
      ],
    );
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password is too weak. Use at least 6 characters.';
      case 'operation-not-allowed':
        return 'Email/password accounts are not enabled.';
      default:
        return 'Sign up failed. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final password = _passwordController.text;
    final strength = _passwordStrength(password);

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
                        context.t('auth.getStarted'),
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.inkSoft,
                          fontWeight: FontWeight.w400,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.t('auth.createAccount'),
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w600,
                          color: brand.ink,
                          letterSpacing: -0.5,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 32),
                      const _FieldLabel('FULL NAME'),
                      const SizedBox(height: 6),
                      _AuthTextField(
                        controller: _nameController,
                        icon: CupertinoIcons.person,
                        hintText: 'Your name',
                        textInputAction: TextInputAction.next,
                        validator: (v) => (v == null || v.trim().isEmpty)
                            ? context.t('validation.enterName')
                            : null,
                      ),
                      const SizedBox(height: 20),
                      const _FieldLabel('EMAIL'),
                      const SizedBox(height: 6),
                      _AuthTextField(
                        controller: _emailController,
                        icon: CupertinoIcons.mail,
                        hintText: 'Email address',
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return context.t('auth.enterEmail');
                          }
                          if (!v.contains('@')) {
                            return context.t('auth.validEmail');
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      const _FieldLabel('PASSWORD'),
                      const SizedBox(height: 6),
                      _PasswordInputField(
                        controller: _passwordController,
                        obscure: _obscurePassword,
                        hintText: 'Password',
                        textInputAction: TextInputAction.next,
                        onToggle: () =>
                            setState(() => _obscurePassword = !_obscurePassword),
                        onChanged: (_) => setState(() {}),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please enter a password';
                          }
                          if (v.length < 6) {
                            return 'At least 6 characters required';
                          }
                          return null;
                        },
                      ),
                      if (password.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _PasswordStrengthBar(
                          strength: strength,
                          color: _strengthColor(strength),
                          label: _strengthLabel(strength),
                        ),
                      ],
                      const SizedBox(height: 20),
                      const _FieldLabel('CONFIRM PASSWORD'),
                      const SizedBox(height: 6),
                      _PasswordInputField(
                        controller: _confirmPasswordController,
                        obscure: _obscureConfirm,
                        hintText: 'Re-enter password',
                        textInputAction: TextInputAction.done,
                        onToggle: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                        validator: (v) {
                          if (v == null || v.isEmpty) {
                            return 'Please confirm your password';
                          }
                          if (v != _passwordController.text) {
                            return 'Passwords do not match';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 20),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 22,
                            height: 22,
                            child: Checkbox(
                              value: _agreedToTerms,
                              onChanged: (v) =>
                                  setState(() => _agreedToTerms = v ?? false),
                              activeColor: _kPrimary,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                              ),
                              side: BorderSide(
                                color: AppColors.divider,
                                width: 1.5,
                              ),
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(
                              TextSpan(
                                style: const TextStyle(fontSize: 13),
                                children: [
                                  TextSpan(
                                    text: context.t('auth.agreeTo'),
                                    style: const TextStyle(color: AppColors.inkSoft),
                                  ),
                                  TextSpan(
                                    text: context.t('auth.terms'),
                                    style: const TextStyle(
                                      color: _kPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {},
                                  ),
                                  TextSpan(
                                    text: context.t('auth.and'),
                                    style: const TextStyle(color: AppColors.inkSoft),
                                  ),
                                  TextSpan(
                                    text: context.t('auth.privacyPolicy'),
                                    style: const TextStyle(
                                      color: _kPrimary,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () {},
                                  ),
                                ],
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
                      SizedBox(
                        height: 56,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            backgroundColor: _kPrimary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(AppRadius.chip),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: _isLoading ? null : _signUp,
                          child: _isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(context.t('auth.createAccountFlat')),
                                    const SizedBox(width: 8),
                                    const Icon(CupertinoIcons.arrow_right, size: 18),
                                  ],
                                ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${context.t('auth.alreadyHaveAccount')} ',
                            style: const TextStyle(
                              color: AppColors.inkSoft,
                              fontSize: 14,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => Navigator.pushReplacement(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const LoginScreen(),
                              ),
                            ),
                            child: Text(
                              context.t('auth.logIn'),
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

class _AuthTextField extends StatelessWidget {
  final TextEditingController controller;
  final IconData icon;
  final String hintText;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final FormFieldValidator<String>? validator;

  const _AuthTextField({
    required this.controller,
    required this.icon,
    required this.hintText,
    this.keyboardType,
    this.textInputAction,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      style: TextStyle(fontSize: 15, color: context.brand.ink),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: TextStyle(color: AppColors.inkSoft.withValues(alpha: 0.6)),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
        prefixIcon: Icon(icon, size: 18, color: AppColors.inkSoft),
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

class _PasswordInputField extends StatelessWidget {
  final TextEditingController controller;
  final bool obscure;
  final String hintText;
  final TextInputAction? textInputAction;
  final VoidCallback onToggle;
  final ValueChanged<String>? onChanged;
  final FormFieldValidator<String>? validator;

  const _PasswordInputField({
    required this.controller,
    required this.obscure,
    required this.hintText,
    required this.onToggle,
    this.textInputAction,
    this.onChanged,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscure,
      textInputAction: textInputAction,
      onChanged: onChanged,
      style: TextStyle(fontSize: 15, color: context.brand.ink),
      decoration: InputDecoration(
        isDense: true,
        hintText: hintText,
        hintStyle: TextStyle(color: AppColors.inkSoft.withValues(alpha: 0.6)),
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

class _PasswordStrengthBar extends StatelessWidget {
  final int strength;
  final Color color;
  final String label;
  const _PasswordStrengthBar({
    required this.strength,
    required this.color,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...List.generate(4, (i) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 3 ? 4 : 0),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 4,
                decoration: BoxDecoration(
                  color: i < strength ? color : AppColors.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          );
        }),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
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
