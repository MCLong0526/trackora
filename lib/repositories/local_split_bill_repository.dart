import 'dart:convert';

import 'package:hive/hive.dart';

import '../models/split_bill.dart';
import 'local_storage.dart';

class LocalSplitBillRepository {
  static Future<void> init() => LocalStorage.init();

  static String _key(String uid, String id) => 'splitbill_${uid}_$id';
  static String _byExpenseKey(String uid, String expenseId) =>
      'splitbill_expense_${uid}_$expenseId';

  /// Returns true if the expense has an associated split bill stored locally.
  /// Safe to call synchronously after LocalStorage is initialized.
  static bool hasSplitBillSync(String uid, String expenseId) {
    if (!Hive.isBoxOpen(LocalStorage.splitBillsBoxName)) return false;
    return LocalStorage.splitBills
        .containsKey('splitbill_expense_${uid}_$expenseId');
  }

  /// Number of non-payer members who still owe (status != paid) for the split
  /// bill linked to [expenseId]. Returns 0 when there is no bill. Synchronous so
  /// it can drive a badge in list rows.
  static int unsettledCountSync(String uid, String expenseId) {
    if (!Hive.isBoxOpen(LocalStorage.splitBillsBoxName)) return 0;
    final box = LocalStorage.splitBills;
    final id = box.get('splitbill_expense_${uid}_$expenseId') as String?;
    if (id == null) return 0;
    final raw = box.get('splitbill_${uid}_$id') as String?;
    if (raw == null) return 0;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final members = map['members'] as List<dynamic>? ?? const [];
      var count = 0;
      for (final e in members) {
        final m = Map<String, dynamic>.from(e as Map);
        if (m['isPayer'] as bool? ?? false) continue;
        if ((m['status'] as String?) != 'paid') count++;
      }
      return count;
    } catch (_) {
      return 0;
    }
  }

  Future<String> saveSplitBill(String uid, SplitBill bill) async {
    await LocalStorage.init();
    final id = bill.id.isEmpty
        ? DateTime.now().microsecondsSinceEpoch.toString()
        : bill.id;
    final saved = bill.id == id
        ? bill
        : SplitBill(
            id: id,
            expenseId: bill.expenseId,
            billNumber: bill.billNumber,
            title: bill.title,
            totalAmount: bill.totalAmount,
            currency: bill.currency,
            currencySymbol: bill.currencySymbol,
            splitMode: bill.splitMode,
            members: bill.members,
            date: bill.date,
            createdAt: bill.createdAt,
            updatedAt: bill.updatedAt,
          );
    final box = LocalStorage.splitBills;
    final data = jsonEncode(saved.toMap());
    await box.put(_key(uid, id), data);
    // index by expenseId for quick lookup
    await box.put(_byExpenseKey(uid, saved.expenseId), id);
    return id;
  }

  Future<void> updateSplitBill(String uid, SplitBill bill) async {
    await LocalStorage.init();
    final box = LocalStorage.splitBills;
    final data = jsonEncode(bill.toMap());
    await box.put(_key(uid, bill.id), data);
    await box.put(_byExpenseKey(uid, bill.expenseId), bill.id);
  }

  Future<SplitBill?> getSplitBillByExpenseId(
      String uid, String expenseId) async {
    await LocalStorage.init();
    final box = LocalStorage.splitBills;
    final id = box.get(_byExpenseKey(uid, expenseId)) as String?;
    if (id == null) return null;
    final raw = box.get(_key(uid, id)) as String?;
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return SplitBill.fromMap(map, id);
    } catch (_) {
      return null;
    }
  }

  Future<void> deleteSplitBill(String uid, String id, String expenseId) async {
    await LocalStorage.init();
    final box = LocalStorage.splitBills;
    await box.delete(_key(uid, id));
    await box.delete(_byExpenseKey(uid, expenseId));
  }

  Future<List<SplitBill>> getAllSplitBills(String uid) async {
    await LocalStorage.init();
    final box = LocalStorage.splitBills;
    final results = <SplitBill>[];
    for (final k in box.keys) {
      if (k is String && k.startsWith('splitbill_${uid}_') && !k.startsWith('splitbill_expense_')) {
        try {
          final raw = box.get(k) as String?;
          if (raw == null) continue;
          final map = jsonDecode(raw) as Map<String, dynamic>;
          final id = k.replaceFirst('splitbill_${uid}_', '');
          results.add(SplitBill.fromMap(map, id));
        } catch (_) {}
      }
    }
    results.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return results;
  }
}
