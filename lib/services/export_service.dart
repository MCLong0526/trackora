import 'dart:io';
import 'dart:ui';

import 'package:csv/csv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/expense.dart';
import '../repositories/expense_repository.dart';

class CsvImportResult {
  final int imported;
  final int skipped;
  final int failed;

  const CsvImportResult({
    required this.imported,
    required this.skipped,
    required this.failed,
  });

  /// True when the user cancelled the file picker (no work attempted).
  bool get cancelled => imported == 0 && skipped == 0 && failed == 0;
}

class CsvExportResult {
  final String filePath;
  final int rowCount;
  final ShareResultStatus shareStatus;

  const CsvExportResult({
    required this.filePath,
    required this.rowCount,
    required this.shareStatus,
  });
}

/// CSV export / import for [Expense] entries.
///
/// **Header schema** — exported with display-friendly Title Case names:
/// ```
/// ID, Date, Type, Category, Amount, Note, Receipt URL, Created At, Updated At
/// ```
/// **Date format** — ISO-8601 (`2026-05-01T19:30:00.000`). Round-trips
/// cleanly through `DateTime.parse`.
///
/// **Encoding** — UTF-8 with BOM (`﻿`) so Excel auto-detects the
/// encoding and renders accented characters correctly.
///
/// **Sort order** — newest entries first. Stable for deduping.
///
/// **Import is forgiving** — header names are normalised (lowercase,
/// strip spaces / punctuation) so files written by older versions of
/// Trackora (lowercase headers like `createdAt`) still import. Missing
/// optional columns fall back to sensible defaults.
class ExportService {
  /// Display-friendly headers used when writing CSVs. Order is fixed.
  static const _exportHeaders = <String>[
    'ID',
    'Date',
    'Type',
    'Category',
    'Amount',
    'Note',
    'Receipt URL',
    'Created At',
    'Updated At',
  ];

  static String _normalize(String s) =>
      s.trim().toLowerCase().replaceAll(RegExp(r'[\s_\-]+'), '');

  /// Exports [items] as CSV, writes the file to the temp directory, then
  /// presents the iOS / Android share sheet. Throws on any failure so the
  /// caller can surface a SnackBar.
  ///
  /// On iPad (and some iPhone configurations) the share sheet is presented
  /// as a popover that needs an anchor rect. Pass [sharePositionOrigin] from
  /// the source widget so iOS knows where to point the popover.
  Future<CsvExportResult> exportCsv(
    List<Expense> items, {
    Rect? sharePositionOrigin,
  }) async {
    if (items.isEmpty) {
      throw StateError('No expenses to export.');
    }

    // Newest first — easier to skim in Excel/Numbers.
    final sorted = [...items]..sort((a, b) => b.date.compareTo(a.date));

    final rows = <List<dynamic>>[
      _exportHeaders,
      for (final e in sorted)
        [
          e.id,
          e.date.toIso8601String(),
          e.type == EntryType.income ? 'income' : 'expense',
          e.category,
          e.amount.toStringAsFixed(2),
          e.note,
          e.receiptUrl ?? '',
          e.createdAt.toIso8601String(),
          e.updatedAt.toIso8601String(),
        ],
    ];

    // ListToCsvConverter quotes fields with commas / newlines / quotes
    // automatically. Force \r\n line endings (Excel-friendly).
    final csv = const ListToCsvConverter(eol: '\r\n').convert(rows);
    // UTF-8 BOM so Excel opens the file with the right encoding.
    const bom = '﻿';

    final dir = await getTemporaryDirectory();
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    final file = File('${dir.path}/trackora_expenses_$ts.csv');
    await file.writeAsString(bom + csv, flush: true);

    if (!await file.exists()) {
      throw FileSystemException('CSV file failed to write', file.path);
    }

    final share = await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv', name: 'trackora_expenses.csv')],
      subject: 'Trackora CSV export',
      text: 'Trackora CSV export — ${items.length} entries',
      sharePositionOrigin: sharePositionOrigin,
    );

