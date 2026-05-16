import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../services/exchange_rate_service.dart';
import '../services/fx_preferences_service.dart';
import '../state/providers.dart';
import '../theme/app_theme.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────
const _blue = Color(0xFF0066CC);
const _hairline = Color(0xFFE0E0E0);
const _parchment = Color(0xFFF5F5F7);
const _ink = Color(0xFF1D1D1F);
const _ink48 = Color(0xFF7A7A7A);
const _ink24 = Color(0x3D1D1D1F);
const _gold = Color(0xFFFFB800);

// ── Currency metadata ──────────────────────────────────────────────────────────
const _kCurrencyNames = <String, String>{
  'AUD': 'Australian Dollar',   'BGN': 'Bulgarian Lev',
  'BRL': 'Brazilian Real',      'CAD': 'Canadian Dollar',
  'CHF': 'Swiss Franc',         'CNY': 'Chinese Yuan',
  'CZK': 'Czech Koruna',        'DKK': 'Danish Krone',
  'EUR': 'Euro',                'GBP': 'British Pound',
  'HKD': 'Hong Kong Dollar',    'HUF': 'Hungarian Forint',
  'IDR': 'Indonesian Rupiah',   'ILS': 'Israeli Shekel',
  'INR': 'Indian Rupee',        'ISK': 'Icelandic Króna',
  'JPY': 'Japanese Yen',        'KRW': 'South Korean Won',
  'MXN': 'Mexican Peso',        'MYR': 'Malaysian Ringgit',
  'NOK': 'Norwegian Krone',     'NZD': 'New Zealand Dollar',
  'PHP': 'Philippine Peso',     'PLN': 'Polish Zloty',
  'RON': 'Romanian Leu',        'SEK': 'Swedish Krona',
  'SGD': 'Singapore Dollar',    'THB': 'Thai Baht',
  'TRY': 'Turkish Lira',        'USD': 'US Dollar',
  'ZAR': 'South African Rand',
};

// ── Public FX button (shared across pages) ─────────────────────────────────────

class FxRateButton extends ConsumerWidget {
  final double size;
  const FxRateButton({super.key, this.size = 40});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Tooltip(
      message: 'Exchange rates',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          HapticFeedback.selectionClick();
          ExchangeRateSheet.show(context);
        },
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF2C2C2E) : _parchment,
            shape: BoxShape.circle,
            border: Border.all(
              color: brand.surface.withValues(alpha: 0.75),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Icon(
            Icons.currency_exchange_rounded,
            size: size * 0.46,
            color: isDark ? Colors.white70 : _ink.withValues(alpha: 0.75),
          ),
        ),
      ),
    );
  }
}

// ── Sheet ──────────────────────────────────────────────────────────────────────

class ExchangeRateSheet extends ConsumerStatefulWidget {
  const ExchangeRateSheet({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      enableDrag: true,
      isDismissible: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (_) => const ExchangeRateSheet(),
    );
  }

  @override
  ConsumerState<ExchangeRateSheet> createState() => _ExchangeRateSheetState();
}

