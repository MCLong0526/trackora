import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/account.dart';
import '../../models/expense.dart';
import '../../models/split_bill.dart';
import '../../repositories/local_expense_repository.dart';
import '../../repositories/local_split_bill_repository.dart';
import '../../repositories/split_bill_repository.dart';
import '../../screens/expenses/bill_receipt_screen.dart';
import '../../services/i18n.dart';
import '../../services/sync_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';

const _kGreen = Color(0xFF1F7A60);

const _kAvatarColors = [
  Color(0xFF6B40A8),
  Color(0xFF1F7A60),
  Color(0xFF2A6FB5),
  Color(0xFFB23A4A),
  Color(0xFFA0801C),
  Color(0xFFE8820E),
  Color(0xFF5C3A9E),
];

Color _avatarColor(int colorIndex) =>
    _kAvatarColors[colorIndex % _kAvatarColors.length];

/// Full tracking + settle screen for a SplitBill.
class BillDetailScreen extends ConsumerStatefulWidget {
  final SplitBill bill;
  final String uid;

  /// Account the original expense was paid from — used as the default
  /// destination when collecting a settlement.
  final String? defaultAccountId;

  const BillDetailScreen({
    super.key,
    required this.bill,
    required this.uid,
    this.defaultAccountId,
  });

  @override
  ConsumerState<BillDetailScreen> createState() => _BillDetailScreenState();
}

class _BillDetailScreenState extends ConsumerState<BillDetailScreen> {
  late SplitBill _bill;

  @override
  void initState() {
    super.initState();
    _bill = widget.bill;
  }

  /// Persists the updated bill, local-first then Firestore best-effort so it
  /// works offline.
  Future<void> _persistBill(SplitBill newBill) async {
    try {
      await LocalSplitBillRepository().updateSplitBill(widget.uid, newBill);
    } catch (_) {}
    if (ref.read(isOnlineProvider)) {
      try {
        await SplitBillRepository().updateSplitBill(widget.uid, newBill);
      } catch (_) {}
    }
  }

  /// Collects a debtor's share. Lets the user enter the amount received
  /// (default = remaining owed) and the account to receive into, posts an
  /// income ("receive"), updates the bill, then pops back to the previous page.
  Future<void> _settle(SplitMember member) async {
    final accounts = ref.read(accountsProvider).valueOrNull ?? const <Account>[];
    if (accounts.isEmpty) {
      AppToast.show(context, context.t('split.needAccount'),
          type: AppToastType.error);
      return;
    }

    final result = await showModalBottomSheet<({double amount, String accountId})>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SettleSheet(
        member: member,
        accounts: accounts,
        defaultAccountId: widget.defaultAccountId,
        currencySymbol: _bill.currencySymbol,
      ),
    );
    if (result == null || !mounted) return;

    // Capture localized strings before further awaits (avoid context across gaps).
    final settlementLabel = context.t('split.settlementNote');
    final settledLabel = context.t('split.settled');

    final uid = widget.uid;
    final now = DateTime.now();
    final remaining = member.amount;
    final settledAmount =
        result.amount >= remaining ? remaining : result.amount;

    // FX: freeze a converted amount when the bill currency differs from base.
    final mainCode = await ref.read(currencyCodeProvider.future);
    String? originalCurrency;
    double? fxRate;
    double? baseAmt;
    if (_bill.currency != mainCode) {
      originalCurrency = _bill.currency;
      try {
        fxRate = await ref.read(exchangeRateServiceProvider).getRate(
              from: _bill.currency,
              to: mainCode,
              base: mainCode,
            );
      } catch (_) {}
      if (fxRate != null) baseAmt = settledAmount * fxRate;
    }

    final settlement = Expense(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      amount: settledAmount,
      category: 'Others',
      note: '$settlementLabel: ${member.name} · ${_bill.title}',
      date: now,
      type: EntryType.receive,
      accountId: result.accountId,
      counterpart: member.name,
      originalCurrency: originalCurrency,
      exchangeRate: fxRate,
      baseCurrencyAmount: baseAmt,
      createdAt: now,
      updatedAt: now,
    );

    final isOnline = ref.read(isOnlineProvider);
    final repo = ref.read(expenseRepositoryProvider);
    if (isOnline) {
      try {
        await repo.addExpense(uid, settlement);
        await LocalExpenseRepository().upsertExpense(uid, settlement);
      } catch (_) {
        await LocalExpenseRepository().upsertExpense(uid, settlement);
        if (storageMode == StorageMode.firebase) {
          await SyncService().markPending(uid, settlement.id);
        }
      }
    } else {
      await LocalExpenseRepository().upsertExpense(uid, settlement);
      if (storageMode == StorageMode.firebase) {
        await SyncService().markPending(uid, settlement.id);
      }
    }

