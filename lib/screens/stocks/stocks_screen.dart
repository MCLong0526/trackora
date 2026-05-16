import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../models/account.dart';
import '../../models/stock_investment.dart';
import '../../services/stock_service.dart';
import '../../state/providers.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_toast.dart';
import 'stock_detail_screen.dart';

// ── Design tokens ──────────────────────────────────────────────────────────────

const _blue = Color(0xFF0066CC);
const _green = Color(0xFF34C759);
const _red = Color(0xFFFF3B30);

// ── FX rate provider ──────────────────────────────────────────────────────────

const _fxFallback = {'MYR': 4.48, 'SGD': 1.35, 'EUR': 0.92, 'GBP': 0.79};

final stockFxRateProvider = FutureProvider.autoDispose.family<double, String>(
  (ref, targetIso) async {
    if (targetIso == 'USD') return 1.0;
    try {
      final resp = await http.get(Uri.parse(
        'https://cdn.jsdelivr.net/npm/@fawazahmed0/currency-api@latest/v1/currencies/usd.min.json',
      )).timeout(const Duration(seconds: 12));
      if (resp.statusCode == 200) {
        final fx = jsonDecode(resp.body) as Map<String, dynamic>;
        final rates = fx['usd'] as Map<String, dynamic>?;
        if (rates != null) {
          return (rates[targetIso.toLowerCase()] as num?)?.toDouble() ?? 1.0;
        }
      }
    } catch (_) {}
    return (_fxFallback[targetIso] ?? 1.0).toDouble();
  },
);

// ── Quote cache provider ───────────────────────────────────────────────────────

final _stockQuoteProvider =
    FutureProvider.autoDispose.family<StockQuote?, String>(
  (ref, symbol) async {
    final svc = ref.read(stockServiceProvider);
    return svc.getQuote(symbol, range: '1M');
  },
);

// ── Stocks Screen ──────────────────────────────────────────────────────────────

class StocksScreen extends ConsumerStatefulWidget {
  const StocksScreen({super.key});

  @override
  ConsumerState<StocksScreen> createState() => _StocksScreenState();
}

class _StocksScreenState extends ConsumerState<StocksScreen> {
  String _filter = 'All'; // 'All', 'KLSE', 'USD'
  String _sort = 'Value'; // 'Value', 'Gain%', 'Name'
  String _groupBy = 'None'; // 'None', 'Sector', 'Market', 'Currency'

