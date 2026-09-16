import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:rate_helper/fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_text_styles.dart';
import 'app_widgets.dart';
import 'crash_logger.dart';
import 'earnings_models.dart';
import 'earnings_screen.dart';
import 'env.dart';
import 'models/weekly_archive_entry.dart';
import 'l10n.dart';
import 'log.dart';
import 'onboarding_screen.dart';
import 'overlay_sync.dart';
import 'services/event_service.dart';
import 'services/update_service.dart';
import 'overlay_widget.dart';
import 'radar_screen.dart';
import 'shift_counter_store.dart';
import 'tap_history_store.dart';
import 'update_dialog.dart';

enum TripGoal {
  tier0(soloMinTrips: 0, pairedMinTrips: 0, requiredAcceptRate: null),
  tier1(soloMinTrips: 100, pairedMinTrips: 120, requiredAcceptRate: 80),
  tier2(soloMinTrips: 150, pairedMinTrips: 170, requiredAcceptRate: 70),
  tier3(soloMinTrips: 200, pairedMinTrips: 220, requiredAcceptRate: 60),
  tier4(soloMinTrips: 250, pairedMinTrips: 270, requiredAcceptRate: 50);

  const TripGoal({
    required this.soloMinTrips,
    required this.pairedMinTrips,
    required this.requiredAcceptRate,
  });

  final int soloMinTrips;
  final int pairedMinTrips;
  final double? requiredAcceptRate;

  int get minTrips =>
      activeDriverMode == DriverMode.paired ? pairedMinTrips : soloMinTrips;
}

// ignore: constant_identifier_names
const double AMBER_BUFFER = 2.0;
const double kAmberBuffer = AMBER_BUFFER;

int? calculateNeededForRecovery({
  required int acceptedRequests,
  required int rejectedRequests,
  required double? requiredAcceptRate,
}) {
  if (requiredAcceptRate == null) return null;
  final total = acceptedRequests + rejectedRequests;
  final currentRate = total == 0 ? 100.0 : (acceptedRequests / total) * 100.0;
  if (currentRate > requiredAcceptRate) return null;

  final r = requiredAcceptRate / 100.0;
  final val = (r * rejectedRequests - (1 - r) * acceptedRequests) / (1 - r);
  int n = val.floor() + 1;
  while (((acceptedRequests + n) / (total + n)) * 100.0 <= requiredAcceptRate) {
    n++;
  }
  return math.max(1, n);
}

