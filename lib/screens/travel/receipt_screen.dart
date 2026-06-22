import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../models/travel_expense.dart';
import '../../models/travel_group.dart';
import '../../services/travel_group_service.dart';
import '../../state/providers.dart';
import '../../widgets/app_toast.dart';

// ── Design tokens ─────────────────────────────────────────────────────────────
const _paper = Color(0xFFFFFFFF);
const _paperEdge = Color(0xFFE5E5EA);
const _blue = Color(0xFF0055BB);
const _inkColor = Color(0xFF1A1614);
const _inkDark = Color(0xFFF2F2F4);
const _ink60 = Color(0xFF6B6259);
const _green = Color(0xFF2A8C52);
const _red = Color(0xFFCC2B22);
const _kReceiptW = 300.0;

/// Ink for screen chrome (nav, title) resolved for the current brightness.
/// The receipt card itself is always white paper, so its text keeps [_inkColor].
Color _chromeInk(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? _inkDark : _inkColor;

// ── Screen ─────────────────────────────────────────────────────────────────────

class ReceiptScreen extends ConsumerStatefulWidget {
  final TravelGroup group;
  final TravelGroupMember member;
  final MemberBalance balance;
  final List<SettlementTransaction> allTransactions;
  final List<TravelExpense> expenses;

  const ReceiptScreen({
    super.key,
    required this.group,
    required this.member,
    required this.balance,
    required this.allTransactions,
    required this.expenses,
  });

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen> {
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
      debugPrint('[TravelReceipt] share failed (${e.runtimeType}): $e\n$st');
      if (!mounted) return;
      // Show actual error so we know what is failing
      AppToast.show(
        context,
        '${e.runtimeType}: $e',
        type: AppToastType.error,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  Future<void> _shareImageReceipt(Rect shareOrigin) async {
    // Wait 3 frames to ensure the RepaintBoundary layer is fully composited
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;

    final boundary = _receiptKey.currentContext?.findRenderObject()
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
          'trackora_receipt_${DateTime.now().millisecondsSinceEpoch}.png';

      final tempDir = await getTemporaryDirectory();
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);

      if (!mounted) return;
      final result = await Share.shareXFiles(
        [XFile(file.path, mimeType: 'image/png')],
        subject: _receiptSubject,
        sharePositionOrigin: shareOrigin,
      );
      debugPrint('[TravelReceipt] share result: ${result.status}');
    } finally {
      img?.dispose();
    }
  }

  String get _receiptSubject =>
      '${widget.member.name}\'s receipt - ${widget.group.name}';

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
    final bg = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

    // Multiplier from the trip currency to the user's main currency, used to
    // show estimated values when the trip currency differs from it.
    final converter = ref.watch(currencyConverterProvider).valueOrNull;
    final mainCode = converter?.base;
    double? fxToMain;
    if (converter != null && mainCode != null && mainCode != widget.group.currency) {
      final one = converter.toBase(1.0, widget.group.currency);
      if (one > 0) fxToMain = one;
    }

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ── Nav ──────────────────────────────────────────────────────────
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              child: Row(
                children: [
                  _NavBtn(
                    onTap: () => Navigator.pop(context),
                    child: Icon(
                      CupertinoIcons.back,
                      size: 18,
                      color: _chromeInk(context),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Receipt',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: _chromeInk(context),
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 36), // balance the back button
                ],
              ),
            ),
          ),

          // ── Receipt ───────────────────────────────────────────────────────
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
                        child: _ReceiptCard(
                          group: widget.group,
                          member: widget.member,
                          balance: widget.balance,
                          allTransactions: widget.allTransactions,
                          expenses: widget.expenses,
                          mainCode: fxToMain != null ? mainCode : null,
                          fxToMain: fxToMain,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Share button ──────────────────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                key: _shareButtonKey,
                width: double.infinity,
                child: CupertinoButton(
                  color: _blue,
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

// ── Receipt card ───────────────────────────────────────────────────────────────

class _ReceiptCard extends StatelessWidget {
  final TravelGroup group;
  final TravelGroupMember member;
  final MemberBalance balance;
  final List<SettlementTransaction> allTransactions;
  final List<TravelExpense> expenses;
  // When the trip currency differs from the user's main currency, [fxToMain]
  // is the multiplier (main = group × fxToMain) and [mainCode] the main code.
  final String? mainCode;
  final double? fxToMain;

  const _ReceiptCard({
    required this.group,
    required this.member,
    required this.balance,
    required this.allTransactions,
    required this.expenses,
    this.mainCode,
    this.fxToMain,
  });

  // Returns the "~ Est. <main> <amount>" tail for an amount in the trip's
  // currency, or null when the trip is already in the user's main currency.
  String? _mainEst(double amountInGroupCurrency, NumberFormat fmt) {
    final fx = fxToMain;
    final code = mainCode;
    if (fx == null || code == null) return null;
    return '~ Est. $code ${fmt.format(amountInGroupCurrency * fx)}';
  }

  @override
  Widget build(BuildContext context) {
    final fmt = NumberFormat('#,##0.00');
    final paidExpenses = expenses
        .where((e) => e.paidByMemberId == member.id)
        .toList();
    final memberTxns = allTransactions
        .where((t) => t.fromMemberId == member.id || t.toMemberId == member.id)
        .toList();
    final isPositive = balance.net >= 0;

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
          // ── Header ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.airplane, size: 12, color: _blue),
                    const SizedBox(width: 4),
                    const Text(
                      'TRACKORA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3.5,
                        color: _blue,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Travel Expense Receipt',
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

          // ── Trip info ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            child: Column(
              children: [
                _InfoRow('TRIP', group.name),
                const SizedBox(height: 4),
                _InfoRow('DATES', _dateRange()),
                const SizedBox(height: 4),
                _InfoRow('CURRENCY', group.currency),
              ],
            ),
          ),
          _DottedRule(),

          // ── Bill to ─────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _blue.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      member.name.isNotEmpty
                          ? member.name[0].toUpperCase()
                          : '?',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: _blue,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BILL TO',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.2,
                        color: _ink60,
                      ),
                    ),
                    Text(
                      member.name,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: _inkColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Expenses paid ───────────────────────────────────────────────
          if (paidExpenses.isNotEmpty) ...[
            _DottedRule(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 2),
              child: Row(
                children: [
                  const Text(
                    'EXPENSES PAID',
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.2,
                      color: _ink60,
                    ),
                  ),
                ],
              ),
            ),
            ...paidExpenses.map(
              (e) {
                final isForeign = e.currencyCode != null &&
                    e.currencyCode != group.currency;
                final expenseCurrency = e.currencyCode ?? group.currency;
                final convertedAmt = e.amountInGroupCurrency;
                return Padding(
                  padding: const EdgeInsets.fromLTRB(24, 3, 24, 3),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          e.description.isNotEmpty ? e.description : e.category,
                          style: const TextStyle(fontSize: 12, color: _inkColor),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '$expenseCurrency ${fmt.format(e.amount)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _inkColor,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (isForeign)
                            Text(
                              '~ Est. ${group.currency} ${fmt.format(convertedAmt)}',
                              style: const TextStyle(
                                fontSize: 9,
                                color: _ink60,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          if (_mainEst(convertedAmt, fmt) != null)
                            Text(
                              _mainEst(convertedAmt, fmt)!,
                              style: const TextStyle(
                                fontSize: 9,
                                color: _ink60,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 5, 24, 9),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'TOTAL PAID',
                      style: TextStyle(
                        fontSize: 7,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: _ink60,
                      ),
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${group.currency} ${fmt.format(balance.totalPaid)}',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: _inkColor,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                      if (_mainEst(balance.totalPaid, fmt) != null)
                        Text(
                          _mainEst(balance.totalPaid, fmt)!,
                          style: const TextStyle(
                            fontSize: 9,
                            color: _ink60,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],

          // ── Balance ─────────────────────────────────────────────────────
          _DottedRule(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
            child: Column(
              children: [
                _AmountRow(
                  label: 'YOUR SHARE',
                  value: '${group.currency} ${fmt.format(balance.totalShare)}',
                  color: _inkColor,
                  sub: _mainEst(balance.totalShare, fmt),
                ),
                const SizedBox(height: 5),
                _AmountRow(
                  label: isPositive ? "YOU'RE OWED" : 'YOU OWE',
                  value:
                      '${isPositive ? '+' : '−'}${group.currency} ${fmt.format(balance.net.abs())}',
                  color: isPositive ? _green : _red,
                  large: true,
                  sub: _mainEst(balance.net.abs(), fmt),
                ),
              ],
            ),
          ),

          // ── Settlement instructions ──────────────────────────────────────
          if (memberTxns.isNotEmpty) ...[
            _DottedRule(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 2),
              child: const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'TO SETTLE',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: _ink60,
                  ),
                ),
              ),
            ),
            ...memberTxns.map((tx) {
              final owing = tx.fromMemberId == member.id;
              final other = owing ? tx.toMemberName : tx.fromMemberName;
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 3, 24, 3),
                child: Row(
                  children: [
                    Icon(
                      owing
                          ? CupertinoIcons.arrow_right
                          : CupertinoIcons.arrow_left,
                      size: 10,
                      color: owing ? _red : _green,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Text(
                        owing ? 'Pay $other' : 'Receive from $other',
                        style: TextStyle(
                          fontSize: 11,
                          color: owing ? _red : _green,
                        ),
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${group.currency} ${fmt.format(tx.amount)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: owing ? _red : _green,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        if (_mainEst(tx.amount, fmt) != null)
                          Text(
                            _mainEst(tx.amount, fmt)!,
                            style: const TextStyle(
                              fontSize: 8,
                              color: _ink60,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
          ],

          // ── Footer ──────────────────────────────────────────────────────
          _DottedRule(),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
            child: Column(
              children: [
                Text(
                  '✈  Generated by Trackora',
                  style: TextStyle(
                    fontSize: 9,
                    color: _ink60,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  DateFormat('yyyy-MM-dd  HH:mm').format(DateTime.now()),
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

  String _dateRange() {
    final fmt = DateFormat('MMM d, yyyy');
    final s = fmt.format(group.startDate);
    if (group.endDate == null) return s;
    return '$s – ${fmt.format(group.endDate!)}';
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

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
    const dash = 4.0, gap = 3.0;
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
  bool shouldRepaint(covariant CustomPainter _) => false;
}

class _InfoRow extends StatelessWidget {
  final String label, value;
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
            color: _inkColor,
          ),
        ),
      ),
    ],
  );
}

class _AmountRow extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool large;
  final String? sub;
  const _AmountRow({
    required this.label,
    required this.value,
    required this.color,
    this.large = false,
    this.sub,
  });

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Expanded(
        child: Padding(
          padding: const EdgeInsets.only(top: 2),
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
      ),
      Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: large ? 15 : 12,
              fontWeight: large ? FontWeight.w800 : FontWeight.w600,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (sub != null)
            Text(
              sub!,
              style: const TextStyle(
                fontSize: 9,
                color: _ink60,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
        ],
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
              : _inkColor.withValues(alpha: 0.06),
          shape: BoxShape.circle,
        ),
        child: Center(child: child),
      ),
    );
  }
}
