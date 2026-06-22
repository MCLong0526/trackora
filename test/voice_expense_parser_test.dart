import 'package:flutter_test/flutter_test.dart';
import 'package:trackora/services/voice_expense_parser.dart';

void main() {
  const parser = VoiceExpenseParser();

  test('parses the canonical example', () {
    final r = parser.parse('Add expense RM18 for lunch at Starbucks');
    expect(r.amount, 18.0);
    expect(r.currencyCode, 'MYR');
    expect(r.merchant, 'Starbucks');
    expect(r.category, 'Food');
    expect(r.note.toLowerCase(), contains('lunch'));
    expect(r.note.toLowerCase(), contains('starbucks'));
    expect(r.isComplete, isTrue);
  });

  test('reads RM with a space and decimals', () {
    final r = parser.parse('spent RM 25.50 on grab to office');
    expect(r.amount, 25.5);
    expect(r.currencyCode, 'MYR');
    expect(r.category, 'Transport');
  });

  test('amount-before currency word', () {
    final r = parser.parse('paid 12 ringgit for parking');
    expect(r.amount, 12.0);
    expect(r.currencyCode, 'MYR');
    expect(r.category, 'Transport'); // parking folds into Transport
  });

  test('dollar sign maps to USD', () {
    final r = parser.parse('add expense \$9.90 coffee');
    expect(r.amount, 9.9);
    expect(r.currencyCode, 'USD');
    expect(r.category, 'Food');
  });

  test('fuel maps to Transport', () {
    final r = parser.parse('RM60 petrol');
    expect(r.amount, 60.0);
    expect(r.category, 'Transport');
  });

  test('hotel folds into Others (no Hotel category)', () {
    final r = parser.parse('RM200 hotel last night');
    expect(r.amount, 200.0);
    expect(r.category, 'Others');
  });

  test('yesterday resolves to the previous day', () {
    final r = parser.parse('RM8 breakfast yesterday');
    final now = DateTime.now();
    final expected = now.subtract(const Duration(days: 1));
    expect(r.date.year, expected.year);
    expect(r.date.month, expected.month);
    expect(r.date.day, expected.day);
  });

  test('no amount → incomplete', () {
    final r = parser.parse('lunch at mamak');
    expect(r.hasAmount, isFalse);
    expect(r.isComplete, isFalse);
    expect(r.category, 'Food');
  });

  test('no currency token leaves currency null for base fallback', () {
    final r = parser.parse('add expense 15 shopping');
    expect(r.amount, 15.0);
    expect(r.currencyCode, isNull);
    expect(r.category, 'Shopping');
  });
}
