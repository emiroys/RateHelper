import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
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

  static const double _pillWidthDp = OverlayWidget.pillWidthDp;
  static const double _pillHeightDp = OverlayWidget.pillHeightDp;
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
    unawaited(_loadCountsOnStartup());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncNativeWindowSize());
    });
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
        color: _pillBg,
        elevation: 8,
        shadowColor: Colors.black,
        shape: const StadiumBorder(
          side: BorderSide(color: _pillBorder, width: 1),
        ),
        child: SizedBox(
          width: _pillWidthDp,
          height: _pillHeightDp,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _CircleBtn(
                  size: _btnSizeDp,
                  icon: Icons.remove_rounded,
                  color: _crimson,
                  onTap: () => unawaited(_increment(_keyRejected)),
                ),
                const SizedBox(width: _btnTextGapDp),
                _AcceptRateDisplay(
                  text: _formatAcceptRate(_acceptanceRate),
                  color: _acceptRateColor,
                  width: _centerTextWidthDp,
                ),
                const SizedBox(width: _btnTextGapDp),
                _CircleBtn(
                  size: _btnSizeDp,
                  icon: Icons.add_rounded,
                  color: _emerald,
                  onTap: () => unawaited(_increment(_keyAccepted)),
                ),
              ],
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
          onTap: onTap,
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
