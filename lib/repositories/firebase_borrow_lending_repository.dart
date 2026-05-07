import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/borrow_lending.dart';
import 'borrow_lending_repository.dart';

/// Firestore-backed `BorrowLendingRepository`. Mirrors the layout used
/// by the existing expense / installment repositories — collection at
/// `users/{userId}/borrow_lending`.
///
/// Local mode is the default per `app_config.dart`. This implementation
/// is here so changing `storageMode` to `StorageMode.firebase` keeps
/// the same UI working without code changes.
class FirebaseBorrowLendingRepository implements BorrowLendingRepository {
  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('borrow_lending');

  @override
  Stream<List<BorrowLending>> getAll(String userId) {
    return _col(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => BorrowLending.fromMap(d.data(), id: d.id))
            .toList());
  }

  @override
  Future<void> add(String userId, BorrowLending record) async {
    await _col(userId).add(record.toMap());
  }

  @override
  Future<void> update(String userId, BorrowLending record) async {
    if (record.id.isEmpty) return;
    await _col(userId).doc(record.id).set(record.toMap());
  }

  @override
  Future<void> delete(String userId, String id) async {
    await _col(userId).doc(id).delete();
  }

  Future<void> upsertById(String userId, BorrowLending record) async {
    await _col(userId)
        .doc(record.id)
        .set(record.toMap(), SetOptions(merge: true));
  }
}