  List<StockInvestment> _applyFilter(List<StockInvestment> stocks) {
    if (_filter == 'All') return stocks;
    if (_filter == 'KLSE') {
      return stocks.where((s) => s.exchangeDisplay == 'KLSE' || s.currency == 'MYR').toList();
    }
    if (_filter == 'USD') {
      return stocks.where((s) => s.currency == 'USD' || (s.currency == null && s.exchangeDisplay != 'KLSE')).toList();
    }
    return stocks;
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final stocks = ref.watch(stockInvestmentsProvider).valueOrNull ?? <StockInvestment>[];
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? 'RM';
    final filtered = _applyFilter(stocks);

    // Determine currency symbol ISO for FX
    const symToIso = {
      'RM': 'MYR', '\$': 'USD', 'S\$': 'SGD', '€': 'EUR', '£': 'GBP',
    };
    final localIso = symToIso[symbol] ?? 'MYR';
    final fxAsync = ref.watch(stockFxRateProvider(localIso));
    final usdToLocal = fxAsync.valueOrNull ?? 4.48;

    // Count unique markets
    final markets = stocks.map((s) => s.exchangeDisplay).toSet();

    return Scaffold(
      backgroundColor: brand.background,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── App bar ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    _CircleBtn(
                      icon: CupertinoIcons.chevron_left,
                      onTap: () => Navigator.pop(context),
                      brand: brand,
                    ),
                    const Spacer(),
                    Text(
                      'Stocks',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: brand.ink,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const Spacer(),
                    _CircleBtn(
                      icon: CupertinoIcons.arrow_clockwise,
                      onTap: () {
                        for (final s in stocks) {
                          ref.invalidate(_stockQuoteProvider(s.symbol));
                        }
                        HapticFeedback.selectionClick();
                        AppToast.show(context, stocks.isEmpty
                            ? 'No holdings to refresh'
                            : '${stocks.length} price${stocks.length == 1 ? '' : 's'} refreshed');
                      },
                      brand: brand,
                    ),
                    const SizedBox(width: 8),
                    _CircleBtn(
                      icon: CupertinoIcons.search,
                      onTap: () => _showAddStock(context),
                      brand: brand,
                    ),
                  ],
                ),
              ),
            ),

            // ── Live status + totals ────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
                child: _PortfolioHeader(
                  stocks: stocks,
                  usdToLocal: usdToLocal,
                  localSymbol: symbol,
                  marketsCount: markets.length,
                  isDark: isDark,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),

            // ── Buy / Sell buttons ──────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: _PillBtn(
                        label: '+ Buy stock',
                        filled: true,
                        onTap: () => _showAddStock(context),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _PillBtn(
                        label: 'Sell',
                        filled: false,
                        onTap: () => _showSellStock(context, stocks),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ── Filter chips + sort ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    _FilterChip(label: 'All', selected: _filter == 'All', onTap: () => setState(() => _filter = 'All')),
                    const SizedBox(width: 8),
                    _FilterChip(label: 'KLSE', selected: _filter == 'KLSE', onTap: () => setState(() => _filter = 'KLSE')),
                    const SizedBox(width: 8),
                    _FilterChip(label: 'USD', selected: _filter == 'USD', onTap: () => setState(() => _filter = 'USD')),
                    const Spacer(),
                    GestureDetector(
                      onTap: () => _showSortSheet(context),
                      child: Row(
                        children: [
                          Text(
                            '$_sort ',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: _blue,
                            ),
                          ),
                          const Icon(CupertinoIcons.chevron_down, size: 11, color: _blue),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: () => _showGroupSheet(context),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: brand.surface,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          CupertinoIcons.line_horizontal_3_decrease,
                          size: 15,
                          color: brand.inkSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 12)),

            // ── Stock list ──────────────────────────────────────────────────
            if (filtered.isEmpty)
              SliverFillRemaining(
                child: _EmptyPortfolio(onAdd: () => _showAddStock(context)),
              )
            else if (_groupBy != 'None')
              _GroupedStockList(
                stocks: filtered,
                groupBy: _groupBy,
                usdToLocal: usdToLocal,
                localSymbol: symbol,
                isDark: isDark,
                onTap: (s) => _openDetail(context, s),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
                sliver: SliverToBoxAdapter(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      color: brand.surface,
                      child: Column(
                        children: [
                          for (var i = 0; i < filtered.length; i++) ...[
                            if (i > 0)
                              Divider(height: 1, color: brand.divider, indent: 70, endIndent: 16),
                            TweenAnimationBuilder<double>(
                              key: ValueKey(filtered[i].id),
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 250 + i * 60),
                              curve: Curves.easeOut,
                              builder: (ctx, v, child) => Opacity(
                                opacity: v,
                                child: Transform.translate(
                                  offset: Offset(0, 12 * (1 - v)),
                                  child: child,
                                ),
                              ),
                              child: Builder(builder: (ctx) {
                                final s = filtered[i];
                                return _Slidable(
                                  onBuy: () => s.watchOnly
                                      ? _showBuyFromWatchlist(context, s)
                                      : _showBuySheetForStockFromHolding(context, s),
                                  onSell: s.watchOnly ? null : () => _openSellSheet(context, s),
                                  child: _StockTileWithQuote(
                                    stock: s,
                                    usdToLocal: usdToLocal,
                                    localSymbol: symbol,
                                    isDark: isDark,
                                    onTap: () => _openDetail(context, s),
                                    onLongPress: () => _showStockActions(context, s),
                                    onBuyWatchlist: s.watchOnly
                                        ? () => _showBuyFromWatchlist(context, s)
                                        : null,
                                  ),
                                );
                              }),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openDetail(BuildContext context, StockInvestment stock) {
    Navigator.push(
      context,
      CupertinoPageRoute(builder: (_) => StockDetailScreen(stock: stock)),
    );
  }

  void _openEditSheet(BuildContext context, StockInvestment stock) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => _EditStockSheet(
        stock: stock,
        onSave: (updated) async {
          final user = ref.read(authStateProvider).valueOrNull;
          if (user == null) return;
          await ref.read(stockInvestmentRepositoryProvider).update(user.uid, updated);
          if (mounted) AppToast.show(context, '${updated.symbol} updated');
        },
      ),
    );
  }

  void _showAddStock(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => _FindTickerSheet(
        onRecordTransaction: (result, quote) {
          Navigator.pop(context);
          _showBuySheet(context, result, quote);
        },
        onWatchOnly: (result, quote) async {
          Navigator.pop(context);
          final user = ref.read(authStateProvider).valueOrNull;
          if (user == null) return;
          final now = DateTime.now();
          final investment = StockInvestment(
            id: '',
            symbol: result.symbol,
            name: quote?.name ?? result.name,
            quantity: 0,
            buyPrice: quote?.price ?? 0,
            exchange: result.exchange,
            currency: result.currency,
            watchOnly: true,
            createdAt: now,
            updatedAt: now,
          );
          try {
            await ref.read(stockInvestmentRepositoryProvider).add(user.uid, investment);
            if (mounted) AppToast.show(context, '${result.symbol} added to watchlist');
          } catch (_) {
            if (mounted) AppToast.show(context, 'Failed to add', type: AppToastType.error);
          }
        },
      ),
    );
  }

  void _showBuySheet(BuildContext context, StockSearchResult result, StockQuote? quote) {
    _showBuySheetForStock(context, result, quote);
  }

  void _showBuySheetForStock(BuildContext context, StockSearchResult result, StockQuote? quote, {String? existingId}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => _BuyStockSheet(
        result: result,
        quote: quote,
        onSave: (investment) async {
          final user = ref.read(authStateProvider).valueOrNull;
          if (user == null) return;
          try {
            final allStocks = ref.read(stockInvestmentsProvider).valueOrNull ?? [];
            final existing = _findExisting(allStocks, investment.symbol, id: existingId);
            final newTx = {
              'date': DateTime.now().toIso8601String(),
              'qty': investment.quantity,
              'price': investment.buyPrice,
              'currency': investment.currency ?? 'USD',
              'type': 'buy',
            };
            if (existing != null) {
              final merged = existing.copyWith(
                quantity: existing.watchOnly ? investment.quantity : existing.quantity + investment.quantity,
                buyPrice: investment.buyPrice,
                currency: investment.currency,
                watchOnly: false,
                notes: investment.notes ?? existing.notes,
                updatedAt: DateTime.now(),
                transactions: [...existing.transactions, newTx],
              );
              await ref.read(stockInvestmentRepositoryProvider).update(user.uid, merged);
              if (mounted) AppToast.show(context, '${investment.symbol} updated');
            } else {
              final withTx = StockInvestment(
                id: investment.id,
                symbol: investment.symbol,
                name: investment.name,
                quantity: investment.quantity,
                buyPrice: investment.buyPrice,
                notes: investment.notes,
                exchange: investment.exchange,
                currency: investment.currency,
                watchOnly: investment.watchOnly,
                createdAt: investment.createdAt,
                updatedAt: investment.updatedAt,
                transactions: [newTx],
              );
              await ref.read(stockInvestmentRepositoryProvider).add(user.uid, withTx);
              if (mounted) AppToast.show(context, '${investment.symbol} purchase recorded');
            }
          } catch (_) {
            if (mounted) AppToast.show(context, 'Failed to save', type: AppToastType.error);
          }
        },
      ),
    );
  }

  StockInvestment? _findExisting(List<StockInvestment> all, String symbol, {String? id}) {
    if (id != null) {
      for (final s in all) { if (s.id == id) return s; }
      return null;
    }
    for (final s in all) {
      if (s.symbol.toUpperCase() == symbol.toUpperCase()) return s;
    }
    return null;
  }

  void _showSellStock(BuildContext context, List<StockInvestment> stocks) {
    final holdings = stocks.where((s) => !s.watchOnly && s.quantity > 0).toList();
    if (holdings.isEmpty) {
      AppToast.show(context, 'No holdings to sell');
      return;
    }
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Select stock to sell'),
        actions: holdings.map((s) => CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            _openSellSheet(context, s);
          },
          child: Text('${s.symbol} · ${_fmtQty(s.quantity)} sh'),
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _openSellSheet(BuildContext context, StockInvestment stock) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      builder: (_) => _SellStockSheet(
        stock: stock,
        quote: ref.read(_stockQuoteProvider(stock.symbol)).valueOrNull,
        onSell: (qty, price) async {
          final user = ref.read(authStateProvider).valueOrNull;
          if (user == null) return;
          final sellTx = {
            'date': DateTime.now().toIso8601String(),
            'qty': qty,
            'price': price,
            'currency': stock.currency ?? 'USD',
            'type': 'sell',
          };
          try {
            if (qty >= stock.quantity) {
              await ref.read(stockInvestmentRepositoryProvider).delete(user.uid, stock.id);
              if (mounted) AppToast.show(context, '${stock.symbol} position closed');
            } else {
              final updated = stock.copyWith(
                quantity: stock.quantity - qty,
                updatedAt: DateTime.now(),
                transactions: [...stock.transactions, sellTx],
              );
              await ref.read(stockInvestmentRepositoryProvider).update(user.uid, updated);
              if (mounted) AppToast.show(context, 'Sold ${_fmtQty(qty)} sh of ${stock.symbol}');
            }
          } catch (_) {
            if (mounted) AppToast.show(context, 'Failed to sell', type: AppToastType.error);
          }
        },
      ),
    );
  }

  void _showBuyFromWatchlist(BuildContext context, StockInvestment watchlistStock) {
    final result = StockSearchResult(
      symbol: watchlistStock.symbol,
      name: watchlistStock.name ?? watchlistStock.symbol,
      exchange: watchlistStock.exchange ?? '',
      currency: watchlistStock.currency ?? 'USD',
    );
    _showBuySheetForStock(context, result, null, existingId: watchlistStock.id);
  }

  void _showBuySheetForStockFromHolding(BuildContext context, StockInvestment stock) {
    final result = StockSearchResult(
      symbol: stock.symbol,
      name: stock.name ?? stock.symbol,
      exchange: stock.exchange ?? '',
      currency: stock.currency ?? 'USD',
    );
    _showBuySheetForStock(context, result, null, existingId: stock.id);
  }

  String _fmtQty(double qty) {
    return qty == qty.floorToDouble()
        ? NumberFormat('#,##0').format(qty)
        : qty.toStringAsFixed(2);
  }

  void _showStockActions(BuildContext context, StockInvestment stock) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(stock.symbol),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _openDetail(context, stock);
            },
            child: const Text('View Details'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _openEditSheet(context, stock);
            },
            child: const Text('Edit'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () async {
              Navigator.pop(ctx);
              final user = ref.read(authStateProvider).valueOrNull;
              if (user == null) return;
              try {
                await ref.read(stockInvestmentRepositoryProvider).delete(user.uid, stock.id);
                if (mounted) AppToast.show(context, '${stock.symbol} removed');
              } catch (_) {
                if (mounted) AppToast.show(context, 'Failed to remove', type: AppToastType.error);
              }
            },
            child: const Text('Remove'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Sort by'),
        actions: ['Value', 'Gain%', 'Name'].map((s) => CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            setState(() => _sort = s);
          },
          child: Text(s, style: TextStyle(fontWeight: _sort == s ? FontWeight.w700 : FontWeight.w400)),
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _showGroupSheet(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Group by'),
        actions: ['None', 'Sector', 'Market', 'Currency'].map((g) => CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            setState(() => _groupBy = g);
          },
          child: Text(g, style: TextStyle(fontWeight: _groupBy == g ? FontWeight.w700 : FontWeight.w400)),
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }
}

// ── Portfolio Header ───────────────────────────────────────────────────────────

class _PortfolioHeader extends ConsumerWidget {
  final List<StockInvestment> stocks;
  final double usdToLocal;
  final String localSymbol;
  final int marketsCount;
  final bool isDark;

  const _PortfolioHeader({
    required this.stocks,
    required this.usdToLocal,
    required this.localSymbol,
    required this.marketsCount,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brand = context.brand;

    double totalCost = 0;
    double liveTotal = 0;
    double todayGain = 0;
    bool anyLoaded = false;

    for (final s in stocks) {
      if (!s.watchOnly) {
        final fx = s.currency == 'MYR' ? 1.0 : usdToLocal;
        final cost = s.currency == 'MYR' ? s.totalCost : s.totalCost * usdToLocal;
        totalCost += cost;

        final q = ref.watch(_stockQuoteProvider(s.symbol)).valueOrNull;
        if (q != null) {
          anyLoaded = true;
          liveTotal += q.price * s.quantity * fx;
          todayGain += q.change * s.quantity * fx;
        } else {
          liveTotal += cost;
        }
      }
    }
    if (!anyLoaded) liveTotal = totalCost;

    final allTimeGain = liveTotal - totalCost;
    final allTimeGainPct = totalCost > 0 ? (allTimeGain / totalCost) * 100 : 0.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // LIVE badge + holdings count
        Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(color: _green, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              'LIVE · ${stocks.length} HOLDINGS · $marketsCount MARKET${marketsCount == 1 ? '' : 'S'}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: brand.inkSoft,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Total live value
        RichText(
          text: TextSpan(
            children: [
              TextSpan(
                text: '$localSymbol ',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                  letterSpacing: -0.5,
                ),
              ),
              TextSpan(
                text: NumberFormat('#,##0.00').format(liveTotal),
                style: TextStyle(
                  fontSize: 42,
                  fontWeight: FontWeight.w800,
                  color: brand.ink,
                  letterSpacing: -1.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        // Today gain + all-time %
        if (anyLoaded)
          Row(
            children: [
              Text(
                '${todayGain >= 0 ? '+' : ''}$localSymbol ${NumberFormat('#,##0.00').format(todayGain)} today',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: todayGain >= 0 ? _green : _red,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${allTimeGain >= 0 ? '+' : ''}${allTimeGainPct.toStringAsFixed(2)}% all-time',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: allTimeGain >= 0 ? _green : _red,
                ),
              ),
            ],
          )
        else
          Text(
            'Est. total cost basis',
            style: TextStyle(fontSize: 13, color: brand.inkSoft),
          ),
      ],
    );
  }
}

// ── Grouped stock list ─────────────────────────────────────────────────────────

class _GroupedStockList extends ConsumerWidget {
  final List<StockInvestment> stocks;
  final String groupBy;
  final double usdToLocal;
  final String localSymbol;
  final bool isDark;
  final void Function(StockInvestment) onTap;

  const _GroupedStockList({
    required this.stocks,
    required this.groupBy,
    required this.usdToLocal,
    required this.localSymbol,
    required this.isDark,
    required this.onTap,
  });

  String _groupKey(StockInvestment s) {
    switch (groupBy) {
      case 'Market':
        return s.exchangeDisplay;
      case 'Currency':
        return s.currency ?? 'USD';
      case 'Sector':
      default:
        // Simple heuristic sector
        if (s.currency == 'MYR') return 'Banking';
        return 'Technology';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final grouped = <String, List<StockInvestment>>{};
    for (final s in stocks) {
      final key = _groupKey(s);
      grouped.putIfAbsent(key, () => []).add(s);
    }

    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 120),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (_, i) {
            // Build flat list of group headers + items
            final entries = grouped.entries.toList();
            int idx = 0;
            for (final entry in entries) {
              if (i == idx) {
                // Group header
                final groupStocks = entry.value;
                final pct = stocks.isEmpty ? 0 : (groupStocks.length / stocks.length * 100).round();
                return _GroupHeader(
                  name: entry.key.toUpperCase(),
                  count: groupStocks.length,
                  percent: pct,
                );
              }
              idx++;
              final groupStocks = entry.value;
              if (i < idx + groupStocks.length) {
                final stock = groupStocks[i - idx];
                final quoteAsync = ref.watch(_stockQuoteProvider(stock.symbol));
                final quote = quoteAsync.valueOrNull;
                final currentUsd = quote?.price;
                final localPrice = currentUsd != null
                    ? (stock.currency == 'MYR' ? currentUsd : currentUsd * usdToLocal)
                    : null;
                return _StockListTile(
                  stock: stock,
                  quote: quote,
                  currentLocalPrice: localPrice,
                  localSymbol: localSymbol,
                  isDark: isDark,
                  onTap: () => onTap(stock),
                  onLongPress: null,
                );
              }
              idx += groupStocks.length;
            }
            return const SizedBox.shrink();
          },
          childCount: grouped.entries.fold<int>(0, (sum, e) => sum + 1 + e.value.length),
        ),
      ),
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final String name;
  final int count;
  final int percent;

  const _GroupHeader({
    required this.name,
    required this.count,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '$name · $count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: brand.inkSoft,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              Text(
                '$percent%',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: percent / 100,
              backgroundColor: brand.divider,
              valueColor: AlwaysStoppedAnimation(brand.ink),
              minHeight: 3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stock tile with quote fetching ─────────────────────────────────────────────

class _StockTileWithQuote extends ConsumerWidget {
  final StockInvestment stock;
  final double usdToLocal;
  final String localSymbol;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onBuyWatchlist;

  const _StockTileWithQuote({
    required this.stock,
    required this.usdToLocal,
    required this.localSymbol,
    required this.isDark,
    required this.onTap,
    required this.onLongPress,
    this.onBuyWatchlist,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final quote = ref.watch(_stockQuoteProvider(stock.symbol)).valueOrNull;
    final currentUsd = quote?.price;
    final localPrice = currentUsd != null
        ? (stock.currency == 'MYR' ? currentUsd : currentUsd * usdToLocal)
        : null;

    return _StockListTile(
      stock: stock,
      quote: quote,
      currentLocalPrice: localPrice,
      localSymbol: localSymbol,
      isDark: isDark,
      onTap: onTap,
      onLongPress: onLongPress,
      onBuyWatchlist: onBuyWatchlist,
    );
  }
}

// ── Stock list tile ────────────────────────────────────────────────────────────

class _StockListTile extends StatelessWidget {
  final StockInvestment stock;
  final StockQuote? quote;
  final double? currentLocalPrice;
  final String localSymbol;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onBuyWatchlist;

  const _StockListTile({
    required this.stock,
    required this.quote,
    required this.currentLocalPrice,
    required this.localSymbol,
    required this.isDark,
    required this.onTap,
    required this.onLongPress,
    this.onBuyWatchlist,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final gainPct = quote != null
        ? stock.gainLossPercent(quote!.price)
        : null;
    final isUp = gainPct == null || gainPct >= 0;
    final trendColor = isUp ? _green : _red;

    // Estimated local value
    final localValue = currentLocalPrice != null
        ? currentLocalPrice! * stock.quantity
        : null;

    // Initials for avatar
    final initials = _initials(stock.symbol);

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      onLongPress: onLongPress != null ? () {
        HapticFeedback.mediumImpact();
        onLongPress!();
      } : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            // Avatar circle
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE8E8EA),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initials,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: brand.ink,
                  letterSpacing: -0.5,
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Ticker + exchange + shares
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        stock.symbol,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: brand.ink,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        stock.exchangeDisplay,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: brand.inkSoft,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    stock.watchOnly
                        ? 'Watchlist · ${stock.name ?? stock.symbol}'
                        : '${_fmtQty(stock.quantity)} sh · ${_fmtPrice(stock.buyPrice, stock.currency)} avg',
                    style: TextStyle(fontSize: 12, color: stock.watchOnly ? _blue.withValues(alpha: 0.7) : brand.inkSoft),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // Mini sparkline
            if (quote != null && quote!.chartPoints.isNotEmpty) ...[
              SizedBox(
                width: 60,
                height: 32,
                child: _MiniSparkline(
                  points: quote!.chartPoints,
                  color: trendColor,
                ),
              ),
              const SizedBox(width: 12),
            ],

            // Value + gain% (or BUY button for watchOnly)
            if (stock.watchOnly && onBuyWatchlist != null) ...[
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (currentLocalPrice != null)
                    Text(
                      '$localSymbol ${NumberFormat('#,##0.00').format(currentLocalPrice!)}',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: brand.ink, letterSpacing: -0.2),
                    ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onBuyWatchlist!();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: _blue,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text('BUY', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3)),
                    ),
                  ),
                ],
              ),
            ] else
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    localValue != null
                        ? '$localSymbol ${NumberFormat('#,##0').format(localValue)}'
                        : '–',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: brand.ink,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    gainPct != null
                        ? '${gainPct >= 0 ? '+' : ''}${gainPct.toStringAsFixed(2)}%'
                        : '–',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: trendColor,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _initials(String symbol) {
    if (symbol.length >= 2) return symbol.substring(0, 2);
    return symbol;
  }

  String _fmtQty(double qty) {
    return qty == qty.floorToDouble()
        ? NumberFormat('#,##0').format(qty)
        : qty.toStringAsFixed(2);
  }

  String _fmtPrice(double price, String? currency) {
    final sym = currency == 'MYR' ? 'RM' : '\$';
    return '$sym${price.toStringAsFixed(2)}';
  }
}

// ── Mini sparkline ─────────────────────────────────────────────────────────────

class _MiniSparkline extends StatelessWidget {
  final List<StockPoint> points;
  final Color color;

  const _MiniSparkline({required this.points, required this.color});

  @override
  Widget build(BuildContext context) {
    final spots = points.asMap().entries
        .map((e) => FlSpot(e.key.toDouble(), e.value.close))
        .toList();
    final minY = points.map((p) => p.close).reduce((a, b) => a < b ? a : b);
    final maxY = points.map((p) => p.close).reduce((a, b) => a > b ? a : b);
    final pad = (maxY - minY) * 0.1;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        minY: minY - pad,
        maxY: maxY + pad,
        lineTouchData: const LineTouchData(enabled: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            curveSmoothness: 0.4,
            color: color,
            barWidth: 1.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.15), color.withValues(alpha: 0.0)],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
      duration: Duration.zero,
    );
  }
}

// ── Empty portfolio ────────────────────────────────────────────────────────────

class _EmptyPortfolio extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyPortfolio({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('📈', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'No stocks yet',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                color: brand.ink,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Search for a ticker to start tracking your portfolio.',
              style: TextStyle(fontSize: 14, color: brand.inkSoft, height: 1.4),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: onAdd,
              child: Container(
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 24),
                decoration: BoxDecoration(
                  color: _blue,
                  borderRadius: BorderRadius.circular(24),
                ),
                alignment: Alignment.center,
                child: const Text(
                  '+ Buy stock',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared pill button ─────────────────────────────────────────────────────────

class _PillBtn extends StatefulWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _PillBtn({required this.label, required this.filled, required this.onTap});

  @override
  State<_PillBtn> createState() => _PillBtnState();
}

class _PillBtnState extends State<_PillBtn> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween<double>(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            color: widget.filled ? _blue : Colors.transparent,
            borderRadius: BorderRadius.circular(23),
            border: widget.filled ? null : Border.all(color: _blue, width: 1.5),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
              color: widget.filled ? Colors.white : _blue,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Filter chip ────────────────────────────────────────────────────────────────

class _FilterChip extends StatefulWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  State<_FilterChip> createState() => _FilterChipState();
}

class _FilterChipState extends State<_FilterChip> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 80));
    _scale = Tween<double>(begin: 1.0, end: 0.95)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        HapticFeedback.selectionClick();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: widget.selected ? brand.ink : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: widget.selected ? null : Border.all(color: brand.divider, width: 1),
          ),
          alignment: Alignment.center,
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: widget.selected ? brand.background : brand.inkSoft,
            ),
          ),
        ),
      ),
    );
  }
}

