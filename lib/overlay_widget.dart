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
import 'services/backup_service.dart';
import 'shade_controls.dart';
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
  const OverlayWidget({
    super.key,
    this.initialOrientation,
    this.initialShowCancel = false,
    this.initialCollapsed = false,
    this.initialHidden = false,
  });

  /// When set (tests / first-frame), used until prefs load.
  final PillOrientation? initialOrientation;

  /// When true, the first frame shows the cancellation button. Prefs win
  /// once [cancelButtonPrefsKey] has been read.
  final bool initialShowCancel;

  /// When true, the first frame draws the "R" bubble and the window shrinks
  /// to it right after. `overlayMain` reads [collapsedPrefsKey] before
  /// `runApp` so a collapsed pill does not flash open on every reopen.
  final bool initialCollapsed;

  /// Shade-only mode at startup ([ShadeControls.pillHidden] from prefs).
  /// Home opened the native window hidden to match, so nothing flashes.
  final bool initialHidden;

  /// SharedPreferences flag for the optional third button. Default off.
  static const String cancelButtonPrefsKey = 'overlay_show_cancel_button';

  /// SharedPreferences flag: pill collapsed to the "R" bubble. Written by
  /// the overlay isolate only.
  static const String collapsedPrefsKey = 'overlay_pill_collapsed';

  /// Collapsed bubble — the native window shrinks to exactly this square so
  /// the rest of the old pill area passes touches to the app underneath.
  static const double bubbleSizeDp = 48;

  /// Landscape (horizontal) pill — native window equals the visible widget.
  static const double pillWidthDp = 276;
  static const double pillHeightDp = 80;

  static const double btnSizeDp = 68;

  /// Smaller than [btnSizeDp], still a full 48dp target. Appended on the
  /// long axis only, so a horizontal pill grows in width and a vertical
  /// pill grows in height.
  static const double cancelBtnSizeDp = 48;
  static const double cancelGapDp = 12;

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

  /// Layout values that must be known before the overlay's first frame.
  /// Native creates its window from the same persisted pair, so seeding the
  /// widget with them prevents a horizontal/vertical or cancel-size mismatch
  /// while the overlay isolate finishes its full startup load.
  static ({PillOrientation orientation, bool showCancel}) layoutFromPrefs(
    SharedPreferences prefs,
  ) => (
    orientation: PillOrientation.fromPrefs(prefs),
    showCancel: prefs.getBool(cancelButtonPrefsKey) ?? false,
  );

  static int windowWidthDp(
    PillOrientation orientation, {
    bool showCancel = false,
  }) {
    if (orientation.isVertical) return verticalPillWidthDp.round();
    final width = showCancel
        ? pillWidthDp + cancelGapDp + cancelBtnSizeDp
        : pillWidthDp;
    return width.round();
  }

  static int windowHeightDp(
    PillOrientation orientation, {
    bool showCancel = false,
  }) {
    if (!orientation.isVertical) return pillHeightDp.round();
    final height = showCancel
        ? verticalPillHeightDp + verticalGapDp + cancelBtnSizeDp
        : verticalPillHeightDp;
    return height.round();
  }

  @override
  State<OverlayWidget> createState() => _OverlayWidgetState();
}

