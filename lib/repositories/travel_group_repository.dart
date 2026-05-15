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

  // Invite codes
  Future<void> storeInviteCode(String code, String ownerId, String groupId);
  Future<String> joinByCode({
    required String code,
    required String userId,
    required String userName,
    String? userEmail,
  });
  Future<String?> resolveInviteCode(String code); // returns groupId or null

  // Email invites (for auto-join when invitee signs in)
  Future<void> storeEmailInvite({required String email, required String groupId, required String ownerId});
  Future<List<Map<String, String>>> fetchEmailInvites(String email);
  Future<void> deleteEmailInvite(String email, String groupId);
}
