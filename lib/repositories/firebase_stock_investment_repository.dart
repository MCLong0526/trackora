import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/stock_investment.dart';
import 'stock_investment_repository.dart';

class FirebaseStockInvestmentRepository implements StockInvestmentRepository {
  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('stock_investments');

  @override
  Stream<List<StockInvestment>> getAll(String userId) {
    return _col(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => StockInvestment.fromMap(d.data(), id: d.id))
            .toList());
  }

  @override
  Future<void> add(String userId, StockInvestment investment) async {
    if (investment.id.isEmpty) {
      await _col(userId).add(investment.toMap());
    } else {
      await _col(userId).doc(investment.id).set(investment.toMap());
    }
  }

  @override
  Future<void> update(String userId, StockInvestment investment) async {
    if (investment.id.isEmpty) return;
    await _col(userId).doc(investment.id).set(investment.toMap());
  }

  @override
  Future<void> delete(String userId, String id) async {
    await _col(userId).doc(id).delete();
  }
}
