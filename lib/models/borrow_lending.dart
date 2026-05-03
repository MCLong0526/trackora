/// Direction of a borrow / lending record.
enum BorrowLendingType { borrowed, lent }

/// Computed lifecycle state. `cancelled` is a hard stop the user can
/// toggle anytime; `settled` is reached when total repayments equal or
/// exceed the original amount; `partial` when some repayments exist
/// but not enough; `active` is the default.
enum BorrowLendingStatus { active, partial, settled, cancelled }

/// A single repayment / partial settlement against a [BorrowLending]
/// record. Stored inline as part of the parent so we don't need a
/// second Hive box.
class BorrowLendingRepayment {
  final String id;
  final double amount;
  final DateTime date;
  final String note;

  const BorrowLendingRepayment({
    required this.id,
    required this.amount,
    required this.date,
    this.note = '',
  });

  factory BorrowLendingRepayment.fromMap(Map<String, dynamic> data) {
    return BorrowLendingRepayment(
      id: data['id'] as String,
      amount: (data['amount'] as num).toDouble(),
      date: BorrowLending._readDate(data['date']),
      note: data['note'] as String? ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
      };
}

/// Storage-neutral borrow / lending record. Persisted via
/// [BorrowLendingRepository] — screens never touch Hive / Firestore.
class BorrowLending {
  final String id;
  final BorrowLendingType type;
  final String person;
  final double amount;
  final String note;
  final DateTime date;
  final DateTime? dueDate;
  final String? imagePath;
  final List<BorrowLendingRepayment> repayments;
  final bool cancelled;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BorrowLending({
    required this.id,
    required this.type,
    required this.person,
    required this.amount,
    this.note = '',
    required this.date,
    this.dueDate,
    this.imagePath,
    this.repayments = const [],
    this.cancelled = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory BorrowLending.fromMap(
    Map<String, dynamic> data, {
    required String id,
  }) {
    return BorrowLending(
      id: id,
      type: (data['type'] as String?) == 'lent'
          ? BorrowLendingType.lent
          : BorrowLendingType.borrowed,
      person: data['person'] as String? ?? '',
      amount: (data['amount'] as num).toDouble(),
      note: data['note'] as String? ?? '',
      date: _readDate(data['date']),
      dueDate: data['dueDate'] == null ? null : _readDate(data['dueDate']),
      imagePath: data['imagePath'] as String?,
      repayments: (data['repayments'] as List? ?? const [])
          .whereType<Map>()
          .map((r) => BorrowLendingRepayment.fromMap(
                Map<String, dynamic>.from(r),
              ))
          .toList(),
      cancelled: (data['cancelled'] as bool?) ?? false,
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) => {
        if (includeId) 'id': id,
        'type': type == BorrowLendingType.lent ? 'lent' : 'borrowed',
        'person': person,
        'amount': amount,
        'note': note,
        'date': date.toIso8601String(),
        'dueDate': dueDate?.toIso8601String(),
        'imagePath': imagePath,
        'repayments': repayments.map((r) => r.toMap()).toList(),
        'cancelled': cancelled,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  /// Sentinel-aware copyWith so callers can clear `dueDate` /
  /// `imagePath` by passing `null` explicitly.
  static const _sentinel = Object();

  BorrowLending copyWith({
    String? id,
    BorrowLendingType? type,
    String? person,
    double? amount,
    String? note,
    DateTime? date,
    Object? dueDate = _sentinel,
    Object? imagePath = _sentinel,
    List<BorrowLendingRepayment>? repayments,
    bool? cancelled,
    DateTime? updatedAt,
  }) {
    return BorrowLending(
      id: id ?? this.id,
      type: type ?? this.type,
      person: person ?? this.person,
      amount: amount ?? this.amount,
      note: note ?? this.note,
      date: date ?? this.date,
      dueDate: identical(dueDate, _sentinel)
          ? this.dueDate
          : dueDate as DateTime?,
      imagePath: identical(imagePath, _sentinel)
          ? this.imagePath
          : imagePath as String?,
      repayments: repayments ?? this.repayments,
      cancelled: cancelled ?? this.cancelled,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  /// Total repaid so far. Capped at `amount` so a stale list never
  /// reports negative remaining.
  double get repaid {
    final sum = repayments.fold<double>(0, (s, r) => s + r.amount);
    return sum > amount ? amount : sum;
  }

  double get remaining => (amount - repaid).clamp(0, amount);

  double get progress {
    if (amount <= 0) return 0;
    return (repaid / amount).clamp(0.0, 1.0);
  }

  BorrowLendingStatus get status {
    if (cancelled) return BorrowLendingStatus.cancelled;
    if (repaid >= amount) return BorrowLendingStatus.settled;
    if (repaid > 0) return BorrowLendingStatus.partial;
    return BorrowLendingStatus.active;
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
