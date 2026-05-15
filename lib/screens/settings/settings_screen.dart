import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../app_config.dart';
import '../../models/account.dart';
import '../../models/expense.dart';
import '../../services/auth_service.dart';
import '../../services/export_service.dart';
import '../../services/i18n.dart';
import '../../services/live_activity_service.dart';
import '../../services/money_format.dart';
import '../../services/prefs_service.dart';
import '../../services/sync_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/animated_donut_chart.dart';
import '../../widgets/app_toast.dart';
import '../../widgets/masked_amount.dart';
import '../../widgets/section_card.dart';
import '../accounts/accounts_screen.dart';
import '../../widgets/account_carousel_section.dart' show showAddAccountSheet;
import '../auth/welcome_screen.dart';
import '../../main.dart' show rootNavKey;

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
    final code = ref.watch(currencyCodeProvider).valueOrNull ?? 'USD';
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? '\$';
    final themeMode = ref.watch(themeModeProvider);
    final appLocale = ref.watch(localeProvider);
    final accounts = ref.watch(accountsProvider).valueOrNull ?? const [];
    final allExpenses =
        ref.watch(allExpensesProvider).valueOrNull ?? const <Expense>[];
    final totalBalance = ref.watch(totalAccountBalanceProvider);
    final visible = ref.watch(balanceVisibleProvider);
    final canPop = Navigator.canPop(context);

    return Scaffold(
      backgroundColor: brand.background,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            // ── Page title ───────────────────────────────────────
            Row(
              children: [
                if (canPop) ...[
                  CircleIconButton(
                    icon: CupertinoIcons.chevron_left,
                    size: 40,
                    onTap: () => Navigator.maybePop(context),
                  ),
                  const SizedBox(width: 12),
                ],
                const Expanded(
                  child: Text(
                    'Profile',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Cloud Sync ───────────────────────────────────────
            const _CloudSyncSection(),

            const SizedBox(height: 22),

            // ── My Accounts ─────────────────────────────────────
            _AccountsSection(
              accounts: accounts,
              allExpenses: allExpenses,
              symbol: symbol,
              totalBalance: totalBalance,
              visible: visible,
            ),

            const SizedBox(height: 22),

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
                  icon: CupertinoIcons.bell,
                  iconColor: AppColors.sky,
                  label: 'Reminders',
                  trailing: 'Daily at 8 PM',
                  onTap: () {},
                ),
                if (defaultTargetPlatform == TargetPlatform.iOS) ...[
                  _GroupDivider(),
                  _LiveActivityToggleTile(currency: symbol),
                ],
                if (email.isNotEmpty && email != localUserEmail) ...[
                  _GroupDivider(),
                  _Tile(
                    icon: CupertinoIcons.envelope,
                    iconColor: AppColors.sky,
                    label: 'Change Email',
                    trailing: email,
                    onTap: () => _showChangeEmail(context, ref, email),
                  ),
                ],
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
                      if (context.mounted) {
                        AppToast.show(
                          context,
                          'Signed out',
                          type: AppToastType.info,
                          icon: CupertinoIcons.square_arrow_right,
                        );
                      }
                      rootNavKey.currentState?.pushAndRemoveUntil(
                        CupertinoPageRoute(
                          builder: (_) => const WelcomeScreen(),
                        ),
                        (route) => false,
                      );
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
                  fontWeight: FontWeight.w600,
                  color: brand.inkSoft,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
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
                      fontWeight: FontWeight.w600,
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

  void _showChangeEmail(
    BuildContext context,
    WidgetRef ref,
    String currentEmail,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ChangeEmailSheet(
        currentEmail: currentEmail,
        authService: ref.read(authServiceProvider),
      ),
    );
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
                        fontWeight: FontWeight.w600,
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
                      fontWeight: FontWeight.w600,
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
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

// ── My Accounts section — donut chart card ───────────────────────────────────

const _kAccountChartColors = [
  AppActionBlue.color,
  Color(0xFF34D399),
  Color(0xFFFBBF24),
  Color(0xFF60A5FA),
  Color(0xFFF472B6),
  Color(0xFFA78BFA),
  Color(0xFF2DD4BF),
  Color(0xFFFB923C),
];

class _AccountsSection extends StatefulWidget {
  final List<Account> accounts;
  final List<Expense> allExpenses;
  final String symbol;
  final double totalBalance;
  final bool visible;

  const _AccountsSection({
    required this.accounts,
    required this.allExpenses,
    required this.symbol,
    required this.totalBalance,
    required this.visible,
  });

  @override
  State<_AccountsSection> createState() => _AccountsSectionState();
}

class _AccountsSectionState extends State<_AccountsSection> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;

    final balanceMap = <String, double>{
      for (final a in widget.accounts)
        a.id: computeAccountBalance(a, widget.allExpenses),
    };
    final positiveAccounts = widget.accounts
        .where((a) => (balanceMap[a.id] ?? 0) > 0)
        .toList();
    final positiveTotal = positiveAccounts.fold<double>(
      0,
      (s, a) => s + balanceMap[a.id]!,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'MY ACCOUNTS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: brand.inkSoft,
                letterSpacing: 0.5,
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                CupertinoPageRoute(builder: (_) => const AccountsScreen()),
              ),
              child: Text(
                'Manage',
                style: TextStyle(
                  fontSize: 13,
                  color: brand.accentDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: brand.surface,
            borderRadius: BorderRadius.circular(18),
            ),
          child: widget.accounts.isEmpty
              ? _buildEmpty(context, brand)
              : _buildChart(
                  context,
                  brand,
                  positiveAccounts,
                  positiveTotal,
                  balanceMap,
                ),
        ),
      ],
    );
  }

  Widget _buildEmpty(BuildContext context, BrandColors brand) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: GestureDetector(
        onTap: () => showAddAccountSheet(context),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: brand.accentDark.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                CupertinoIcons.add_circled,
                size: 18,
                color: brand.accentDark,
              ),
              const SizedBox(width: 8),
              Text(
                'Add Your First Account',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: brand.accentDark,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChart(
    BuildContext context,
    BrandColors brand,
    List<Account> positiveAccounts,
    double positiveTotal,
    Map<String, double> balanceMap,
  ) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: positiveAccounts.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No positive balance to display',
                    style: TextStyle(fontSize: 13, color: brand.inkSoft),
                  ),
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Donut chart — animated sweep reveal
                    SizedBox(
                      width: 108,
                      height: 108,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          AnimatedDonutChart(
                            key: ValueKey(positiveAccounts.length),
                            size: 108,
                            strokeWidth: 16,
                            segments: List.generate(positiveAccounts.length, (
                              i,
                            ) {
                              final a = positiveAccounts[i];
                              final bal = balanceMap[a.id]!;
                              final color =
                                  _kAccountChartColors[i %
                                      _kAccountChartColors.length];
                              return DonutSegment(
                                value: bal,
                                color: color.withValues(alpha: 0.88),
                              );
                            }),
                            onSegmentTap: (idx) => setState(() {
                              _touched = _touched == idx ? null : idx;
                            }),
                          ),
                          // Center label
                          _touched != null &&
                                  _touched! < positiveAccounts.length
                              ? Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${((balanceMap[positiveAccounts[_touched!].id]! / positiveTotal) * 100).toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: brand.ink,
                                      ),
                                    ),
                                    Text(
                                      positiveAccounts[_touched!].name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: brand.inkSoft,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                )
                              : Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Total',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: brand.inkSoft,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    MaskedAmount(
                                      visibleText: formatMoney(
                                        widget.symbol,
                                        widget.totalBalance,
                                      ),
                                      visible: widget.visible,
                                      currencyPrefix: widget.symbol,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: brand.ink,
                                      ),
                                    ),
                                  ],
                                ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Legend
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(positiveAccounts.length, (i) {
                          final a = positiveAccounts[i];
                          final bal = balanceMap[a.id]!;
                          final pct = bal / positiveTotal * 100;
                          final color =
                              _kAccountChartColors[i %
                                  _kAccountChartColors.length];
                          final isActive = _touched == i;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 9),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 3,
                                  height: 30,
                                  decoration: BoxDecoration(
                                    color: color.withValues(
                                      alpha: isActive ? 1.0 : 0.7,
                                    ),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        a.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: isActive
                                              ? FontWeight.w700
                                              : FontWeight.w600,
                                          color: brand.ink,
                                        ),
                                      ),
                                      Text(
                                        '${pct.toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: color,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                MaskedAmount(
                                  visibleText: formatMoney(widget.symbol, bal),
                                  visible: widget.visible,
                                  currencyPrefix: widget.symbol,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: isActive ? brand.ink : brand.inkSoft,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
        ),
        Divider(
          height: 0.5,
          thickness: 0.5,
          indent: 16,
          endIndent: 16,
          color: brand.divider,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: GestureDetector(
            onTap: () => showAddAccountSheet(context),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  CupertinoIcons.add_circled,
                  size: 16,
                  color: brand.accentDark,
                ),
                const SizedBox(width: 6),
                Text(
                  'Add Account',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: brand.accentDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
          fontWeight: FontWeight.w600,
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

// ── Live Activity Toggle ──────────────────────────────────────────────────────

class _LiveActivityToggleTile extends StatefulWidget {
  final String currency;
  const _LiveActivityToggleTile({required this.currency});

  @override
  State<_LiveActivityToggleTile> createState() =>
      _LiveActivityToggleTileState();
}

class _LiveActivityToggleTileState extends State<_LiveActivityToggleTile> {
  bool _enabled = false;
  final _prefs = PrefsService();

  @override
  void initState() {
    super.initState();
    _prefs.liveActivityEnabled().then((v) {
      if (mounted) setState(() => _enabled = v);
    });
  }

  Future<void> _toggle(bool value) async {
    HapticFeedback.selectionClick();
    setState(() => _enabled = value);
    await _prefs.setLiveActivityEnabled(value);
    if (value) {
      final error = await LiveActivityService.start(
        currency: widget.currency,
        todaySpent: 0,
      );
      if (error != null) {
        if (!mounted) return;
        // Revert toggle and show the native error so the user knows what happened.
        setState(() => _enabled = false);
        await _prefs.setLiveActivityEnabled(false);
        if (!mounted) return;
        AppToast.show(
          context,
          'Could not start Live Activity: $error',
          type: AppToastType.error,
          icon: CupertinoIcons.exclamationmark_circle,
        );
      }
    } else {
      await LiveActivityService.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: AppColors.peach,
              borderRadius: BorderRadius.circular(9),
            ),
            child: const Icon(
              CupertinoIcons.bolt_horizontal_fill,
              size: 16,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Quick Add Live Activity',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: brand.ink,
                  ),
                ),
                Text(
                  'Dynamic Island & Lock Screen shortcut',
                  style: TextStyle(
                    fontSize: 12,
                    color: brand.inkSoft,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          CupertinoSwitch(
            value: _enabled,
            activeTrackColor: AppColors.income,
            onChanged: _toggle,
          ),
        ],
      ),
    );
  }
}

