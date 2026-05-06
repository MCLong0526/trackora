import '../models/account.dart';

abstract class AccountRepository {
  Stream<List<Account>> getAll(String userId);

  Future<void> add(String userId, Account account);

  Future<void> update(String userId, Account account);

  Future<void> delete(String userId, String accountId);
}
