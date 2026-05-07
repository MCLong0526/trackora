import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../theme/app_theme.dart';
import 'login_screen.dart';
import 'signup_screen.dart';

const Color _kPrimary = Color(0xFF5B5FEF);
const String _kHasSeenWelcome = 'has_seen_welcome';

Future<void> markWelcomeSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kHasSeenWelcome, true);
}

Future<bool> hasSeenWelcome() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kHasSeenWelcome) ?? false;
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  void _toSignup(BuildContext context) async {
    await markWelcomeSeen();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SignupScreen()),
    );
  }

  void _toLogin(BuildContext context) async {
    await markWelcomeSeen();
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            _IllustrationCards(),
            const Spacer(flex: 3),
            _AppBranding(),
            const Spacer(flex: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: _kPrimary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      onPressed: () => _toSignup(context),
                      child: const Text('Create an account'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Already have an account? ',
                        style: TextStyle(
                          color: AppColors.inkSoft,
                          fontSize: 15,
                        ),
                      ),
                      GestureDetector(
                        onTap: () => _toLogin(context),
                        child: const Text(
                          'Log in',
                          style: TextStyle(
                            color: _kPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _AppBranding extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6C72FF), Color(0xFF4E52D8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: _kPrimary.withValues(alpha: 0.35),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: _StackedCardsIcon(),
          ),
        ),
        const SizedBox(height: 18),
        const Text(
          'Trackora',
          style: TextStyle(
            fontSize: 38,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.5,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'A calmer way to see where every ringgit goes — across all your accounts.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.inkSoft,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }
}

class _IllustrationCards extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 220,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Balance card (back, rotated left)
          Positioned(
            left: 30,
            top: 10,
            child: Transform.rotate(
              angle: -0.08,
              child: _BalanceCard(),
            ),
          ),
          // Expense + chart card (front, slight right tilt)
          Positioned(
            right: 20,
            bottom: 0,
            child: Transform.rotate(
              angle: 0.04,
              child: _ExpenseChartCard(),
            ),
          ),
        ],
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 210,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'TOTAL BALANCE',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'RM 12,480',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: Color(0xFF111111),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _ColorDot(color: _kPrimary),
              const SizedBox(width: 6),
              _ColorDot(color: const Color(0xFF59C28A)),
              const SizedBox(width: 6),
              _ColorDot(color: const Color(0xFFE4D7F5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  final Color color;
  const _ColorDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 28,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _ExpenseChartCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 190,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFCD9B6),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        CupertinoIcons.cart_fill,
                        size: 18,
                        color: Color(0xFFE0873A),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Food · Lunch',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111111),
                          ),
                        ),
                        Text(
                          '–RM 24.50',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColors.inkSoft,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
          _MiniDonutChart(),
        ],
      ),
    );
  }
}

class _MiniDonutChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(54, 54),
      painter: _DonutPainter(),
    );
  }
}

class _DonutPainter extends CustomPainter {
  static const _segments = [
    (color: Color(0xFF59C28A), fraction: 0.42),
    (color: Color(0xFFC4813A), fraction: 0.28),
    (color: Color(0xFF5B5FEF), fraction: 0.18),
    (color: Color(0xFF60A5FA), fraction: 0.12),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final outerR = cx - 2;
    final innerR = outerR * 0.52;
    const gapRad = 0.07;

    double angle = -math.pi / 2;
    for (final seg in _segments) {
      final sweep = seg.fraction * 2 * math.pi - gapRad;
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

      canvas.drawPath(path, Paint()..color = seg.color);
      angle += seg.fraction * 2 * math.pi;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter _) => false;
}

/// Stacked cards icon matching the Trackora brand — three fanned cards
/// (yellow back, lavender middle, white front with account elements).
class _StackedCardsIcon extends StatelessWidget {
  const _StackedCardsIcon();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _StackedCardsPainter(),
    );
  }
}

class _StackedCardsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    void drawCard(
      Canvas canvas,
      double cx,
      double cy,
      double cw,
      double ch,
      double angle,
      Color color,
    ) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: cw, height: ch),
        const Radius.circular(3),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = color
          ..style = PaintingStyle.fill,
      );
      canvas.restore();
    }

    // Back card — yellow, rotated left
    drawCard(canvas, w * 0.35, h * 0.55, w * 0.72, h * 0.46, -0.35,
        const Color(0xFFFFCB47));

    // Middle card — lavender, slight rotation
    drawCard(canvas, w * 0.55, h * 0.50, w * 0.72, h * 0.46, -0.12,
        const Color(0xFFD4C9F5));

    // Front card — white, straight
    drawCard(canvas, w * 0.55, h * 0.52, w * 0.72, h * 0.46, 0.05,
        Colors.white);

    // Front card details — dark strip (card number area)
    canvas.save();
    canvas.translate(w * 0.55, h * 0.52);
    canvas.rotate(0.05);
    final stripRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, h * 0.06),
        width: w * 0.52,
        height: h * 0.08,
      ),
      const Radius.circular(2),
    );
    canvas.drawRRect(
      stripRect,
      Paint()..color = const Color(0xFF1A1A2E),
    );
    // Two small dots (chip + contactless)
    canvas.drawCircle(
      Offset(w * 0.18, h * 0.0),
      w * 0.055,
      Paint()..color = const Color(0xFF5B5FEF),
    );
    canvas.drawCircle(
      Offset(w * 0.28, h * 0.0),
      w * 0.055,
      Paint()..color = const Color(0xFF5B5FEF).withValues(alpha: 0.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
