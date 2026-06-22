import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/custom_category.dart';
import 'custom_category_repository.dart';

class FirebaseCustomCategoryRepository implements CustomCategoryRepository {
  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('categories');

  @override
  Stream<List<CustomCategory>> getAll(String userId) {
    return _col(userId).snapshots().map((snap) => snap.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          final c = data['createdAt'];
          if (c is Timestamp) data['createdAt'] = c.toDate();
          final u = data['updatedAt'];
          if (u is Timestamp) data['updatedAt'] = u.toDate();
          return CustomCategory.fromMap(data, id: d.id);
        }).toList());
  }

  @override
  Future<void> add(String userId, CustomCategory category) async {
    if (category.id.isEmpty) {
      await _col(userId).add(category.toMap());
    } else {
      await _col(userId).doc(category.id).set(category.toMap());
    }
  }

  @override
  Future<void> update(String userId, CustomCategory category) async {
    if (category.id.isEmpty) return;
    await _col(userId).doc(category.id).set(category.toMap());
  }

  Future<void> upsert(String userId, CustomCategory category) async {
    if (category.id.isEmpty) {
      await add(userId, category);
      return;
    }
    await _col(userId)
        .doc(category.id)
        .set(category.toMap(), SetOptions(merge: true));
  }

  @override
  Future<void> delete(String userId, String id) async {
    await _col(userId).doc(id).delete();
  }
}
