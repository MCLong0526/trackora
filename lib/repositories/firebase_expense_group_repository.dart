import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/expense_group.dart';
import '../models/group_expense_item.dart';
import 'expense_group_repository.dart';

/// Firestore paths (top-level so all members have equal access):
///   groups/{groupId}
///   groups/{groupId}/expenses/{expenseId}
///   groupInvites/{hashedCode}
class FirebaseExpenseGroupRepository implements ExpenseGroupRepository {
  final FirebaseFirestore _db;

  FirebaseExpenseGroupRepository({FirebaseFirestore? firestore})
      : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _groupsRef =>
      _db.collection('groups');

  CollectionReference<Map<String, dynamic>> _expensesRef(String groupId) =>
      _groupsRef.doc(groupId).collection('expenses');

  CollectionReference<Map<String, dynamic>> get _invitesRef =>
      _db.collection('groupInvites');

  // ── Groups ───────────────────────────────────────────────────────────────────

  @override
  Stream<List<ExpenseGroup>> getGroups(String userId) {
    return _groupsRef
        .where('memberUids', arrayContains: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) => ExpenseGroup.fromMap(d.data(), id: d.id))
            .toList());
  }

  @override
  Future<String> addGroup(ExpenseGroup group) async {
    final data = _toFirestoreMap(group.toMap());
    if (group.id.isNotEmpty) {
      await _groupsRef.doc(group.id).set(data);
      return group.id;
    }
    final ref = await _groupsRef.add(data);
    return ref.id;
  }

  @override
  Future<void> updateGroup(ExpenseGroup group) async {
    await _groupsRef.doc(group.id).update(_toFirestoreMap(group.toMap()));
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    await _deleteCollection(_expensesRef(groupId));
    await _groupsRef.doc(groupId).delete();
  }

  // ── Expenses ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<GroupExpenseItem>> getExpenses(String groupId) {
    return _expensesRef(groupId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs
            .map((d) =>
                GroupExpenseItem.fromMap(d.data(), id: d.id, groupId: groupId))
            .toList());
  }

  @override
  Future<String> addExpense(GroupExpenseItem expense) async {
    final data = _toFirestoreMap(expense.toMap());
    if (expense.id.isNotEmpty) {
      await _expensesRef(expense.groupId).doc(expense.id).set(data);
      return expense.id;
    }
    final ref = await _expensesRef(expense.groupId).add(data);
    return ref.id;
  }

  @override
  Future<void> updateExpense(GroupExpenseItem expense) async {
    await _expensesRef(expense.groupId)
        .doc(expense.id)
        .update(_toFirestoreMap(expense.toMap()));
  }

  @override
  Future<void> deleteExpense(String groupId, String expenseId) async {
    await _expensesRef(groupId).doc(expenseId).delete();
  }

  // ── Invites ──────────────────────────────────────────────────────────────────

  @override
  Future<void> storeInvite({
    required String hashedCode,
    required String groupId,
    required String createdBy,
    required DateTime expiresAt,
  }) async {
    await _invitesRef.doc(hashedCode).set({
      'groupId': groupId,
      'createdBy': createdBy,
      'expiresAt': Timestamp.fromDate(expiresAt),
      'used': false,
      'createdAt': Timestamp.now(),
    });
  }

  @override
  Future<Map<String, dynamic>?> resolveInvite(String hashedCode) async {
    final doc = await _invitesRef.doc(hashedCode).get();
    if (!doc.exists) return null;
    return doc.data();
  }

  @override
  Future<void> markInviteUsed(String hashedCode) async {
    await _invitesRef.doc(hashedCode).update({'used': true});
  }

  @override
  Future<void> addMemberToGroup(String groupId, GroupMember member) async {
    await _groupsRef.doc(groupId).update({
      'members': FieldValue.arrayUnion([member.toMap()]),
      'memberUids': FieldValue.arrayUnion([member.uid]),
      'updatedAt': Timestamp.now(),
    });
  }

  // ── Helpers ──────────────────────────────────────────────────────────────────

  Map<String, dynamic> _toFirestoreMap(Map<String, dynamic> map) {
    final result = Map<String, dynamic>.from(map);
    for (final key in result.keys.toList()) {
      final v = result[key];
      if (v is String) {
        final parsed = DateTime.tryParse(v);
        if (parsed != null) result[key] = Timestamp.fromDate(parsed);
      } else if (v is List) {
        result[key] = v.map((e) {
          if (e is Map) return _toFirestoreMap(Map<String, dynamic>.from(e));
          return e;
        }).toList();
      }
    }
    return result;
  }

  Future<void> _deleteCollection(
      CollectionReference<Map<String, dynamic>> ref) async {
    const batchSize = 100;
    var snapshot = await ref.limit(batchSize).get();
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