    return CsvExportResult(
      filePath: file.path,
      rowCount: items.length,
      shareStatus: share.status,
    );
  }

  /// Imports a CSV that the user picks via the system file picker.
  /// Dedupes by `id` against the existing repository contents so importing
  /// the same file twice is safe.
  Future<CsvImportResult> importCsv({
    required String userId,
    required ExpenseRepository repository,
  }) async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['csv'],
      withData: false,
    );
    final path = picked?.files.single.path;
    if (path == null) {
      return const CsvImportResult(imported: 0, skipped: 0, failed: 0);
    }

    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('CSV file not readable', path);
    }
    var content = await file.readAsString();
    // Strip a leading UTF-8 BOM if Excel / our exporter wrote one.
    if (content.startsWith('﻿')) {
      content = content.substring(1);
    }
    final rows = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(content);
    if (rows.isEmpty) {
      return const CsvImportResult(imported: 0, skipped: 0, failed: 0);
    }

    final header = rows.first.map((v) => v.toString()).toList();
    // Normalise header names so we can match both display-style headers
    // ("Created At") and legacy lowercase headers ("createdAt"). Maps the
    // canonical normalised key (e.g. "createdat") to its column index.
    final indexes = <String, int>{};
    for (var i = 0; i < header.length; i++) {
      indexes[_normalize(header[i])] = i;
    }

    final existing = await repository.getAllExpenses(userId).first;
    final existingIds = existing.map((e) => e.id).toSet();
    var imported = 0;
    var skipped = 0;
    var failed = 0;

    for (final row in rows.skip(1)) {
      try {
        // Skip blank lines (Excel sometimes appends one).
        if (row.every((v) => v.toString().trim().isEmpty)) continue;

        final id = _value(row, indexes, 'id');
        if (id.isNotEmpty && existingIds.contains(id)) {
          skipped++;
          continue;
        }

        final date = _date(row, indexes, 'date') ?? DateTime.now();
        final createdAt = _date(row, indexes, 'createdat') ?? date;
        final updatedAt = _date(row, indexes, 'updatedat') ?? createdAt;

        final expense = Expense(
          id: id,
          amount: double.parse(_value(row, indexes, 'amount')),
          category: _value(row, indexes, 'category', fallback: 'Others'),
          note: _value(row, indexes, 'note'),
          date: date,
          type: _entryType(_value(row, indexes, 'type')),
          receiptUrl: _nullable(_value(row, indexes, 'receipturl')),
          createdAt: createdAt,
          updatedAt: updatedAt,
        );
        await repository.upsertExpense(userId, expense);
        if (expense.id.isNotEmpty) existingIds.add(expense.id);
        imported++;
      } catch (_) {
        failed++;
      }
    }

    return CsvImportResult(
      imported: imported,
      skipped: skipped,
      failed: failed,
    );
  }

  /// Reads [key] (already normalised — lowercase, no spaces) from [row].
  String _value(
    List<dynamic> row,
    Map<String, int> indexes,
    String key, {
    String fallback = '',
  }) {
    final index = indexes[key];
    if (index == null || index >= row.length) return fallback;
    final value = row[index].toString().trim();
    return value.isEmpty ? fallback : value;
  }

  DateTime? _date(List<dynamic> row, Map<String, int> indexes, String key) {
    final value = _value(row, indexes, key);
    if (value.isEmpty) return null;
    try {
      return DateTime.parse(value);
    } catch (_) {
      // Tolerate a few common alternatives that Excel might emit.
      // e.g. "2026-05-01 19:30:00" (space instead of T).
      final tryReplace = DateTime.tryParse(value.replaceFirst(' ', 'T'));
      if (tryReplace != null) return tryReplace;
      rethrow;
    }
  }

  EntryType _entryType(String value) {
    return value.toLowerCase() == 'income'
        ? EntryType.income
        : EntryType.expense;
  }

  String? _nullable(String value) => value.trim().isEmpty ? null : value;
}
