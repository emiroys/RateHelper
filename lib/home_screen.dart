import 'dart:async';
import 'dart:convert';
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
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'app_colors.dart';
import 'app_text_styles.dart';
import 'app_widgets.dart';
import 'crash_logger.dart';
import 'display_mode.dart';
import 'earnings_models.dart';
import 'earnings_screen.dart';
import 'env.dart';
import 'format_rate.dart';
import 'instruments/bezel.dart';
import 'instruments/gauge_painter.dart';
import 'instruments/plate.dart';
import 'instruments/shift_clock.dart';
import 'models/weekly_archive_entry.dart';
import 'l10n.dart';
import 'log.dart';
import 'onboarding_screen.dart';
import 'overlay_sync.dart';
import 'services/event_service.dart';
import 'overlay_widget.dart';
import 'radar_screen.dart';
import 'shift_counter_store.dart';
import 'tap_history_store.dart';

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

const String kReleaseName =
    "2. Büyük Güncelleme"; // update manually each significant release

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

  /// Asset name on GitHub Releases must match this exactly (case-sensitive).
  static const _expectedApkAsset = 'app-arm64-v8a-release.apk';

  /// Only this host is reachable through the hardened HttpClient. A
  /// compromised DNS / hostile WiFi / hijacked Gist URL cannot redirect
  /// us elsewhere because we re-validate the host on every request and
  /// refuse to follow redirects.
  static const _allowedManifestHost = 'gist.githubusercontent.com';

  /// Only APK URLs starting with this prefix are passed to the OS
  /// browser. A compromised Gist that swaps `apk_url` for a malicious
  /// site is silently ignored — the user never sees a download prompt.
  static const _allowedApkUrlPrefix =
      'https://github.com/emiroys/ratehelper/releases/';

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
  static const _gold = AppColors.gold;
  static final _cardBorder = kCardBorder;
  static final _cardRadius = kCardBorderRadius;

  SharedPreferences? _prefs;
  AppLang _currentLang = AppLang.tr;
  String _versionLabel = '';
  bool _showRawVersion = false;
  String? _debugBuildSignature;

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
  TripGoal _selectedGoal = TripGoal.tier1;
  String _plate = kDefaultPlate;
  Color? _flashColor;
  Color? _prevAcceptBand;
  Timer? _flashTimer;

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
    _getActualSignature(info.buildSignature);
    if (kReleaseMode) {
      final trusted = await _verifySignature(info.buildSignature);
      if (!trusted) return;
    }
    if (mounted) {
      setState(() {
        _currentLang = lang;
        _versionLabel = 'v${info.version}+${info.buildNumber}';
      });
    }
    unawaited(_checkForUpdate(info.version));
    _loadAndCheckReset();
    unawaited(_refreshOverlayState());
    _plate = prefs.getString(kDriverPlateKey) ?? kDefaultPlate;
    if (mounted) setState(() {});
  }

  String _normalizeSignature(String sig) =>
      sig.replaceAll(':', '').replaceAll(' ', '').toUpperCase();

  /// Debug only: surfaces [buildSignature] on screen so it can be copied into `.env`.
  /// No-op in release builds.
  void _getActualSignature(String buildSignature) {
    if (kReleaseMode) return;
    if (!mounted) return;
    setState(() => _debugBuildSignature = buildSignature);
  }

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

  /// Parses semver `major.minor.patch` numerically — never string-compare.
  List<int> _parseVersionParts(String version) {
    var core = version.trim();
    if (core.startsWith('v') || core.startsWith('V')) {
      core = core.substring(1).trim();
    }
    core = core.split('+').first.split('-').first.trim();
    final parts = <int>[];
    for (final segment in core.split('.')) {
      final parsed = int.tryParse(segment.trim());
      if (parsed == null) break;
      parts.add(parsed);
    }
    while (parts.length < 3) {
      parts.add(0);
    }
    return parts.take(3).toList();
  }

  /// True only when [latest] is strictly greater than [current] (numeric semver).
  bool _isNewerVersion(String latest, String current) {
    final latestParts = _parseVersionParts(latest);
    final currentParts = _parseVersionParts(current);

    for (var i = 0; i < 3; i++) {
      if (latestParts[i] > currentParts[i]) return true;
      if (latestParts[i] < currentParts[i]) return false;
    }
    return false;
  }

  bool _isValidApkUrl(String apkUrl) {
    if (!apkUrl.startsWith(_allowedApkUrlPrefix)) return false;
    if (!apkUrl.endsWith('/$_expectedApkAsset')) return false;
    final uri = Uri.tryParse(apkUrl);
    if (uri == null || uri.scheme != 'https' || uri.host != 'github.com') {
      return false;
    }
    return uri.pathSegments.contains('latest') &&
        uri.pathSegments.contains('download');
  }

  Future<Map<String, String>?> _fetchUpdateManifest() async {
    // Pre-flight host check. Even if the constant is ever edited to a
    // hostile URL, this re-derivation rejects anything outside the
    // single approved host.
    final manifestUri = Uri.tryParse(Env.gistUrl);
    if (manifestUri == null ||
        manifestUri.scheme != 'https' ||
        manifestUri.host != _allowedManifestHost) {
      return null;
    }

    final client = HttpClient();
    try {
      client.connectionTimeout = const Duration(seconds: 8);
      // No automatic redirect-following. A compromised Gist that
      // 30x-redirects us to attacker.example would bypass the host
      // allowlist if we let HttpClient chase the Location header.
      client.autoUncompress = true;

      final request = await client
          .getUrl(manifestUri)
          .timeout(const Duration(seconds: 8));
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) return null;

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;

      final latest = decoded['latest']?.toString().trim();
      final apkUrl = decoded['apk_url']?.toString().trim();
      if (latest == null ||
          latest.isEmpty ||
          apkUrl == null ||
          apkUrl.isEmpty) {
        return null;
      }
      return {'latest': latest, 'apk_url': apkUrl};
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _openApkUrl(String url) async {
    // Belt-and-braces: re-verify the allowlist at the final hand-off
    // to the OS browser. If a caller ever forgets the upstream check,
    // we still refuse to dispatch unknown URLs.
    if (!url.startsWith(_allowedApkUrlPrefix)) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (uri.scheme != 'https' || uri.host != 'github.com') return;
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      // Silent — same policy as the manifest fetch.
    }
  }

  Future<void> _checkForUpdate(String currentVersion) async {
    final manifest = await _fetchUpdateManifest();
    if (!mounted || manifest == null) return;

    final latest = manifest['latest']!;
    final apkUrl = manifest['apk_url']!;

    if (!_isValidApkUrl(apkUrl)) return;
    if (!_isNewerVersion(latest, currentVersion)) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.updateAvailable(latest)),
        duration: const Duration(seconds: 10),
        backgroundColor: AppColors.card,
        action: SnackBarAction(
          label: S.updateDownload,
          textColor: _emerald,
          onPressed: () => unawaited(_openApkUrl(apkUrl)),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // Detach the media-key handler so the static channel cannot retain
    // this State or invoke setState() on it after disposal.
    _kSysChannel.setMethodCallHandler(null);
    _overlayListenerSub?.cancel();
    _saveDebounce?.cancel();
    _wakelockIdleTimer?.cancel();
    _flashTimer?.cancel();
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
      unawaited(DisplayMode.instance.playSelfTest());
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
    _loadAndCheckReset();
    await _drainPendingTaps();
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
    final counts = snapshot ?? await ShiftCounterStore.instance.read();
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
    final disk = await ShiftCounterStore.instance.read();

    final newAccepted = (disk.accepted + (acceptedRequests - _baselineAccepted))
        .clamp(0, 99999);
    final newRejected = (disk.rejected + (rejectedRequests - _baselineRejected))
        .clamp(0, 99999);
    final newCompleted = (disk.completed + (completedTrips - _baselineCompleted))
        .clamp(0, 99999);
    final newCanceled = (disk.canceled + (canceledTrips - _baselineCanceled))
        .clamp(0, 99999);

    if (mounted) {
      acceptedRequests = newAccepted;
      rejectedRequests = newRejected;
      completedTrips = newCompleted;
      canceledTrips = newCanceled;
      _syncBaseline();
    }

    await ShiftCounterStore.instance.write(
      ShiftCounters(
        accepted: newAccepted.toInt(),
        rejected: newRejected.toInt(),
        completed: newCompleted.toInt(),
        canceled: newCanceled.toInt(),
      ),
    );
    unawaited(
      OverlaySync.notifyCountersChanged(
        accepted: newAccepted,
        rejected: newRejected,
        completed: newCompleted,
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
          style: T.titleSm.copyWith(fontWeight: FontWeight.w700),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.hairlineFaint,
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
      backgroundColor: AppColors.base,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSheetHandle(),
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

      final granted = await FlutterOverlayWindow.isPermissionGranted();
      if (!granted) {
        await FlutterOverlayWindow.requestPermission();
        final check = await FlutterOverlayWindow.isPermissionGranted();
        if (!check) return;
      }
      if (!mounted) return;

      // Native window sized to the pill (dp) so touches pass through elsewhere.
      await FlutterOverlayWindow.showOverlay(
        width: OverlayWidget.nativeWindowWidthDp,
        height: OverlayWidget.nativeWindowHeightDp,
        alignment: OverlayAlignment.topLeft,
        visibility: NotificationVisibility.visibilitySecret,
        flag: OverlayFlag.defaultFlag,
        enableDrag: true,
        positionGravity: PositionGravity.none,
        startPosition: const OverlayPosition(0, 60),
        overlayTitle: 'RateHelper',
      );

      await OverlaySync.notifyCountersChanged();
      unawaited(OverlaySync.notifySunMode(kSunMode.value));

      if (!mounted) return;
      setState(() => _overlayActive = true);
    } on PlatformException catch (e, s) {
      loge('overlay toggle failed', name: 'home', error: e, stack: s);
      if (!mounted) return;
      // Re-derive truth from the plugin instead of guessing:
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
      backgroundColor: AppColors.base,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _HistorySheet(
        archive: archive,
        taps: taps,
        formatTapDate: _formatTapDate,
        plate: _plate,
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
      backgroundColor: AppColors.base,
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
                style: T.sectionHeader,
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
                      style: T.monoSm,
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
    final sun = Theme.of(context).brightness == Brightness.light;
    final ink = AppColors.ink(sun);
    final scaffold = AppColors.scaffold(sun);
    return Listener(
      onPointerDown: (_) => _onUserInteraction(),
      child: Scaffold(
        backgroundColor: scaffold,
        appBar: AppBar(
          backgroundColor: scaffold,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: ValueListenableBuilder<bool>(
            valueListenable: _undoAvailable,
            builder: (context, canUndo, _) => IconButton(
              icon: Icon(
                Icons.undo_rounded,
                color: canUndo ? ink : AppColors.mutedFor(sun),
              ),
              onPressed: canUndo ? _undo : null,
            ),
          ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              LicensePlate(text: _plate, height: 26, compact: true),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _overlayActive
                      ? AppColors.emeraldFor(sun)
                      : AppColors.trackFor(sun),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _overlayActive ? S.overlayOn : S.overlayOff,
                  style: T.captionSm.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _overlayActive ? Colors.white : AppColors.ink(sun),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            PopupMenuButton<String>(
              icon: Icon(Icons.more_vert_rounded, color: ink),
              color: AppColors.cardBg(sun),
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
                } else if (v == 'display') {
                  DisplayMode.instance.cyclePref();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'setup',
                  child: Text(
                    S.setupGuide,
                    style: TextStyle(
                      fontFamily: AppFonts.dmSans,
                      color: ink,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'display',
                  child: Text(
                    '${S.displayModeAuto}/${S.displayModeSun}/${S.displayModeDark}',
                    style: TextStyle(
                      fontFamily: AppFonts.dmSans,
                      color: ink,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'crash',
                  child: Text(
                    S.crashLogTitle,
                    style: TextStyle(
                      fontFamily: AppFonts.dmSans,
                      color: ink,
                    ),
                  ),
                ),
                PopupMenuItem(
                  value: 'driver_mode',
                  child: Text(
                    S.driverModeLabel(activeDriverMode == DriverMode.paired),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: AppFonts.dmSans,
                      color: ink,
                    ),
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
                      listenable: Listenable.merge([
                        _ratesListenable,
                        kGaugeSweep,
                      ]),
                      builder: (context, _) {
                        final sun =
                            Theme.of(context).brightness == Brightness.light;
                        final band = _acceptRateColor;
                        if (_prevAcceptBand != null &&
                            _prevAcceptBand != band) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (!mounted) return;
                            HapticFeedback.heavyImpact();
                            setState(() => _flashColor = band);
                            _flashTimer?.cancel();
                            _flashTimer = Timer(
                              const Duration(milliseconds: 600),
                              () {
                                if (mounted) {
                                  setState(() => _flashColor = null);
                                }
                              },
                            );
                          });
                        }
                        _prevAcceptBand = band;
                        final cancelColor = cancellationRate >= 5.0
                            ? AppColors.crimsonFor(sun)
                            : AppColors.emeraldFor(sun);
                        final req = _selectedGoal.requiredAcceptRate;
                        final acceptHeadroom =
                            req == null ? 100.0 : acceptanceRate - req;
                        final cancelHeadroom = 5.0 - cancellationRate;
                        final worstIsCancel = req != null &&
                            cancelHeadroom < acceptHeadroom;
                        final sweep = kGaugeSweep.value;
                        final stateColor = AppColors.stateFor(band, sun);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                              decoration: instrumentBezel(
                                sun: sun,
                                flash: _flashColor == null
                                    ? null
                                    : AppColors.stateFor(_flashColor!, sun),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Expanded(
                                    flex: 5,
                                    child: ArcGauge(
                                      value: acceptanceRate,
                                      arcValue: acceptanceRate * sweep,
                                      redline: req,
                                      color: stateColor,
                                      label: S.acceptRate,
                                      caption: worstIsCancel
                                          ? S.constraintCancel
                                          : (req == null
                                              ? null
                                              : S.constraintAccept),
                                      sun: sun,
                                      size: 220,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    flex: 2,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 14,
                                        horizontal: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: sun && cancellationRate >= 5
                                            ? AppColors.sunCrimson
                                            : Colors.transparent,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: cancelColor.withValues(
                                            alpha: 0.55,
                                          ),
                                        ),
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            cancellationRate >= 5
                                                ? Icons.warning_rounded
                                                : Icons.shield_rounded,
                                            color: sun && cancellationRate >= 5
                                                ? Colors.white
                                                : cancelColor,
                                            size: 18,
                                          ),
                                          const SizedBox(height: 6),
                                          Text(
                                            S.cancelRate,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: T.caption.copyWith(
                                              fontWeight: FontWeight.w800,
                                              color: sun &&
                                                      cancellationRate >= 5
                                                  ? Colors.white
                                                  : AppColors.labelFor(sun),
                                            ),
                                          ),
                                          const SizedBox(height: 4),
                                          FittedBox(
                                            child: Text(
                                              formatRatePercent(
                                                cancellationRate,
                                              ),
                                              style: T.rateFor(
                                                cancelColor,
                                                sun: sun,
                                              ).copyWith(
                                                fontSize: 22,
                                                color: sun &&
                                                        cancellationRate >= 5
                                                    ? Colors.white
                                                    : cancelColor,
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
                            const SizedBox(height: 12),
                            _buildStateStrip(sun),
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
                    _buildAutoCompleteSwitch(),
                    const SizedBox(height: 10),
                    _buildSteeringWheelSwitch(),
                    const SizedBox(height: 10),
                    _buildKeepScreenOnSwitch(),
                    const SizedBox(height: 10),
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

                    const SizedBox(height: 40),

                    Material(
                      color: _cardColor,
                      borderRadius: _cardRadius,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.mediumImpact();
                          _showManualResetDialog();
                        },
                        borderRadius: _cardRadius,
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 18),
                          decoration: BoxDecoration(
                            border: _cardBorder,
                            borderRadius: _cardRadius,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            S.resetWeek,
                            style: T.labelStrong.copyWith(
                              letterSpacing: 2,
                              color: _crimson,
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),
                    KeyedSubtree(
                      key: ValueKey('footer-$_currentLang'),
                      child: Column(
                        children: [
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
    final sun = Theme.of(context).brightness == Brightness.light;
    return Material(
      color: AppColors.elevatedBg(sun),
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: AppColors.hairlineFor(sun)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: _BottomBarAction(
                icon: Icons.language_rounded,
                label: S.navLang,
                onTap: _showLanguageSelector,
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
                icon: Icons.list_alt_rounded,
                label: S.navLogs,
                onTap: _showHistory,
              ),
            ),
            Expanded(
              child: _BottomBarAction(
                icon: Icons.radar_rounded,
                label: S.navRadar,
                onTap: _openRadar,
              ),
            ),
            Expanded(
              child: _BottomBarAction(
                icon: Icons.payments_rounded,
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

  Widget _buildDesignerSignature() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border.all(color: AppColors.hairlineStrong, width: 1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'KK4181R',
            style: T.captionSm.copyWith(
              fontFamily: AppFonts.jetBrainsMono,
              color: _gold,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            S.designer,
            style: T.nano.copyWith(
              letterSpacing: 1.5,
              color: _gold.withValues(alpha: 0.65),
              height: 1,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReleaseInfoRow() {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _showRawVersion = !_showRawVersion);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'RateHelper — ${S.releaseName}',
                textAlign: TextAlign.center,
                style: T.micro.copyWith(
                  fontFamily: AppFonts.jetBrainsMono,
                  color: AppColors.mutedText,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_versionLabel.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  _showRawVersion ? '${S.version} $_versionLabel' : _versionLabel,
                  textAlign: TextAlign.center,
                  style: _showRawVersion
                      ? T.nano.copyWith(
                          fontFamily: AppFonts.jetBrainsMono,
                          fontWeight: FontWeight.w400,
                          letterSpacing: 1.0,
                        )
                      : T.nano.copyWith(
                          fontFamily: AppFonts.jetBrainsMono,
                          color: AppColors.disabledText,
                          letterSpacing: 1.0,
                          fontWeight: FontWeight.w400,
                        ),
                ),
              ],
              if (_showRawVersion &&
                  !kReleaseMode &&
                  _debugBuildSignature != null &&
                  _debugBuildSignature!.isNotEmpty) ...[
                const SizedBox(height: 4),
                SelectableText(
                  'SIG: $_debugBuildSignature',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontFamily: AppFonts.jetBrainsMono,
                    fontSize: 8,
                    color: Color(0x55FFFFFF),
                    letterSpacing: 0.5,
                    height: 1.3,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTripGoalSelectorChip() {
    return Material(
      color: _cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: _cardRadius,
        side: const BorderSide(color: AppColors.hairlineFaint, width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          _showTripGoalSelector();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  style: T.labelStrong,
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
      ),
    );
  }

  void _showTripGoalSelector() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.base,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSheetHandle(),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  child: Text(
                    S.tripGoalTitle,
                    style: T.eyebrow,
                  ),
                ),
                const SizedBox(height: 12),
                for (final goal in TripGoal.values) ...[
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    selected: _selectedGoal == goal,
                    selectedTileColor: AppColors.raised,
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
                      style: _selectedGoal == goal
                          ? T.bodyStrong
                          : T.body.copyWith(color: AppColors.mutedText),
                    ),
                    trailing: _selectedGoal == goal
                        ? const Icon(
                            Icons.check_circle_rounded,
                            color: _amber,
                            size: 20,
                          )
                        : null,
                    onTap: () {
                      HapticFeedback.selectionClick();
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

  Widget _buildStateStrip(bool sun) {
    final recovery = neededForRecovery;
    final budget = _selectedGoal == TripGoal.tier0
        ? null
        : maxCancellationsBudget;
    final req = _selectedGoal.requiredAcceptRate;
    final close = req != null &&
        recovery == null &&
        acceptanceRate >= req &&
        acceptanceRate < req + AMBER_BUFFER;

    Color color;
    IconData icon;
    Widget body;

    if (recovery != null) {
      color = AppColors.crimsonFor(sun);
      icon = Icons.trending_up_rounded;
      body = Row(
        children: [
          Text(
            S.recoveryCount(recovery),
            style: T.heroOverlay.copyWith(
              fontSize: 28,
              color: sun ? Colors.white : color,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              S.recovery(recovery, req ?? 80),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: T.body.copyWith(
                fontWeight: FontWeight.w600,
                color: sun ? Colors.white : color,
              ),
            ),
          ),
        ],
      );
    } else if (budget != null && budget < 0) {
      color = AppColors.crimsonFor(sun);
      icon = Icons.warning_amber_rounded;
      body = Text(
        S.cancellationLimitExceeded,
        style: T.body.copyWith(
          fontWeight: FontWeight.w700,
          color: sun ? Colors.white : color,
        ),
      );
    } else if (close) {
      color = AppColors.amberFor(sun);
      icon = Icons.shield_rounded;
      body = Text(
        S.safeButClose,
        style: T.body.copyWith(
          fontWeight: FontWeight.w600,
          color: sun ? Colors.white : color,
        ),
      );
    } else if (budget != null) {
      color = budget == 0
          ? AppColors.amberFor(sun)
          : AppColors.emeraldFor(sun);
      icon = budget == 0 ? Icons.shield_rounded : Icons.info_rounded;
      body = Text(
        S.maxAdditionalCancellations(budget),
        style: T.body.copyWith(
          fontWeight: FontWeight.w600,
          color: sun ? Colors.white : color,
        ),
      );
    } else {
      return const SizedBox.shrink();
    }

    final fill = sun ? color : AppColors.cardBg(sun);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: fill,
        border: Border.all(color: color.withValues(alpha: sun ? 0 : 0.55)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: sun ? Colors.white : color, size: 22),
          const SizedBox(width: 12),
          Expanded(child: body),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    final sun = Theme.of(context).brightness == Brightness.light;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: T.bodyStrong.copyWith(
          letterSpacing: 1.2,
          color: AppColors.labelFor(sun),
        ),
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
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              S.autoCompleteTrips,
              style: T.body.copyWith(
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
              style: T.body.copyWith(
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
              style: T.body.copyWith(
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
              backgroundColor: AppColors.raised,
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
        }
      } on PlatformException catch (e, s) {
        loge('Steering wheel check failed', name: 'home', error: e, stack: s);
        // Do not enable it if we couldn't check permissions.
        return;
      }
    }
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

  static const _valueStyle = T.heroSmall;

  static const _labelStyle = T.titleXs;

  @override
  Widget build(BuildContext context) {
    final sun = Theme.of(context).brightness == Brightness.light;
    final valueStyle = _valueStyle.copyWith(color: AppColors.ink(sun));
    final labelStyle = _labelStyle.copyWith(color: AppColors.mutedFor(sun));
    return RepaintBoundary(
      child: Container(
        decoration: instrumentBezel(sun: sun),
        padding: const EdgeInsets.only(left: 20, top: 16, bottom: 16, right: 8),
        child: ValueListenableBuilder<int>(
          valueListenable: valueListenable,
          builder: (context, value, _) {
            return Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: labelStyle),
                      const SizedBox(height: 4),
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
                              child: Text('$value', style: valueStyle),
                            ),
                            if (onEdit != null) ...[
                              const SizedBox(width: 8),
                              Icon(
                                Icons.edit_rounded,
                                size: 22,
                                color: AppColors.labelFor(sun),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                _CounterIconButton(
                  icon: Icons.remove_rounded,
                  color: AppColors.crimson,
                  mediumHaptic: true,
                  onTap: () => onDelta(-1),
                ),
                const SizedBox(width: 6),
                _CounterIconButton(
                  icon: Icons.add_rounded,
                  color: AppColors.emerald,
                  onTap: () => onDelta(1),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _CounterIconButton extends StatelessWidget {
  const _CounterIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    this.mediumHaptic = false,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool mediumHaptic;

  @override
  Widget build(BuildContext context) {
    return AppCircleButton(
      icon: icon,
      color: color,
      onTap: onTap,
      size: 56,
      mediumHaptic: mediumHaptic,
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
    final sun = Theme.of(context).brightness == Brightness.light;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: AppColors.ink(sun)),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: T.body.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppColors.mutedFor(sun),
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
        onTap: busy
            ? null
            : () {
                HapticFeedback.selectionClick();
                onTap();
              },
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: active ? _emerald : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: active ? _emerald : _emerald.withValues(alpha: 0.55),
                    width: 1.5,
                  ),
                ),
                child: busy
                    ? Center(
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.6,
                            color: active ? Colors.white : _emerald,
                          ),
                        ),
                      )
                    : Icon(
                        active ? Icons.stop_rounded : Icons.play_arrow_rounded,
                        color: active ? Colors.white : _emerald,
                        size: 28,
                      ),
              ),
              const SizedBox(height: 4),
              Text(
                active ? S.widgetStop : S.widgetStart,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: active
                    ? T.captionSm.copyWith(
                        fontWeight: FontWeight.w800,
                        color: AppColors.emerald,
                        letterSpacing: 0.2,
                      )
                    : T.captionSm.copyWith(
                        fontWeight: FontWeight.w800,
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
    required this.plate,
  });

  final List<String> archive;
  final List<Map<String, dynamic>> taps;
  final String Function(DateTime dt) formatTapDate;
  final String plate;

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
  late List<String> _archive;
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
    _archive = List<String>.from(widget.archive);
    _tabController.addListener(() {
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
            const AppSheetHandle(),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    S.history,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: T.sectionHeader,
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
                      style: T.caption.copyWith(
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
              labelStyle: T.captionSm.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
                color: Colors.white,
              ),
              unselectedLabelStyle: T.captionSm.copyWith(
                letterSpacing: 1.5,
                color: AppColors.labelText,
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
        if (widget.taps.isNotEmpty) ...[
          Text(
            S.shiftClockTitle,
            style: T.sectionHeader.copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 8),
          Center(child: ShiftClock(taps: widget.taps, size: 180)),
          const SizedBox(height: 12),
        ],
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
                  icon: Icons.touch_app_rounded,
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
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: AppColors.hairlineFaint,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            accepted
                                ? Icons.check_circle_rounded
                                : Icons.cancel_rounded,
                            size: 18,
                            color: accepted ? _emerald : _crimson,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              accepted ? S.tapAcceptShort : S.tapRejectShort,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: T.titleXs.copyWith(
                                fontWeight: FontWeight.w700,
                                color: accepted ? _emerald : _crimson,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              _tapTimeLabel(entry),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: T.label.copyWith(
                                fontFamily: AppFonts.jetBrainsMono,
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
      itemBuilder: (_, i) => _ArchiveCard(
        rawEntry: _archive[i],
        plate: widget.plate,
      ),
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
  const _ArchiveCard({required this.rawEntry, required this.plate});

  static const _emerald = AppColors.emerald;
  static const _crimson = AppColors.crimson;

  final String rawEntry;
  final String plate;

  @override
  Widget build(BuildContext context) {
    final entry = WeeklyArchiveEntry.parse(rawEntry);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border.all(color: AppColors.hairlineFaint),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.getFormattedDateRange(),
            style: T.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          LicensePlate(text: plate, height: 22, compact: true),
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
              style: T.caption.copyWith(
                fontFamily: AppFonts.jetBrainsMono,
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
        style: T.captionSm.copyWith(
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
    return Material(
      color: selected
          ? AppColors.emerald.withValues(alpha: 0.15)
          : AppColors.card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: selected ? AppColors.emerald : AppColors.hairlineFaint,
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Container(
          constraints: const BoxConstraints(minHeight: kMinTouchTarget),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          alignment: Alignment.center,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: selected
                ? T.labelStrong.copyWith(
                    color: AppColors.emerald,
                    letterSpacing: 0.5,
                  )
                : T.label.copyWith(
                    color: AppColors.labelText,
                    letterSpacing: 0.5,
                  ),
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
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
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
                      ? T.titleMd.copyWith(fontWeight: FontWeight.w700)
                      : T.titleMd.copyWith(
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
