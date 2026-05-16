import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:io';

import '../../models/split_bill.dart';
import '../../repositories/split_bill_repository.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

const _kPurple = Color(0xFF6B40A8);

const _kAvatarColors = [
  Color(0xFF6B40A8),
  Color(0xFF1F7A60),
  Color(0xFF2A6FB5),
  Color(0xFFB23A4A),
  Color(0xFFA0801C),
  Color(0xFFE8820E),
  Color(0xFF5C3A9E),
];

Color _avatarColor(int colorIndex) => _kAvatarColors[colorIndex % _kAvatarColors.length];

/// Full tracking screen for a SplitBill.
class BillDetailScreen extends StatefulWidget {
  final SplitBill bill;
  final String uid;

  const BillDetailScreen({super.key, required this.bill, required this.uid});

  @override
  State<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends State<BillDetailScreen> {
  late SplitBill _bill;
  final _receiptKey = GlobalKey();
  bool _sharing = false;

  @override
  void initState() {
    super.initState();
    _bill = widget.bill;
  }

  Future<void> _markPaid(SplitMember member) async {
    final updated = member.copyWith(
      status: SplitMemberStatus.paid,
      paidAt: DateTime.now(),
    );
    final newMembers = _bill.members.map((m) => m.id == member.id ? updated : m).toList();
    final newBill = _bill.copyWith(members: newMembers, updatedAt: DateTime.now());
    try {
      await SplitBillRepository().updateSplitBill(widget.uid, newBill);
      setState(() => _bill = newBill);
      if (newBill.isClosed && mounted) {
        AppToast.show(context, 'Bill closed! All settled.', type: AppToastType.success);
      }
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Failed to update: $e', type: AppToastType.error);
      }
    }
  }

  void _remind(SplitMember member) {
    final msg = 'Hey ${member.name}, you owe me '
        '${_bill.currencySymbol} ${member.amount.toStringAsFixed(2)} '
        'for "${_bill.title}". Please settle when you can!';
    Clipboard.setData(ClipboardData(text: msg));
    AppToast.show(context, 'Reminder copied to clipboard!', type: AppToastType.info);
  }

