import '../models/expense.dart';
import '../models/monthly_budget.dart';

abstract class ExpenseRepository {
  Stream<List<Expense>> getAllExpenses(String userId);

  Stream<List<Expense>> getExpenses(String userId, {DateTime? month});

  Future<void> addExpense(String userId, Expense expense);

  Future<void> updateExpense(String userId, Expense expense);

  Future<void> upsertExpense(String userId, Expense expense);

  Future<void> deleteExpense(String userId, String expenseId);

  Stream<double> getMonthlyBudget(String userId);

  Future<void> setMonthlyBudget(String userId, double amount);

  /// Full budget config (total vs by-category). The legacy
  /// [getMonthlyBudget]/[setMonthlyBudget] still operate on the effective total.
  Stream<MonthlyBudget> getBudgetConfig(String userId);

  Future<void> setBudgetConfig(String userId, MonthlyBudget budget);

  Stream<double> getOpeningSavings(String userId);

  Future<void> setOpeningSavings(String userId, double amount);
}
