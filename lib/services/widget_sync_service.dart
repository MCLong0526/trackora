import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import '../models/account.dart';
import '../models/expense.dart';
import 'live_activity_service.dart';

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

  bool _watchUnavailable = false;
  WatchConnectivity? _watch;

  // Last context successfully pushed to the Watch so we can re-send it
  // when the WCSession activates without waiting for a dashboard rebuild.
  Map<String, dynamic>? _lastWatchContext;

  Future<void> init() async {
    if (!_enabled) return;
    await _runOptional(() => HomeWidget.setAppGroupId(_appGroupId));
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
    List<Account> accounts = const [],
    List<Expense> recentExpenses = const [],
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
    });

    // Keep Live Activity in sync with latest spending (no-ops if not active).
    LiveActivityService.update(
      currency: currencySymbol,
      todaySpent: todaySpent,
    );

    // Push the same totals to the paired Apple Watch via WCSession
    // applicationContext so the watch gets live data even on first install,
    // without depending solely on the App Group UserDefaults being populated.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      try {
        final watch = _watchClient();
        if (watch == null) return;
        final supported = await watch.isSupported;
        if (supported) {
          final expensesPayload = recentExpenses
              .take(5)
              .map(
                (e) => {
                  'id': e.id,
                  'amount': e.amount,
                  'category': e.category,
                  'note': e.note,
                  'type': e.type.name,
                  'date': e.date.millisecondsSinceEpoch / 1000.0,
                },
              )
              .toList();
          final accountsPayload = accounts
              .map((a) => {'id': a.id, 'name': a.name})
              .toList();
          final ctx = {
            'currency': currencySymbol,
            'monthSpent': monthSpent,
            'monthBudget': monthBudget,
            'savings': savings,
            'budgetableSpent': budgetableSpent,
            'recentExpenses': expensesPayload,
            'accounts': accountsPayload,
          };
          await watch.updateApplicationContext(ctx);
          _lastWatchContext = ctx;
        }
      } on MissingPluginException {
        // watch_connectivity not available — skip
      } on ArgumentError catch (e) {
        debugPrint('[WidgetSync] watch native bridge unavailable: $e');
        _watchUnavailable = true;
      } catch (_) {
        // Best-effort; never block the main app
      }
    }
  }

  /// Re-sends the last watch context after WCSession activation completes.
  /// Called via the onSessionActivated callback so the Watch gets data without
  /// waiting for the next dashboard rebuild.
  Future<void> repushToWatch() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;
    final ctx = _lastWatchContext;
    if (ctx == null) return;
    try {
      final watch = _watchClient();
      if (watch == null) return;
      final supported = await watch.isSupported;
      if (supported) {
        await watch.updateApplicationContext(ctx);
      }
    } on MissingPluginException {
      // watch_connectivity not available
    } on ArgumentError catch (e) {
      debugPrint('[WidgetSync] watch native bridge unavailable: $e');
      _watchUnavailable = true;
    } catch (_) {
      // Best-effort
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
    });
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
    });
  }

  Future<void> _runOptional(FutureOr<void> Function() action) async {
    try {
      await action();
    } on MissingPluginException {
      _enabled = false;
    } on PlatformException {
      // Widget sync is best-effort; the main app must still open.
    } on ArgumentError catch (e) {
      debugPrint('[WidgetSync] native bridge unavailable: $e');
      _enabled = false;
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
    } on ArgumentError catch (e) {
      debugPrint('[WidgetSync] native bridge unavailable: $e');
      _enabled = false;
      return null;
    } catch (_) {
      return null;
    }
  }

  WatchConnectivity? _watchClient() {
    if (_watchUnavailable) return null;
    try {
      return _watch ??= WatchConnectivity();
    } on ArgumentError catch (e) {
      debugPrint('[WidgetSync] watch native bridge unavailable: $e');
      _watchUnavailable = true;
      return null;
    } catch (e) {
      debugPrint('[WidgetSync] watch bridge unavailable: $e');
      _watchUnavailable = true;
      return null;
    }
  }
}
