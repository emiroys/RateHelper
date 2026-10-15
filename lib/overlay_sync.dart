import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'log.dart';

/// Counter snapshot carried on overlay <-> main-isolate sync messages so
/// the receiver can apply values without `SharedPreferences.reload()`.
class OverlayCounters {
  const OverlayCounters({
    required this.accepted,
    required this.rejected,
    required this.completed,
    this.canceled,
  });

  final int accepted;
  final int rejected;
  final int completed;

  /// Present only when the sender updated `canceledTrips` ("İptal Edilen").
  /// Null means "leave the receiver's cancellation count alone".
  final int? canceled;
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
  static const String keyCanceled = 'canceled';

  static const String actionSettingsChanged = 'settings_changed';
  static const String keyLang = 'lang';
  static const String keyGoalTier = 'goal_tier';
  static const String keyAutoComplete = 'auto_complete';

  static const String actionMediaKeyIncrement = 'media_key_increment';
  static const String keyMediaKey = 'key';

  /// Matches home-screen manual counter clamp.
  static const int maxCounterValue = 99999;

  static const Set<String> _allowedLangs = {'tr', 'en', 'pl'};
  static const Set<String> _allowedGoalTiers = {
    'tier0',
    'tier1',
    'tier2',
    'tier3',
    'tier4',
  };

  static const Set<String> _reloadCounterKeys = {
    'action',
    keyAccepted,
    keyRejected,
    keyCompleted,
    keyCanceled,
  };

  static const Set<String> _settingsKeys = {
    'action',
    keyLang,
    keyGoalTier,
    keyAutoComplete,
  };

  static const Set<String> _mediaKeyKeys = {'action', keyMediaKey};

  static bool _mapKeysAllowed(Map<dynamic, dynamic> map, Set<String> allowed) {
    for (final key in map.keys) {
      if (key is! String || !allowed.contains(key)) return false;
    }
    return true;
  }

  static bool _isReloadMessage(Object? event) {
    if (event is Map) {
      return event['action'] == actionReloadCounters;
    }
    return event == actionReloadCounters;
  }

  /// Returns true when [event] is a counters-reload signal from the other isolate.
  static bool shouldReloadCounters(Object? event) => _isReloadMessage(event);

  static int? _counterInt(Object? value) {
    final parsed = _asInt(value);
    if (parsed == null || parsed < 0 || parsed > maxCounterValue) return null;
    return parsed;
  }

