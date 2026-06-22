import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/i18n.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

class GroupPendingScreen extends ConsumerStatefulWidget {
  final String rawCode;
  final DateTime expiresAt;
  final String? partnerInitial;

  const GroupPendingScreen({
    super.key,
    required this.rawCode,
    required this.expiresAt,
    this.partnerInitial,
  });

  @override
  ConsumerState<GroupPendingScreen> createState() =>
      _GroupPendingScreenState();
}

class _GroupPendingScreenState extends ConsumerState<GroupPendingScreen>
    with TickerProviderStateMixin {
  Timer? _timer;
  late AnimationController _spinCtrl;
  late AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _spinCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _spinCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  String _timeRemaining() {
    final diff = widget.expiresAt.difference(DateTime.now());
    if (diff.isNegative) return context.t('group.expired');
    final m = diff.inMinutes;
    final s = diff.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  String get _displayCode =>
      '${widget.rawCode.substring(0, 3)}·${widget.rawCode.substring(3)}';

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: _displayCode));
    AppToast.show(context, context.t('group.codeCopied'));
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final user = ref.watch(authStateProvider).valueOrNull;
    final myInitial =
        (user?.email?.substring(0, 1) ?? 'Y').toUpperCase();
    final timeStr = _timeRemaining();

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.chevron_back,
              color: Color(0xFF0B0B0F),
              size: 18,
            ),
          ),
        ),
        title: Text(
          context.t('group.invitePartnerTitle'),
          style: TextStyle(
            color: brand.ink,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Avatar pair with animation
              SizedBox(
                height: 120,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // My avatar with dashed spinning ring
                    SizedBox(
                      width: 100,
                      height: 100,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedBuilder(
                            animation: _spinCtrl,
                            builder: (_, child) => Transform.rotate(
                              angle: _spinCtrl.value * 2 * math.pi,
                              child: CustomPaint(
                                size: const Size(100, 100),
                                painter: _DashedCirclePainter(
                                  color: const Color(0xFF9F8DDB),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: 76,
                            height: 76,
                            decoration: const BoxDecoration(
                              color: Color(0xFFEAE3F8),
                              shape: BoxShape.circle,
                            ),
                            child: Center(
                              child: Text(
                                myInitial,
                                style: const TextStyle(
                                  color: Color(0xFF5A4AAB),
                                  fontSize: 30,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 12),

                    // 3 pulsing dots
                    AnimatedBuilder(
                      animation: _pulseCtrl,
                      builder: (_, child) {
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (int i = 0; i < 3; i++) ...[
                              if (i > 0) const SizedBox(height: 6),
                              Opacity(
                                opacity: 0.4 +
                                    0.6 *
                                        ((i == 1
                                                ? _pulseCtrl.value
                                                : i == 0
                                                    ? (1 - _pulseCtrl.value)
                                                    : _pulseCtrl.value) *
                                            0.5 +
                                            0.5),
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF9F8DDB),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        );
                      },
                    ),

                    const SizedBox(width: 12),

                    // Empty partner avatar placeholder
                    Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: const Color(0xFFC9C9CF),
                          width: 2,
                          strokeAlign: BorderSide.strokeAlignCenter,
                        ),
                      ),
                      child: CustomPaint(
                        painter: _DashedCirclePainter(
                          color: const Color(0xFFC9C9CF),
                          isDashed: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Title
              Text(
                context.t('group.pendingWaiting'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: brand.ink,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                ),
              ),

              const SizedBox(height: 10),

              Text(
                context.t('group.pendingShareDesc'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: const Color(0xFF5B5B66),
                  fontSize: 15,
                  height: 1.5,
                ),
              ),

              const SizedBox(height: 28),

              // Compact code card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.t('group.yourCode'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: brand.inkSoft,
                              letterSpacing: 0.6,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _displayCode,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'monospace',
                              color: brand.ink,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    CupertinoButton(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      color: const Color(0xFF1A6CFF),
                      borderRadius: BorderRadius.circular(12),
                      onPressed: _copyCode,
                      child: Text(
                        context.t('group.shareAgain'),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Expiry chip
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFBE5C9),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      CupertinoIcons.clock_fill,
                      size: 12,
                      color: Color(0xFFF0A33A),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      context.t('group.inviteExpiry').replaceAll('{time}', timeStr),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFFF0A33A),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

              // Cancel invite button
              SizedBox(
                width: double.infinity,
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: brand.divider,
                        width: 1,
                      ),
                    ),
                    child: Center(
                      child: Text(
                        context.t('group.cancelInvite'),
                        style: TextStyle(
                          color: brand.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Dashed circle painter ────────────────────────────────────────────────────

class _DashedCirclePainter extends CustomPainter {
  final Color color;
  final bool isDashed;

  const _DashedCirclePainter({required this.color, this.isDashed = false});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = isDashed ? 2 : 2.5
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 2;

    if (isDashed) {
      const dashCount = 16;
      const gapFraction = 0.4;
      final sweepAngle = (2 * math.pi) / dashCount;
      final dashAngle = sweepAngle * (1 - gapFraction);
      for (int i = 0; i < dashCount; i++) {
        final startAngle = i * sweepAngle;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startAngle,
          dashAngle,
          false,
          paint,
        );
      }
    } else {
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCirclePainter oldDelegate) => false;
}
