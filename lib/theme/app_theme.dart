import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Brand palette that varies between light and dark mode. Read via
/// `Theme.of(context).extension<BrandColors>()!` or the
/// `context.brand` extension below.
@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  final Color background;
  final Color surface;
  final Color ink;
  final Color inkSoft;
  final Color divider;
  // Pastels are decorative — they stay constant in both modes.
  final Color mint;
  final Color lilac;
  final Color peach;
  final Color butter;
  final Color blush;
  final Color sky;
  final Color sage;
  final Color sand;
  final Color income;
  final Color expense;
  final Color accent;
  final Color accentDark;

  const BrandColors({
    required this.background,
    required this.surface,
    required this.ink,
    required this.inkSoft,
    required this.divider,
    required this.mint,
    required this.lilac,
    required this.peach,
    required this.butter,
    required this.blush,
    required this.sky,
    required this.sage,
    required this.sand,
    required this.income,
    required this.expense,
    required this.accent,
    required this.accentDark,
  });

  static const _lightBackground = Color(0xFFF7F7FC);
  static const _lightSurface = Color(0xFFFFFFFF);
  static const _lightInk = Color(0xFF111111);
  static const _lightInkSoft = Color(0xFF6B6B70);
  static const _lightDivider = Color(0xFFEAEAEC);

  // Dark-mode neutrals tuned to look nice next to the pastel cards.
  static const _darkBackground = Color(0xFF0F0F12);
  static const _darkSurface = Color(0xFF1B1B20);
  static const _darkInk = Color(0xFFF2F2F4);
  static const _darkInkSoft = Color(0xFFA1A1A6);
  static const _darkDivider = Color(0xFF2A2A30);

  static const _mint = Color(0xFFCFEFE2);
  static const _lilac = Color(0xFFE4D7F5);
  static const _peach = Color(0xFFFCD9B6);
  static const _butter = Color(0xFFFCEAB6);
  static const _blush = Color(0xFFFAD3D3);
  static const _sky = Color(0xFFD0E4FB);
  static const _sage = Color(0xFFD8EBC9);
  static const _sand = Color(0xFFEDE5D8);
  static const _income = Color(0xFF59C28A);
  static const _expense = Color(0xFFE96B6B);
  static const _accent = Color(0xFF8FE3D0);
  static const _accentDarkLight = Color(0xFF111111);
  static const _accentDarkDark = Color(0xFFF2F2F4);

  static const light = BrandColors(
    background: _lightBackground,
    surface: _lightSurface,
    ink: _lightInk,
    inkSoft: _lightInkSoft,
    divider: _lightDivider,
    mint: _mint,
    lilac: _lilac,
    peach: _peach,
    butter: _butter,
    blush: _blush,
    sky: _sky,
    sage: _sage,
    sand: _sand,
    income: _income,
    expense: _expense,
    accent: _accent,
    // In light mode the "dark" accent is true black (used for buttons/CTAs).
    accentDark: _accentDarkLight,
  );

  static const dark = BrandColors(
    background: _darkBackground,
    surface: _darkSurface,
    ink: _darkInk,
    inkSoft: _darkInkSoft,
    divider: _darkDivider,
    mint: _mint,
    lilac: _lilac,
    peach: _peach,
    butter: _butter,
    blush: _blush,
    sky: _sky,
    sage: _sage,
    sand: _sand,
    income: _income,
    expense: _expense,
    accent: _accent,
    // In dark mode the "dark" accent flips to off-white so CTAs stay readable.
    accentDark: _accentDarkDark,
  );

  @override
  ThemeExtension<BrandColors> copyWith() => this;

  @override
  ThemeExtension<BrandColors> lerp(
    covariant ThemeExtension<BrandColors>? other,
    double t,
  ) {
    if (other is! BrandColors) return this;
    return BrandColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      inkSoft: Color.lerp(inkSoft, other.inkSoft, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      mint: mint,
      lilac: lilac,
      peach: peach,
      butter: butter,
      blush: blush,
      sky: sky,
      sage: sage,
      sand: sand,
      income: income,
      expense: expense,
      accent: accent,
      accentDark: Color.lerp(accentDark, other.accentDark, t)!,
    );
  }
}

extension BrandColorsX on BuildContext {
  /// Convenience accessor: `context.brand.surface`, etc.
  BrandColors get brand =>
      Theme.of(this).extension<BrandColors>() ?? BrandColors.light;
}

Color foregroundOn(Color background) =>
    background.computeLuminance() < 0.5 ? Colors.white : Colors.black;

