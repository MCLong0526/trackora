import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/travel_expense.dart';
import '../models/travel_group.dart';
import 'travel_group_repository.dart';

/// Firestore paths:
///   users/{ownerId}/travelGroups/{groupId}
///   users/{ownerId}/travelGroups/{groupId}/members/{memberId}
///   users/{ownerId}/travelGroups/{groupId}/expenses/{expenseId}
class FirebaseTravelGroupRepository implements TravelGroupRepository {
  final FirebaseFirestore _db;

  /// groupId → ownerId cache, populated by getGroups / addGroup
  final _ownerCache = <String, String>{};

  FirebaseTravelGroupRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _groupsRef(String ownerId) =>
      _db.collection('users').doc(ownerId).collection('travelGroups');

  CollectionReference<Map<String, dynamic>> _membersRef(
          String ownerId, String groupId) =>
      _groupsRef(ownerId).doc(groupId).collection('members');

  CollectionReference<Map<String, dynamic>> _expensesRef(
          String ownerId, String groupId) =>
      _groupsRef(ownerId).doc(groupId).collection('expenses');

  String? _ownerOf(String groupId) => _ownerCache[groupId];

  // ── Groups ──────────────────────────────────────────────────────────────────

  @override
  Stream<List<TravelGroup>> getGroups(String userId) {
    return _groupsRef(userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) {
              _ownerCache[d.id] = userId;
              return TravelGroup.fromMap(d.data(), id: d.id);
            }).toList());
  }

  @override
  Future<String> addGroup(String userId, TravelGroup group) async {
    final data = _toFirestoreMap(group.toMap());
    if (group.id.isNotEmpty) {
      await _groupsRef(userId).doc(group.id).set(data);
      _ownerCache[group.id] = userId;
      return group.id;
    }
    final ref = await _groupsRef(userId).add(data);
    _ownerCache[ref.id] = userId;
    return ref.id;
  }

  @override
  Future<void> updateGroup(TravelGroup group) async {
    _ownerCache[group.id] = group.ownerId;
    await _groupsRef(group.ownerId)
        .doc(group.id)
        .update(_toFirestoreMap(group.toMap()));
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    final ownerId = _ownerOf(groupId);
    if (ownerId == null) return;
    await _deleteCollection(_membersRef(ownerId, groupId));
    await _deleteCollection(_expensesRef(ownerId, groupId));
    await _groupsRef(ownerId).doc(groupId).delete();
    _ownerCache.remove(groupId);
  }

  // ── Members ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<TravelGroupMember>> getMembers(String groupId) {
    final ownerId = _ownerOf(groupId);
    if (ownerId == null) return const Stream.empty();
    return _membersRef(ownerId, groupId)
        .orderBy('createdAt')
        .snapshots()
        .map((s) => s.docs
            .map((d) => TravelGroupMember.fromMap(d.data(), id: d.id))
            .toList());
  }

  @override
  Future<String> addMember(String groupId, TravelGroupMember member) async {
    final ownerId = _ownerOf(groupId);
    if (ownerId == null) throw StateError('Unknown owner for group $groupId');
    final data = _toFirestoreMap(member.toMap());
    if (member.id.isNotEmpty) {
      await _membersRef(ownerId, groupId).doc(member.id).set(data);
      return member.id;
    }
    final ref = await _membersRef(ownerId, groupId).add(data);
    return ref.id;
  }

  @override
  Future<void> updateMember(String groupId, TravelGroupMember member) async {
    final ownerId = _ownerOf(groupId);
    if (ownerId == null) return;
    await _membersRef(ownerId, groupId)
        .doc(member.id)
        .update(_toFirestoreMap(member.toMap()));
  }

  @override
  Future<void> removeMember(String groupId, String memberId) async {
    final ownerId = _ownerOf(groupId);
    if (ownerId == null) return;
    await _membersRef(ownerId, groupId).doc(memberId).delete();
  }

  // ── Expenses ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<TravelExpense>> getExpenses(String groupId) {
    final ownerId = _ownerOf(groupId);
    if (ownerId == null) return const Stream.empty();
    return _expensesRef(ownerId, groupId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) =>
                TravelExpense.fromMap(d.data(), id: d.id, groupId: groupId))
            .toList());
  }

  @override
  Future<String> addExpense(String groupId, TravelExpense expense) async {
    final ownerId = _ownerOf(groupId);
    if (ownerId == null) throw StateError('Unknown owner for group $groupId');
    final data = _toFirestoreMap(expense.toMap());
    if (expense.id.isNotEmpty) {
      await _expensesRef(ownerId, groupId).doc(expense.id).set(data);
      return expense.id;
    }
    final ref = await _expensesRef(ownerId, groupId).add(data);
    return ref.id;
  }

  @override
  Future<void> updateExpense(String groupId, TravelExpense expense) async {
    final ownerId = _ownerOf(groupId);
    if (ownerId == null) return;
    await _expensesRef(ownerId, groupId)
        .doc(expense.id)
        .update(_toFirestoreMap(expense.toMap()));
  }

  @override
  Future<void> deleteExpense(String groupId, String expenseId) async {
    final ownerId = _ownerOf(groupId);
    if (ownerId == null) return;
    await _expensesRef(ownerId, groupId).doc(expenseId).delete();
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _toFirestoreMap(Map<String, dynamic> map) {
    final result = Map<String, dynamic>.from(map);
    for (final key in result.keys.toList()) {
      final v = result[key];
      if (v is String) {
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
