import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/i18n.dart';
import '../state/providers.dart';

/// App-wide connectivity indicator. Wrap the app's content (via `MaterialApp`'s
/// `builder`) so a compact, iOS-style pill drops in below the status bar when
/// the device is offline — and **pushes the content down** rather than
/// overlaying it, so nothing is ever covered. On reconnect it briefly shows a
/// "back online / syncing" state, then slides away.
class ConnectionBanner extends ConsumerStatefulWidget {
  final Widget child;
  const ConnectionBanner({super.key, required this.child});

  @override
  ConsumerState<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends ConsumerState<ConnectionBanner> {
  bool _reconnecting = false;
  Timer? _hideTimer;

  static const _offlineColor = Color(0xFFF59E0B); // amber
  static const _onlineColor = Color(0xFF34C759); // iOS green

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<bool>>(networkStatusProvider, (prev, next) {
      final was = prev?.valueOrNull;
      final now = next.valueOrNull;
      if (was == false && now == true) {
        setState(() => _reconnecting = true);
        _hideTimer?.cancel();
        _hideTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _reconnecting = false);
        });
      } else if (now == false) {
        _hideTimer?.cancel();
        if (_reconnecting) setState(() => _reconnecting = false);
      }
    });

    final online = ref.watch(networkStatusProvider).valueOrNull ?? true;
    final pending = ref.watch(pendingExpenseChangeCountProvider);
    final offline = !online;
    final visible = offline || _reconnecting;

    final color = offline ? _offlineColor : _onlineColor;
    final String message;
    if (offline) {
      message = context.t('conn.offline');
    } else if (pending > 0) {
      message = context.t('conn.syncing');
    } else {
      message = context.t('conn.online');
    }

    // The status-bar area is always reserved with the scaffold background so
    // the layout never jumps; only the pill's height animates in/out, pushing
    // the content down without covering it.
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: SafeArea(
        top: true,
        bottom: false,
        left: false,
        right: false,
        child: Column(
          children: [
            AnimatedSize(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: visible
                  ? _Pill(
                      color: color,
                      message: message,
                      offline: offline,
                      pending: pending,
                    )
                  : const SizedBox(width: double.infinity),
            ),
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeTop: true,
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final Color color;
  final String message;
  final bool offline;
  final int pending;
  const _Pill({
    required this.color,
    required this.message,
    required this.offline,
    required this.pending,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(100),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.32),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (offline)
                const Icon(CupertinoIcons.wifi_slash,
                    size: 14, color: Colors.white)
              else if (pending > 0)
                const SizedBox(
                  width: 13,
                  height: 13,
                  child: CupertinoActivityIndicator(color: Colors.white),
                )
              else
                const Icon(CupertinoIcons.checkmark_alt_circle,
                    size: 14, color: Colors.white),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
