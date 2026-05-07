import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import '../models/expense.dart';
import '../repositories/expense_repository.dart';

/// Bridge between the Flutter app and the paired watchOS app.
///
/// Watch → phone: the watch sends a `{type:'addExpense', amount, category, note}`
///   payload via `transferUserInfo`.  The patched `watch_connectivity` iOS plugin
///   forwards `session(_:didReceiveUserInfo:)` to the Dart `messageStream`, so
///   messages arrive here even when the phone app was backgrounded at send time.
///
/// Phone → watch: budget + spent are pushed to the watch via
///   `WidgetSyncService.push()` which calls both the App Group UserDefaults
///   (for the widget) and `WatchConnectivity.updateApplicationContext` (for the
///   watch app's live state).
class WatchService {
  final WatchConnectivity _watch = WatchConnectivity();
  StreamSubscription<Map<String, dynamic>>? _sub;

  /// Updated by attach(); closure reads these at delivery time.
  String? _userId;
  ExpenseRepository? _repository;

  /// True once we have subscribed to the message stream.
  bool _subscribed = false;

  /// Call once the user is known.  Safe to call multiple times — only the
  /// first call creates the subscription; subsequent calls update the
  /// userId / repository so the live listener picks them up.
  Future<void> attach({
    required String userId,
    required ExpenseRepository repository,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    _userId = userId;
    _repository = repository;

    if (_subscribed) return; // already listening — just updated the references
    _subscribed = true;

    final bool supported;
    try {
      supported = await _watch.isSupported;
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
    if (!supported) return;

    try {
      _sub = _watch.messageStream.listen((message) async {
        final uid = _userId;
        final repo = _repository;
        if (uid == null || repo == null) return;
        try {
          await _handle(message, userId: uid, repository: repo);
        } catch (e, st) {
          debugPrint('[WatchService] failed to handle message: $e\n$st');
        }
      }, onError: (dynamic e) {
        debugPrint('[WatchService] messageStream error: $e');
      });
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    _subscribed = false;
  }

  Future<void> _handle(
    Map<String, dynamic> message, {
    required String userId,
    required ExpenseRepository repository,
  }) async {
    if (message['type'] != 'addExpense') return;
    final amount = (message['amount'] as num?)?.toDouble();
    final category = message['category'] as String?;
    if (amount == null || amount <= 0 || category == null) return;
    final note = (message['note'] as String?) ?? '';
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
        createdAt: now,
        updatedAt: now,
      ),
    );
    debugPrint('[WatchService] expense saved: $category $amount');
  }
}
