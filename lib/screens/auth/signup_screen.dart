import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../services/i18n.dart';
import '../../theme/app_theme.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscure1 = true;
  bool _obscure2 = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _signUp() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.signUp(
        email: _emailController.text,
        password: _passwordController.text,
      );
      if (mounted) Navigator.pop(context);
    } on FirebaseAuthException catch (e) {
      setState(
        () => _errorMessage = e.message ?? context.t('auth.signupFailed'),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  context.t('auth.createAccount'),
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  context.t('auth.signupSubtitle'),
                  style: TextStyle(color: brand.inkSoft, fontSize: 15),
                ),
                const SizedBox(height: 36),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.t('auth.email'),
                    prefixIcon: const Icon(CupertinoIcons.mail, size: 20),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return context.t('auth.enterEmail');
                    }
                    if (!v.contains('@')) return context.t('auth.validEmail');
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscure1,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: context.t('auth.password'),
                    prefixIcon: const Icon(CupertinoIcons.lock, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure1
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure1 = !_obscure1),
                    ),
                  ),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return context.t('auth.enterPassword');
                    }
                    if (v.length < 6) return context.t('auth.minPassword');
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _confirmController,
                  obscureText: _obscure2,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _signUp(),
                  decoration: InputDecoration(
                    labelText: context.t('auth.confirmPassword'),
                    prefixIcon: const Icon(CupertinoIcons.lock, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscure2
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        size: 20,
                      ),
                      onPressed: () => setState(() => _obscure2 = !_obscure2),
                    ),
                  ),
                  validator: (v) => v != _passwordController.text
                      ? context.t('auth.passwordMismatch')
                      : null,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.blush,
                      borderRadius: BorderRadius.circular(AppRadius.field),
                    ),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: AppColors.expense,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _isLoading ? null : _signUp,
                  child: _isLoading
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : Text(context.t('auth.createAccountFlat')),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
