/// Parses a free-form spoken/typed phrase (from in-app speech recognition or a
/// Siri App Intent) into the fields of an expense entry.
///
/// Example: "Add expense RM18 for lunch at Starbucks" →
///   amount 18.0, currency MYR, merchant "Starbucks", category "Food",
///   note "Lunch at Starbucks", date today.
///
/// Pure Dart, no I/O — deterministic and unit-testable. The result is only ever
/// used to pre-fill the manual entry form; nothing is saved without the user
/// confirming.
library;

class ParsedExpense {
  /// Detected amount, or null when none could be read.
  final double? amount;

  /// ISO currency code when a currency token was present (e.g. "RM" → MYR),
  /// otherwise null so the caller can fall back to the user's base currency.
  final String? currencyCode;

  /// Captured merchant / place ("Starbucks"), or null.
  final String? merchant;

  /// A built-in category key (Food, Transport, Shopping, …). Always set;
  /// defaults to "Others".
  final String category;

  /// Human-readable note for the entry (may include the merchant).
  final String note;

  /// Resolved date — defaults to "now" when no date word was spoken.
  final DateTime date;

  /// The original transcript, kept for the manual-edit fallback / debugging.
  final String rawText;

  const ParsedExpense({
    required this.amount,
    required this.currencyCode,
    required this.merchant,
    required this.category,
    required this.note,
    required this.date,
    required this.rawText,
  });

  bool get hasAmount => amount != null && amount! > 0;

  /// True when the parse is confident enough to skip straight to confirmation
  /// without highlighting missing fields. The amount is the only hard
  /// requirement; everything else has a sensible default.
  bool get isComplete => hasAmount;
}

class VoiceExpenseParser {
  const VoiceExpenseParser();

  /// Maps a spoken currency symbol or word to its ISO code.
  static const Map<String, String> _currencyTokens = {
    'rm': 'MYR',
    'myr': 'MYR',
    'ringgit': 'MYR',
    r'$': 'USD',
    'usd': 'USD',
    'dollar': 'USD',
    'dollars': 'USD',
    'buck': 'USD',
    'bucks': 'USD',
    r's$': 'SGD',
    'sgd': 'SGD',
    '€': 'EUR',
    'eur': 'EUR',
    'euro': 'EUR',
    'euros': 'EUR',
    '£': 'GBP',
    'gbp': 'GBP',
    'pound': 'GBP',
    'pounds': 'GBP',
    '¥': 'JPY',
    'jpy': 'JPY',
    'yen': 'JPY',
    'baht': 'THB',
    'thb': 'THB',
    'idr': 'IDR',
    'rupiah': 'IDR',
  };

  /// Keyword → built-in category key. Order doesn't matter; the first keyword
  /// found in the text wins (longer/more-specific keywords are checked first).
  /// Note: the app has no dedicated Parking / Hotel / Fuel categories, so those
  /// fold into the closest built-in (Transport / Others).
  static const Map<String, List<String>> _categoryKeywords = {
    'Food': [
      'breakfast', 'brunch', 'lunch', 'dinner', 'supper', 'coffee', 'cafe',
      'tea', 'drinks', 'drink', 'meal', 'restaurant', 'mcdonald', 'mcdonalds',
      'kfc', 'starbucks', 'mamak', 'makan', 'nasi', 'burger', 'pizza', 'snack',
      'food',
    ],
    'Groceries': [
      'groceries', 'grocery', 'supermarket', 'market', 'mart', 'tesco',
      'giant', 'lotus', 'grocer',
    ],
    'Transport': [
      'transport', 'grab', 'taxi', 'uber', 'bus', 'train', 'mrt', 'lrt',
      'ktm', 'parking', 'toll', 'fuel', 'petrol', 'diesel', 'gas', 'fare',
      'ride', 'flight', 'car park', 'carpark',
    ],
    'Shopping': [
      'shopping', 'clothes', 'clothing', 'shoes', 'lazada', 'shopee', 'mall',
      'uniqlo', 'zara', 'shop',
    ],
    'Entertainment': [
      'entertainment', 'movie', 'cinema', 'gym', 'games', 'game', 'netflix',
      'spotify', 'concert', 'ticket', 'karaoke',
    ],
    'Health': [
      'clinic', 'hospital', 'pharmacy', 'medicine', 'doctor', 'dental',
      'dentist', 'health', 'drug',
    ],
    'Bills': [
      'electricity', 'electric', 'water bill', 'internet', 'wifi', 'utility',
      'rent', 'subscription', 'bill', 'bills',
    ],
  };

