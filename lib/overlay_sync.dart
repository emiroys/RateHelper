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
  static const String actionSunMode = 'sun_mode';
  static const String keyAccepted = 'accepted';
  static const String keyRejected = 'rejected';
  static const String keyCompleted = 'completed';
  static const String keySunMode = 'sunMode';

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

  static bool isSunModeMessage(Object? event) {
    return event is Map && event['action'] == actionSunMode;
  }

  /// `true` / `false` when [event] is a sun-mode signal; `null` otherwise.
  static bool? sunModeFromEvent(Object? event) {
    if (event is! Map) return null;
    final raw = event[keySunMode];
    if (event['action'] == actionSunMode) {
      return _asBool(raw) ?? false;
    }
    if (_isReloadMessage(event) && raw != null) return _asBool(raw);
    return null;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool? _asBool(Object? value) {
    if (value is bool) return value;
    if (value is String) return value == '1' || value.toLowerCase() == 'true';
    if (value is num) return value != 0;
    return null;
  }

  /// Pushes fresh counter values to the other isolate after a write.
  static Future<void> notifyCountersChanged({
    int? accepted,
    int? rejected,
    int? completed,
    bool? sunMode,
  }) async {
    try {
      if (!await FlutterOverlayWindow.isActive()) return;
      final payload = <String, String>{'action': actionReloadCounters};
      if (accepted != null) payload[keyAccepted] = '$accepted';
      if (rejected != null) payload[keyRejected] = '$rejected';
      if (completed != null) payload[keyCompleted] = '$completed';
      if (sunMode != null) payload[keySunMode] = sunMode ? '1' : '0';
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

  static Future<void> notifySunMode(bool sun) async {
    try {
      if (!await FlutterOverlayWindow.isActive()) return;
      await FlutterOverlayWindow.shareData(<String, String>{
        'action': actionSunMode,
        keySunMode: sun ? '1' : '0',
      });
    } catch (e, s) {
      loge(
        'overlay sun-mode notify failed',
        name: 'overlay_sync',
        error: e,
        stack: s,
      );
    }
  }
}
