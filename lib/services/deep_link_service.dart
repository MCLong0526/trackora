import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';

import '../screens/expenses/add_edit_expense_screen.dart';
import '../screens/expenses/quick_add_sheet.dart';

/// Routes incoming widget URIs to the right screen / sheet.
///
/// Routes:
/// - `trackora://add`            → full Add/Edit Expense screen.
/// - `trackora://quickadd`       → compact `QuickAddSheet` modal.
///   Optional `?amount=N` pre-fills the amount field (used by the
///   iOS-16 fallback link from the widget's preset buttons).
class DeepLinkService {
  static StreamSubscription<Uri?>? _clickSub;

  static void attach(GlobalKey<NavigatorState> navKey) {
    if (_clickSub != null) return;
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

  static void _handle(Uri? uri, GlobalKey<NavigatorState> navKey) {
    if (uri == null) return;
    final host = uri.host.isEmpty ? uri.path.replaceAll('/', '') : uri.host;

    if (host == 'add') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        navKey.currentState?.push(
          CupertinoPageRoute(builder: (_) => const AddEditExpenseScreen()),
        );
      });
      return;
    }

    if (host == 'quickadd') {
      final amountStr = uri.queryParameters['amount'];
      final preset = double.tryParse(amountStr ?? '');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = navKey.currentContext;
        if (ctx == null) return;
        QuickAddSheet.show(ctx, presetAmount: preset);
      });
      return;
    }
  }
}
