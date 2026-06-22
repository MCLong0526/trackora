/// Built-in expense and income category keys. These map to translations
/// (`category.<key>`) and to styles in `kCategoryStyles`. Users cannot rename
/// or delete these; custom categories are stored separately as
/// [CustomCategory] and appended to these lists at runtime.
const List<String> kDefaultExpenseCategories = [
  'Food',
  'Groceries',
  'Transport',
  'Shopping',
  'Entertainment',
  'Health',
  'Bills',
  'PreciousMetal',
  'Stock',
  'Others',
];

const List<String> kDefaultIncomeCategories = [
  'Salary',
  'PreciousMetal',
  'Stock',
  'Others',
];

/// Built-in category keys that double as system categories the user should not
/// be able to shadow with a custom name (besides the visible defaults above).
const List<String> kReservedCategoryKeys = [
  'Transfer',
];
