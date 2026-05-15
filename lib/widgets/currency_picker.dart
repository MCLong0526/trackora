import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../services/prefs_service.dart';
import '../theme/app_theme.dart';

/// Inline row that shows the current currency and opens a picker sheet.
class CurrencyPickerTile extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? label;

  const CurrencyPickerTile({
    super.key,
    required this.value,
    required this.onChanged,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = kSupportedCurrencies[value] ?? value;
    return InkWell(
      onTap: () => showCurrencyPickerSheet(context, current: value, onPicked: onChanged),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: brand.accentDark.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
              ),
              alignment: Alignment.center,
              child: Text(
                symbol,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: brand.accentDark,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label ?? 'Currency',
                style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 15),
              ),
            ),
            Text(
              '$symbol  $value',
              style: TextStyle(color: brand.inkSoft, fontSize: 15),
            ),
            const SizedBox(width: 4),
            Icon(CupertinoIcons.chevron_right, size: 13, color: brand.inkSoft),
          ],
        ),
      ),
    );
  }
}

/// Shows the full-screen currency picker bottom sheet.
Future<void> showCurrencyPickerSheet(
  BuildContext context, {
  required String current,
  required ValueChanged<String> onPicked,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: context.brand.background,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _CurrencyPickerSheet(
      current: current,
      onPicked: (code) {
        onPicked(code);
        Navigator.pop(ctx);
      },
    ),
  );
}

class _CurrencyPickerSheet extends StatefulWidget {
  final String current;
  final ValueChanged<String> onPicked;

  const _CurrencyPickerSheet({required this.current, required this.onPicked});

  @override
  State<_CurrencyPickerSheet> createState() => _CurrencyPickerSheetState();
}

class _CurrencyPickerSheetState extends State<_CurrencyPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final entries = kSupportedCurrencies.entries
        .where((e) =>
            _query.isEmpty ||
            e.key.toLowerCase().contains(_query.toLowerCase()) ||
            e.value.toLowerCase().contains(_query.toLowerCase()))
        .toList();

    return SafeArea(
      top: false,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.72,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.fromLTRB(0, 12, 0, 8),
                decoration: BoxDecoration(
                  color: brand.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
              child: Text(
                'Select Currency',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            // Search bar
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: Container(
                height: 40,
                decoration: BoxDecoration(
                  color: brand.surface,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  style: TextStyle(fontSize: 14, color: brand.ink),
                  decoration: InputDecoration(
                    hintText: 'Search…',
                    hintStyle: TextStyle(color: brand.inkSoft, fontSize: 14),
                    prefixIcon: Icon(CupertinoIcons.search, size: 16, color: brand.inkSoft),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: entries.length,
                separatorBuilder: (_, _) => Divider(
                  height: 1,
                  color: brand.inkSoft.withValues(alpha: 0.12),
                ),
                itemBuilder: (context, index) {
                  final e = entries[index];
                  final isSelected = e.key == widget.current;
                  return ListTile(
                    leading: SizedBox(
                      width: 36,
                      child: Text(
                        e.value,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                        ),
                      ),
                    ),
                    title: Text(
                      e.key,
                      style: TextStyle(
                        color: brand.ink,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(
                            CupertinoIcons.checkmark_alt,
                            color: brand.accentDark,
                          )
                        : null,
                    onTap: () => widget.onPicked(e.key),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
