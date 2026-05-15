import 'dart:math';

import '../models/travel_expense.dart';
import '../models/travel_group.dart';
import '../repositories/travel_group_repository.dart';

class MemberBalance {
  final String memberId;
  final String memberName;
  final double totalPaid;
  final double totalShare;
  double get net => totalPaid - totalShare;

  const MemberBalance({
    required this.memberId,
    required this.memberName,
    required this.totalPaid,
    required this.totalShare,
  });
}

class SettlementTransaction {
  final String fromMemberId;
  final String fromMemberName;
  final String toMemberId;
  final String toMemberName;
  final double amount;

  const SettlementTransaction({
    required this.fromMemberId,
    required this.fromMemberName,
    required this.toMemberId,
    required this.toMemberName,
    required this.amount,
  });
}

class TravelSettlement {
  final double totalSpent;
  final List<MemberBalance> balances;
  final List<SettlementTransaction> transactions;

  const TravelSettlement({
    required this.totalSpent,
    required this.balances,
    required this.transactions,
  });
}

class TravelGroupService {
  final TravelGroupRepository _repo;

  TravelGroupService(this._repo);

  // ── Groups ──────────────────────────────────────────────────────────────────

  Stream<List<TravelGroup>> getGroups(String userId) =>
      _repo.getGroups(userId);

  Future<String> createGroup({
    required String userId,
    required String name,
    required String currency,
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final now = DateTime.now();
    final inviteCode = _generateInviteCode();
    final group = TravelGroup(
      id: '',
      name: name,
      currency: currency,
      startDate: startDate,
      endDate: endDate,
      ownerId: userId,
      memberIds: [userId],
      inviteCode: inviteCode,
      createdAt: now,
      updatedAt: now,
    );
    return _repo.addGroup(userId, group);
  }

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rand = Random.secure();
    return List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
  }

  Future<void> updateGroup(TravelGroup group) =>
      _repo.updateGroup(group.copyWith(updatedAt: DateTime.now()));

  Future<void> deleteGroup(String groupId) => _repo.deleteGroup(groupId);

  // ── Members ─────────────────────────────────────────────────────────────────

  Stream<List<TravelGroupMember>> getMembers(String groupId) =>
      _repo.getMembers(groupId);

  Future<String> addMember({
    required String groupId,
    required TravelGroup group,
    required String name,
    String? userId,
    String? email,
  }) async {
    final member = TravelGroupMember(
      id: '',
      name: name,
      userId: userId,
      email: email,
      status: MemberStatus.active,
      createdAt: DateTime.now(),
    );
    final memberId = await _repo.addMember(groupId, member);

    // If linked to a user, add userId to group's memberIds
    if (userId != null && !group.memberIds.contains(userId)) {
      final updated = group.copyWith(
        memberIds: [...group.memberIds, userId],
        updatedAt: DateTime.now(),
      );
      await _repo.updateGroup(updated);
    }
    return memberId;
  }

  Future<void> updateMember(String groupId, TravelGroupMember member) =>
      _repo.updateMember(groupId, member);

  Future<void> removeMember(
    String groupId,
    TravelGroup group,
    String memberId,
    String? linkedUserId,
  ) async {
    await _repo.removeMember(groupId, memberId);
    if (linkedUserId != null && linkedUserId != group.ownerId) {
      final updated = group.copyWith(
        memberIds: group.memberIds.where((id) => id != linkedUserId).toList(),
        updatedAt: DateTime.now(),
      );
      await _repo.updateGroup(updated);
    }
  }

  // ── Expenses ─────────────────────────────────────────────────────────────────

  Stream<List<TravelExpense>> getExpenses(String groupId) =>
      _repo.getExpenses(groupId);

  Future<String> addExpense({
    required String groupId,
    required String addedByUserId,
    required double amount,
    required String description,
    required String category,
    required DateTime date,
    required String paidByMemberId,
    required List<String> splitAmong,
    String? notes,
    String? receiptUrl,
    Map<String, double>? splitAmounts,
    String? splitMode,
  }) async {
    final now = DateTime.now();
    final expense = TravelExpense(
      id: '',
      groupId: groupId,
      amount: amount,
      description: description,
      category: category,
      date: date,
      paidByMemberId: paidByMemberId,
      splitAmong: splitAmong,
      notes: notes,
      receiptUrl: receiptUrl,
      addedByUserId: addedByUserId,
      createdAt: now,
      updatedAt: now,
      splitAmounts: splitAmounts,
      splitMode: splitMode,
    );
    return _repo.addExpense(groupId, expense);
  }

  Future<void> updateExpense(String groupId, TravelExpense expense) =>
      _repo.updateExpense(groupId, expense.copyWith(updatedAt: DateTime.now()));

