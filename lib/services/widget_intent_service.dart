import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import '../models/expense.dart';
import '../repositories/expense_repository.dart';

/// Drains the queue of pending widget quick-add expenses written by
/// `QuickAddExpenseIntent` (iOS WidgetKit). Each entry is persisted via
/// the active [ExpenseRepository] so storage stays neutral between
/// local Hive and Firestore. The queue is cleared on success.
///
/// The queue is a JSON-encoded array of objects:
/// `{ id, amount, category, ts }` stored under the App Group
/// UserDefaults key `pending_widget_expenses_json`.
class WidgetIntentService {
  static const _key = 'pending_widget_expenses_json';
  static const _kPendingQuickAdd = 'pending_open_quickadd';
  static const _kPendingVoicePhrase = 'pending_voice_phrase';

  /// Returns the phrase captured by the "Add Expense by Voice" Siri App Intent
  /// (transcribed natively by Siri), or null. Cleared after the read so the
  /// confirmation screen only opens once per invocation. iOS-only.
  Future<String?> consumePendingVoicePhrase() async {
    try {
      final raw = await HomeWidget.getWidgetData<String>(_kPendingVoicePhrase);
      if (raw == null || raw.trim().isEmpty) return null;
      await HomeWidget.saveWidgetData<String>(_kPendingVoicePhrase, '');
      return raw.trim();
    } catch (_) {
      return null;
    }
  }

  /// Returns `true` if the iOS App Shortcut "Quick Add Expense" was
  /// invoked (e.g. from Back Tap, Siri, or the Action Button). The flag
  /// is cleared after the read so the sheet only opens once per
  /// invocation. iOS-only; on Android this just returns `false`.
  Future<bool> consumePendingQuickAdd() async {
    try {
      final raw = await HomeWidget.getWidgetData<bool>(_kPendingQuickAdd);
      if (raw != true) return false;
      await HomeWidget.saveWidgetData<bool>(_kPendingQuickAdd, false);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<int> drain(String userId, ExpenseRepository repo) async {
    final raw = await HomeWidget.getWidgetData<String>(_key);
    if (raw == null || raw.isEmpty) return 0;

    final List<dynamic> items;
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) {
        await HomeWidget.saveWidgetData<String>(_key, '');
        return 0;
      }
      items = decoded;
    } catch (_) {
      // Corrupted queue — discard so it doesn't block future writes.
      await HomeWidget.saveWidgetData<String>(_key, '');
      return 0;
    }

    int saved = 0;
    for (final dynamic e in items) {
      if (e is! Map) continue;
      final amount = (e['amount'] as num?)?.toDouble();
      if (amount == null || amount <= 0) continue;
      final category = (e['category'] as String?) ?? 'Others';
      final ts = (e['ts'] as num?)?.toInt();
      final date = ts != null
          ? DateTime.fromMillisecondsSinceEpoch(ts)
          : DateTime.now();
      try {
        final now = DateTime.now();
        await repo.addExpense(
          userId,
          Expense(
            id: '',
            amount: amount,
            category: category,
            note: 'Quick add (widget)',
            date: date,
            type: EntryType.expense,
            createdAt: now,
            updatedAt: now,
          ),
        );
        saved++;
      } catch (_) {
        // Skip failed entries; surface nothing to the user, the rest of
        // the queue should still drain.
      }
    }
    // Clear the queue regardless — entries that failed are dropped to
    // avoid an unbounded retry loop. Optimistic widget counters were
    // already bumped at quick-add time; the next push() will reconcile.
    await HomeWidget.saveWidgetData<String>(_key, '');
    return saved;
  }
}
