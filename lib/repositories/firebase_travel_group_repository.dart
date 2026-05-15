import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/travel_expense.dart';
import '../models/travel_group.dart';
import 'travel_group_repository.dart';

/// Firestore paths:
///   travelGroups/{groupId}
///   travelGroups/{groupId}/members/{memberId}
///   travelGroups/{groupId}/expenses/{expenseId}
class FirebaseTravelGroupRepository implements TravelGroupRepository {
  final FirebaseFirestore _db;

  FirebaseTravelGroupRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _groupsRef =>
      _db.collection('travelGroups');

  CollectionReference<Map<String, dynamic>> _membersRef(String groupId) =>
      _groupsRef.doc(groupId).collection('members');

  CollectionReference<Map<String, dynamic>> _expensesRef(String groupId) =>
      _groupsRef.doc(groupId).collection('expenses');

  // ── Groups ──────────────────────────────────────────────────────────────────

  @override
  Stream<List<TravelGroup>> getGroups(String userId) {
    // Returns groups where user is owner or member
    return _groupsRef
        .where('memberIds', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => TravelGroup.fromMap(d.data(), id: d.id))
            .toList());
  }

  @override
  Future<String> addGroup(String userId, TravelGroup group) async {
    final data = _toFirestoreMap(group.toMap());
    if (group.id.isNotEmpty) {
      await _groupsRef.doc(group.id).set(data);
      return group.id;
    }
    final ref = await _groupsRef.add(data);
    return ref.id;
  }

  @override
  Future<void> updateGroup(TravelGroup group) async {
    await _groupsRef.doc(group.id).update(_toFirestoreMap(group.toMap()));
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    // Delete subcollections first
    await _deleteCollection(_membersRef(groupId));
    await _deleteCollection(_expensesRef(groupId));
    await _groupsRef.doc(groupId).delete();
  }

  // ── Members ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<TravelGroupMember>> getMembers(String groupId) {
    return _membersRef(groupId)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs
            .map((d) => TravelGroupMember.fromMap(d.data(), id: d.id))
            .toList());
  }

  @override
  Future<String> addMember(String groupId, TravelGroupMember member) async {
    final data = _toFirestoreMap(member.toMap());
    if (member.id.isNotEmpty) {
      await _membersRef(groupId).doc(member.id).set(data);
      return member.id;
    }
    final ref = await _membersRef(groupId).add(data);
    return ref.id;
  }

  @override
  Future<void> updateMember(String groupId, TravelGroupMember member) async {
    await _membersRef(groupId)
        .doc(member.id)
        .update(_toFirestoreMap(member.toMap()));
  }

  @override
  Future<void> removeMember(String groupId, String memberId) async {
    await _membersRef(groupId).doc(memberId).delete();
  }

  // ── Expenses ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<TravelExpense>> getExpenses(String groupId) {
    return _expensesRef(groupId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) =>
                TravelExpense.fromMap(d.data(), id: d.id, groupId: groupId))
            .toList());
  }

  @override
  Future<String> addExpense(String groupId, TravelExpense expense) async {
    final data = _toFirestoreMap(expense.toMap());
    if (expense.id.isNotEmpty) {
      await _expensesRef(groupId).doc(expense.id).set(data);
      return expense.id;
    }
    final ref = await _expensesRef(groupId).add(data);
    return ref.id;
  }

  @override
  Future<void> updateExpense(String groupId, TravelExpense expense) async {
    await _expensesRef(groupId)
        .doc(expense.id)
        .update(_toFirestoreMap(expense.toMap()));
  }

  @override
  Future<void> deleteExpense(String groupId, String expenseId) async {
    await _expensesRef(groupId).doc(expenseId).delete();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _toFirestoreMap(Map<String, dynamic> map) {
    final result = Map<String, dynamic>.from(map);
    for (final key in result.keys.toList()) {
      final v = result[key];
      if (v is String) {
        // Convert ISO date strings to Firestore Timestamps
        final parsed = DateTime.tryParse(v);
        if (parsed != null) {
          result[key] = Timestamp.fromDate(parsed);
        }
      }
    }
    return result;
  }

  Future<void> _deleteCollection(
    CollectionReference<Map<String, dynamic>> ref,
  ) async {
    const batchSize = 100;
    QuerySnapshot snapshot = await ref.limit(batchSize).get();
    while (snapshot.docs.isNotEmpty) {
      final batch = _db.batch();
      for (final doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snapshot.docs.length < batchSize) break;
      snapshot = await ref.limit(batchSize).get();
    }
  }
}
