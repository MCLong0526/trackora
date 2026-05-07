import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

/// Pushes summary numbers to the home-screen widget and the paired watch app.
/// The iOS/Android widget extension reads these via shared UserDefaults.
/// The watchOS app receives an applicationContext update via WCSession so it
/// shows live totals without depending solely on the App Group.
class WidgetSyncService {
  static const _appGroupId = 'group.com.michaelchia.trackora';
  static const _iosWidgetName = 'TrackoraWidget';
  static const _androidWidgetProvider = 'TrackoraWidgetProvider';
  static bool _enabled =
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  final WatchConnectivity _watch = WatchConnectivity();

  Future<void> init() async {
    if (!_enabled) return;
    await _runOptional(HomeWidget.setAppGroupId(_appGroupId));
  }

  Future<void> push({
    required String currencySymbol,
    required double monthSpent,
    required double monthBudget,
    required double savings,
    required double upcomingInstallments,
    required double budgetableSpent,
    String localeCode = 'system',
    double todaySpent = 0,
    double weekSpent = 0,
  }) async {
    if (!_enabled) return;
    await _runOptional(() async {
      await HomeWidget.saveWidgetData<String>('currency', currencySymbol);
      await HomeWidget.saveWidgetData<String>('appLocale', localeCode);
      await HomeWidget.saveWidgetData<double>('monthSpent', monthSpent);
      await HomeWidget.saveWidgetData<double>('monthBudget', monthBudget);
      await HomeWidget.saveWidgetData<double>('savings', savings);
      await HomeWidget.saveWidgetData<double>(
        'upcomingInstallments',
        upcomingInstallments,
      );
      // Spend that counts against the budget (bills + installments excluded).
      await HomeWidget.saveWidgetData<double>(
        'budgetableSpent',
        budgetableSpent,
      );
      // Today / week totals power the widget's secondary copy lines.
      await HomeWidget.saveWidgetData<double>('todaySpent', todaySpent);
      await HomeWidget.saveWidgetData<double>('weekSpent', weekSpent);
      await HomeWidget.updateWidget(
        iOSName: _iosWidgetName,
        androidName: _androidWidgetProvider,
      );
    }());

    // Push the same totals to the paired Apple Watch via WCSession
    // applicationContext so the watch gets live data even on first install,
    // without depending solely on the App Group UserDefaults being populated.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final supported = await _watch.isSupported;
        if (supported) {
          await _watch.updateApplicationContext({
            'currency': currencySymbol,
            'monthSpent': monthSpent,
            'monthBudget': monthBudget,
            'savings': savings,
            'budgetableSpent': budgetableSpent,
          });
        }
      } on MissingPluginException {
        // watch_connectivity not available — skip
      } catch (_) {
        // Best-effort; never block the main app
      }
    }
  }

  Future<void> setLocale(String localeCode) async {
    if (!_enabled) return;
    await _runOptional(() async {
      await HomeWidget.saveWidgetData<String>('appLocale', localeCode);
      await HomeWidget.updateWidget(
        iOSName: _iosWidgetName,
        androidName: _androidWidgetProvider,
      );
    }());
  }

  /// Optimistically reflects a quick expense before the next dashboard rebuild
  /// pushes the authoritative totals.
  Future<void> nudgeQuickExpense(
    double amount, {
    bool budgetable = true,
    double? nextDraftAmount,
  }) async {
    if (!_enabled) return;
    final todaySpent = await _getOptional<double>('todaySpent') ?? 0;
    final weekSpent = await _getOptional<double>('weekSpent') ?? 0;
    final monthSpent = await _getOptional<double>('monthSpent') ?? 0;
    final budgetableSpent = await _getOptional<double>('budgetableSpent') ?? 0;
    final savings = await _getOptional<double>('savings') ?? 0;

    await _runOptional(() async {
      await HomeWidget.saveWidgetData<double>(
        'todaySpent',
        todaySpent + amount,
      );
      await HomeWidget.saveWidgetData<double>('weekSpent', weekSpent + amount);
      await HomeWidget.saveWidgetData<double>(
        'monthSpent',
        monthSpent + amount,
      );
      if (budgetable) {
        await HomeWidget.saveWidgetData<double>(
          'budgetableSpent',
          budgetableSpent + amount,
        );
      }
      await HomeWidget.saveWidgetData<double>('savings', savings - amount);
      if (nextDraftAmount != null && nextDraftAmount > 0) {
        await HomeWidget.saveWidgetData<double>(
          'widgetDraftAmount',
          nextDraftAmount,
        );
      }
      await HomeWidget.updateWidget(
        iOSName: _iosWidgetName,
        androidName: _androidWidgetProvider,
      );
    }());
  }

  Future<void> _runOptional(Future<void> future) async {
    try {
      await future;
    } on MissingPluginException {
      _enabled = false;
    } on PlatformException {
      // Widget sync is best-effort; the main app must still open.
    } catch (_) {
      // Keep launch and saves resilient even if the native widget bridge fails.
    }
  }

  Future<T?> _getOptional<T>(String key) async {
    try {
      return await HomeWidget.getWidgetData<T>(key);
    } on MissingPluginException {
      _enabled = false;
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      return null;
    }
  }
}
