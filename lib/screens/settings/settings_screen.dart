import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/expense.dart';
import '../../services/export_service.dart';
import '../../services/i18n.dart';
import '../../services/money_format.dart';
import '../../services/prefs_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';

enum _CsvExportRangeMode { month, all }

class _CsvExportSelection {
  final _CsvExportRangeMode mode;
  final DateTime month;

  const _CsvExportSelection({required this.mode, required this.month});
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final user = ref.watch(authStateProvider).valueOrNull;
    final email = user?.email ?? '';
    final initial = email.isNotEmpty ? email[0].toUpperCase() : '?';
    final code = ref.watch(currencyCodeProvider).valueOrNull ?? 'USD';
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final opening = ref.watch(openingSavingsProvider).valueOrNull ?? 0.0;
    final themeMode = ref.watch(themeModeProvider);
    final appLocale = ref.watch(localeProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          // ── Hero profile card ────────────────────────────────
          _ProfileHero(initial: initial, email: email),

          const SizedBox(height: 24),

          // ── Account ─────────────────────────────────────────
          _GroupHeader(label: context.t('settings.account')),
          _GroupCard(
            children: [
              _Tile(
                icon: CupertinoIcons.money_dollar,
                iconColor: AppColors.mint,
                label: context.t('settings.currency'),
                trailing: '$symbol  $code',
                onTap: () => _pickCurrency(context, ref),
              ),
              _GroupDivider(),
              _Tile(
                icon: CupertinoIcons.creditcard,
                iconColor: AppColors.peach,
                label: context.t('settings.startingSavings'),
                trailing: formatMoney(symbol, opening),
                onTap: () => _editOpeningSavings(
                  context,
                  ref,
                  opening,
                  symbol,
                  user?.uid,
                ),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ── Display ─────────────────────────────────────────
          _GroupHeader(label: context.t('settings.display')),
          _GroupCard(
            children: [
              _Tile(
                icon: CupertinoIcons.paintbrush,
                iconColor: AppColors.lilac,
                label: context.t('settings.appearance'),
                trailing: _themeLabel(context, themeMode),
                onTap: () => _pickThemeMode(context, ref, themeMode),
              ),
              _GroupDivider(),
              _Tile(
                icon: CupertinoIcons.globe,
                iconColor: AppColors.sky,
                label: context.t('settings.language'),
                trailing: context.appLocaleLabel(appLocale),
                onTap: () => _pickLanguage(context, ref, appLocale),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ── Data ────────────────────────────────────────────
          _GroupHeader(label: context.t('settings.data')),
          _GroupCard(
            children: [
              _Tile(
                // Outward-arrow / share-style — matches "send out".
                icon: CupertinoIcons.square_arrow_up,
                iconColor: AppColors.sage,
                label: context.t('settings.exportCsv'),
                onTap: () => _exportCsv(context, ref, user?.uid),
              ),
              _GroupDivider(),
              _Tile(
                // Inward-arrow / download-style — matches "bring in".
                icon: CupertinoIcons.tray_arrow_down,
                iconColor: AppColors.butter,
                label: context.t('settings.importCsv'),
                onTap: () => _importCsv(context, ref, user?.uid),
              ),
            ],
          ),

          const SizedBox(height: 22),

          // ── About ───────────────────────────────────────────
          _GroupHeader(label: context.t('settings.about')),
          _GroupCard(
            children: [
              _Tile(
                icon: CupertinoIcons.info,
                iconColor: AppColors.sand,
                label: context.t('settings.version'),
                trailing: '1.0.0',
              ),
              if (storageMode == StorageMode.firebase) ...[
                _GroupDivider(),
                _Tile(
                  icon: CupertinoIcons.square_arrow_right,
                  iconColor: AppColors.blush,
                  label: context.t('settings.signOut'),
                  destructive: true,
                  onTap: () async {
                    await ref.read(authServiceProvider).signOut();
                  },
                ),
              ],
            ],
          ),

          const SizedBox(height: 18),
          Center(
            child: Text(
              'Trackora',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: brand.inkSoft,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _themeLabel(BuildContext context, ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return context.t('settings.themeLight');
      case ThemeMode.dark:
        return context.t('settings.themeDark');
      case ThemeMode.system:
        return context.t('settings.themeSystem');
    }
  }

  Future<void> _pickLanguage(
    BuildContext context,
    WidgetRef ref,
    AppLocale current,
  ) async {
    final brand = context.brand;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 12, 8, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: brand.divider,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.t('settings.language'),
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              for (final option in AppLocale.values)
                ListTile(
                  title: Text(context.appLocaleLabel(option)),
                  trailing: option == current
                      ? const Icon(
                          CupertinoIcons.check_mark,
                          color: AppColors.income,
                          size: 18,
                        )
                      : null,
                  onTap: () async {
                    await ref.read(localeProvider.notifier).set(option);
                    await ref
                        .read(widgetSyncServiceProvider)
                        .setLocale(option.encode());
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickThemeMode(
    BuildContext context,
    WidgetRef ref,
    ThemeMode current,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final brand = ctx.brand;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  context.t('settings.appearance'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Text(
                  context.t('settings.appearanceSubtitle'),
                  style: TextStyle(fontSize: 12, color: brand.inkSoft),
                ),
              ),
              for (final mode in ThemeMode.values)
                _themeRow(
                  context: ctx,
                  mode: mode,
                  selected: current == mode,
                  onTap: () async {
                    await ref.read(themeModeProvider.notifier).set(mode);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _themeRow({
    required BuildContext context,
    required ThemeMode mode,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final IconData icon;
    final String label;
    final String sub;
    switch (mode) {
      case ThemeMode.system:
        icon = CupertinoIcons.device_phone_portrait;
        label = context.t('settings.themeSystem');
        sub = context.t('settings.themeSystemSub');
        break;
      case ThemeMode.light:
        icon = CupertinoIcons.sun_max_fill;
        label = context.t('settings.themeLight');
        sub = context.t('settings.themeLightSub');
        break;
      case ThemeMode.dark:
        icon = CupertinoIcons.moon_fill;
        label = context.t('settings.themeDark');
        sub = context.t('settings.themeDarkSub');
        break;
    }
    final brand = context.brand;
    return ListTile(
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: AppColors.sand,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(icon, color: AppColors.ink, size: 18),
      ),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(sub, style: TextStyle(fontSize: 11, color: brand.inkSoft)),
      trailing: selected
          ? const Icon(
              CupertinoIcons.check_mark_circled_solid,
              color: AppColors.income,
            )
          : null,
      onTap: onTap,
    );
  }

  Future<void> _editOpeningSavings(
    BuildContext context,
    WidgetRef ref,
    double current,
    String symbol,
    String? userId,
  ) async {
    if (userId == null) return;
    final controller = TextEditingController(
      text: current > 0 ? current.toStringAsFixed(2) : '',
    );
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: context.brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        final brand = ctx.brand;
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.t('settings.startingSavings'),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                context.t('settings.startingSavingsSubtitle'),
                style: TextStyle(color: brand.inkSoft, fontSize: 12),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                autofocus: true,
                decoration: InputDecoration(
                  prefixText: '$symbol  ',
                  hintText: '0.00',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  final v = double.tryParse(controller.text) ?? 0;
                  Navigator.pop(ctx, v);
                },
                child: Text(context.t('common.save')),
              ),
            ],
          ),
        );
      },
    );
    if (result != null) {
      await ref
          .read(expenseRepositoryProvider)
          .setOpeningSavings(userId, result);
    }
  }

  Future<void> _exportCsv(
    BuildContext context,
    WidgetRef ref,
    String? userId,
  ) async {
    if (userId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final nothingToExport = context.t('settings.nothingToExport');
    final exportedCsv = context.t('settings.exportedCsv');
    final exportFailed = context.t('settings.exportFailed');
    // iPad / iOS popover anchor — required by share_plus on iOS.
    final box = context.findRenderObject() as RenderBox?;
    final origin = (box != null && box.hasSize)
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    try {
      final items = await ref
          .read(expenseRepositoryProvider)
          .getAllExpenses(userId)
          .first;
      if (!context.mounted) return;
      if (items.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(nothingToExport)));
        return;
      }
      final selection = await _pickCsvExportRange(context, items);
      if (selection == null) return;
      final exportItems = selection.mode == _CsvExportRangeMode.all
          ? items
          : items.where((e) => _isInSelectedMonth(e, selection.month)).toList();
      if (exportItems.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(nothingToExport)));
        return;
      }
      final result = await ExportService().exportCsv(
        exportItems,
        sharePositionOrigin: origin,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            exportedCsv.replaceFirst('{count}', '${result.rowCount}'),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$exportFailed: $e')));
    }
  }

  bool _isInSelectedMonth(Expense e, DateTime month) {
    return e.date.year == month.year && e.date.month == month.month;
  }

  Future<_CsvExportSelection?> _pickCsvExportRange(
    BuildContext context,
    List<Expense> items,
  ) async {
    final months = _exportMonths(items);
    final initialMonth = months.first;
    return showModalBottomSheet<_CsvExportSelection>(
      context: context,
      backgroundColor: context.brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        var mode = _CsvExportRangeMode.month;
        var selectedMonth = initialMonth;
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final brand = context.brand;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: brand.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      context.t('settings.exportRangeTitle'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      context.t('settings.exportRangeSubtitle'),
                      style: TextStyle(
                        fontSize: 12,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _ExportRangeOption(
                      icon: CupertinoIcons.calendar,
                      title: context.t('settings.exportSpecificMonth'),
                      subtitle: DateFormat('MMMM yyyy').format(selectedMonth),
                      selected: mode == _CsvExportRangeMode.month,
                      onTap: () =>
                          setSheetState(() => mode = _CsvExportRangeMode.month),
                    ),
                    if (mode == _CsvExportRangeMode.month) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 42,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: months.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 8),
                          itemBuilder: (context, index) {
                            final month = months[index];
                            final selected =
                                month.year == selectedMonth.year &&
                                month.month == selectedMonth.month;
                            return _ExportMonthChip(
                              label: DateFormat('MMM yyyy').format(month),
                              selected: selected,
                              onTap: () => setSheetState(() {
                                mode = _CsvExportRangeMode.month;
                                selectedMonth = month;
                              }),
                            );
                          },
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    _ExportRangeOption(
                      icon: CupertinoIcons.tray_arrow_up,
                      title: context.t('settings.exportAllRecords'),
                      subtitle: context.t('settings.exportAllRecordsSubtitle'),
                      selected: mode == _CsvExportRangeMode.all,
                      onTap: () =>
                          setSheetState(() => mode = _CsvExportRangeMode.all),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                        ctx,
                        _CsvExportSelection(mode: mode, month: selectedMonth),
                      ),
                      child: Text(context.t('settings.exportCsv')),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  List<DateTime> _exportMonths(List<Expense> items) {
    final seen = <String>{};
    final months = <DateTime>[];
    for (final e in items) {
      final month = DateTime(e.date.year, e.date.month, 1);
      final key = '${month.year}-${month.month}';
      if (seen.add(key)) months.add(month);
    }
    months.sort((a, b) => b.compareTo(a));
    return months;
  }

  Future<void> _importCsv(
    BuildContext context,
    WidgetRef ref,
    String? userId,
  ) async {
    if (userId == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final importCancelled = context.t('settings.importCancelled');
    final importedCsv = context.t('settings.importedCsv');
    final importFailed = context.t('settings.importFailed');
    try {
      final result = await ExportService().importCsv(
        userId: userId,
        repository: ref.read(expenseRepositoryProvider),
      );
      if (result.cancelled) {
        messenger.showSnackBar(SnackBar(content: Text(importCancelled)));
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            importedCsv
                .replaceFirst('{imported}', '${result.imported}')
                .replaceFirst('{skipped}', '${result.skipped}')
                .replaceFirst('{failed}', '${result.failed}'),
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$importFailed: $e')));
    }
  }

  Future<void> _pickCurrency(BuildContext context, WidgetRef ref) async {
    await showModalBottomSheet(
      context: context,
      backgroundColor: context.brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
                child: Text(
                  context.t('settings.currency'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              ...kSupportedCurrencies.entries.map(
                (e) => ListTile(
                  leading: SizedBox(
                    width: 32,
                    child: Text(
                      e.value,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  title: Text(e.key),
                  onTap: () async {
                    await ref
                        .read(prefsServiceProvider)
                        .setCurrency(e.key, e.value);
                    ref.invalidate(currencySymbolProvider);
                    ref.invalidate(currencyCodeProvider);
                    if (ctx.mounted) Navigator.pop(ctx);
                  },
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }
}

class _ExportRangeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ExportRangeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: brand.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? brand.accentDark : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: selected ? AppColors.mint : brand.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 17, color: brand.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: brand.ink,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: brand.inkSoft,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              selected
                  ? CupertinoIcons.check_mark_circled_solid
                  : CupertinoIcons.circle,
              size: 20,
              color: selected ? AppColors.income : brand.inkSoft,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportMonthChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ExportMonthChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final selectedBg = brand.accentDark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: selected ? selectedBg : brand.surface,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? foregroundOn(selectedBg) : brand.ink,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

// ── Profile hero + grouped tiles ────────────────────────────
//
// Beautified Profile UI. iOS-style grouped lists with subtle dividers,
// a soft gradient hero card, larger avatar, and breathing-room
// spacing. All existing actions are preserved — these widgets just
// host them.

class _ProfileHero extends StatelessWidget {
  final String initial;
  final String email;
  const _ProfileHero({required this.initial, required this.email});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.card),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.lilac, AppColors.sky],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: AppColors.ink,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  storageMode == StorageMode.local
                      ? context.t('settings.offlineProfile')
                      : context.t('settings.signedIn'),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  email.isEmpty ? 'Trackora' : email,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String label;
  const _GroupHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.only(left: 14, bottom: 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: brand.inkSoft,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  final List<Widget> children;
  const _GroupCard({required this.children});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Column(children: children),
      ),
    );
  }
}

class _GroupDivider extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    // Indent matches icon column width so the divider sits under the
    // label rather than running edge-to-edge — classic iOS look.
    return Padding(
      padding: const EdgeInsets.only(left: 60),
      child: Container(height: 0.5, color: brand.divider),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String? trailing;
  final VoidCallback? onTap;
  final bool destructive;

  const _Tile({
    required this.icon,
    required this.iconColor,
    required this.label,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap == null
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap!();
              },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: iconColor,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  icon,
                  size: 17,
                  color: destructive ? AppColors.expense : AppColors.ink,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: destructive ? AppColors.expense : brand.ink,
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.36,
                  ),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      trailing!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontSize: 14,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
              // Fixed-width chevron slot at the right edge so chevrons
              // line up across **every** row, regardless of whether the
              // row has a trailing value or whether it's tappable.
              // Non-tappable rows (Version) and destructive rows
              // (Sign out) still occupy this slot — empty — so trailing
              // text columns stay aligned.
              SizedBox(
                width: 22,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: (onTap != null && !destructive)
                      ? Icon(
                          CupertinoIcons.chevron_right,
                          size: 14,
                          color: brand.inkSoft,
                        )
                      : const SizedBox(width: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