// ── Swipe-action tile wrapper ─────────────────────────────────────────────────

class _Slidable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onBuy;
  final VoidCallback? onSell;

  const _Slidable({required this.child, this.onBuy, this.onSell});

  @override
  State<_Slidable> createState() => _SlidableState();
}

class _SlidableState extends State<_Slidable> with SingleTickerProviderStateMixin {
  double _offset = 0.0;
  late final AnimationController _ctrl;
  Animation<double>? _anim;

  static const double _maxW = 76.0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _ctrl.addListener(() {
      if (_anim != null) setState(() => _offset = _anim!.value);
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _snapTo(double target) {
    _anim = Tween<double>(begin: _offset, end: target).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic),
    );
    _ctrl
      ..reset()
      ..forward();
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _ctrl.stop();
    setState(() {
      final raw = _offset + d.delta.dx;
      // Only allow drag in directions that have an action
      if (raw < 0 && widget.onBuy == null) return;
      if (raw > 0 && widget.onSell == null) return;
      _offset = raw.clamp(-_maxW, _maxW);
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final vel = d.primaryVelocity ?? 0;
    if (_offset < -28 || vel < -400) {
      _snapTo(-_maxW);
    } else if (_offset > 28 || vel > 400) {
      _snapTo(_maxW);
    } else {
      _snapTo(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: Stack(
        children: [
          // Sell action (left side, revealed on right-swipe)
          if (widget.onSell != null)
            Positioned(
              left: 0, top: 0, bottom: 0,
              width: _offset > 0 ? _offset.clamp(0, _maxW) : 0,
              child: GestureDetector(
                onTap: () {
                  _snapTo(0);
                  widget.onSell!();
                },
                child: Container(
                  color: _red,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.minus_circle, size: 20, color: Colors.white),
                      SizedBox(height: 4),
                      Text('Sell', style: TextStyle(color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                    ],
                  ),
                ),
              ),
            ),
          // Buy action (right side, revealed on left-swipe)
          if (widget.onBuy != null)
            Positioned(
              right: 0, top: 0, bottom: 0,
              width: _offset < 0 ? (-_offset).clamp(0, _maxW) : 0,
              child: GestureDetector(
                onTap: () {
                  _snapTo(0);
                  widget.onBuy!();
                },
                child: Container(
                  color: _blue,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(CupertinoIcons.plus_circle, size: 20, color: Colors.white),
                      SizedBox(height: 4),
                      Text('Buy', style: TextStyle(color: Colors.white, fontSize: 11,
                          fontWeight: FontWeight.w700, letterSpacing: 0.2)),
                    ],
                  ),
                ),
              ),
            ),
          // Main tile
          Transform.translate(
            offset: Offset(_offset, 0),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onTap: _offset != 0 ? () => _snapTo(0) : null,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Circle icon button ─────────────────────────────────────────────────────────

class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final BrandColors brand;

  const _CircleBtn({required this.icon, required this.onTap, required this.brand});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(color: brand.surface, shape: BoxShape.circle),
        child: Icon(icon, size: 16, color: brand.ink),
      ),
    );
  }
}

// ── Find Ticker Sheet ──────────────────────────────────────────────────────────

class _FindTickerSheet extends ConsumerStatefulWidget {
  final void Function(StockSearchResult, StockQuote?) onRecordTransaction;
  final Future<void> Function(StockSearchResult, StockQuote?) onWatchOnly;

  const _FindTickerSheet({
    required this.onRecordTransaction,
    required this.onWatchOnly,
  });

  @override
  ConsumerState<_FindTickerSheet> createState() => _FindTickerSheetState();
}

class _FindTickerSheetState extends ConsumerState<_FindTickerSheet> {
  final _ctrl = TextEditingController();
  List<StockSearchResult> _results = [];
  StockSearchResult? _topMatch;
  StockQuote? _topQuote;
  bool _searching = false;
  bool _loadingQuote = false;

  static const _trending = [
    ('MAYBANK', 'Malayan Banking', 'KLSE · MYR'),
    ('PBBANK', 'Public Bank', 'KLSE · MYR'),
    ('TENAGA', 'Tenaga Nasional', 'KLSE · MYR'),
    ('CIMB', 'CIMB Group', 'KLSE · MYR'),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 1) {
      setState(() { _results = []; _topMatch = null; _topQuote = null; });
      return;
    }
    setState(() => _searching = true);
    final svc = ref.read(stockServiceProvider);
    final results = await svc.search(query);
    if (!mounted) return;

    final topResult = results.isEmpty ? null : results.first;
    StockQuote? topQuote;

    if (topResult != null) {
      setState(() { _loadingQuote = true; });
      topQuote = await svc.getQuote(topResult.symbol, range: '1M');
    }

    if (!mounted) return;
    setState(() {
      _results = results;
      _topMatch = topResult;
      _topQuote = topQuote;
      _searching = false;
      _loadingQuote = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final keyboardH = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      decoration: BoxDecoration(
        color: brand.background,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle + header — always stays at top
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(top: 10, bottom: 4),
              decoration: BoxDecoration(
                color: brand.divider,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Text('Cancel', style: TextStyle(fontSize: 16, color: _blue)),
                ),
                const Expanded(
                  child: Text('Find Ticker', textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                GestureDetector(
                  onTap: _topMatch != null
                      ? () => widget.onRecordTransaction(_topMatch!, _topQuote)
                      : null,
                  child: Text('Next',
                    style: TextStyle(
                      fontSize: 16,
                      color: _topMatch != null ? _blue : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(20, 16, 20, keyboardH + 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Search bar: full-width, rounded rectangle, with icon
                    Container(
                      decoration: BoxDecoration(
                        color: isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.search, size: 17, color: Colors.grey.shade500),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _ctrl,
                              autofocus: false,
                              textCapitalization: TextCapitalization.characters,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w400,
                                color: isDark ? Colors.white : const Color(0xFF1D1D1F),
                                letterSpacing: -0.3,
                              ),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Ticker or company name',
                                hintStyle: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w400,
                                  color: Colors.grey.shade500,
                                  letterSpacing: -0.3,
                                ),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                              ),
                              onChanged: _search,
                            ),
                          ),
                          if (_searching)
                            const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: _blue))
                          else if (_ctrl.text.isNotEmpty)
                            GestureDetector(
                              onTap: () { _ctrl.clear(); _search(''); },
                              child: Icon(CupertinoIcons.clear_circled_solid, size: 17, color: Colors.grey.shade400),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Top match card
                    if (_topMatch != null) ...[
                      _TopMatchCard(
                        result: _topMatch!,
                        quote: _topQuote,
                        loadingQuote: _loadingQuote,
                        isDark: isDark,
                        onRecordTransaction: () =>
                            widget.onRecordTransaction(_topMatch!, _topQuote),
                        onWatchOnly: () => widget.onWatchOnly(_topMatch!, _topQuote),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Other matches
                    if (_results.length > 1) ...[
                      Text(
                        'OTHER MATCHES',
                        style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500, letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: () {
                            final matches = _results.skip(1).take(5).toList();
                            final widgets = <Widget>[];
                            for (var i = 0; i < matches.length; i++) {
                              final r = matches[i];
                              if (i > 0) {
                                widgets.add(Divider(
                                  height: 1,
                                  indent: 62,
                                  endIndent: 14,
                                  color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFF2F2F7),
                                ));
                              }
                              widgets.add(GestureDetector(
                                onTap: () {
                                  setState(() {
                                    _topMatch = r;
                                    _topQuote = null;
                                    _loadingQuote = true;
                                  });
                                  ref.read(stockServiceProvider).getQuote(r.symbol, range: '1M').then((q) {
                                    if (mounted) setState(() { _topQuote = q; _loadingQuote = false; });
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                  child: Row(
                                    children: [
                                      StockAvatarBadge(symbol: r.symbol, size: 36),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(r.symbol,
                                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                                color: isDark ? Colors.white : Colors.black)),
                                            Text(r.name,
                                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                                              maxLines: 1, overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        '${r.exchange} · ${r.currency}',
                                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                      ),
                                    ],
                                  ),
                                ),
                              ));
                            }
                            return widgets;
                          }(),
                        ),
                      ),
                    ],

                    // Trending section
                    if (_results.isEmpty) ...[
                      Text(
                        'TRENDING ON KLSE',
                        style: TextStyle(
                          fontSize: 11, fontWeight: FontWeight.w600,
                          color: Colors.grey.shade500, letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Column(
                          children: _trending.map((t) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            child: Row(
                              children: [
                                StockAvatarBadge(symbol: t.$1, size: 36),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(t.$1,
                                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700,
                                          color: isDark ? Colors.white : Colors.black)),
                                      Text(t.$2,
                                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                    ],
                                  ),
                                ),
                                Text(t.$3,
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                              ],
                            ),
                          )).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
    );
  }
}

// ── Top match card ─────────────────────────────────────────────────────────────

class _TopMatchCard extends StatelessWidget {
  final StockSearchResult result;
  final StockQuote? quote;
  final bool loadingQuote;
  final bool isDark;
  final VoidCallback onRecordTransaction;
  final VoidCallback onWatchOnly;

  const _TopMatchCard({
    required this.result,
    required this.quote,
    required this.loadingQuote,
    required this.isDark,
    required this.onRecordTransaction,
    required this.onWatchOnly,
  });

  @override
  Widget build(BuildContext context) {
    final isUp = quote?.isUp ?? true;
    final trendColor = isUp ? _green : _red;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1C1C1E) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _blue, width: 1.5),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StockAvatarBadge(symbol: result.symbol, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(result.symbol,
                      style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      '${result.name} · ${result.exchange} · ${result.currency}',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (quote != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '\$${quote!.price.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 18, fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      '${isUp ? '+' : ''}${quote!.changePercent.toStringAsFixed(2)}% today',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: trendColor),
                    ),
                  ],
                )
              else if (loadingQuote)
                const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
                ),
            ],
          ),

          // Mini chart
          if (quote != null && quote!.chartPoints.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 80,
              child: _MiniSparkline(points: quote!.chartPoints, color: trendColor),
            ),
          ] else
            const SizedBox(height: 8),

          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onRecordTransaction,
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: _blue,
                      borderRadius: BorderRadius.circular(23),
                    ),
                    alignment: Alignment.center,
                    child: const Text(
                      '+ Record transaction',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: onWatchOnly,
                child: Container(
                  height: 46,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(23),
                    border: Border.all(color: _blue, width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    'Watch only',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _blue),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Buy Stock Sheet ────────────────────────────────────────────────────────────

class _BuyStockSheet extends ConsumerStatefulWidget {
  final StockSearchResult result;
  final StockQuote? quote;
  final Future<void> Function(StockInvestment) onSave;

  const _BuyStockSheet({
    required this.result,
    required this.quote,
    required this.onSave,
  });

  @override
  ConsumerState<_BuyStockSheet> createState() => _BuyStockSheetState();
}

class _BuyStockSheetState extends ConsumerState<_BuyStockSheet> {
  double _units = 5;
  late final TextEditingController _unitsCtrl;
  double? _overridePrice;
  DateTime _date = DateTime.now();
  bool _saving = false;
  Account? _selectedAccount;
  late String _selectedCurrency;
  final _notesCtrl = TextEditingController();

  double get _unitPrice => _overridePrice ?? widget.quote?.price ?? 0;

  String _fmtUnits(double v) =>
      v == v.floorToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);

  @override
  void initState() {
    super.initState();
    _unitsCtrl = TextEditingController(text: '5');
    _selectedCurrency = widget.result.currency.isNotEmpty ? widget.result.currency : 'USD';
  }

  @override
  void dispose() {
    _unitsCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_units <= 0) return;
    setState(() => _saving = true);
    final now = DateTime.now();
    final investment = StockInvestment(
      id: '',
      symbol: widget.result.symbol,
      name: widget.quote?.name ?? widget.result.name,
      quantity: _units,
      buyPrice: _unitPrice,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      exchange: widget.result.exchange,
      currency: _selectedCurrency,
      watchOnly: false,
      createdAt: now,
      updatedAt: now,
    );
    await widget.onSave(investment);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final symbol = ref.watch(currencySymbolProvider).valueOrNull ?? 'RM';
    const symToIso = {'RM': 'MYR', '\$': 'USD', 'S\$': 'SGD', '€': 'EUR'};
    final localIso = symToIso[symbol] ?? 'MYR';
    final fxAsync = ref.watch(stockFxRateProvider(localIso));
    final usdToLocal = fxAsync.valueOrNull ?? 4.48;
    final accounts = ref.watch(accountsProvider).valueOrNull ?? <Account>[];
    final displayAccount = _selectedAccount ?? (accounts.isNotEmpty ? accounts.first : null);

    final isUsd = _selectedCurrency == 'USD';
    final unitLocalValue = _unitPrice * (isUsd ? usdToLocal : 1.0) * _units;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.88,
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                decoration: BoxDecoration(color: brand.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(fontSize: 16, color: _blue)),
                  ),
                  Expanded(
                    child: Text(
                      'Buy ${widget.quote?.name ?? widget.result.symbol}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Text('Save', style: TextStyle(fontSize: 16, color: _blue, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),

                    // Selected stock row
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          StockAvatarBadge(symbol: widget.result.symbol, size: 36),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(widget.quote?.name ?? widget.result.symbol,
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: brand.ink)),
                                Text(
                                  '${widget.result.exchange} · ${widget.result.currency}${widget.quote != null ? ' · live \$${widget.quote!.price.toStringAsFixed(2)}' : ''}',
                                  style: TextStyle(fontSize: 12, color: brand.inkSoft),
                                ),
                              ],
                            ),
                          ),
                          Icon(CupertinoIcons.chevron_right, size: 14, color: brand.inkSoft),
                        ],
                      ),
                    ),

                    const SizedBox(height: 28),

                    // Units label
                    Text('UNITS',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600,
                        color: brand.inkSoft, letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Units stepper + custom input
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (_units > 0) {
                              final v = _units - 1;
                              setState(() { _units = v; _unitsCtrl.text = _fmtUnits(v); });
                              HapticFeedback.selectionClick();
                            }
                          },
                          child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: brand.surface, shape: BoxShape.circle),
                            child: Icon(CupertinoIcons.minus, size: 16, color: brand.ink),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 120,
                          child: TextField(
                            controller: _unitsCtrl,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            style: TextStyle(
                              fontSize: 52, fontWeight: FontWeight.w800,
                              color: brand.ink, letterSpacing: -2,
                            ),
                            decoration: InputDecoration(
                              border: InputBorder.none,
                              isDense: true,
                              contentPadding: EdgeInsets.zero,
                              hintText: '0',
                              hintStyle: TextStyle(
                                fontSize: 52, fontWeight: FontWeight.w800,
                                color: brand.divider, letterSpacing: -2,
                              ),
                            ),
                            onChanged: (v) {
                              final d = double.tryParse(v);
                              if (d != null && d >= 0) setState(() => _units = d);
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('sh',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w500, color: brand.inkSoft)),
                        ),
                        const SizedBox(width: 16),
                        GestureDetector(
                          onTap: () {
                            final v = _units + 1;
                            setState(() { _units = v; _unitsCtrl.text = _fmtUnits(v); });
                            HapticFeedback.selectionClick();
                          },
                          child: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(color: brand.surface, shape: BoxShape.circle),
                            child: Icon(CupertinoIcons.plus, size: 16, color: brand.ink),
                          ),
                        ),
                      ],
                    ),

                    // ≈ local value
                    Text(
                      '≈ $symbol ${NumberFormat('#,##0.00').format(unitLocalValue)}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: brand.inkSoft),
                    ),

                    const SizedBox(height: 20),

                    // Quick select chips
                    Row(
                      children: [1, 5, 10, 25].map((qty) {
                        final sel = qty.toDouble() == _units;
                        return Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() { _units = qty.toDouble(); _unitsCtrl.text = qty.toString(); });
                            },
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              height: 44,
                              decoration: BoxDecoration(
                                color: sel ? brand.ink : brand.surface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$qty',
                                style: TextStyle(
                                  fontSize: 16, fontWeight: FontWeight.w600,
                                  color: sel ? brand.background : brand.ink,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 20),

                    // Detail rows
                    Container(
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        children: [
                          _DetailRow(
                            label: 'Unit price',
                            value: '${_selectedCurrency == 'MYR' ? 'RM' : _selectedCurrency == 'USD' ? '\$' : _selectedCurrency} ${_unitPrice.toStringAsFixed(2)}',
                            subtitle: 'Tap to override',
                            onTap: () => _overrideUnitPrice(context, brand),
                          ),
                          Divider(height: 1, color: brand.divider, indent: 14, endIndent: 14),
                          _DetailRow(
                            label: 'Account',
                            value: displayAccount != null
                                ? '${displayAccount.name} · ${displayAccount.currencyCode ?? 'USD'}'
                                : 'Default',
                            subtitle: _selectedAccount == null ? 'Default' : null,
                            onTap: accounts.isNotEmpty
                                ? () => _pickAccount(context, accounts, displayAccount)
                                : null,
                          ),
                          Divider(height: 1, color: brand.divider, indent: 14, endIndent: 14),
                          _DetailRow(
                            label: 'Currency',
                            value: _selectedCurrency,
                            onTap: () => _pickCurrency(context),
                          ),
                          Divider(height: 1, color: brand.divider, indent: 14, endIndent: 14),
                          _DetailRow(
                            label: 'Date',
                            value: DateFormat('MMM d, y').format(_date),
                            subtitle: _date.difference(DateTime.now()).inDays == 0 ? 'Today' : null,
                            onTap: () => _pickDate(context),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Notes
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: brand.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.doc_text, size: 16, color: brand.inkSoft),
                          const SizedBox(width: 10),
                          Expanded(
                            child: TextField(
                              controller: _notesCtrl,
                              style: TextStyle(fontSize: 15, color: brand.ink),
                              decoration: InputDecoration(
                                border: InputBorder.none,
                                hintText: 'Notes (optional)',
                                hintStyle: TextStyle(color: brand.inkSoft),
                                isDense: true,
                                contentPadding: EdgeInsets.zero,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Record purchase button
                    GestureDetector(
                      onTap: _saving ? null : _save,
                      child: Container(
                        height: 54,
                        decoration: BoxDecoration(
                          color: _blue,
                          borderRadius: BorderRadius.circular(27),
                        ),
                        alignment: Alignment.center,
                        child: _saving
                            ? const SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(CupertinoIcons.checkmark, size: 16, color: Colors.white),
                                  SizedBox(width: 8),
                                  Text('Record purchase',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                                ],
                              ),
                      ),
                    ),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _overrideUnitPrice(BuildContext context, BrandColors brand) {
    final ctrl = TextEditingController(text: _unitPrice.toStringAsFixed(2));
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: brand.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 20,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Override unit price',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(prefixText: '${_selectedCurrency == 'MYR' ? 'RM' : '\$'}  ', hintText: '0.00'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(ctrl.text);
                if (v != null) setState(() => _overridePrice = v);
                Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(backgroundColor: _blue),
              child: const Text('Set price'),
            ),
          ],
        ),
      ),
    );
  }

  void _pickAccount(BuildContext context, List<Account> accounts, Account? current) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Select account'),
        actions: accounts.map((a) => CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            setState(() => _selectedAccount = a);
          },
          child: Text(
            '${a.name} · ${a.currencyCode ?? 'USD'}',
            style: TextStyle(
              fontWeight: a.id == current?.id ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  void _pickCurrency(BuildContext context) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Select currency'),
        actions: ['MYR', 'USD', 'SGD', 'EUR', 'GBP'].map((c) => CupertinoActionSheetAction(
          onPressed: () {
            Navigator.pop(ctx);
            setState(() { _selectedCurrency = c; _overridePrice = null; });
          },
          child: Text(c, style: TextStyle(fontWeight: c == _selectedCurrency ? FontWeight.w700 : FontWeight.w400)),
        )).toList(),
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _date = picked);
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final VoidCallback? onTap;

  const _DetailRow({required this.label, required this.value, this.subtitle, this.onTap});

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return GestureDetector(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(
          children: [
            Text(label, style: TextStyle(fontSize: 15, color: brand.ink)),
            const Spacer(),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: brand.ink)),
                if (subtitle != null)
                  Text(subtitle!,
                    style: TextStyle(fontSize: 11, color: brand.inkSoft)),
              ],
            ),
            if (onTap != null) ...[
              const SizedBox(width: 6),
              Icon(CupertinoIcons.chevron_right, size: 13, color: brand.inkSoft),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Avatar badge ───────────────────────────────────────────────────────────────

class StockAvatarBadge extends StatelessWidget {
  final String symbol;
  final double size;

  const StockAvatarBadge({required this.symbol, required this.size});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final initials = symbol.length >= 2 ? symbol.substring(0, 2) : symbol;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF3A3A3C) : const Color(0xFFE8E8EA),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.3,
          fontWeight: FontWeight.w700,
          color: isDark ? Colors.white : Colors.black,
          letterSpacing: -0.5,
        ),
      ),
    );
  }
}

