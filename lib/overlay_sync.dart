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

/// The subset of home-screen settings the pill renders with, carried in-band
/// on a settings-changed message.
///
/// These are sent as values rather than as a "re-read prefs" signal because
/// each isolate holds its own `SharedPreferences` cache: a write on the home
/// isolate is invisible to the overlay until `reload()`, which parses the
/// whole prefs file. The overlay only calls `reload()` once, at startup.
class OverlaySettings {
  const OverlaySettings({
    required this.lang,
    required this.goalTier,
    required this.autoComplete,
  });

  final String lang;
  final String goalTier;
  final bool autoComplete;
}

/// Messages sent between the main app and the overlay isolate via
/// [FlutterOverlayWindow.shareData] / [FlutterOverlayWindow.overlayListener].
abstract final class OverlaySync {
  static const String actionReloadCounters = 'reload_counters';
  static const String keyAccepted = 'accepted';
  static const String keyRejected = 'rejected';
  static const String keyCompleted = 'completed';

  static const String actionSettingsChanged = 'settings_changed';
  static const String keyLang = 'lang';
  static const String keyGoalTier = 'goal_tier';
  static const String keyAutoComplete = 'auto_complete';

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

  /// Returns the settings carried by [event], or null when it is not a
  /// settings-changed message.
  static OverlaySettings? settingsFromEvent(Object? event) {
    if (event is! Map || event['action'] != actionSettingsChanged) return null;
    final lang = event[keyLang];
    final goalTier = event[keyGoalTier];
    final autoComplete = event[keyAutoComplete];
    if (lang is! String || goalTier is! String || autoComplete is! String) {
      return null;
    }
    return OverlaySettings(
      lang: lang,
      goalTier: goalTier,
      autoComplete: autoComplete == 'true',
    );
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

  /// Pushes the pill-relevant settings to the overlay after a home-screen
  /// write. Must be called from every settings mutation the pill reads —
  /// without it the running overlay keeps the previous language, goal tier
  /// and auto-complete behaviour until it is closed and reopened.
  static Future<void> notifySettingsChanged({
    required String lang,
    required String goalTier,
    required bool autoComplete,
  }) async {
    try {
      if (!await FlutterOverlayWindow.isActive()) return;
      await FlutterOverlayWindow.shareData(<String, String>{
        'action': actionSettingsChanged,
        keyLang: lang,
        keyGoalTier: goalTier,
        keyAutoComplete: '$autoComplete',
      });
    } catch (e, s) {
      loge(
        'overlay sync settings notify failed',
        name: 'overlay_sync',
        error: e,
        stack: s,
      );
    }
  }
}
