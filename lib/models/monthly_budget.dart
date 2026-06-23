/// How the monthly budget is tracked: one overall total, or a per-category
/// breakdown. In [BudgetMode.category] the effective total is the sum of the
/// category amounts.
enum BudgetMode { total, category }

class MonthlyBudget {
  final BudgetMode mode;

  /// User-set total used in [BudgetMode.total].
  final double total;

  /// Per-category amounts used in [BudgetMode.category], keyed by the same
  /// category name stored on expenses (built-in keys + custom names).
  final Map<String, double> categories;

  const MonthlyBudget({
    this.mode = BudgetMode.total,
    this.total = 0,
    this.categories = const {},
  });

  /// Whether per-category sub-budgets have been set.
  bool get isByCategory => categories.isNotEmpty;

  /// Sum of the per-category allocations.
  double get categoryTotal =>
      categories.values.fold(0.0, (s, v) => s + v);

  /// The overall monthly cap. [total] is the user-set cap, but it can never be
  /// less than what's already allocated across categories — if the categories
  /// add up to more, the effective total grows to match.
  double get effectiveTotal => total > categoryTotal ? total : categoryTotal;

  factory MonthlyBudget.fromMap(Map<String, dynamic> m) {
    final rawCats = m['categories'];
    final cats = <String, double>{};
    if (rawCats is Map) {
      rawCats.forEach((k, v) {
        if (v is num && v > 0) cats[k.toString()] = v.toDouble();
      });
    }
    return MonthlyBudget(
      mode: m['mode'] == 'category' ? BudgetMode.category : BudgetMode.total,
      total: (m['monthly'] is num) ? (m['monthly'] as num).toDouble() : 0.0,
      categories: cats,
    );
  }

  Map<String, dynamic> toMap() => {
        'mode': isByCategory ? 'category' : 'total',
        // Keep `monthly` as the effective total so legacy readers still work.
        'monthly': effectiveTotal,
        'categories': categories,
      };

  MonthlyBudget copyWith({
    BudgetMode? mode,
    double? total,
    Map<String, double>? categories,
  }) =>
      MonthlyBudget(
        mode: mode ?? this.mode,
        total: total ?? this.total,
        categories: categories ?? this.categories,
      );
}
