import 'package:flutter/material.dart';

enum MetalType {
  gold,
  silver,
  // Add more here: platinum, palladium, etc.
}

enum MetalAction { buy, sell }

extension MetalTypeX on MetalType {
  String get label {
    switch (this) {
      case MetalType.gold:
        return 'Gold';
      case MetalType.silver:
        return 'Silver';
    }
  }

  String get encode {
    switch (this) {
      case MetalType.gold:
        return 'gold';
      case MetalType.silver:
        return 'silver';
    }
  }

  static MetalType decode(String? raw) {
    switch (raw) {
      case 'gold':
        return MetalType.gold;
      case 'silver':
        return MetalType.silver;
      default:
        return MetalType.gold;
    }
  }

  Color get primaryColor {
    switch (this) {
      case MetalType.gold:
        return const Color(0xFFD4AF37);
      case MetalType.silver:
        return const Color(0xFF9BA5B0);
    }
  }

  Color get bgColor {
    switch (this) {
      case MetalType.gold:
        return const Color(0xFFFFF3C4);
      case MetalType.silver:
        return const Color(0xFFECEDF0);
    }
  }

  String get unit => 'g';
}

extension MetalActionX on MetalAction {
  String get label {
    switch (this) {
      case MetalAction.buy:
        return 'Buy';
      case MetalAction.sell:
        return 'Sell';
    }
  }

  String get encode {
    switch (this) {
      case MetalAction.buy:
        return 'buy';
      case MetalAction.sell:
        return 'sell';
    }
  }

  static MetalAction decode(String? raw) {
    switch (raw) {
      case 'sell':
        return MetalAction.sell;
      default:
        return MetalAction.buy;
    }
  }
}

class PreciousMetal {
  final String id;
  final MetalType metalType;
  final MetalAction action;
  final double weightGrams;
  final double? pricePerGram;
  final double totalAmount;
  final DateTime date;
  final String? notes;
  final String? accountId;
  final DateTime createdAt;

  const PreciousMetal({
    required this.id,
    required this.metalType,
    required this.action,
    required this.weightGrams,
    this.pricePerGram,
    required this.totalAmount,
    required this.date,
    this.notes,
    this.accountId,
    required this.createdAt,
  });

  factory PreciousMetal.fromMap(Map<String, dynamic> data, {required String id}) {
    return PreciousMetal(
      id: id,
      metalType: MetalTypeX.decode(data['metalType'] as String?),
      action: MetalActionX.decode(data['action'] as String?),
      weightGrams: (data['weightGrams'] as num?)?.toDouble() ?? 0.0,
      pricePerGram: (data['pricePerGram'] as num?)?.toDouble(),
      totalAmount: (data['totalAmount'] as num?)?.toDouble() ?? 0.0,
      date: _readDate(data['date']),
      notes: data['notes'] as String?,
      accountId: data['accountId'] as String?,
      createdAt: _readDate(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    return {
      if (includeId) 'id': id,
      'metalType': metalType.encode,
      'action': action.encode,
      'weightGrams': weightGrams,
      if (pricePerGram != null) 'pricePerGram': pricePerGram,
      'totalAmount': totalAmount,
      'date': date.toIso8601String(),
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      if (accountId != null && accountId!.isNotEmpty) 'accountId': accountId,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  PreciousMetal copyWith({
    String? id,
    MetalType? metalType,
    MetalAction? action,
    double? weightGrams,
    double? pricePerGram,
    double? totalAmount,
    DateTime? date,
    String? notes,
    String? accountId,
    DateTime? createdAt,
  }) {
    return PreciousMetal(
      id: id ?? this.id,
      metalType: metalType ?? this.metalType,
      action: action ?? this.action,
      weightGrams: weightGrams ?? this.weightGrams,
      pricePerGram: pricePerGram ?? this.pricePerGram,
      totalAmount: totalAmount ?? this.totalAmount,
      date: date ?? this.date,
      notes: notes ?? this.notes,
      accountId: accountId ?? this.accountId,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) return DateTime.parse(value);
    return DateTime.now();
  }
}
