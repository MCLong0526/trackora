enum EntryType { expense, income }

class Expense {
  final String id;
  final double amount;
  final String category;
  final String note;
  final DateTime date;
  final EntryType type;
  final String? receiptUrl;
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
      type: (data['type'] as String?) == 'income'
          ? EntryType.income
          : EntryType.expense,
      receiptUrl: data['receiptUrl'] as String?,
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
      'type': type == EntryType.income ? 'income' : 'expense',
      'receiptUrl': receiptUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static const _sentinel = Object();

  /// `receiptUrl` uses a sentinel so callers can explicitly clear the
  /// reference (pass `null`) without `copyWith` falling back to the old
  /// value. Needed by the "Remove receipt" action on the edit screen.
  Expense copyWith({
    String? id,
    double? amount,
    String? category,
    String? note,
    DateTime? date,
    EntryType? type,
    Object? receiptUrl = _sentinel,
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
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.parse(value);
    if (value != null) {
      try {
        final date = (value as dynamic).toDate();
        if (date is DateTime) return date;
      } catch (_) {
        // The repositories keep dates normalized; this only supports older
        // Firestore-shaped values that may still flow through the model.
      }
    }
    throw FormatException('Unsupported date value: $value');
  }
}
