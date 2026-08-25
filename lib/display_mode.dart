import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log.dart';
import 'overlay_sync.dart';

/// User override for the glance-surface theme.
enum DisplayModePref { auto, dark, sun }

/// True when glance surfaces should invert to a high-luminance field.
final ValueNotifier<bool> kSunMode = ValueNotifier<bool>(false);

/// 0→1 multiplier applied only to gauge *arcs* during the ignition sweep.
/// Numerals always show the true value.
final ValueNotifier<double> kGaugeSweep = ValueNotifier<double>(1.0);

/// Pref key stored in SharedPreferences.
const String kDisplayModePrefKey = 'display_mode';

/// Asymmetric lux hysteresis so tunnels and overpasses don't flicker the theme.
class LuxHysteresis {
  LuxHysteresis({
    this.enterLux = 8000,
    this.exitLux = 3000,
    this.enterHold = const Duration(seconds: 3),
    this.exitHold = const Duration(seconds: 10),
  });

  final double enterLux;
  final double exitLux;
  final Duration enterHold;
  final Duration exitHold;

  bool sun = false;
  DateTime? _enterSince;
  DateTime? _exitSince;

  /// Feed a lux sample at [now]. Returns true if [sun] flipped.
  bool tick(double lux, DateTime now) {
    if (lux >= enterLux) {
      _exitSince = null;
      _enterSince ??= now;
      if (!sun && now.difference(_enterSince!) >= enterHold) {
        sun = true;
        _enterSince = null;
        return true;
      }
    } else if (lux <= exitLux) {
      _enterSince = null;
      _exitSince ??= now;
      if (sun && now.difference(_exitSince!) >= exitHold) {
        sun = false;
        _exitSince = null;
        return true;
      }
    } else {
      _enterSince = null;
      _exitSince = null;
    }
    return false;
  }

  void reset() {
    sun = false;
    _enterSince = null;
    _exitSince = null;
  }
}

/// Owns the light-sensor stream, the user override, brightness, and overlay sync.
class DisplayMode {
  DisplayMode._();

  static final DisplayMode instance = DisplayMode._();

  static const _sys = MethodChannel('com.ratehelper.app/system');
  static const _light = EventChannel('com.ratehelper.app/light');

  DisplayModePref pref = DisplayModePref.auto;
  final LuxHysteresis hysteresis = LuxHysteresis();
  StreamSubscription<dynamic>? _luxSub;
  bool _started = false;
  bool _selfTestRunning = false;

  @visibleForTesting
  bool get isListeningToLux => _luxSub != null;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      pref = _parsePref(prefs.getString(kDisplayModePrefKey));
      _applyForced();
    } catch (e, s) {
      loge('display mode prefs failed', name: 'display', error: e, stack: s);
    }
    try {
      _luxSub = _light.receiveBroadcastStream().listen(
        (event) {
          if (event is num) _onLux(event.toDouble());
        },
        onError: (_) {},
      );
    } catch (e, s) {
      loge('light sensor listen failed', name: 'display', error: e, stack: s);
    }
  }

  Future<void> setPref(DisplayModePref next) async {
    pref = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kDisplayModePrefKey, next.name);
    } catch (_) {}
    _applyForced();
  }

  void cyclePref() {
    final next = switch (pref) {
      DisplayModePref.auto => DisplayModePref.sun,
      DisplayModePref.sun => DisplayModePref.dark,
      DisplayModePref.dark => DisplayModePref.auto,
    };
    unawaited(setPref(next));
  }

  void _onLux(double lux) {
    if (pref != DisplayModePref.auto) return;
    final flipped = hysteresis.tick(lux, DateTime.now());
    if (flipped) unawaited(_commit(hysteresis.sun));
  }

  void _applyForced() {
    switch (pref) {
      case DisplayModePref.sun:
        unawaited(_commit(true));
      case DisplayModePref.dark:
        unawaited(_commit(false));
      case DisplayModePref.auto:
        unawaited(_commit(hysteresis.sun));
    }
  }

  Future<void> _commit(bool sun) async {
    if (kSunMode.value != sun) kSunMode.value = sun;
    try {
      if (sun) {
        await _sys.invokeMethod<bool>('setScreenBrightness', {'value': 1.0});
      } else {
        await _sys.invokeMethod<bool>('clearScreenBrightness');
      }
    } catch (_) {}
    unawaited(OverlaySync.notifySunMode(sun));
  }

  /// Cluster self-test: arc sweeps 0 → slight overshoot → settle. Numeral stays.
  Future<void> playSelfTest() async {
    if (_selfTestRunning) return;
    _selfTestRunning = true;
    try {
      kGaugeSweep.value = 0;
      const totalMs = 450;
      const overshootAtMs = 320;
      const stepMs = 16;
      var elapsedMs = 0;
      while (elapsedMs < totalMs) {
        await Future<void>.delayed(const Duration(milliseconds: stepMs));
        elapsedMs += stepMs;
        final t = elapsedMs / totalMs;
        if (elapsedMs < overshootAtMs) {
          kGaugeSweep.value = (t / (overshootAtMs / totalMs)).clamp(0.0, 1.05);
        } else {
          final rest = (elapsedMs - overshootAtMs) / (totalMs - overshootAtMs);
          kGaugeSweep.value = 1.05 - 0.05 * rest.clamp(0.0, 1.0);
        }
      }
      kGaugeSweep.value = 1.0;
    } finally {
      _selfTestRunning = false;
      kGaugeSweep.value = 1.0;
    }
  }

  static DisplayModePref _parsePref(String? raw) {
    for (final v in DisplayModePref.values) {
      if (v.name == raw) return v;
    }
    return DisplayModePref.auto;
  }
}
