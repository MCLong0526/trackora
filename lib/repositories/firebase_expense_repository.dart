import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/expense.dart';
import '../models/monthly_budget.dart';
import 'expense_repository.dart';

class FirebaseExpenseRepository implements ExpenseRepository {
  final FirebaseFirestore _db;

  FirebaseExpenseRepository({FirebaseFirestore? firestore})
    : _db = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _expensesRef(String userId) {
    return _db.collection('users').doc(userId).collection('expenses');
  }

  @override
  Stream<List<Expense>> getAllExpenses(String userId) {
    return _expensesRef(userId)
        .orderBy('date', descending: true)
        .snapshots()
        .map((s) => s.docs.map(_fromDoc).toList());
  }

  @override
  Stream<List<Expense>> getExpenses(String userId, {DateTime? month}) {
    Query<Map<String, dynamic>> query = _expensesRef(userId);

    if (month != null) {
      final start = DateTime(month.year, month.month, 1);
      final end = DateTime(month.year, month.month + 1, 1);
      query = query
          .where('date', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
          .where('date', isLessThan: Timestamp.fromDate(end));
    }

    return query
        .orderBy('date', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map(_fromDoc).toList());
  }

  @override
  Future<void> addExpense(String userId, Expense expense) async {
    if (expense.id.isEmpty) {
      await _expensesRef(userId).add(_toFirestoreMap(expense));
      return;
    }
    await _expensesRef(userId).doc(expense.id).set(_toFirestoreMap(expense));
  }

  @override
  Future<void> updateExpense(String userId, Expense expense) async {
    await _expensesRef(userId).doc(expense.id).update(_toFirestoreMap(expense));
  }

  @override
  Future<void> upsertExpense(String userId, Expense expense) async {
    if (expense.id.isEmpty) {
      await addExpense(userId, expense);
      return;
    }
    await _expensesRef(
      userId,
    ).doc(expense.id).set(_toFirestoreMap(expense), SetOptions(merge: true));
  }

  @override
  Future<void> deleteExpense(String userId, String expenseId) async {
    await _expensesRef(userId).doc(expenseId).delete();
  }

  DocumentReference<Map<String, dynamic>> _budgetRef(String userId) {
    return _db.collection('users').doc(userId).collection('meta').doc('budget');
  }

  @override
  Stream<double> getMonthlyBudget(String userId) {
    return _budgetRef(userId).snapshots().map((doc) {
      if (!doc.exists) return 0.0;
      final v = doc.data()?['monthly'];
      return (v is num) ? v.toDouble() : 0.0;
    });
  }

  @override
  Future<void> setMonthlyBudget(String userId, double amount) async {
    await _budgetRef(userId).set(
      {'monthly': amount, 'mode': 'total'},
      SetOptions(merge: true),
    );
  }

  @override
  Stream<MonthlyBudget> getBudgetConfig(String userId) {
    return _budgetRef(userId).snapshots().map((doc) {
      if (!doc.exists) return const MonthlyBudget();
      return MonthlyBudget.fromMap(doc.data() ?? const {});
    });
  }

  @override
  Future<void> setBudgetConfig(String userId, MonthlyBudget budget) async {
    // Overwrite categories wholesale (merge would leave deleted ones behind).
    await _budgetRef(userId).set(budget.toMap());
  }

  DocumentReference<Map<String, dynamic>> _savingsRef(String userId) {
    return _db
        .collection('users')
        .doc(userId)
        .collection('meta')
        .doc('savings');
  }

  @override
  Stream<double> getOpeningSavings(String userId) {
    return _savingsRef(userId).snapshots().map((doc) {
      if (!doc.exists) return 0.0;
      final v = doc.data()?['opening'];
      return (v is num) ? v.toDouble() : 0.0;
    });
  }

  @override
  Future<void> setOpeningSavings(String userId, double amount) async {
    await _savingsRef(userId).set({'opening': amount}, SetOptions(merge: true));
  }

  Expense _fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) {
      throw StateError('Expense document ${doc.id} is empty.');
    }
    return Expense.fromMap(data, id: doc.id);
  }

  Map<String, dynamic> _toFirestoreMap(Expense expense) {
    return {
      'amount': expense.amount,
      'category': expense.category,
      'note': expense.note,
      'date': Timestamp.fromDate(expense.date),
      'type': _encodeType(expense.type),
      'receiptUrl': expense.receiptUrl,
      'accountId': expense.accountId,
      'toAccountId': expense.toAccountId,
      'counterpart': expense.counterpart,
      'createdAt': Timestamp.fromDate(expense.createdAt),
      'updatedAt': Timestamp.fromDate(expense.updatedAt),
      if (expense.originalCurrency != null)
        'originalCurrency': expense.originalCurrency,
      if (expense.exchangeRate != null) 'exchangeRate': expense.exchangeRate,
      if (expense.baseCurrencyAmount != null)
        'baseCurrencyAmount': expense.baseCurrencyAmount,
    };
  }

  static String _encodeType(EntryType type) {
    switch (type) {
      case EntryType.income:
        return 'income';
      case EntryType.transfer:
        return 'transfer';
      case EntryType.receive:
        return 'receive';
      case EntryType.expense:
        return 'expense';
    }
  }
}
