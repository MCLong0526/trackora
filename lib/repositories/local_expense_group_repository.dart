import 'dart:math';

import 'package:hive/hive.dart';

import '../models/expense_group.dart';
import '../models/group_expense_item.dart';
import 'expense_group_repository.dart';
import 'local_storage.dart';

class LocalExpenseGroupRepository implements ExpenseGroupRepository {
  Box<dynamic> get _groups => LocalStorage.expenseGroups;
  Box<dynamic> get _items => LocalStorage.expenseGroupItems;

  String _newId() =>
      Random().nextInt(0x7FFFFFFF).toRadixString(16) +
      DateTime.now().millisecondsSinceEpoch.toRadixString(16);

  // ── Groups ───────────────────────────────────────────────────────────────────

  @override
  Stream<List<ExpenseGroup>> getGroups(String userId) async* {
    await LocalStorage.init();
    yield _readGroups(userId);
    yield* _groups.watch().map<List<ExpenseGroup>>((_) => _readGroups(userId));
  }

  List<ExpenseGroup> _readGroups(String userId) {
    return _groups.values
        .whereType<Map>()
        .map(
          (m) => ExpenseGroup.fromMap(
            Map<String, dynamic>.from(m),
            id: m['id'] as String,
          ),
        )
        .where((g) => g.memberUids.contains(userId))
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<String> addGroup(ExpenseGroup group) async {
    await LocalStorage.init();
    final id = group.id.isEmpty ? _newId() : group.id;
    await _groups.put(id, group.toMap(includeId: true)..['id'] = id);
    return id;
  }

  @override
  Future<void> updateGroup(ExpenseGroup group) async {
    await LocalStorage.init();
    await _groups.put(group.id, group.toMap(includeId: true));
  }

  @override
  Future<void> deleteGroup(String groupId) async {
    await LocalStorage.init();
    final keys = _items.keys
        .where((k) => k.toString().startsWith('${groupId}_'))
        .toList();
    for (final k in keys) {
      await _items.delete(k);
    }
    await _groups.delete(groupId);
  }

  // ── Expenses ─────────────────────────────────────────────────────────────────

  @override
  Stream<List<GroupExpenseItem>> getExpenses(String groupId) async* {
    await LocalStorage.init();
    yield _readExpenses(groupId);
    yield* _items.watch().map<List<GroupExpenseItem>>(
      (_) => _readExpenses(groupId),
    );
  }

  List<GroupExpenseItem> _readExpenses(String groupId) {
    return _items.keys
        .where((k) => k.toString().startsWith('${groupId}_'))
        .map((k) {
          final m = _items.get(k);
          if (m == null) return null;
          final data = Map<String, dynamic>.from(m as Map);
          return GroupExpenseItem.fromMap(
            data,
            id: data['id'] as String,
            groupId: groupId,
          );
        })
        .whereType<GroupExpenseItem>()
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  @override
  Future<String> addExpense(GroupExpenseItem expense) async {
    await LocalStorage.init();
    final id = expense.id.isEmpty ? _newId() : expense.id;
    final key = '${expense.groupId}_$id';
    await _items.put(key, expense.toMap(includeId: true)..['id'] = id);
    return id;
  }

  @override
  Future<void> updateExpense(GroupExpenseItem expense) async {
    await LocalStorage.init();
    final key = '${expense.groupId}_${expense.id}';
    await _items.put(key, expense.toMap(includeId: true));
  }

  @override
  Future<void> deleteExpense(String groupId, String expenseId) async {
    await LocalStorage.init();
    await _items.delete('${groupId}_$expenseId');
  }

  // ── Invites (not supported in local mode) ────────────────────────────────────

  @override
  Future<void> storeInvite({
    required String hashedCode,
    required String groupId,
    required String createdBy,
    required DateTime expiresAt,
  }) async {}

  @override
  Future<Map<String, dynamic>?> resolveInvite(String hashedCode) async => null;

  @override
  Future<void> markInviteUsed(String hashedCode) async {}

  @override
  Future<void> addMemberToGroup(String groupId, GroupMember member) async {
    await LocalStorage.init();
    final raw = _groups.get(groupId);
    if (raw == null) return;
    final data = Map<String, dynamic>.from(raw as Map);
    final members = List<dynamic>.from(data['members'] as List? ?? []);
    members.add(member.toMap());
    final uids = List<String>.from(data['memberUids'] as List? ?? []);
    if (!uids.contains(member.uid)) uids.add(member.uid);
    data['members'] = members;
    data['memberUids'] = uids;
    data['updatedAt'] = DateTime.now().toIso8601String();
    await _groups.put(groupId, data);
  }

  @override
  Future<void> removeMemberFromGroup(String groupId, String userId) async {
    await LocalStorage.init();
    final raw = _groups.get(groupId);
    if (raw == null) return;
    final data = Map<String, dynamic>.from(raw as Map);
    final members = (data['members'] as List? ?? [])
        .where((m) => (m as Map)['uid'] != userId)
        .map((m) => Map<String, dynamic>.from(m as Map))
        .toList();
    final uids = List<String>.from(data['memberUids'] as List? ?? [])
      ..remove(userId);
    data['members'] = members;
    data['memberUids'] = uids;
    data['updatedAt'] = DateTime.now().toIso8601String();
    await _groups.put(groupId, data);
  }
}