/// Backwards-compatible static palette. Existing widgets that use
/// `AppColors.surface` etc. still compile and look fine in light mode.
/// New / migrated widgets should prefer `context.brand.*` so they flip
/// correctly in dark mode.
class AppColors {
  static const background = BrandColors._lightBackground;
  static const surface = BrandColors._lightSurface;
  static const ink = BrandColors._lightInk;
  static const inkSoft = BrandColors._lightInkSoft;
  static const divider = BrandColors._lightDivider;

  static const accentDark = BrandColors._accentDarkLight;
  static const accent = BrandColors._accent;

  static const mint = BrandColors._mint;
  static const lilac = BrandColors._lilac;
  static const peach = BrandColors._peach;
  static const butter = BrandColors._butter;
  static const blush = BrandColors._blush;
  static const sky = BrandColors._sky;
  static const sage = BrandColors._sage;
  static const sand = BrandColors._sand;

  static const income = BrandColors._income;
  static const expense = BrandColors._expense;
}

class AppRadius {
  static const card = 20.0;
  static const chip = 9999.0;
  static const field = 14.0;
  static const sm = 10.0;
}

class AppActionBlue {
  static const color = Color(0xFF0066CC);
  static const colorOnDark = Color(0xFF2997FF);
}

class AppShadows {
  // Minimal surface-lift shadow. Use only on modal sheets and bottom bar.
  static List<BoxShadow> soft = [
    BoxShadow(
      color: const Color(0xFF000000).withValues(alpha: 0.03),
      blurRadius: 12,
      offset: const Offset(0, 4),
    ),
  ];
}

class AppTheme {
  static TextStyle _textStyle({
    required Color color,
    required double fontSize,
    FontWeight fontWeight = FontWeight.w400,
    double? letterSpacing,
  }) {
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: fontWeight,
      letterSpacing: letterSpacing,
    );
  }

  static TextTheme _buildTextTheme(TextTheme base, Color ink, Color inkSoft) {
    return base.copyWith(
      displayLarge: _textStyle(
        fontSize: 40,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.5,
        color: ink,
      ),
      displayMedium: _textStyle(
        fontSize: 34,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.374,
        color: ink,
      ),
      headlineLarge: _textStyle(
        fontSize: 28,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: ink,
      ),
      headlineMedium: _textStyle(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: ink,
      ),
      titleLarge: _textStyle(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: ink,
      ),
      titleMedium: _textStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: ink,
      ),
      bodyLarge: _textStyle(fontSize: 17, letterSpacing: -0.2, color: ink),
      bodyMedium: _textStyle(fontSize: 15, color: ink),
      bodySmall: _textStyle(fontSize: 13, color: inkSoft),
      labelLarge: _textStyle(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: ink,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData.light(useMaterial3: true);
    const brand = BrandColors.light;
    return base.copyWith(
      brightness: Brightness.light,
      scaffoldBackgroundColor: brand.background,
      colorScheme: const ColorScheme.light(
        primary: BrandColors._accentDarkLight,
        onPrimary: Colors.white,
        secondary: BrandColors._accent,
        onSecondary: BrandColors._lightInk,
        surface: BrandColors._lightSurface,
        onSurface: BrandColors._lightInk,
        error: BrandColors._expense,
        onError: Colors.white,
      ),
      textTheme: _buildTextTheme(base.textTheme, brand.ink, brand.inkSoft),
      appBarTheme: AppBarTheme(
        backgroundColor: brand.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: brand.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        primaryColor: brand.accentDark,
        brightness: Brightness.light,
      ),
      dividerColor: brand.divider,
      cardTheme: CardThemeData(
        elevation: 0,
        color: brand.surface,
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand.accentDark,
          foregroundColor: Colors.white,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brand.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide.none,
        ),
        // No visible box/line on focus — fields rely on their fill + the
        // blinking cursor for focus feedback. (Previously this drew a hard
        // black line in light mode that some dense fields' cursor overflowed.)
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide.none,
        ),
        labelStyle: TextStyle(color: brand.inkSoft),
        hintStyle: TextStyle(color: brand.inkSoft),
        prefixIconColor: brand.inkSoft,
        suffixIconColor: brand.inkSoft,
      ),
      extensions: const [BrandColors.light],
    );
  }

  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    const brand = BrandColors.dark;
    return base.copyWith(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: brand.background,
      colorScheme: const ColorScheme.dark(
        primary: BrandColors._accent,
        onPrimary: BrandColors._lightInk,
        secondary: BrandColors._mint,
        onSecondary: BrandColors._lightInk,
        surface: BrandColors._darkSurface,
        onSurface: BrandColors._darkInk,
        error: BrandColors._expense,
        onError: Colors.white,
      ),
      textTheme: _buildTextTheme(base.textTheme, brand.ink, brand.inkSoft),
      appBarTheme: AppBarTheme(
        backgroundColor: brand.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: brand.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
      ),
      cupertinoOverrideTheme: CupertinoThemeData(
        primaryColor: brand.accent,
        brightness: Brightness.dark,
      ),
      dividerColor: brand.divider,
      cardTheme: CardThemeData(
        elevation: 0,
        color: brand.surface,
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: brand.accent,
          foregroundColor: BrandColors._lightInk,
          elevation: 0,
          shadowColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: brand.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide.none,
        ),
        // No visible box/line on focus — fields rely on their fill + the
        // blinking cursor for focus feedback (consistent with light mode).
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.field),
          borderSide: BorderSide.none,
        ),
        labelStyle: TextStyle(color: brand.inkSoft),
        hintStyle: TextStyle(color: brand.inkSoft),
        prefixIconColor: brand.inkSoft,
        suffixIconColor: brand.inkSoft,
      ),
      extensions: const [BrandColors.dark],
    );
  }
}

