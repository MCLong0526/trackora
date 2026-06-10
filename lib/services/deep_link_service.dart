import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';

import '../models/expense.dart';
import '../screens/expenses/add_edit_expense_screen.dart';
import '../screens/expenses/import_receipt_screen.dart';
import '../screens/expenses/quick_add_sheet.dart';

/// Routes incoming widget URIs to the right screen / sheet.
///
/// Routes:
/// - `trackora://add`            → full Add/Edit Expense screen.
/// - `trackora://quickadd`       → compact `QuickAddSheet` modal.
///   Optional `?amount=N` pre-fills the amount field (used by the
///   iOS-16 fallback link from the widget's preset buttons).
/// - `trackora://scan`           → ImportReceiptScreen camera OCR flow.
/// - `trackora://import-receipt` → ImportReceiptScreen (Share Extension).
class DeepLinkService {
  static const _shareChannel = MethodChannel('trackora/share_import');
  static const _initialLinkChannel = MethodChannel('trackora/initial_link');

  static StreamSubscription<Uri?>? _clickSub;

  // Prevents opening ImportReceiptScreen multiple times for the same share.
  static bool _importScreenOpen = false;

  static void attach(GlobalKey<NavigatorState> navKey) {
    if (_clickSub != null) return;

    // Listen for URLs pushed from native (app brought to foreground via widget/live activity)
    _initialLinkChannel.setMethodCallHandler((call) async {
      if (call.method == 'onLink') {
        final urlStr = call.arguments as String?;
        if (urlStr != null) _handle(Uri.tryParse(urlStr), navKey);
      }
    });

    // Check for a URL captured by native before Flutter was ready (cold start case)
    _initialLinkChannel.invokeMethod<String?>('getInitialLink').then((urlStr) {
      if (urlStr != null) _handle(Uri.tryParse(urlStr), navKey);
    }).catchError((_) {});

    // Must be set up before the iOS platform check so we handle the channel
    // on all platforms gracefully (no-op on Android / web).
    _attachShareImportListener(navKey);

    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.iOS &&
            defaultTargetPlatform != TargetPlatform.android)) {
      return;
    }

    HomeWidget.initiallyLaunchedFromHomeWidget()
        .then((uri) {
          _handle(uri, navKey);
        })
        .catchError((_) {});

    try {
      _clickSub = HomeWidget.widgetClicked.listen(
        (uri) => _handle(uri, navKey),
        onError: (_) {},
      );
    } catch (_) {}
  }

  /// Called on every app resume (foreground) so a share made while the app
  /// was in background or when the URL scheme failed is still detected.
  static Future<void> checkAndOpenPendingShare(
    GlobalKey<NavigatorState> navKey,
  ) async {
    try {
      final result = await _shareChannel.invokeMethod<Map<Object?, Object?>>(
        'checkPendingShare',
      );
      if (result != null && result.isNotEmpty) {
        _openImportScreen(navKey);
      }
    } catch (_) {}
  }

  /// Mark the import screen as closed so the next share can open it again.
  static void onImportScreenClosed() {
    _importScreenOpen = false;
  }

  /// Opens [ImportReceiptScreen] from a Back Tap when a pending image exists.
  /// Uses the same [_importScreenOpen] guard to prevent duplicate screens.
  static void openImportScreenForBackTap(GlobalKey<NavigatorState> navKey) {
    _openImportScreen(navKey);
  }

  // MARK: - Private

  static void _attachShareImportListener(GlobalKey<NavigatorState> navKey) {
    _shareChannel.setMethodCallHandler((call) async {
      if (call.method == 'onShareImport') {
        _openImportScreen(navKey);
      }
    });
    _checkPendingShareOnStartup(navKey);
  }

  static Future<void> _checkPendingShareOnStartup(
    GlobalKey<NavigatorState> navKey,
  ) async {
    try {
      final result = await _shareChannel.invokeMethod<Map<Object?, Object?>>(
        'checkPendingShare',
      );
      if (result != null && result.isNotEmpty) {
        _openImportScreen(navKey);
      }
    } catch (_) {}
  }

  /// Push ImportReceiptScreen, retrying until the navigator is ready.
  /// This handles cold-start races where the engine fires onShareImport
  /// before Firebase initialisation completes and the navigator is mounted.
  static void _openImportScreen(
    GlobalKey<NavigatorState> navKey, {
    bool openCamera = false,
    int retries = 20,
  }) {
    if (_importScreenOpen) return;
    _importScreenOpen = true;

    _tryPush(navKey, retries, openCamera: openCamera);
  }

  static void _tryPush(
    GlobalKey<NavigatorState> navKey,
    int retries, {
    required bool openCamera,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final state = navKey.currentState;
      if (state != null) {
        state.push(
          CupertinoPageRoute(
            builder: (_) => ImportReceiptScreen(
              onClose: DeepLinkService.onImportScreenClosed,
              openCamera: openCamera,
            ),
          ),
        );
      } else if (retries > 0) {
        // Navigator not yet mounted — wait one more frame tick.
        Future.delayed(const Duration(milliseconds: 250), () {
          _tryPush(navKey, retries - 1, openCamera: openCamera);
        });
      } else {
        // Gave up — reset flag so the next share can still open the screen.
        _importScreenOpen = false;
      }
    });
  }

  // Guards against the same deep link being delivered twice in quick succession
  // (it can arrive via both the native channel and the home_widget plugin),
  // which otherwise stacks two Add-Expense screens.
  static String? _lastHandledUri;
  static DateTime? _lastHandledAt;

  static void _handle(Uri? uri, GlobalKey<NavigatorState> navKey) {
    if (uri == null) return;
    final uriStr = uri.toString();
    final now = DateTime.now();
    if (_lastHandledUri == uriStr &&
        _lastHandledAt != null &&
        now.difference(_lastHandledAt!) < const Duration(milliseconds: 1200)) {
      return;
    }
    _lastHandledUri = uriStr;
    _lastHandledAt = now;
    final host = uri.host.isEmpty ? uri.path.replaceAll('/', '') : uri.host;

    if (host == 'add') {
      final typeStr = uri.queryParameters['type'];
      final initialType = typeStr == 'income'
          ? EntryType.income
          : typeStr == 'expense'
          ? EntryType.expense
          : typeStr == 'receive'
          ? EntryType.receive
          : typeStr == 'transfer'
          ? EntryType.transfer
          : null;
      final amountStr = uri.queryParameters['amount'];
      final initialAmount = double.tryParse(amountStr ?? '');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navKey.currentState?.push(
          CupertinoPageRoute(
            builder: (_) => AddEditExpenseScreen(
              initialType: initialType,
              initialAmount: initialAmount,
            ),
          ),
        );
      });
      return;
    }

    if (host == 'scan') {
      _openImportScreen(navKey, openCamera: true);
      return;
    }

    if (host == 'quickadd') {
      final amountStr = uri.queryParameters['amount'];
      final preset = double.tryParse(amountStr ?? '');
      final category = uri.queryParameters['category'];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navKey.currentContext;
        if (ctx == null) return;
        QuickAddSheet.show(ctx, presetAmount: preset, presetCategory: category);
      });
      return;
    }
  }
}
