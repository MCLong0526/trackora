import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import '../models/expense.dart';
import '../repositories/account_repository.dart';
import '../repositories/expense_repository.dart';
import '../services/prefs_service.dart';

/// Bridge between the Flutter app and the paired watchOS app.
///
/// Watch → phone: the iOS WatchUserInfoBridge receives transferUserInfo
///   messages and delivers them here via the `trackora/watch_queue`
///   MethodChannel (`onWatchUserInfo`). We also keep a messageStream
///   listener as a fallback for sendMessage-based delivery.
///
/// Phone → watch: WidgetSyncService.push() pushes the full dashboard
///   snapshot (currency + totals + accounts + recentExpenses) via
///   WCSession applicationContext on every dashboard rebuild.
class WatchService {
  static const _watchQueueChannel = MethodChannel('trackora/watch_queue');
  StreamSubscription<Map<String, dynamic>>? _sub;
  WatchConnectivity? _watch;
  bool _watchUnavailable = false;

  String? _userId;
  ExpenseRepository? _repository;
  void Function()? _onSessionActivated;

  bool _subscribed = false;

  /// Call once the user is known. Safe to call multiple times — subsequent
  /// calls update the userId/repository references without re-subscribing.
  Future<void> attach({
    required String userId,
    required ExpenseRepository repository,
    required AccountRepository accountRepository,
    required PrefsService prefsService,
    void Function()? onSessionActivated,
  }) async {
    _userId = userId;
    _repository = repository;
    _onSessionActivated = onSessionActivated;

    if (_subscribed) return;
    _subscribed = true;

    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    // Handle transferUserInfo messages routed via WatchUserInfoBridge.
    _watchQueueChannel.setMethodCallHandler((call) async {
      if (call.method == 'onSessionActivated') {
        _onSessionActivated?.call();
        return;
      }
      if (call.method != 'onWatchUserInfo') return;
      final uid = _userId;
      final repo = _repository;
      if (uid == null || repo == null) return;
      try {
        final userInfo = Map<String, dynamic>.from(call.arguments as Map);
        await _handle(userInfo, userId: uid, repository: repo);
      } catch (e, st) {
        debugPrint('[WatchService] onWatchUserInfo error: $e\n$st');
      }
    });

    // Also subscribe to messageStream as a fallback for sendMessage delivery.
    final bool supported;
    try {
      final watch = _watchClient();
      if (watch == null) return;
      supported = await watch.isSupported;
    } on MissingPluginException {
      return;
    } on ArgumentError catch (e) {
      debugPrint('[WatchService] native bridge unavailable: $e');
      _watchUnavailable = true;
      return;
    } catch (_) {
      return;
    }
    if (!supported) return;

    try {
      final watch = _watchClient();
      if (watch == null) return;
      _sub = watch.messageStream.listen(
        (message) async {
          final uid = _userId;
          final repo = _repository;
          if (uid == null || repo == null) return;
          try {
            await _handle(message, userId: uid, repository: repo);
          } catch (e, st) {
            debugPrint('[WatchService] messageStream error: $e\n$st');
          }
        },
        onError: (dynamic e) {
          debugPrint('[WatchService] messageStream stream error: $e');
        },
      );
    } on MissingPluginException {
      return;
    } on ArgumentError catch (e) {
      debugPrint('[WatchService] native bridge unavailable: $e');
      _watchUnavailable = true;
      return;
    } catch (_) {
      return;
    }
  }

  /// Full context sync is handled by WidgetSyncService.push() which pushes
  /// currency + monthSpent + budget + savings + accounts + recentExpenses.
  /// Pushing partial data here would replace that full context, so this is
  /// intentionally a no-op. Call WidgetSyncService.push() for a full refresh.
  Future<void> syncToWatch() async {}

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _subscribed = false;
  }

  WatchConnectivity? _watchClient() {
    if (_watchUnavailable) return null;
    try {
      return _watch ??= WatchConnectivity();
    } on ArgumentError catch (e) {
      debugPrint('[WatchService] native bridge unavailable: $e');
      _watchUnavailable = true;
      return null;
    } catch (e) {
      debugPrint('[WatchService] bridge unavailable: $e');
      _watchUnavailable = true;
      return null;
    }
  }

  Future<void> _handle(
    Map<String, dynamic> message, {
    required String userId,
    required ExpenseRepository repository,
  }) async {
    final type = message['type'] as String?;
    if (type != 'addExpense') return;
    final amount = (message['amount'] as num?)?.toDouble();
    final category = message['category'] as String?;
    if (amount == null || amount <= 0 || category == null) return;
    final note = (message['note'] as String?) ?? '';
    final accountId = message['accountId'] as String?;
    final now = DateTime.now();
    await repository.addExpense(
      userId,
      Expense(
        id: '',
        amount: amount,
        category: category,
        note: note,
        date: now,
        type: EntryType.expense,
        accountId: accountId,
        createdAt: now,
        updatedAt: now,
      ),
    );
    debugPrint(
      '[WatchService] expense saved: $category \$$amount accountId=$accountId',
    );
  }
}