class _ExchangeRateSheetState extends ConsumerState<ExchangeRateSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entryCtrl;
  late final Animation<double> _entryFade;
  late final Animation<Offset> _entrySlide;
  final _searchCtrl = TextEditingController();
  String _query = '';
  Map<String, double>? _rates;
  DateTime? _lastFetched;
  bool _loading = true;
  String? _error;
  String _base = 'USD';
  bool _showHidden = false;

  // Converter state
  bool _calcOpen = false;
  String _fromCode = 'USD';
  String _toCode = 'MYR';
  final _fromCtrl = TextEditingController(text: '1');
  final _toCtrl = TextEditingController();
  bool _editingFrom = true;
  final _fromFocus = FocusNode();
  final _toFocus = FocusNode();

  // Optimistic local prefs (updated immediately, synced to Firebase)
  FxPreferences _localPrefs = const FxPreferences();
  FxPreferencesService? _prefsSvc;
  bool _prefsLoaded = false; // true after first Firestore delivery

  @override
  void initState() {
    super.initState();
    _entryCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 380),
    );
    _entryFade = CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOut);
    _entrySlide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic));
    _entryCtrl.forward();
    _init();
  }

  Future<void> _init() async {
    final code = await ref.read(prefsServiceProvider).currencyCode();
    if (!mounted) return;
    setState(() {
      _base = code;
      _fromCode = code;
      _toCode = code == 'USD' ? 'MYR' : 'USD';
    });
    // Wire up Firestore service
    final user = ref.read(authStateProvider).valueOrNull;
    if (user != null) {
      _prefsSvc = FxPreferencesService(FirebaseFirestore.instance, user.uid);
    }
    await _fetchRates();
    _recalc(fromSide: true);
  }

  Future<void> _fetchRates() async {
    setState(() { _loading = true; _error = null; });
    try {
      final svc = ExchangeRateService();
      final rates = await svc.getRates(_base);
      final fetched = await svc.lastFetched(_base);
      if (!mounted) return;
      setState(() {
        _rates = rates;
        _lastFetched = fetched ?? DateTime.now();
        _loading = false;
      });
      _recalc(fromSide: _editingFrom);
    } catch (_) {
      if (!mounted) return;
      setState(() { _error = 'Could not load rates. Check your connection.'; _loading = false; });
    }
  }

  // ── Preferences ──────────────────────────────────────────────────────────────

  void _updatePrefs(FxPreferences updated) {
    setState(() => _localPrefs = updated);
    _prefsSvc?.save(updated);
    HapticFeedback.lightImpact();
  }

  void _toggleStar(String code) => _updatePrefs(_localPrefs.toggleStar(code));

  void _hideCode(String code) {
    _updatePrefs(_localPrefs.toggleHide(code));
    HapticFeedback.mediumImpact();
  }

  void _unhideCode(String code) => _updatePrefs(_localPrefs.unhide(code));

  // ── Converter ────────────────────────────────────────────────────────────────

  double _crossRate(String from, String to) {
    if (from == to) return 1.0;
    final rates = _rates ?? {};
    if (from == _base) return rates[to] ?? 1.0;
    if (to == _base) return 1.0 / (rates[from] ?? 1.0);
    final fromRate = rates[from] ?? 1.0;
    final toRate = rates[to] ?? 1.0;
    return toRate / fromRate;
  }

  void _recalc({required bool fromSide}) {
    if (_rates == null) return;
    if (fromSide) {
      final amt = double.tryParse(_fromCtrl.text.replaceAll(',', '')) ?? 0.0;
      _toCtrl.text = _fmtCalc(amt * _crossRate(_fromCode, _toCode));
    } else {
      final amt = double.tryParse(_toCtrl.text.replaceAll(',', '')) ?? 0.0;
      _fromCtrl.text = _fmtCalc(amt * _crossRate(_toCode, _fromCode));
    }
  }

  String _fmtCalc(double v) {
    if (v == 0) return '0';
    if (v >= 1000) return NumberFormat('#,##0.00').format(v);
    if (v >= 1) return NumberFormat('0.####').format(v);
    return NumberFormat('0.######').format(v);
  }

  void _swapCurrencies() {
    HapticFeedback.selectionClick();
    setState(() {
      final tmp = _fromCode; _fromCode = _toCode; _toCode = tmp;
      _editingFrom = true;
    });
    _recalc(fromSide: true);
  }

  void _pickCurrency(bool isFrom) async {
    final available = (_rates?.keys.toList() ?? [])..sort();
    if (!available.contains(_base)) available.insert(0, _base);

    final picked = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => _MiniCurrencyPicker(
        selected: isFrom ? _fromCode : _toCode,
        currencies: available,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() { if (isFrom) { _fromCode = picked; } else { _toCode = picked; } });
    _recalc(fromSide: _editingFrom);
  }

  String _formatRate(double rate) {
    if (rate >= 1000) return NumberFormat('#,##0').format(rate);
    if (rate >= 100) return NumberFormat('#,##0.00').format(rate);
    return NumberFormat('0.0000').format(rate);
  }

  @override
  void dispose() {
    _entryCtrl.dispose();
    _searchCtrl.dispose();
    _fromCtrl.dispose();
    _toCtrl.dispose();
    _fromFocus.dispose();
    _toFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // On first Firestore delivery, seed _localPrefs from the saved data.
    // After that, _localPrefs is the source of truth (optimistic updates).
    final streamedPrefs = ref.watch(fxPreferencesProvider).valueOrNull;
    if (streamedPrefs != null && !_prefsLoaded) {
      _prefsLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _localPrefs = streamedPrefs);
      });
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final chipBg = isDark ? const Color(0xFF2C2C2E) : _parchment;
    final searchBg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final divider = isDark ? const Color(0xFF3A3A3C) : _hairline;
    final inkColor = isDark ? Colors.white : _ink;
    final mutedColor = isDark ? const Color(0xFF8E8E93) : _ink48;

    // Build sorted entry lists
    final rates = _rates ?? {};
    final allEntries = rates.entries
        .where((e) => e.key != _base)
        .where((e) {
          if (_query.isEmpty) return true;
          final q = _query.toLowerCase();
          return e.key.toLowerCase().contains(q) ||
              (_kCurrencyNames[e.key] ?? '').toLowerCase().contains(q);
        })
        .toList()
      ..sort((a, b) {
        final aStarred = _localPrefs.isStarred(a.key);
        final bStarred = _localPrefs.isStarred(b.key);
        if (aStarred && !bStarred) return -1;
        if (!aStarred && bStarred) return 1;
        return a.key.compareTo(b.key);
      });

    final visibleEntries = allEntries
        .where((e) => !_localPrefs.isHidden(e.key) || _query.isNotEmpty)
        .toList();
    final hiddenEntries = _query.isEmpty
        ? allEntries.where((e) => _localPrefs.isHidden(e.key)).toList()
        : <MapEntry<String, double>>[];

    final starredVisible = visibleEntries.where((e) => _localPrefs.isStarred(e.key)).toList();
    final normalVisible = visibleEntries.where((e) => !_localPrefs.isStarred(e.key)).toList();

    final updatedLabel = _lastFetched != null
        ? 'Updated ${DateFormat('d MMM, HH:mm').format(_lastFetched!)}'
        : '';

    return FadeTransition(
      opacity: _entryFade,
      child: SlideTransition(
        position: _entrySlide,
        child: GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: () => FocusScope.of(context).unfocus(),
      child: Material(
        type: MaterialType.transparency,
        child: Container(
          height: MediaQuery.of(context).size.height * 0.90,
          decoration: BoxDecoration(
            color: surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              // ── Handle ──────────────────────────────────────────────────
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40, height: 5,
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF48484A) : _ink24,
                    borderRadius: BorderRadius.circular(100),
                  ),
                ),
              ),
              const SizedBox(height: 18),

              // ── Header ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Exchange Rates',
                              style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.w600,
                                letterSpacing: -0.5, color: inkColor,
                              )),
                          const SizedBox(height: 3),
                          Text('Base: $_base  ·  Frankfurter · ECB',
                              style: TextStyle(fontSize: 12, color: mutedColor, letterSpacing: -0.1)),
                          if (updatedLabel.isNotEmpty)
                            Text(updatedLabel, style: TextStyle(fontSize: 11, color: mutedColor)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                            decoration: BoxDecoration(
                              color: chipBg, borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Text('Done',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500,
                                    color: _blue, letterSpacing: -0.2)),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Convert toggle
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _calcOpen = !_calcOpen);
                                if (!_calcOpen) FocusScope.of(context).unfocus();
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: _calcOpen ? _blue : chipBg,
                                  borderRadius: BorderRadius.circular(9999),
                                  border: Border.all(
                                    color: _calcOpen ? _blue : divider, width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(CupertinoIcons.arrow_right_arrow_left,
                                        size: 11, color: _calcOpen ? Colors.white : _blue),
                                    const SizedBox(width: 4),
                                    Text('Convert',
                                        style: TextStyle(fontSize: 12,
                                            color: _calcOpen ? Colors.white : _blue,
                                            letterSpacing: -0.1)),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Refresh
                            GestureDetector(
                              onTap: _loading ? null : _fetchRates,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _loading
                                      ? const SizedBox(width: 10, height: 10,
                                          child: CircularProgressIndicator(strokeWidth: 1.5, color: _ink48))
                                      : const Icon(CupertinoIcons.arrow_2_circlepath, size: 11, color: _blue),
                                  const SizedBox(width: 3),
                                  Text('Refresh',
                                      style: TextStyle(fontSize: 12,
                                          color: _loading ? mutedColor : _blue, letterSpacing: -0.1)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // ── Converter (animated expand) ──────────────────────────────
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeInOut,
                child: _calcOpen
                    ? _ConverterCard(
                        isDark: isDark, chipBg: chipBg, divider: divider,
                        inkColor: inkColor, mutedColor: mutedColor,
                        fromCode: _fromCode, toCode: _toCode,
                        fromCtrl: _fromCtrl, toCtrl: _toCtrl,
                        fromFocus: _fromFocus, toFocus: _toFocus,
                        loading: _rates == null,
                        onFromChanged: (v) { _editingFrom = true; _recalc(fromSide: true); },
                        onToChanged: (v) { _editingFrom = false; _recalc(fromSide: false); },
                        onPickFrom: () => _pickCurrency(true),
                        onPickTo: () => _pickCurrency(false),
                        onSwap: _swapCurrencies,
                      )
                    : const SizedBox.shrink(),
              ),

              const SizedBox(height: 14),

              // ── Search (taller) ──────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                  decoration: BoxDecoration(
                    color: searchBg, borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(CupertinoIcons.search, size: 17, color: mutedColor),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          autofocus: false,
                          style: TextStyle(fontSize: 16, color: inkColor, letterSpacing: -0.2),
                          decoration: InputDecoration(
                            hintText: 'Search currency…',
                            hintStyle: TextStyle(fontSize: 16, color: mutedColor, letterSpacing: -0.2),
                            border: InputBorder.none, isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      if (_query.isNotEmpty)
                        GestureDetector(
                          onTap: () { _searchCtrl.clear(); setState(() => _query = ''); },
                          child: Icon(CupertinoIcons.xmark_circle_fill, size: 18, color: mutedColor),
                        ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),
              Divider(height: 1, thickness: 1, color: divider),

              // ── Rates list ───────────────────────────────────────────────
              Expanded(
                child: _loading
                    ? const Center(child: CupertinoActivityIndicator())
                    : _error != null
                        ? _ErrorView(error: _error!, onRetry: _fetchRates, mutedColor: mutedColor)
                        : GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () => FocusScope.of(context).unfocus(),
                            child: CustomScrollView(
                              primary: true,
                              slivers: [
                                // Starred section
                                if (starredVisible.isNotEmpty && _query.isEmpty) ...[
                                  _SectionHeader(
                                    label: 'STARRED',
                                    icon: CupertinoIcons.star_fill,
                                    iconColor: _gold,
                                    mutedColor: mutedColor,
                                  ),
                                  SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (ctx, i) => _RateRow(
                                        key: ValueKey('starred_${starredVisible[i].key}'),
                                        code: starredVisible[i].key,
                                        rate: starredVisible[i].value,
                                        base: _base,
                                        isStarred: true,
                                        isDark: isDark,
                                        chipBg: chipBg,
                                        divider: divider,
                                        inkColor: inkColor,
                                        mutedColor: mutedColor,
                                        showDivider: i < starredVisible.length - 1,
                                        formatRate: _formatRate,
                                        onStar: () => _toggleStar(starredVisible[i].key),
                                        onHide: () => _hideCode(starredVisible[i].key),
                                      ),
                                      childCount: starredVisible.length,
                                    ),
                                  ),
                                  SliverToBoxAdapter(child: Divider(height: 1, thickness: 1, color: divider)),
                                  const SliverToBoxAdapter(child: SizedBox(height: 6)),
                                ],

                                // All / remaining section
                                if (normalVisible.isNotEmpty) ...[
                                  if (starredVisible.isNotEmpty && _query.isEmpty)
                                    _SectionHeader(label: 'ALL CURRENCIES', mutedColor: mutedColor),
                                  SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (ctx, i) => _RateRow(
                                        key: ValueKey('normal_${normalVisible[i].key}'),
                                        code: normalVisible[i].key,
                                        rate: normalVisible[i].value,
                                        base: _base,
                                        isStarred: false,
                                        isDark: isDark,
                                        chipBg: chipBg,
                                        divider: divider,
                                        inkColor: inkColor,
                                        mutedColor: mutedColor,
                                        showDivider: i < normalVisible.length - 1,
                                        formatRate: _formatRate,
                                        onStar: () => _toggleStar(normalVisible[i].key),
                                        onHide: () => _hideCode(normalVisible[i].key),
                                      ),
                                      childCount: normalVisible.length,
                                    ),
                                  ),
                                ],

                                // Hidden section toggle
                                if (hiddenEntries.isNotEmpty)
                                  SliverToBoxAdapter(
                                    child: _HiddenToggle(
                                      count: hiddenEntries.length,
                                      expanded: _showHidden,
                                      isDark: isDark,
                                      chipBg: chipBg,
                                      divider: divider,
                                      inkColor: inkColor,
                                      mutedColor: mutedColor,
                                      onToggle: () => setState(() => _showHidden = !_showHidden),
                                    ),
                                  ),

                                if (hiddenEntries.isNotEmpty && _showHidden)
                                  SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (ctx, i) => _RateRow(
                                        key: ValueKey('hidden_${hiddenEntries[i].key}'),
                                        code: hiddenEntries[i].key,
                                        rate: hiddenEntries[i].value,
                                        base: _base,
                                        isStarred: false,
                                        isHidden: true,
                                        isDark: isDark,
                                        chipBg: chipBg,
                                        divider: divider,
                                        inkColor: inkColor,
                                        mutedColor: mutedColor,
                                        showDivider: i < hiddenEntries.length - 1,
                                        formatRate: _formatRate,
                                        onStar: () => _toggleStar(hiddenEntries[i].key),
                                        onHide: () => _unhideCode(hiddenEntries[i].key),
                                      ),
                                      childCount: hiddenEntries.length,
                                    ),
                                  ),

                                // Footer
                                SliverToBoxAdapter(
                                  child: Padding(
                                    padding: const EdgeInsets.fromLTRB(22, 20, 22, 48),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Divider(height: 1, thickness: 1, color: divider),
                                        const SizedBox(height: 14),
                                        Row(children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            decoration: BoxDecoration(
                                              color: chipBg,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: divider, width: 0.5),
                                            ),
                                            child: Text('Open source · Free · No API key',
                                                style: TextStyle(fontSize: 10, color: mutedColor, letterSpacing: 0.1)),
                                          ),
                                        ]),
                                        const SizedBox(height: 8),
                                        Text(
                                          'Rates provided by Frankfurter (frankfurter.app). Data sourced from the European Central Bank (ECB). Rates refresh daily on ECB business days.',
                                          style: TextStyle(fontSize: 11, color: mutedColor, height: 1.55, letterSpacing: -0.1),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ],
          ),
        ),
      ),
        ),
      ),
    );
  }
}

