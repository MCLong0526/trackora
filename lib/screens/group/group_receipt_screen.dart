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

import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

// ── Constants matching BillReceiptScreen style ───────────────────────────────
const _kPaper = Colors.white;
const _kPaperEdge = Color(0xFFE0E0E0);
const _kPurple = Color(0xFF5A4AAB);
const _kInk = Color(0xFF1A1614);
const _kInk60 = Color(0xFF6B6259);
const _kGreen = Color(0xFF1FBE71);
const _kAmber = Color(0xFFF0A33A);
const _kReceiptW = 320.0;

enum GroupReceiptPeriod { day, month }

class GroupReceiptScreen extends ConsumerStatefulWidget {
  final ExpenseGroup group;
  final GroupReceiptPeriod period;
  final DateTime? selectedDate;

  const GroupReceiptScreen({
    super.key,
    required this.group,
    this.period = GroupReceiptPeriod.month,
    this.selectedDate,
  });

  @override
  ConsumerState<GroupReceiptScreen> createState() =>
      _GroupReceiptScreenState();
}

class _GroupReceiptScreenState extends ConsumerState<GroupReceiptScreen> {
  final _shareButtonKey = GlobalKey();
  final _receiptKey = GlobalKey();
  bool _sharing = false;

  DateTime get _date => widget.selectedDate ?? DateTime.now();
  bool get _isDaily => widget.period == GroupReceiptPeriod.day;

  String get _periodLabel => _isDaily
      ? DateFormat('d MMM yyyy').format(_date)
      : DateFormat('MMMM yyyy').format(_date);

