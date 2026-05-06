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
  });

  factory Expense.fromMap(Map<String, dynamic> data, {required String id}) {
    return Expense(
      id: id,
      amount: (data['amount'] as num).toDouble(),
      category: data['category'] as String,
      note: data['note'] as String? ?? '',
      date: _readDate(data['date']),
      type: _decodeType(data['type'] as String?),
      receiptUrl: data['receiptUrl'] as String?,
      accountId: data['accountId'] as String?,
      toAccountId: data['toAccountId'] as String?,
      counterpart: data['counterpart'] as String?,
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
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

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.parse(value);
    if (value != null) {
      try {
        final date = (value as dynamic).toDate();
        if (date is DateTime) return date;
      } catch (_) {}
    }
    throw FormatException('Unsupported date value: $value');
  }
}
