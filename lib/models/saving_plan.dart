/// Four flavours of saving plan, each with a different progress story:
///
/// - `fixed` — target amount + recurring contribution per period.
/// - `flexible` — target amount, contribute any amount any time.
/// - `daysChallenge` — N consecutive days, contribute daily.
/// - `weeksChallenge` — N consecutive weeks, contribute weekly.
enum SavingPlanType { fixed, flexible, daysChallenge, weeksChallenge }

enum SavingFrequency { daily, weekly, monthly }

enum SavingPlanStatus { active, completed, cancelled }

/// One contribution against a plan. Stored inline on the plan so we
/// don't need a second Hive box. `slotIndex` is meaningful for the
/// challenge variants — it pairs the contribution with day N or week
/// N of the plan; null for flexible / fixed plans.
class SavingContribution {
  final String id;
  final double amount;
  final DateTime date;
  final String note;
  final int? slotIndex;

  const SavingContribution({
    required this.id,
    required this.amount,
    required this.date,
    this.note = '',
    this.slotIndex,
  });

  factory SavingContribution.fromMap(Map<String, dynamic> data) {
    return SavingContribution(
      id: data['id'] as String,
      amount: (data['amount'] as num).toDouble(),
      date: SavingPlan._readDate(data['date']),
      note: data['note'] as String? ?? '',
      slotIndex: (data['slotIndex'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'amount': amount,
        'date': date.toIso8601String(),
        'note': note,
        'slotIndex': slotIndex,
      };
}

class SavingPlan {
  final String id;
  final String name;
  final SavingPlanType type;
  final double targetAmount;
  final double? contributionAmount;
  final SavingFrequency? frequency;
  final DateTime startDate;
  final DateTime? endDate;
  final int? totalDays;
  final int? totalWeeks;
  final List<SavingContribution> contributions;
  final bool cancelled;
  final bool manualCompleted;
  final String? icon;
  final String note;
  final DateTime createdAt;
  final DateTime updatedAt;

  const SavingPlan({
    required this.id,
    required this.name,
    required this.type,
    required this.targetAmount,
    this.contributionAmount,
    this.frequency,
    required this.startDate,
    this.endDate,
    this.totalDays,
    this.totalWeeks,
    this.contributions = const [],
    this.cancelled = false,
    this.manualCompleted = false,
    this.icon,
    this.note = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory SavingPlan.fromMap(
    Map<String, dynamic> data, {
    required String id,
  }) {
    SavingPlanType decodeType(String? raw) {
      switch (raw) {
        case 'flexible':
          return SavingPlanType.flexible;
        case 'daysChallenge':
          return SavingPlanType.daysChallenge;
        case 'weeksChallenge':
          return SavingPlanType.weeksChallenge;
        case 'fixed':
        default:
          return SavingPlanType.fixed;
      }
    }

    SavingFrequency? decodeFreq(String? raw) {
      switch (raw) {
        case 'daily':
          return SavingFrequency.daily;
        case 'weekly':
          return SavingFrequency.weekly;
        case 'monthly':
          return SavingFrequency.monthly;
      }
      return null;
    }

    return SavingPlan(
      id: id,
      name: data['name'] as String? ?? '',
      type: decodeType(data['type'] as String?),
      targetAmount: (data['targetAmount'] as num?)?.toDouble() ?? 0,
      contributionAmount:
          (data['contributionAmount'] as num?)?.toDouble(),
      frequency: decodeFreq(data['frequency'] as String?),
      startDate: _readDate(data['startDate']),
      endDate:
          data['endDate'] == null ? null : _readDate(data['endDate']),
      totalDays: (data['totalDays'] as num?)?.toInt(),
      totalWeeks: (data['totalWeeks'] as num?)?.toInt(),
      contributions: (data['contributions'] as List? ?? const [])
          .whereType<Map>()
          .map((m) => SavingContribution.fromMap(
                Map<String, dynamic>.from(m),
              ))
          .toList(),
      cancelled: (data['cancelled'] as bool?) ?? false,
      manualCompleted: (data['manualCompleted'] as bool?) ?? false,
      icon: data['icon'] as String?,
      note: data['note'] as String? ?? '',
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    String encodeType() {
      switch (type) {
        case SavingPlanType.fixed:
          return 'fixed';
        case SavingPlanType.flexible:
          return 'flexible';
        case SavingPlanType.daysChallenge:
          return 'daysChallenge';
        case SavingPlanType.weeksChallenge:
          return 'weeksChallenge';
      }
    }

    String? encodeFreq() {
      switch (frequency) {
        case SavingFrequency.daily:
          return 'daily';
        case SavingFrequency.weekly:
          return 'weekly';
        case SavingFrequency.monthly:
          return 'monthly';
        case null:
          return null;
      }
    }

    return {
      if (includeId) 'id': id,
      'name': name,
      'type': encodeType(),
      'targetAmount': targetAmount,
      'contributionAmount': contributionAmount,
      'frequency': encodeFreq(),
      'startDate': startDate.toIso8601String(),
      'endDate': endDate?.toIso8601String(),
      'totalDays': totalDays,
      'totalWeeks': totalWeeks,
      'contributions': contributions.map((c) => c.toMap()).toList(),
      'cancelled': cancelled,
      'manualCompleted': manualCompleted,
      'icon': icon,
      'note': note,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static const _sentinel = Object();

  SavingPlan copyWith({
    String? id,
    String? name,
    SavingPlanType? type,
    double? targetAmount,
    Object? contributionAmount = _sentinel,
    Object? frequency = _sentinel,
    DateTime? startDate,
    Object? endDate = _sentinel,
    Object? totalDays = _sentinel,
    Object? totalWeeks = _sentinel,
    List<SavingContribution>? contributions,
    bool? cancelled,
    bool? manualCompleted,
    Object? icon = _sentinel,
    String? note,
    DateTime? updatedAt,
  }) {
    return SavingPlan(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      targetAmount: targetAmount ?? this.targetAmount,
      contributionAmount: identical(contributionAmount, _sentinel)
          ? this.contributionAmount
          : contributionAmount as double?,
      frequency: identical(frequency, _sentinel)
          ? this.frequency
          : frequency as SavingFrequency?,
      startDate: startDate ?? this.startDate,
      endDate: identical(endDate, _sentinel)
          ? this.endDate
          : endDate as DateTime?,
      totalDays: identical(totalDays, _sentinel)
          ? this.totalDays
          : totalDays as int?,
      totalWeeks: identical(totalWeeks, _sentinel)
          ? this.totalWeeks
          : totalWeeks as int?,
      contributions: contributions ?? this.contributions,
      cancelled: cancelled ?? this.cancelled,
      manualCompleted: manualCompleted ?? this.manualCompleted,
      icon: identical(icon, _sentinel) ? this.icon : icon as String?,
      note: note ?? this.note,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  // ── Computed ────────────────────────────────────────────────

  double get currentAmount =>
      contributions.fold<double>(0, (s, c) => s + c.amount);

  double get remaining {
    final r = targetAmount - currentAmount;
    return r < 0 ? 0 : r;
  }

  double get progress {
    if (targetAmount <= 0) return 0;
    return (currentAmount / targetAmount).clamp(0.0, 1.0);
  }

  /// For challenge plans: how many slots have been deposited at least
  /// once. Slots are 1-indexed; we count distinct `slotIndex` values
  /// in [contributions].
  int get slotsCompleted {
    final seen = <int>{};
    for (final c in contributions) {
      if (c.slotIndex != null) seen.add(c.slotIndex!);
    }
    return seen.length;
  }

  int? get totalSlots {
    switch (type) {
      case SavingPlanType.daysChallenge:
        return totalDays;
      case SavingPlanType.weeksChallenge:
        return totalWeeks;
      case SavingPlanType.fixed:
      case SavingPlanType.flexible:
        return null;
    }
  }

  SavingPlanStatus get status {
    if (cancelled) return SavingPlanStatus.cancelled;
    if (manualCompleted) return SavingPlanStatus.completed;
    if (currentAmount >= targetAmount && targetAmount > 0) {
      return SavingPlanStatus.completed;
    }
    final slots = totalSlots;
    if (slots != null && slotsCompleted >= slots) {
      return SavingPlanStatus.completed;
    }
    return SavingPlanStatus.active;
  }

  /// Estimated periods remaining at the current contribution cadence.
  /// Null when there's no fixed schedule (flexible plans).
  /// The screen formats this as days / weeks / months as appropriate.
  int? get periodsLeft {
    final amount = contributionAmount;
    if (amount == null || amount <= 0) {
      // Challenge plans: slots remaining.
      final total = totalSlots;
      if (total != null) {
        return (total - slotsCompleted).clamp(0, total);
      }
      return null;
    }
    final left = remaining;
    if (left <= 0) return 0;
    return (left / amount).ceil();
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
