import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/saving_plan.dart';
import 'saving_plan_repository.dart';

/// Firestore-backed `SavingPlanRepository`.
/// Collection: `users/{userId}/saving_plans`. Contributions live inline
/// on the document (matches the local Hive layout).
class FirebaseSavingPlanRepository implements SavingPlanRepository {
  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('saving_plans');

  @override
  Stream<List<SavingPlan>> getAll(String userId) {
    return _col(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => SavingPlan.fromMap(d.data(), id: d.id))
            .toList());
  }

  @override
  Future<void> add(String userId, SavingPlan plan) async {
    await _col(userId).add(plan.toMap());
  }

  @override
  Future<void> update(String userId, SavingPlan plan) async {
    if (plan.id.isEmpty) return;
    await _col(userId).doc(plan.id).set(plan.toMap());
  }

  @override
  Future<void> delete(String userId, String id) async {
    await _col(userId).doc(id).delete();
  }
}
