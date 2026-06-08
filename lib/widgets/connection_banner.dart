import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/i18n.dart';
import '../state/providers.dart';

/// App-wide connectivity banner. Wrap the app's content (via `MaterialApp`'s
/// `builder`) so a slim strip slides down from the top whenever the device is
/// offline — letting the user know their changes are saved locally and will
/// sync on reconnect. On reconnect it briefly shows a "back online / syncing"
/// state, then hides.
class ConnectionBanner extends ConsumerStatefulWidget {
  final Widget child;
  const ConnectionBanner({super.key, required this.child});

  @override
  ConsumerState<ConnectionBanner> createState() => _ConnectionBannerState();
}

class _ConnectionBannerState extends ConsumerState<ConnectionBanner> {
  // Brief window after reconnecting where we show the "back online" state.
  bool _reconnecting = false;
  Timer? _hideTimer;

  static const _offlineColor = Color(0xFFD97706); // amber-600
  static const _onlineColor = Color(0xFF16A34A); // green-600

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
        // Just reconnected — show the "back online" state briefly.
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
    final mq = MediaQuery.of(context);

    final bg = offline ? _offlineColor : _onlineColor;
    final String message;
    if (offline) {
      message = context.t('conn.offline');
    } else if (pending > 0) {
      message = context.t('conn.syncing');
    } else {
      message = context.t('conn.online');
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedSlide(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            offset: visible ? Offset.zero : const Offset(0, -1),
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 220),
              opacity: visible ? 1 : 0,
              child: Material(
                color: bg,
                child: Padding(
                  padding: EdgeInsets.only(
                    top: mq.padding.top + 6,
                    bottom: 8,
                    left: 16,
                    right: 16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (offline)
                        const Icon(CupertinoIcons.wifi_slash,
                            size: 15, color: Colors.white)
                      else if (pending > 0)
                        const SizedBox(
                          width: 14,
                          height: 14,
                          child: CupertinoActivityIndicator(color: Colors.white),
                        )
                      else
                        const Icon(CupertinoIcons.checkmark_alt_circle,
                            size: 15, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          message,
                          textAlign: TextAlign.center,
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
            ),
          ),
        ),
      ],
    );
  }
}
