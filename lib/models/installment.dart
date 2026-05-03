/// A recurring monthly payment (loan, subscription, phone plan, etc.).
/// `paidMonths` stores 'YYYY-MM' strings for months already paid.
///
/// Term:
/// - `totalMonths == null` means **lifetime** (no fixed end, e.g. Netflix).
/// - `totalMonths > 0` is a fixed-term plan; once `paidMonths.length`
///   reaches `totalMonths` the installment is considered **completed**.
///
/// `cancelled` is a hard stop the user can toggle anytime.
enum InstallmentStatus { active, completed, cancelled }

class Installment {
  final String id;
  final String name;
  final double amount;
  final int dayOfMonth; // 1..28 to be safe
  final String category;
  final DateTime startDate;
  final DateTime? endDate;
  final List<String> paidMonths;
  final int? totalMonths; // null = lifetime
  final bool cancelled;

  /// Months the user already paid **before** they started using Trackora.
  /// Used when adding an existing installment that's already partially
  /// done (e.g. "I'm 8 months into a 24-month car loan"). Always >= 0.
  /// Effective paid count = `paidMonthsAtStart + paidMonths.length`.
  final int paidMonthsAtStart;

  /// Optional original total amount (principal). Purely informational —
  /// it lets the user record what the plan was originally worth without
  /// affecting any computation. Null when unknown.
  final double? originalPrincipal;

  /// Optional user-entered current remaining amount. When present it wins
  /// over the computed `monthly amount × months left` value.
  final double? remainingAmountOverride;

  const Installment({
    required this.id,
    required this.name,
    required this.amount,
    required this.dayOfMonth,
    required this.category,
    required this.startDate,
    this.endDate,
    this.paidMonths = const [],
    this.totalMonths,
    this.cancelled = false,
    this.paidMonthsAtStart = 0,
    this.originalPrincipal,
    this.remainingAmountOverride,
  });

  factory Installment.fromMap(Map<String, dynamic> data, {required String id}) {
    final raw = data['totalMonths'];
    int? total;
    if (raw is num) {
      final v = raw.toInt();
      total = v > 0 ? v : null;
    }
    return Installment(
      id: id,
      name: data['name'] as String,
      amount: (data['amount'] as num).toDouble(),
      dayOfMonth: (data['dayOfMonth'] as num?)?.toInt() ?? 1,
      category: data['category'] as String? ?? 'Bills',
      startDate: _readDate(data['startDate']),
      endDate: data['endDate'] == null ? null : _readDate(data['endDate']),
      paidMonths: List<String>.from(data['paidMonths'] as List? ?? const []),
      totalMonths: total,
      cancelled: (data['cancelled'] as bool?) ?? false,
      paidMonthsAtStart: (data['paidMonthsAtStart'] as num?)?.toInt() ?? 0,
      originalPrincipal: (data['originalPrincipal'] as num?)?.toDouble(),
      remainingAmountOverride: (data['remainingAmountOverride'] as num?)
          ?.toDouble(),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) => {
    if (includeId) 'id': id,
    'name': name,
    'amount': amount,
    'dayOfMonth': dayOfMonth,
    'category': category,
    'startDate': startDate.toIso8601String(),
    'endDate': endDate?.toIso8601String(),
    'paidMonths': paidMonths,
    'totalMonths': totalMonths,
    'cancelled': cancelled,
    'paidMonthsAtStart': paidMonthsAtStart,
    'originalPrincipal': originalPrincipal,
    'remainingAmountOverride': remainingAmountOverride,
  };

  Installment copyWith({
    String? id,
    String? name,
    double? amount,
    int? dayOfMonth,
    String? category,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? paidMonths,
    Object? totalMonths = _sentinel,
    bool? cancelled,
    int? paidMonthsAtStart,
    Object? originalPrincipal = _sentinel,
    Object? remainingAmountOverride = _sentinel,
  }) {
    return Installment(
      id: id ?? this.id,
      name: name ?? this.name,
      amount: amount ?? this.amount,
      dayOfMonth: dayOfMonth ?? this.dayOfMonth,
      category: category ?? this.category,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      paidMonths: paidMonths ?? this.paidMonths,
      totalMonths: identical(totalMonths, _sentinel)
          ? this.totalMonths
          : totalMonths as int?,
      cancelled: cancelled ?? this.cancelled,
      paidMonthsAtStart: paidMonthsAtStart ?? this.paidMonthsAtStart,
      originalPrincipal: identical(originalPrincipal, _sentinel)
          ? this.originalPrincipal
          : originalPrincipal as double?,
      remainingAmountOverride: identical(remainingAmountOverride, _sentinel)
          ? this.remainingAmountOverride
          : remainingAmountOverride as double?,
    );
  }

  static const _sentinel = Object();

  static String monthKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

  bool get isLifetime => totalMonths == null;

  /// Months paid in-app since the user added this installment.
  int get paidInApp => paidMonths.length;

  /// Total months paid: pre-existing + paid in-app, capped to `totalMonths`
  /// when known so a stale paid-list never reports > 100 %.
  int get paidCount {
    final raw = paidMonthsAtStart + paidInApp;
    if (totalMonths == null) return raw < 0 ? 0 : raw;
    return raw.clamp(0, totalMonths!);
  }

  int? get monthsLeft => totalMonths == null
      ? null
      : (totalMonths! - paidCount).clamp(0, totalMonths!);

  /// Money already paid (effective months × monthly amount). For lifetime
  /// plans this is "paid so far in-app + before adding the plan".
  double get amountPaid => paidCount * amount;

  double? get totalRemaining {
    if (remainingAmountOverride != null) {
      return remainingAmountOverride!.clamp(0, double.infinity).toDouble();
    }
    return monthsLeft == null ? null : monthsLeft! * amount;
  }

  double get progress {
    if (totalMonths == null || totalMonths! <= 0) return 0;
    return (paidCount / totalMonths!).clamp(0.0, 1.0);
  }

  InstallmentStatus get status {
    if (cancelled) return InstallmentStatus.cancelled;
    if (totalMonths != null && paidCount >= totalMonths!) {
      return InstallmentStatus.completed;
    }
    return InstallmentStatus.active;
  }

  /// Best-effort next due date. If this month is already paid (or
  /// not active in this month), advance to next month. Returns null
  /// for cancelled / completed plans.
  DateTime? nextDueDate({DateTime? from}) {
    if (status != InstallmentStatus.active) return null;
    final ref = from ?? DateTime.now();
    final thisMonth = DateTime(ref.year, ref.month, 1);
    final dueThis = dueDateIn(thisMonth);
    if (!isPaidIn(thisMonth) && !ref.isAfter(dueThis)) return dueThis;
    final nextMonth = DateTime(ref.year, ref.month + 1, 1);
    return dueDateIn(nextMonth);
  }

  bool isActiveIn(DateTime month) {
    if (status != InstallmentStatus.active) return false;
    final m = DateTime(month.year, month.month, 1);
    if (m.isBefore(DateTime(startDate.year, startDate.month, 1))) return false;
    if (endDate != null &&
        m.isAfter(DateTime(endDate!.year, endDate!.month, 1))) {
      return false;
    }
    return true;
  }

  bool isPaidIn(DateTime month) => paidMonths.contains(monthKey(month));

  DateTime dueDateIn(DateTime month) {
    final lastDay = DateTime(month.year, month.month + 1, 0).day;
    final day = dayOfMonth.clamp(1, lastDay);
    return DateTime(month.year, month.month, day);
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