// ── Rate row ──────────────────────────────────────────────────────────────────

// ── Swipe-to-hide row wrapper ─────────────────────────────────────────────────

class _SwipeRow extends StatefulWidget {
  final Widget child;
  final bool isHidden;
  final VoidCallback onHide;

  const _SwipeRow({
    super.key,
    required this.child,
    required this.isHidden,
    required this.onHide,
  });

  @override
  State<_SwipeRow> createState() => _SwipeRowState();
}

class _SwipeRowState extends State<_SwipeRow> with SingleTickerProviderStateMixin {
  static const _kActionWidth = 80.0;
  static const _kConfirmThreshold = 0.55;

  late AnimationController _ctrl;
  bool _isOpen = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  void _onDragUpdate(DragUpdateDetails d) {
    // Only allow left swipe
    final delta = -d.delta.dx / _kActionWidth;
    _ctrl.value = (_ctrl.value + delta).clamp(0.0, 1.0);
  }

  void _onDragEnd(DragEndDetails d) {
    final velocity = d.primaryVelocity ?? 0;
    if (_ctrl.value > _kConfirmThreshold || velocity < -600) {
      _ctrl.animateTo(1.0, curve: Curves.easeOut,
          duration: const Duration(milliseconds: 180));
      setState(() => _isOpen = true);
    } else {
      _snapClosed();
    }
  }

