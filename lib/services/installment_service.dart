import '../models/expense.dart';
import '../models/installment.dart';
import '../repositories/expense_repository.dart';
import '../repositories/installment_repository.dart';

class InstallmentService {
  final InstallmentRepository _repository;
  final ExpenseRepository _expenses;

  InstallmentService({
    required InstallmentRepository repository,
    required ExpenseRepository expenses,
  }) : _repository = repository,
       _expenses = expenses;

  Stream<List<Installment>> getAll(String userId) {
    return _repository.getAll(userId);
  }

  Future<void> add(String userId, Installment installment) {
    return _repository.add(userId, installment);
  }

  Future<void> update(String userId, Installment installment) {
    return _repository.update(userId, installment);
  }

  Future<void> delete(String userId, String id) {
    return _repository.delete(userId, id);
  }

  /// Marks the installment paid for `month` and creates a matching expense
  /// so it shows up in the regular ledger and totals.
  Future<void> markPaid(
    String userId,
    Installment installment,
    DateTime month,
  ) async {
    final key = Installment.monthKey(month);
    if (installment.paidMonths.contains(key)) return;

    final paidMonths = [...installment.paidMonths, key];
    final updatedInstallment = installment.remainingAmountOverride == null
        ? installment.copyWith(paidMonths: paidMonths)
        : installment.copyWith(
            paidMonths: paidMonths,
            remainingAmountOverride:
                (installment.remainingAmountOverride! - installment.amount)
                    .clamp(0, double.infinity)
                    .toDouble(),
          );
    await _repository.update(userId, updatedInstallment);

    final now = DateTime.now();
    await _expenses.addExpense(
      userId,
      Expense(
        id: '',
        amount: installment.amount,
        category: installment.category,
        note: '${installment.name} (installment)',
        date: installment.dueDateIn(month),
        type: EntryType.expense,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> markUnpaid(
    String userId,
    Installment installment,
    DateTime month,
  ) async {
    final key = Installment.monthKey(month);
    if (!installment.paidMonths.contains(key)) return;
    final updated = [...installment.paidMonths]..remove(key);
    final updatedInstallment = installment.remainingAmountOverride == null
        ? installment.copyWith(paidMonths: updated)
        : installment.copyWith(
            paidMonths: updated,
            remainingAmountOverride:
                installment.remainingAmountOverride! + installment.amount,
          );
    await _repository.update(userId, updatedInstallment);
  }

  /// Toggle cancellation. Cancelled installments hide from monthly totals
  /// but stay in the list so the user can revive them later.
  Future<void> setCancelled(
    String userId,
    Installment installment,
    bool cancelled,
  ) {
    return _repository.update(
      userId,
      installment.copyWith(cancelled: cancelled),
    );
  }

  /// Manually mark a fixed-term installment as completed by setting
  /// `totalMonths` to whatever is already paid (min 1). Lifetime plans get
  /// pinned to their current paid count, effectively converting them to a
  /// completed fixed-term plan.
  Future<void> markCompleted(String userId, Installment installment) {
    final paid = installment.paidCount;
    final target = paid > 0 ? paid : 1;
    return _repository.update(
      userId,
      installment.copyWith(
        totalMonths: target,
        cancelled: false,
        paidMonthsAtStart: paid > 0 ? installment.paidMonthsAtStart : 1,
        remainingAmountOverride: 0.0,
      ),
    );
  }

  /// Reactivate a cancelled installment.
  Future<void> reactivate(String userId, Installment installment) {
    return _repository.update(userId, installment.copyWith(cancelled: false));
  }
}
