import '../models/travel_expense.dart';
import '../models/travel_group.dart';

abstract class TravelGroupRepository {
  // Groups — returns groups where userId is owner or member
  Stream<List<TravelGroup>> getGroups(String userId);
  Future<String> addGroup(String userId, TravelGroup group);
  Future<void> updateGroup(TravelGroup group);
  Future<void> deleteGroup(String groupId);

  // Members
  Stream<List<TravelGroupMember>> getMembers(String groupId);
  Future<String> addMember(String groupId, TravelGroupMember member);
  Future<void> updateMember(String groupId, TravelGroupMember member);
  Future<void> removeMember(String groupId, String memberId);

  // Expenses
  Stream<List<TravelExpense>> getExpenses(String groupId);
  Future<String> addExpense(String groupId, TravelExpense expense);
  Future<void> updateExpense(String groupId, TravelExpense expense);
  Future<void> deleteExpense(String groupId, String expenseId);
}