  void _snapClosed() {
    _ctrl.animateTo(0.0, curve: Curves.easeOut,
        duration: const Duration(milliseconds: 220));
    setState(() => _isOpen = false);
  }

  void _triggerHide() {
    HapticFeedback.mediumImpact();
    _snapClosed();
    widget.onHide();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final actionBg = widget.isHidden
        ? const Color(0xFF34C759) // green = "show"
        : const Color(0xFFFF3B30); // red = "hide"
    final actionIcon = widget.isHidden ? CupertinoIcons.eye : CupertinoIcons.eye_slash;
    final actionLabel = widget.isHidden ? 'Show' : 'Hide';

    return GestureDetector(
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onTap: _isOpen ? _snapClosed : null,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (ctx, child) {
          final offset = -_ctrl.value * _kActionWidth;
          // Scale + fade the action button as it's revealed
          final actionProgress = _ctrl.value.clamp(0.0, 1.0);
          return Stack(
            children: [
              // ── Action button (revealed on swipe) ────────────────────
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: GestureDetector(
                    onTap: _triggerHide,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 80),
                      width: _kActionWidth * actionProgress + 0.001,
                      color: actionBg,
                      alignment: Alignment.center,
                      child: actionProgress > 0.3
                          ? Opacity(
                              opacity: ((actionProgress - 0.3) / 0.7).clamp(0, 1),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(actionIcon, color: Colors.white, size: 18),
                                  const SizedBox(height: 3),
                                  Text(actionLabel,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: -0.2,
                                      )),
                                ],
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ),
                ),
              ),
              // ── Sliding content ──────────────────────────────────────
              Transform.translate(
                offset: Offset(offset, 0),
                child: Container(
                  color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
                  child: child,
                ),
              ),
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}

// ── Star burst painter ─────────────────────────────────────────────────────────

class _BurstPainter extends CustomPainter {
  final double progress; // 0 → 1
  final Color color;

