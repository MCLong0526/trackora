import 'package:flutter/cupertino.dart';

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

IconData travelCatIcon(String cat) =>
    kTravelCatIcons[cat] ?? CupertinoIcons.square_grid_2x2_fill;

Color travelCatColor(String cat) =>
    kTravelCatColors[cat] ?? const Color(0xFF8E8E93);

/// Human-readable label for a travel category key (capitalizes the key).
String travelCatLabel(String cat) =>
    cat.isEmpty ? cat : cat[0].toUpperCase() + cat.substring(1);
