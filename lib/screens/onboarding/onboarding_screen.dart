import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/i18n.dart';
import '../../services/prefs_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';

/// First-run onboarding shown to brand-new accounts.
///
/// Two phases inside a single button-driven [PageView]:
///   1. Setup   — display name, currency, language (persisted as you go).
///   2. Quick tour — six concise tip cards covering the key features.
///
/// Selections persist immediately (language + currency live, name on
/// leaving its page), so nothing is lost if the user skips the tour.
class OnboardingScreen extends ConsumerStatefulWidget {
  /// When true, the setup steps (name / currency / language) are skipped
  /// and only the feature tour is shown — used to replay the tour from
  /// Settings.
  final bool tourOnly;

  const OnboardingScreen({super.key, this.tourOnly = false});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageCtrl = PageController();
  final _nameCtrl = TextEditingController();

  int _page = 0;
  String _currencyCode = 'USD';
  String _currencyQuery = '';
  AppLocale _locale = AppLocale.system;
  bool _nameSaved = false;

  // 3 setup pages + 6 tour cards.
  static const _setupCount = 3;
  static const _tourCount = 6;

  int get _setupPages => widget.tourOnly ? 0 : _setupCount;
  int get _lastPage => _setupPages + _tourCount - 1;
  bool get _isTour => _page >= _setupPages;

  static const _tour = <(IconData, String, String)>[
    (CupertinoIcons.add_circled_solid, 'onb.t1Title', 'onb.t1Body'),
    (CupertinoIcons.device_phone_portrait, 'onb.t2Title', 'onb.t2Body'),
    (CupertinoIcons.square_grid_2x2_fill, 'onb.t3Title', 'onb.t3Body'),
    (CupertinoIcons.calendar, 'onb.t4Title', 'onb.t4Body'),
    (CupertinoIcons.person_2_fill, 'onb.t5Title', 'onb.t5Body'),
    (CupertinoIcons.divide_circle_fill, 'onb.t6Title', 'onb.t6Body'),
  ];

  @override
  void initState() {
    super.initState();
    _locale = ref.read(localeProvider);
    final existing = ref.read(userNameProvider);
    if (existing.trim().isNotEmpty) {
      _nameCtrl.text = existing.trim();
    } else {
      final email = ref.read(authStateProvider).valueOrNull?.email ?? '';
      if (email.contains('@')) _nameCtrl.text = email.split('@').first;
    }
    // Load the currently-saved currency for the default selection.
    ref.read(prefsServiceProvider).currencyCode().then((code) {
      if (mounted) setState(() => _currencyCode = code);
    });
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  void _saveName() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    ref.read(userNameProvider.notifier).set(name);
    _nameSaved = true;
  }

  Future<void> _selectCurrency(String code) async {
    setState(() => _currencyCode = code);
    final sym = kSupportedCurrencies[code] ?? code;
    await ref.read(prefsServiceProvider).setCurrency(code, sym);
    ref.invalidate(currencySymbolProvider);
    ref.invalidate(currencyCodeProvider);
  }

  void _selectLocale(AppLocale locale) {
    setState(() => _locale = locale);
    ref.read(localeProvider.notifier).set(locale);
  }

  void _goTo(int page) {
    FocusScope.of(context).unfocus();
    _pageCtrl.animateToPage(
      page,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeInOutCubic,
    );
  }

  void _primary() {
    HapticFeedback.selectionClick();
    if (!widget.tourOnly && _page == 0) {
      if (_nameCtrl.text.trim().isEmpty) return;
      _saveName();
    }
    if (_page >= _lastPage) {
      _finish();
    } else {
      _goTo(_page + 1);
    }
  }