  _BurstPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;
    const count = 8;
    const maxDist = 22.0;
    final center = Offset(size.width / 2, size.height / 2);

    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi - math.pi / 2;
      final dist = maxDist * progress;
      final opacity = (1 - progress).clamp(0.0, 1.0);
      final dotR = (3.0 * (1 - progress * 0.6)).clamp(0.8, 3.0);

      canvas.drawCircle(
        Offset(center.dx + math.cos(angle) * dist,
               center.dy + math.sin(angle) * dist),
        dotR,
        Paint()..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_BurstPainter old) => old.progress != progress;
}

// ── Rate row ──────────────────────────────────────────────────────────────────

class _RateRow extends StatefulWidget {
  final String code;
  final double rate;
  final String base;
  final bool isStarred;
  final bool isHidden;
  final bool isDark;
  final Color chipBg;
  final Color divider;
  final Color inkColor;
  final Color mutedColor;
  final bool showDivider;
  final String Function(double) formatRate;
  final VoidCallback onStar;
  final VoidCallback onHide;

  const _RateRow({
    super.key,
    required this.code,
    required this.rate,
    required this.base,
    required this.isStarred,
    this.isHidden = false,
    required this.isDark,
    required this.chipBg,
    required this.divider,
    required this.inkColor,
    required this.mutedColor,
    required this.showDivider,
    required this.formatRate,
    required this.onStar,
    required this.onHide,
  });

