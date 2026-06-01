import 'expense_group.dart';

class GroupExpenseItem {
  final String id;
  final String groupId;
  final String description;
  final double amount;
  final String paidBy;
  final String? paidByAccountId;
  final List<String> splitBetween;
  // Optional: maps uid → percent (0–100). When present, overrides equal split.
  final Map<String, double>? splitPercents;
  final String category;
  final DateTime date;
  final String createdBy;
  final String? notes;
  final String? receiptUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const GroupExpenseItem({
    required this.id,
    required this.groupId,
    required this.description,
    required this.amount,
    required this.paidBy,
    this.paidByAccountId,
    required this.splitBetween,
    this.splitPercents,
    required this.category,
    required this.date,
    required this.createdBy,
    this.notes,
    this.receiptUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory GroupExpenseItem.fromMap(
    Map<String, dynamic> data, {
    required String id,
    required String groupId,
  }) {
    return GroupExpenseItem(
      id: id,
      groupId: groupId,
      description: data['description'] as String? ?? '',
      amount: (data['amount'] as num).toDouble(),
      paidBy: data['paidBy'] as String? ?? '',
      paidByAccountId: data['paidByAccountId'] as String?,
      splitBetween: List<String>.from(data['splitBetween'] as List? ?? []),
      splitPercents: (data['splitPercents'] as Map?)?.map(
        (k, v) => MapEntry(k as String, (v as num).toDouble()),
      ),
      category: data['category'] as String? ?? 'Others',
      date: ExpenseGroup.readDate(data['date']),
      createdBy: data['createdBy'] as String? ?? '',
      notes: data['notes'] as String?,
      receiptUrl: data['receiptUrl'] as String?,
      createdAt: ExpenseGroup.readDate(data['createdAt']),
      updatedAt: ExpenseGroup.readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    return {
      if (includeId) 'id': id,
      'groupId': groupId,
      'description': description,
      'amount': amount,
      'paidBy': paidBy,
      if (paidByAccountId != null) 'paidByAccountId': paidByAccountId,
      'splitBetween': splitBetween,
      if (splitPercents != null) 'splitPercents': splitPercents,
      'category': category,
      'date': date.toIso8601String(),
      'createdBy': createdBy,
      if (notes != null) 'notes': notes,
      if (receiptUrl != null) 'receiptUrl': receiptUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  static const _sentinel = Object();

  GroupExpenseItem copyWith({
    String? description,
    double? amount,
    String? paidBy,
    Object? paidByAccountId = _sentinel,
    List<String>? splitBetween,
    Object? splitPercents = _sentinel,
    String? category,
    DateTime? date,
    Object? notes = _sentinel,
    Object? receiptUrl = _sentinel,
    DateTime? updatedAt,
  }) {
    return GroupExpenseItem(
      id: id,
      groupId: groupId,
      description: description ?? this.description,
      amount: amount ?? this.amount,
      paidBy: paidBy ?? this.paidBy,
      paidByAccountId: identical(paidByAccountId, _sentinel)
          ? this.paidByAccountId
          : paidByAccountId as String?,
      splitBetween: splitBetween ?? this.splitBetween,
      splitPercents: identical(splitPercents, _sentinel)
          ? this.splitPercents
          : splitPercents as Map<String, double>?,
      category: category ?? this.category,
      date: date ?? this.date,
      createdBy: createdBy,
      notes: identical(notes, _sentinel) ? this.notes : notes as String?,
      receiptUrl: identical(receiptUrl, _sentinel)
          ? this.receiptUrl
          : receiptUrl as String?,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