class _OverlayWidgetState extends State<OverlayWidget>
    with WidgetsBindingObserver {
  static const _keyAccepted = 'acceptedRequests';
  static const _keyRejected = 'rejectedRequests';
  static const _keyAutoComplete = 'autoCompleteTrips';
  static const _persistDebounce = Duration(milliseconds: 300);

  /// Gap between the two reject pulses, matching REJECT_PATTERN in
  /// MediaKeyAccessibilityService so both input paths feel identical.
  static const _rejectPulseGap = Duration(milliseconds: 70);

  /// Cap on the native resize round-trip. An APK whose plugin has no handler
  /// must not leave [_windowResizeBusy] stuck and the bubble dead.
  static const _resizeTimeout = Duration(milliseconds: 1500);

  /// Cap on waiting for the grown window's metrics before drawing the pill.
  static const _viewSizeWait = Duration(milliseconds: 250);

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
  late bool _notificationControls = widget.initialHidden;
  late bool _hidePill = widget.initialHidden;
  double? _requiredAcceptRate = 80.0;

  /// What the native window is (or is being switched to). Counters, taps and
  /// the notification run the same either way; only drawing stops.
  late bool _windowHidden = widget.initialHidden;

  final ShadeNotificationThrottle _shade = ShadeNotificationThrottle(
    send: FlutterOverlayWindow.updateNotification,
  );
  late PillOrientation _orientation =
      widget.initialOrientation ?? PillOrientation.horizontal;
  late bool _showCancelButton = widget.initialShowCancel;

  /// UI state only. Counters, tap log, persistence, pings and steering-wheel
  /// increments run the same whether the pill or the bubble is showing.
  late bool _collapsed = widget.initialCollapsed;

  /// A collapse/expand is between "draw" and "native window resized".
  /// Taps on the percentage or bubble are ignored until it settles.
  bool _windowResizeBusy = false;

  /// The driver toggled before the startup prefs read landed; that read is
  /// older than the tap and must not undo it.
  bool _collapseToggledByUser = false;

  Completer<void>? _viewSizeWaiter;
  Size _viewSizeTarget = Size.zero;

  /// Deltas waiting for the debounced write. Absolute merges from this isolate
  /// would clobber Home's concurrent applyDelta, so only deltas go to disk.
  int _unpersistedAccepted = 0;
  int _unpersistedRejected = 0;
  int _unpersistedCompleted = 0;
  int _unpersistedCancels = 0;
  Future<bool>? _inFlightPersist;

  int? _trackedPointer;
  Offset? _pointerDownPos;
  bool _pointerIsDrag = false;

  bool get _hasUnpersistedTaps =>
      (_persistTimer?.isActive ?? false) ||
      _inFlightPersist != null ||
      _unpersistedAccepted != 0 ||
      _unpersistedRejected != 0 ||
      _unpersistedCompleted != 0 ||
      _unpersistedCancels != 0;

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
    WidgetsBinding.instance.addObserver(this);
    if (_collapsed || _windowHidden) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_syncWindowOnStartup());
      });
    }
    unawaited(_loadCountsOnStartup());
    FlutterOverlayWindow.setMessageReplyHandler(_handleNativeMessage);
    try {
      _syncSub = FlutterOverlayWindow.overlayListener.listen((event) {
        OverlaySync.deliver(
          event,
          onCounters: _applyRemoteCounters,
          onCountersReloadFromStore: () => unawaited(_loadCounts()),
          onSettings: _applyRemoteSettings,
          // Fallback when [_handleNativeMessage] is unset (tests) or returns
          // null. The live native path ACKs only after persist in the reply
          // handler, which consumes the message before it reaches here.
          onMediaKey: (target) {
            final key = target == 'accepted' ? _keyAccepted : _keyRejected;
            unawaited(_increment(key, haptic: false));
          },
        );
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

  /// Answers native messages that must not be echoed until work finishes.
  ///
  /// Returns `true` only after pending deltas are persisted so TapDelivery
  /// and OverlayService can treat the reply as a real ACK.
  Future<Object?> _handleNativeMessage(Object? message) async {
    try {
      if (OverlaySync.isFlushRequest(message)) {
        return await _persistCounts();
      }
      final target = OverlaySync.mediaKeyTargetFromEvent(message);
      if (target == null) return null;
      final key = target == 'accepted' ? _keyAccepted : _keyRejected;
      // Native already fired its own accept/reject waveform before handing
      // the tap over — a second buzz here would blur the rhythm.
      await _increment(key, haptic: false);
      return await _persistCounts();
    } catch (e, s) {
      loge(
        'overlay native message failed',
        name: 'overlay',
        error: e,
        stack: s,
      );
      return false;
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
      await BackupService.recoverPendingRestoreIfNeeded(prefs: prefs);
      unawaited(TapHistoryStore.instance.migrateFromPrefs(prefs));
      await ShiftCounterStore.instance.migrateFromPrefs(prefs);
      if (!mounted) return;
      final stored = await ShiftCounterStore.instance.read();
      if (!mounted) return;
      final accepted = stored.accepted;
      final rejected = stored.rejected;
      final completed = stored.completed;
      final layout = OverlayWidget.layoutFromPrefs(prefs);
      final collapsed = prefs.getBool(OverlayWidget.collapsedPrefsKey) ?? false;
      // A settings push that landed while this load was in flight is newer
      // than anything `prefs` holds — the reload above may have run before
      // home's write reached disk. Don't roll it back.
      final applySettings = !_settingsPushed;
      if (applySettings) _updateLang(prefs);
      final autoComplete = applySettings
          ? (prefs.getBool(_keyAutoComplete) ?? false)
          : _autoComplete;
      final reqRate = applySettings
          ? _parseReqRate(prefs)
          : _requiredAcceptRate;
      final notificationControls = applySettings
          ? (prefs.getBool(ShadeControls.prefsKey) ?? false)
          : _notificationControls;
      final hidePill = applySettings
          ? (prefs.getBool(ShadeControls.hidePillPrefsKey) ?? false)
          : _hidePill;
      setState(() {
        _accepted = accepted;
        _rejected = rejected;
        _completed = completed;
        _autoComplete = autoComplete;
        _notificationControls = notificationControls;
        _hidePill = hidePill;
        _requiredAcceptRate = reqRate;
        _orientation = layout.orientation;
        _showCancelButton = layout.showCancel;
      });
      _syncShade();
      unawaited(_syncWindowHidden());
      // overlayMain already seeded [_collapsed] from the same key; this only
      // matters when that early read failed or timed out.
      if (collapsed != _collapsed &&
          !_windowResizeBusy &&
          !_collapseToggledByUser) {
        unawaited(_setCollapsed(collapsed, persist: false));
      }
    } catch (e, s) {
      loge('overlay startup load failed', name: 'overlay', error: e, stack: s);
    }
  }

  @override
  void dispose() {
    FlutterOverlayWindow.setMessageReplyHandler(null);
    _rejectPulseTimer?.cancel();
    _rejectPulseTimer = null;
    _persistTimer?.cancel();
    _persistTimer = null;
    if (_hasUnpersistedTaps) {
      unawaited(_persistCounts());
    }
    _syncSub?.cancel();
    _shade.dispose();
    WidgetsBinding.instance.removeObserver(this);
    final waiter = _viewSizeWaiter;
    _viewSizeWaiter = null;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    final waiter = _viewSizeWaiter;
    if (waiter == null || waiter.isCompleted) return;
    if (_viewCovers(_viewSizeTarget)) waiter.complete();
  }

  double get _expandedWidthDp => OverlayWidget.windowWidthDp(
    _orientation,
    showCancel: _showCancelButton,
  ).toDouble();

  double get _expandedHeightDp => OverlayWidget.windowHeightDp(
    _orientation,
    showCancel: _showCancelButton,
  ).toDouble();

  /// Whether this isolate's FlutterView (= the native window) is at least
  /// [target] logical px. Native dp→px truncates, so allow 1px of slack.
  bool _viewCovers(Size target) {
    if (!mounted) return false;
    final view = View.maybeOf(context);
    if (view == null) return true;
    final size = view.physicalSize / view.devicePixelRatio;
    return size.width >= target.width - 1 && size.height >= target.height - 1;
  }

  Future<void> _awaitViewSize(Size target) async {
    if (_viewCovers(target)) return;
    final waiter = Completer<void>();
    _viewSizeWaiter = waiter;
    _viewSizeTarget = target;
    try {
      await waiter.future.timeout(_viewSizeWait);
    } on TimeoutException {
      logd('overlay view size wait timed out', name: 'overlay');
    } finally {
      if (identical(_viewSizeWaiter, waiter)) _viewSizeWaiter = null;
    }
  }

  /// Native window resize. Never throws: a failure is logged and reported as
  /// false so the caller can keep the UI consistent with the real window.
  Future<bool> _resizeWindow(double widthDp, double heightDp) async {
    try {
      final ok = await FlutterOverlayWindow.resizeOverlay(
        widthDp.round(),
        heightDp.round(),
      ).timeout(_resizeTimeout);
      if (ok != true) {
        loge(
          'overlay resize to ${widthDp.round()}x${heightDp.round()} '
          'returned $ok',
          name: 'overlay',
        );
      }
      return ok == true;
    } catch (e, s) {
      loge('overlay resize failed', name: 'overlay', error: e, stack: s);
      return false;
    }
  }

  /// Native show/hide. Never throws, like [_resizeWindow].
  Future<bool> _setNativeHidden(bool hidden) async {
    try {
      final ok = await FlutterOverlayWindow.setWindowHidden(
        hidden,
      ).timeout(_resizeTimeout);
      if (ok != true) {
        loge('overlay setWindowHidden($hidden) returned $ok', name: 'overlay');
      }
      return ok == true;
    } catch (e, s) {
      loge(
        'overlay setWindowHidden failed',
        name: 'overlay',
        error: e,
        stack: s,
      );
      return false;
    }
  }

  bool get _wantHidden => ShadeControls.pillHidden(
    notificationControls: _notificationControls,
    hidePill: _hidePill,
  );

  /// Home opens the window at pill size. Shade-only re-sends "hidden" (one
  /// idempotent call) so the window can never stay transparent but
  /// touchable; a collapsed pill shrinks to the bubble once that frame is
  /// on screen so no frame shows a clipped pill.
  Future<void> _syncWindowOnStartup() async {
    if (!mounted || _windowResizeBusy) return;
    _windowResizeBusy = true;
    try {
      if (_windowHidden) {
        await _setNativeHidden(true);
        return;
      }
      if (!mounted || !_collapsed) return;
      const bubble = OverlayWidget.bubbleSizeDp;
      final ok = await _resizeWindow(bubble, bubble);
      // The window is still pill-sized; show the pill that fits it.
      if (!ok && mounted) setState(() => _collapsed = false);
    } finally {
      _windowResizeBusy = false;
      unawaited(_syncWindowHidden());
    }
  }

  /// Brings the window in line with [_wantHidden]. Safe to call on every
  /// settings change: a no-op when they already match, and a request made
  /// while another window change runs is picked up when that one finishes.
  ///
  /// Hide: stop drawing, then shrink natively. Show: restore natively, fit
  /// the window to the pill or bubble, then draw — same order rule as
  /// [_setCollapsed], so drawn content never outgrows the window.
  Future<void> _syncWindowHidden() async {
    if (!mounted || _windowResizeBusy) return;
    final hide = _wantHidden;
    if (hide == _windowHidden) return;
    _windowResizeBusy = true;
    try {
      if (hide) {
        setState(() => _windowHidden = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        if (!await _setNativeHidden(true) && mounted) {
          setState(() => _windowHidden = false);
        }
        return;
      }
      if (!await _setNativeHidden(false) || !mounted) return;
      final width = _collapsed ? OverlayWidget.bubbleSizeDp : _expandedWidthDp;
      final height = _collapsed
          ? OverlayWidget.bubbleSizeDp
          : _expandedHeightDp;
      await _resizeWindow(width, height);
      if (!mounted) return;
      await _awaitViewSize(Size(width, height));
      if (!mounted) return;
      setState(() => _windowHidden = false);
    } finally {
      _windowResizeBusy = false;
      // Only a newer request re-runs; a failed native call must not loop.
      if (mounted && _wantHidden != hide) unawaited(_syncWindowHidden());
    }
  }

  void _onToggleCollapsedTap(bool collapse) {
    if (_windowResizeBusy) {
      logd('overlay collapse toggle ignored (busy)', name: 'overlay');
      return;
    }
    _collapseToggledByUser = true;
    unawaited(HapticFeedback.selectionClick());
    unawaited(_setCollapsed(collapse));
  }

  /// Order matters for touch pass-through and for flashes:
  /// collapse draws the bubble first, then shrinks the window; expand grows
  /// the window first, then draws the pill. The drawn content never needs
  /// more room than the window has, and a failed resize leaves the UI
  /// matching whatever size the window really is.
  Future<void> _setCollapsed(bool collapse, {bool persist = true}) async {
    if (!mounted || _windowResizeBusy || collapse == _collapsed) return;
    if (_windowHidden) {
      // Nothing on screen to resize; showing the window fits it to this.
      setState(() => _collapsed = collapse);
      if (persist) _persistCollapsed(collapse);
      return;
    }
    _windowResizeBusy = true;
    try {
      if (collapse) {
        setState(() => _collapsed = true);
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        const bubble = OverlayWidget.bubbleSizeDp;
        final ok = await _resizeWindow(bubble, bubble);
        if (!mounted) return;
        if (!ok) {
          setState(() => _collapsed = false);
          return;
        }
      } else {
        final width = _expandedWidthDp;
        final height = _expandedHeightDp;
        final ok = await _resizeWindow(width, height);
        if (!mounted || !ok) return;
        await _awaitViewSize(Size(width, height));
        if (!mounted) return;
        setState(() => _collapsed = false);
      }
      if (persist) _persistCollapsed(collapse);
    } finally {
      _windowResizeBusy = false;
      unawaited(_syncWindowHidden());
    }
  }

  void _persistCollapsed(bool collapsed) {
    unawaited(
      SharedPreferences.getInstance()
          .then((p) => p.setBool(OverlayWidget.collapsedPrefsKey, collapsed))
          .catchError((Object e, StackTrace s) {
            loge(
              'overlay collapsed pref write failed',
              name: 'overlay',
              error: e,
              stack: s,
            );
            return false;
          }),
    );
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
    _syncShade();
  }

  /// Hands the current rate to the notification. Cheap to call on every
  /// change: the throttle drops duplicates and posts at most once a second.
  void _syncShade() {
    _shade.update(
      _notificationControls
          ? ShadeControls.content(
              accepted: _accepted,
              rejected: _rejected,
              requiredRate: _requiredAcceptRate,
            )
          : null,
    );
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
    final notificationControls =
        settings.notificationControls ?? _notificationControls;
    final hidePill = settings.hidePill ?? _hidePill;
    if (lang == S.lang &&
        reqRate == _requiredAcceptRate &&
        settings.autoComplete == _autoComplete &&
        notificationControls == _notificationControls &&
        hidePill == _hidePill) {
      return;
    }
    S.setLang(lang);
    setState(() {
      _requiredAcceptRate = reqRate;
      _autoComplete = settings.autoComplete;
      _notificationControls = notificationControls;
      _hidePill = hidePill;
    });
    // Also covers a language switch: the notification strings change.
    _syncShade();
    unawaited(_syncWindowHidden());
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
      _syncShade();
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

  /// One heavy pulse. Accept is a single medium impact and reject is two
  /// quick light impacts, so a cancellation is a different hit entirely.
  void _fireCancelHaptic() {
    _rejectPulseTimer?.cancel();
    _rejectPulseTimer = null;
    unawaited(HapticFeedback.heavyImpact());
  }

  Future<void> _increment(String key, {bool haptic = true}) async {
    final accepted = key == _keyAccepted;

    logd('overlay tap complete key=$key', name: 'overlay');

    if (haptic) _fireTapHaptic(accepted);

    setState(() {
      _tapSeq++;
      if (accepted) {
        _accepted = (_accepted + 1).clamp(0, 99999);
        _unpersistedAccepted++;
        if (_autoComplete) {
          _completed = (_completed + 1).clamp(0, 99999);
          _unpersistedCompleted++;
        }
      } else {
        _rejected = (_rejected + 1).clamp(0, 99999);
        _unpersistedRejected++;
      }
    });

    _syncShade();
    unawaited(
      TapHistoryStore.instance.append(accepted ? 'accepted' : 'rejected'),
    );
    _schedulePersist();
    // Live path to the home isolate. Not chained onto the store queue and
    // not awaited — a missed ping cannot freeze the button.
    _pingMain();
  }

  /// Logs one cancelled trip on `canceledTrips` — the counter behind
  /// "İptal Edilen" — without touching the accept/reject request totals.
  void _incrementCancel() {
    logd('overlay tap complete key=canceledTrips', name: 'overlay');
    _fireCancelHaptic();
    _unpersistedCancels++;
    _schedulePersist();
  }

  void _pingMain({int? canceled}) {
    // Never send on the overlay messenger while a native reply handler is
    // still awaiting: shareData on the same channel deadlocks the test
    // binding (and can stall TapDelivery's ACK on device).
    final accepted = _accepted;
    final rejected = _rejected;
    final completed = _completed;
    scheduleMicrotask(() {
      OverlaySync.pingCountersChanged(
        accepted: accepted,
        rejected: rejected,
        completed: completed,
        canceled: canceled,
      );
    });
  }

  void _schedulePersist() {
    _persistTimer?.cancel();
    _persistTimer = Timer(_persistDebounce, () {
      unawaited(_persistCounts());
    });
  }

  Future<bool> _persistCounts() async {
    _persistTimer?.cancel();
    _persistTimer = null;

    while (_inFlightPersist != null) {
      final ok = await _inFlightPersist!;
      if (!ok) return false;
    }

    if (_unpersistedAccepted == 0 &&
        _unpersistedRejected == 0 &&
        _unpersistedCompleted == 0 &&
        _unpersistedCancels == 0) {
      return true;
    }

    final future = _runPersistStep();
    _inFlightPersist = future;
    try {
      return await future;
    } finally {
      if (identical(_inFlightPersist, future)) {
        _inFlightPersist = null;
      }
    }
  }

  Future<bool> _runPersistStep() async {
    final accepted = _unpersistedAccepted;
    final rejected = _unpersistedRejected;
    final completed = _unpersistedCompleted;
    final cancels = _unpersistedCancels;
    _unpersistedAccepted = 0;
    _unpersistedRejected = 0;
    _unpersistedCompleted = 0;
    _unpersistedCancels = 0;
    try {
      final saved = await ShiftCounterStore.instance.applyDelta(
        acceptedDelta: accepted,
        rejectedDelta: rejected,
        completedDelta: completed,
        canceledDelta: cancels,
      );
      // Latest in-memory counts: a tap that landed during the await is
      // already newer; pinging [saved] alone would roll home backwards.
      _pingMain(canceled: cancels != 0 ? saved.canceled : null);
      return true;
    } catch (e, s) {
      // Keep the deltas dirty for retry. Reloading disk here would wipe
      // in-memory taps the failed write never reached.
      _unpersistedAccepted += accepted;
      _unpersistedRejected += rejected;
      _unpersistedCompleted += completed;
      _unpersistedCancels += cancels;
      loge('overlay write failed', name: 'overlay', error: e, stack: s);
      return false;
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
    if (_windowHidden) return const SizedBox.shrink();
    final vertical = _orientation.isVertical;
    final showCancel = _showCancelButton;
    final width = OverlayWidget.windowWidthDp(
      _orientation,
      showCancel: showCancel,
    ).toDouble();
    final height = OverlayWidget.windowHeightDp(
      _orientation,
      showCancel: showCancel,
    ).toDouble();
    // Long-axis order: [cancel] → reject → percentage → accept, so the rate
    // sits dead-centre between − and + with the same gap on both sides.
    // The optional cancel hangs off the reject end; the gap after it is
    // cancelGapDp (12) horizontally and verticalGapDp (8, AppSpacing.sm)
    // vertically, so the 48dp cancel target does not meet the reject target.
    SizedBox alongGap() => SizedBox(
      width: vertical ? 0 : _btnTextGapDp,
      height: vertical ? OverlayWidget.verticalGapDp : 0,
    );
    final children = <Widget>[
      if (showCancel) ...[
        _CircleBtn(
          size: OverlayWidget.cancelBtnSizeDp,
          icon: Icons.block_rounded,
          color: _amber,
          onTap: _incrementCancel,
        ),
        SizedBox(
          width: vertical ? 0 : OverlayWidget.cancelGapDp,
          height: vertical ? OverlayWidget.verticalGapDp : 0,
        ),
      ],
      _CircleBtn(
        size: _btnSizeDp,
        icon: Icons.remove_rounded,
        color: _crimson,
        onTap: () => unawaited(_increment(_keyRejected)),
      ),
      alongGap(),
      _TapPop(
        key: ValueKey<int>(_tapSeq),
        child: _AcceptRateDisplay(
          text: _formatAcceptRate(_acceptanceRate),
          color: _acceptRateColor,
          width: vertical ? _verticalCenterTextWidthDp : _centerTextWidthDp,
          // Full button height horizontally so the collapse target is as
          // forgiving as the +/− buttons next to it.
          height: vertical ? OverlayWidget.verticalRateSlotDp : _btnSizeDp,
          // The vertical slot spans the pill's straight sides, 3dp from
          // the stroke; the inset keeps the glyphs off the border.
          textPadding: vertical
              ? const EdgeInsets.symmetric(horizontal: AppSpacing.sm)
              : const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          onTap: () => _onToggleCollapsedTap(true),
        ),
      ),
      alongGap(),
      _CircleBtn(
        size: _btnSizeDp,
        icon: Icons.add_rounded,
        color: _emerald,
        onTap: () => unawaited(_increment(_keyAccepted)),
      ),
    ];

    final pill = Material(
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
    );

    const bubbleSize = OverlayWidget.bubbleSizeDp;
    final collapsed = _collapsed;
    // The window and the drawn content change size in separate frames
    // (native resize vs setState). Fixed constraints here keep the pill's
    // Row/Column from ever being laid out inside a 48dp window, so the
    // transition cannot raise a RenderFlex overflow.
    return Material(
      type: MaterialType.transparency,
      color: Colors.transparent,
      child: Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: collapsed ? bubbleSize : width,
          maxWidth: collapsed ? bubbleSize : width,
          minHeight: collapsed ? bubbleSize : height,
          maxHeight: collapsed ? bubbleSize : height,
          child: collapsed
              ? _CollapsedBubble(onTap: () => _onToggleCollapsedTap(false))
              : pill,
        ),
      ),
    );
  }
}

/// The collapsed pill: one 48dp dark circle with a white "R". Tapping expands; dragging goes
/// through the same native window drag (20dp slop + ACTION_CANCEL) as the
/// pill, so the InkWell cannot be left holding a stuck pointer.
class _CollapsedBubble extends StatelessWidget {
  const _CollapsedBubble({required this.onTap});

  final VoidCallback onTap;

  /// A capital has no descender, so a centred line box leaves the "R"
  /// sitting high. At 20sp DM Sans the cap centre is ~2dp above the box
  /// centre; this drop centres the glyph itself, not its line box.
  static const double _glyphOpticalDropDp = 2;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: S.overlayExpand,
      excludeSemantics: true,
      child: Material(
        // Opaque, same hue as the pill: crisp over light and dark maps alike.
        color: AppColors.surface,
        elevation: 8,
        shadowColor: Colors.black,
        clipBehavior: Clip.antiAlias,
        shape: const CircleBorder(
          side: BorderSide(color: AppColors.strongBorder, width: 1.5),
        ),
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          splashColor: AppColors.hairline,
          highlightColor: AppColors.cardBorderColor,
          child: SizedBox.square(
            dimension: OverlayWidget.bubbleSizeDp,
            child: Center(
              child: Transform.translate(
                offset: const Offset(0, _glyphOpticalDropDp),
                child: Text(
                  S.overlayBubbleLetter,
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: T.overlayBubbleLetter,
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
    required this.onTap,
    this.height,
    this.textPadding = EdgeInsets.zero,
  });

  final String text;
  final Color color;
  final double width;
  final double? height;

  /// Inset between the tap target's edge and the scaled-down text. The tap
  /// target keeps the full slot; only the glyphs move in.
  final EdgeInsets textPadding;

  /// Collapses the pill to the bubble.
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Semantics(
        button: true,
        hint: S.overlayCollapse,
        child: InkWell(
          onTap: onTap,
          customBorder: const StadiumBorder(),
          splashColor: color.withValues(alpha: 0.20),
          highlightColor: color.withValues(alpha: 0.10),
          child: SizedBox(
            width: width,
            height: height,
            child: Padding(
              padding: textPadding,
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
          ),
        ),
      ),
    );
  }
}