  @override
  State<_RateRow> createState() => _RateRowState();
}

class _RateRowState extends State<_RateRow> with TickerProviderStateMixin {
  // Star bounce
  late AnimationController _starCtrl;
  late Animation<double> _starScale;
  // Burst particles
  late AnimationController _burstCtrl;
  late Animation<double> _burstAnim;
  // Gold glow flash
  late AnimationController _glowCtrl;
  late Animation<double> _glowAnim;

  @override
  void initState() {
    super.initState();

    _starCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 340));
    _starScale = TweenSequence([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.7), weight: 15),
      TweenSequenceItem(tween: Tween(begin: 0.7, end: 1.5), weight: 45),
      TweenSequenceItem(tween: Tween(begin: 1.5, end: 0.9), weight: 25),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 15),
    ]).animate(CurvedAnimation(parent: _starCtrl, curve: Curves.easeInOut));

    _burstCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 520));
    _burstAnim = CurvedAnimation(parent: _burstCtrl, curve: Curves.easeOut);

    _glowCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 400));
    _glowAnim = Tween(begin: 0.0, end: 1.0).animate(
        CurvedAnimation(parent: _glowCtrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _starCtrl.dispose();
    _burstCtrl.dispose();
    _glowCtrl.dispose();
    super.dispose();
  }

  void _handleStar() {
    HapticFeedback.lightImpact();
    _starCtrl.forward(from: 0);
    if (!widget.isStarred) {
      // Starring: fire burst + glow
      _burstCtrl.forward(from: 0);
      _glowCtrl.forward(from: 0).then((_) => _glowCtrl.reverse());
    }
    widget.onStar();
  }

  @override
  Widget build(BuildContext context) {
    return _SwipeRow(
      key: ValueKey('swipe_${widget.code}'),
      isHidden: widget.isHidden,
      onHide: widget.onHide,
      child: Opacity(
        opacity: widget.isHidden ? 0.45 : 1.0,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 12, 0),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  children: [
                    // Currency chip
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: widget.chipBg,
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(color: widget.divider, width: 0.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        widget.code.length >= 2 ? widget.code.substring(0, 2) : widget.code,
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                            color: widget.inkColor, letterSpacing: -0.3),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Code + name
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.code,
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                                  color: widget.inkColor, letterSpacing: -0.3)),
                          Text(_kCurrencyNames[widget.code] ?? widget.code,
                              style: TextStyle(fontSize: 12, color: widget.mutedColor,
                                  letterSpacing: -0.1)),
                        ],
                      ),
                    ),
                    // Rate
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(widget.formatRate(widget.rate),
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                                color: widget.inkColor, letterSpacing: -0.4)),
                        Text('per 1 ${widget.base}',
                            style: TextStyle(fontSize: 10, color: widget.mutedColor)),
                      ],
                    ),
                    const SizedBox(width: 4),

                    // ── Star button with burst ──────────────────────────
                    GestureDetector(
                      onTap: _handleStar,
                      behavior: HitTestBehavior.opaque,
                      child: SizedBox(
                        width: 40, height: 40,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // Glow ring (fades in/out when starring)
                            AnimatedBuilder(
                              animation: _glowAnim,
                              builder: (ctx, _) {
                                final v = _glowAnim.value;
                                if (v <= 0) return const SizedBox.shrink();
                                return Container(
                                  width: 32 * (0.6 + v * 0.4),
                                  height: 32 * (0.6 + v * 0.4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: _gold.withValues(alpha: v * 0.22),
                                  ),
                                );
                              },
                            ),
                            // Burst particles
                            AnimatedBuilder(
                              animation: _burstAnim,
                              builder: (ctx, _) => CustomPaint(
                                size: const Size(40, 40),
                                painter: _BurstPainter(
                                  progress: _burstAnim.value,
                                  color: _gold,
                                ),
                              ),
                            ),
                            // Star icon with bounce scale
                            ScaleTransition(
                              scale: _starScale,
                              child: AnimatedSwitcher(
                                duration: const Duration(milliseconds: 180),
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(scale: anim, child: child),
                                child: Icon(
                                  widget.isStarred
                                      ? CupertinoIcons.star_fill
                                      : CupertinoIcons.star,
                                  key: ValueKey(widget.isStarred),
                                  size: 21,
                                  color: widget.isStarred ? _gold : widget.mutedColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.showDivider)
              Divider(height: 1, thickness: 1, color: widget.divider, indent: 22, endIndent: 22),
          ],
        ),
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? iconColor;
  final Color mutedColor;

  const _SectionHeader({
    required this.label,
    this.icon,
    this.iconColor,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 8),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: iconColor ?? mutedColor),
              const SizedBox(width: 5),
            ],
            Text(label,
                style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w600,
                  color: mutedColor, letterSpacing: 0.6,
                )),
          ],
        ),
      ),
    );
  }
}