/// Maps a category name to a pastel background + accent ink color.
class CategoryStyle {
  final Color background;
  final Color accent;
  final IconData icon;
  const CategoryStyle({
    required this.background,
    required this.accent,
    required this.icon,
  });
}

const Map<String, CategoryStyle> kCategoryStyles = {
  'Food': CategoryStyle(
    background: AppColors.peach,
    accent: Color(0xFFB36A1F),
    icon: CupertinoIcons.bag,
  ),
  'Transport': CategoryStyle(
    background: AppColors.sky,
    accent: Color(0xFF2A6FB5),
    icon: CupertinoIcons.car_detailed,
  ),
  'Shopping': CategoryStyle(
    background: AppColors.lilac,
    accent: Color(0xFF6B40A8),
    icon: CupertinoIcons.cart,
  ),
  'Entertainment': CategoryStyle(
    background: AppColors.blush,
    accent: Color(0xFFB23A4A),
    icon: CupertinoIcons.film,
  ),
  'Health': CategoryStyle(
    background: AppColors.sage,
    accent: Color(0xFF3F7E2C),
    icon: CupertinoIcons.heart,
  ),
  'Bills': CategoryStyle(
    background: AppColors.butter,
    accent: Color(0xFFA0801C),
    icon: CupertinoIcons.doc_text,
  ),
  'Groceries': CategoryStyle(
    background: AppColors.mint,
    accent: Color(0xFF1F7A60),
    icon: CupertinoIcons.cube_box,
  ),
  'Salary': CategoryStyle(
    background: AppColors.mint,
    accent: Color(0xFF1F7A60),
    icon: CupertinoIcons.money_dollar_circle,
  ),
  'Others': CategoryStyle(
    background: AppColors.sand,
    accent: Color(0xFF6B6B70),
    icon: CupertinoIcons.square_grid_2x2,
  ),
  'PreciousMetal': CategoryStyle(
    background: Color(0xFFFFF3C4),
    accent: Color(0xFFB8860B),
    icon: CupertinoIcons.star_fill,
  ),
  'Stock': CategoryStyle(
    background: AppColors.sky,
    accent: Color(0xFF2A6FB5),
    icon: CupertinoIcons.chart_bar,
  ),
  'Transfer': CategoryStyle(
    background: AppColors.blush,
    accent: Color(0xFFB23A4A),
    icon: CupertinoIcons.arrow_right_arrow_left_circle_fill,
  ),
};

