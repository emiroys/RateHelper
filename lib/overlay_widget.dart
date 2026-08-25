import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'format_rate.dart';
import 'l10n.dart';
import 'log.dart';
import 'overlay_sync.dart';
import 'shift_counter_store.dart';
import 'tap_history_store.dart';

class OverlayWidget extends StatefulWidget {
  const OverlayWidget({super.key});

  /// Native overlay window size in dp — must match the visible pill.
  static const int nativeWindowWidthDp = 276;
  static const int nativeWindowHeightDp = 80;

  static const double pillWidthDp = 276;
  static const double pillHeightDp = 80;

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget>
    with SingleTickerProviderStateMixin {
  static const _keyAccepted = 'acceptedRequests';
  static const _keyRejected = 'rejectedRequests';
  static const _keyAutoComplete = 'autoCompleteTrips';
  static const _persistDebounce = Duration(milliseconds: 300);

  static const _crimson = AppColors.crimson;
  static const _emerald = AppColors.emerald;
  static const _amber = AppColors.amber;
  static const _pillBorder = AppColors.hairlineStrong;

  static const double _pillWidthDp = OverlayWidget.pillWidthDp;
  static const double _pillHeightDp = OverlayWidget.pillHeightDp;
  static const double _centerTextWidthDp = 100;
  static const double _btnSizeDp = 68;
  static const double _btnTextGapDp = 12;
  static const Duration _tapPulseDuration = Duration(milliseconds: 220);

  SharedPreferences? _prefs;
  late final AnimationController _tapPulse;
  bool _lastTapAccepted = true;
  StreamSubscription<dynamic>? _syncSub;
  Timer? _persistTimer;

  int _accepted = 0;
  int _rejected = 0;
  int _completed = 0;
  bool _autoComplete = false;
  double? _requiredAcceptRate = 80.0;
  bool _sun = false;

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
    return formatRatePercent(rate);
  }

  /// 0 → 1 → 0 over [_tapPulseDuration] so the flash peaks mid-tap.
  double get _tapFlash {
    final t = _tapPulse.value;
    return t <= 0.5 ? t * 2.0 : (1.0 - t) * 2.0;
  }

  @override
  void initState() {
    super.initState();
    _tapPulse = AnimationController(vsync: this, duration: _tapPulseDuration);
    unawaited(_loadCountsOnStartup());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncNativeWindowSize());
    });
    try {
      _syncSub = FlutterOverlayWindow.overlayListener.listen((event) {
        final sun = OverlaySync.sunModeFromEvent(event);
        if (sun != null && sun != _sun && mounted) {
          setState(() => _sun = sun);
        }
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

  Future<void> _syncNativeWindowSize() async {
    try {
      await FlutterOverlayWindow.resizeOverlay(
        OverlayWidget.nativeWindowWidthDp,
        OverlayWidget.nativeWindowHeightDp,
        true,
      );
    } catch (e, s) {
      loge('overlay resize failed', name: 'overlay', error: e, stack: s);
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
      setState(() {
        _accepted = accepted;
        _rejected = rejected;
        _completed = completed;
        _autoComplete = autoComplete;
        _requiredAcceptRate = reqRate;
      });
    } catch (e, s) {
      loge('overlay startup load failed', name: 'overlay', error: e, stack: s);
    }
  }

  @override
  void dispose() {
    _tapPulse.dispose();
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
      if (accepted == _accepted &&
          rejected == _rejected &&
          completed == _completed &&
          autoComplete == _autoComplete &&
          reqRate == _requiredAcceptRate) {
        return;
      }
      setState(() {
        _accepted = accepted;
        _rejected = rejected;
        _completed = completed;
        _autoComplete = autoComplete;
        _requiredAcceptRate = reqRate;
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
    }
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<void> _increment(String key) async {
    final accepted = key == _keyAccepted;

    logd('overlay tap', name: 'overlay');

    if (accepted) {
      HapticFeedback.lightImpact();
    } else {
      HapticFeedback.mediumImpact();
    }
    _lastTapAccepted = accepted;
    unawaited(_tapPulse.forward(from: 0));

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

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      color: Colors.transparent,
      child: Material(
        color: AppColors.overlayPillFor(_sun),
        elevation: 8,
        shadowColor: Colors.black,
        shape: StadiumBorder(
          side: BorderSide(
            color: _sun ? const Color(0x99000000) : _pillBorder,
            width: 1.4,
          ),
        ),
        child: SizedBox(
          width: _pillWidthDp,
          height: _pillHeightDp,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: AnimatedBuilder(
              animation: _tapPulse,
              builder: (context, _) {
                final flash = _tapFlash;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _CircleBtn(
                      size: _btnSizeDp,
                      icon: Icons.remove_rounded,
                      color: AppColors.crimsonFor(_sun),
                      flash: _lastTapAccepted ? 0 : flash,
                      filled: _sun,
                      onTap: () => unawaited(_increment(_keyRejected)),
                    ),
                    const SizedBox(width: _btnTextGapDp),
                    _AcceptRateDisplay(
                      text: _formatAcceptRate(_acceptanceRate),
                      ratio: '$_accepted/${_accepted + _rejected}',
                      color: AppColors.stateFor(_acceptRateColor, _sun),
                      width: _centerTextWidthDp,
                      scale: 1.0 + 0.08 * flash,
                      sun: _sun,
                    ),
                    const SizedBox(width: _btnTextGapDp),
                    _CircleBtn(
                      size: _btnSizeDp,
                      icon: Icons.add_rounded,
                      color: AppColors.emeraldFor(_sun),
                      flash: _lastTapAccepted ? flash : 0,
                      filled: _sun,
                      onTap: () => unawaited(_increment(_keyAccepted)),
                    ),
                  ],
                );
              },
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
    this.flash = 0,
    this.filled = false,
  });

  final double size;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  /// 0–1 pulse; fill lerps 0.28 → 0.45 at the peak.
  final double flash;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final iconSize = size * 0.5;
    final fill = filled
        ? Color.lerp(color, Colors.white, 0.18 * flash)!
        : color.withValues(alpha: 0.28 + 0.17 * flash);
    return RepaintBoundary(
      child: Material(
        color: fill,
        shape: CircleBorder(
          side: BorderSide(
            color: color.withValues(alpha: filled ? 1 : 0.55),
            width: 1.5,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          splashColor: color.withValues(alpha: 0.35),
          highlightColor: color.withValues(alpha: 0.15),
          child: SizedBox(
            width: size,
            height: size,
            child: Center(
              child: Icon(
                icon,
                color: filled ? Colors.white : color,
                size: iconSize,
              ),
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
    required this.ratio,
    required this.color,
    required this.width,
    this.scale = 1.0,
    this.sun = false,
  });

  final String text;
  final String ratio;
  final Color color;
  final double width;
  final double scale;
  final bool sun;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: width,
        child: Align(
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Transform.scale(
                  scale: scale,
                  child: Text(
                    text,
                    maxLines: 1,
                    softWrap: false,
                    textAlign: TextAlign.center,
                    style: T.rateOverlayFor(color, sun: sun),
                  ),
                ),
                Text(
                  ratio,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: T.overlayRatioFor(sun: sun),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
