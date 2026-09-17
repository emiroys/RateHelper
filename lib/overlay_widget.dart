import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';
import 'l10n.dart';
import 'log.dart';
import 'overlay_sync.dart';
import 'shift_counter_store.dart';
import 'tap_history_store.dart';

enum PillOrientation {
  horizontal,
  vertical;

  static const String prefsKey = 'overlay_pill_orientation';
  static const String legacyBoolKey = 'overlayVertical';

  bool get isVertical => this == vertical;

  static PillOrientation fromName(String? raw) {
    if (raw == vertical.name) return vertical;
    return horizontal;
  }

  static PillOrientation fromPrefs(SharedPreferences prefs) {
    final named = prefs.getString(prefsKey);
    if (named != null) return fromName(named);
    if (prefs.getBool(legacyBoolKey) == true) return vertical;
    return horizontal;
  }
}

class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key, this.initialOrientation});

  /// When set (tests / first-frame), used until prefs load.
  final PillOrientation? initialOrientation;

  /// Landscape (horizontal) pill — native window equals the visible widget.
  static const double pillWidthDp = 276;
  static const double pillHeightDp = 80;

  static const double btnSizeDp = 68;

  /// Portrait pill hugs its content: a uniform [verticalInsetDp] ring on all
  /// four sides, so the stadium caps stay concentric with the round buttons
  /// instead of leaving dead space at the ends.
  static const double verticalInsetDp = 3;
  static const double verticalGapDp = 8;
  static const double verticalRateSlotDp = 36;
  static const double verticalPillWidthDp = btnSizeDp + verticalInsetDp * 2;
  static const double verticalPillHeightDp =
      btnSizeDp * 2 +
      verticalGapDp * 2 +
      verticalRateSlotDp +
      verticalInsetDp * 2;

  static const int nativeWindowWidthDp = 276;
  static const int nativeWindowHeightDp = 80;

  static int windowWidthDp(PillOrientation orientation) =>
      orientation.isVertical
      ? verticalPillWidthDp.round()
      : pillWidthDp.round();

  static int windowHeightDp(PillOrientation orientation) =>
      orientation.isVertical
      ? verticalPillHeightDp.round()
      : pillHeightDp.round();

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget> {
  static const _keyAccepted = 'acceptedRequests';
  static const _keyRejected = 'rejectedRequests';
  static const _keyAutoComplete = 'autoCompleteTrips';
  static const _persistDebounce = Duration(milliseconds: 300);

  /// Gap between the two reject pulses, matching REJECT_PATTERN in
  /// MediaKeyAccessibilityService so both input paths feel identical.
  static const _rejectPulseGap = Duration(milliseconds: 70);

  static const _crimson = AppColors.crimson;
  static const _emerald = AppColors.emerald;
  static const _amber = AppColors.amber;
  static const _pillBg = AppColors.overlayPill;
  static const _pillBorder = AppColors.strongBorder;

  static const double _centerTextWidthDp = 100;
  static const double _btnSizeDp = OverlayWidget.btnSizeDp;
  static const double _btnTextGapDp = 12;
  static const double _verticalCenterTextWidthDp = OverlayWidget.btnSizeDp;

  StreamSubscription<dynamic>? _syncSub;
  Timer? _persistTimer;
  Timer? _rejectPulseTimer;

  /// Bumped on every counted tap. Re-keys the value pop so it replays.
  int _tapSeq = 0;

  /// Set once home has pushed settings to this isolate. From then on prefs is
  /// a stale mirror and must not win over a pushed value.
  bool _settingsPushed = false;

  int _accepted = 0;
  int _rejected = 0;
  int _completed = 0;
  bool _autoComplete = false;
  double? _requiredAcceptRate = 80.0;
  late PillOrientation _orientation =
      widget.initialOrientation ?? PillOrientation.horizontal;

  int? _trackedPointer;
  Offset? _pointerDownPos;
  bool _pointerIsDrag = false;

  bool get _hasUnpersistedTaps => _persistTimer?.isActive ?? false;

  double get _acceptanceRate {
    final total = _accepted + _rejected;
    if (total == 0) return 100.0;
    return (_accepted / total) * 100;
  }

  Color get _acceptRateColor {
    final req = _requiredAcceptRate;
    if (req == null) return _emerald;
    if (_acceptanceRate < req) return _crimson;
    if (_acceptanceRate < req + 2.0) return _amber;
    return _emerald;
  }

  String _formatAcceptRate(double rate) {
    if (_accepted == 0 && _rejected == 0) {
      return S.formatPercent('100');
    }
    final rounded = (rate * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return S.formatPercent(rounded.toInt().toString());
    }
    return S.formatPercent(rounded.toStringAsFixed(1));
  }

  @override
  void initState() {
    super.initState();
    _orientation = widget.initialOrientation ?? PillOrientation.horizontal;
    unawaited(_loadCountsOnStartup());
    try {
      _syncSub = FlutterOverlayWindow.overlayListener.listen((event) {
        if (OverlaySync.shouldReloadCounters(event)) {
          final counters = OverlaySync.countersFromEvent(event);
          if (counters != null) {
            _applyRemoteCounters(counters);
          } else {
            unawaited(_loadCounts());
          }
          return;
        }
        final settings = OverlaySync.settingsFromEvent(event);
        if (settings != null) {
          _applyRemoteSettings(settings);
          return;
        }
        if (event is Map && event['action'] == 'media_key_increment') {
          final keyStr = event['key'];
          final key = keyStr == 'accepted' ? _keyAccepted : _keyRejected;
          // Native already fired its own accept/reject waveform before
          // handing the tap over — a second buzz here would blur the rhythm.
          unawaited(_increment(key, haptic: false));
        }
      });
    } catch (e, s) {
      loge(
        'overlayListener listen failed',
        name: 'overlay',
        error: e,
        stack: s,
      );
    }
  }

  static double? _reqRateForTier(String? goalStr) {
    if (goalStr == 'tier0') return null;
    if (goalStr == 'tier2') return 70.0;
    if (goalStr == 'tier3') return 60.0;
    if (goalStr == 'tier4') return 50.0;
    return 80.0;
  }

  double? _parseReqRate(SharedPreferences prefs) =>
      _reqRateForTier(prefs.getString('trip_goal_tier'));

  Future<void> _loadCountsOnStartup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Startup-only reload for lang / goal / autoComplete / layout.
      // Rapid taps must never call reload() — overlapping reload() on the
      // same isolate instance can stall and freeze every later read/write.
      await prefs.reload();
      unawaited(TapHistoryStore.instance.migrateFromPrefs(prefs));
      await ShiftCounterStore.instance.migrateFromPrefs(prefs);
      if (!mounted) return;
      final stored = await ShiftCounterStore.instance.read();
      if (!mounted) return;
      final accepted = stored.accepted;
      final rejected = stored.rejected;
      final completed = stored.completed;
      final orientation = PillOrientation.fromPrefs(prefs);
      // A settings push that landed while this load was in flight is newer
      // than anything `prefs` holds — the reload above may have run before
      // home's write reached disk. Don't roll it back.
      final applySettings = !_settingsPushed;
      if (applySettings) _updateLang(prefs);
      final autoComplete = applySettings
          ? (prefs.getBool(_keyAutoComplete) ?? false)
          : _autoComplete;
      final reqRate = applySettings ? _parseReqRate(prefs) : _requiredAcceptRate;
      setState(() {
        _accepted = accepted;
        _rejected = rejected;
        _completed = completed;
        _autoComplete = autoComplete;
        _requiredAcceptRate = reqRate;
        _orientation = orientation;
      });
    } catch (e, s) {
      loge('overlay startup load failed', name: 'overlay', error: e, stack: s);
    }
  }

  @override
  void dispose() {
    _rejectPulseTimer?.cancel();
    _rejectPulseTimer = null;
    final hadPending = _persistTimer?.isActive ?? false;
    _persistTimer?.cancel();
    _persistTimer = null;
    if (hadPending) {
      unawaited(_persistCounts());
    }
    _syncSub?.cancel();
    super.dispose();
  }

  void _applyRemoteCounters(OverlayCounters counters) {
    if (_hasUnpersistedTaps) return;
    if (!mounted) return;
    if (counters.accepted == _accepted &&
        counters.rejected == _rejected &&
        counters.completed == _completed) {
      return;
    }
    setState(() {
      _accepted = counters.accepted;
      _rejected = counters.rejected;
      _completed = counters.completed;
    });
  }

  /// Applies settings pushed by the home isolate. Authoritative over anything
  /// this isolate could read from its own prefs cache, which is frozen at the
  /// last [SharedPreferences.reload] — i.e. at overlay startup.
  void _applyRemoteSettings(OverlaySettings settings) {
    if (!mounted) return;
    _settingsPushed = true;
    final lang = AppLang.values.firstWhere(
      (l) => l.name == settings.lang,
      orElse: () => S.lang,
    );
    final reqRate = _reqRateForTier(settings.goalTier);
    if (lang == S.lang &&
        reqRate == _requiredAcceptRate &&
        settings.autoComplete == _autoComplete) {
      return;
    }
    S.setLang(lang);
    setState(() {
      _requiredAcceptRate = reqRate;
      _autoComplete = settings.autoComplete;
    });
  }

  Future<void> _loadCounts() async {
    if (_hasUnpersistedTaps) return;
    try {
      // Counters only, and no prefs.reload(): this runs on the tap-recovery
      // path. Lang / goal / autoComplete come from startup plus the
      // settings-changed push — re-reading them from this isolate's stale
      // prefs cache here would silently revert a pushed setting.
      final stored = await ShiftCounterStore.instance.read();
      if (!mounted || _hasUnpersistedTaps) return;
      final accepted = stored.accepted;
      final rejected = stored.rejected;
      final completed = stored.completed;
      if (accepted == _accepted &&
          rejected == _rejected &&
          completed == _completed) {
        return;
      }
      setState(() {
        _accepted = accepted;
        _rejected = rejected;
        _completed = completed;
      });
    } catch (e, s) {
      loge('overlay load failed', name: 'overlay', error: e, stack: s);
    }
  }

  void _updateLang(SharedPreferences prefs) {
    if (prefs.containsKey('appLanguage')) {
      final langStr = prefs.getString('appLanguage')!;
      final lang = AppLang.values.firstWhere(
        (l) => l.name == langStr,
        orElse: () => AppLang.en,
      );
      S.setLang(lang);
    } else {
      final lang = S.langFromLocale(
        WidgetsBinding.instance.platformDispatcher.locale,
      );
      S.setLang(lang);
    }
  }

  /// Mirrors the native accept/reject waveforms: one pulse for accept, two for
  /// reject. HapticFeedback has no waveform API, so the double is two impacts
  /// spaced by the same gap the native pattern uses. This is the only
  /// confirmation a driver gets with their eyes on the road, so the two must
  /// stay distinguishable.
  void _fireTapHaptic(bool accepted) {
    _rejectPulseTimer?.cancel();
    if (accepted) {
      unawaited(HapticFeedback.mediumImpact());
      return;
    }
    unawaited(HapticFeedback.lightImpact());
    _rejectPulseTimer = Timer(_rejectPulseGap, () {
      unawaited(HapticFeedback.lightImpact());
    });
  }

  Future<void> _increment(String key, {bool haptic = true}) async {
    final accepted = key == _keyAccepted;

    logd('overlay tap complete key=$key', name: 'overlay');

    if (haptic) _fireTapHaptic(accepted);

    setState(() {
      _tapSeq++;
      if (accepted) {
        _accepted = (_accepted + 1).clamp(0, 99999);
        if (_autoComplete) {
          _completed = (_completed + 1).clamp(0, 99999);
        }
      } else {
        _rejected = (_rejected + 1).clamp(0, 99999);
      }
    });

    unawaited(
      TapHistoryStore.instance.append(accepted ? 'accepted' : 'rejected'),
    );
    _schedulePersist();
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      unawaited(_persistCounts());
    });
  }

  Future<void> _persistCounts() async {
    _persistTimer?.cancel();
    _persistTimer = null;
    try {
      await ShiftCounterStore.instance.merge(
        accepted: _accepted,
        rejected: _rejected,
        completed: _completed,
      );
      unawaited(
        OverlaySync.notifyCountersChanged(
          accepted: _accepted,
          rejected: _rejected,
          completed: _completed,
        ),
      );
    } catch (e, s) {
      loge('overlay write failed', name: 'overlay', error: e, stack: s);
      await _loadCounts();
    }
  }

  void _onPointerDown(PointerDownEvent event) {
    _trackedPointer = event.pointer;
    _pointerDownPos = event.position;
    _pointerIsDrag = false;
    logd('overlay pointer down id=${event.pointer}', name: 'overlay');
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_trackedPointer != event.pointer || _pointerDownPos == null) return;
    if (_pointerIsDrag) return;
    if ((event.position - _pointerDownPos!).distance > kTouchSlop) {
      _pointerIsDrag = true;
      logd(
        'overlay pan start id=${event.pointer} slop=$kTouchSlop',
        name: 'overlay',
      );
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_trackedPointer != event.pointer) return;
    logd(
      _pointerIsDrag
          ? 'overlay pan end id=${event.pointer}'
          : 'overlay pointer up id=${event.pointer}',
      name: 'overlay',
    );
    _trackedPointer = null;
    _pointerDownPos = null;
    _pointerIsDrag = false;
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_trackedPointer != event.pointer) return;
    logd('overlay pan cancel id=${event.pointer}', name: 'overlay');
    _trackedPointer = null;
    _pointerDownPos = null;
    _pointerIsDrag = false;
  }

  @override
  Widget build(BuildContext context) {
    final vertical = _orientation.isVertical;
    final width = vertical
        ? OverlayWidget.verticalPillWidthDp
        : OverlayWidget.pillWidthDp;
    final height = vertical
        ? OverlayWidget.verticalPillHeightDp
        : OverlayWidget.pillHeightDp;
    final children = <Widget>[
      _CircleBtn(
        size: _btnSizeDp,
        icon: Icons.remove_rounded,
        color: _crimson,
        onTap: () => unawaited(_increment(_keyRejected)),
      ),
      SizedBox(
        width: vertical ? 0 : _btnTextGapDp,
        height: vertical ? OverlayWidget.verticalGapDp : 0,
      ),
      _TapPop(
        key: ValueKey<int>(_tapSeq),
        child: _AcceptRateDisplay(
          text: _formatAcceptRate(_acceptanceRate),
          color: _acceptRateColor,
          width: vertical ? _verticalCenterTextWidthDp : _centerTextWidthDp,
          height: vertical ? OverlayWidget.verticalRateSlotDp : null,
        ),
      ),
      SizedBox(
        width: vertical ? 0 : _btnTextGapDp,
        height: vertical ? OverlayWidget.verticalGapDp : 0,
      ),
      _CircleBtn(
        size: _btnSizeDp,
        icon: Icons.add_rounded,
        color: _emerald,
        onTap: () => unawaited(_increment(_keyAccepted)),
      ),
    ];

    return Align(
      alignment: Alignment.topLeft,
      child: Material(
        type: MaterialType.transparency,
        color: Colors.transparent,
        child: Listener(
          behavior: HitTestBehavior.deferToChild,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: Material(
            color: _pillBg,
            elevation: 8,
            shadowColor: Colors.black,
            clipBehavior: Clip.antiAlias,
            shape: const StadiumBorder(
              side: BorderSide(color: _pillBorder, width: 1),
            ),
            child: SizedBox(
              width: width,
              height: height,
              child: Padding(
                padding: vertical
                    ? const EdgeInsets.all(OverlayWidget.verticalInsetDp)
                    : const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: 6,
                      ),
                child: vertical
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: children,
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: children,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A one-shot scale pop, restarted by giving it a new key. Nothing schedules
/// it: `TweenAnimationBuilder` runs begin -> end once on first build, so the
/// pill still holds no controller and produces no frames once it has settled.
class _TapPop extends StatelessWidget {
  const _TapPop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 1.14, end: 1.0),
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutBack,
      builder: (BuildContext context, double scale, Widget? child) {
        return Transform.scale(scale: scale, child: child);
      },
      child: child,
    );
  }
}

class _CircleBtn extends StatelessWidget {
  const _CircleBtn({
    required this.size,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final double size;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.5;
    return RepaintBoundary(
      child: Material(
        color: color.withValues(alpha: 0.20),
        shape: CircleBorder(
          side: BorderSide(color: color.withValues(alpha: 0.55), width: 1.5),
        ),
        child: InkWell(
          onTap: () {
            logd('overlay tap complete', name: 'overlay');
            onTap();
          },
          onTapDown: (_) => logd('overlay tap start', name: 'overlay'),
          onTapCancel: () => logd('overlay tap cancel', name: 'overlay'),
          customBorder: const CircleBorder(),
          splashColor: color.withValues(alpha: 0.35),
          highlightColor: color.withValues(alpha: 0.15),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Icon(icon, color: Colors.white, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}

class _AcceptRateDisplay extends StatelessWidget {
  const _AcceptRateDisplay({
    required this.text,
    required this.color,
    required this.width,
    this.height,
  });

  final String text;
  final Color color;
  final double width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: width,
        height: height,
        child: Align(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              text,
              maxLines: 1,
              softWrap: false,
              textAlign: TextAlign.center,
              style: T.rateFor(color),
            ),
          ),
        ),
      ),
    );
  }
}