  List<GroupExpenseItem> _filter(List<GroupExpenseItem> all) {
    return all
        .where((e) {
          if (_isDaily) {
            return e.date.year == _date.year &&
                e.date.month == _date.month &&
                e.date.day == _date.day;
          }
          return e.date.year == _date.year && e.date.month == _date.month;
        })
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _share() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      final boundary =
          _receiptKey.currentContext?.findRenderObject()
              as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Receipt not ready');
      ui.Image? img;
      try {
        img = await boundary.toImage(pixelRatio: 3.0);
        final byteData =
            await img.toByteData(format: ui.ImageByteFormat.png);
        if (byteData == null) throw StateError('PNG encode failed');
        final bytes = byteData.buffer.asUint8List(
          byteData.offsetInBytes,
          byteData.lengthInBytes,
        );
        final fileName =
            'trackora_group_receipt_${DateTime.now().millisecondsSinceEpoch}.png';
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$fileName');
        await file.writeAsBytes(bytes, flush: true);
        if (!mounted) return;
        // Share origin for iPad popover
        final box = _shareButtonKey.currentContext?.findRenderObject()
            as RenderBox?;
        final origin = box != null && box.hasSize
            ? box.localToGlobal(Offset.zero) & box.size
            : Rect.fromLTWH(
                MediaQuery.of(context).size.width / 2,
                MediaQuery.of(context).size.height / 2,
                1,
                1,
              );
        await Share.shareXFiles(
          [XFile(file.path, mimeType: 'image/png')],
          subject: 'Group receipt – $_periodLabel',
          sharePositionOrigin: origin,
        );
      } finally {
        img?.dispose();
      }
    } catch (e) {
      if (mounted) AppToast.show(context, 'Could not share receipt: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = context.brand.background;
    final userId = ref.watch(authStateProvider).valueOrNull?.uid;
    final userName = ref.watch(userNameProvider);
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '';
    final expensesAsync = ref.watch(groupExpensesProvider(widget.group.id));
    final allExpenses = expensesAsync.valueOrNull ?? const [];
    final filtered = _filter(allExpenses);
    final service = ref.read(expenseGroupServiceProvider);
    final balances =
        service.computeBalances(widget.group.members, filtered);
    final myBalance = balances.cast<dynamic>().firstWhere(
          (b) => b.uid == userId,
          orElse: () => null,
        );
    final myNet = myBalance?.net as double? ?? 0;
    final partner =
        widget.group.members.where((m) => m.uid != userId).firstOrNull;
    final partnerName = partner?.displayName ?? 'Partner';

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ── App bar ──────────────────────────────────────────
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
                      color: _kInk,
                    ),
                  ),
                  const Spacer(),
                  const Text(
                    'Receipt',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: _kInk,
                    ),
                  ),
                  const Spacer(),
                  const SizedBox(width: 36),
                ],
              ),
            ),
          ),

          // ── Receipt card (centered, scrollable) ──────────────
          Expanded(
            child: LayoutBuilder(
              builder: (ctx, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                      child: RepaintBoundary(
                        key: _receiptKey,
                        child: _GroupReceiptCard(
                          group: widget.group,
                          filtered: filtered,
                          symbol: symbol,
                          periodLabel: _periodLabel,
                          isDaily: _isDaily,
                          myNet: myNet,
                          partnerName: partnerName,
                          userId: userId,
                          userName: userName,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Share button ──────────────────────────────────────
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: SizedBox(
                key: _shareButtonKey,
                width: double.infinity,
                child: CupertinoButton(
                  color: _kPurple,
                  borderRadius: BorderRadius.circular(9999),
                  onPressed: _sharing ? null : _share,
                  child: _sharing
                      ? const CupertinoActivityIndicator(
                          color: Colors.white,
                        )
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

// ── Thermal receipt card ─────────────────────────────────────────────────────

class _GroupReceiptCard extends StatelessWidget {
  final ExpenseGroup group;
  final List<GroupExpenseItem> filtered;
  final String symbol;
  final String periodLabel;
  final bool isDaily;
  final double myNet;
  final String partnerName;
  final String? userId;
  final String userName;

  const _GroupReceiptCard({
    required this.group,
    required this.filtered,
    required this.symbol,
    required this.periodLabel,
    required this.isDaily,
    required this.myNet,
    required this.partnerName,
    required this.userId,
    this.userName = '',
  });

  String _memberName(String uid) {
    if (uid == userId) {
      final displayName = group.members
          .where((m) => m.uid == uid)
          .firstOrNull
          ?.displayName ?? '';
      if (userName.isNotEmpty) return userName;
      if (displayName.isNotEmpty) return displayName;
      return 'You';
    }
    try {
      return group.members.firstWhere((m) => m.uid == uid).displayName;
    } catch (_) {
      return 'Partner';
    }
  }

  String _memberInitials(String uid) {
    final name = uid == userId
        ? group.members.where((m) => m.uid == uid).firstOrNull?.displayName ??
            'Y'
        : group.members.where((m) => m.uid == uid).firstOrNull?.displayName ??
            'P';
    return name.substring(0, 1).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final total = filtered.fold<double>(0, (s, e) => s + e.amount);
    final generatedAt =
        DateFormat('yyyy-MM-dd  HH:mm').format(DateTime.now());

    return Container(
      width: _kReceiptW,
      decoration: BoxDecoration(
        color: _kPaper,
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
          // ── Header ────────────────────────────────────────────
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
                      color: _kPurple,
                    ),
                    const SizedBox(width: 5),
                    const Text(
                      'TRACKORA',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 3.5,
                        color: _kPurple,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                const Text(
                  'Group Expense Receipt',
                  style: TextStyle(
                    fontSize: 9,
                    letterSpacing: 0.8,
                    color: _kInk60,
                  ),
                ),
              ],
            ),
          ),

          _DottedRule(),

          // ── Meta info ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
            child: Column(
              children: [
                _InfoRow('GROUP', group.name),
                const SizedBox(height: 4),
                _InfoRow('PERIOD', periodLabel),
                const SizedBox(height: 4),
                _InfoRow('TYPE', isDaily ? 'Daily' : 'Monthly'),
              ],
            ),
          ),

          _DottedRule(),

          // ── Expense rows ──────────────────────────────────────
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
              child: Center(
                child: Text(
                  isDaily
                      ? 'No expenses on this day'
                      : 'No expenses this month',
                  style: const TextStyle(
                    fontSize: 13,
                    color: _kInk60,
                    letterSpacing: 0.2,
                  ),
                ),
              ),
            )
          else ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'EXPENSES',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    color: _kInk60,
                  ),
                ),
              ),
            ),
            ...filtered.map(
              (e) => Padding(
                padding: const EdgeInsets.fromLTRB(24, 5, 24, 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Payer avatar
                    Container(
                      width: 22,
                      height: 22,
                      margin: const EdgeInsets.only(top: 1, right: 8),
                      decoration: BoxDecoration(
                        color: e.paidBy == userId
                            ? _kPurple.withValues(alpha: 0.12)
                            : _kGreen.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          _memberInitials(e.paidBy),
                          style: TextStyle(
                            fontSize: 8,
                            fontWeight: FontWeight.w800,
                            color: e.paidBy == userId ? _kPurple : _kGreen,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            e.description,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _kInk,
                            ),
                          ),
                          Text(
                            '${_memberName(e.paidBy)} · ${DateFormat('MMM d').format(e.date)} · ${e.category}',
                            style: const TextStyle(
                              fontSize: 9,
                              color: _kInk60,
                              letterSpacing: 0.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '$symbol${e.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: _kInk,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            _DottedRule(),

            // ── Total ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
              child: Column(
                children: [
                  _AmountRow(
                    label: 'TOTAL SPENT',
                    value: '$symbol${total.toStringAsFixed(2)}',
                    color: _kInk,
                    large: true,
                  ),
                ],
              ),
            ),

            _DottedRule(),

            // ── Balance summary ────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 10, 24, 10),
              child: Row(
                children: [
                  Container(
                    width: 22,
                    height: 22,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      color: myNet.abs() < 0.005
                          ? _kGreen.withValues(alpha: 0.12)
                          : _kAmber.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Icon(
                        myNet.abs() < 0.005
                            ? CupertinoIcons.checkmark_alt
                            : CupertinoIcons.arrow_right,
                        size: 11,
                        color: myNet.abs() < 0.005 ? _kGreen : _kAmber,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      myNet.abs() < 0.005
                          ? 'All settled up'
                          : myNet > 0
                              ? '$partnerName owes you  $symbol${myNet.abs().toStringAsFixed(2)}'
                              : '${userName.isNotEmpty ? userName : 'You'} owe $partnerName  $symbol${myNet.abs().toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: myNet.abs() < 0.005 ? _kGreen : _kAmber,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          _DottedRule(),

          // ── Footer ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 10, 24, 20),
            child: Column(
              children: [
                const Text(
                  'Generated by Trackora',
                  style: TextStyle(
                    fontSize: 9,
                    color: _kInk60,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  generatedAt,
                  style: const TextStyle(
                    fontSize: 8,
                    color: _kInk60,
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

// ── Shared sub-widgets (mirrors BillReceiptScreen style) ─────────────────────

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
      ..color = _kPaperEdge
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
  bool shouldRepaint(covariant CustomPainter _) => false;
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
                color: _kInk60,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: _kInk,
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
                color: _kInk60,
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: _kInk.withValues(alpha: 0.06),
          shape: BoxShape.circle,
        ),
        child: Center(child: child),
      ),
    );
  }
}
