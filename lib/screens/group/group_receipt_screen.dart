import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import '../../models/expense_group.dart';
import '../../models/group_expense_item.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

class GroupReceiptScreen extends ConsumerStatefulWidget {
  final ExpenseGroup group;
  const GroupReceiptScreen({super.key, required this.group});

  @override
  ConsumerState<GroupReceiptScreen> createState() => _GroupReceiptScreenState();
}

class _GroupReceiptScreenState extends ConsumerState<GroupReceiptScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _sharing = false;
  final _repaintKey = GlobalKey();

  List<GroupExpenseItem> _filterByMonth(List<GroupExpenseItem> all) {
    return all
        .where((e) =>
            e.date.year == _selectedMonth.year &&
            e.date.month == _selectedMonth.month)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  Future<void> _shareAsImage() async {
    setState(() => _sharing = true);
    try {
      await Future.delayed(const Duration(milliseconds: 100));
      final boundary = _repaintKey.currentContext!
          .findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;
      final bytes = byteData.buffer.asUint8List();
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/group_receipt.png');
      await file.writeAsBytes(bytes);
      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Group receipt — ${DateFormat('MMMM yyyy').format(_selectedMonth)}',
      );
    } catch (e) {
      if (mounted) AppToast.show(context, 'Could not share: $e');
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  String _memberName(List<GroupMember> members, String uid, String? myUid) {
    if (uid == myUid) return 'You';
    try {
      return members.firstWhere((m) => m.uid == uid).displayName;
    } catch (_) {
      return 'Partner';
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '';
    final userId = ref.watch(authStateProvider).valueOrNull?.uid;
    final expensesAsync = ref.watch(groupExpensesProvider(widget.group.id));
    final allExpenses = expensesAsync.valueOrNull ?? const [];
    final filtered = _filterByMonth(allExpenses);
    final total = filtered.fold<double>(0, (s, e) => s + e.amount);
    final service = ref.read(expenseGroupServiceProvider);
    final balances = service.computeBalances(widget.group.members, filtered);
    final myBalance = balances
        .cast<dynamic>()
        .firstWhere((b) => b.uid == userId, orElse: () => null);
    final myNet = myBalance?.net as double? ?? 0;
    final partner =
        widget.group.members.where((m) => m.uid != userId).firstOrNull;
    final partnerName = partner?.displayName ?? 'Partner';

    // Build list of available months (past 12)
    final now = DateTime.now();
    final months =
        List.generate(12, (i) => DateTime(now.year, now.month - i));

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
                color: Colors.white, shape: BoxShape.circle),
            child: const Icon(CupertinoIcons.chevron_back,
                color: Color(0xFF0B0B0F), size: 18),
          ),
        ),
        title: Text('Receipt',
            style: TextStyle(
                color: brand.ink, fontSize: 17, fontWeight: FontWeight.w600)),
        centerTitle: true,
        actions: [
          CupertinoButton(
            padding: const EdgeInsets.only(right: 16),
            onPressed: _sharing ? null : _shareAsImage,
            child: _sharing
                ? const CupertinoActivityIndicator()
                : const Icon(CupertinoIcons.share,
                    color: Color(0xFF1A6CFF), size: 20),
          ),
        ],
      ),
      body: Column(
        children: [
          // Month picker
          SizedBox(
            height: 44,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: months.length,
              itemBuilder: (_, i) {
                final m = months[i];
                final isSelected = m.year == _selectedMonth.year &&
                    m.month == _selectedMonth.month;
                return GestureDetector(
                  onTap: () => setState(() => _selectedMonth = m),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? const Color(0xFF1A6CFF)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      DateFormat('MMM yyyy').format(m),
                      style: TextStyle(
                        color: isSelected ? Colors.white : brand.inkSoft,
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // Receipt body (wrapped in RepaintBoundary for screenshot)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
              child: RepaintBoundary(
                key: _repaintKey,
                child: Container(
                  color: brand.background,
                  child: Column(
                    children: [
                      // Receipt card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text('Trackora',
                                        style: TextStyle(
                                            color: brand.ink,
                                            fontSize: 18,
                                            fontWeight: FontWeight.w800)),
                                    Text(widget.group.name,
                                        style: TextStyle(
                                            color: brand.inkSoft,
                                            fontSize: 13)),
                                  ],
                                ),
                                Text(
                                  DateFormat('MMMM yyyy')
                                      .format(_selectedMonth),
                                  style: TextStyle(
                                      color: brand.inkSoft,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            Divider(color: brand.divider, height: 1),
                            const SizedBox(height: 16),

                            // Expense rows
                            if (filtered.isEmpty)
                              Center(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 24),
                                  child: Text('No expenses this month',
                                      style: TextStyle(
                                          color: brand.inkSoft,
                                          fontSize: 14)),
                                ),
                              )
                            else
                              ...filtered.map((e) => Padding(
                                    padding:
                                        const EdgeInsets.only(bottom: 12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(e.description,
                                                  style: TextStyle(
                                                      color: brand.ink,
                                                      fontSize: 14,
                                                      fontWeight:
                                                          FontWeight.w500)),
                                              Text(
                                                '${_memberName(widget.group.members, e.paidBy, userId)} · ${DateFormat('MMM d').format(e.date)}',
                                                style: TextStyle(
                                                    color: brand.inkSoft,
                                                    fontSize: 12),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Text(
                                            '$symbol${e.amount.toStringAsFixed(2)}',
                                            style: TextStyle(
                                                color: brand.ink,
                                                fontSize: 14,
                                                fontWeight:
                                                    FontWeight.w600)),
                                      ],
                                    ),
                                  )),

                            if (filtered.isNotEmpty) ...[
                              Divider(color: brand.divider, height: 1),
                              const SizedBox(height: 12),
                              // Total
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Total',
                                      style: TextStyle(
                                          color: brand.ink,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                  Text(
                                      '$symbol${total.toStringAsFixed(2)}',
                                      style: TextStyle(
                                          color: brand.ink,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700)),
                                ],
                              ),
                              const SizedBox(height: 16),

                              // Balance summary
                              Container(
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF7F7FA),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      myNet.abs() < 0.005
                                          ? CupertinoIcons
                                              .checkmark_circle_fill
                                          : CupertinoIcons
                                              .exclamationmark_circle_fill,
                                      color: myNet.abs() < 0.005
                                          ? const Color(0xFF1FBE71)
                                          : const Color(0xFFF0A33A),
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      myNet.abs() < 0.005
                                          ? 'All settled up'
                                          : myNet > 0
                                              ? '$partnerName owes you $symbol${myNet.abs().toStringAsFixed(2)}'
                                              : 'You owe $partnerName $symbol${myNet.abs().toStringAsFixed(2)}',
                                      style: TextStyle(
                                          color: brand.ink,
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
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

      // Share button
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: SizedBox(
            width: double.infinity,
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(vertical: 14),
              color: const Color(0xFF1A6CFF),
              borderRadius: BorderRadius.circular(18),
              onPressed: _sharing ? null : _shareAsImage,
              child: _sharing
                  ? const CupertinoActivityIndicator(color: Colors.white)
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.share,
                            color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('Share as image',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 15,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
