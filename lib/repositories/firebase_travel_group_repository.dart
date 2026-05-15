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

  CollectionReference<Map<String, dynamic>> _codesRef() =>
      _db.collection('travelInviteCodes');

  CollectionReference<Map<String, dynamic>> _emailInvitesRef() =>
      _db.collection('travelEmailInvites');

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
              // Use ownerId from doc data — joined groups have a different ownerId
              final ownerId = (d.data()['ownerId'] as String?) ?? userId;
              _ownerCache[d.id] = ownerId;
              return TravelGroup.fromMap(d.data(), id: d.id);
            }).toList());
  }

  @override
  Future<String> addGroup(String userId, TravelGroup group) async {
    final data = _toFirestoreMap(group.toMap());
    if (group.id.isNotEmpty) {
      await _groupsRef(userId).doc(group.id).set(data);
      _ownerCache[group.id] = userId;
      if (group.inviteCode != null) {
        try { await storeInviteCode(group.inviteCode!, userId, group.id, data); } catch (_) {}
      }
      return group.id;
    }
    final ref = await _groupsRef(userId).add(data);
    _ownerCache[ref.id] = userId;
    if (group.inviteCode != null) {
      try { await storeInviteCode(group.inviteCode!, userId, ref.id, data); } catch (_) {}
    }
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

  // ── Invite Codes ─────────────────────────────────────────────────────────────

  @override
  Future<void> storeInviteCode(String code, String ownerId, String groupId,
      [Map<String, dynamic>? groupData]) async {
    await _codesRef().doc(code).set({
      'ownerId': ownerId,
      'groupId': groupId,
      'createdAt': Timestamp.now(),
      'groupData': groupData,
    });
  }

  @override
  Future<String?> resolveInviteCode(String code) async {
    final doc = await _codesRef().doc(code).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    final ownerId = data['ownerId'] as String;
    final groupId = data['groupId'] as String;
    _ownerCache[groupId] = ownerId;
    return groupId;
  }

  @override
  Future<String> joinByCode({
    required String code,
    required String userId,
    required String userName,
    String? userEmail,
  }) async {
    final doc = await _codesRef().doc(code).get();
    if (!doc.exists) throw StateError('Invalid invite code');
    final codeData = doc.data()!;
    final ownerId = codeData['ownerId'] as String;
    final groupId = codeData['groupId'] as String;
    _ownerCache[groupId] = ownerId;

    // Check if user is already a member — skip gracefully if read is denied
    try {
      final membersSnap = await _membersRef(ownerId, groupId)
          .where('userId', isEqualTo: userId)
          .get();
      if (membersSnap.docs.isNotEmpty) {
        // Already a member — just ensure joiner has the group in their space
        await _writeGroupStubToJoiner(
            userId: userId, ownerId: ownerId, groupId: groupId, codeData: codeData);
        return membersSnap.docs.first.id;
      }
    } catch (_) {
      // Not yet a member or read denied — proceed to add
    }

    // Add member (self-registration rule allows this)
    final member = TravelGroupMember(
      id: '',
      name: userName,
      userId: userId,
      email: userEmail,
      status: MemberStatus.active,
      createdAt: DateTime.now(),
    );
    final ref = await _membersRef(ownerId, groupId)
        .add(_toFirestoreMap(member.toMap()));

    // Add userId to group memberIds via arrayUnion (no read required)
    await _groupsRef(ownerId).doc(groupId).update({
      'memberIds': FieldValue.arrayUnion([userId]),
      'updatedAt': Timestamp.now(),
    });

    // Write group stub to joiner's own travelGroups so getGroups() finds it
    await _writeGroupStubToJoiner(
        userId: userId, ownerId: ownerId, groupId: groupId, codeData: codeData);

    return ref.id;
  }

  /// Writes a copy of the group document under the joiner's travelGroups path
  /// so that getGroups(joinerId) returns it. The stub retains the real ownerId
  /// so _ownerCache is populated correctly.
  Future<void> _writeGroupStubToJoiner({
    required String userId,
    required String ownerId,
    required String groupId,
    required Map<String, dynamic> codeData,
  }) async {
    // Try to use the full group data stored in the code doc first
    final stored = codeData['groupData'] as Map<String, dynamic>?;
    Map<String, dynamic> groupData;
    if (stored != null) {
      groupData = Map<String, dynamic>.from(stored);
    } else {
      // Fallback: read from owner's path (now allowed since user is in memberIds)
      try {
        final snap = await _groupsRef(ownerId).doc(groupId).get();
        groupData = snap.data() ?? {};
      } catch (_) {
        return;
      }
    }
    // Write to the joiner's own path so their getGroups() stream finds it
    await _groupsRef(userId).doc(groupId).set(groupData);
    _ownerCache[groupId] = ownerId;
  }

  // ── Email Invites ─────────────────────────────────────────────────────────────

  @override
  Future<void> storeEmailInvite({required String email, required String groupId, required String ownerId}) async {
    final docId = '${email}_$groupId'.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    await _emailInvitesRef().doc(docId).set({
      'email': email,
      'groupId': groupId,
      'ownerId': ownerId,
      'createdAt': Timestamp.now(),
    });
    _ownerCache[groupId] = ownerId;
  }

  @override
  Future<List<Map<String, String>>> fetchEmailInvites(String email) async {
    final snap = await _emailInvitesRef().where('email', isEqualTo: email).get();
    return snap.docs.map((d) {
      final data = d.data();
      return {
        'groupId': data['groupId'] as String,
        'ownerId': data['ownerId'] as String,
      };
    }).toList();
  }

  @override
  Future<void> deleteEmailInvite(String email, String groupId) async {
    final docId = '${email}_$groupId'.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    await _emailInvitesRef().doc(docId).delete();
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
