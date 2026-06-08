import '../models/account.dart';
import '../models/expense.dart';
import '../repositories/account_repository.dart';
import '../repositories/expense_repository.dart';

/// Accrues optional interest on interest-bearing accounts (e.g. an e-wallet
/// configured with a daily/monthly/yearly rate).
///
/// For each due period since an account's checkpoint it creates an income
/// entry equal to `balance × rate%` and advances the checkpoint, so the work
/// is idempotent across launches — running it again the same period is a no-op.
class InterestService {
  InterestService._();

  /// Safety cap on the number of catch-up periods processed per account in a
  /// single run, to avoid runaway loops for very old accounts.
  static const int _maxCatchUpPeriods = 370;

  /// Guards against concurrent runs (e.g. cold-start + resume firing together).
  static bool _running = false;

  static Future<void> accrueDue({
    required String userId,
    required AccountRepository accountRepo,
    required ExpenseRepository expenseRepo,
    required List<Account> accounts,
    required Map<String, double> balances,
    String noteLabel = 'Interest',
    double Function(double amount, String currencyCode)? toBase,
    String? baseCurrencyCode,
  }) async {
    if (_running) return;
    _running = true;
    try {
      final now = DateTime.now();
      for (final a in accounts) {
        final rate = (a.interestRatePercent ?? 0) / 100.0;
        final period = a.interestPeriod;
        if (rate <= 0 || period == null) continue;

        var checkpoint = a.lastInterestAt ?? a.createdAt;
        var balance = balances[a.id] ?? 0;
        var due = _addPeriod(checkpoint, period);
        var created = 0;
        var changed = false;

        while (!due.isAfter(now) && created < _maxCatchUpPeriods) {
          if (balance > 0) {
            final interest = balance * rate;
            if (interest > 0) {
              double? baseAmt;
              double? fx;
              if (toBase != null &&
                  baseCurrencyCode != null &&
                  a.currencyCode != null &&
                  a.currencyCode != baseCurrencyCode) {
                baseAmt = toBase(interest, a.currencyCode!);
                if (interest > 0) fx = baseAmt / interest;
              }
              await expenseRepo.addExpense(
                userId,
                Expense(
                  id: '',
                  amount: interest,
                  category: 'Others',
                  note: noteLabel,
                  date: due,
                  type: EntryType.income,
                  accountId: a.id,
                  createdAt: now,
                  updatedAt: now,
                  originalCurrency: a.currencyCode,
                  exchangeRate: fx,
                  baseCurrencyAmount: baseAmt,
                ),
              );
              // Compound so multi-period catch-up matches reality.
              balance += interest;
              created++;
            }
          }
          checkpoint = due;
          changed = true;
          due = _addPeriod(checkpoint, period);
        }

        if (changed) {
          await accountRepo.update(
            userId,
            a.copyWith(lastInterestAt: checkpoint),
          );
        }
      }
    } finally {
      _running = false;
    }
  }

  static DateTime _addPeriod(DateTime from, String period) {
    switch (period) {
      case 'yearly':
        return DateTime(
            from.year + 1, from.month, from.day, from.hour, from.minute);
      case 'monthly':
        return DateTime(
            from.year, from.month + 1, from.day, from.hour, from.minute);
      case 'daily':
      default:
        return from.add(const Duration(days: 1));
    }
  }
}