// ── Hidden toggle row ─────────────────────────────────────────────────────────

class _HiddenToggle extends StatelessWidget {
  final int count;
  final bool expanded;
  final bool isDark;
  final Color chipBg;
  final Color divider;
  final Color inkColor;
  final Color mutedColor;
  final VoidCallback onToggle;

  const _HiddenToggle({
    required this.count,
    required this.expanded,
    required this.isDark,
    required this.chipBg,
    required this.divider,
    required this.inkColor,
    required this.mutedColor,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Divider(height: 1, thickness: 1, color: divider),
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () { HapticFeedback.selectionClick(); onToggle(); },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
            child: Row(
              children: [
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  child: Icon(CupertinoIcons.chevron_right, size: 13, color: mutedColor),
                ),
                const SizedBox(width: 10),
                Text(
                  expanded ? 'Hide $count hidden currencies' : 'Show $count hidden currencies',
                  style: TextStyle(fontSize: 14, color: mutedColor, letterSpacing: -0.2),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Error view ─────────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final Color mutedColor;

  const _ErrorView({required this.error, required this.onRetry, required this.mutedColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(CupertinoIcons.wifi_slash, size: 36, color: mutedColor),
            const SizedBox(height: 14),
            Text(error,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: mutedColor, height: 1.4)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: onRetry,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
                decoration: BoxDecoration(color: _blue, borderRadius: BorderRadius.circular(9999)),
                child: const Text('Try again',
                    style: TextStyle(fontSize: 15, color: Colors.white,
                        fontWeight: FontWeight.w400, letterSpacing: -0.2)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Converter card ─────────────────────────────────────────────────────────────

class _ConverterCard extends StatelessWidget {
  final bool isDark;
  final Color chipBg;
  final Color divider;
  final Color inkColor;
  final Color mutedColor;
  final String fromCode;
  final String toCode;
  final TextEditingController fromCtrl;
  final TextEditingController toCtrl;
  final FocusNode fromFocus;
  final FocusNode toFocus;
  final bool loading;
  final ValueChanged<String> onFromChanged;
  final ValueChanged<String> onToChanged;
  final VoidCallback onPickFrom;
  final VoidCallback onPickTo;
  final VoidCallback onSwap;

  const _ConverterCard({
    required this.isDark, required this.chipBg, required this.divider,
    required this.inkColor, required this.mutedColor,
    required this.fromCode, required this.toCode,
    required this.fromCtrl, required this.toCtrl,
    required this.fromFocus, required this.toFocus,
    required this.loading,
    required this.onFromChanged, required this.onToChanged,
    required this.onPickFrom, required this.onPickTo, required this.onSwap,
  });

  @override
  Widget build(BuildContext context) {
    final cardBg = isDark ? const Color(0xFF2C2C2E) : _parchment;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: divider, width: 0.5),
        ),
        child: Column(
          children: [
            _ConverterRow(
              isDark: isDark, chipBg: chipBg, divider: divider,
              inkColor: inkColor, mutedColor: mutedColor,
              code: fromCode, ctrl: fromCtrl, focusNode: fromFocus,
              label: 'From', onChanged: onFromChanged, onPickCurrency: onPickFrom,
            ),
            Stack(
              alignment: Alignment.center,
              children: [
                Divider(height: 1, thickness: 1, color: divider),
                GestureDetector(
                  onTap: onSwap,
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF3A3A3C) : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(color: divider, width: 1),
                    ),
                    child: const Icon(CupertinoIcons.arrow_up_arrow_down, size: 14, color: _blue),
                  ),
                ),
              ],
            ),
            _ConverterRow(
              isDark: isDark, chipBg: chipBg, divider: divider,
              inkColor: inkColor, mutedColor: mutedColor,
              code: toCode, ctrl: toCtrl, focusNode: toFocus,
              label: 'To', onChanged: onToChanged, onPickCurrency: onPickTo,
            ),
          ],
        ),
      ),
    );
  }
}

class _ConverterRow extends StatelessWidget {
  final bool isDark;
  final Color chipBg;
  final Color divider;
  final Color inkColor;
  final Color mutedColor;
  final String code;
  final TextEditingController ctrl;
  final FocusNode focusNode;
  final String label;
  final ValueChanged<String> onChanged;
  final VoidCallback onPickCurrency;

