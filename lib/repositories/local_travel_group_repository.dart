import 'dart:math';

import 'package:hive/hive.dart';

import '../models/travel_expense.dart';
import '../models/travel_group.dart';
import 'local_storage.dart';
import 'travel_group_repository.dart';

class LocalTravelGroupRepository implements TravelGroupRepository {
  Box<dynamic> get _groups => LocalStorage.travelGroups;
  Box<dynamic> get _expenses => LocalStorage.travelExpenses;
  Box<dynamic> get _members => LocalStorage.travelMembers;

  String _newId() =>
      Random().nextInt(0x7FFFFFFF).toRadixString(16) +
      DateTime.now().millisecondsSinceEpoch.toRadixString(16);

  // ── Groups ──────────────────────────────────────────────────────────────────

  @override
  Stream<List<TravelGroup>> getGroups(String userId) async* {
    await LocalStorage.init();
    yield _readGroups(userId);
    yield* _groups.watch().map<List<TravelGroup>>((_) => _readGroups(userId));
  }

  List<TravelGroup> _readGroups(String userId) {
    return _groups.values
        .whereType<Map>()
        .map(
          (m) => TravelGroup.fromMap(
            Map<String, dynamic>.from(m),
            id: m['id'] as String,
          ),
        )
        .where((g) => g.ownerId == userId || g.memberIds.contains(userId))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<String> addGroup(String userId, TravelGroup group) async {
    await LocalStorage.init();
    final id = group.id.isEmpty ? _newId() : group.id;
    final saved = group.id == id ? group : group.copyWith(id: id);
    await _groups.put(id, saved.toMap(includeId: true));
    return id;
  }

  @override
  Future<void> updateGroup(TravelGroup group) async {
    await LocalStorage.init();
    await _groups.put(group.id, group.toMap(includeId: true));
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    await LocalStorage.init();
    await _groups.delete(groupId);
    // Cascade delete expenses and members
    final expenseKeys = _expenses.keys
        .where((k) => k.toString().startsWith('${groupId}_'))
        .toList();
    for (final k in expenseKeys) {
      await _expenses.delete(k);
    }
    final memberKeys = _members.keys
        .where((k) => k.toString().startsWith('${groupId}_'))
        .toList();
    for (final k in memberKeys) {
      await _members.delete(k);
    }
  }

  // ── Members ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<TravelGroupMember>> getMembers(String groupId) async* {
    await LocalStorage.init();
    yield _readMembers(groupId);
    yield* _members.watch().map<List<TravelGroupMember>>(
      (_) => _readMembers(groupId),
    );
  }

  List<TravelGroupMember> _readMembers(String groupId) {
    return _members.keys
        .where((k) => k.toString().startsWith('${groupId}_'))
        .map((k) {
          final m = _members.get(k);
          if (m == null) return null;
          final data = Map<String, dynamic>.from(m as Map);
          return TravelGroupMember.fromMap(data, id: data['id'] as String);
        })
        .whereType<TravelGroupMember>()
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  @override
  Future<String> addMember(String groupId, TravelGroupMember member) async {
    await LocalStorage.init();
    final id = member.id.isEmpty ? _newId() : member.id;
    final key = '${groupId}_$id';
    await _members.put(key, member.toMap(includeId: true)..['id'] = id);
    return id;
  }

  @override
  Future<void> updateMember(String groupId, TravelGroupMember member) async {
    await LocalStorage.init();
    final key = '${groupId}_${member.id}';
    await _members.put(key, member.toMap(includeId: true));
  }

  @override
  Future<void> removeMember(String groupId, String memberId) async {
    await LocalStorage.init();
    await _members.delete('${groupId}_$memberId');
  }

  // ── Expenses ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<TravelExpense>> getExpenses(String groupId) async* {
    await LocalStorage.init();
    yield _readExpenses(groupId);
    yield* _expenses.watch().map<List<TravelExpense>>(
      (_) => _readExpenses(groupId),
    );
  }

  List<TravelExpense> _readExpenses(String groupId) {
    return _expenses.keys
        .where((k) => k.toString().startsWith('${groupId}_'))
        .map((k) {
          final m = _expenses.get(k);
          if (m == null) return null;
          final data = Map<String, dynamic>.from(m as Map);
          return TravelExpense.fromMap(
            data,
            id: data['id'] as String,
            groupId: groupId,
          );
        })
        .whereType<TravelExpense>()
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<String> addExpense(String groupId, TravelExpense expense) async {
    await LocalStorage.init();
    final id = expense.id.isEmpty ? _newId() : expense.id;
    final key = '${groupId}_$id';
    await _expenses.put(key, expense.toMap(includeId: true)..['id'] = id);
    return id;
  }

  @override
  Future<void> updateExpense(String groupId, TravelExpense expense) async {
    await LocalStorage.init();
    final key = '${groupId}_${expense.id}';
    await _expenses.put(key, expense.toMap(includeId: true));
  }

  @override
  Future<void> deleteExpense(String groupId, String expenseId) async {
    await LocalStorage.init();
    await _expenses.delete('${groupId}_$expenseId');
  }

  // ── Invite Codes (not supported in local mode) ────────────────────────────────

  @override
  Future<void> storeInviteCode(
    String code,
    String ownerId,
    String groupId,
  ) async {}

  @override
  Future<String?> resolveInviteCode(String code) async => null;

  @override
  Future<String> joinByCode({
    required String code,
    required String userId,
    required String userName,
    String? userEmail,
  }) async {
    throw UnimplementedError('Join by code not supported in local mode');
  }

  // ── Email Invites (not supported in local mode) ───────────────────────────────

  @override
  Future<void> storeEmailInvite({
    required String email,
    required String groupId,
    required String ownerId,
  }) async {}

  @override
  Future<List<Map<String, String>>> fetchEmailInvites(String email) async => [];

  @override
  Future<void> deleteEmailInvite(String email, String groupId) async {}
}
