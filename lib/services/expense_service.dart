import '../models/expense.dart';
import '../repositories/expense_repository.dart';

class ExpenseService {
  final ExpenseRepository _repository;

  ExpenseService(this._repository);

  Stream<List<Expense>> getAllExpenses(String userId) {
    return _repository.getAllExpenses(userId);
  }

  Stream<List<Expense>> getExpenses(String userId, {DateTime? month}) {
    return _repository.getExpenses(userId, month: month);
  }

  Future<void> addExpense(String userId, Expense expense) {
    return _repository.addExpense(userId, expense);
  }

  Future<void> updateExpense(String userId, Expense expense) {
    return _repository.updateExpense(userId, expense);
  }

  Future<void> upsertExpense(String userId, Expense expense) {
    return _repository.upsertExpense(userId, expense);
  }

  Future<void> deleteExpense(String userId, String expenseId) {
    return _repository.deleteExpense(userId, expenseId);
  }

  Stream<double> getMonthlyBudget(String userId) {
    return _repository.getMonthlyBudget(userId);
  }

  Future<void> setMonthlyBudget(String userId, double amount) {
    return _repository.setMonthlyBudget(userId, amount);
  }

  Stream<double> getOpeningSavings(String userId) {
    return _repository.getOpeningSavings(userId);
  }

  Future<void> setOpeningSavings(String userId, double amount) {
    return _repository.setOpeningSavings(userId, amount);
  }
}
