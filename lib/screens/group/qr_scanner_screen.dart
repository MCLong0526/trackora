import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../services/i18n.dart';
import '../../theme/app_theme.dart';

class QRScannerScreen extends StatefulWidget {
  const QRScannerScreen({super.key});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  late final MobileScannerController _controller;
  bool _scanned = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final barcode = capture.barcodes.firstOrNull;
    if (barcode == null) return;
    final raw = barcode.rawValue;
    if (raw == null || raw.isEmpty) return;

    // Extract 6-char alphanumeric code — handle both plain "ABC123" and
    // any URL/deep-link format that ends with the code.
    final cleaned = raw
        .toUpperCase()
        .replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final code = cleaned.length >= 6
        ? cleaned.substring(cleaned.length - 6)
        : cleaned;

    if (code.length == 6) {
      _scanned = true;
      Navigator.pop(context, code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            width: 38,
            height: 38,
            decoration: const BoxDecoration(
              color: Color(0xFF1C1C1E),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              CupertinoIcons.chevron_back,
              color: Colors.white,
              size: 18,
            ),
          ),
        ),
        title: Text(
          context.t('group.scanQrTitle'),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => _controller.toggleTorch(),
            icon: const Icon(
              CupertinoIcons.bolt_fill,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          // Camera feed
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // Overlay with cutout
          _ScanOverlay(brand: brand),

          // Hint text
          Positioned(
            bottom: 80,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  context.t('group.scanQrHint'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  context.t('group.scanQrAuto'),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.55),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScanOverlay extends StatelessWidget {
  final BrandColors brand;
  const _ScanOverlay({required this.brand});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const cutoutSize = 240.0;
    final cutoutTop = (size.height - cutoutSize) / 2.5;

    return CustomPaint(
      size: size,
      painter: _OverlayPainter(
        cutoutRect: Rect.fromCenter(
          center: Offset(size.width / 2, cutoutTop + cutoutSize / 2),
          width: cutoutSize,
          height: cutoutSize,
        ),
        cornerColor: const Color(0xFF1A6CFF),
      ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final Rect cutoutRect;
  final Color cornerColor;

  const _OverlayPainter({
    required this.cutoutRect,
    required this.cornerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Semi-transparent overlay
    final shadowPaint = Paint()..color = Colors.black.withValues(alpha: 0.6);
    final fullRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()
      ..addRect(fullRect)
      ..addRRect(RRect.fromRectAndRadius(cutoutRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, shadowPaint);

    // Corner brackets
    const cornerLen = 24.0;
    const cornerWidth = 3.0;
    final cornerPaint = Paint()
      ..color = cornerColor
      ..strokeWidth = cornerWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final l = cutoutRect.left;
    final r = cutoutRect.right;
    final t = cutoutRect.top;
    final b = cutoutRect.bottom;
    const rad = 16.0;

    // Top-left
    canvas.drawLine(Offset(l + rad, t), Offset(l + rad + cornerLen, t), cornerPaint);
    canvas.drawLine(Offset(l, t + rad), Offset(l, t + rad + cornerLen), cornerPaint);
    // Top-right
    canvas.drawLine(Offset(r - rad - cornerLen, t), Offset(r - rad, t), cornerPaint);
    canvas.drawLine(Offset(r, t + rad), Offset(r, t + rad + cornerLen), cornerPaint);
    // Bottom-left
    canvas.drawLine(Offset(l + rad, b), Offset(l + rad + cornerLen, b), cornerPaint);
    canvas.drawLine(Offset(l, b - rad - cornerLen), Offset(l, b - rad), cornerPaint);
    // Bottom-right
    canvas.drawLine(Offset(r - rad - cornerLen, b), Offset(r - rad, b), cornerPaint);
    canvas.drawLine(Offset(r, b - rad - cornerLen), Offset(r, b - rad), cornerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
