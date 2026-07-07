import 'package:flutter/material.dart';

/// Evaluates a simple arithmetic expression containing `+ - * /` (and `×`/`÷`)
/// and returns the numeric result, or `null` if the text can't be parsed.
///
/// A plain number parses to itself, so this is a drop-in replacement for
/// `double.tryParse` on amount fields. Used so users can type `200+350` and
/// have it auto-calculate to `550`.
double? evalAmount(String input) {
  final s = input.trim().replaceAll('×', '*').replaceAll('÷', '/').replaceAll(
    ',',
    '',
  );
  if (s.isEmpty) return null;

  // Tokenize into numbers and operators.
  final tokens = <String>[];
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    if (c == ' ' || c == '\t') continue;
    if (c == '+' || c == '-' || c == '*' || c == '/') {
      // Unary +/- at the start or after another operator; leading * or / is
      // invalid.
      if (buf.isEmpty &&
          (tokens.isEmpty ||
              const ['+', '-', '*', '/'].contains(tokens.last))) {
        if (c == '*' || c == '/') return null;
        if (c == '-') buf.write('-');
        continue;
      }
      if (buf.isEmpty) return null; // operator with no preceding number
      tokens.add(buf.toString());
      buf.clear();
      tokens.add(c);
    } else if ((c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) || c == '.') {
      buf.write(c);
    } else {
      return null; // unsupported character
    }
  }
  if (buf.isNotEmpty) tokens.add(buf.toString());
  if (tokens.isEmpty || const ['+', '-', '*', '/'].contains(tokens.last)) {
    return null;
  }

  // Shunting-yard to RPN, then evaluate.
  const prec = {'+': 1, '-': 1, '*': 2, '/': 2};
  final output = <String>[];
  final ops = <String>[];
  for (final t in tokens) {
    if (prec.containsKey(t)) {
      while (ops.isNotEmpty && prec[ops.last]! >= prec[t]!) {
        output.add(ops.removeLast());
      }
      ops.add(t);
    } else {
      if (double.tryParse(t) == null) return null;
      output.add(t);
    }
  }
  while (ops.isNotEmpty) {
    output.add(ops.removeLast());
  }

  final stack = <double>[];
  for (final t in output) {
    if (prec.containsKey(t)) {
      if (stack.length < 2) return null;
      final b = stack.removeLast();
      final a = stack.removeLast();
      switch (t) {
        case '+':
          stack.add(a + b);
        case '-':
          stack.add(a - b);
        case '*':
          stack.add(a * b);
        case '/':
          if (b == 0) return null;
          stack.add(a / b);
      }
    } else {
      stack.add(double.parse(t));
    }
  }
  if (stack.length != 1) return null;
  final result = stack.single;
  if (result.isNaN || result.isInfinite) return null;
  return result;
}

/// Formats an evaluated amount back into the field: drops a trailing `.0`
/// but keeps real decimals.
String formatEvaluatedAmount(double v) => _formatEvaluated(v);

String _formatEvaluated(double v) {
  if (v == v.roundToDouble()) return v.toInt().toString();
  return v
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// Wires calculator behaviour onto an amount field: when [focus] loses focus,
/// any arithmetic expression in [controller] is replaced by its computed
/// result (e.g. `200+350` becomes `550`). Returns the listener so callers can
/// remove it on dispose if they keep the focus node alive.
VoidCallback attachAmountCalculator(
  TextEditingController controller,
  FocusNode focus,
) {
  void listener() {
    if (focus.hasFocus) return;
    final text = controller.text.trim();
    if (text.isEmpty) return;
    // Only rewrite when an operator is present, so plain numbers are untouched.
    if (!RegExp(r'[+\-*/×÷]').hasMatch(text.replaceFirst(RegExp(r'^-'), ''))) {
      return;
    }
    final v = evalAmount(text);
    if (v != null && v >= 0) controller.text = _formatEvaluated(v);
  }

  focus.addListener(listener);
  return () => focus.removeListener(listener);
}
