import '../app_config.dart';
import '../models/borrow_lending.dart';
import '../models/expense.dart';
import '../models/person.dart';
import '../models/split_bill.dart';
import '../repositories/firebase_borrow_lending_repository.dart';
import '../repositories/firebase_expense_repository.dart';
import '../repositories/local_borrow_lending_repository.dart';
import '../repositories/local_expense_repository.dart';
import '../repositories/local_split_bill_repository.dart';
import '../repositories/split_bill_repository.dart';

/// Propagates a contact ([Person]) edit — name / colour / emoji — to every
/// transaction that stores a denormalised copy of that person, so the data the
/// user sees elsewhere never drifts from the contact:
///   • split bills (and their detail / settle / receipt screens), which embed
///     each member's `name`, `colorIndex` and `emoji`;
///   • borrow / lending records, which reference the person by name.
///
/// Follows the same local-first + Firestore-when-online write strategy as
/// [SplitSettlementService] so it behaves consistently in both storage modes.
class PersonPropagationService {
  static Future<void> propagatePersonUpdate({
    required String uid,
    required Person person,
    required String oldName,
    required bool isOnline,
  }) async {
    final lowerOld = oldName.trim().toLowerCase();
    await _propagateSplitBills(uid, person, lowerOld, isOnline);
    await _propagateBorrowLending(uid, person, oldName, lowerOld, isOnline);
    await _propagateExpenseCounterparts(uid, person, oldName, lowerOld, isOnline);
  }

  // ── Split bills ────────────────────────────────────────────────────────────
  static Future<void> _propagateSplitBills(
    String uid,
    Person person,
    String lowerOld,
    bool isOnline,
  ) async {
    final bills = await _loadAllSplitBills(uid, isOnline);
    for (final bill in bills) {
      var changed = false;
      final newMembers = bill.members.map((m) {
        // The payer is the user themselves, never an external contact.
        if (m.isPayer) return m;
        final matches = (m.personId != null && m.personId == person.id) ||
            (m.personId == null && m.name.trim().toLowerCase() == lowerOld);
        if (!matches) return m;
        if (m.name == person.name &&
            m.colorIndex == person.colorIndex &&
            m.emoji == person.emoji &&
            m.personId == person.id) {
          return m; // already in sync
        }
        changed = true;
        return SplitMember(
          id: m.id,
          name: person.name,
          colorIndex: person.colorIndex,
          emoji: person.emoji,
          amount: m.amount,
          isPayer: m.isPayer,
          status: m.status,
          paidAt: m.paidAt,
          // Link the member to the contact going forward so future edits match
          // by id even if the name changes again.
          personId: person.id,
        );
      }).toList();
      if (!changed) continue;

      final newBill =
          bill.copyWith(members: newMembers, updatedAt: DateTime.now());
      try {
        await LocalSplitBillRepository().updateSplitBill(uid, newBill);
      } catch (_) {}
      if (storageMode == StorageMode.firebase && isOnline) {
        try {
          await SplitBillRepository().updateSplitBill(uid, newBill);
        } catch (_) {}
      }
    }
  }

  /// Local-first, merged with Firestore when online (both stores share the same
  /// bill id, so merge by id is safe). Mirrors `allSplitBillsProvider`.
  static Future<List<SplitBill>> _loadAllSplitBills(
    String uid,
    bool isOnline,
  ) async {
    List<SplitBill> local;
    try {
      local = await LocalSplitBillRepository().getAllSplitBills(uid);
    } catch (_) {
      local = const [];
    }
    if (storageMode == StorageMode.firebase && isOnline) {
      try {
        final remote = await SplitBillRepository().watchSplitBills(uid).first;
        final byId = {for (final b in local) b.id: b};
        for (final r in remote) {
          byId[r.id] = r;
        }
        return byId.values.toList();
      } catch (_) {}
    }
    return local;
  }

  // ── Borrow / lending ─────────────────────────────────────────────────────
  static Future<void> _propagateBorrowLending(
    String uid,
    Person person,
    String oldName,
    String lowerOld,
    bool isOnline,
  ) async {
    // Borrow / lending records only store the person's name (their avatar
    // colour is derived from it), so they only need touching on a rename.
    if (person.name.trim() == oldName.trim()) return;

    List<BorrowLending> records;
    try {
      records = await LocalBorrowLendingRepository().getAll(uid).first;
    } catch (_) {
      return;
    }
    for (final r in records) {
      if (r.person.trim().toLowerCase() != lowerOld) continue;
      if (r.person == person.name) continue;
      final updated =
          r.copyWith(person: person.name, updatedAt: DateTime.now());
      try {
        await LocalBorrowLendingRepository().update(uid, updated);
      } catch (_) {}
      if (storageMode == StorageMode.firebase && isOnline) {
        try {
          await FirebaseBorrowLendingRepository().update(uid, updated);
        } catch (_) {}
      }
    }
  }

  // ── Expense "From / To" counterparts ──────────────────────────────────────
  static Future<void> _propagateExpenseCounterparts(
    String uid,
    Person person,
    String oldName,
    String lowerOld,
    bool isOnline,
  ) async {
    // The counterpart is a free-text name (it carries no colour), so it only
    // needs touching when the contact is renamed.
    if (person.name.trim() == oldName.trim()) return;

    List<Expense> expenses;
    try {
      expenses = await LocalExpenseRepository().getAllExpenses(uid).first;
    } catch (_) {
      return;
    }
    for (final e in expenses) {
      final cp = e.counterpart?.trim();
      if (cp == null || cp.toLowerCase() != lowerOld) continue;
      if (cp == person.name) continue;
      final updated =
          e.copyWith(counterpart: person.name, updatedAt: DateTime.now());
      try {
        await LocalExpenseRepository().updateExpense(uid, updated);
      } catch (_) {}
      if (storageMode == StorageMode.firebase && isOnline) {
        try {
          await FirebaseExpenseRepository().updateExpense(uid, updated);
        } catch (_) {}
      }
    }
  }
}
