import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'i18n.dart';

class PrefsService {
  static const _kCurrency = 'currency_symbol';
  static const _kCurrencyCode = 'currency_code';
  static const _kThemeMode = 'theme_mode';
  static const _kAppLocale = 'app_locale';
  static const _kBalanceVisible = 'balance_visible';
  static const _kHomeCardsVisible = 'home_cards_visible';
  static const _kHomeCardOrder = 'home_card_order';
  static const _kMoneyHubModulesVisible = 'money_hub_modules_visible';
  static const _kMoneyHubSeenModules = 'money_hub_seen_modules';
  static const _kMoneyHubOrder = 'money_hub_order';
  static const _kStatsSectionsVisible = 'stats_sections_visible';
  static const _kStatsCardOrder = 'stats_card_order';
  static const _kStatsHiddenCards = 'stats_hidden_cards';
  static const _kLiveActivityEnabled = 'live_activity_enabled';
  static const _kFirstLaunchDone = 'first_launch_done';
  static const _kUseCustomCycle = 'use_custom_cycle';
  static const _kCycleDayStart = 'cycle_day_start';
  static const _kMoneyHubDragHintShown = 'money_hub_drag_hint_shown';
  static const _kUserName = 'user_name';
  static const _kQuickAddOrder = 'quick_add_order';

  static const defaultHomeCards = <String>[
    'totalBalance',
    'monthlyBudget',
    'savingPlans',
    'borrowLending',
  ];

  static const defaultMoneyHubModules = <String>[
    'installments',
    'borrowLending',
    'savingPlans',
    'monthlyBudget',
    'people',
    'travelGroups',
    'investments',
    'groups',
    'expenseCycle',
  ];

  static const defaultMoneyHubOrder = <String>[
    'monthlyBudget',
    'savingPlans',
    'borrowLending',
    'installments',
    'people',
    'travelGroups',
    'investments',
    'groups',
    'expenseCycle',
  ];

  static const defaultStatsSections = <String>['importantData', 'donutChart'];

  /// Top-to-bottom order of the Statistics report cards. Long-press drag in the
  /// stats page rewrites this; unknown/new ids are appended on read.
  static const defaultStatsCardOrder = <String>[
    'donutChart',
    'monthlyBudget',
    'importantData',
    'groupSpend',
  ];

  /// Whether the user wants the home balance to be readable. Default
  /// `true` (shown). Persisted so the choice survives app restart.
  Future<bool> balanceVisible() async {
    final p = await _prefsOrNull();
    if (p == null) return true;
    return p.getBool(_kBalanceVisible) ?? true;
  }

