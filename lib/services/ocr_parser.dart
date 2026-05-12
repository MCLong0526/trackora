/// Parsed fields extracted from raw OCR text of a receipt / bank notification.
class OcrParseResult {
  final double? amount;
  final String? merchant;
  final DateTime? date;
  final String? paymentMethod;

  const OcrParseResult({
    this.amount,
    this.merchant,
    this.date,
    this.paymentMethod,
  });
}

/// Extracts structured expense fields from raw Vision OCR output.
class OcrParser {
  static OcrParseResult parse(String rawText) {
    final lines = rawText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    return OcrParseResult(
      amount: _parseAmount(rawText),
      merchant: _parseMerchant(lines),
      date: _parseDate(rawText),
      paymentMethod: _parsePaymentMethod(rawText),
    );
  }

  // ── Amount ──────────────────────────────────────────────────────────────────

  static double? _parseAmount(String text) {
    // Priority 1: explicit currency prefix (RM, MYR, $, £, €, SGD, USD)
    final currencyRe = RegExp(
      r'(?:RM|MYR|USD|SGD|\$|£|€)\s*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    // Priority 2: labelled total line
    final labelRe = RegExp(
      r'(?:total|amount|jumlah|bayaran|payment)[^\d]*([0-9]{1,3}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?)',
      caseSensitive: false,
    );
    // Priority 3: bare decimal number (xx.xx)
    final bareRe = RegExp(r'([0-9]{1,3}(?:,[0-9]{3})*\.[0-9]{2})\b');

    for (final re in [currencyRe, labelRe, bareRe]) {
      final match = re.firstMatch(text);
      if (match != null) {
        final raw = (match.groupCount >= 1 ? match.group(1) : match.group(0)) ?? '';
        final num = double.tryParse(raw.replaceAll(',', ''));
        if (num != null && num > 0) return num;
      }
    }
    return null;
  }

  // ── Merchant ─────────────────────────────────────────────────────────────────

  static final _skipLine = RegExp(
    r'^\d|receipt|invoice|total|amount|jumlah|date|time|rm\b|myr\b|thank|payment|transaction|ref|order|no\.',
    caseSensitive: false,
  );

  static String? _parseMerchant(List<String> lines) {
    for (final line in lines) {
      if (line.length >= 3 && !_skipLine.hasMatch(line)) {
        // Truncate very long lines (e.g. address blocks)
        return line.length > 50 ? line.substring(0, 50).trimRight() : line;
      }
    }
    return null;
  }

  // ── Date ─────────────────────────────────────────────────────────────────────

  static final _monthNames = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  static DateTime? _parseDate(String text) {
    // YYYY-MM-DD or YYYY/MM/DD
    final isoRe = RegExp(r'(\d{4})[-/](\d{1,2})[-/](\d{1,2})');
    // DD/MM/YYYY or DD-MM-YYYY or DD.MM.YYYY
    final dmy = RegExp(r'(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{4})');
    // DD MMM YYYY  (e.g. "15 Jan 2024")
    final written = RegExp(
      r'(\d{1,2})\s+(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\s+(\d{4})',
      caseSensitive: false,
    );

    Match? m;

    m = isoRe.firstMatch(text);
    if (m != null) {
      return _tryDate(int.parse(m.group(1)!), int.parse(m.group(2)!), int.parse(m.group(3)!));
    }

    m = written.firstMatch(text);
    if (m != null) {
      final monthIdx = _monthNames.indexOf(m.group(2)!.toLowerCase().substring(0, 3));
      if (monthIdx >= 0) {
        return _tryDate(int.parse(m.group(3)!), monthIdx + 1, int.parse(m.group(1)!));
      }
    }

    m = dmy.firstMatch(text);
    if (m != null) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final y = int.parse(m.group(3)!);
      // Heuristic: if first value > 12 it must be day; otherwise assume DD/MM
      if (d <= 31 && mo <= 12) return _tryDate(y, mo, d);
    }

    return null;
  }

  static DateTime? _tryDate(int y, int m, int d) {
    try {
      final dt = DateTime(y, m, d);
      // Sanity: not in the distant future/past
      final now = DateTime.now();
      if (dt.isAfter(now.add(const Duration(days: 1)))) return null;
      if (dt.isBefore(DateTime(2000))) return null;
      return dt;
    } catch (_) {
      return null;
    }
  }

  // ── Payment method ────────────────────────────────────────────────────────

  static const _paymentMethods = <String, String>{
    'grabpay': 'GrabPay',
    'grab pay': 'GrabPay',
    'touch \'n go': "Touch 'n Go",
    'touch n go': "Touch 'n Go",
    'tng ewallet': "Touch 'n Go",
    'tng e-wallet': "Touch 'n Go",
    'boost': 'Boost',
    'shopee pay': 'ShopeePay',
    'shopeepay': 'ShopeePay',
    'duitnow': 'DuitNow',
    'fpx': 'FPX',
    'mastercard': 'Mastercard',
    'master card': 'Mastercard',
    'visa': 'Visa',
    'amex': 'Amex',
    'american express': 'Amex',
    'maybank': 'Maybank',
    'cimb': 'CIMB',
    'hong leong': 'Hong Leong',
    'rhb': 'RHB',
    'public bank': 'Public Bank',
    'ambank': 'AmBank',
    'affin': 'Affin Bank',
    'atm': 'ATM/Cash',
    'cash': 'Cash',
  };

  static String? _parsePaymentMethod(String text) {
    final lower = text.toLowerCase();
    for (final entry in _paymentMethods.entries) {
      if (lower.contains(entry.key)) return entry.value;
    }
    // Generic card hint
    if (lower.contains('debit')) return 'Debit Card';
    if (lower.contains('credit')) return 'Credit Card';
    return null;
  }
}
