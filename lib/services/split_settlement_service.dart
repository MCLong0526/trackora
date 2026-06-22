import '../app_config.dart';
import '../models/split_bill.dart';
import '../repositories/local_expense_repository.dart';
import '../repositories/local_split_bill_repository.dart';
import '../repositories/split_bill_repository.dart';
import 'sync_service.dart';

/// Keeps split bills in sync when their settlement ("receive") expenses are
/// deleted from the Activity list.
class SplitSettlementService {
  /// Deletes the split bill whose source (origin) expense is [expenseId], along
  /// with every settlement-backing "receive" expense it had collected. This
  /// keeps the Activity list, account balances and the People page correct when
  /// the original split transaction is removed. No-op when [expenseId] has no
  /// linked bill (e.g. it's a settlement or a plain expense).
  static Future<void> deleteBillForSourceExpense({
    required String uid,
    required String expenseId,
    required bool isOnline,
  }) async {
    SplitBill? local;
    try {
      local = await LocalSplitBillRepository()
          .getSplitBillByExpenseId(uid, expenseId);
    } catch (_) {}

    SplitBill? remote;
    if (storageMode == StorageMode.firebase && isOnline) {
      try {
        remote = await SplitBillRepository()
            .getSplitBillByExpenseId(uid, expenseId);
      } catch (_) {}
    }

    if (local == null && remote == null) return;

    // Delete every "receive" expense that backed a collected settlement so the
    // money collected from members disappears together with the bill.
    final settlementExpenseIds = <String>{
      ...?local?.settlements.map((s) => s.expenseId),
      ...?remote?.settlements.map((s) => s.expenseId),
    }..removeWhere((id) => id.isEmpty);
    for (final sid in settlementExpenseIds) {
      try {
        if (storageMode == StorageMode.firebase) {
          await SyncService()
              .deleteExpense(userId: uid, expenseId: sid, isOnline: isOnline);
        } else {
          await LocalExpenseRepository().deleteExpense(uid, sid);
        }
      } catch (_) {}
    }

    if (local != null) {
      try {
        await LocalSplitBillRepository()
            .deleteSplitBill(uid, local.id, expenseId);
      } catch (_) {}
    }
    if (storageMode == StorageMode.firebase && isOnline && remote != null) {
      try {
        await SplitBillRepository().deleteSplitBill(uid, remote.id);
      } catch (_) {}
    }
  }

  /// If [expenseId] is a settlement (receive) expense linked to a split bill,
  /// removes that settlement and reverts the corresponding member back to
  /// owing (status → pending, payment restored). No-op when the expense is not
  /// a recorded settlement. Returns true when a settlement was reverted.
  static Future<bool> revertIfSettlement({
    required String uid,
    required String expenseId,
    required bool isOnline,
  }) async {
    final bills = await LocalSplitBillRepository().getAllSplitBills(uid);
    for (final bill in bills) {
      final idx =
          bill.settlements.indexWhere((s) => s.expenseId == expenseId);
      if (idx < 0) continue;

      final settlement = bill.settlements[idx];
      final newSettlements = [...bill.settlements]..removeAt(idx);
      final newMembers = bill.members.map((m) {
        if (m.id != settlement.memberId) return m;
        // A fully-paid member keeps its frozen owed amount; a partially-paid
        // member gets the collected amount added back to what they still owe.
        final restoredAmount = m.status == SplitMemberStatus.paid
            ? m.amount
            : m.amount + settlement.amount;
        return SplitMember(
          id: m.id,
          name: m.name,
          colorIndex: m.colorIndex,
          emoji: m.emoji,
          amount: restoredAmount,
          isPayer: m.isPayer,
          status: SplitMemberStatus.pending,
          paidAt: null,
          personId: m.personId,
        );
      }).toList();

      final newBill = bill.copyWith(
        members: newMembers,
        settlements: newSettlements,
        updatedAt: DateTime.now(),
      );

      try {
        await LocalSplitBillRepository().updateSplitBill(uid, newBill);
      } catch (_) {}
      if (storageMode == StorageMode.firebase && isOnline) {
        try {
          await SplitBillRepository().updateSplitBill(uid, newBill);
        } catch (_) {}
      }
      return true;
    }
    return false;
  }
}
