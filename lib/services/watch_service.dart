import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:watch_connectivity/watch_connectivity.dart';

import '../models/expense.dart';
import '../repositories/expense_repository.dart';

/// Bridge between the Flutter app and the paired watchOS app.
///
/// Watch → phone: when the user adds an expense on the watch, the watch
///   sends a `{type: 'addExpense', amount, category, note}` message via
///   `WCSession.sendMessage`. We hand it to the active [ExpenseRepository]
///   so it lands in the same Hive (or Firestore) store the rest of the app
///   uses. Repository pattern stays intact — this service never touches
///   Hive or Firestore directly.
///
/// Phone → watch: budget + spent are already pushed to the shared App Group
///   `UserDefaults` by `WidgetSyncService`; the watch reads from there
///   directly so no extra plumbing is needed for the read path.
class WatchService {
  final WatchConnectivity _watch = WatchConnectivity();
  StreamSubscription<Map<String, dynamic>>? _sub;

  Future<void> attach({
    required String userId,
    required ExpenseRepository repository,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) return;

    final bool supported;
    try {
      supported = await _watch.isSupported;
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
    if (!supported) return;
    await _sub?.cancel();
    try {
      _sub = _watch.messageStream.listen((message) async {
        try {
          await _handle(message, userId: userId, repository: repository);
        } catch (_) {
          // Don't crash the app on a bad payload — silently drop.
        }
      }, onError: (_) {});
    } on MissingPluginException {
      return;
    } catch (_) {
      return;
    }
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
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
  }
}