  /// Command / filler words stripped from the start of the note.
  static const List<String> _leadingFiller = [
    'add an expense', 'add expense', 'new expense', 'record expense',
    'log expense', 'i spent', 'i paid', 'spent', 'paid', 'expense', 'add',
    'log', 'record', 'for',
  ];

  ParsedExpense parse(String input, {String? defaultCurrency}) {
    final raw = input.trim();
    final lower = raw.toLowerCase();

    final amountMatch = _extractAmount(lower);
    final amount = amountMatch?.amount;
    final currency = amountMatch?.currency ?? _detectCurrency(lower);

    final merchant = _extractMerchant(raw);
    final category = _detectCategory(lower);
    final date = _extractDate(lower);
    final note = _buildNote(
      raw: raw,
      amountText: amountMatch?.matchedText,
      merchant: merchant,
      category: category,
    );

    return ParsedExpense(
      amount: amount,
      currencyCode: currency,
      merchant: merchant,
      category: category,
      note: note,
      date: date,
      rawText: raw,
    );
  }

  // ── Amount ──────────────────────────────────────────────────────────────
  _AmountMatch? _extractAmount(String lower) {
    // 1) Symbol/word currency directly attached: "rm18", "rm 18.50", "$18",
    //    "18 ringgit", "18.50 dollars".
    final patterns = <RegExp>[
      // currency-before: rm 18.50 / $18 / s$ 9 / € 5
      RegExp(r'(rm|s\$|\$|myr|usd|sgd|eur|€|£|gbp|¥|jpy)\s*([0-9]+(?:[.,][0-9]{1,2})?)'),
      // amount-before-word: 18 ringgit / 18.50 dollars / 9 bucks
      RegExp(r'([0-9]+(?:[.,][0-9]{1,2})?)\s*(ringgit|myr|dollars?|usd|sgd|euros?|eur|pounds?|gbp|yen|jpy|baht|bucks?|rupiah)'),
    ];
    for (final re in patterns) {
      final m = re.firstMatch(lower);
      if (m == null) continue;
      final isCurrencyFirst = re == patterns.first;
      final amtStr = (isCurrencyFirst ? m.group(2) : m.group(1))!;
      final curTok = (isCurrencyFirst ? m.group(1) : m.group(2))!;
      final amount = _toDouble(amtStr);
      if (amount == null) continue;
      return _AmountMatch(
        amount: amount,
        currency: _currencyTokens[curTok],
        matchedText: m.group(0)!,
      );
    }
    // 2) Bare number fallback ("eighteen" not handled — speech returns digits).
    final bare = RegExp(r'(?<![0-9.])([0-9]+(?:\.[0-9]{1,2})?)(?![0-9])')
        .firstMatch(lower);
    if (bare != null) {
      final amount = _toDouble(bare.group(1)!);
      if (amount != null) {
        return _AmountMatch(
          amount: amount,
          currency: null,
          matchedText: bare.group(0)!,
        );
      }
    }
    return null;
  }

  double? _toDouble(String s) => double.tryParse(s.replaceAll(',', '.'));

  String? _detectCurrency(String lower) {
    for (final entry in _currencyTokens.entries) {
      final token = entry.key;
      // Word-boundary match for alphabetic tokens; plain contains for symbols.
      final isWord = RegExp(r'^[a-z]+$').hasMatch(token);
      final found = isWord
          ? RegExp('\\b${RegExp.escape(token)}\\b').hasMatch(lower)
          : lower.contains(token);
      if (found) return entry.value;
    }
    return null;
  }

  // ── Category ────────────────────────────────────────────────────────────
  String _detectCategory(String lower) {
    for (final entry in _categoryKeywords.entries) {
      for (final kw in entry.value) {
        if (lower.contains(kw)) return entry.key;
      }
    }
    return 'Others';
  }

