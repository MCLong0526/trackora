import '../app_config.dart';
import '../models/split_bill.dart';
import '../repositories/local_split_bill_repository.dart';
import '../repositories/split_bill_repository.dart';

/// Keeps split bills in sync when their settlement ("receive") expenses are
/// deleted from the Activity list.
class SplitSettlementService {
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
