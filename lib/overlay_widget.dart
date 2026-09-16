import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
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

  /// Portrait (vertical) pill — swapped so the native window still clips
  /// tightly around the visible widget.
  static const double verticalPillWidthDp = pillHeightDp;
  static const double verticalPillHeightDp = pillWidthDp;

  static const int nativeWindowWidthDp = 276;
  static const int nativeWindowHeightDp = 80;

  static int windowWidthDp(PillOrientation orientation) => orientation.isVertical
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

  static const _crimson = AppColors.crimson;
  static const _emerald = AppColors.emerald;
  static const _amber = AppColors.amber;
  static const _pillBg = AppColors.overlayPill;
  static const _pillBorder = AppColors.strongBorder;

  static const double _centerTextWidthDp = 100;
  static const double _btnSizeDp = 68;
  static const double _btnTextGapDp = 12;

  SharedPreferences? _prefs;
  StreamSubscription<dynamic>? _syncSub;
  Timer? _persistTimer;

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
        } else if (event is Map && event['action'] == 'media_key_increment') {
          final keyStr = event['key'];
          final key = keyStr == 'accepted' ? _keyAccepted : _keyRejected;
          unawaited(_increment(key));
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

  double? _parseReqRate(SharedPreferences prefs) {
    final goalStr = prefs.getString('trip_goal_tier');
    if (goalStr == 'tier0') return null;
    if (goalStr == 'tier2') return 70.0;
    if (goalStr == 'tier3') return 60.0;
    if (goalStr == 'tier4') return 50.0;
    return 80.0;
  }

  Future<void> _loadCountsOnStartup() async {
    try {
      _prefs = null;
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      // Startup-only reload for lang / goal / autoComplete / layout.
      // Rapid taps must never call reload() — overlapping reload() on the
      // same isolate instance can stall and freeze every later read/write.
      await prefs.reload();
      unawaited(TapHistoryStore.instance.migrateFromPrefs(prefs));
      await ShiftCounterStore.instance.migrateFromPrefs(prefs);
      if (!mounted) return;
      _updateLang(prefs);
      final stored = await ShiftCounterStore.instance.read();
      if (!mounted) return;
      final accepted = stored.accepted;
      final rejected = stored.rejected;
      final completed = stored.completed;
      final autoComplete = prefs.getBool(_keyAutoComplete) ?? false;
      final reqRate = _parseReqRate(prefs);
      final orientation = PillOrientation.fromPrefs(prefs);
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

  Future<void> _loadCounts() async {
    if (_hasUnpersistedTaps) return;
    try {
      final prefs = await _getPrefs();
      // Counters live in ShiftCounterStore — no prefs.reload() on the
      // hot path. Lang/goal/autoComplete are home-only and were loaded
      // at overlay startup.
      final stored = await ShiftCounterStore.instance.read();
      if (!mounted || _hasUnpersistedTaps) return;
      _updateLang(prefs);
      final accepted = stored.accepted;
      final rejected = stored.rejected;
      final completed = stored.completed;
      final autoComplete = prefs.getBool(_keyAutoComplete) ?? false;
      final reqRate = _parseReqRate(prefs);
      final orientation = PillOrientation.fromPrefs(prefs);
      if (accepted == _accepted &&
          rejected == _rejected &&
          completed == _completed &&
          autoComplete == _autoComplete &&
          reqRate == _requiredAcceptRate &&
          orientation == _orientation) {
        return;
      }
      setState(() {
        _accepted = accepted;
        _rejected = rejected;
        _completed = completed;
        _autoComplete = autoComplete;
        _requiredAcceptRate = reqRate;
        _orientation = orientation;
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

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> _increment(String key) async {
    final accepted = key == _keyAccepted;

    logd('overlay tap complete key=$key', name: 'overlay');

    setState(() {
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
    logd(
      'overlay pointer down id=${event.pointer}',
      name: 'overlay',
    );
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
    logd(
      'overlay pan cancel id=${event.pointer}',
      name: 'overlay',
    );
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
        height: vertical ? _btnTextGapDp : 0,
      ),
      _AcceptRateDisplay(
        text: _formatAcceptRate(_acceptanceRate),
        color: _acceptRateColor,
        width: vertical ? _btnSizeDp : _centerTextWidthDp,
      ),
      SizedBox(
        width: vertical ? 0 : _btnTextGapDp,
        height: vertical ? _btnTextGapDp : 0,
      ),
      _CircleBtn(
        size: _btnSizeDp,
        icon: Icons.add_rounded,
        color: _emerald,
        onTap: () => unawaited(_increment(_keyAccepted)),
      ),
    ];

    return Material(
      type: MaterialType.transparency,
      color: Colors.transparent,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: Material(
          color: _pillBg,
          elevation: 8,
          shadowColor: Colors.black,
          shape: const StadiumBorder(
            side: BorderSide(color: _pillBorder, width: 1),
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: Padding(
              padding: vertical
                  ? const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: AppSpacing.sm,
                    )
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
  });

  final String text;
  final Color color;
  final double width;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: width,
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