  Future<void> setBalanceVisible(bool visible) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setBool(_kBalanceVisible, visible);
  }

  /// Returns true if the first-launch currency setup has been completed.
  Future<bool> isFirstLaunchDone() async {
    final p = await _prefsOrNull();
    if (p == null) return true; // default to done on error
    return p.getBool(_kFirstLaunchDone) ?? false;
  }

  Future<void> markFirstLaunchDone() async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setBool(_kFirstLaunchDone, true);
  }

  Future<String> userName() async {
    final p = await _prefsOrNull();
    if (p == null) return '';
    return p.getString(_kUserName) ?? '';
  }

  Future<void> setUserName(String name) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    if (name.trim().isEmpty) {
      await p.remove(_kUserName);
    } else {
      await p.setString(_kUserName, name.trim());
    }
  }

  // Per-user display name cache — avoids cross-account name bleed.
  Future<String> userNameForUid(String uid) async {
    final p = await _prefsOrNull();
    if (p == null) return '';
    return p.getString('${_kUserName}_$uid') ?? '';
  }

  Future<void> setUserNameForUid(String uid, String name) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    if (name.trim().isEmpty) {
      await p.remove('${_kUserName}_$uid');
    } else {
      await p.setString('${_kUserName}_$uid', name.trim());
    }
  }

  Future<bool> isDragHintShown() async {
    final p = await _prefsOrNull();
    if (p == null) return true;
    return p.getBool(_kMoneyHubDragHintShown) ?? false;
  }

  Future<void> markDragHintShown() async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setBool(_kMoneyHubDragHintShown, true);
  }

  Future<List<String>> homeCardOrder() async {
    final p = await _prefsOrNull();
    if (p == null) return defaultHomeCards;
    final saved = p.getStringList(_kHomeCardOrder);
    if (saved == null) return defaultHomeCards;
    final all = defaultHomeCards.toSet();
    final result = saved.where(all.contains).toList();
    for (final id in defaultHomeCards) {
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }

  Future<void> setHomeCardOrder(List<String> order) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setStringList(_kHomeCardOrder, order);
  }

  Future<List<String>> statsCardOrder() async {
    final p = await _prefsOrNull();
    if (p == null) return defaultStatsCardOrder;
    final saved = p.getStringList(_kStatsCardOrder);
    if (saved == null) return defaultStatsCardOrder;
    final all = defaultStatsCardOrder.toSet();
    final result = saved.where(all.contains).toList();
    for (final id in defaultStatsCardOrder) {
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }

  Future<void> setStatsCardOrder(List<String> order) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setStringList(_kStatsCardOrder, order);
  }

  /// Stats report cards the user has hidden (via the per-card hide button in
  /// rearrange mode). Empty by default — every available card is shown.
  Future<Set<String>> statsHiddenCards() async {
    final p = await _prefsOrNull();
    if (p == null) return <String>{};
    return (p.getStringList(_kStatsHiddenCards) ?? const []).toSet();
  }

  Future<void> setStatsHiddenCards(Set<String> ids) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setStringList(_kStatsHiddenCards, ids.toList());
  }

  Future<Set<String>> visibleHomeCards() async {
    final p = await _prefsOrNull();
    if (p == null) return defaultHomeCards.toSet();
    return _decodeVisibleSet(
      p.getStringList(_kHomeCardsVisible),
      defaultHomeCards,
    );
  }

  Future<void> setVisibleHomeCards(Set<String> ids) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setStringList(
      _kHomeCardsVisible,
      _sanitizeVisibleSet(ids, defaultHomeCards).toList(),
    );
  }

  Future<Set<String>> visibleMoneyHubModules() async {
    final p = await _prefsOrNull();
    if (p == null) return defaultMoneyHubModules.toSet();
    final rawVisible = p.getStringList(_kMoneyHubModulesVisible);
    if (rawVisible == null) return defaultMoneyHubModules.toSet();
    var visible = _decodeVisibleSet(rawVisible, defaultMoneyHubModules);
    // Auto-show any newly added modules (not previously seen by the user).
    final seen = p.getStringList(_kMoneyHubSeenModules)?.toSet() ?? {};
    for (final id in defaultMoneyHubModules) {
      if (!seen.contains(id)) visible = {...visible, id};
    }
    await p.setStringList(_kMoneyHubSeenModules, defaultMoneyHubModules);
    return visible;
  }

  Future<void> setVisibleMoneyHubModules(Set<String> ids) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setStringList(
      _kMoneyHubModulesVisible,
      _sanitizeVisibleSet(ids, defaultMoneyHubModules).toList(),
    );
  }

  Future<List<String>> moneyHubOrder() async {
    final p = await _prefsOrNull();
    if (p == null) return defaultMoneyHubOrder;
    final saved = p.getStringList(_kMoneyHubOrder);
    if (saved == null) return defaultMoneyHubOrder;
    final all = defaultMoneyHubOrder.toSet();
    final result = saved.where(all.contains).toList();
    for (final id in defaultMoneyHubOrder) {
      if (!result.contains(id)) result.add(id);
    }
    return result;
  }

  Future<void> setMoneyHubOrder(List<String> order) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setStringList(_kMoneyHubOrder, order);
  }

  Future<Set<String>> visibleStatsSections() async {
    final p = await _prefsOrNull();
    if (p == null) return defaultStatsSections.toSet();
    return _decodeVisibleSet(
      p.getStringList(_kStatsSectionsVisible),
      defaultStatsSections,
    );
  }

  Future<void> setVisibleStatsSections(Set<String> ids) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setStringList(
      _kStatsSectionsVisible,
      _sanitizeVisibleSet(ids, defaultStatsSections).toList(),
    );
  }

  Future<AppLocale> appLocale() async {
    final p = await _prefsOrNull();
    if (p == null) return AppLocale.system;
    return AppLocale.decode(p.getString(_kAppLocale));
  }

  Future<void> setAppLocale(AppLocale locale) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setString(_kAppLocale, locale.encode());
  }

  Future<String> currencySymbol() async {
    final p = await _prefsOrNull();
    if (p == null) return '\$';
    return p.getString(_kCurrency) ?? '\$';
  }

  Future<String> currencyCode() async {
    final p = await _prefsOrNull();
    if (p == null) return 'USD';
    return p.getString(_kCurrencyCode) ?? 'USD';
  }

  Future<void> setCurrency(String code, String symbol) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setString(_kCurrencyCode, code);
    await p.setString(_kCurrency, symbol);
  }

  Future<bool> useCustomCycle() async {
    final p = await _prefsOrNull();
    if (p == null) return false;
    return p.getBool(_kUseCustomCycle) ?? false;
  }

  Future<void> setUseCustomCycle(bool value) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setBool(_kUseCustomCycle, value);
  }

  Future<int> cycleDayStart() async {
    final p = await _prefsOrNull();
    if (p == null) return 1;
    return p.getInt(_kCycleDayStart) ?? 1;
  }

  Future<void> setCycleDayStart(int day) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setInt(_kCycleDayStart, day.clamp(1, 28));
  }

  static const defaultQuickAddOrder = <int>[0, 1, 2, 3, 4, 5];

  Future<List<int>> quickAddOrder() async {
    final p = await _prefsOrNull();
    if (p == null) return defaultQuickAddOrder;
    final saved = p.getStringList(_kQuickAddOrder);
    if (saved == null || saved.length != 6) return defaultQuickAddOrder;
    try {
      final order = saved.map(int.parse).toList();
      if (order.toSet().length == 6 && order.every((i) => i >= 0 && i < 6)) {
        return order;
      }
    } catch (_) {}
    return defaultQuickAddOrder;
  }

  Future<void> setQuickAddOrder(List<int> order) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setStringList(_kQuickAddOrder, order.map((i) => '$i').toList());
  }

  Future<bool> liveActivityEnabled() async {
    final p = await _prefsOrNull();
    if (p == null) return false;
    return p.getBool(_kLiveActivityEnabled) ?? false;
  }

  Future<void> setLiveActivityEnabled(bool enabled) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setBool(_kLiveActivityEnabled, enabled);
  }

  /// Stored as one of: 'system', 'light', 'dark'. Default is 'system'.
  Future<ThemeMode> themeMode() async {
    final p = await _prefsOrNull();
    if (p == null) return ThemeMode.system;
    return _decodeThemeMode(p.getString(_kThemeMode));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final p = await _prefsOrNull();
    if (p == null) return;
    await p.setString(_kThemeMode, _encodeThemeMode(mode));
  }

  Future<SharedPreferences?> _prefsOrNull() async {
    try {
      return await SharedPreferences.getInstance();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } on ArgumentError {
      return null;
    }
  }

  static ThemeMode _decodeThemeMode(String? raw) {
    switch (raw) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
      default:
        return ThemeMode.system;
    }
  }

  static String _encodeThemeMode(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }

  static Set<String> _decodeVisibleSet(List<String>? raw, List<String> all) {
    if (raw == null) return all.toSet();
    return _sanitizeVisibleSet(raw.toSet(), all);
  }

  static Set<String> _sanitizeVisibleSet(Set<String> ids, List<String> all) {
    final allowed = all.toSet();
    final visible = ids.where(allowed.contains).toSet();
    if (visible.isEmpty) return {all.first};
    return visible;
  }
}

const kSupportedCurrencies = <String, String>{
  'USD': '\$',
  'EUR': '€',
  'GBP': '£',
  'JPY': '¥',
  'CNY': '¥',
  'INR': '₹',
  'MYR': 'RM',
  'SGD': 'S\$',
  'AUD': 'A\$',
  'CAD': 'C\$',
  'HKD': 'HK\$',
  'KRW': '₩',
};