  void _finish() {
    if (!widget.tourOnly && !_nameSaved) _saveName();
    Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: brand.background,
        body: SafeArea(
          child: Column(
            children: [
              _topBar(brand),
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    if (!widget.tourOnly) ...[
                      _namePage(brand),
                      _currencyPage(brand),
                      _languagePage(brand),
                    ],
                    for (final card in _tour) _tourPage(brand, card),
                  ],
                ),
              ),
              _bottomBar(brand),
            ],
          ),
        ),
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────
  Widget _topBar(BrandColors brand) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 12, 0),
      child: Row(
        children: [
          // Back chevron (hidden on the very first page).
          SizedBox(
            width: 44,
            child: _page == 0
                ? null
                : IconButton(
                    icon: Icon(CupertinoIcons.back, color: brand.ink),
                    onPressed: () => _goTo(_page - 1),
                  ),
          ),
          const Spacer(),
          if (_isTour)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: brand.accentDark.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                context.t('onb.tourBadge'),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: brand.accentDark,
                ),
              ),
            )
          else
            Text(
              context
                  .t('onb.step')
                  .replaceFirst('{n}', '${_page + 1}')
                  .replaceFirst('{total}', '$_setupPages'),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: brand.inkSoft,
              ),
            ),
          const Spacer(),
          SizedBox(
            width: 56,
            child: _isTour
                ? TextButton(
                    onPressed: _finish,
                    child: Text(
                      context.t('onb.skipTour'),
                      style: TextStyle(
                        fontSize: 13,
                        color: brand.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )
                : null,
          ),
        ],
      ),
    );
  }

  // ── Setup: display name ───────────────────────────────────────
  Widget _namePage(BrandColors brand) {
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroIcon(brand, CupertinoIcons.person_crop_circle_fill),
          const SizedBox(height: 22),
          _title(brand, context.t('onb.nameTitle')),
          const SizedBox(height: 8),
          _subtitle(brand, context.t('onb.nameSubtitle')),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: brand.divider),
            ),
            child: TextField(
              controller: _nameCtrl,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.done,
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _primary(),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: brand.ink,
              ),
              decoration: InputDecoration(
                hintText: context.t('onb.nameHint'),
                hintStyle: TextStyle(color: brand.inkSoft),
                border: InputBorder.none,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Setup: currency ───────────────────────────────────────────
  Widget _currencyPage(BrandColors brand) {
    final entries = kSupportedCurrencies.entries
        .where(
          (e) =>
              _currencyQuery.isEmpty ||
              e.key.toLowerCase().contains(_currencyQuery.toLowerCase()) ||
              e.value.toLowerCase().contains(_currencyQuery.toLowerCase()),
        )
        .toList();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroIcon(brand, CupertinoIcons.money_dollar_circle_fill),
          const SizedBox(height: 22),
          _title(brand, context.t('onb.currencyTitle')),
          const SizedBox(height: 8),
          _subtitle(brand, context.t('onb.currencySubtitle')),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: brand.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(CupertinoIcons.search, size: 16, color: brand.inkSoft),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() => _currencyQuery = v),
                    style: TextStyle(fontSize: 15, color: brand.ink),
                    decoration: InputDecoration(
                      hintText: context.t('common.searchCurrency'),
                      hintStyle: TextStyle(color: brand.inkSoft, fontSize: 15),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: entries.length,
              itemBuilder: (ctx, i) {
                final code = entries[i].key;
                final sym = entries[i].value;
                final selected = code == _currencyCode;
                return GestureDetector(
                  onTap: () => _selectCurrency(code),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? brand.accentDark.withValues(alpha: 0.10)
                          : brand.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? brand.accentDark.withValues(alpha: 0.35)
                            : Colors.transparent,
                        width: 1.2,
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected
                                ? brand.accentDark.withValues(alpha: 0.15)
                                : brand.background,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            sym,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: selected ? brand.accentDark : brand.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            code,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: brand.ink,
                            ),
                          ),
                        ),
                        if (selected)
                          Icon(
                            CupertinoIcons.check_mark_circled_solid,
                            size: 20,
                            color: brand.accentDark,
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Setup: language ───────────────────────────────────────────
  Widget _languagePage(BrandColors brand) {
    const options = [
      AppLocale.system,
      AppLocale.en,
      AppLocale.zh,
      AppLocale.ms,
    ];
    return _PageScaffold(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heroIcon(brand, CupertinoIcons.globe),
          const SizedBox(height: 22),
          _title(brand, context.t('onb.langTitle')),
          const SizedBox(height: 8),
          _subtitle(brand, context.t('onb.langSubtitle')),
          const SizedBox(height: 24),
          for (final loc in options) ...[
            GestureDetector(
              onTap: () => _selectLocale(loc),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                decoration: BoxDecoration(
                  color: _locale == loc
                      ? brand.accentDark.withValues(alpha: 0.10)
                      : brand.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _locale == loc
                        ? brand.accentDark.withValues(alpha: 0.35)
                        : brand.divider,
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        context.appLocaleLabel(loc),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: _locale == loc
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: brand.ink,
                        ),
                      ),
                    ),
                    if (_locale == loc)
                      Icon(
                        CupertinoIcons.check_mark_circled_solid,
                        size: 22,
                        color: brand.accentDark,
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tour card ─────────────────────────────────────────────────
  Widget _tourPage(BrandColors brand, (IconData, String, String) card) {
    return _PageScaffold(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: brand.accentDark.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
            child: Icon(card.$1, size: 44, color: brand.accentDark),
          ),
          const SizedBox(height: 28),
          Text(
            context.t(card.$2),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w700,
              color: brand.ink,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            context.t(card.$3),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: brand.inkSoft,
            ),
          ),
        ],
      ),
    );
  }

  // ── Bottom bar (dots + primary button) ────────────────────────
  Widget _bottomBar(BrandColors brand) {
    final count = _isTour ? _tourCount : _setupPages;
    final activeIdx = _isTour ? _page - _setupPages : _page;
    final nameEmpty =
        !widget.tourOnly && _page == 0 && _nameCtrl.text.trim().isEmpty;
    final label = _page >= _lastPage
        ? context.t('onb.getStarted')
        : _isTour
            ? context.t('onb.next')
            : context.t('onb.continue');

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (int i = 0; i < count; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == activeIdx ? 20 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == activeIdx
                        ? brand.accentDark
                        : brand.inkSoft.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (!_isTour)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                context.t('onb.changeLater'),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: brand.inkSoft),
              ),
            ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: TextButton(
              onPressed: nameEmpty ? null : _primary,
              style: TextButton.styleFrom(
                backgroundColor: nameEmpty
                    ? brand.accentDark.withValues(alpha: 0.4)
                    : brand.accentDark,
                foregroundColor: Colors.white,
                shape: const StadiumBorder(),
                disabledBackgroundColor:
                    brand.accentDark.withValues(alpha: 0.4),
                disabledForegroundColor: Colors.white,
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 17,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Small shared pieces ───────────────────────────────────────
  Widget _heroIcon(BrandColors brand, IconData icon) => Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: brand.accentDark.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(icon, size: 32, color: brand.accentDark),
      );

  Widget _title(BrandColors brand, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w700,
          color: brand.ink,
          letterSpacing: -0.6,
          height: 1.15,
        ),
      );

  Widget _subtitle(BrandColors brand, String text) => Text(
        text,
        style: TextStyle(
          fontSize: 15,
          height: 1.45,
          color: brand.inkSoft,
        ),
      );
}

/// Standard padded, top-aligned page body used by the non-list pages.
class _PageScaffold extends StatelessWidget {
  final Widget child;
  const _PageScaffold({required this.child});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.of(context).size.height * 0.42,
        ),
        child: child,
      ),
    );
  }
}
