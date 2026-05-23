import '../models/expense_group.dart';
import '../models/group_expense_item.dart';

abstract class ExpenseGroupRepository {
  Stream<List<ExpenseGroup>> getGroups(String userId);
  Future<String> addGroup(ExpenseGroup group);
  Future<void> updateGroup(ExpenseGroup group);
  Future<void> deleteGroup(String groupId);

  Stream<List<GroupExpenseItem>> getExpenses(String groupId);
  Future<String> addExpense(GroupExpenseItem expense);
  Future<void> updateExpense(GroupExpenseItem expense);
  Future<void> deleteExpense(String groupId, String expenseId);

  Future<void> storeInvite({
    required String hashedCode,
    required String groupId,
    required String createdBy,
    required DateTime expiresAt,
  });
  Future<Map<String, dynamic>?> resolveInvite(String hashedCode);
  Future<void> markInviteUsed(String hashedCode);
  Future<void> addMemberToGroup(String groupId, GroupMember member);
  Future<void> removeMemberFromGroup(String groupId, String userId);
}
