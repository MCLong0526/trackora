import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Controls the Trackora Quick Add Live Activity on iOS (Dynamic Island /
/// Lock Screen). No-ops silently on Android and when the iOS version does
/// not support Live Activities (< 16.1).
class LiveActivityService {
  static const _channel = MethodChannel('trackora/live_activity');

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Starts (or restarts) the Live Activity.
  /// Returns null on success, or an error string if it failed.
  static Future<String?> start({
    required String currency,
    required double todaySpent,
    int todayCount = 0,
  }) async {
    if (!_supported) return null;
    try {
      await _channel.invokeMethod<dynamic>('start', {
        'currency': currency,
        'todaySpent': todaySpent,
        'todayCount': todayCount,
      });
      return null;
    } on PlatformException catch (e) {
      debugPrint('[LiveActivity] start failed: ${e.code} – ${e.message}');
      return e.message ?? e.code;
    } catch (e) {
      debugPrint('[LiveActivity] start error: $e');
      return e.toString();
    }
  }

  /// Updates the Live Activity state. No-op if no activity is running.
  static Future<void> update({
    required String currency,
    required double todaySpent,
    int todayCount = 0,
  }) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<dynamic>('update', {
        'currency': currency,
        'todaySpent': todaySpent,
        'todayCount': todayCount,
      });
    } on PlatformException catch (e) {
      debugPrint('[LiveActivity] update failed: ${e.code} – ${e.message}');
    } catch (e) {
      debugPrint('[LiveActivity] update error: $e');
    }
  }

  /// Ends and dismisses the Live Activity immediately.
  static Future<void> stop() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod<dynamic>('stop');
    } on PlatformException catch (e) {
      debugPrint('[LiveActivity] stop failed: ${e.code} – ${e.message}');
    } catch (e) {
      debugPrint('[LiveActivity] stop error: $e');
    }
  }
}