  static OverlayCounters? countersFromEvent(Object? event) {
    if (event is! Map || !_isReloadMessage(event)) return null;
    if (!_mapKeysAllowed(event, _reloadCounterKeys)) return null;
    final accepted = _counterInt(event['accepted']);
    final rejected = _counterInt(event['rejected']);
    final completed = _counterInt(event['completed']);
    if (accepted == null || rejected == null || completed == null) return null;
    int? canceled;
    if (event.containsKey(keyCanceled)) {
      canceled = _counterInt(event[keyCanceled]);
      if (canceled == null) return null;
    }
    return OverlayCounters(
      accepted: accepted,
      rejected: rejected,
      completed: completed,
      canceled: canceled,
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  static bool? _boolField(Object? value) {
    if (value is bool) return value;
    if (value is String) {
      if (value == 'true') return true;
      if (value == 'false') return false;
    }
    return null;
  }

  /// Returns the settings carried by [event], or null when it is not a
  /// settings-changed message.
  static OverlaySettings? settingsFromEvent(Object? event) {
    if (event is! Map || event['action'] != actionSettingsChanged) return null;
    if (!_mapKeysAllowed(event, _settingsKeys)) return null;
    final lang = event[keyLang];
    final goalTier = event[keyGoalTier];
    final autoComplete = _boolField(event[keyAutoComplete]);
    if (lang is! String ||
        goalTier is! String ||
        autoComplete == null ||
        !_allowedLangs.contains(lang) ||
        !_allowedGoalTiers.contains(goalTier)) {
      return null;
    }
    return OverlaySettings(
      lang: lang,
      goalTier: goalTier,
      autoComplete: autoComplete,
    );
  }

  /// Steering-wheel overlay path: `accepted` or `rejected`, or null if invalid.
  static String? mediaKeyTargetFromEvent(Object? event) {
    if (event is! Map || event['action'] != actionMediaKeyIncrement) {
      return null;
    }
    if (!_mapKeysAllowed(event, _mediaKeyKeys)) return null;
    final key = event[keyMediaKey];
    if (key == 'accepted' || key == 'rejected') return key;
    return null;
  }

  /// Applies [event] when it matches a known, validated message. Never throws.
  static void deliver(
    Object? event, {
    void Function(OverlayCounters counters)? onCounters,
    void Function()? onCountersReloadFromStore,
    void Function(OverlaySettings settings)? onSettings,
    void Function(String counterKey)? onMediaKey,
  }) {
    try {
      if (shouldReloadCounters(event)) {
        final counters = countersFromEvent(event);
        if (counters != null) {
          onCounters?.call(counters);
        } else {
          onCountersReloadFromStore?.call();
        }
        return;
      }
      final settings = settingsFromEvent(event);
      if (settings != null) {
        onSettings?.call(settings);
        return;
      }
      final mediaKey = mediaKeyTargetFromEvent(event);
      if (mediaKey != null) {
        onMediaKey?.call(mediaKey);
      }
    } catch (e, s) {
      loge(
        'overlay message rejected',
        name: 'overlay_sync',
        error: e,
        stack: s,
      );
    }
  }

  static Map<String, String> counterPayload({
    int? accepted,
    int? rejected,
    int? completed,
    int? canceled,
  }) {
    final payload = <String, String>{'action': actionReloadCounters};
    if (accepted != null) payload[keyAccepted] = '$accepted';
    if (rejected != null) payload[keyRejected] = '$rejected';
    if (completed != null) payload[keyCompleted] = '$completed';
    if (canceled != null) payload[keyCanceled] = '$canceled';
    return payload;
  }

  /// Pushes fresh counter values to the other isolate after a write.
  ///
  /// Main → overlay. Checks that the pill is up first; a send with no
  /// overlay engine is a no-op on the native side, but the check avoids
  /// the channel hop when the driver has the pill closed.
  static Future<void> notifyCountersChanged({
    int? accepted,
    int? rejected,
    int? completed,
    int? canceled,
  }) async {
    try {
      if (!await FlutterOverlayWindow.isActive()) return;
      await FlutterOverlayWindow.shareData(
        counterPayload(
          accepted: accepted,
          rejected: rejected,
          completed: completed,
          canceled: canceled,
        ),
      );
    } catch (e, s) {
      loge(
        'overlay sync notify failed',
        name: 'overlay_sync',
        error: e,
        stack: s,
      );
    }
  }

  /// Overlay → main. Fire-and-forget: no `isActive` round trip (that await
  /// can reorder a burst) and no wait on the reply. [Future.catchError]
  /// keeps a dead main isolate from ever touching the tap handler — the
  /// same class of hung Future that froze the pill when a store write threw.
  ///
  /// Disk is the fallback. If nobody is listening, the next resume still
  /// reads the shift-counter file.
  static void pingCountersChanged({
    int? accepted,
    int? rejected,
    int? completed,
    int? canceled,
  }) {
    final payload = counterPayload(
      accepted: accepted,
      rejected: rejected,
      completed: completed,
      canceled: canceled,
    );
    // Future<void> so catchError's callback can return nothing. A raw
    // shareData future is not void, and returning null from its error
    // handler is rejected — that throw would escape the tap path.
    try {
      unawaited(
        Future<void>.sync(
          () => FlutterOverlayWindow.shareData(payload),
        ).catchError((Object error, StackTrace stack) {
          loge(
            'overlay sync ping failed',
            name: 'overlay_sync',
            error: error,
            stack: stack,
          );
        }),
      );
    } catch (e, s) {
      loge(
        'overlay sync ping failed',
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

/// Collapses a burst of overlay counter messages into one apply.
///
/// Ten pings that land before the next frame update the pending snapshot
/// and flush once. There is no periodic timer; the callback is armed by
/// the message itself.
class OverlayCounterBurst {
  OverlayCounterBurst({void Function(void Function() callback)? schedule})
    : _schedule = schedule ?? scheduleOnNextFrame;

  /// Test hook. Production flushes on the next frame, which is also the
  /// earliest a counter widget can rebuild.
  final void Function(void Function() callback) _schedule;

  static void scheduleOnNextFrame(void Function() callback) {
    SchedulerBinding.instance.scheduleFrameCallback((_) => callback());
  }

  OverlayCounters? _latest;
  var _pending = false;
  var _armed = false;
  void Function(OverlayCounters? latest)? _flush;

  /// [counters] null means "read the counter file". The last event in the
  /// burst wins, so a payload that arrives after an empty ping is kept.
  void add(
    OverlayCounters? counters,
    void Function(OverlayCounters? latest) flush,
  ) {
    _flush = flush;
    _pending = true;
    _latest = counters;
    if (_armed) return;
    _armed = true;
    _schedule(_fire);
  }

  void _fire() {
    _armed = false;
    if (!_pending) return;
    _pending = false;
    final latest = _latest;
    _latest = null;
    final flush = _flush;
    _flush = null;
    if (flush != null) flush(latest);
  }
}
