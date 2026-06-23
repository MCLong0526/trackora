import 'dart:convert';
import 'dart:developer' as dev;

import 'package:hive/hive.dart';

import '../models/expense.dart';
import '../models/monthly_budget.dart';
import 'expense_repository.dart';
import 'local_storage.dart';

class LocalExpenseRepository implements ExpenseRepository {
  static Future<void> init() => LocalStorage.init();

  Box<dynamic> get _expenses => LocalStorage.expenses;
  Box<dynamic> get _meta => LocalStorage.meta;

  @override
  Stream<List<Expense>> getAllExpenses(String userId) async* {
    await LocalStorage.init();
    yield _readExpenses(userId);
    yield* _expenses.watch().map<List<Expense>>((_) => _readExpenses(userId));
  }

  @override
  Stream<List<Expense>> getExpenses(String userId, {DateTime? month}) async* {
    await LocalStorage.init();
    yield _readExpenses(userId, month: month);
    yield* _expenses.watch().map<List<Expense>>(
      (_) => _readExpenses(userId, month: month),
    );
  }

  @override
  Future<void> addExpense(String userId, Expense expense) async {
    await LocalStorage.init();
    final id = expense.id.isEmpty ? _newId() : expense.id;
    final saved = expense.id == id ? expense : expense.copyWith(id: id);
    await _expenses.put(_expenseKey(userId, id), _toStoredMap(userId, saved));
  }

  @override
  Future<void> updateExpense(String userId, Expense expense) async {
    await LocalStorage.init();
    if (expense.id.isEmpty) return;
    await _expenses.put(
      _expenseKey(userId, expense.id),
      _toStoredMap(userId, expense),
    );
  }

  @override
  Future<void> upsertExpense(String userId, Expense expense) async {
    await LocalStorage.init();
    final id = expense.id.isEmpty ? _newId() : expense.id;
    final saved = expense.id == id ? expense : expense.copyWith(id: id);
    await _expenses.put(_expenseKey(userId, id), _toStoredMap(userId, saved));
  }

  @override
  Future<void> deleteExpense(String userId, String expenseId) async {
    await LocalStorage.init();
    await _expenses.delete(_expenseKey(userId, expenseId));
  }

  Future<Expense?> getExpenseById(String userId, String expenseId) async {
    await LocalStorage.init();
    final raw = _expenses.get(_expenseKey(userId, expenseId));
    if (raw is! Map) return null;
    final data = Map<String, dynamic>.from(raw);
    if (data['userId'] != userId) return null;
    return Expense.fromMap(data, id: expenseId);
  }

  Future<void> replaceAllExpenses(
    String userId,
    List<Expense> expenses, {
    Set<String> preserveIds = const {},
  }) async {
    await LocalStorage.init();
    final incomingIds = expenses
        .map((e) => e.id)
        .where((id) => id.isNotEmpty)
        .toSet();
    for (final key in _expenses.keys.toList()) {
      final raw = _expenses.get(key);
      if (raw is! Map) continue;
      final data = Map<String, dynamic>.from(raw);
      final id = data['id'];
      if (data['userId'] == userId &&
          id is String &&
          !incomingIds.contains(id) &&
          !preserveIds.contains(id)) {
        await _expenses.delete(key);
      }
    }
    for (final expense in expenses) {
      if (expense.id.isEmpty) continue;
      await upsertExpense(userId, expense);
    }
  }

  @override
  Stream<double> getMonthlyBudget(String userId) async* {
    await LocalStorage.init();
    final key = _budgetKey(userId);
    yield _readDouble(key);
    yield* _meta.watch(key: key).map<double>((_) => _readDouble(key));
  }

  @override
  Future<void> setMonthlyBudget(String userId, double amount) async {
    await LocalStorage.init();
    await _meta.put(_budgetKey(userId), amount);
    await _meta.put(
        _budgetConfigKey(userId),
        jsonEncode(MonthlyBudget(total: amount).toMap()));
  }

  @override
  Stream<MonthlyBudget> getBudgetConfig(String userId) async* {
    await LocalStorage.init();
    final key = _budgetConfigKey(userId);
    yield _readBudgetConfig(userId);
    yield* _meta.watch(key: key).map((_) => _readBudgetConfig(userId));
  }

  @override
  Future<void> setBudgetConfig(String userId, MonthlyBudget budget) async {
    await LocalStorage.init();
    await _meta.put(_budgetConfigKey(userId), jsonEncode(budget.toMap()));
    // Keep the legacy double in sync so total-only consumers stay correct.
    await _meta.put(_budgetKey(userId), budget.effectiveTotal);
  }

  MonthlyBudget _readBudgetConfig(String userId) {
    final raw = _meta.get(_budgetConfigKey(userId));
    if (raw is String && raw.isNotEmpty) {
      try {
        return MonthlyBudget.fromMap(
            Map<String, dynamic>.from(jsonDecode(raw) as Map));
      } catch (_) {}
    }
    // Fall back to the legacy single-number budget.
    return MonthlyBudget(total: _readDouble(_budgetKey(userId)));
  }

  @override
  Stream<double> getOpeningSavings(String userId) async* {
    await LocalStorage.init();
    final key = _openingSavingsKey(userId);
    yield _readDouble(key);
    yield* _meta.watch(key: key).map<double>((_) => _readDouble(key));
  }

  @override
  Future<void> setOpeningSavings(String userId, double amount) async {
    await LocalStorage.init();
    await _meta.put(_openingSavingsKey(userId), amount);
  }

  List<Expense> _readExpenses(String userId, {DateTime? month}) {
    final expenses = _expenses.values
        .whereType<Map>()
        .map<Map<String, dynamic>>((raw) => Map<String, dynamic>.from(raw))
        .where((data) => data['userId'] == userId && data['id'] is String)
        .map<Expense?>((data) {
          try {
            return Expense.fromMap(data, id: data['id'] as String);
          } catch (e, st) {
            dev.log(
              '[LocalExpenseRepo] skipping malformed row ${data['id']}: $e',
              stackTrace: st,
            );
            return null;
          }
        })
        .whereType<Expense>()
        .where((expense) {
          if (month == null) return true;
          final start = DateTime(month.year, month.month, 1);
          final end = DateTime(month.year, month.month + 1, 1);
          return !expense.date.isBefore(start) && expense.date.isBefore(end);
        })
        .toList();

    expenses.sort((a, b) => b.date.compareTo(a.date));

    return expenses;
  }

  Map<String, dynamic> _toStoredMap(String userId, Expense expense) {
    return {...expense.toMap(includeId: true), 'userId': userId};
  }

  double _readDouble(String key) {
    final value = _meta.get(key);
    return value is num ? value.toDouble() : 0.0;
  }

  String _expenseKey(String userId, String expenseId) => '$userId:$expenseId';

  String _budgetKey(String userId) => '$userId:monthlyBudget';

  String _budgetConfigKey(String userId) => '$userId:monthlyBudgetConfig';

  String _openingSavingsKey(String userId) => '$userId:openingSavings';

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