int? maxAdditionalCancellations({
  required int completedTrips,
  required int currentCancellations,
  double ceiling = 5.0,
}) {
  if (completedTrips == 0) return 0;
  if ((currentCancellations / completedTrips) * 100 >= ceiling) return -1;

  int n = 0;
  while (((currentCancellations + n + 1) / (completedTrips + n + 1)) * 100 <
      ceiling) {
    n++;
  }
  return n;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  static const _keyAccepted = 'acceptedRequests';
  static const _keyRejected = 'rejectedRequests';
  static const _keyCompleted = 'completedTrips';
  static const _keyCanceled = 'canceledTrips';
  static const _keyAutoComplete = 'autoCompleteTrips';
  static const _keySteeringWheel = 'steeringWheelEnabled';
  static const _keyKeepScreenOn = 'keepScreenOn';
  static const _wakelockIdleTimeout = Duration(minutes: 10);
  static const _keyTripGoal = 'trip_goal_tier';
  static const _kSysChannel = MethodChannel('com.ratehelper.app/system');
  static const _keyLastReset = 'lastResetTimestamp';
  static const _keyArchive = 'weekly_archive';
  static const _keyLang = 'appLanguage';

  static tz.Location get _warsaw {
    try {
      return tz.getLocation('Europe/Warsaw');
    } catch (_) {
      // Fallback if tz.initializeTimeZones() failed in main.dart
      return tz.local;
    }
  }

  static const _cardColor = AppColors.card;
  static const _emerald = AppColors.emerald;
  static const _crimson = AppColors.crimson;
  static const _amber = AppColors.amber;
  static const _designerGold = AppColors.designerGold;
  static final _cardBorder = Border.all(
    color: AppColors.cardBorderColor,
    width: 1,
  );
  static final _cardRadius = AppRadius.mdBorder;

  SharedPreferences? _prefs;
  AppLang _currentLang = AppLang.tr;

  /// Read from the installed APK, so the footer badge and the update check can
  /// never disagree about which build is running.
  String? _appVersion;
  final _accepted = ValueNotifier<int>(0);
  final _rejected = ValueNotifier<int>(0);
  final _completed = ValueNotifier<int>(0);
  final _canceled = ValueNotifier<int>(0);
  final _undoAvailable = ValueNotifier<bool>(false);
  late final Listenable _ratesListenable = Listenable.merge([
    _accepted,
    _rejected,
    _completed,
    _canceled,
  ]);

  int get acceptedRequests => _accepted.value;
  set acceptedRequests(int v) => _accepted.value = v;
  int get rejectedRequests => _rejected.value;
  set rejectedRequests(int v) => _rejected.value = v;
  int get completedTrips => _completed.value;
  set completedTrips(int v) => _completed.value = v;
  int get canceledTrips => _canceled.value;
  set canceledTrips(int v) => _canceled.value = v;
  bool _autoCompleteTrips = false;
  bool _steeringWheelEnabled = false;
  bool _keepScreenOn = false;
  PillOrientation _pillOrientation = PillOrientation.horizontal;
  TripGoal _selectedGoal = TripGoal.tier1;

  int? _prevAccepted;
  int? _prevRejected;
  int? _prevCompleted;
  int? _prevCanceled;

  int _baselineAccepted = 0;
  int _baselineRejected = 0;
  int _baselineCompleted = 0;
  int _baselineCanceled = 0;

  void _syncBaseline() {
    _baselineAccepted = acceptedRequests;
    _baselineRejected = rejectedRequests;
    _baselineCompleted = completedTrips;
    _baselineCanceled = canceledTrips;
  }

  Timer? _saveDebounce;
  Timer? _wakelockIdleTimer;

  /// Set when the user was sent to Settings to switch the accessibility
  /// service on. The toggle stays off until the service reports active.
  bool _pendingSteeringWheelEnable = false;

  bool _isLoadingOrResetting = false;
  bool _overlayActive = false;

  /// True while [_toggleOverlay] is round-tripping through the platform
  /// channel, so the toggle can show progress instead of looking unresponsive.
  bool _overlayToggleBusy = false;
  StreamSubscription<dynamic>? _overlayListenerSub;

  bool get _canUndo => _prevAccepted != null;

  int get totalRequests => acceptedRequests + rejectedRequests;
  double get acceptanceRate =>
      totalRequests == 0 ? 100.0 : (acceptedRequests / totalRequests) * 100;

  int get totalAcceptedTrips => completedTrips + canceledTrips;
  double get cancellationRate => totalAcceptedTrips == 0
      ? 0.0
      : (canceledTrips / totalAcceptedTrips) * 100;

  int? get neededForRecovery => calculateNeededForRecovery(
    acceptedRequests: acceptedRequests,
    rejectedRequests: rejectedRequests,
    requiredAcceptRate: _selectedGoal.requiredAcceptRate,
  );

  int? get maxCancellationsBudget => maxAdditionalCancellations(
    completedTrips: totalAcceptedTrips,
    currentCancellations: canceledTrips,
  );

  Color get _acceptRateColor {
    final req = _selectedGoal.requiredAcceptRate;
    if (req == null) return _emerald;
    if (acceptanceRate < req) return _crimson;
    if (acceptanceRate < req + AMBER_BUFFER) return _amber;
    return _emerald;
  }

  Future<SharedPreferences> _getPrefs() async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    try {
      _overlayListenerSub = FlutterOverlayWindow.overlayListener.listen((
        event,
      ) {
        if (OverlaySync.shouldReloadCounters(event)) {
          unawaited(_applyOverlayCounters(event));
        }
      });
    } catch (e, s) {
      loge(
        'overlayListener listen failed in home screen',
        name: 'home',
        error: e,
        stack: s,
      );
    }
    _kSysChannel.setMethodCallHandler((call) async {
      if (call.method == 'onMediaKeyIncrement') {
        _drainPendingTaps();
      }
    });
    _init();
  }

  Future<void> _init() async {
    final prefsFuture = _getPrefs();
    final infoFuture = PackageInfo.fromPlatform();
    final prefs = await prefsFuture;

    final AppLang lang;
    if (prefs.containsKey(_keyLang)) {
      final langStr = prefs.getString(_keyLang)!;
      lang = AppLang.values.firstWhere(
        (l) => l.name == langStr,
        orElse: () => AppLang.en,
      );
    } else {
      lang = S.langFromLocale(
        WidgetsBinding.instance.platformDispatcher.locale,
      );
      await prefs.setString(_keyLang, lang.name);
    }
    S.setLang(lang);

    final info = await infoFuture;
    if (kReleaseMode) {
      final trusted = await _verifySignature(info.buildSignature);
      if (!trusted) return;
    }
    if (mounted) {
      setState(() {
        _currentLang = lang;
        _appVersion = info.version;
      });
    }
    unawaited(_checkForUpdate());
    await _loadAndCheckReset();
    // A cold start never fires a lifecycle resume, so this is the only place
    // steering-wheel taps taken while the app was closed reach the counters.
    unawaited(_drainPendingTaps());
    unawaited(_syncSteeringWheelState());
    unawaited(_refreshOverlayState());
  }

  String _normalizeSignature(String sig) =>
      sig.replaceAll(':', '').replaceAll(' ', '').toUpperCase();

  /// Release-only tamper check. Returns false when the app must exit.
  Future<bool> _verifySignature(String buildSignature) async {
    if (!kReleaseMode) return true;
    if (Env.appSignature.isEmpty || Env.appSignature == 'PLACEHOLDER') {
      return true;
    }

    final actual = _normalizeSignature(buildSignature);
    final expected = _normalizeSignature(Env.appSignature);
    if (actual.isNotEmpty && actual == expected) return true;

    await CrashLogger.appendError(
      'SIGNATURE',
      'APK signature mismatch',
      null,
      null,
    );

    if (!mounted) return false;

    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            backgroundColor: AppColors.card,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: const Text(
              'Güvenlik Uyarısı',
              style: TextStyle(
                fontFamily: AppFonts.dmSans,
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: const Text(
              'Bu uygulama değiştirilmiş. Güvenliğiniz için kapatılıyor.',
              style: TextStyle(
                fontFamily: AppFonts.dmSans,
                color: AppColors.mutedText,
                height: 1.4,
              ),
            ),
          ),
        ),
      ),
    );

    await Future<void>.delayed(const Duration(seconds: 3));
    SystemNavigator.pop();
    return false;
  }

  /// Startup check: never blocks boot, never reports failures. An offline
  /// driver just sees nothing, and the 12-hour cooldown plus per-version skip
  /// live in [UpdateService.checkOnStartup].
  Future<void> _checkForUpdate() async {
    final result =
        await UpdateService.instance.checkOnStartup(languageCode: S.lang.name);
    if (!mounted || result.status != UpdateStatus.available) return;
    await showUpdatePrompt(context, result);
  }

  @override
  void dispose() {
    // Detach the media-key handler so the static channel cannot retain
    // this State or invoke setState() on it after disposal.
    _kSysChannel.setMethodCallHandler(null);
    _overlayListenerSub?.cancel();
    _saveDebounce?.cancel();
    _wakelockIdleTimer?.cancel();
    _flushSave();
    unawaited(_setWakelock(false));
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyWakelockPolicy();
      _reloadAndSync();
    } else if (state == AppLifecycleState.paused) {
      // Kick the write before the OS freezes us. shared_preferences
      // updates its in-memory map synchronously and flushes to disk
      // async — starting it here (instead of behind a reload() round
      // trip) minimizes the kill-race window for the last taps.
      if (_saveDebounce?.isActive ?? false) {
        _saveDebounce!.cancel();
        unawaited(_saveDataNow());
      }
      _wakelockIdleTimer?.cancel();
      unawaited(_setWakelock(false));
    }
  }

  Future<void> _setWakelock(bool on) async {
    try {
      if (on) {
        await WakelockPlus.enable();
      } else {
        await WakelockPlus.disable();
      }
    } catch (_) {}
  }

  void _applyWakelockPolicy() {
    _wakelockIdleTimer?.cancel();
    _wakelockIdleTimer = null;
    if (!_keepScreenOn) {
      unawaited(_setWakelock(false));
      return;
    }
    unawaited(_setWakelock(true));
    _wakelockIdleTimer = Timer(_wakelockIdleTimeout, () {
      unawaited(_setWakelock(false));
    });
  }

  void _onUserInteraction() {
    if (!_keepScreenOn) return;
    _applyWakelockPolicy();
  }

  Future<void> _applyOverlayCounters(Object? event) async {
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      await _saveDataNow();
      return;
    }
    final counters = OverlaySync.countersFromEvent(event);
    if (counters == null) {
      await _applyStoredCounters();
      return;
    }
    if (!mounted) return;
    acceptedRequests = counters.accepted;
    rejectedRequests = counters.rejected;
    completedTrips = counters.completed;
    _syncBaseline();
  }

  Future<void> _applyStoredCounters() async {
    final stored = await ShiftCounterStore.instance.read();
    if (!mounted) return;
    acceptedRequests = stored.accepted;
    rejectedRequests = stored.rejected;
    completedTrips = stored.completed;
    canceledTrips = stored.canceled;
    _syncBaseline();
  }

  @override
  void didHaveMemoryPressure() {
    // Drop every re-creatable cache so the OS keeps our process alive
    // instead of killing it (a cold start costs far more battery than
    // re-fetching events or re-decoding the logo).
    EventService.clearCache();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
  }

  Future<void> _reloadAndSync() async {
    // Settle any debounced in-app delta FIRST; otherwise the disk read
    // below overwrites memory+baseline and the pending taps evaporate.
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      await _saveDataNow(); // merges delta into disk before we re-read it
    }
    if (!mounted) return;
    // Must settle before draining: it reloads the counters from disk and
    // re-syncs the save baseline, so a tap applied while it was still in
    // flight used to be overwritten and lost.
    await _loadAndCheckReset();
    await _drainPendingTaps();
    unawaited(_syncSteeringWheelState());
    unawaited(_refreshOverlayState());
  }

  Future<void> _drainPendingTaps() async {
    try {
      final Map<dynamic, dynamic>? result = await _kSysChannel.invokeMethod(
        'drainPendingTaps',
      );
      if (result != null) {
        final int accepted = result['accepted'] as int? ?? 0;
        final int rejected = result['rejected'] as int? ?? 0;
        if (accepted > 0) _change(_keyAccepted, accepted);
        if (rejected > 0) _change(_keyRejected, rejected);
      }
    } catch (e, s) {
      loge('Failed to drain pending taps', name: 'home', error: e, stack: s);
    }
  }

  Future<void> _refreshOverlayState() async {
    final active = await FlutterOverlayWindow.isActive();
    if (!mounted || active == _overlayActive) return;
    setState(() => _overlayActive = active);
  }

  void _flushSave() {
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      _saveDataNow();
    }
  }

  tz.TZDateTime _lastMonday4amWarsaw(tz.TZDateTime now) {
    final daysFromMonday = (now.weekday - DateTime.monday) % 7;
    final monday = tz.TZDateTime(
      _warsaw,
      now.year,
      now.month,
      now.day - daysFromMonday,
      4,
      0,
      0,
    );
    if (now.isBefore(monday)) {
      return tz.TZDateTime(
        _warsaw,
        monday.year,
        monday.month,
        monday.day - 7,
        4,
        0,
        0,
      );
    }
    return monday;
  }

  tz.TZDateTime _nowWarsaw() => tz.TZDateTime.now(_warsaw);

  Future<void> _loadAndCheckReset() async {
    if (_isLoadingOrResetting) return;
    _isLoadingOrResetting = true;

    try {
      final prefs = await _getPrefs();
      if (!mounted) return;

      unawaited(TapHistoryStore.instance.migrateFromPrefs(prefs));
      await ShiftCounterStore.instance.migrateFromPrefs(prefs);
      final stored = await ShiftCounterStore.instance.read();
      if (!mounted) return;

      final now = _nowWarsaw();
      final resetBoundary = _lastMonday4amWarsaw(now);
      final lastResetMs = prefs.getInt(_keyLastReset) ?? 0;
      final lastReset = tz.TZDateTime.fromMillisecondsSinceEpoch(
        _warsaw,
        lastResetMs,
      );

      final goalStr = prefs.getString(_keyTripGoal);
      final loadedGoal = goalStr != null
          ? TripGoal.values.firstWhere(
              (g) => g.name == goalStr,
              orElse: () => TripGoal.tier1,
            )
          : TripGoal.tier1;

      final modeStr = prefs.getString(DriverMode.key);
      activeDriverMode = modeStr == 'paired'
          ? DriverMode.paired
          : DriverMode.solo;

      if (prefs.getBool(DriverMode.askedKey) != true) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && prefs.getBool(DriverMode.askedKey) != true) {
            showDriverModeDialog(context, prefs, () {
              if (mounted) setState(() {});
            });
          }
        });
      }

      if (lastReset.isBefore(resetBoundary)) {
        await _performReset(prefs, resetBoundary, stored);
        if (mounted) {
          setState(() {
            _selectedGoal = loadedGoal;
            _keepScreenOn = prefs.getBool(_keyKeepScreenOn) ?? false;
            _pillOrientation = PillOrientation.fromPrefs(prefs);
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _selectedGoal = loadedGoal;
          acceptedRequests = stored.accepted;
          rejectedRequests = stored.rejected;
          completedTrips = stored.completed;
          canceledTrips = stored.canceled;
          _autoCompleteTrips = prefs.getBool(_keyAutoComplete) ?? false;
          _steeringWheelEnabled = prefs.getBool(_keySteeringWheel) ?? false;
          _keepScreenOn = prefs.getBool(_keyKeepScreenOn) ?? false;
          _pillOrientation = PillOrientation.fromPrefs(prefs);
          _syncBaseline();
        });
        unawaited(
          OverlaySync.notifyCountersChanged(
            accepted: acceptedRequests,
            rejected: rejectedRequests,
            completed: completedTrips,
          ),
        );
      }
      _applyWakelockPolicy();
    } finally {
      _isLoadingOrResetting = false;
    }
  }

  Future<void> _setTripGoal(TripGoal goal) async {
    if (_selectedGoal == goal) return;
    setState(() {
      _selectedGoal = goal;
    });
    final prefs = await _getPrefs();
    await prefs.setString(_keyTripGoal, goal.name);
    unawaited(
      OverlaySync.notifyCountersChanged(
        accepted: acceptedRequests,
        rejected: rejectedRequests,
        completed: completedTrips,
      ),
    );
  }

  /// Keep 2 years of weekly snapshots, matching kMaxEarningEntries.
  static const int _maxArchiveEntries = 104;

  Future<void> _performReset(
    SharedPreferences prefs, [
    tz.TZDateTime? boundary,
    ShiftCounters? snapshot,
  ]) async {
    // Settle debounced in-app taps first. Both the archive snapshot and the
    // zeroing below read from disk, so taps still inside the 300 ms window
    // would be archived as missing and then wiped with everything else.
    var counts = snapshot;
    if (_saveDebounce?.isActive ?? false) {
      _saveDebounce!.cancel();
      await _saveDataNow();
      counts = null; // the caller's snapshot predates the flush
    }
    counts ??= await ShiftCounterStore.instance.read();
    final snap = _buildArchiveEntry(counts, boundary);
    if (snap != null) {
      var archive = prefs.getStringList(_keyArchive) ?? [];
      archive.add(snap);
      if (archive.length > _maxArchiveEntries) {
        archive = archive.sublist(archive.length - _maxArchiveEntries);
      }
      await prefs.setStringList(_keyArchive, archive);
    }

    await ShiftCounterStore.instance.write(const ShiftCounters());
    await prefs.setInt(_keyLastReset, _nowWarsaw().millisecondsSinceEpoch);

    if (!mounted) return;
    setState(() {
      acceptedRequests = 0;
      rejectedRequests = 0;
      completedTrips = 0;
      canceledTrips = 0;
      _clearUndo();
      _syncBaseline();
    });
    unawaited(
      OverlaySync.notifyCountersChanged(accepted: 0, rejected: 0, completed: 0),
    );
  }

  String? _buildArchiveEntry(ShiftCounters counts, tz.TZDateTime? boundary) {
    final accepted = counts.accepted;
    final rejected = counts.rejected;
    final completed = counts.completed;
    final canceled = counts.canceled;

    final total = accepted + rejected;
    final totalTrips = completed + canceled;

    if (total == 0 && totalTrips == 0) return null;

    final aRate = total == 0 ? 100.0 : (accepted / total) * 100;
    final cRate = totalTrips == 0 ? 0.0 : (canceled / totalTrips) * 100;

    final weekStart = boundary ?? _lastMonday4amWarsaw(_nowWarsaw());
    final weekEnd = tz.TZDateTime(
      _warsaw,
      weekStart.year,
      weekStart.month,
      weekStart.day + 6,
      4,
      0,
      0,
    );

    final entry = WeeklyArchiveEntry(
      weekStart: weekStart,
      weekEnd: weekEnd,
      acceptRate: aRate,
      cancelRate: cRate,
      acceptedCount: accepted,
      rejectedCount: rejected,
      completedTrips: completed,
    );
    return entry.encode();
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), _saveDataNow);
  }

  Future<void> _saveDataNow() async {
    // Claim the deltas before awaiting: taps that land while the write is in
    // flight then accumulate against the fresh baseline instead of being
    // replayed on the next save.
    final acceptedDelta = acceptedRequests - _baselineAccepted;
    final rejectedDelta = rejectedRequests - _baselineRejected;
    final completedDelta = completedTrips - _baselineCompleted;
    final canceledDelta = canceledTrips - _baselineCanceled;
    _syncBaseline();

    final saved = await ShiftCounterStore.instance.applyDelta(
      acceptedDelta: acceptedDelta,
      rejectedDelta: rejectedDelta,
      completedDelta: completedDelta,
      canceledDelta: canceledDelta,
    );

    if (mounted) {
      // Fold in anything tapped while the write was running.
      acceptedRequests =
          (saved.accepted + (acceptedRequests - _baselineAccepted))
              .clamp(0, 99999);
      rejectedRequests =
          (saved.rejected + (rejectedRequests - _baselineRejected))
              .clamp(0, 99999);
      completedTrips =
          (saved.completed + (completedTrips - _baselineCompleted))
              .clamp(0, 99999);
      canceledTrips = (saved.canceled + (canceledTrips - _baselineCanceled))
          .clamp(0, 99999);
      _syncBaseline();
    }

    unawaited(
      OverlaySync.notifyCountersChanged(
        accepted: saved.accepted,
        rejected: saved.rejected,
        completed: saved.completed,
      ),
    );
  }

  void _snapshotUndo() {
    _prevAccepted = acceptedRequests;
    _prevRejected = rejectedRequests;
    _prevCompleted = completedTrips;
    _prevCanceled = canceledTrips;
    _undoAvailable.value = true;
  }

  void _clearUndo() {
    _prevAccepted = null;
    _prevRejected = null;
    _prevCompleted = null;
    _prevCanceled = null;
    _undoAvailable.value = false;
  }

  void _undo() {
    if (!_canUndo) return;
    acceptedRequests = _prevAccepted!;
    rejectedRequests = _prevRejected!;
    completedTrips = _prevCompleted!;
    canceledTrips = _prevCanceled!;
    _clearUndo();
    _scheduleSave();
  }

  void _change(String key, int delta) {
    _snapshotUndo();
    switch (key) {
      case _keyAccepted:
        acceptedRequests = (acceptedRequests + delta).clamp(0, 99999);
        if (delta > 0 && _autoCompleteTrips) {
          completedTrips = (completedTrips + delta).clamp(0, 99999);
        }
      case _keyRejected:
        rejectedRequests = (rejectedRequests + delta).clamp(0, 99999);
      case _keyCompleted:
        completedTrips = (completedTrips + delta).clamp(0, 99999);
      case _keyCanceled:
        canceledTrips = (canceledTrips + delta).clamp(0, 99999);
    }
    _scheduleSave();
  }

  void _setCounter(String key, int value) {
    _snapshotUndo();
    final clamped = value.clamp(0, 99999);
    switch (key) {
      case _keyAccepted:
        acceptedRequests = clamped;
      case _keyRejected:
        rejectedRequests = clamped;
      case _keyCompleted:
        completedTrips = clamped;
      case _keyCanceled:
        canceledTrips = clamped;
    }
    _scheduleSave();
  }

  Future<void> _setAutoCompleteTrips(bool enabled) async {
    setState(() => _autoCompleteTrips = enabled);
    final prefs = await _getPrefs();
    await prefs.setBool(_keyAutoComplete, enabled);
  }

  Future<void> _setKeepScreenOn(bool enabled) async {
    setState(() => _keepScreenOn = enabled);
    final prefs = await _getPrefs();
    await prefs.setBool(_keyKeepScreenOn, enabled);
    _applyWakelockPolicy();
  }

  Future<void> _setPillOrientation(PillOrientation orientation) async {
    if (_pillOrientation == orientation) return;
    setState(() => _pillOrientation = orientation);
    final prefs = await _getPrefs();
    await prefs.setString(PillOrientation.prefsKey, orientation.name);
    if (prefs.containsKey(PillOrientation.legacyBoolKey)) {
      await prefs.remove(PillOrientation.legacyBoolKey);
    }
    if (!_overlayActive || _overlayToggleBusy) return;
    await _reopenOverlayPreservingPosition();
  }

  Future<void> _showEditCounterDialog({
    required String title,
    required int currentValue,
    required void Function(int value) onSave,
  }) async {
    final controller = TextEditingController(text: '$currentValue');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: Colors.white,
            fontSize: 24,
            fontWeight: FontWeight.w700,
          ),
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0x0AFFFFFF),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              S.cancel,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: AppColors.mutedText,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              S.save,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: _emerald,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) {
      controller.dispose();
      return;
    }
    final parsed = int.tryParse(controller.text.trim());
    controller.dispose();
    if (parsed == null) return;
    onSave(parsed);
  }

  Future<void> _setLanguage(AppLang lang) async {
    S.setLang(lang);
    if (!mounted) return;
    // Rebuild cached chrome (bottom bar + version footer) immediately so a
    // language switch cannot leave last-frame Turkish labels on screen.
    setState(() => _currentLang = lang);
    final prefs = await _getPrefs();
    await prefs.setString(_keyLang, lang.name);
  }

  Future<void> _showLanguageSelector() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.sheet,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            _LangOption(
              flag: '🇹🇷',
              name: 'Türkçe',
              selected: _currentLang == AppLang.tr,
              onTap: () {
                _setLanguage(AppLang.tr);
                Navigator.of(ctx).pop();
              },
            ),
            _LangOption(
              flag: '🇬🇧',
              name: 'English',
              selected: _currentLang == AppLang.en,
              onTap: () {
                _setLanguage(AppLang.en);
                Navigator.of(ctx).pop();
              },
            ),
            _LangOption(
              flag: '🇵🇱',
              name: 'Polski',
              selected: _currentLang == AppLang.pl,
              onTap: () {
                _setLanguage(AppLang.pl);
                Navigator.of(ctx).pop();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  static const _defaultOverlayStart = OverlayPosition(0, 60);

  Future<void> _toggleOverlay() async {
    // Showing/closing the native overlay round-trips through the platform
    // channel and the permission screen; without this guard the button just
    // sits there looking dead and re-fires on every impatient tap.
    if (_overlayToggleBusy) return;
    setState(() => _overlayToggleBusy = true);
    try {
      final active = await FlutterOverlayWindow.isActive();

      if (active) {
        await FlutterOverlayWindow.closeOverlay();
        if (!mounted) return;
        setState(() => _overlayActive = false);
        return;
      }

      await _showOverlayWindow();
    } on PlatformException catch (e, s) {
      loge('overlay toggle failed', name: 'home', error: e, stack: s);
      if (!mounted) return;
      unawaited(_refreshOverlayState());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.overlayToggleFailed),
          backgroundColor: AppColors.card,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _overlayToggleBusy = false);
      } else {
        _overlayToggleBusy = false;
      }
    }
  }

  Future<void> _showOverlayWindow({OverlayPosition? startPosition}) async {
    final granted = await FlutterOverlayWindow.isPermissionGranted();
    if (!granted) {
      await FlutterOverlayWindow.requestPermission();
      final check = await FlutterOverlayWindow.isPermissionGranted();
      if (!check) return;
    }
    if (!mounted) return;

    // Native window sized to the pill (dp) so touches pass through elsewhere.
    // resizeOverlay from the main isolate is unreliable — orientation changes
    // close+reopen with these dimensions instead.
    await FlutterOverlayWindow.showOverlay(
      width: OverlayWidget.windowWidthDp(_pillOrientation),
      height: OverlayWidget.windowHeightDp(_pillOrientation),
      alignment: OverlayAlignment.topLeft,
      visibility: NotificationVisibility.visibilitySecret,
      flag: OverlayFlag.defaultFlag,
      enableDrag: true,
      positionGravity: PositionGravity.none,
      startPosition: startPosition ?? _defaultOverlayStart,
      overlayTitle: 'RateHelper',
    );

    await OverlaySync.notifyCountersChanged();

    if (!mounted) return;
    setState(() => _overlayActive = true);
  }

  Future<void> _reopenOverlayPreservingPosition() async {
    if (_overlayToggleBusy) return;
    setState(() => _overlayToggleBusy = true);
    OverlayPosition start = _defaultOverlayStart;
    try {
      if (await FlutterOverlayWindow.isActive()) {
        try {
          start = await FlutterOverlayWindow.getOverlayPosition();
        } catch (_) {
          start = _defaultOverlayStart;
        }
        await FlutterOverlayWindow.closeOverlay();
      }
      if (!mounted) return;
      await _showOverlayWindow(startPosition: start);
    } on PlatformException catch (e, s) {
      loge('overlay reopen failed', name: 'home', error: e, stack: s);
      if (!mounted) return;
      unawaited(_refreshOverlayState());
    } finally {
      if (mounted) {
        setState(() => _overlayToggleBusy = false);
      } else {
        _overlayToggleBusy = false;
      }
    }
  }

  String _formatTapDate(DateTime dt) {
    final months = S.months;
    return '${dt.day} ${months[dt.month]}';
  }

  Future<void> _showHistory() async {
    final prefs = await _getPrefs();
    await TapHistoryStore.instance.migrateFromPrefs(prefs);
    final archive = (prefs.getStringList(_keyArchive) ?? []).reversed.toList();
    final taps = await TapHistoryStore.instance.readNewestFirst();

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _HistorySheet(
        archive: archive,
        taps: taps,
        formatTapDate: _formatTapDate,
      ),
    );
  }

  Future<void> _showCrashLog() async {
    String body = '';
    final f = await CrashLogger.currentLogFile();
    if (f != null) {
      try {
        final content = await f.readAsString();
        if (content.trim().isNotEmpty) {
          body = content;
        }
      } on FileSystemException {
        // Stay with the empty-state placeholder.
      }
    }
    final isEmpty = body.trim().isEmpty;

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.sheet,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                S.crashLogTitle,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: AppColors.labelText,
                ),
              ),
              const SizedBox(height: 12),
              if (isEmpty)
                AppEmptyState(
                  compact: true,
                  icon: Icons.verified_rounded,
                  title: S.crashLogEmptyTitle,
                  description: S.crashLogEmpty,
                )
              else ...[
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      body,
                      style: const TextStyle(
                        fontFamily: AppFonts.jetBrainsMono,
                        color: Colors.white,
                        fontSize: 11,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, kMinTouchTarget),
                        ),
                        onPressed: () async {
                          await Clipboard.setData(ClipboardData(text: body));
                          if (!ctx.mounted) return;
                          ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(
                              content: Text(S.crashLogCopied),
                              duration: const Duration(seconds: 1),
                              backgroundColor: AppColors.card,
                            ),
                          );
                        },
                        child: Text(
                          S.crashLogCopy,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.dmSans,
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        style: TextButton.styleFrom(
                          minimumSize: const Size(0, kMinTouchTarget),
                        ),
                        onPressed: () async {
                          await CrashLogger.clear();
                          if (!ctx.mounted) return;
                          Navigator.of(ctx).pop();
                        },
                        child: Text(
                          S.crashLogClear,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.dmSans,
                            color: _crimson,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showManualResetDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          S.resetWeekTitle,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          S.resetConfirm,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: AppColors.mutedText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              S.cancel,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: AppColors.mutedText,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              S.reset,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: _crimson,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final prefs = await _getPrefs();
      await _performReset(prefs);
    }
  }

  @override
  Widget build(BuildContext context) {
    final logoCachePx =
        (28 * MediaQuery.devicePixelRatioOf(context)).round();
    return Listener(
      onPointerDown: (_) => _onUserInteraction(),
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: ValueListenableBuilder<bool>(
            valueListenable: _undoAvailable,
            builder: (context, canUndo, _) => IconButton(
              icon: Icon(
                Icons.undo_rounded,
                color: canUndo ? Colors.white : const Color(0x26FFFFFF),
              ),
              onPressed: canUndo ? _undo : null,
            ),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0x33FFFFFF),
                    width: 1,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(7),
                  child: Image.asset(
                    'assets/logo.png',
                    width: 28,
                    height: 28,
                    cacheWidth: logoCachePx,
                    cacheHeight: logoCachePx,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _cardColor,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: const Icon(
                        Icons.local_taxi_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'RateHelper',
                style: TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _overlayActive ? _emerald : const Color(0x44FFFFFF),
                  boxShadow: _overlayActive
                      ? [
                          BoxShadow(
                            color: _emerald.withValues(alpha: 0.55),
                            blurRadius: 6,
                          ),
                        ]
                      : null,
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert_rounded, color: Colors.white),
              color: AppColors.card,
              onSelected: (v) {
                if (v == 'setup') {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SetupGuideScreen(),
                    ),
                  );
                } else if (v == 'crash') {
                  _showCrashLog();
                } else if (v == 'driver_mode') {
                  _getPrefs().then((p) {
                    if (!context.mounted) return;
                    showDriverModeDialog(context, p, () {
                      if (mounted) setState(() {});
                    });
                  });
                } else if (v == 'lang') {
                  _showLanguageSelector();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'setup',
                  child: Text(
                    S.setupGuide,
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      color: Colors.white,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'crash',
                  child: Text(
                    S.crashLogTitle,
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      color: Colors.white,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'driver_mode',
                  child: Text(
                    S.driverModeLabel(activeDriverMode == DriverMode.paired),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      color: Colors.white,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'lang',
                  child: Row(
                    children: [
                      const Icon(
                        Icons.language_rounded,
                        size: 20,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        S.navLang,
                        style: const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            SafeArea(
              bottom: false,
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  20,
                  4,
                  20,
                  120 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTripGoalSelectorChip(),
                    const SizedBox(height: 12),
                    ListenableBuilder(
                      listenable: _ratesListenable,
                      builder: (context, _) {
                        final cancelColor = cancellationRate >= 5.0
                            ? _crimson
                            : _emerald;
                        final recovery = neededForRecovery;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(
                              height: 110,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(
                                    flex: 1,
                                    child: _buildRateCard(
                                      label: S.acceptRate,
                                      value: S.formatPercent(
                                        acceptanceRate.toStringAsFixed(2),
                                      ),
                                      color: _acceptRateColor,
                                      hasGlow: true,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    flex: 1,
                                    child: _buildRateCard(
                                      label: S.cancelRate,
                                      value: S.formatPercent(
                                        cancellationRate.toStringAsFixed(2),
                                      ),
                                      color: cancelColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (recovery != null) ...[
                              const SizedBox(height: 12),
                              _buildWarningCard(
                                icon: Icons.trending_up_rounded,
                                color: _amber,
                                text: S.recovery(
                                  recovery,
                                  _selectedGoal.requiredAcceptRate!,
                                ),
                              ),
                            ] else if (_selectedGoal.requiredAcceptRate !=
                                    null &&
                                acceptanceRate >=
                                    _selectedGoal.requiredAcceptRate! &&
                                acceptanceRate <
                                    _selectedGoal.requiredAcceptRate! +
                                        AMBER_BUFFER) ...[
                              const SizedBox(height: AppSpacing.sm + 4),
                              _buildWarningCard(
                                icon: Icons.shield_rounded,
                                color: _amber,
                                text: S.safeButClose,
                              ),
                            ],
                            if (_selectedGoal != TripGoal.tier0)
                              Builder(
                                builder: (context) {
                                  final budget = maxCancellationsBudget;
                                  if (budget == null) {
                                    return const SizedBox.shrink();
                                  }

                                  final isOverLimit = budget < 0;
                                  final isZeroBudget = budget == 0;

                                  final textColor = isOverLimit
                                      ? _crimson
                                      : (isZeroBudget ? _amber : _emerald);

                                  final icon = isOverLimit
                                      ? Icons.warning_amber_rounded
                                      : (isZeroBudget
                                            ? Icons.shield_rounded
                                            : Icons.info_outline_rounded);

                                  final text = isOverLimit
                                      ? S.cancellationLimitExceeded
                                      : S.maxAdditionalCancellations(budget);

                                  return Column(
                                    children: [
                                      const SizedBox(height: 12),
                                      _buildWarningCard(
                                        icon: icon,
                                        color: textColor,
                                        text: text,
                                      ),
                                    ],
                                  );
                                },
                              ),
                          ],
                        );
                      },
                    ),

                    const SizedBox(height: 32),

                    _sectionHeader(S.requests),
                    const SizedBox(height: 12),
                    _CounterRow(
                      label: S.accepted,
                      valueListenable: _accepted,
                      onDelta: (d) => _change(_keyAccepted, d),
                      onEdit: () => _showEditCounterDialog(
                        title: S.editAcceptedTitle,
                        currentValue: acceptedRequests,
                        onSave: (v) => _setCounter(_keyAccepted, v),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _CounterRow(
                      label: S.rejected,
                      valueListenable: _rejected,
                      onDelta: (d) => _change(_keyRejected, d),
                      onEdit: () => _showEditCounterDialog(
                        title: S.editRejectedTitle,
                        currentValue: rejectedRequests,
                        onSave: (v) => _setCounter(_keyRejected, v),
                      ),
                    ),

                    const SizedBox(height: 28),

                    _sectionHeader(S.trips),
                    const SizedBox(height: 12),
                    _CounterRow(
                      label: S.completed,
                      valueListenable: _completed,
                      onDelta: (d) => _change(_keyCompleted, d),
                      onEdit: () => _showEditCounterDialog(
                        title: S.editCompletedTitle,
                        currentValue: completedTrips,
                        onSave: (v) => _setCounter(_keyCompleted, v),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _CounterRow(
                      label: S.cancelled,
                      valueListenable: _canceled,
                      onDelta: (d) => _change(_keyCanceled, d),
                      onEdit: () => _showEditCounterDialog(
                        title: S.editCancelledTitle,
                        currentValue: canceledTrips,
                        onSave: (v) => _setCounter(_keyCanceled, v),
                      ),
                    ),

                    const SizedBox(height: 28),

                    _sectionHeader(S.settings),
                    const SizedBox(height: 12),
                    _buildAutoCompleteSwitch(),
                    const SizedBox(height: 10),
                    _buildSteeringWheelSwitch(),
                    const SizedBox(height: 10),
                    _buildKeepScreenOnSwitch(),
                    const SizedBox(height: 10),
                    _buildPillOrientationRow(),

                    const SizedBox(height: AppSpacing.xl),
                    SizedBox(
                      width: double.infinity,
                      child: AppDangerButton(
                        label: S.resetWeek,
                        icon: Icons.refresh_rounded,
                        onTap: _showManualResetDialog,
                      ),
                    ),

                    const SizedBox(height: 20),
                    KeyedSubtree(
                      key: ValueKey('footer-$_currentLang'),
                      child: Column(
                        children: [
                          UpdateCheckTile(versionLabel: _appVersion),
                          const SizedBox(height: 20),
                          Center(child: _buildDesignerSignature()),
                          const SizedBox(height: 12),
                          Center(child: _buildReleaseInfoRow()),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                child: KeyedSubtree(
                  key: ValueKey('nav-$_currentLang'),
                  child: _buildBottomActionBar(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Material(
      color: AppColors.elevated,
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.hairline),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: _BottomBarAction(
                icon: Icons.local_gas_station_rounded,
                label: S.quickFuelNavLabel,
                onTap: _quickAddFuelReceipt,
              ),
            ),
            Expanded(
              child: _BottomBarWidgetToggle(
                active: _overlayActive,
                busy: _overlayToggleBusy,
                onTap: _toggleOverlay,
              ),
            ),
            Expanded(
              child: _BottomBarAction(
                icon: Icons.receipt_long_rounded,
                label: S.navLogs,
                onTap: _showHistory,
              ),
            ),
            Expanded(
              child: _BottomBarAction(
                icon: Icons.radar_rounded,
                label: 'Radar',
                onTap: _openRadar,
              ),
            ),
            Expanded(
              child: _BottomBarAction(
                icon: Icons.account_balance_wallet_rounded,
                label: S.navEarnings,
                onTap: _openEarnings,
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool _navInFlight = false;

  Future<void> _pushGuarded(Widget Function() builder) async {
    if (_navInFlight) return; // swallow the accidental second tap
    _navInFlight = true;
    try {
      await Navigator.of(
        context,
      ).push(MaterialPageRoute<void>(builder: (_) => builder()));
    } finally {
      _navInFlight = false;
    }
  }

  void _openRadar() => unawaited(_pushGuarded(() => const RadarScreen()));

  Future<void> _openEarnings() async {
    await _pushGuarded(() => const EarningsScreen());
    if (mounted) setState(() {});
  }

  Future<void> _quickAddFuelReceipt() async {
    final prefs = await _getPrefs();
    await prefs.reload();
    if (!mounted) return;
    final ctrl = TextEditingController();
    double? added;
    try {
      added = await showDialog<double>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            backgroundColor: AppColors.card,
            shape: const RoundedRectangleBorder(
              borderRadius: AppRadius.mdBorder,
              side: BorderSide(color: AppColors.hairline),
            ),
            title: Text(
              S.quickAddFuelTitle,
              style: AppTextStyles.headlineStyle,
            ),
            content: TextField(
              controller: ctrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: AppTextStyles.tabularNumbers(
                fontSize: 18,
                color: Colors.white,
              ),
              autofocus: true,
              decoration: InputDecoration(
                labelText: S.amountPaidLabel,
                labelStyle: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: AppColors.mutedText,
                  fontSize: AppTextStyles.body,
                ),
                suffixText: 'PLN',
                suffixStyle: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: AppColors.actionAccent,
                  fontWeight: FontWeight.w700,
                  fontSize: AppTextStyles.body,
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: AppColors.actionAccent),
                ),
              ),
              onSubmitted: (_) {
                final val = double.tryParse(
                  ctrl.text.replaceAll(' ', '').replaceAll(',', '.').trim(),
                );
                if (val != null && val > 0) {
                  Navigator.of(ctx).pop(val);
                }
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(
                  S.cancel,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: AppColors.mutedText,
                    fontSize: AppTextStyles.body,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.actionAccent,
                  foregroundColor: Colors.black,
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.smBorder,
                  ),
                ),
                onPressed: () {
                  final val = double.tryParse(
                    ctrl.text.replaceAll(' ', '').replaceAll(',', '.').trim(),
                  );
                  if (val != null && val > 0) {
                    Navigator.of(ctx).pop(val);
                  }
                },
                child: Text(
                  S.add,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    fontWeight: FontWeight.w800,
                    fontSize: AppTextStyles.body,
                  ),
                ),
              ),
            ],
          );
        },
      );
    } finally {
      ctrl.dispose();
    }

    if (added == null || added <= 0 || !mounted) return;

    final entries = decodeEarnings(
      prefs.getString(kEarningsHistoryKey),
      onCorrupt: (raw) => prefs.setString(kEarningsCorruptBackupKey, raw),
    )..sort((a, b) => b.weekStart.compareTo(a.weekStart));

    final currentMonday = weekStartForOffset(0);
    final currentSunday = weekEndForStart(currentMonday);

    WeekEarning? currentEntry;
    int entryIndex = -1;
    for (int i = 0; i < entries.length; i++) {
      if (isSameDate(entries[i].weekStart, currentMonday)) {
        currentEntry = entries[i];
        entryIndex = i;
        break;
      }
    }

    final newReceipt = FuelReceipt(
      timestamp: DateTime.now(),
      amountPaid: added,
    );

    final List<WeekEarning> nextEntries = List.of(entries);
    final int newCount;
    if (currentEntry != null) {
      final updatedReceipts = capFuelReceipts([
        ...currentEntry.fuelReceipts,
        newReceipt,
      ]);
      newCount = updatedReceipts.length;
      nextEntries[entryIndex] = currentEntry.copyWith(
        fuelReceipts: updatedReceipts,
      );
    } else {
      newCount = 1;
      final modeStr = prefs.getString(DriverMode.key);
      final driverMode =
          modeStr == 'paired' ? DriverMode.paired : DriverMode.solo;
      nextEntries.insert(
        0,
        WeekEarning(
          id:
              '${currentMonday.millisecondsSinceEpoch}_${currentSunday.millisecondsSinceEpoch}',
          weekStart: currentMonday,
          weekEnd: currentSunday,
          driverMode: driverMode,
          netIncome: 0,
          cashReceived: 0,
          onlineHours: 0,
          driverTripCount: 0,
          hasRentalDiscount: true,
          fuelReceipts: [newReceipt],
        ),
      );
    }

    await prefs.setString(kEarningsHistoryKey, encodeEarnings(nextEntries));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          S.fuelAddedConfirmation(added.toStringAsFixed(2), newCount),
          style: const TextStyle(fontFamily: AppFonts.dmSans),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Widget _buildDesignerSignature() {
    const gold = _designerGold;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.surfaceElevated,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(color: gold.withValues(alpha: 0.22), width: 1),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'KK4181R',
            style: TextStyle(
              fontFamily: AppFonts.jetBrainsMono,
              fontSize: 12,
              letterSpacing: 3.0,
              fontWeight: FontWeight.w600,
              color: gold.withValues(alpha: 0.82),
              height: 1.2,
            ),
          ),
          const SizedBox(height: 5),
          Container(
            width: 28,
            height: 1,
            color: gold.withValues(alpha: 0.18),
          ),
          const SizedBox(height: 5),
          Text(
            S.designer.toUpperCase(),
            style: TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 2.2,
              color: gold.withValues(alpha: 0.45),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseInfoRow() {
    final version = _appVersion;
    return Text(
      version == null ? 'RateHelper' : 'RateHelper v$version',
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontFamily: AppFonts.dmSans,
        fontSize: 12,
        color: Colors.white38,
        letterSpacing: 1.5,
        fontWeight: FontWeight.w400,
        height: 1.2,
      ),
    );
  }

  Widget _buildTripGoalSelectorChip() {
    return GestureDetector(
      onTap: _showTripGoalSelector,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: _cardColor,
          border: _cardBorder,
          borderRadius: _cardRadius,
        ),
        child: Row(
          children: [
            const Icon(Icons.flag_rounded, color: _amber, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                S.tripGoalChip(
                  _selectedGoal.minTrips,
                  _selectedGoal.requiredAcceptRate,
                ),
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(
              Icons.expand_more_rounded,
              color: AppColors.mutedText,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showTripGoalSelector() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.dialog,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    S.tripGoalTitle,
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                for (final goal in TripGoal.values) ...[
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    selected: _selectedGoal == goal,
                    selectedTileColor: AppColors.selected,
                    leading: Icon(
                      Icons.outlined_flag_rounded,
                      color: _selectedGoal == goal
                          ? _amber
                          : AppColors.mutedText,
                    ),
                    title: Text(
                      S.tripGoalOption(goal.minTrips, goal.requiredAcceptRate),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: AppFonts.dmSans,
                        fontSize: 14,
                        fontWeight: _selectedGoal == goal
                            ? FontWeight.w800
                            : FontWeight.w500,
                        color: _selectedGoal == goal
                            ? Colors.white
                            : AppColors.mutedText,
                      ),
                    ),
                    trailing: _selectedGoal == goal
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: _amber,
                            size: 20,
                          )
                        : null,
                    onTap: () {
                      Navigator.pop(ctx);
                      _setTripGoal(goal);
                    },
                  ),
                  const SizedBox(height: 4),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRateCard({
    required String label,
    required String value,
    required Color color,
    bool hasGlow = false,
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: _cardColor,
        border: hasGlow
            ? Border.all(color: color.withValues(alpha: 0.4), width: 1.2)
            : _cardBorder,
        borderRadius: _cardRadius,
        boxShadow: hasGlow
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.2),
                  blurRadius: 20,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.eyebrowStyle(AppColors.labelText),
          ),
          const SizedBox(height: AppSpacing.sm),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: T.rateFor(color),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWarningCard({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
        borderRadius: _cardRadius,
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 5,
              color: color,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(icon, color: color, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        text,
                        style: TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: color,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Text(
        title,
        style: AppTextStyles.eyebrowStyle(AppColors.labelText),
      ),
    );
  }

  Widget _buildAutoCompleteSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              S.autoCompleteTrips,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedText,
              ),
            ),
          ),
          Switch(
            value: _autoCompleteTrips,
            onChanged: _setAutoCompleteTrips,
            activeThumbColor: _emerald,
            activeTrackColor: _emerald.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }

  Widget _buildSteeringWheelSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              S.steeringWheelCounter,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedText,
              ),
            ),
          ),
          Switch(
            value: _steeringWheelEnabled,
            onChanged: _setSteeringWheelCounter,
            activeThumbColor: _emerald,
            activeTrackColor: _emerald.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }

  Widget _buildKeepScreenOnSwitch() {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              S.keepScreenOn,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedText,
              ),
            ),
          ),
          Switch(
            value: _keepScreenOn,
            onChanged: _setKeepScreenOn,
            activeThumbColor: _emerald,
            activeTrackColor: _emerald.withValues(alpha: 0.45),
          ),
        ],
      ),
    );
  }

  Widget _buildPillOrientationRow() {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.xs,
              top: AppSpacing.xs,
              bottom: AppSpacing.sm,
            ),
            child: Text(
              S.overlayPillOrientation,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: AppTextStyles.body,
                fontWeight: FontWeight.w600,
                color: AppColors.mutedText,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _pillOrientationChip(
                  PillOrientation.horizontal,
                  S.overlayPillHorizontal,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _pillOrientationChip(
                  PillOrientation.vertical,
                  S.overlayPillVertical,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pillOrientationChip(PillOrientation value, String label) {
    final selected = _pillOrientation == value;
    return Material(
      color: selected ? _emerald.withValues(alpha: 0.22) : AppColors.inset,
      borderRadius: AppRadius.smBorder,
      child: InkWell(
        onTap: () => unawaited(_setPillOrientation(value)),
        borderRadius: AppRadius.smBorder,
        child: SizedBox(
          height: kMinTouchTarget + 8,
          child: Center(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: AppTextStyles.body,
                fontWeight: FontWeight.w800,
                color: selected ? _emerald : AppColors.mutedText,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The OS can switch the accessibility service off behind our back — OEM
  /// battery policies kill it, and the user can revoke it in system settings.
  /// Turn the toggle off rather than advertise a feature that is dead; one tap
  /// re-runs the permission flow. Left untouched when the check itself fails,
  /// so a channel error never disables a working counter.
  Future<void> _syncSteeringWheelState() async {
    if (!_steeringWheelEnabled && !_pendingSteeringWheelEnable) return;
    final bool? active;
    try {
      active = await _kSysChannel.invokeMethod<bool>(
        'isAccessibilityServiceEnabled',
      );
    } on PlatformException catch (e, s) {
      loge('Steering wheel sync failed', name: 'home', error: e, stack: s);
      return;
    }

    // The user was sent to Settings to switch the service on. Finish the
    // toggle for them once it actually reports active; anything less than a
    // definite `true` means keep waiting.
    if (_pendingSteeringWheelEnable) {
      if (active != true || !mounted) return;
      _pendingSteeringWheelEnable = false;
      setState(() => _steeringWheelEnabled = true);
      final prefs = await _getPrefs();
      await prefs.setBool(_keySteeringWheel, true);
      return;
    }

    // Only a definite `false` turns the toggle back off — an unknown result
    // must not disable a working counter.
    if (active != false || !mounted) return;
    setState(() => _steeringWheelEnabled = false);
    final prefs = await _getPrefs();
    await prefs.setBool(_keySteeringWheel, false);
  }

  Future<void> _setSteeringWheelCounter(bool enabled) async {
    if (enabled) {
      try {
        final bool isServiceActive =
            await _kSysChannel.invokeMethod('isAccessibilityServiceEnabled') ??
            false;
        if (!isServiceActive) {
          if (!mounted) return;
          final bool? open = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              backgroundColor: AppColors.dialogAlt,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Text(
                S.steeringWheelDialogTitle,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Longest body copy in the app (~180 chars in Polish) — must
              // stay scrollable on short screens.
              content: SingleChildScrollView(
                child: Text(
                  S.steeringWheelDialogDesc,
                  style: const TextStyle(
                    fontFamily: AppFonts.dmSans,
                    color: AppColors.mutedText,
                    height: 1.4,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, kMinTouchTarget),
                  ),
                  child: Text(
                    S.cancel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      color: AppColors.mutedText,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, kMinTouchTarget),
                  ),
                  child: Text(
                    S.openSettings,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      color: _emerald,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
          if (open == true) {
            await _kSysChannel.invokeMethod('openAccessibilitySettings');
          }
          // The service is still off at this point either way: on cancel the
          // user declined, and on "open settings" the switch is flipped in
          // another app. Turning the toggle on here would claim the media
          // keys work when nothing is listening. _pendingSteeringWheelEnable
          // finishes the job on resume once the service reports active.
          _pendingSteeringWheelEnable = open == true;
          return;
        }
      } on PlatformException catch (e, s) {
        loge('Steering wheel check failed', name: 'home', error: e, stack: s);
        // Do not enable it if we couldn't check permissions.
        return;
      }
    }
    _pendingSteeringWheelEnable = false;
    setState(() => _steeringWheelEnabled = enabled);
    final prefs = await _getPrefs();
    await prefs.setBool(_keySteeringWheel, enabled);
  }
}

/// Isolated so a +/- tap rebuilds only this row, not the whole home screen.
class _CounterRow extends StatelessWidget {
  const _CounterRow({
    required this.label,
    required this.valueListenable,
    required this.onDelta,
    this.onEdit,
  });

  final String label;
  final ValueNotifier<int> valueListenable;
  final void Function(int delta) onDelta;
  final VoidCallback? onEdit;

  static const _valueStyle = AppTextStyles.hero;

  static const _labelStyle = TextStyle(
    fontFamily: AppFonts.dmSans,
    fontSize: AppTextStyles.caption,
    fontWeight: FontWeight.w600,
    color: AppColors.mutedText,
  );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          border: Border.all(color: AppColors.cardBorderColor, width: 1),
          borderRadius: AppRadius.mdBorder,
        ),
        padding: const EdgeInsets.only(
          left: AppSpacing.lg,
          top: AppSpacing.md,
          bottom: AppSpacing.md,
          right: AppSpacing.sm,
        ),
        child: ValueListenableBuilder<int>(
          valueListenable: valueListenable,
          builder: (context, value, _) {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: _labelStyle),
                      const SizedBox(height: AppSpacing.xs),
                      GestureDetector(
                        onTap: onEdit == null
                            ? null
                            : () {
                                HapticFeedback.selectionClick();
                                onEdit!();
                              },
                        onLongPress: onEdit == null
                            ? null
                            : () {
                                HapticFeedback.mediumImpact();
                                onEdit!();
                              },
                        behavior: HitTestBehavior.opaque,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text('$value', style: _valueStyle),
                            ),
                            if (onEdit != null) ...[
                              const SizedBox(width: AppSpacing.sm),
                              const Icon(
                                Icons.edit_rounded,
                                size: 20,
                                color: AppColors.labelText,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                AppIconActionButton(
                  icon: Icons.remove_rounded,
                  tintColor: AppColors.crimson,
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    onDelta(-1);
                  },
                ),
                const SizedBox(width: AppSpacing.sm),
                AppIconActionButton(
                  icon: Icons.add_rounded,
                  tintColor: AppColors.emerald,
                  onTap: () {
                    HapticFeedback.lightImpact();
                    onDelta(1);
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _BottomBarAction extends StatelessWidget {
  const _BottomBarAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdBorder,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Color(0x0AFFFFFF),
                  borderRadius: AppRadius.smBorder,
                ),
                child: Icon(icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: AppTextStyles.eyebrow,
                  fontWeight: FontWeight.w700,
                  color: AppColors.mutedText,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BottomBarWidgetToggle extends StatelessWidget {
  const _BottomBarWidgetToggle({
    required this.active,
    required this.busy,
    required this.onTap,
  });

  static const _emerald = AppColors.emerald;

  final bool active;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: AppRadius.mdBorder,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: active ? _emerald : Colors.transparent,
                  borderRadius: AppRadius.smBorder,
                  border: Border.all(
                    color: active ? _emerald : _emerald.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                ),
                child: busy
                    ? const Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        ),
                      )
                    : Icon(
                        active ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        color: active ? Colors.white : _emerald,
                        size: 26,
                      ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                active ? S.widgetStop : S.widgetStart,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: active
                    ? const TextStyle(
                        fontFamily: AppFonts.dmSans,
                        fontSize: AppTextStyles.eyebrow,
                        fontWeight: FontWeight.w800,
                        color: AppColors.emerald,
                        letterSpacing: 0.2,
                      )
                    : const TextStyle(
                        fontFamily: AppFonts.dmSans,
                        fontSize: AppTextStyles.eyebrow,
                        fontWeight: FontWeight.w800,
                        color: AppColors.mutedText,
                        letterSpacing: 0.2,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HistorySheet extends StatefulWidget {
  const _HistorySheet({
    required this.archive,
    required this.taps,
    required this.formatTapDate,
  });

  final List<String> archive;
  final List<Map<String, dynamic>> taps;
  final String Function(DateTime dt) formatTapDate;

  @override
  State<_HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<_HistorySheet>
    with SingleTickerProviderStateMixin {
  static const _keyArchive = 'weekly_archive';
  static const _emerald = AppColors.emerald;
  static const _crimson = AppColors.crimson;

  late final TabController _tabController;
  late final List<({Map<String, dynamic> raw, DateTime? local})> _parsedTaps;
  /// Parsed once here rather than in `_ArchiveCard.build`, which re-decoded
  /// its JSON on every scroll frame and every sheet rebuild.
  late List<WeeklyArchiveEntry> _archive;
  int _lastTabIndex = 0;
  bool _todayOnly = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _parsedTaps = widget.taps
        .map(
          (e) => (
            raw: e,
            local: DateTime.tryParse(
              e['timestamp']?.toString() ?? '',
            )?.toLocal(),
          ),
        )
        .toList();
    _archive = widget.archive.map(WeeklyArchiveEntry.parse).toList();
    // TabController is an AnimationController: a bare listener fires on every
    // frame of a swipe, rebuilding the whole sheet ~60x per tab change. Only
    // the settled index matters here.
    _tabController.addListener(() {
      if (_tabController.index == _lastTabIndex) return;
      _lastTabIndex = _tabController.index;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<({Map<String, dynamic> raw, DateTime? local})> get _filteredTaps {
    if (!_todayOnly) return _parsedTaps;
    final now = DateTime.now();
    return _parsedTaps.where((t) {
      if (t.local == null) return false;
      return t.local!.year == now.year &&
          t.local!.month == now.month &&
          t.local!.day == now.day;
    }).toList();
  }

  String _tapTimeLabel(({Map<String, dynamic> raw, DateTime? local}) t) {
    final localTime = t.raw['localTime']?.toString();
    if (localTime == null || localTime.length < 5) return '';
    final hhmm = localTime.substring(0, 5);

    if (t.local == null) return hhmm;

    final now = DateTime.now();
    final isToday =
        t.local!.year == now.year &&
        t.local!.month == now.month &&
        t.local!.day == now.day;
    if (isToday) return hhmm;
    return '$hhmm · ${widget.formatTapDate(t.local!)}';
  }

  Future<void> _confirmClearTapHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          S.tapLogTab,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          S.tapHistoryClearConfirm,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: AppColors.mutedText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              S.cancel,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: AppColors.mutedText,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              S.tapHistoryClear,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: _crimson,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    await TapHistoryStore.instance.clear();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(TapHistoryStore.prefsKey);
    setState(() => _parsedTaps.clear());
  }

  Future<void> _confirmClearWeeklyArchive() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          S.weeklyTab,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          S.weeklyArchiveClearConfirm,
          style: const TextStyle(
            fontFamily: AppFonts.dmSans,
            color: AppColors.mutedText,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              S.cancel,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: AppColors.mutedText,
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              S.weeklyArchiveClear,
              style: const TextStyle(
                fontFamily: AppFonts.dmSans,
                color: _crimson,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyArchive);
    setState(() => _archive = []);
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.of(context).size.height * 0.72;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    S.history,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: AppFonts.dmSans,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: AppColors.labelText,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: TextButton.icon(
                    onPressed: _tabController.index == 0
                        ? (_parsedTaps.isEmpty ? null : _confirmClearTapHistory)
                        : (_archive.isEmpty
                              ? null
                              : _confirmClearWeeklyArchive),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(
                      _tabController.index == 0
                          ? S.tapHistoryClear
                          : S.weeklyArchiveClear,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.dmSans,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: _crimson,
                      disabledForegroundColor: AppColors.disabledText,
                      minimumSize: const Size(0, kMinTouchTarget),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TabBar(
              controller: _tabController,
              indicatorColor: _emerald,
              labelColor: Colors.white,
              unselectedLabelColor: AppColors.labelText,
              labelPadding: const EdgeInsets.symmetric(horizontal: 8),
              labelStyle: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
              unselectedLabelStyle: const TextStyle(
                fontFamily: AppFonts.dmSans,
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
              tabs: [
                _OverflowSafeTab(label: S.tapLogTab),
                _OverflowSafeTab(label: S.weeklyTab),
              ],
            ),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: TabBarView(
                controller: _tabController,
                children: [
                  _KeepAliveTabView(
                    key: const ValueKey('tab_tap_log'),
                    child: _buildTapLogTab(),
                  ),
                  _KeepAliveTabView(
                    key: const ValueKey('tab_weekly'),
                    child: _buildWeeklyTab(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTapLogTab() {
    final entries = _filteredTaps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _FilterChip(
                label: S.filterToday,
                selected: _todayOnly,
                onTap: () => setState(() => _todayOnly = true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _FilterChip(
                label: S.filterAll,
                selected: !_todayOnly,
                onTap: () => setState(() => _todayOnly = false),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: entries.isEmpty
              ? AppEmptyState(
                  compact: true,
                  icon: Icons.touch_app_outlined,
                  title: S.noTapHistoryTitle,
                  description: _todayOnly ? S.noTapHistory : S.noTapHistoryDesc,
                )
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final entry = entries[i];
                    final accepted = entry.raw['type'] == 'accepted';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm + 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: AppRadius.mdBorder,
                        border: Border.all(
                          color: AppColors.cardBorderColor,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            accepted
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            color: accepted ? _emerald : _crimson,
                            size: 18,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              accepted ? S.tapAcceptShort : S.tapRejectShort,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: AppFonts.dmSans,
                                color: accepted ? _emerald : _crimson,
                                fontSize: AppTextStyles.body,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Flexible(
                            child: Text(
                              _tapTimeLabel(entry),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: AppFonts.dmSans,
                                color: AppColors.mutedText,
                                fontSize: AppTextStyles.caption,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildWeeklyTab() {
    if (_archive.isEmpty) {
      return AppEmptyState(
        compact: true,
        icon: Icons.inventory_2_rounded,
        title: S.noHistoryTitle,
        description: S.noHistoryDesc,
      );
    }

    return ListView.separated(
      itemCount: _archive.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (_, i) => _ArchiveCard(entry: _archive[i]),
    );
  }
}

/// Tab label that shrinks to fit rather than clipping — the Polish labels
/// ("DOTKNIĘCIA", "TYGODNIOWE") are much wider than the Turkish ones.
class _OverflowSafeTab extends StatelessWidget {
  const _OverflowSafeTab({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(label, maxLines: 1, softWrap: false),
      ),
    );
  }
}

class _ArchiveCard extends StatelessWidget {
  const _ArchiveCard({required this.entry});

  static const _emerald = AppColors.emerald;
  static const _crimson = AppColors.crimson;

  final WeeklyArchiveEntry entry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.cardBorderColor),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.getFormattedDateRange(),
            style: const TextStyle(
              fontFamily: AppFonts.dmSans,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          // Wrap, not Row: the Polish chip labels ("Akceptacja"/"Anulowanie")
          // are long enough to overflow side by side on a narrow sheet.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildStatChip(
                label:
                    '%${entry.acceptRate.toStringAsFixed(0)} ${S.archiveAccept}',
                color: entry.acceptRate >= 80 ? _emerald : _crimson,
              ),
              _buildStatChip(
                label:
                    '%${entry.cancelRate.toStringAsFixed(0)} ${S.archiveCancel}',
                color: entry.cancelRate <= 5 ? _emerald : _crimson,
              ),
            ],
          ),
          if (!entry.isLegacy) ...[
            const SizedBox(height: 10),
            Text(
              '${S.accepted}: ${entry.acceptedCount} · ${S.rejected}: ${entry.rejectedCount}',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: AppFonts.jetBrainsMono,
                fontSize: 12,
                color: AppColors.mutedText,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatChip({required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontFamily: AppFonts.dmSans,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        constraints: const BoxConstraints(minHeight: kMinTouchTarget),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? AppColors.emerald.withValues(alpha: 0.15)
              : AppColors.card,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? AppColors.emerald : AppColors.cardBorderColor,
            width: 1,
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: selected
              ? const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: AppColors.emerald,
                  letterSpacing: 0.5,
                )
              : const TextStyle(
                  fontFamily: AppFonts.dmSans,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.labelText,
                  letterSpacing: 0.5,
                ),
        ),
      ),
    );
  }
}

class _LangOption extends StatelessWidget {
  const _LangOption({
    required this.flag,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final String flag;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Text(flag, style: const TextStyle(fontSize: 26)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  name,
                  style: selected
                      ? const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        )
                      : const TextStyle(
                          fontFamily: AppFonts.dmSans,
                          fontSize: 17,
                          fontWeight: FontWeight.w400,
                          color: AppColors.mutedText,
                        ),
                ),
              ),
              if (selected)
                const Icon(
                  Icons.check_rounded,
                  color: AppColors.emerald,
                  size: 22,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeepAliveTabView extends StatefulWidget {
  const _KeepAliveTabView({required this.child, super.key});

  final Widget child;

  @override
  State<_KeepAliveTabView> createState() => _KeepAliveTabViewState();
}

class _KeepAliveTabViewState extends State<_KeepAliveTabView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
