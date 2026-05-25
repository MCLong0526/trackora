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
        .snapshots()
        .map((s) {
          final groups = s.docs
              .map((d) => ExpenseGroup.fromMap(d.data(), id: d.id))
              .toList();
          // Sort client-side to avoid requiring a composite Firestore index
          groups.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          return groups;
        });
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
    try {
      await _deleteCollection(_expensesRef(groupId));
      await _groupsRef.doc(groupId).delete();
    } on FirebaseException catch (e) {
      if (e.code == 'not-found' || e.code == 'permission-denied') return;
      rethrow;
    }
  }

  // ── Expenses ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<GroupExpenseItem>> getExpenses(String groupId) {
    return _expensesRef(groupId).snapshots().map((s) {
      final items = s.docs
          .map((d) =>
              GroupExpenseItem.fromMap(d.data(), id: d.id, groupId: groupId))
          .toList();
      items.sort((a, b) => b.date.compareTo(a.date));
      return items;
    });
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

  @override
  Future<void> removeMemberFromGroup(String groupId, String userId) async {
    final docRef = _groupsRef.doc(groupId);

    // Try to read the doc. If the read itself fails (offline + no cache, or
    // permission-denied because the doc is gone server-side and stale rules),
    // treat it as a soft success — the group no longer exists from the user's
    // perspective, so "leaving" is effectively done.
    DocumentSnapshot<Map<String, dynamic>> doc;
    try {
      doc = await docRef.get();
    } on FirebaseException catch (e) {
      if (e.code == 'not-found' || e.code == 'permission-denied') return;
      rethrow;
    }
    if (!doc.exists) return;
    final data = doc.data();
    if (data == null) return;

    // Defensively rebuild the members list: nested maps can come back as
    // either Map<String, dynamic> or Map<Object?, Object?> depending on the
    // platform/codec, and joinedAt may be a Timestamp (set via addGroup's
    // _toFirestoreMap) or an ISO string (set via addMemberToGroup's
    // arrayUnion). We preserve whatever value is there and just drop the
    // leaver's entry by matching uid.
    final rawMembers = (data['members'] as List?) ?? const [];
    final newMembers = <Map<String, dynamic>>[];
    for (final m in rawMembers) {
      if (m is! Map) continue;
      final uid = m['uid'];
      if (uid is String && uid == userId) continue;
      newMembers.add(_coerceStringKeyedMap(m));
    }

    // No members remain — delete the group so the stream emits empty immediately.
    // Only the creator can delete per Firestore rules; non-creators fall through
    // to the memberUids update so the query stops matching and they leave cleanly.
    if (newMembers.isEmpty) {
      final isCreator = (data['createdBy'] as String?) == userId;
      if (isCreator) {
        try {
          await _deleteCollection(_expensesRef(groupId));
          await docRef.delete();
        } on FirebaseException catch (e) {
          if (e.code == 'not-found' || e.code == 'permission-denied') return;
          rethrow;
        }
        return;
      }
      // Non-creator: fall through to memberUids update so query stops matching.
    }

    try {
      await docRef.update({
        'members': newMembers,
        'memberUids': FieldValue.arrayRemove([userId]),
        'updatedAt': Timestamp.now(),
      });
    } on FirebaseException catch (e) {
      // If the server doc is gone (cache-only ghost) or our rule check fails
      // because memberUids is already stale, swallow the error so the caller
      // can still clear local state and the user perceives a successful leave.
      if (e.code == 'not-found' || e.code == 'permission-denied') return;
      rethrow;
    }
  }

  /// Recursively converts a [Map] (possibly with non-String keys, as some
  /// Firestore codecs return) into a Firestore-writable [Map<String, dynamic>].
  Map<String, dynamic> _coerceStringKeyedMap(Map source) {
    final out = <String, dynamic>{};
    source.forEach((k, v) {
      final key = k is String ? k : k.toString();
      if (v is Map) {
        out[key] = _coerceStringKeyedMap(v);
      } else if (v is List) {
        out[key] = v
            .map((e) => e is Map ? _coerceStringKeyedMap(e) : e)
            .toList();
      } else {
        out[key] = v;
      }
    });
    return out;
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
