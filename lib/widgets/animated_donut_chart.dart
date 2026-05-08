import 'dart:math';

import 'package:flutter/material.dart';

class DonutSegment {
  final double value;
  final Color color;
  final String? label;

  const DonutSegment({required this.value, required this.color, this.label});
}

/// A donut chart with a smooth clockwise sweep-reveal animation.
///
/// Segments sweep in from 12 o'clock, one flowing into the next.
/// A small gap is drawn between segments for clarity.
class AnimatedDonutChart extends StatefulWidget {
  final List<DonutSegment> segments;
  final double size;
  final double strokeWidth;
  final Widget? centerChild;
  final void Function(int index)? onSegmentTap;
  final Duration duration;
  final bool showLabels;

  const AnimatedDonutChart({
    super.key,
    required this.segments,
    required this.size,
    this.strokeWidth = 36,
    this.centerChild,
    this.onSegmentTap,
    this.duration = const Duration(milliseconds: 820),
    this.showLabels = false,
  });

  @override
  State<AnimatedDonutChart> createState() => _AnimatedDonutChartState();
}

class _AnimatedDonutChartState extends State<AnimatedDonutChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _progress = CurvedAnimation(
      parent: _ctrl,
      curve: Curves.easeInOutCubic,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ctrl.forward();
    });
  }

  @override
  void didUpdateWidget(covariant AnimatedDonutChart old) {
    super.didUpdateWidget(old);
    final oldTotal = old.segments.fold<double>(0, (s, e) => s + e.value);
    final newTotal = widget.segments.fold<double>(0, (s, e) => s + e.value);
    if (oldTotal != newTotal || old.segments.length != widget.segments.length) {
      _ctrl.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int _hitTestSegment(Offset local) {
    final center = Offset(widget.size / 2, widget.size / 2);
    final dx = local.dx - center.dx;
    final dy = local.dy - center.dy;
    final dist = sqrt(dx * dx + dy * dy);
    final outerR = widget.size / 2;
    final innerR = outerR - widget.strokeWidth;
    if (dist < innerR || dist > outerR) return -1;

    final total = widget.segments.fold<double>(0, (s, e) => s + e.value);
    if (total == 0) return -1;

    double angle = atan2(dy, dx) + pi / 2; // normalise: 0 = 12 o'clock
    if (angle < 0) angle += 2 * pi;

    double cumAngle = 0;
    for (var i = 0; i < widget.segments.length; i++) {
      final sweep = (widget.segments[i].value / total) * 2 * pi;
      if (angle >= cumAngle && angle < cumAngle + sweep) return i;
      cumAngle += sweep;
    }
    return -1;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapUp: widget.onSegmentTap == null
          ? null
          : (details) {
              final idx = _hitTestSegment(details.localPosition);
              if (idx >= 0) widget.onSegmentTap!(idx);
            },
      child: AnimatedBuilder(
        animation: _progress,
        builder: (ctx, _) => SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CustomPaint(
                size: Size(widget.size, widget.size),
                painter: _DonutPainter(
                  segments: widget.segments,
                  progress: _progress.value,
                  strokeWidth: widget.strokeWidth,
                  showLabels: widget.showLabels && _progress.value >= 0.95,
                ),
              ),
              if (widget.centerChild != null)
                Opacity(
                  opacity: _progress.value.clamp(0.0, 1.0),
                  child: widget.centerChild,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  final List<DonutSegment> segments;
  final double progress; // 0 → 1
  final double strokeWidth;
  final bool showLabels;

  static const double _gapAngle = 0.025; // radians gap between segments

  _DonutPainter({
    required this.segments,
    required this.progress,
    required this.strokeWidth,
    required this.showLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;
    const startOffset = -pi / 2; // 12 o'clock

    final total = segments.fold<double>(0, (s, e) => s + e.value);
    if (total == 0) return;

    // Total angle to draw this frame (0 → 2π)
    final revealAngle = 2 * pi * progress;
    double cumAngle = 0;

    for (var i = 0; i < segments.length; i++) {
      final seg = segments[i];
      final fullSweep = (seg.value / total) * 2 * pi;
      // How much of this segment to draw given the current reveal angle
      final drawn = (revealAngle - cumAngle).clamp(0.0, fullSweep);
      if (drawn <= 0) {
        cumAngle += fullSweep;
        continue;
      }

      // Apply a tiny gap at the start of each segment (except the first frame)
      final gap = i == 0 ? 0.0 : _gapAngle;
      final sweepToDraw = (drawn - gap).clamp(0.0, fullSweep);
      final segStart = cumAngle + gap;

      if (sweepToDraw > 0) {
        final paint = Paint()
          ..color = seg.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.butt;

        canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          startOffset + segStart,
          sweepToDraw,
          false,
          paint,
        );
      }

      // Percentage label on fully-drawn segments
      if (showLabels && drawn >= fullSweep - 0.01) {
        final pct = seg.value / total;
        if (pct >= 0.08) {
          final midAngle = startOffset + segStart + sweepToDraw / 2;
          final labelR = radius;
          final lx = center.dx + labelR * cos(midAngle);
          final ly = center.dy + labelR * sin(midAngle);
          final tp = TextPainter(
            text: TextSpan(
              text: '${(pct * 100).round()}%',
              style: TextStyle(
                color: _foregroundOn(seg.color),
                fontSize: 9,
                fontWeight: FontWeight.w800,
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(
            canvas,
            Offset(lx - tp.width / 2, ly - tp.height / 2),
          );
        }
      }

      cumAngle += fullSweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) =>
      old.progress != progress || old.showLabels != showLabels;
}

Color _foregroundOn(Color bg) {
  final lum = bg.computeLuminance();
  return lum > 0.35 ? const Color(0xFF1A1A2E) : Colors.white;
}
