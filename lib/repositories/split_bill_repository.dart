import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/split_bill.dart';

class SplitBillRepository {
  final FirebaseFirestore _db;

  SplitBillRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _ref(String uid) =>
      _db.collection('users').doc(uid).collection('splitBills');

  Future<String> saveSplitBill(String uid, SplitBill bill) async {
    final doc = await _ref(uid).add(bill.toMap());
    return doc.id;
  }

  Future<void> updateSplitBill(String uid, SplitBill bill) async {
    await _ref(uid).doc(bill.id).update(bill.toMap());
  }

  Future<SplitBill?> getSplitBillByExpenseId(String uid, String expenseId) async {
    final snap = await _ref(uid)
        .where('expenseId', isEqualTo: expenseId)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    final doc = snap.docs.first;
    return SplitBill.fromMap(doc.data(), doc.id);
  }

  Stream<List<SplitBill>> watchSplitBills(String uid) {
    return _ref(uid)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => SplitBill.fromMap(d.data(), d.id))
            .toList());
  }
}
