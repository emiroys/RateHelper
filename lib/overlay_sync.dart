import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'log.dart';

/// Messages sent between the main app and the overlay isolate via
/// [FlutterOverlayWindow.shareData] / [FlutterOverlayWindow.overlayListener].
abstract final class OverlaySync {
  static const String actionReloadCounters = 'reload_counters';

  static bool _isReloadMessage(Object? event) {
    if (event is Map) {
      return event['action'] == actionReloadCounters;
    }
    return event == actionReloadCounters;
  }

  /// Returns true when [event] is a counters-reload signal from the main app.
  static bool shouldReloadCounters(Object? event) =>
      _isReloadMessage(event);

  /// Pushes fresh counter values to the overlay after main-app writes.
  static Future<void> notifyCountersChanged() async {
    try {
      if (!await FlutterOverlayWindow.isActive()) return;
      await FlutterOverlayWindow.shareData(
        <String, String>{'action': actionReloadCounters},
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
}
