enum EntryType { expense, income, transfer, receive }

extension EntryTypeX on EntryType {
  bool get isOutflow => this == EntryType.expense || this == EntryType.transfer;
  bool get isInflow => this == EntryType.income || this == EntryType.receive;
}

class Expense {
  final String id;
  final double amount;
  final String category;
  final String note;
  final DateTime date;
  final EntryType type;
  final String? receiptUrl;
  final String? accountId;
  final String? toAccountId;
  final String? counterpart;
  final DateTime createdAt;
  final DateTime updatedAt;
  /// ISO 4217 code for this transaction's original currency.
  /// Null → treated as the user's main/base currency.
  final String? originalCurrency;
  /// Rate used to convert [originalCurrency] → main currency at entry time.
  /// Null → 1.0 (same currency or unknown).
  final double? exchangeRate;
  /// Pre-computed amount in user's main/base currency (amount × exchangeRate).
  /// Null → use [amount] as-is.
  final double? baseCurrencyAmount;

  const Expense({
    required this.id,
    required this.amount,
    required this.category,
    required this.note,
    required this.date,
    this.type = EntryType.expense,
    this.receiptUrl,
    this.accountId,
    this.toAccountId,
    this.counterpart,
    required this.createdAt,
    required this.updatedAt,
    this.originalCurrency,
    this.exchangeRate,
    this.baseCurrencyAmount,
  });

  /// Returns the amount converted to main/base currency.
  double get convertedAmount => baseCurrencyAmount ?? amount;

  factory Expense.fromMap(Map<String, dynamic> data, {required String id}) {
    final date = _readDate(data['date']);
    return Expense(
      id: id,
      amount: (data['amount'] as num?)?.toDouble() ?? 0.0,
      category: data['category'] as String? ?? '',
      note: data['note'] as String? ?? '',
      date: date,
      type: _decodeType(data['type'] as String?),
      receiptUrl: data['receiptUrl'] as String?,
      accountId: data['accountId'] as String?,
      toAccountId: data['toAccountId'] as String?,
      counterpart: data['counterpart'] as String?,
      createdAt: _readDate(data['createdAt'], fallback: date),
      updatedAt: _readDate(data['updatedAt'], fallback: date),
      originalCurrency: data['originalCurrency'] as String?,
      exchangeRate: (data['exchangeRate'] as num?)?.toDouble(),
      baseCurrencyAmount: (data['baseCurrencyAmount'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    return {
      if (includeId) 'id': id,
      'amount': amount,
      'category': category,
      'note': note,
      'date': date.toIso8601String(),
      'type': _encodeType(type),
      'receiptUrl': receiptUrl,
      'accountId': accountId,
      'toAccountId': toAccountId,
      'counterpart': counterpart,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (originalCurrency != null) 'originalCurrency': originalCurrency,
      if (exchangeRate != null) 'exchangeRate': exchangeRate,
      if (baseCurrencyAmount != null) 'baseCurrencyAmount': baseCurrencyAmount,
    };
  }

  static const _sentinel = Object();

  Expense copyWith({
    String? id,
    double? amount,
    String? category,
    String? note,
    DateTime? date,
    EntryType? type,
    Object? receiptUrl = _sentinel,
    Object? accountId = _sentinel,
    Object? toAccountId = _sentinel,
    Object? counterpart = _sentinel,
    DateTime? updatedAt,
    Object? originalCurrency = _sentinel,
    Object? exchangeRate = _sentinel,
    Object? baseCurrencyAmount = _sentinel,
  }) {
    return Expense(
      id: id ?? this.id,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      note: note ?? this.note,
      date: date ?? this.date,
      type: type ?? this.type,
      receiptUrl: identical(receiptUrl, _sentinel)
          ? this.receiptUrl
          : receiptUrl as String?,
      accountId: identical(accountId, _sentinel)
          ? this.accountId
          : accountId as String?,
      toAccountId: identical(toAccountId, _sentinel)
          ? this.toAccountId
          : toAccountId as String?,
      counterpart: identical(counterpart, _sentinel)
          ? this.counterpart
          : counterpart as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      originalCurrency: identical(originalCurrency, _sentinel)
          ? this.originalCurrency
          : originalCurrency as String?,
      exchangeRate: identical(exchangeRate, _sentinel)
          ? this.exchangeRate
          : exchangeRate as double?,
      baseCurrencyAmount: identical(baseCurrencyAmount, _sentinel)
          ? this.baseCurrencyAmount
          : baseCurrencyAmount as double?,
    );
  }

  static EntryType _decodeType(String? raw) {
    switch (raw) {
      case 'income':
        return EntryType.income;
      case 'transfer':
        return EntryType.transfer;
      case 'receive':
        return EntryType.receive;
      default:
        return EntryType.expense;
    }
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

  static DateTime _readDate(Object? value, {DateTime? fallback}) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final parsed = DateTime.tryParse(value);
      if (parsed != null) return parsed;
    }
    if (value != null) {
      try {
        final date = (value as dynamic).toDate();
        if (date is DateTime) return date;
      } catch (_) {}
    }
    return fallback ?? DateTime.fromMillisecondsSinceEpoch(0);
  }
}