/// Curated icon set users can pick from when creating a custom category.
/// All icons are referenced statically so they survive icon tree-shaking.
const Map<String, IconData> kCategoryIconChoices = {
  // Shopping / money
  'bag': CupertinoIcons.bag,
  'bagfill': CupertinoIcons.bag_fill,
  'cart': CupertinoIcons.cart,
  'cartfill': CupertinoIcons.cart_fill,
  'creditcard': CupertinoIcons.creditcard,
  'creditcardfill': CupertinoIcons.creditcard_fill,
  'money': CupertinoIcons.money_dollar_circle,
  'dollar': CupertinoIcons.money_dollar,
  'euro': CupertinoIcons.money_euro,
  'pound': CupertinoIcons.money_pound,
  'yen': CupertinoIcons.money_yen,
  'bitcoin': CupertinoIcons.bitcoin,
  'chartbar': CupertinoIcons.chart_bar,
  'chartpie': CupertinoIcons.chart_pie,
  'tag': CupertinoIcons.tag,
  'tagfill': CupertinoIcons.tag_fill,
  'gift': CupertinoIcons.gift,
  'giftfill': CupertinoIcons.gift_fill,
  'cube': CupertinoIcons.cube_box,
  // Transport / travel
  'car': CupertinoIcons.car_detailed,
  'bus': CupertinoIcons.bus,
  'tram': CupertinoIcons.tram_fill,
  'airplane': CupertinoIcons.airplane,
  'map': CupertinoIcons.map,
  'location': CupertinoIcons.location_solid,
  'compass': CupertinoIcons.compass,
  'flag': CupertinoIcons.flag,
  // Home / living
  'house': CupertinoIcons.house,
  'housefill': CupertinoIcons.house_fill,
  'bed': CupertinoIcons.bed_double_fill,
  'building': CupertinoIcons.building_2_fill,
  'umbrella': CupertinoIcons.umbrella,
  'lightbulb': CupertinoIcons.lightbulb,
  'bolt': CupertinoIcons.bolt,
  'drop': CupertinoIcons.drop,
  'flame': CupertinoIcons.flame,
  'wifi': CupertinoIcons.wifi,
  'phone': CupertinoIcons.phone,
  // Entertainment / media
  'film': CupertinoIcons.film,
  'tv': CupertinoIcons.tv,
  'music': CupertinoIcons.music_note,
  'music2': CupertinoIcons.music_note_2,
  'headphones': CupertinoIcons.headphones,
  'mic': CupertinoIcons.mic,
  'gamecontroller': CupertinoIcons.game_controller,
  'camera': CupertinoIcons.camera,
  'photo': CupertinoIcons.photo,
  'book': CupertinoIcons.book,
  'bookmark': CupertinoIcons.bookmark,
  'sports': CupertinoIcons.sportscourt,
  'paw': CupertinoIcons.paw,
  // Health / personal
  'heart': CupertinoIcons.heart,
  'heartfill': CupertinoIcons.heart_fill,
  'bandage': CupertinoIcons.bandage,
  'person': CupertinoIcons.person,
  'people': CupertinoIcons.person_2,
  'family': CupertinoIcons.person_3,
  'star': CupertinoIcons.star,
  'starfill': CupertinoIcons.star_fill,
  // Work / tools / misc
  'briefcase': CupertinoIcons.briefcase,
  'doc': CupertinoIcons.doc_text,
  'folder': CupertinoIcons.folder_fill,
  'mail': CupertinoIcons.mail,
  'chat': CupertinoIcons.chat_bubble_2,
  'pencil': CupertinoIcons.pencil,
  'paintbrush': CupertinoIcons.paintbrush,
  'scissors': CupertinoIcons.scissors,
  'wrench': CupertinoIcons.wrench,
  'hammer': CupertinoIcons.hammer,
  'gear': CupertinoIcons.gear_alt_fill,
  'lock': CupertinoIcons.lock_fill,
  'calendar': CupertinoIcons.calendar,
  'clock': CupertinoIcons.clock,
  'bell': CupertinoIcons.bell,
  'globe': CupertinoIcons.globe,
  'sun': CupertinoIcons.sun_max_fill,
  'moon': CupertinoIcons.moon_fill,
  'cloud': CupertinoIcons.cloud_fill,
  'leaf': CupertinoIcons.leaf_arrow_circlepath,
};

/// Curated pastel-background + accent pairs for custom categories.
const List<({Color background, Color accent})> kCategoryColorChoices = [
  (background: AppColors.peach, accent: Color(0xFFB36A1F)),
  (background: AppColors.sky, accent: Color(0xFF2A6FB5)),
  (background: AppColors.lilac, accent: Color(0xFF6B40A8)),
  (background: AppColors.blush, accent: Color(0xFFB23A4A)),
  (background: AppColors.sage, accent: Color(0xFF3F7E2C)),
  (background: AppColors.butter, accent: Color(0xFFA0801C)),
  (background: AppColors.mint, accent: Color(0xFF1F7A60)),
  (background: AppColors.sand, accent: Color(0xFF6B6B70)),
  (background: Color(0xFFFFF3C4), accent: Color(0xFFB8860B)),
];

IconData categoryIconFor(String iconKey) =>
    kCategoryIconChoices[iconKey] ?? CupertinoIcons.tag;

/// Builds a [CategoryStyle] for a custom category from its stored icon key and
/// colour index.
CategoryStyle customCategoryStyle({
  required String iconKey,
  required int colorIndex,
}) {
  final c = kCategoryColorChoices[colorIndex % kCategoryColorChoices.length];
  return CategoryStyle(
    background: c.background,
    accent: c.accent,
    icon: categoryIconFor(iconKey),
  );
}

/// Runtime registry of user-defined category styles, keyed by category name.
/// Kept in sync with the custom categories provider so [styleFor] resolves
/// custom categories the same way it does built-ins.
final Map<String, CategoryStyle> _customCategoryStyles = {};

void setCustomCategoryStyles(Map<String, CategoryStyle> styles) {
  _customCategoryStyles
    ..clear()
    ..addAll(styles);
}

CategoryStyle styleFor(String category) =>
    kCategoryStyles[category] ??
    _customCategoryStyles[category] ??
    kCategoryStyles['Others']!;
