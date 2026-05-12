import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/precious_metal.dart';
import 'precious_metal_repository.dart';

class FirebasePreciousMetalRepository implements PreciousMetalRepository {
  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('precious_metals');

  @override
  Stream<List<PreciousMetal>> getAll(String userId) {
    return _col(userId)
        .orderBy('date', descending: true)
        .snapshots()
        .map(
          (snap) => snap.docs
              .map((d) => PreciousMetal.fromMap(d.data(), id: d.id))
              .toList(),
        );
  }

  @override
  Future<void> add(String userId, PreciousMetal metal) async {
    if (metal.id.isEmpty) {
      await _col(userId).add(metal.toMap());
    } else {
      await _col(userId).doc(metal.id).set(metal.toMap());
    }
  }

  @override
  Future<void> update(String userId, PreciousMetal metal) async {
    if (metal.id.isEmpty) return;
    await _col(userId).doc(metal.id).set(metal.toMap());
  }

  @override
  Future<void> delete(String userId, String id) async {
    await _col(userId).doc(id).delete();
  }

  Future<void> upsertById(String userId, PreciousMetal metal) async {
    await _col(userId)
        .doc(metal.id)
        .set(metal.toMap(), SetOptions(merge: true));
  }
}