  Future<void> deleteExpense(String groupId, String expenseId) =>
      _repo.deleteExpense(groupId, expenseId);

  Future<String> joinByCode({
    required String code,
    required String userId,
    required String userName,
    String? userEmail,
  }) async {
    return _repo.joinByCode(
      code: code,
      userId: userId,
      userName: userName,
      userEmail: userEmail,
    );
  }

  Future<void> storeEmailInvite({
    required String email,
    required String groupId,
    required String ownerId,
  }) => _repo.storeEmailInvite(email: email, groupId: groupId, ownerId: ownerId);

  /// Called on sign-in: auto-join any groups the user was invited to by email.
  /// Returns list of groupIds joined.
  Future<List<String>> processEmailInvites({
    required String userEmail,
    required String userId,
    required String userName,
  }) async {
    final invites = await _repo.fetchEmailInvites(userEmail);
    final joined = <String>[];
    for (final invite in invites) {
      try {
        final groupId = invite['groupId']!;
        // Find the member doc that has this email and update it with userId
        final members = await _repo.getMembers(groupId).first;
        final match = members.where((m) => m.email == userEmail && m.userId == null).toList();
        if (match.isNotEmpty) {
          await _repo.updateMember(groupId, match.first.copyWith(userId: userId));
        }
        await _repo.deleteEmailInvite(userEmail, groupId);
        joined.add(groupId);
      } catch (_) {}
    }
    return joined;
  }

  // ── Settlement Calculation ────────────────────────────────────────────────────

  /// Calculates who owes whom using greedy debt minimization.
  TravelSettlement calculateSettlement(
    List<TravelGroupMember> members,
    List<TravelExpense> expenses,
  ) {
    final totalSpent = expenses.fold<double>(0, (sum, e) => sum + e.amount);

    // Build member lookup
    final memberMap = {for (final m in members) m.id: m};

    // Calculate net balance for each member
    final paidMap = <String, double>{};
    final shareMap = <String, double>{};

    for (final m in members) {
      paidMap[m.id] = 0;
      shareMap[m.id] = 0;
    }

    for (final expense in expenses) {
      paidMap[expense.paidByMemberId] =
          (paidMap[expense.paidByMemberId] ?? 0) + expense.amount;

      if (expense.splitAmounts != null && expense.splitAmounts!.isNotEmpty) {
        for (final entry in expense.splitAmounts!.entries) {
          shareMap[entry.key] = (shareMap[entry.key] ?? 0) + entry.value;
        }
      } else if (expense.splitAmong.isNotEmpty) {
        final share = expense.amount / expense.splitAmong.length;
        for (final memberId in expense.splitAmong) {
          shareMap[memberId] = (shareMap[memberId] ?? 0) + share;
        }
      }
    }

    final balances = members.map((m) {
      return MemberBalance(
        memberId: m.id,
        memberName: m.name,
        totalPaid: paidMap[m.id] ?? 0,
        totalShare: shareMap[m.id] ?? 0,
      );
    }).toList();

    // Greedy debt minimization algorithm
    final transactions = _minimizeTransactions(balances, memberMap);

    return TravelSettlement(
      totalSpent: totalSpent,
      balances: balances,
      transactions: transactions,
    );
  }

  List<SettlementTransaction> _minimizeTransactions(
    List<MemberBalance> balances,
    Map<String, TravelGroupMember> memberMap,
  ) {
    // Separate into creditors (net > 0) and debtors (net < 0)
    final creditors = balances
        .where((b) => b.net > 0.005)
        .map((b) => _MutableBalance(b.memberId, b.net))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final debtors = balances
        .where((b) => b.net < -0.005)
        .map((b) => _MutableBalance(b.memberId, b.net.abs()))
        .toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));

    final transactions = <SettlementTransaction>[];

    int ci = 0;
    int di = 0;

    while (ci < creditors.length && di < debtors.length) {
      final creditor = creditors[ci];
      final debtor = debtors[di];

      final payment = min(creditor.amount, debtor.amount);

      if (payment > 0.005) {
        transactions.add(SettlementTransaction(
          fromMemberId: debtor.memberId,
          fromMemberName: memberMap[debtor.memberId]?.name ?? debtor.memberId,
          toMemberId: creditor.memberId,
          toMemberName: memberMap[creditor.memberId]?.name ?? creditor.memberId,
          amount: payment,
        ));
      }

      creditor.amount -= payment;
      debtor.amount -= payment;

      if (creditor.amount < 0.005) ci++;
      if (debtor.amount < 0.005) di++;
    }

    return transactions;
  }
}

class _MutableBalance {
  final String memberId;
  double amount;
  _MutableBalance(this.memberId, this.amount);
}