  // ── Merchant ────────────────────────────────────────────────────────────
  String? _extractMerchant(String raw) {
    // Capture 1–3 capitalised-ish words after "at" / "from".
    final m = RegExp(
      r"\b(?:at|from)\s+([A-Za-z][\w&.-]*(?:\s+[A-Za-z][\w&.-]*){0,2})",
    ).firstMatch(raw);
    if (m == null) return null;
    var name = m.group(1)!.trim();
    // Trim trailing date/filler words that may have been captured.
    name = name.replaceAll(
      RegExp(r'\s+(today|yesterday|tomorrow|just now|now)$',
          caseSensitive: false),
      '',
    );
    if (name.isEmpty) return null;
    return _titleCase(name);
  }

  // ── Date ────────────────────────────────────────────────────────────────
  DateTime _extractDate(String lower) {
    final now = DateTime.now();
    DateTime atMidday(DateTime d) => DateTime(d.year, d.month, d.day, 12);
    if (RegExp(r'\byesterday\b').hasMatch(lower)) {
      return atMidday(now.subtract(const Duration(days: 1)));
    }
    if (RegExp(r'\b(day before yesterday)\b').hasMatch(lower)) {
      return atMidday(now.subtract(const Duration(days: 2)));
    }
    if (RegExp(r'\btomorrow\b').hasMatch(lower)) {
      return atMidday(now.add(const Duration(days: 1)));
    }
    // Most recent past occurrence of a named weekday ("on monday", "last fri").
    const weekdays = {
      'monday': 1, 'tuesday': 2, 'wednesday': 3, 'thursday': 4,
      'friday': 5, 'saturday': 6, 'sunday': 7,
    };
    for (final entry in weekdays.entries) {
      if (RegExp('\\b${entry.key.substring(0, 3)}').hasMatch(lower)) {
        var diff = now.weekday - entry.value;
        if (diff <= 0) diff += 7; // always look back
        return atMidday(now.subtract(Duration(days: diff)));
      }
    }
    return now;
  }

  // ── Note ────────────────────────────────────────────────────────────────
  String _buildNote({
    required String raw,
    required String? amountText,
    required String? merchant,
    required String category,
  }) {
    var text = raw;
    // Strip the matched amount/currency span.
    if (amountText != null && amountText.isNotEmpty) {
      text = text.replaceAll(
        RegExp(RegExp.escape(amountText), caseSensitive: false),
        ' ',
      );
    }
    // Strip standalone currency words left behind.
    text = text.replaceAll(
      RegExp(
        r'\b(rm|myr|ringgit|usd|dollars?|sgd|eur|euros?|gbp|pounds?|jpy|yen|baht|bucks?|rupiah)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    // Strip date words.
    text = text.replaceAll(
      RegExp(
        r'\b(today|yesterday|tomorrow|day before yesterday|just now|now|on\s+\w+day|last\s+\w+day|mon|tue|wed|thu|fri|sat|sun)\b',
        caseSensitive: false,
      ),
      ' ',
    );
    // Strip leading command/filler words, repeatedly.
    var changed = true;
    while (changed) {
      changed = false;
      final trimmed = text.trimLeft();
      for (final f in _leadingFiller) {
        final re = RegExp('^${RegExp.escape(f)}\\b', caseSensitive: false);
        if (re.hasMatch(trimmed)) {
          text = trimmed.replaceFirst(re, '');
          changed = true;
          break;
        }
      }
    }
    // Collapse whitespace and tidy.
    var note = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    // Drop a dangling leading "for"/"on"/"at" that lost its object.
    note = note.replaceFirst(RegExp(r'^(for|on|at)\s+', caseSensitive: false), '');
    if (note.isEmpty) {
      note = merchant ?? '';
    }
    return _sentenceCase(note);
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _titleCase(String s) => s
      .split(RegExp(r'\s+'))
      .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');

  String _sentenceCase(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _AmountMatch {
  final double amount;
  final String? currency;
  final String matchedText;
  const _AmountMatch({
    required this.amount,
    required this.currency,
    required this.matchedText,
  });
}
