import '../models/borrow_lending.dart';
import '../repositories/borrow_lending_repository.dart';
import '../repositories/local_borrow_lending_repository.dart';
import 'sync_service.dart';

/// Thin orchestration layer over [BorrowLendingRepository]. Adds the
/// little bits of business logic that don't belong on the model
/// (repayment + cancel + delete helpers).
class BorrowLendingService {
  final BorrowLendingRepository _repo;
  BorrowLendingService(this._repo);

  Stream<List<BorrowLending>> getAll(String userId) => _repo.getAll(userId);

  Future<void> add(String userId, BorrowLending record) =>
      _repo.add(userId, record);

  Future<void> update(String userId, BorrowLending record) =>
      _repo.update(userId, record);

  Future<void> delete(String userId, String id) async {
    await _repo.delete(userId, id);
    await LocalBorrowLendingRepository().delete(userId, id);
    await SyncService.markEntityPendingDelete(userId, 'bl', id);
  }

  /// Append a partial repayment. Caller passes a fully formed
  /// [BorrowLendingRepayment] (so the screen can decide id / date).
  /// `updatedAt` is bumped so the list re-sorts correctly.
  Future<void> addRepayment(
    String userId,
    BorrowLending record,
    BorrowLendingRepayment repayment,
  ) {
    final next = record.copyWith(
      repayments: [...record.repayments, repayment],
      updatedAt: DateTime.now(),
    );
    return _repo.update(userId, next);
  }

  Future<void> removeRepayment(
    String userId,
    BorrowLending record,
    String repaymentId,
  ) {
    final next = record.copyWith(
      repayments: record.repayments.where((r) => r.id != repaymentId).toList(),
      updatedAt: DateTime.now(),
    );
    return _repo.update(userId, next);
  }

  /// Mark fully settled by appending a single repayment for the
  /// remaining balance.
  Future<void> markSettled(String userId, BorrowLending record) {
    final remaining = record.remaining;
    if (remaining <= 0) return Future.value();
    final repayment = BorrowLendingRepayment(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      amount: remaining,
      date: DateTime.now(),
      note: 'Settled',
    );
    return addRepayment(userId, record, repayment);
  }

  Future<void> setCancelled(
    String userId,
    BorrowLending record,
    bool cancelled,
  ) {
    return _repo.update(
      userId,
      record.copyWith(cancelled: cancelled, updatedAt: DateTime.now()),
    );
  }
}
