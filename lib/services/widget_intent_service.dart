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