// ── Cloud Sync ───────────────────────────────────────────────────────────────

class _CloudSyncSection extends ConsumerStatefulWidget {
  const _CloudSyncSection();

  @override
  ConsumerState<_CloudSyncSection> createState() => _CloudSyncSectionState();
}

class _CloudSyncSectionState extends ConsumerState<_CloudSyncSection>
    with SingleTickerProviderStateMixin {
  final _sync = SyncService();
  SyncState _state = SyncState.idle;
  String? _email;
  DateTime? _lastSynced;
  late final AnimationController _rotateCtrl;
  bool? _prevOnline;

  @override
  void initState() {
    super.initState();
    _rotateCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _loadEmail();
  }

  @override
  void dispose() {
    _rotateCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadEmail() async {
    final e = await _sync.currentFirebaseEmail();
    if (mounted) setState(() => _email = e);
  }

  String _relativeTime(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  void _onSyncState(SyncState s) {
    if (!mounted) return;
    setState(() => _state = s);
    if (s == SyncState.syncing) {
      _rotateCtrl.repeat();
    } else {
      _rotateCtrl.stop();
      _rotateCtrl.reset();
    }
  }

  // Sync Now — called when already authenticated.
  Future<void> _syncNow() async {
    _onSyncState(SyncState.syncing);
    try {
      final user = ref.read(authStateProvider).valueOrNull;
      if (user == null) {
        _onSyncState(SyncState.failed);
        return;
      }
      // Only sync pending changes for the authenticated user.
      // Do NOT call syncIfAuthenticated here — that re-uploads the offline
      // user's entire local store and can resurrect records deleted from Firebase.
      await _sync.syncPendingIfAuthenticated(
        localUserId: user.uid,
        onState: _onSyncState,
      );
      if (mounted) {
        setState(() => _lastSynced = DateTime.now());
        await ref.read(watchServiceProvider).syncToWatch();
        _showSuccessBanner();
      }
    } catch (e) {
      if (mounted) _showError(e.toString());
    }
  }

  // Sign In & Sync — called when no account is linked yet.
  Future<void> _showSignInSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _SyncSheet(
        onSync: (email, password) async {
          Navigator.pop(ctx);
          _onSyncState(SyncState.syncing);
          try {
            await _sync.signInAndSync(
              email: email,
              password: password,
              onState: _onSyncState,
            );
            if (mounted) {
              setState(() {
                _email = email;
                _lastSynced = DateTime.now();
              });
              await ref.read(watchServiceProvider).syncToWatch();
              _showSuccessBanner();
            }
          } catch (e) {
            if (mounted) _showError(e.toString());
          }
        },
      ),
    );
  }

  void _showSuccessBanner() {
    AppToast.show(
      context,
      'Sync complete',
      type: AppToastType.success,
      icon: CupertinoIcons.checkmark_circle_fill,
    );
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) setState(() => _state = SyncState.idle);
    });
  }

  void _showError(String msg) {
    AppToast.show(
      context,
      'Sync failed',
      type: AppToastType.error,
      icon: CupertinoIcons.exclamationmark_circle_fill,
    );
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isOnline = ref.watch(isOnlineProvider);
    final pendingCount = ref.watch(pendingSyncCountProvider).valueOrNull ?? 0;

    // Auto-sync when connectivity is restored.
    if (_prevOnline == false && isOnline && _email != null &&
        _state != SyncState.syncing) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _state != SyncState.syncing) _syncNow();
      });
    }
    _prevOnline = isOnline;

    final isSyncing = _state == SyncState.syncing;
    final hasSynced = _lastSynced != null || _state == SyncState.success;
    final hasFailed = _state == SyncState.failed;
    final hasPending = pendingCount > 0 && !isSyncing;

    final Color iconBg = hasFailed
        ? AppColors.blush
        : hasSynced
        ? AppColors.mint
        : hasPending
        ? const Color(0xFFFFEFCC)
        : AppColors.sky;
    final Color iconColor = hasFailed
        ? AppColors.expense
        : hasSynced
        ? AppColors.income
        : hasPending
        ? const Color(0xFFB07800)
        : const Color(0xFF2A6FB5);
    final IconData iconData = isSyncing
        ? CupertinoIcons.arrow_2_circlepath
        : hasFailed
        ? CupertinoIcons.exclamationmark_triangle
        : hasSynced
        ? CupertinoIcons.cloud_fill
        : hasPending
        ? CupertinoIcons.clock
        : CupertinoIcons.cloud_upload;

    final String syncLabel;
    if (isSyncing) {
      syncLabel = 'Uploading data…';
    } else if (hasFailed) {
      syncLabel = 'Sync failed';
    } else if (_lastSynced != null) {
      syncLabel = 'Synced · ${_relativeTime(_lastSynced!)}';
    } else if (hasSynced) {
      syncLabel = 'Synced to Cloud';
    } else if (hasPending) {
      syncLabel = '$pendingCount pending';
    } else {
      syncLabel = _email != null ? 'Not synced yet' : 'Not connected';
    }

    final bool canSync = isOnline && !isSyncing;
    final String syncBtnLabel = _email != null ? 'Sync Now' : 'Sign In & Sync';

    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(AppRadius.card),
        ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.card),
        child: Column(
          children: [
            // ── Header row ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
              child: Row(
                children: [
                  // Animated sync icon
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: iconBg,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: isSyncing
                        ? RotationTransition(
                            turns: _rotateCtrl,
                            child: Icon(
                              CupertinoIcons.arrow_2_circlepath,
                              size: 17,
                              color: iconColor,
                            ),
                          )
                        : AnimatedSwitcher(
                            duration: const Duration(milliseconds: 250),
                            transitionBuilder: (child, anim) => ScaleTransition(
                              scale: anim,
                              child: child,
                            ),
                            child: Icon(
                              iconData,
                              key: ValueKey(iconData),
                              size: 17,
                              color: iconColor,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cloud Sync',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: brand.ink,
                          ),
                        ),
                        if (hasPending)
                          Text(
                            '$pendingCount offline entr${pendingCount == 1 ? "y" : "ies"} pending',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFFB07800),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Sync button
                  GestureDetector(
                    onTap: canSync
                        ? (_email != null ? _syncNow : _showSignInSheet)
                        : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: canSync
                            ? brand.accentDark.withValues(alpha: 0.12)
                            : brand.divider,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          isSyncing
                              ? RotationTransition(
                                  turns: _rotateCtrl,
                                  child: Icon(
                                    CupertinoIcons.arrow_2_circlepath,
                                    size: 13,
                                    color: canSync
                                        ? brand.accentDark
                                        : brand.inkSoft,
                                  ),
                                )
                              : Icon(
                                  CupertinoIcons.cloud_upload,
                                  size: 13,
                                  color: canSync
                                      ? brand.accentDark
                                      : brand.inkSoft,
                                ),
                          const SizedBox(width: 5),
                          Text(
                            isSyncing ? 'Syncing…' : syncBtnLabel,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: canSync ? brand.accentDark : brand.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14),
              child: Container(height: 0.5, color: brand.divider),
            ),

            // ── Status details ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
              child: Column(
                children: [
                  Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isOnline ? AppColors.income : brand.inkSoft,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isOnline ? 'Online' : 'Offline',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: isOnline ? AppColors.income : brand.inkSoft,
                        ),
                      ),
                      const Spacer(),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Text(
                          syncLabel,
                          key: ValueKey(syncLabel),
                          style: TextStyle(
                            fontSize: 12,
                            color: hasFailed
                                ? AppColors.expense
                                : hasPending
                                ? const Color(0xFFB07800)
                                : brand.inkSoft,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_email != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          CupertinoIcons.person_circle,
                          size: 13,
                          color: brand.inkSoft,
                        ),
                        const SizedBox(width: 5),
                        Expanded(
                          child: Text(
                            _email!,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: brand.inkSoft,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Credential entry sheet — shown when no Firebase account is linked yet.
class _SyncSheet extends StatefulWidget {
  final Future<void> Function(String email, String password) onSync;

  const _SyncSheet({required this.onSync});

  @override
  State<_SyncSheet> createState() => _SyncSheetState();
}

class _SyncSheetState extends State<_SyncSheet> {
  final _emailCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: BorderRadius.circular(24),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 18),
                    decoration: BoxDecoration(
                      color: brand.divider,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: AppColors.sky,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        CupertinoIcons.cloud_upload_fill,
                        size: 20,
                        color: Color(0xFF2A6FB5),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Sign In & Sync',
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Your data stays local. Sync creates a backup.',
                            style: TextStyle(
                              fontSize: 12,
                              color: brand.inkSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _field(
                  controller: _emailCtrl,
                  hint: 'Email',
                  icon: CupertinoIcons.mail,
                  keyboardType: TextInputType.emailAddress,
                  brand: brand,
                ),
                const SizedBox(height: 10),
                _passField(brand),
                const SizedBox(height: 16),
                SizedBox(
                  height: 50,
                  child: FilledButton(
                    onPressed: _loading ? null : _doSync,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'Sign In & Sync',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  "No account? We'll create one automatically.",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: brand.inkSoft),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    required BrandColors brand,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: Icon(icon, size: 18, color: brand.inkSoft),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Widget _passField(BrandColors brand) {
    return Container(
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: TextField(
        controller: _passCtrl,
        obscureText: _obscure,
        decoration: InputDecoration(
          hintText: 'Password',
          prefixIcon: Icon(CupertinoIcons.lock, size: 18, color: brand.inkSoft),
          suffixIcon: GestureDetector(
            onTap: () => setState(() => _obscure = !_obscure),
            child: Icon(
              _obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
              size: 18,
              color: brand.inkSoft,
            ),
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
        ),
      ),
    );
  }

  Future<void> _doSync() async {
    final email = _emailCtrl.text.trim();
    final password = _passCtrl.text;
    if (email.isEmpty || password.isEmpty) return;
    setState(() => _loading = true);
    try {
      await widget.onSync(email, password);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ─── Change Email Sheet ────────────────────────────────────────────────────

class _ChangeEmailSheet extends StatefulWidget {
  final String currentEmail;
  final AuthService authService;

  const _ChangeEmailSheet({
    required this.currentEmail,
    required this.authService,
  });

  @override
  State<_ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends State<_ChangeEmailSheet> {
  final _newEmailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  bool _done = false;

  @override
  void dispose() {
    _newEmailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final newEmail = _newEmailCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (newEmail.isEmpty || password.isEmpty) {
      setState(() => _error = 'Please fill in all fields.');
      return;
    }
    if (!newEmail.contains('@')) {
      setState(() => _error = 'Enter a valid email address.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await widget.authService.changeEmail(
        currentPassword: password,
        newEmail: newEmail,
      );
      if (mounted)
        setState(() {
          _loading = false;
          _done = true;
        });
    } on ReauthRequiredException catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = e.message;
        });
    } catch (e) {
      if (mounted)
        setState(() {
          _loading = false;
          _error = 'Something went wrong. Try again.';
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 24 + bottom),
      decoration: BoxDecoration(
        color: brand.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 18),
              decoration: BoxDecoration(
                color: brand.inkSoft.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Change Email',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: brand.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Current: ${widget.currentEmail}',
            style: TextStyle(fontSize: 13, color: brand.inkSoft),
          ),
          const SizedBox(height: 20),

          if (_done) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.mint.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    CupertinoIcons.checkmark_circle_fill,
                    color: AppColors.mint,
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Verification link sent to ${_newEmailCtrl.text.trim()}.\n\nClick the link in that email to confirm your new address, then sign in again.',
                      style: TextStyle(
                        fontSize: 13,
                        color: brand.ink,
                        height: 1.45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: () => Navigator.pop(context),
                child: const Text('Done'),
              ),
            ),
          ] else ...[
            // New email field
            _Field(
              controller: _newEmailCtrl,
              label: 'New email',
              hint: 'chia70857@gmail.com',
              keyboardType: TextInputType.emailAddress,
              brand: brand,
            ),
            const SizedBox(height: 12),
            // Password field
            _Field(
              controller: _passwordCtrl,
              label: 'Current password',
              hint: '••••••••',
              obscure: _obscure,
              brand: brand,
              suffix: GestureDetector(
                onTap: () => setState(() => _obscure = !_obscure),
                child: Icon(
                  _obscure ? CupertinoIcons.eye : CupertinoIcons.eye_slash,
                  size: 18,
                  color: brand.inkSoft,
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(fontSize: 13, color: AppColors.blush),
              ),
            ],
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: CupertinoButton.filled(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const CupertinoActivityIndicator(color: Colors.white)
                    : const Text('Send Verification Link'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final bool obscure;
  final TextInputType keyboardType;
  final Widget? suffix;
  final dynamic brand;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.brand,
    this.obscure = false,
    this.keyboardType = TextInputType.text,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: brand.inkSoft,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: brand.inkSoft.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  obscureText: obscure,
                  keyboardType: keyboardType,
                  style: TextStyle(fontSize: 15, color: brand.ink),
                  decoration: InputDecoration(
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: brand.inkSoft.withValues(alpha: 0.5),
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ),
              ?suffix,
            ],
          ),
        ),
      ],
    );
  }
}
