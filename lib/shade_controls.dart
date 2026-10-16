import 'dart:async';

import 'package:flutter/foundation.dart';

import 'l10n.dart';
import 'log.dart';

/// Accept +1 / Reject +1 on the overlay's foreground notification.
///
/// The overlay isolate is the only sender: it holds the live counters and
/// talks straight to the `OverlayService` that owns the notification, and
/// the notification exists only while that service runs.
abstract final class ShadeControls {
  /// SharedPreferences flag. Default off.
  static const String prefsKey = 'notificationControlsEnabled';

  /// SharedPreferences flag: shade-only mode, no pill on screen. Default
  /// off, and only meaningful while [prefsKey] is on — see [pillHidden].
  static const String hidePillPrefsKey = 'hideOverlayBubbleWhenShadeActive';

  /// The one rule for whether the pill window is hidden. Without the
  /// notification buttons a hidden pill would leave a service with no
  /// controls at all, so the hide flag alone never hides anything.
  static bool pillHidden({
    required bool notificationControls,
    required bool hidePill,
  }) => notificationControls && hidePill;

  /// Fastest the notification is re-posted while counters change.
  static const Duration minInterval = Duration(seconds: 1);

  /// Strings the native side lays out. Rate and counts only — no money.
  ///
  /// `tone` follows the pill's colour rule for [requiredRate]: `green` at or
  /// above the goal plus the 2-point buffer, `amber` inside the buffer,
  /// `red` below the goal. No goal (tier0) is always green.
  static Map<String, Object?> content({
    required int accepted,
    required int rejected,
    double? requiredRate,
  }) {
    final total = accepted + rejected;
    final double rate = total == 0 ? 100.0 : (accepted / total) * 100;
    final percent = S.formatPercent(rate.toStringAsFixed(2));
    return <String, Object?>{
      'channel': S.shadeChannelName,
      'title': S.shadeTitle(percent),
      'text': S.shadeCounts(accepted, rejected),
      'rate': percent,
      'rateLabel': S.acceptRate,
      'tone': _tone(rate, requiredRate),
      'accept': S.shadeAccept,
      'reject': S.shadeReject,
    };
  }

  static const double _amberBuffer = 2.0;

  static String _tone(double rate, double? requiredRate) {
    if (requiredRate == null) return 'green';
    if (rate < requiredRate) return 'red';
    if (rate < requiredRate + _amberBuffer) return 'amber';
    return 'green';
  }
}

/// Coalesces notification updates: the first change goes out at once, later
/// ones inside [interval] collapse into a single trailing post with the
/// newest content. Unchanged content is never re-posted. No periodic timer —
/// the cooldown is armed only by a post.
class ShadeNotificationThrottle {
  ShadeNotificationThrottle({
    required Future<bool?> Function(Map<String, Object?>? content) send,
    this.interval = ShadeControls.minInterval,
  }) : _send = send;

  final Future<bool?> Function(Map<String, Object?>? content) _send;
  final Duration interval;

  Timer? _cooldown;

  /// Null = the plain notification, which is what the service starts with.
  Map<String, Object?>? _lastSent;

  /// The last post failed, so the next update must go out even if equal.
  bool _lastFailed = false;

  bool _hasPending = false;
  Map<String, Object?>? _pending;

  /// [content] null switches the controls off.
  void update(Map<String, Object?>? content) {
    if (_cooldown != null) {
      _pending = content;
      _hasPending = true;
      return;
    }
    _postIfChanged(content);
  }

  void dispose() {
    _cooldown?.cancel();
    _cooldown = null;
    _hasPending = false;
    _pending = null;
  }

  void _postIfChanged(Map<String, Object?>? content) {
    if (!_lastFailed && mapEquals(content, _lastSent)) return;
    _lastSent = content;
    _lastFailed = false;
    _cooldown = Timer(interval, _onCooldownEnd);
    unawaited(
      Future<bool?>.sync(() => _send(content)).then(
        (ok) {
          if (ok != true) _lastFailed = true;
        },
        onError: (Object e, StackTrace s) {
          _lastFailed = true;
          loge(
            'shade notification update failed',
            name: 'shade',
            error: e,
            stack: s,
          );
        },
      ),
    );
  }

  void _onCooldownEnd() {
    _cooldown = null;
    if (!_hasPending) return;
    final content = _pending;
    _hasPending = false;
    _pending = null;
    _postIfChanged(content);
  }
}