// ── Edit stock sheet ──────────────────────────────────────────────────────────

class _EditStockSheet extends ConsumerStatefulWidget {
  final StockInvestment stock;
  final Future<void> Function(StockInvestment) onSave;

  const _EditStockSheet({required this.stock, required this.onSave});

  @override
  ConsumerState<_EditStockSheet> createState() => _EditStockSheetState();
}

class _EditStockSheetState extends ConsumerState<_EditStockSheet> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _notesCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _qtyCtrl = TextEditingController(
        text: widget.stock.quantity == widget.stock.quantity.truncateToDouble()
            ? widget.stock.quantity.toInt().toString()
            : widget.stock.quantity.toStringAsFixed(4));
    _priceCtrl = TextEditingController(
        text: widget.stock.buyPrice.toStringAsFixed(2));
    _notesCtrl = TextEditingController(text: widget.stock.notes ?? '');
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = double.tryParse(_qtyCtrl.text.trim());
    final price = double.tryParse(_priceCtrl.text.trim());
    if (qty == null || qty < 0 || price == null || price < 0) return;
    setState(() => _saving = true);
    final updated = widget.stock.copyWith(
      quantity: qty,
      buyPrice: price,
      notes: _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
      updatedAt: DateTime.now(),
    );
    await widget.onSave(updated);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                decoration: BoxDecoration(
                  color: brand.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text('Cancel',
                        style: TextStyle(fontSize: 16, color: _blue)),
                  ),
                  Expanded(
                    child: Text(
                      'Edit ${widget.stock.symbol}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Text('Save',
                        style: TextStyle(
                            fontSize: 16,
                            color: _blue,
                            fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _EditRow(
                          label: 'Units',
                          controller: _qtyCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          hint: '0',
                        ),
                        Divider(height: 1, color: brand.divider,
                            indent: 14, endIndent: 14),
                        _EditRow(
                          label: 'Buy price',
                          controller: _priceCtrl,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          hint: '0.00',
                          prefix: widget.stock.currency == 'MYR' ? 'RM ' : '\$ ',
                        ),
                        Divider(height: 1, color: brand.divider,
                            indent: 14, endIndent: 14),
                        _EditRow(
                          label: 'Notes',
                          controller: _notesCtrl,
                          hint: 'Optional',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        color: _blue,
                        borderRadius: BorderRadius.circular(27),
                      ),
                      alignment: Alignment.center,
                      child: _saving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Save changes',
                              style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType keyboardType;
  final String hint;
  final String? prefix;

  const _EditRow({
    required this.label,
    required this.controller,
    this.keyboardType = TextInputType.text,
    required this.hint,
    this.prefix,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: TextStyle(fontSize: 15, color: brand.inkSoft)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 15, color: brand.ink),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(color: brand.inkSoft),
                prefixText: prefix,
                prefixStyle: TextStyle(fontSize: 15, color: brand.inkSoft),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Sell stock sheet ──────────────────────────────────────────────────────────

class _SellStockSheet extends ConsumerStatefulWidget {
  final StockInvestment stock;
  final StockQuote? quote;
  final Future<void> Function(double qty, double price) onSell;

  const _SellStockSheet({
    required this.stock,
    required this.quote,
    required this.onSell,
  });

  @override
  ConsumerState<_SellStockSheet> createState() => _SellStockSheetState();
}

class _SellStockSheetState extends ConsumerState<_SellStockSheet> {
  late final TextEditingController _qtyCtrl;
  late final TextEditingController _priceCtrl;
  bool _saving = false;

  double get _sellQty => double.tryParse(_qtyCtrl.text.trim()) ?? 0;
  double get _sellPrice => double.tryParse(_priceCtrl.text.trim()) ?? 0;

  @override
  void initState() {
    super.initState();
    final qtyFmt = widget.stock.quantity == widget.stock.quantity.floorToDouble()
        ? widget.stock.quantity.toInt().toString()
        : widget.stock.quantity.toStringAsFixed(2);
    _qtyCtrl = TextEditingController(text: qtyFmt);
    final price = widget.quote?.price ?? widget.stock.buyPrice;
    _priceCtrl = TextEditingController(text: price.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final qty = _sellQty;
    final price = _sellPrice;
    if (qty <= 0 || price < 0) return;
    setState(() => _saving = true);
    await widget.onSell(qty, price);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    final qty = _sellQty;
    final price = _sellPrice;
    final isUsd = widget.stock.currency == 'USD' || widget.stock.currency == null;
    final currSym = isUsd ? '\$' : 'RM';

    final proceeds = qty * price;
    final costBasis = qty * widget.stock.buyPrice;
    final pnl = proceeds - costBasis;
    final pnlPct = costBasis > 0 ? (pnl / costBasis) * 100 : 0.0;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: brand.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                decoration: BoxDecoration(color: brand.divider, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(fontSize: 16, color: _blue)),
                  ),
                  Expanded(
                    child: Text(
                      'Sell ${widget.stock.symbol}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Text('Confirm',
                      style: TextStyle(fontSize: 16, color: _blue, fontWeight: FontWeight.w500)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: brand.surface,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        _SellRow(
                          label: 'Sell quantity',
                          controller: _qtyCtrl,
                          suffix: 'sh',
                          hint: '0',
                          onChanged: (_) => setState(() {}),
                        ),
                        Divider(height: 1, color: brand.divider, indent: 14, endIndent: 14),
                        _SellRow(
                          label: 'Sell price',
                          controller: _priceCtrl,
                          prefix: currSym,
                          hint: '0.00',
                          onChanged: (_) => setState(() {}),
                        ),
                        Divider(height: 1, color: brand.divider, indent: 14, endIndent: 14),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                          child: Row(
                            children: [
                              Text('Holding', style: TextStyle(fontSize: 15, color: brand.inkSoft)),
                              const Spacer(),
                              Text(
                                '${widget.stock.quantity == widget.stock.quantity.floorToDouble() ? widget.stock.quantity.toInt() : widget.stock.quantity.toStringAsFixed(2)} sh',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: brand.ink),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (qty > 0 && price > 0) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: pnl >= 0
                            ? _green.withValues(alpha: 0.08)
                            : _red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Text('P&L', style: TextStyle(fontSize: 14, color: brand.inkSoft)),
                          const Spacer(),
                          Text(
                            '${pnl >= 0 ? '+' : ''}$currSym${pnl.abs().toStringAsFixed(2)} '
                            '(${pnlPct >= 0 ? '+' : ''}${pnlPct.toStringAsFixed(2)}%)',
                            style: TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w700,
                              color: pnl >= 0 ? _green : _red,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  GestureDetector(
                    onTap: _saving ? null : _save,
                    child: Container(
                      height: 54,
                      decoration: BoxDecoration(
                        color: _red,
                        borderRadius: BorderRadius.circular(27),
                      ),
                      alignment: Alignment.center,
                      child: _saving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Confirm sale',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SellRow extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final String? prefix;
  final String? suffix;
  final ValueChanged<String>? onChanged;

  const _SellRow({
    required this.label,
    required this.controller,
    required this.hint,
    this.prefix,
    this.suffix,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final brand = context.brand;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(label, style: TextStyle(fontSize: 15, color: brand.inkSoft)),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: brand.ink),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(color: brand.inkSoft),
                prefixText: prefix != null ? '$prefix ' : null,
                prefixStyle: TextStyle(fontSize: 15, color: brand.inkSoft),
                suffixText: suffix != null ? ' $suffix' : null,
                suffixStyle: TextStyle(fontSize: 15, color: brand.inkSoft),
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