    // Full payment closes the member; a partial payment reduces what they owe.
    final isFull = settledAmount >= remaining - 0.005;
    final updatedMember = member.copyWith(
      amount: isFull ? member.amount : (remaining - settledAmount),
      status: isFull ? SplitMemberStatus.paid : SplitMemberStatus.pending,
      paidAt: isFull ? now : member.paidAt,
    );
    final newMembers =
        _bill.members.map((m) => m.id == member.id ? updatedMember : m).toList();
    // Record the collected payment, backed by the "receive" expense just posted.
    // Deleting that expense later (from Activity) reverts this settlement.
    final newSettlement = SplitSettlement(
      memberId: member.id,
      amount: settledAmount,
      accountId: result.accountId,
      expenseId: settlement.id,
      date: now,
    );
    final newBill = _bill.copyWith(
      members: newMembers,
      settlements: [..._bill.settlements, newSettlement],
      updatedAt: now,
    );
    await _persistBill(newBill);
    if (!mounted) return;
    setState(() => _bill = newBill);

    AppToast.show(
      context,
      '$settledLabel · ${_bill.currencySymbol} ${settledAmount.toStringAsFixed(2)}',
      type: AppToastType.success,
    );
    // Return to the transaction page; signal that a settlement happened so the
    // caller can play its "done" animation.
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final debtors = _bill.debtors;
    // What others owe you = the whole bill minus your own share. The progress
    // and the "owed to you" stat are measured against this, NOT the bill total,
    // so collecting RM100 on a RM200 bill (your share is RM100) reads as 100%.
    final owedToYou =
        (_bill.totalAmount - _bill.payer.amount).clamp(0.0, double.infinity);
    final collected = _bill.collected;
    final outstanding = _bill.outstanding;
    final progress =
        owedToYou > 0 ? (collected / owedToYou).clamp(0.0, 1.0) : 0.0;
    final progressPct = (progress * 100).round();
    final dateStr = DateFormat('MMM d, yyyy').format(_bill.date);

    return Scaffold(
      backgroundColor: brand.background,
      appBar: AppBar(
        backgroundColor: brand.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration:
                BoxDecoration(color: brand.surface, shape: BoxShape.circle),
            child: Icon(CupertinoIcons.chevron_left, size: 18, color: brand.ink),
          ),
        ),
        title: Text(
          context.t('split.manageSettle'),
          style: TextStyle(
              fontWeight: FontWeight.w700, color: brand.ink, fontSize: 17),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _heroCard(dateStr, progressPct, progress, owedToYou, collected,
                outstanding, brand),
            const SizedBox(height: 24),
            Text(
              '${context.t('split.whoOwesYou')} · ${debtors.length}',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF8E8E93),
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              decoration: BoxDecoration(
                color: brand.surface,
                borderRadius: BorderRadius.circular(AppRadius.card),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.card),
                child: Column(children: _buildDebtorRows(debtors, brand)),
              ),
            ),
            if (_bill.settlements.isNotEmpty) ...[
              const SizedBox(height: 24),
              Text(
                context.t('split.receiveRecords').toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8E8E93),
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.card),
                  child: Column(children: _buildSettlementRows(brand)),
                ),
              ),
            ],
            const SizedBox(height: 24),
            GestureDetector(
              onTap: () => Navigator.push<void>(
                context,
                CupertinoPageRoute(
                  builder: (_) => BillReceiptScreen(bill: _bill),
                ),
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: const Color(0xFF6B40A8),
                  borderRadius: BorderRadius.circular(9999),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(CupertinoIcons.doc_text,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(
                      context.t('group.generateReceipt'),
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              context.t('split.settleFooter'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: brand.inkSoft),
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCard(
      String dateStr,
      int progressPct,
      double progress,
      double owedToYou,
      double collected,
      double outstanding,
      BrandColors brand) {
    String money(double v) => '${_bill.currencySymbol} ${v.toStringAsFixed(2)}';
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
            '$dateStr · ${context.t('split.peopleCount').replaceAll('{n}', '${_bill.members.length}')}',
            style: const TextStyle(fontSize: 13, color: Colors.white70),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _heroStat(
                    context.t('split.billTotal'), money(_bill.totalAmount)),
              ),
              Expanded(
                child: _heroStat(
                    context.t('split.owedToYouLabel'), money(owedToYou)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white.withValues(alpha: 0.2),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF9FF0C8)),
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$progressPct% ${context.t('split.paidBack')}  ·  '
            '${money(collected)} ${context.t('split.collectedLc')} · '
            '${money(outstanding)} ${context.t('split.leftLc')}',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: Colors.white60, letterSpacing: 0.8)),
        Text(
          value,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ],
    );
  }

  List<Widget> _buildDebtorRows(List<SplitMember> debtors, BrandColors brand) {
    if (debtors.isEmpty) {
      return [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Text(context.t('split.noOneElse'),
              style: TextStyle(color: brand.inkSoft)),
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
      final paidStr =
          paidAt != null ? _relativeTime(context, paidAt) : context.t('split.recently');
      statusText = '${context.t('split.settled')} · $paidStr';
      statusColor = _kGreen;
    } else {
      statusText = '${_bill.currencySymbol} ${m.amount.toStringAsFixed(2)} ${context.t('split.outstandingLc')}';
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
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: brand.ink),
                ),
                Text(statusText,
                    style: TextStyle(fontSize: 12, color: statusColor)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          if (isPaid)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFCFEFE2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(CupertinoIcons.checkmark_alt,
                      size: 12, color: _kGreen),
                  const SizedBox(width: 4),
                  Text(
                    context.t('split.paidBadge'),
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kGreen,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
            )
          else
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                _settle(m);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _kGreen,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  context.t('split.settle').toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildSettlementRows(BrandColors brand) {
    final items = [..._bill.settlements]
      ..sort((a, b) => b.date.compareTo(a.date));
    final divider = Container(
      height: 0.5,
      margin: const EdgeInsets.only(left: 62),
      color: brand.divider,
    );
    final rows = <Widget>[];
    for (int i = 0; i < items.length; i++) {
      if (i > 0) rows.add(divider);
      rows.add(_settlementRow(items[i], brand));
    }
    return rows;
  }

  Widget _settlementRow(SplitSettlement s, BrandColors brand) {
    final member = _bill.members.firstWhere(
      (m) => m.id == s.memberId,
      orElse: () => SplitMember(
        id: s.memberId,
        name: context.t('split.someone'),
        colorIndex: 0,
        amount: 0,
      ),
    );
    final dateStr = DateFormat('MMM d, yyyy · h:mm a').format(s.date);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: _avatarColor(member.colorIndex),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(CupertinoIcons.arrow_down_left,
                  size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.name,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: brand.ink),
                ),
                Text(dateStr,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF8E8E93))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '+ ${_bill.currencySymbol} ${s.amount.toStringAsFixed(2)}',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: _kGreen),
          ),
        ],
      ),
    );
  }

  String _relativeTime(BuildContext context, DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60) {
      return context.t('split.minAgo').replaceAll('{n}', '${diff.inMinutes}');
    }
    if (diff.inHours < 24) {
      return context.t('split.hourAgo').replaceAll('{n}', '${diff.inHours}');
    }
    if (diff.inDays == 1) return context.t('split.yesterdayRel');
    return DateFormat('MMM d').format(dt);
  }
}

