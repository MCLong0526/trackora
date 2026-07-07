import 'package:flutter/cupertino.dart';

import '../../theme/app_theme.dart';

/// Shared travel-expense categories — a richer set mirroring the personal
/// expense categories (was previously only 6 options). Keys are kept lowercase
/// to stay compatible with existing travel-expense records.
const List<String> kTravelCategories = [
  'food',
  'groceries',
  'transport',
  'accommodation',
  'activities',
  'shopping',
  'entertainment',
  'health',
  'bills',
  'general',
];

const Map<String, IconData> kTravelCatIcons = {
  'food': CupertinoIcons.cart_fill,
  'groceries': CupertinoIcons.cube_box_fill,
  'transport': CupertinoIcons.car_fill,
  'accommodation': CupertinoIcons.house_fill,
  'activities': CupertinoIcons.star_fill,
  'shopping': CupertinoIcons.bag_fill,
  'entertainment': CupertinoIcons.film_fill,
  'health': CupertinoIcons.heart_fill,
  'bills': CupertinoIcons.doc_text_fill,
  'general': CupertinoIcons.square_grid_2x2_fill,
};

const Map<String, Color> kTravelCatColors = {
  'food': Color(0xFFFF9500),
  'groceries': Color(0xFF30B0C7),
  'transport': Color(0xFF3478F6),
  'accommodation': Color(0xFF5856D6),
  'activities': Color(0xFFFF2D55),
  'shopping': Color(0xFF34C759),
  'entertainment': Color(0xFFAF52DE),
  'health': Color(0xFFFF6961),
  'bills': Color(0xFFFFCC00),
  'general': Color(0xFF8E8E93),
};

// Travel expenses now use the same category keys as personal expenses
// (capitalized built-ins + custom categories). These helpers first honour the
// legacy lowercase travel map (so old records keep their icon/colour) and fall
// back to the shared personal-expense style for the new/custom keys.
IconData travelCatIcon(String cat) => kTravelCatIcons[cat] ?? styleFor(cat).icon;

Color travelCatColor(String cat) => kTravelCatColors[cat] ?? styleFor(cat).accent;

/// Human-readable label for a travel category key (capitalizes the key).
String travelCatLabel(String cat) =>
    cat.isEmpty ? cat : cat[0].toUpperCase() + cat.substring(1);
