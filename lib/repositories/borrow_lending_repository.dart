import '../models/borrow_lending.dart';

/// Storage-neutral contract for borrow / lending records. Mirrors the
/// shape of `ExpenseRepository` / `InstallmentRepository` so screens
/// can switch between local Hive and Firestore by changing
/// `app_config.dart`.
abstract class BorrowLendingRepository {
  Stream<List<BorrowLending>> getAll(String userId);

  Future<void> add(String userId, BorrowLending record);

  Future<void> update(String userId, BorrowLending record);

  Future<void> delete(String userId, String id);
}
