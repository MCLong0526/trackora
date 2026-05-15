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

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _entranceController;
  late AnimationController _floatController;

  late Animation<double> _fadeAnim;
  late Animation<Offset> _slideAnim;
  late Animation<double> _floatAnim;

  @override
  void initState() {
    super.initState();

    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat(reverse: true);

    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: const Interval(0.0, 0.7, curve: Curves.easeOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));
    _floatAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _floatController, curve: Curves.easeInOut),
    );

    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _floatController.dispose();
    super.dispose();
  }

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
        child: FadeTransition(
          opacity: _fadeAnim,
          child: SlideTransition(
            position: _slideAnim,
            child: Column(
              children: [
                const Spacer(flex: 2),
                _IllustrationCards(floatAnim: _floatAnim),
                const Spacer(flex: 3),
                _AppBranding(),
                const Spacer(flex: 4),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      _PrimaryButton(
                        label: 'Create an account',
                        onPressed: () => _toSignup(context),
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
                const SizedBox(height: 36),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatefulWidget {
  final String label;
  final VoidCallback onPressed;

  const _PrimaryButton({required this.label, required this.onPressed});

  @override
  State<_PrimaryButton> createState() => _PrimaryButtonState();
}

class _PrimaryButtonState extends State<_PrimaryButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _pressController;
  late Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
      reverseDuration: const Duration(milliseconds: 200),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _pressController.forward(),
      onTapUp: (_) {
        _pressController.reverse();
        widget.onPressed();
      },
      onTapCancel: () => _pressController.reverse(),
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: double.infinity,
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF6C72FF), _kPrimary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(AppRadius.chip),
            ),
          alignment: Alignment.center,
          child: const Text(
            'Create an account',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.white,
              letterSpacing: 0.1,
            ),
          ),
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
              colors: [Color(0xFF7C80F4), Color(0xFF4A4EE0)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            ),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: _StackedCardsIcon(),
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Trackora',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.w600,
            letterSpacing: -1.0,
            color: Color(0xFF111111),
          ),
        ),
        const SizedBox(height: 10),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 44),
          child: Text(
            'A calmer way to see where every ringgit goes — across all your accounts.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              color: AppColors.inkSoft,
              height: 1.55,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ],
    );
  }
}

class _IllustrationCards extends StatelessWidget {
  final Animation<double> floatAnim;

  const _IllustrationCards({required this.floatAnim});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 270,
      child: AnimatedBuilder(
        animation: floatAnim,
        builder: (context, _) {
          final floatY = math.sin(floatAnim.value * math.pi) * 5.0;
          final floatY2 = math.sin((floatAnim.value * math.pi) + 1.0) * 4.5;
          final floatY3 = math.sin((floatAnim.value * math.pi) + 1.8) * 3.5;

          return Stack(
            alignment: Alignment.center,
            children: [
              // Ambient glow blob
              Positioned(
                left: 20,
                top: 20,
                child: Container(
                  width: 240,
                  height: 170,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(120),
                    gradient: RadialGradient(
                      colors: [
                        _kPrimary.withValues(alpha: 0.10),
                        _kPrimary.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Balance card — top-left, tilted back
              Positioned(
                left: 12,
                top: 4,
                child: Transform.translate(
                  offset: Offset(0, -floatY),
                  child: Transform.rotate(
                    angle: -0.07,
                    child: _BalanceCard(),
                  ),
                ),
              ),
              // Donut chart — top-right, lowered and shifted left for visual balance
              Positioned(
                right: 24,
                top: 96,
                child: Transform.translate(
                  offset: Offset(0, -floatY2),
                  child: Transform.rotate(
                    angle: 0.05,
                    child: _ChartCard(),
                  ),
                ),
              ),
              // Food / Lunch transaction card — bottom-center, shifted right for balance
              Positioned(
                left: 52,
                bottom: 6,
                child: Transform.translate(
                  offset: Offset(0, -floatY3),
                  child: Transform.rotate(
                    angle: -0.03,
                    child: _ExpenseTransactionCard(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1,
        ),
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
              letterSpacing: 1.4,
              color: AppColors.inkSoft,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'RM 12,480',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w600,
              color: Color(0xFF111111),
              letterSpacing: -1.0,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF34C759).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.arrow_up_right,
                      size: 9,
                      color: Color(0xFF34C759),
                    ),
                    SizedBox(width: 2),
                    Text(
                      '2.4%',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF34C759),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'this month',
                style: TextStyle(
                  fontSize: 10,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _AccountPill(color: _kPrimary),
              const SizedBox(width: 6),
              _AccountPill(color: const Color(0xFF59C28A)),
              const SizedBox(width: 6),
              _AccountPill(color: const Color(0xFFD4C9F5)),
            ],
          ),
        ],
      ),
    );
  }
}

class _AccountPill extends StatelessWidget {
  final Color color;
  const _AccountPill({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 5,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1,
        ),
        ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _MiniDonutChart(),
          const SizedBox(height: 6),
          Text(
            'SPENDING',
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
              color: AppColors.inkSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpenseTransactionCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 188,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.9),
          width: 1,
        ),
        ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFFD580), Color(0xFFF5A623)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              ),
            child: const Icon(
              CupertinoIcons.cart_fill,
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Food · Lunch',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111111),
                  letterSpacing: -0.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '–RM 24.50',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.inkSoft,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniDonutChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(60, 60),
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
    final outerR = cx - 1;
    final innerR = outerR * 0.54;
    const gapRad = 0.06;

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
        ..lineTo(
            cx + innerR * math.cos(angle + sweep),
            cy + innerR * math.sin(angle + sweep))
        ..arcTo(
          Rect.fromCircle(center: Offset(cx, cy), radius: innerR),
          angle + sweep,
          -sweep,
          false,
        )
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = seg.color
          ..style = PaintingStyle.fill,
      );
      angle += seg.fraction * 2 * math.pi;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter _) => false;
}

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

    // Back card — golden yellow, rotated left
    drawCard(canvas, w * 0.35, h * 0.55, w * 0.72, h * 0.46, -0.35,
        const Color(0xFFFFCB47));

    // Middle card — lavender, slight rotation
    drawCard(canvas, w * 0.55, h * 0.50, w * 0.72, h * 0.46, -0.12,
        const Color(0xFFD4C9F5));

    // Front card — white, slight positive rotation
    drawCard(canvas, w * 0.55, h * 0.52, w * 0.72, h * 0.46, 0.05,
        Colors.white);

    // Front card details — dark strip
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
    canvas.drawRRect(stripRect, Paint()..color = const Color(0xFF1A1A2E));

    canvas.drawCircle(
      Offset(w * 0.18, h * 0.0),
      w * 0.055,
      Paint()..color = const Color(0xFF7C80F4),
    );
    canvas.drawCircle(
      Offset(w * 0.28, h * 0.0),
      w * 0.055,
      Paint()..color = const Color(0xFF7C80F4).withValues(alpha: 0.5),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
