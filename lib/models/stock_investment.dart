import 'package:cloud_firestore/cloud_firestore.dart';

class StockInvestment {
  final String id;
  final String symbol;
  final String? name;
  final double quantity;
  final double buyPrice;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StockInvestment({
    required this.id,
    required this.symbol,
    this.name,
    required this.quantity,
    required this.buyPrice,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  double get totalCost => quantity * buyPrice;

  double currentValue(double currentPrice) => quantity * currentPrice;

  double gainLoss(double currentPrice) => currentValue(currentPrice) - totalCost;

  double gainLossPercent(double currentPrice) =>
      totalCost > 0 ? (gainLoss(currentPrice) / totalCost) * 100 : 0;

  factory StockInvestment.fromMap(Map<String, dynamic> data,
      {required String id}) {
    return StockInvestment(
      id: id,
      symbol: data['symbol'] as String? ?? '',
      name: data['name'] as String?,
      quantity: (data['quantity'] as num?)?.toDouble() ?? 0.0,
      buyPrice: (data['buyPrice'] as num?)?.toDouble() ?? 0.0,
      notes: data['notes'] as String?,
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) {
    return {
      if (includeId) 'id': id,
      'symbol': symbol.toUpperCase(),
      if (name != null && name!.isNotEmpty) 'name': name,
      'quantity': quantity,
      'buyPrice': buyPrice,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  StockInvestment copyWith({
    String? id,
    String? symbol,
    String? name,
    double? quantity,
    double? buyPrice,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return StockInvestment(
      id: id ?? this.id,
      symbol: symbol ?? this.symbol,
      name: name ?? this.name,
      quantity: quantity ?? this.quantity,
      buyPrice: buyPrice ?? this.buyPrice,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      try {
        return DateTime.parse(value);
      } catch (_) {}
    }
    return DateTime.now();
  }
}
