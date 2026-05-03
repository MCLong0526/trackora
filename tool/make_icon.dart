// Generates Trackora app icons.
// Run: dart run tool/make_icon.dart
//
// Produces:
//   assets/icon/app_icon.png            (1024×1024, full background — used for iOS)
//   assets/icon/app_icon_foreground.png (1024×1024, transparent — Android adaptive)
//
// Then run: dart run flutter_launcher_icons

import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

void main() async {
  await Directory('assets/icon').create(recursive: true);

  // Full icon (mint background + dark "T" chart symbol)
  final full = img.Image(width: 1024, height: 1024);
  // mint background #CFEFE2
  img.fill(full, color: img.ColorRgb8(0xCF, 0xEF, 0xE2));
  _drawLogo(full, withBackground: false);
  await File('assets/icon/app_icon.png').writeAsBytes(img.encodePng(full));

  // Foreground only (transparent background) for Android adaptive
  final fg = img.Image(width: 1024, height: 1024, numChannels: 4);
  // start transparent
  for (final p in fg) {
    p.r = 0;
    p.g = 0;
    p.b = 0;
    p.a = 0;
  }
  _drawLogo(fg, withBackground: false, scale: 0.65);
  await File('assets/icon/app_icon_foreground.png')
      .writeAsBytes(img.encodePng(fg));

  // ignore: avoid_print
  print('✓ Icons generated in assets/icon/');
}

/// Draws a stylized "T" with three rising chart bars below the crossbar —
/// reads as Trackora at any size.
void _drawLogo(img.Image canvas, {bool withBackground = true, double scale = 0.78}) {
  final w = canvas.width;
  final h = canvas.height;
  final cx = w ~/ 2;
  final cy = h ~/ 2;
  final size = (math.min(w, h) * scale).toInt();

  final ink = img.ColorRgb8(0x11, 0x11, 0x11);
  final accent = img.ColorRgb8(0x59, 0xC2, 0x8A);

  // T crossbar
  final crossW = (size * 0.78).toInt();
  final crossH = (size * 0.16).toInt();
  final crossL = cx - crossW ~/ 2;
  final crossT = cy - (size * 0.36).toInt();
  _roundedRect(canvas, crossL, crossT, crossW, crossH, crossH ~/ 2, ink);

  // T stem
  final stemW = (size * 0.16).toInt();
  final stemH = (size * 0.42).toInt();
  final stemL = cx - stemW ~/ 2;
  final stemT = crossT;
  _roundedRect(canvas, stemL, stemT, stemW, stemH, stemW ~/ 2, ink);

  // 3 chart bars below — left low, mid medium, right tall (accent)
  final barW = (size * 0.13).toInt();
  final gap = (size * 0.05).toInt();
  final maxBarH = (size * 0.32).toInt();
  final baseY = cy + (size * 0.30).toInt();
  final groupW = barW * 3 + gap * 2;
  final startX = cx - groupW ~/ 2;

  final heights = [
    (maxBarH * 0.45).toInt(),
    (maxBarH * 0.70).toInt(),
    maxBarH,
  ];
  for (var i = 0; i < 3; i++) {
    final x = startX + i * (barW + gap);
    final y = baseY - heights[i];
    final c = i == 2 ? accent : ink;
    _roundedRect(canvas, x, y, barW, heights[i], barW ~/ 2, c);
  }
}

/// Filled rounded rectangle.
void _roundedRect(
  img.Image canvas,
  int x,
  int y,
  int w,
  int h,
  int r,
  img.Color color,
) {
  final right = x + w;
  final bottom = y + h;
  final rr = math.min(r, math.min(w ~/ 2, h ~/ 2));

  for (var py = y; py < bottom; py++) {
    for (var px = x; px < right; px++) {
      // corner check
      bool inside = true;
      if (px < x + rr && py < y + rr) {
        final dx = x + rr - px;
        final dy = y + rr - py;
        inside = dx * dx + dy * dy <= rr * rr;
      } else if (px >= right - rr && py < y + rr) {
        final dx = px - (right - rr - 1);
        final dy = y + rr - py;
        inside = dx * dx + dy * dy <= rr * rr;
      } else if (px < x + rr && py >= bottom - rr) {
        final dx = x + rr - px;
        final dy = py - (bottom - rr - 1);
        inside = dx * dx + dy * dy <= rr * rr;
      } else if (px >= right - rr && py >= bottom - rr) {
        final dx = px - (right - rr - 1);
        final dy = py - (bottom - rr - 1);
        inside = dx * dx + dy * dy <= rr * rr;
      }
      if (inside) {
        canvas.setPixel(px, py, color);
      }
    }
  }
}
