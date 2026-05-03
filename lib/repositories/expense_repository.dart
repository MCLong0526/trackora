import '../models/expense.dart';

abstract class ExpenseRepository {
  Stream<List<Expense>> getAllExpenses(String userId);

  Stream<List<Expense>> getExpenses(String userId, {DateTime? month});

  Future<void> addExpense(String userId, Expense expense);

  Future<void> updateExpense(String userId, Expense expense);

  Future<void> upsertExpense(String userId, Expense expense);

  Future<void> deleteExpense(String userId, String expenseId);

  Stream<double> getMonthlyBudget(String userId);

  Future<void> setMonthlyBudget(String userId, double amount);

  Stream<double> getOpeningSavings(String userId);

  Future<void> setOpeningSavings(String userId, double amount);
}
