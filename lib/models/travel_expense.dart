import 'travel_group.dart';

class TravelExpense {
  final String id;
  final String groupId;
  final double amount;
  final String description;
  final String category;
  final DateTime date;
  final String paidByMemberId;
  final List<String> splitAmong;
  final String? notes;
  final String? receiptUrl;
  final String? addedByUserId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Map<String, double>? splitAmounts;
  final String? splitMode;
  /// Currency code for this expense (e.g. 'JPY').
  /// Null → uses the parent group's currency.
  final String? currencyCode;
  /// Exchange rate from [currencyCode] → group's currency at entry time.
  /// Null → 1.0 (same currency or unknown).
  final double? exchangeRate;

  const TravelExpense({
    required this.id,
    required this.groupId,
    required this.amount,
    required this.description,
    required this.category,
    required this.date,
    required this.paidByMemberId,
    required this.splitAmong,
    this.notes,
    this.receiptUrl,
    this.addedByUserId,
    required this.createdAt,
    required this.updatedAt,
    this.splitAmounts,
    this.splitMode,
    this.currencyCode,
    this.exchangeRate,
  });

  factory TravelExpense.fromMap(
    Map<String, dynamic> data, {
    required String id,
    required String groupId,
  }) {
    return TravelExpense(
      id: id,
      groupId: groupId,
      amount: (data['amount'] as num).toDouble(),
      description: data['description'] as String? ?? '',
      category: data['category'] as String? ?? 'general',
      date: TravelGroup.readDate(data['date']),
      paidByMemberId: data['paidByMemberId'] as String,
      splitAmong: List<String>.from(data['splitAmong'] as List? ?? []),
      notes: data['notes'] as String?,
      receiptUrl: data['receiptUrl'] as String?,
      addedByUserId: data['addedByUserId'] as String?,
      createdAt: TravelGroup.readDate(data['createdAt']),
      updatedAt: TravelGroup.readDate(data['updatedAt']),
      splitAmounts: data['splitAmounts'] != null
          ? Map<String, double>.from(
              (data['splitAmounts'] as Map)
                  .map((k, v) => MapEntry(k as String, (v as num).toDouble())))
          : null,
      splitMode: data['splitMode'] as String?,
      currencyCode: data['currencyCode'] as String?,
      exchangeRate: (data['exchangeRate'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    return {
      if (includeId) 'id': id,
      'groupId': groupId,
      'amount': amount,
      'description': description,
      'category': category,
      'date': date.toIso8601String(),
      'paidByMemberId': paidByMemberId,
      'splitAmong': splitAmong,
      'notes': notes,
      'receiptUrl': receiptUrl,
      'addedByUserId': addedByUserId,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (splitAmounts != null) 'splitAmounts': splitAmounts,
      if (splitMode != null) 'splitMode': splitMode,
      if (currencyCode != null) 'currencyCode': currencyCode,
      if (exchangeRate != null) 'exchangeRate': exchangeRate,
    };
  }

  static const _sentinel = Object();

  TravelExpense copyWith({
    double? amount,
    String? description,
    String? category,
    DateTime? date,
    String? paidByMemberId,
    List<String>? splitAmong,
    Object? notes = _sentinel,
    Object? receiptUrl = _sentinel,
    DateTime? updatedAt,
    Map<String, double>? splitAmounts,
    String? splitMode,
    Object? currencyCode = _sentinel,
    Object? exchangeRate = _sentinel,
  }) {
    return TravelExpense(
      id: id,
      groupId: groupId,
      amount: amount ?? this.amount,
      description: description ?? this.description,
      category: category ?? this.category,
      date: date ?? this.date,
      paidByMemberId: paidByMemberId ?? this.paidByMemberId,
      splitAmong: splitAmong ?? this.splitAmong,
      notes: identical(notes, _sentinel) ? this.notes : notes as String?,
      receiptUrl: identical(receiptUrl, _sentinel)
          ? this.receiptUrl
          : receiptUrl as String?,
      addedByUserId: addedByUserId,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      splitAmounts: splitAmounts ?? this.splitAmounts,
      splitMode: splitMode ?? this.splitMode,
      currencyCode: identical(currencyCode, _sentinel)
          ? this.currencyCode
          : currencyCode as String?,
      exchangeRate: identical(exchangeRate, _sentinel)
          ? this.exchangeRate
          : exchangeRate as double?,
    );
  }
}
