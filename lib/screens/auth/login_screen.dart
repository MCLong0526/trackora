import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../services/auth_service.dart';
import '../../services/i18n.dart';
import '../../theme/app_theme.dart';
import 'signup_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      await _authService.signIn(
        email: _emailController.text,
        password: _passwordController.text,
      );
    } on FirebaseAuthException catch (e) {
      setState(
        () => _errorMessage = e.message ?? context.t('auth.loginFailed'),
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
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _HeroIllustration(),
                const SizedBox(height: 28),
                Text(
                  context.t('auth.welcomeBack'),
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  context.t('auth.loginSubtitle'),
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
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return context.t('auth.enterEmail');
                    }
                    if (!value.contains('@')) {
                      return context.t('auth.validEmail');
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _signIn(),
                  decoration: InputDecoration(
                    labelText: context.t('auth.password'),
                    prefixIcon: const Icon(CupertinoIcons.lock, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword
                            ? CupertinoIcons.eye
                            : CupertinoIcons.eye_slash,
                        size: 20,
                      ),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  validator: (v) => (v == null || v.isEmpty)
                      ? context.t('auth.enterPassword')
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
                  onPressed: _isLoading ? null : _signIn,
                  child: _isLoading
                      ? SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : Text(context.t('auth.signIn')),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      context.t('auth.noAccount'),
                      style: TextStyle(color: brand.inkSoft),
                    ),
                    TextButton(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const SignupScreen()),
                      ),
                      child: Text(
                        context.t('auth.signUp'),
                        style: TextStyle(
                          color: brand.ink,
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
    );
  }
}

// ── Login hero illustration ────────────────────────────────────

class _HeroIllustration extends StatelessWidget {
  const _HeroIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Balance card — top-left, slight CCW tilt
          Positioned(
            left: 0,
            top: 0,
            child: Transform.rotate(
              angle: -0.06,
              child: const _BalancePreviewCard(),
            ),
          ),
          // Expense + donut card — bottom-right, slight CW tilt
          Positioned(
            right: 0,
            bottom: 0,
            child: Transform.rotate(
              angle: 0.05,
              child: const _ExpensePreviewCard(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalancePreviewCard extends StatelessWidget {
  const _BalancePreviewCard();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TOTAL BALANCE',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              color: brand.inkSoft,
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'RM 12,480',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: brand.ink,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ColorBar(color: const Color(0xFF5B8AF4), width: 52),
              const SizedBox(width: 6),
              _ColorBar(color: const Color(0xFF59C28A), width: 40),
              const SizedBox(width: 6),
              _ColorBar(color: const Color(0xFF8B5CF6), width: 28),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorBar extends StatelessWidget {
  final Color color;
  final double width;
  const _ColorBar({required this.color, required this.width});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _ExpensePreviewCard extends StatelessWidget {
  const _ExpensePreviewCard();

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.peach,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              CupertinoIcons.cart_fill,
              size: 20,
              color: Color(0xFFC07C3A),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Food · Lunch',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: brand.ink,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '–RM 24.50',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFFE96B6B),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          const _MiniDonut(),
        ],
      ),
    );
  }
}

class _MiniDonut extends StatelessWidget {
  const _MiniDonut();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(44, 44),
      painter: _DonutPainter(),
    );
  }
}

class _DonutPainter extends CustomPainter {
  static const _segments = [
    (color: Color(0xFF59C28A), sweep: 0.42),
    (color: Color(0xFFC07C3A), sweep: 0.25),
    (color: Color(0xFF5B8AF4), sweep: 0.20),
    (color: Color(0xFF8B5CF6), sweep: 0.13),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = cx - 2;
    final innerR = outerR * 0.54;
    const gapRad = 0.06;

    double angle = -math.pi / 2;
    for (final seg in _segments) {
      final sweep = seg.sweep * 2 * math.pi - gapRad;
      final paint = Paint()
        ..color = seg.color
        ..style = PaintingStyle.fill;

      final path = Path()
        ..moveTo(cx + outerR * math.cos(angle), cy + outerR * math.sin(angle))
        ..arcTo(
          Rect.fromCircle(center: Offset(cx, cy), radius: outerR),
          angle,
          sweep,
          false,
        )
        ..lineTo(cx + innerR * math.cos(angle + sweep), cy + innerR * math.sin(angle + sweep))
        ..arcTo(
          Rect.fromCircle(center: Offset(cx, cy), radius: innerR),
          angle + sweep,
          -sweep,
          false,
        )
        ..close();

      canvas.drawPath(path, paint);
      angle += seg.sweep * 2 * math.pi;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter _) => false;
}
