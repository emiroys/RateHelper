import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'log.dart';
import 'overlay_sync.dart';

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
  static const _keyCompleted = 'completedTrips';
  static const _keyAutoComplete = 'autoCompleteTrips';
  static const _keyTapHistory = 'tapHistory';
  static const _maxTapHistory = 500;

  static const _crimson = Color(0xFFEF4444);
  static const _emerald = Color(0xFF10B981);
  static const _pillBg = Color(0xE6161616);
  static const _pillBorder = Color(0x33FFFFFF);

  static const double _pillWidthDp = OverlayWidget.pillWidthDp;
  static const double _pillHeightDp = OverlayWidget.pillHeightDp;
  static const double _centerTextWidthDp = 100;
  static const double _btnSizeDp = 68;
  static const double _btnTextGapDp = 12;

  SharedPreferences? _prefs;
  StreamSubscription<dynamic>? _syncSub;
  bool _incrementInFlight = false;

  int _accepted = 0;
  int _rejected = 0;

  double get _acceptanceRate {
    final total = _accepted + _rejected;
    if (total == 0) return 100.0;
    return (_accepted / total) * 100;
  }

  Color get _acceptRateColor =>
      _acceptanceRate > 80.0 ? _emerald : _crimson;

  String _formatAcceptRate(double rate) {
    if (_accepted == 0 && _rejected == 0) {
      return '%100';
    }
    final rounded = (rate * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return '%${rounded.toInt()}';
    }
    return '%${rounded.toStringAsFixed(1)}';
  }

  @override
  void initState() {
    super.initState();
    unawaited(_loadCountsOnStartup());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_syncNativeWindowSize());
    });
    _syncSub = FlutterOverlayWindow.overlayListener.listen((event) {
      if (OverlaySync.shouldReloadCounters(event)) {
        unawaited(_loadCounts());
      }
    });
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

  Future<void> _loadCountsOnStartup() async {
    try {
      _prefs = null;
      final prefs = await SharedPreferences.getInstance();
      _prefs = prefs;
      await prefs.reload();
      if (!mounted) return;
      final accepted = prefs.getInt(_keyAccepted) ?? 0;
      final rejected = prefs.getInt(_keyRejected) ?? 0;
      setState(() {
        _accepted = accepted;
        _rejected = rejected;
      });
    } catch (e, s) {
      loge('overlay startup load failed', name: 'overlay', error: e, stack: s);
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    super.dispose();
  }

  Future<void> _loadCounts() async {
    if (_incrementInFlight) return;
    try {
      final prefs = await _getPrefs();
      await prefs.reload();
      if (!mounted || _incrementInFlight) return;
      final accepted = prefs.getInt(_keyAccepted) ?? 0;
      final rejected = prefs.getInt(_keyRejected) ?? 0;
      if (accepted == _accepted && rejected == _rejected) return;
      setState(() {
        _accepted = accepted;
        _rejected = rejected;
      });
    } catch (e, s) {
      loge('overlay load failed', name: 'overlay', error: e, stack: s);
    }
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  String _formatLocalTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}';
  }

  Future<void> _appendTapHistory(SharedPreferences prefs, String type) async {
    final now = DateTime.now();
    final entry = <String, String>{
      'type': type,
      'timestamp': now.toIso8601String(),
      'localTime': _formatLocalTime(now),
    };

    List<dynamic> list;
    final raw = prefs.getString(_keyTapHistory);
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        list = decoded is List ? List<dynamic>.from(decoded) : <dynamic>[];
      } catch (_) {
        list = <dynamic>[];
      }
    } else {
      list = <dynamic>[];
    }

    list.add(entry);
    if (list.length > _maxTapHistory) {
      list = list.sublist(list.length - _maxTapHistory);
    }
    await prefs.setString(_keyTapHistory, jsonEncode(list));
  }

  Future<void> _increment(String key) async {
    if (_incrementInFlight) return;
    _incrementInFlight = true;
    final accepted = key == _keyAccepted;

    logd('overlay tap', name: 'overlay');

    try {
      final prefs = await _getPrefs();
      await prefs.reload();

      var nextAccepted = prefs.getInt(_keyAccepted) ?? 0;
      var nextRejected = prefs.getInt(_keyRejected) ?? 0;
      if (accepted) {
        nextAccepted = (nextAccepted + 1).clamp(0, 99999);
      } else {
        nextRejected = (nextRejected + 1).clamp(0, 99999);
      }

      if (!mounted) return;
      setState(() {
        _accepted = nextAccepted;
        _rejected = nextRejected;
      });

      await _appendTapHistory(
        prefs,
        accepted ? 'accepted' : 'rejected',
      );

      await prefs.setInt(_keyAccepted, nextAccepted);
      await prefs.setInt(_keyRejected, nextRejected);

      if (accepted && (prefs.getBool(_keyAutoComplete) ?? false)) {
        final completed = prefs.getInt(_keyCompleted) ?? 0;
        await prefs.setInt(
          _keyCompleted,
          (completed + 1).clamp(0, 99999),
        );
      }
    } catch (e, s) {
      loge('overlay write failed', name: 'overlay', error: e, stack: s);
      await _loadCounts();
    } finally {
      _incrementInFlight = false;
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
    return Material(
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
    return SizedBox(
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
            style: GoogleFonts.dmSans(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: color,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}
