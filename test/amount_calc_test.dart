import 'package:flutter_test/flutter_test.dart';
import 'package:trackora/services/amount_calc.dart';

void main() {
  test('plain numbers parse like double.tryParse', () {
    expect(evalAmount('200'), 200);
    expect(evalAmount('12.50'), 12.5);
    expect(evalAmount(''), isNull);
    expect(evalAmount('abc'), isNull);
  });

  test('basic operators', () {
    expect(evalAmount('200+350'), 550);
    expect(evalAmount('500-150'), 350);
    expect(evalAmount('3*4'), 12);
    expect(evalAmount('10/4'), 2.5);
  });

  test('precedence and chaining', () {
    expect(evalAmount('2+3*4'), 14);
    expect(evalAmount('100+50-25'), 125);
    expect(evalAmount('1.5*2+1'), 4);
  });

  test('whitespace, commas and unicode operators', () {
    expect(evalAmount('200 + 350'), 550);
    expect(evalAmount('1,200+300'), 1500);
    expect(evalAmount('6×7'), 42);
    expect(evalAmount('84÷2'), 42);
  });

  test('unary minus and divide-by-zero', () {
    expect(evalAmount('-5+10'), 5);
    expect(evalAmount('10/0'), isNull);
    expect(evalAmount('200+'), isNull);
    expect(evalAmount('*5'), isNull);
  });
}
