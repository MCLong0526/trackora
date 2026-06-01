import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

import '../models/expense_group.dart';
import '../models/group_expense_item.dart';
import '../repositories/expense_group_repository.dart';

class GroupMemberBalance {
  final String uid;
  final String displayName;
  final double totalPaid;
  final double totalShare;
  double get net => totalPaid - totalShare;

  const GroupMemberBalance({
    required this.uid,
    required this.displayName,
    required this.totalPaid,
    required this.totalShare,
  });
}

class GroupSettlementTx {
  final String fromUid;
  final String fromName;
  final String toUid;
  final String toName;
  final double amount;

  const GroupSettlementTx({
    required this.fromUid,
    required this.fromName,
    required this.toUid,
    required this.toName,
    required this.amount,
  });
}

class ExpenseGroupService {
  final ExpenseGroupRepository _repo;

  ExpenseGroupService(this._repo);

  // ── Groups ───────────────────────────────────────────────────────────────────

  Stream<List<ExpenseGroup>> getGroups(String userId) =>
      _repo.getGroups(userId);

  Future<String> createGroup({
    required String userId,
    required String displayName,
    required String groupName,
    String currency = 'USD',
  }) async {
    final now = DateTime.now();
    final self = GroupMember(
      uid: userId,
      displayName: displayName,
      joinedAt: now,
    );
    final group = ExpenseGroup(
      id: '',
      name: groupName,
      createdBy: userId,
      members: [self],
      memberUids: [userId],
      currency: currency,
      createdAt: now,
      updatedAt: now,
    );
    return _repo.addGroup(group);
  }

  Future<void> updateGroupName(ExpenseGroup group, String newName) =>
      _repo.updateGroup(group.copyWith(
        name: newName,
        updatedAt: DateTime.now(),
      ));

  Future<void> deleteGroup(String groupId) => _repo.deleteGroup(groupId);

  Future<void> leaveGroup(String groupId, String userId) =>
      _repo.removeMemberFromGroup(groupId, userId);

  // ── Invite codes ─────────────────────────────────────────────────────────────

  /// Generates a 6-char raw code like `A3X8B2`.
  /// Display splits it into `ABC·DEF` grouping.
  String generateRawCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  String hashInviteCode(String rawCode) {
    final bytes = utf8.encode(rawCode.toUpperCase());
    return sha256.convert(bytes).toString();
  }

  Future<void> createInvite({
    required String rawCode,
    required String groupId,
    required String createdBy,
  }) async {
    final hashed = hashInviteCode(rawCode);
    await _repo.storeInvite(
      hashedCode: hashed,
      groupId: groupId,
      createdBy: createdBy,
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
  }

  /// Returns the groupId if valid, null otherwise.
  Future<String?> validateInvite(String rawCode) async {
    final hashed = hashInviteCode(rawCode);
    final data = await _repo.resolveInvite(hashed);
    if (data == null) return null;
    if (data['used'] == true) return null;
    final expiresAt = ExpenseGroup.readDate(data['expiresAt']);
    if (DateTime.now().isAfter(expiresAt)) return null;
    return data['groupId'] as String?;
  }

  Future<String> joinGroup({
    required String rawCode,
    required String userId,
    required String displayName,
  }) async {
    final hashed = hashInviteCode(rawCode);
    final data = await _repo.resolveInvite(hashed);
    if (data == null) throw Exception('Invalid invite code');
    if (data['used'] == true) throw Exception('Invite code already used');
    final expiresAt = ExpenseGroup.readDate(data['expiresAt']);
    if (DateTime.now().isAfter(expiresAt)) throw Exception('Invite code expired');

    final groupId = data['groupId'] as String;
    final member = GroupMember(
      uid: userId,
      displayName: displayName,
      joinedAt: DateTime.now(),
    );
    await _repo.addMemberToGroup(groupId, member);
    await _repo.markInviteUsed(hashed);
    return groupId;
  }

  // ── Expenses ─────────────────────────────────────────────────────────────────

  Stream<List<GroupExpenseItem>> getExpenses(String groupId) =>
      _repo.getExpenses(groupId);

  Future<String> addExpense(GroupExpenseItem expense) => _repo.addExpense(expense);

  Future<void> updateExpense(GroupExpenseItem expense) =>
      _repo.updateExpense(expense.copyWith(updatedAt: DateTime.now()));

  Future<void> deleteExpense(String groupId, String expenseId) =>
      _repo.deleteExpense(groupId, expenseId);

  // ── Settlement ───────────────────────────────────────────────────────────────

  List<GroupMemberBalance> computeBalances(
    List<GroupMember> members,
    List<GroupExpenseItem> expenses,
  ) {
    final paid = <String, double>{};
    final owed = <String, double>{};
    for (final m in members) {
      paid[m.uid] = 0;
      owed[m.uid] = 0;
    }
    for (final e in expenses) {
      paid[e.paidBy] = (paid[e.paidBy] ?? 0) + e.amount;
      if (e.splitPercents != null && e.splitPercents!.isNotEmpty) {
        for (final entry in e.splitPercents!.entries) {
          final share = e.amount * (entry.value / 100.0);
          owed[entry.key] = (owed[entry.key] ?? 0) + share;
        }
      } else if (e.splitBetween.isNotEmpty) {
        final share = e.amount / e.splitBetween.length;
        for (final uid in e.splitBetween) {
          owed[uid] = (owed[uid] ?? 0) + share;
        }
      }
    }
    return members
        .map((m) => GroupMemberBalance(
              uid: m.uid,
              displayName: m.displayName,
              totalPaid: paid[m.uid] ?? 0,
              totalShare: owed[m.uid] ?? 0,
            ))
        .toList();
  }

  List<GroupSettlementTx> computeSettlement(
      List<GroupMemberBalance> balances) {
    // Greedy debt minimization
    final debtors = balances.where((b) => b.net < -0.005).toList()
      ..sort((a, b) => a.net.compareTo(b.net));
    final creditors = balances.where((b) => b.net > 0.005).toList()
      ..sort((a, b) => b.net.compareTo(a.net));

    final transactions = <GroupSettlementTx>[];
    int di = 0, ci = 0;
    final debts = debtors.map((b) => -b.net).toList();
    final credits = creditors.map((b) => b.net).toList();

    while (di < debtors.length && ci < creditors.length) {
      final amt = debts[di] < credits[ci] ? debts[di] : credits[ci];
      if (amt > 0.005) {
        transactions.add(GroupSettlementTx(
          fromUid: debtors[di].uid,
          fromName: debtors[di].displayName,
          toUid: creditors[ci].uid,
          toName: creditors[ci].displayName,
          amount: double.parse(amt.toStringAsFixed(2)),
        ));
      }
      debts[di] -= amt;
      credits[ci] -= amt;
      if (debts[di] < 0.005) di++;
      if (credits[ci] < 0.005) ci++;
    }
    return transactions;
  }
}
