import 'package:hive_flutter/hive_flutter.dart';

import '../models/expense.dart';
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
        .map<Expense>((data) => Expense.fromMap(data, id: data['id'] as String))
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

  String _openingSavingsKey(String userId) => '$userId:openingSavings';

  String _newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
