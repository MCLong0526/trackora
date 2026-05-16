import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/split_bill.dart';
import '../../widgets/app_toast.dart';

const _paper = Color(0xFFF5F0E8);
const _paperEdge = Color(0xFFE8E0D0);
const _purple = Color(0xFF6B40A8);
const _ink = Color(0xFF1A1614);
const _ink60 = Color(0xFF6B6259);
const _green = Color(0xFF2A8C52);
const _kReceiptW = 320.0;

class BillReceiptScreen extends StatefulWidget {
  final SplitBill bill;

  const BillReceiptScreen({super.key, required this.bill});

  @override
  State<BillReceiptScreen> createState() => _BillReceiptScreenState();
}

class _BillReceiptScreenState extends State<BillReceiptScreen> {
  final _receiptKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  bool _sharing = false;

  Future<void> _share() async {
    if (_sharing) return;
    final shareOrigin = _sharePositionOrigin();
    setState(() => _sharing = true);
    try {
      await _shareImageReceipt(shareOrigin);
    } catch (e, st) {
      debugPrint('[BillReceipt] share failed (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      AppToast.show(context, '$e', type: AppToastType.error);
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareImageReceipt(Rect shareOrigin) async {
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final boundary =
        _receiptKey.currentContext?.findRenderObject()
            as RenderRepaintBoundary?;
    if (boundary == null) throw StateError('RepaintBoundary not found');

    ui.Image? img;
    try {
      img = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await img.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw StateError('PNG encoding returned null');

      final bytes = byteData.buffer.asUint8List(
        byteData.offsetInBytes,
        byteData.lengthInBytes,
      );
      final fileName =
          'trackora_split_bill_${DateTime.now().millisecondsSinceEpoch}.png';
      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: '${widget.bill.title} receipt',
        sharePositionOrigin: shareOrigin,
      );
    } finally {
      img?.dispose();
    }
  }

  Rect _sharePositionOrigin() {
    final buttonBox =
        _shareButtonKey.currentContext?.findRenderObject() as RenderBox?;
    if (buttonBox != null && buttonBox.hasSize && !buttonBox.size.isEmpty) {
      return buttonBox.localToGlobal(Offset.zero) & buttonBox.size;
    }

    final size = MediaQuery.of(context).size;
    return Rect.fromLTWH(size.width / 2, size.height / 2, 1, 1);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE8E3DA);

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  _NavBtn(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(
                      CupertinoIcons.back,
                      size: 18,
                      color: _ink,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Receipt',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: _ink,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 36),
                ],
              ),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: RepaintBoundary(
                        key: _receiptKey,
                        child: _ReceiptCard(bill: widget.bill),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                key: _shareButtonKey,
                width: double.infinity,
                child: CupertinoButton(
                  color: _purple,
                  borderRadius: BorderRadius.circular(9999),
                  onPressed: _sharing ? null : _share,
                  child: _sharing
                      ? const CupertinoActivityIndicator(color: Colors.white)
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              CupertinoIcons.share,
                              color: Colors.white,
                              size: 16,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Share Receipt',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final SplitBill bill;

  const _ReceiptCard({required this.bill});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy').format(bill.date);
    final generatedAt = DateFormat('yyyy-MM-dd  HH:mm').format(DateTime.now());
    final splitLabel =
        '${bill.splitMode.name[0].toUpperCase()}${bill.splitMode.name.substring(1)}';
    final payer = bill.payer;

    return Container(
      width: _kReceiptW,
      decoration: BoxDecoration(
        color: _paper,
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x28000000),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
          BoxShadow(
            color: Color(0x12000000),
            blurRadius: 40,
            offset: Offset(0, 20),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      CupertinoIcons.person_2_fill,
                      size: 12,
                      color: _purple,
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'TRACKORA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3.5,
                        color: _purple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Split Bill Receipt',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: _ink60,
                  ),
                ),
              ],
            ),
          ),
          _DottedRule(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            child: Column(
              children: [
                _InfoRow('BILL', bill.billNumber),
                const SizedBox(height: 4),
                _InfoRow('DATE', dateStr),
                const SizedBox(height: 4),
                _InfoRow('SPLIT', splitLabel),
              ],
            ),
          ),
          _DottedRule(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _purple.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      payer.initials,
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: _purple,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'PAID BY',
                        style: TextStyle(
                          fontSize: 7,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.2,
                          color: _ink60,
                        ),
                      ),
                      Text(
                        payer.name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: _ink,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _DottedRule(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Column(
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    bill.title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: _ink,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                _AmountRow(
                  label: 'BILL TOTAL',
                  value:
                      '${bill.currencySymbol} ${bill.totalAmount.toStringAsFixed(2)}',
                  color: _ink,
                ),
                const SizedBox(height: 5),
                _AmountRow(
                  label: 'OUTSTANDING',
                  value:
                      '${bill.currencySymbol} ${bill.outstanding.toStringAsFixed(2)}',
                  color: _green,
                  large: true,
                ),
              ],
            ),
          ),
          _DottedRule(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 2),
            child: const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'SPLIT BETWEEN',
                style: TextStyle(
                  fontSize: 7,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                  color: _ink60,
                ),
              ),
            ),
          ),
          ...bill.members.map(
            (member) => Padding(
              padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: member.isPayer
                          ? _purple.withValues(alpha: 0.12)
                          : _ink.withValues(alpha: 0.08),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        member.initials,
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: member.isPayer ? _purple : _ink60,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      member.isPayer ? '${member.name} (paid)' : member.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: _ink),
                    ),
                  ),
                  Text(
                    '${bill.currencySymbol} ${member.amount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          _DottedRule(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
            child: Column(
              children: [
                Text(
                  'Generated by Trackora',
                  style: TextStyle(
                    fontSize: 9,
                    color: _ink60,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  generatedAt,
                  style: TextStyle(
                    fontSize: 8,
                    color: _ink60,
                    letterSpacing: 0.3,
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

class _DottedRule extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 24),
    child: CustomPaint(
      size: const Size(double.infinity, 6),
      painter: _DottedRulePainter(),
    ),
  );
}

class _DottedRulePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _paperEdge
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    const dash = 4.0;
    const gap = 3.0;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(
        Offset(x, size.height / 2),
        Offset(math.min(x + dash, size.width), size.height / 2),
        paint,
      );
      x += dash + gap;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow(this.label, this.value);

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        width: 60,
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 7,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: _ink60,
          ),
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: _ink,
          ),
        ),
      ),
    ],
  );
}

class _AmountRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool large;

  const _AmountRow({
    required this.label,
    required this.value,
    required this.color,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 7,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: _ink60,
          ),
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: large ? 15 : 12,
          fontWeight: large ? FontWeight.w800 : FontWeight.w600,
          color: color,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    ],
  );
}

class _NavBtn extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;

  const _NavBtn({required this.child, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : _ink.withValues(alpha: 0.06),
          shape: BoxShape.circle,
        ),
        child: Center(child: child),
      ),
    );
  }
}
