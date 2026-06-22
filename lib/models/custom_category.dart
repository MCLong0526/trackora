/// A user-defined expense or income category with a custom name, icon and
/// colour. Stored per-user in Firestore (online) and Hive (offline).
///
/// The category [name] is what gets written into `Expense.category`, exactly
/// like the built-in categories, so custom categories flow through the rest of
/// the app (statistics, budgets, cards) unchanged. Names are unique per [type]
/// (case-insensitive) and must not collide with a built-in category.
class CustomCategory {
  final String id;
  final String name;

  /// Key into `kCategoryIconChoices` (see app_theme.dart). Falls back to a
  /// generic icon when unknown.
  final String iconKey;

  /// Index into `kCategoryColorChoices` (see app_theme.dart).
  final int colorIndex;

  /// Whether this category is for income (`true`) or expense (`false`).
  final bool isIncome;

  final DateTime createdAt;
  final DateTime updatedAt;

  const CustomCategory({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.colorIndex,
    required this.isIncome,
    required this.createdAt,
    required this.updatedAt,
  });

  factory CustomCategory.fromMap(Map<String, dynamic> data, {required String id}) {
    return CustomCategory(
      id: id,
      name: (data['name'] as String? ?? '').trim(),
      iconKey: data['iconKey'] as String? ?? 'tag',
      colorIndex: (data['colorIndex'] as num?)?.toInt() ?? 0,
      isIncome: data['isIncome'] as bool? ?? false,
      createdAt: _readDate(data['createdAt']),
      updatedAt: _readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toMap({bool includeId = false}) => {
        if (includeId) 'id': id,
        'name': name,
        'iconKey': iconKey,
        'colorIndex': colorIndex,
        'isIncome': isIncome,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  CustomCategory copyWith({
    String? id,
    String? name,
    String? iconKey,
    int? colorIndex,
    bool? isIncome,
    DateTime? updatedAt,
  }) {
    return CustomCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      iconKey: iconKey ?? this.iconKey,
      colorIndex: colorIndex ?? this.colorIndex,
      isIncome: isIncome ?? this.isIncome,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static DateTime _readDate(Object? value) {
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    if (value is String) {
      final d = DateTime.tryParse(value);
      if (d != null) return d;
    }
    if (value != null) {
      try {
        final date = (value as dynamic).toDate();
        if (date is DateTime) return date;
      } catch (_) {}
    }
    return DateTime.now();
  }
}
