import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/person.dart';
import 'person_repository.dart';

class FirebasePersonRepository implements PersonRepository {
  CollectionReference<Map<String, dynamic>> _col(String userId) =>
      FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('people');

  @override
  Stream<List<Person>> getAll(String userId) {
    return _col(userId)
        .orderBy('name')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => Person.fromMap(d.data(), id: d.id))
            .toList());
  }

  @override
  Future<void> add(String userId, Person person) async {
    if (person.id.isEmpty) {
      await _col(userId).add(person.toMap());
    } else {
      await _col(userId).doc(person.id).set(person.toMap());
    }
  }

  @override
  Future<void> update(String userId, Person person) async {
    if (person.id.isEmpty) return;
    await _col(userId).doc(person.id).set(person.toMap());
  }

  @override
  Future<void> delete(String userId, String id) async {
    await _col(userId).doc(id).delete();
  }
}