/// Bottom sheet to settle a debtor: enter the amount received and pick the
/// account to receive it into.
class _SettleSheet extends StatefulWidget {
  final SplitMember member;
  final List<Account> accounts;
  final String? defaultAccountId;
  final String currencySymbol;

  const _SettleSheet({
    required this.member,
    required this.accounts,
    required this.defaultAccountId,
    required this.currencySymbol,
  });

  @override
  State<_SettleSheet> createState() => _SettleSheetState();
}

class _SettleSheetState extends State<_SettleSheet> {
  late final TextEditingController _amountCtrl;
  late String _accountId;

  @override
  void initState() {
    super.initState();
    _amountCtrl = TextEditingController(
        text: widget.member.amount.toStringAsFixed(2));
    _accountId = widget.defaultAccountId != null &&
            widget.accounts.any((a) => a.id == widget.defaultAccountId)
        ? widget.defaultAccountId!
        : widget.accounts.first.id;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  void _confirm() {
    final amount = double.tryParse(_amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) return;
    Navigator.pop(context, (amount: amount, accountId: _accountId));
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: brand.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  '${context.t('split.settle')} · ${widget.member.name}',
                  style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: brand.ink),
                ),
                const SizedBox(height: 16),
                _label(context.t('split.amountReceived'), brand),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: brand.surface,
                    borderRadius: BorderRadius.circular(AppRadius.field),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Text(widget.currencySymbol,
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: brand.inkSoft)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _amountCtrl,
                          autofocus: false,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: brand.ink),
                          decoration: const InputDecoration(
                            hintText: '0.00',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                _label(context.t('split.receiveInto'), brand),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: widget.accounts.map((a) {
                    final selected = a.id == _accountId;
                    final isDefault = a.id == widget.defaultAccountId;
                    return GestureDetector(
                      onTap: () => setState(() => _accountId = a.id),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 9),
                        decoration: BoxDecoration(
                          color: selected ? _kGreen : brand.surface,
                          borderRadius: BorderRadius.circular(AppRadius.chip),
                          border: selected
                              ? null
                              : Border.all(color: brand.divider),
                        ),
                        child: Text(
                          isDefault
                              ? '${a.displayName} · ${context.t('split.original')}'
                              : a.displayName,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : brand.ink,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    style: FilledButton.styleFrom(backgroundColor: _kGreen),
                    onPressed: _confirm,
                    child: Text(context.t('split.settle')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _label(String text, BrandColors brand) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: brand.inkSoft,
        ),
      );
}
