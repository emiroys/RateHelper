import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'log.dart';

/// Counter snapshot carried on overlay <-> main-isolate sync messages so
/// the receiver can apply values without `SharedPreferences.reload()`.
class OverlayCounters {
  const OverlayCounters({
    required this.accepted,
    required this.rejected,
    required this.completed,
  });

  final int accepted;
  final int rejected;
  final int completed;
}

/// Messages sent between the main app and the overlay isolate via
/// [FlutterOverlayWindow.shareData] / [FlutterOverlayWindow.overlayListener].
abstract final class OverlaySync {
  static const String actionReloadCounters = 'reload_counters';
  static const String keyAccepted = 'accepted';
  static const String keyRejected = 'rejected';
  static const String keyCompleted = 'completed';

  static bool _isReloadMessage(Object? event) {
    if (event is Map) {
      return event['action'] == actionReloadCounters;
    }
    return event == actionReloadCounters;
  }

  /// Returns true when [event] is a counters-reload signal from the other isolate.
  static bool shouldReloadCounters(Object? event) => _isReloadMessage(event);

  static OverlayCounters? countersFromEvent(Object? event) {
    if (event is! Map || !_isReloadMessage(event)) return null;
    final accepted = _asInt(event['accepted']);
    final rejected = _asInt(event['rejected']);
    final completed = _asInt(event['completed']);
    if (accepted == null || rejected == null || completed == null) return null;
    return OverlayCounters(
      accepted: accepted,
      rejected: rejected,
      completed: completed,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  /// Pushes fresh counter values to the other isolate after a write.
  static Future<void> notifyCountersChanged({
    int? accepted,
    int? rejected,
    int? completed,
  }) async {
    try {
      if (!await FlutterOverlayWindow.isActive()) return;
      final payload = <String, String>{'action': actionReloadCounters};
      if (accepted != null) payload[keyAccepted] = '$accepted';
      if (rejected != null) payload[keyRejected] = '$rejected';
      if (completed != null) payload[keyCompleted] = '$completed';
      await FlutterOverlayWindow.shareData(payload);
    } catch (e, s) {
      loge(
        'overlay sync notify failed',
        name: 'overlay_sync',
        error: e,
        stack: s,
      );
    }
  }
}