  const _ConverterRow({
    required this.isDark, required this.chipBg, required this.divider,
    required this.inkColor, required this.mutedColor,
    required this.code, required this.ctrl, required this.focusNode,
    required this.label, required this.onChanged, required this.onPickCurrency,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: onPickCurrency,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(9999),
                border: Border.all(color: divider, width: 0.5),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(code,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                          color: inkColor, letterSpacing: -0.2)),
                  const SizedBox(width: 4),
                  Icon(CupertinoIcons.chevron_up_chevron_down, size: 11, color: mutedColor),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(fontSize: 10, color: mutedColor, letterSpacing: 0.2)),
                const SizedBox(height: 2),
                TextField(
                  controller: ctrl,
                  focusNode: focusNode,
                  autofocus: false,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w600,
                      color: inkColor, letterSpacing: -0.5),
                  decoration: InputDecoration(
                    border: InputBorder.none, isDense: true,
                    contentPadding: EdgeInsets.zero,
                    hintText: '0',
                    hintStyle: TextStyle(fontSize: 26, fontWeight: FontWeight.w600,
                        color: mutedColor.withValues(alpha: 0.5), letterSpacing: -0.5),
                  ),
                  onChanged: onChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Mini currency picker ───────────────────────────────────────────────────────

class _MiniCurrencyPicker extends StatefulWidget {
  final String selected;
  final List<String> currencies;
  const _MiniCurrencyPicker({required this.selected, required this.currencies});

  @override
  State<_MiniCurrencyPicker> createState() => _MiniCurrencyPickerState();
}

class _MiniCurrencyPickerState extends State<_MiniCurrencyPicker> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() { _searchCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1C1C1E) : Colors.white;
    final searchBg = isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
    final divider = isDark ? const Color(0xFF3A3A3C) : _hairline;
    final inkColor = isDark ? Colors.white : _ink;
    final mutedColor = isDark ? const Color(0xFF8E8E93) : _ink48;

    final filtered = widget.currencies.where((c) =>
        _query.isEmpty ||
        c.toLowerCase().contains(_query.toLowerCase()) ||
        (_kCurrencyNames[c] ?? '').toLowerCase().contains(_query.toLowerCase())).toList();

    return Material(
      type: MaterialType.transparency,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.65,
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Center(
              child: Container(
                width: 36, height: 4,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF48484A) : _ink24,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
            ),
            const SizedBox(height: 14),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Text('Select Currency',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600,
                          color: inkColor, letterSpacing: -0.3)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(fontSize: 15, color: _blue, letterSpacing: -0.2)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(color: searchBg, borderRadius: BorderRadius.circular(12)),
                child: Row(
                  children: [
                    Icon(CupertinoIcons.search, size: 15, color: mutedColor),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _searchCtrl,
                        autofocus: true,
                        style: TextStyle(fontSize: 15, color: inkColor),
                        decoration: InputDecoration(
                          hintText: 'Search…',
                          hintStyle: TextStyle(fontSize: 15, color: mutedColor),
                          border: InputBorder.none, isDense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Divider(height: 1, thickness: 1, color: divider),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: filtered.length,
                separatorBuilder: (ctx, i) =>
                    Divider(height: 1, thickness: 1, color: divider, indent: 22, endIndent: 22),
                itemBuilder: (ctx, i) {
                  final code = filtered[i];
                  final isSelected = code == widget.selected;
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.pop(context, code),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 13, 22, 13),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(code,
                                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                                        color: inkColor, letterSpacing: -0.2)),
                                Text(_kCurrencyNames[code] ?? code,
                                    style: TextStyle(fontSize: 12, color: mutedColor)),
                              ],
                            ),
                          ),
                          if (isSelected)
                            const Icon(CupertinoIcons.checkmark, size: 15, color: _blue),
                        ],
                      ),
                    ),
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