  Future<void> _shareBill() async {
    if (_sharing) return;
    setState(() => _sharing = true);
    try {
      // Render receipt widget to image
      final boundary = _receiptKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/bill_${_bill.billNumber}.png');
      await file.writeAsBytes(bytes);
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Bill ${_bill.billNumber} — ${_bill.title}\n'
            'Total: ${_bill.currencySymbol} ${_bill.totalAmount.toStringAsFixed(2)}\n'
            'Split between ${_bill.members.length} people.',
      );
    } catch (e) {
      if (mounted) {
        AppToast.show(context, 'Failed to share: $e', type: AppToastType.error);
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  void _showMarkPaidSheet() {
    final debtors = _bill.debtors.where((m) => m.status != SplitMemberStatus.paid).toList();
    if (debtors.isEmpty) {
      AppToast.show(context, 'Everyone has already paid!', type: AppToastType.info);
      return;
    }
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Mark someone as paid'),
        actions: debtors.map((m) {
          return CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _markPaid(m);
            },
            child: Text('${m.name} — ${_bill.currencySymbol} ${m.amount.toStringAsFixed(2)}'),
          );
        }).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final debtors = _bill.debtors;
    final progress = _bill.totalAmount > 0
        ? (_bill.collected / (_bill.totalAmount - _bill.payer.amount)).clamp(0.0, 1.0)
        : 0.0;
    final progressPct = (progress * 100).round();
    final dateStr = DateFormat('MMM d, yyyy').format(_bill.date);

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: brand.surface, shape: BoxShape.circle),
            child: Icon(CupertinoIcons.chevron_left, size: 18, color: brand.ink),
          ),
        ),
        title: Text(
          'Bill Detail',
          style: TextStyle(fontWeight: FontWeight.w700, color: brand.ink, fontSize: 17),
        ),
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.only(right: 8),
            onPressed: () => _showMoreMenu(context),
            child: Icon(CupertinoIcons.ellipsis_circle, color: brand.ink),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Hero card ──
            _heroCard(dateStr, progressPct, progress, brand),
            const SizedBox(height: 20),
            // ── Share button ──
            GestureDetector(
              onTap: _shareBill,
              child: Container(
                height: 48,
                decoration: BoxDecoration(
                  color: _kPurple.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _kPurple.withValues(alpha: 0.25)),
                ),
                child: Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_sharing)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: _kPurple),
                        )
                      else
                        const Icon(CupertinoIcons.share, size: 18, color: _kPurple),
                      const SizedBox(width: 8),
                      const Text(
                        'Share bill',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _kPurple,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // ── Who owes you ──
            Row(
              children: [
                Text(
                  'WHO OWES YOU · ${debtors.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF8E8E93),
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Column(
                  children: _buildDebtorRows(debtors, brand),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // ── Mark paid link ──
            GestureDetector(
              onTap: _showMarkPaidSheet,
              child: const Center(
                child: Text(
                  '+ Mark someone paid manually',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _kPurple,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // ── Footer note ──
            Text(
              'When everyone settles, this bill closes automatically and posts the income back to your Funds.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: brand.inkSoft),
            ),
            // ── Off-screen receipt (for sharing) ──
            const SizedBox(height: 40),
            Transform.translate(
              offset: const Offset(10000, 0), // hide off-screen
              child: RepaintBoundary(
                key: _receiptKey,
                child: _ReceiptCard(bill: _bill),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCard(String dateStr, int progressPct, double progress, BrandColors brand) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF7B52BE), Color(0xFF5A32A3)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'BILL ${_bill.billNumber}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _bill.title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '$dateStr · ${_bill.members.length} people · ${_bill.splitMode.name[0].toUpperCase()}${_bill.splitMode.name.substring(1)} split',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('BILL TOTAL', style: TextStyle(fontSize: 10, color: Colors.white60, letterSpacing: 0.8)),
                    Text(
                      '${_bill.currencySymbol} ${_bill.totalAmount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('OUTSTANDING', style: TextStyle(fontSize: 10, color: Colors.white60, letterSpacing: 0.8)),
                    Text(
                      '${_bill.currencySymbol} ${_bill.outstanding.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF9FF0C8)),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$progressPct% paid back',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDebtorRows(List<SplitMember> debtors, BrandColors brand) {
    if (debtors.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text('No one else in this split.', style: TextStyle(color: brand.inkSoft)),
        ),
      ];
    }
    final divider = Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 62),
      color: brand.divider,
    );
    final rows = <Widget>[];
    for (int i = 0; i < debtors.length; i++) {
      if (i > 0) rows.add(divider);
      rows.add(_debtorRow(debtors[i], brand));
    }
    return rows;
  }

  Widget _debtorRow(SplitMember m, BrandColors brand) {
    final isPaid = m.status == SplitMemberStatus.paid;
    String statusText;
    Color statusColor;
    if (isPaid) {
      final paidAt = m.paidAt;
      final paidStr = paidAt != null ? _relativeTime(paidAt) : 'recently';
      statusText = 'Paid · $paidStr';
      statusColor = const Color(0xFF1F7A60);
    } else if (m.status == SplitMemberStatus.reminded) {
      statusText = 'Reminded';
      statusColor = const Color(0xFFA0801C);
    } else {
      statusText = 'Not sent';
      statusColor = const Color(0xFF8E8E93);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _avatarColor(m.colorIndex),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                m.initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  m.name,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: brand.ink),
                ),
                Text(statusText, style: TextStyle(fontSize: 12, color: statusColor)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '${_bill.currencySymbol} ${m.amount.toStringAsFixed(2)}',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: isPaid ? const Color(0xFF1F7A60) : brand.ink,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: () {
              if (isPaid) return;
              HapticFeedback.selectionClick();
              _remind(m);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: isPaid
                    ? const Color(0xFFCFEFE2)
                    : _kPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isPaid) ...[
                    const Icon(CupertinoIcons.checkmark_alt, size: 12, color: Color(0xFF1F7A60)),
                    const SizedBox(width: 4),
                    const Text(
                      'PAID',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F7A60),
                        letterSpacing: 0.5,
                      ),
                    ),
                  ] else ...[
                    const Text(
                      'REMIND',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _kPurple,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _showMarkPaidSheet();
            },
            child: const Text('Mark someone as paid'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _shareBill();
            },
            child: const Text('Share bill receipt'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'yesterday';
    return DateFormat('MMM d').format(dt);
  }
}

// ─── Shareable Receipt Card ────────────────────────────────────────────────────

class _ReceiptCard extends StatelessWidget {
  final SplitBill bill;

  const _ReceiptCard({required this.bill});

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('MMM d, yyyy').format(bill.date);
    final payer = bill.payer;
    final splitLabel = '${bill.splitMode.name[0].toUpperCase()}${bill.splitMode.name.substring(1)}';

    return Container(
      width: 320,
      color: Colors.white,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'TRACKORA · BILL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Color(0xFF6B40A8),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            bill.billNumber,
            style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93)),
          ),
          Text(dateStr, style: const TextStyle(fontSize: 12, color: Color(0xFF8E8E93))),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFEAEAEC)),
          ),
          // Title info
          Text(
            bill.title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF111111)),
          ),
          const SizedBox(height: 4),
          Text(
            'Paid by ${payer.name} · Split $splitLabel · ${bill.members.length} people',
            style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B70)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFEAEAEC)),
          ),
          // Bill total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Bill Total', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              Text(
                '${bill.currencySymbol} ${bill.totalAmount.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF6B40A8)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Per person', style: TextStyle(fontSize: 12, color: Color(0xFF6B6B70))),
              Text(
                '${bill.currencySymbol} ${(bill.totalAmount / bill.members.length).toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF6B6B70)),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1, color: Color(0xFFEAEAEC)),
          ),
          // Person list
          ...bill.members.map((m) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _avatarColor(m.colorIndex),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          m.initials,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        m.isPayer ? '${m.name} (paid)' : m.name,
                        style: const TextStyle(fontSize: 13, color: Color(0xFF111111)),
                      ),
                    ),
                    Text(
                      '${bill.currencySymbol} ${m.amount.toStringAsFixed(2)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              )),
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: Divider(height: 1, color: Color(0xFFEAEAEC)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Generated by Trackora',
            style: TextStyle(fontSize: 10, color: Color(0xFF8E8E93)),
          ),
        ],
      ),
    );
  }
}
