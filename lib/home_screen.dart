import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'crash_logger.dart';
import 'earnings_models.dart';
import 'earnings_screen.dart';
import 'env.dart';
import 'l10n.dart';
import 'log.dart';
import 'onboarding_screen.dart';
import 'overlay_sync.dart';
import 'overlay_widget.dart';
import 'radar_screen.dart';

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

  int get minTrips => activeDriverMode == DriverMode.paired ? pairedMinTrips : soloMinTrips;
}

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
  static const _keyTripGoal = 'trip_goal_tier';
  static const _kSysChannel = MethodChannel('com.ratehelper.app/system');
  static const _keyLastReset = 'lastResetTimestamp';
  static const _keyArchive = 'weekly_archive';
  static const _keyTapHistory = 'tapHistory';
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

  static final _warsaw = tz.getLocation('Europe/Warsaw');

  static const _cardColor = Color(0xFF1A1A1A);
  static const _emerald = Color(0xFF10B981);
  static const _crimson = Color(0xFFEF4444);
  static const _amber = Color(0xFFF59E0B);
  static const _designerGold = Color(0xFFD4AF37);
  static final _cardBorder = Border.all(color: const Color(0x0DFFFFFF), width: 1);
  static final _cardRadius = BorderRadius.circular(16);

  SharedPreferences? _prefs;
  AppLang _currentLang = AppLang.tr;
  String _versionLabel = '';
  String? _debugBuildSignature;

  int acceptedRequests = 0;
  int rejectedRequests = 0;
  int completedTrips = 0;
  int canceledTrips = 0;
  bool _autoCompleteTrips = false;
  bool _steeringWheelEnabled = false;
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
  bool _isLoadingOrResetting = false;
  bool _overlayActive = false;
  StreamSubscription<dynamic>? _overlayListenerSub;

  bool get _canUndo => _prevAccepted != null;

  int get totalRequests => acceptedRequests + rejectedRequests;
  double get acceptanceRate =>
      totalRequests == 0 ? 100.0 : (acceptedRequests / totalRequests) * 100;

  int get totalAcceptedTrips => completedTrips + canceledTrips;
  double get cancellationRate =>
      totalAcceptedTrips == 0 ? 0.0 : (canceledTrips / totalAcceptedTrips) * 100;

  int? get neededForRecovery => calculateNeededForRecovery(
        acceptedRequests: acceptedRequests,
        rejectedRequests: rejectedRequests,
        requiredAcceptRate: _selectedGoal.requiredAcceptRate,
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
    WakelockPlus.enable();
    try {
      _overlayListenerSub = FlutterOverlayWindow.overlayListener.listen((event) {
        if (OverlaySync.shouldReloadCounters(event)) {
          _reloadAndSync();
        }
      });
    } catch (e, s) {
      loge('overlayListener listen failed in home screen', name: 'home', error: e, stack: s);
    }
    _kSysChannel.setMethodCallHandler((call) async {
      if (call.method == 'onMediaKeyIncrement') {
        final keyStr = call.arguments as String?;
        final key = keyStr == 'accepted' ? _keyAccepted : _keyRejected;
        _change(key, 1);
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
    unawaited(_checkForUpdate());
    _loadAndCheckReset();
    unawaited(_refreshOverlayState());
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
            backgroundColor: const Color(0xFF1A1A1A),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              'Güvenlik Uyarısı',
              style: GoogleFonts.dmSans(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
            content: Text(
              'Bu uygulama değiştirilmiş. Güvenliğiniz için kapatılıyor.',
              style: GoogleFonts.dmSans(color: Colors.white70, height: 1.4),
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

      final request = await client.getUrl(manifestUri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return null;

      final body = await response.transform(utf8.decoder).join();
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

  Future<void> _checkForUpdate() async {
    final info = await PackageInfo.fromPlatform();
    final currentVersion = info.version.trim();

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
        backgroundColor: const Color(0xFF1A1A1A),
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
    _overlayListenerSub?.cancel();
    _saveDebounce?.cancel();
    _flushSave();
    WakelockPlus.disable();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      WakelockPlus.enable();
      _reloadAndSync();
    } else if (state == AppLifecycleState.paused) {
      _flushSave();
      WakelockPlus.disable();
    }
  }

  Future<void> _reloadAndSync() async {
    final prefs = await _getPrefs();
    await prefs.reload();
    if (!mounted) return;
    _loadAndCheckReset();
    unawaited(_refreshOverlayState());
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
      4, 0, 0,
    );
    if (now.isBefore(monday)) {
      return tz.TZDateTime(
        _warsaw,
        monday.year,
        monday.month,
        monday.day - 7,
        4, 0, 0,
      );
    }
    return monday;
  }

  tz.TZDateTime _nowWarsaw() => tz.TZDateTime.now(_warsaw);

  String _formatDateRange(tz.TZDateTime monday4am) {
    final months = S.months;
    final weekStart = monday4am;
    final weekEnd = tz.TZDateTime(
      _warsaw,
      weekStart.year,
      weekStart.month,
      weekStart.day + 6,
      4, 0, 0,
    );
    final startMonth = months[weekStart.month];
    final endMonth = months[weekEnd.month];
    if (weekStart.month == weekEnd.month) {
      return '${weekStart.day}-${weekEnd.day} $endMonth';
    }
    return '${weekStart.day} $startMonth - ${weekEnd.day} $endMonth';
  }

  Future<void> _loadAndCheckReset() async {
    if (_isLoadingOrResetting) return;
    _isLoadingOrResetting = true;

    try {
      final prefs = await _getPrefs();
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
      activeDriverMode = modeStr == 'paired' ? DriverMode.paired : DriverMode.solo;

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
        await _performReset(prefs, resetBoundary);
        if (mounted) {
          setState(() {
            _selectedGoal = loadedGoal;
          });
        }
      } else {
        if (!mounted) return;
        setState(() {
          _selectedGoal = loadedGoal;
          acceptedRequests = prefs.getInt(_keyAccepted) ?? 0;
          rejectedRequests = prefs.getInt(_keyRejected) ?? 0;
          completedTrips = prefs.getInt(_keyCompleted) ?? 0;
          canceledTrips = prefs.getInt(_keyCanceled) ?? 0;
          _autoCompleteTrips = prefs.getBool(_keyAutoComplete) ?? false;
          _steeringWheelEnabled = prefs.getBool(_keySteeringWheel) ?? false;
          _syncBaseline();
        });
        unawaited(OverlaySync.notifyCountersChanged());
      }
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
    unawaited(OverlaySync.notifyCountersChanged());
  }

  Future<void> _performReset(SharedPreferences prefs, [tz.TZDateTime? boundary]) async {
    final snap = _buildArchiveEntry(prefs, boundary);
    if (snap != null) {
      final archive = prefs.getStringList(_keyArchive) ?? [];
      archive.add(snap);
      await prefs.setStringList(_keyArchive, archive);
    }

    await prefs.setInt(_keyAccepted, 0);
    await prefs.setInt(_keyRejected, 0);
    await prefs.setInt(_keyCompleted, 0);
    await prefs.setInt(_keyCanceled, 0);
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
    unawaited(OverlaySync.notifyCountersChanged());
  }

  String? _buildArchiveEntry(SharedPreferences prefs, tz.TZDateTime? boundary) {
    final accepted = prefs.getInt(_keyAccepted) ?? 0;
    final rejected = prefs.getInt(_keyRejected) ?? 0;
    final completed = prefs.getInt(_keyCompleted) ?? 0;
    final canceled = prefs.getInt(_keyCanceled) ?? 0;

    final total = accepted + rejected;
    final totalTrips = completed + canceled;

    if (total == 0 && totalTrips == 0) return null;

    final aRate = total == 0 ? 100.0 : (accepted / total) * 100;
    final cRate = totalTrips == 0 ? 0.0 : (canceled / totalTrips) * 100;

    final rangeLabel = boundary != null
        ? _formatDateRange(boundary)
        : _formatDateRange(_lastMonday4amWarsaw(_nowWarsaw()));

    return '$rangeLabel: %${aRate.toStringAsFixed(2)} ${S.archiveAccept} | %${cRate.toStringAsFixed(2)} ${S.archiveCancel}';
  }

  void _scheduleSave() {
    _saveDebounce?.cancel();
    _saveDebounce = Timer(const Duration(milliseconds: 300), _saveDataNow);
  }

  Future<void> _saveDataNow() async {
    final prefs = await _getPrefs();
    await prefs.reload();

    final diskAccepted = prefs.getInt(_keyAccepted) ?? 0;
    final diskRejected = prefs.getInt(_keyRejected) ?? 0;
    final diskCompleted = prefs.getInt(_keyCompleted) ?? 0;
    final diskCanceled = prefs.getInt(_keyCanceled) ?? 0;

    final newAccepted = (diskAccepted + (acceptedRequests - _baselineAccepted)).clamp(0, 99999);
    final newRejected = (diskRejected + (rejectedRequests - _baselineRejected)).clamp(0, 99999);
    final newCompleted = (diskCompleted + (completedTrips - _baselineCompleted)).clamp(0, 99999);
    final newCanceled = (diskCanceled + (canceledTrips - _baselineCanceled)).clamp(0, 99999);

    if (mounted) {
      setState(() {
        acceptedRequests = newAccepted;
        rejectedRequests = newRejected;
        completedTrips = newCompleted;
        canceledTrips = newCanceled;
        _syncBaseline();
      });
    } else {
      acceptedRequests = newAccepted;
      rejectedRequests = newRejected;
      completedTrips = newCompleted;
      canceledTrips = newCanceled;
      _syncBaseline();
    }

    await prefs.setInt(_keyAccepted, newAccepted);
    await prefs.setInt(_keyRejected, newRejected);
    await prefs.setInt(_keyCompleted, newCompleted);
    await prefs.setInt(_keyCanceled, newCanceled);
    await prefs.setBool(_keyAutoComplete, _autoCompleteTrips);
    await prefs.setBool(_keySteeringWheel, _steeringWheelEnabled);
    unawaited(OverlaySync.notifyCountersChanged());
  }

  void _snapshotUndo() {
    _prevAccepted = acceptedRequests;
    _prevRejected = rejectedRequests;
    _prevCompleted = completedTrips;
    _prevCanceled = canceledTrips;
  }

  void _clearUndo() {
    _prevAccepted = null;
    _prevRejected = null;
    _prevCompleted = null;
    _prevCanceled = null;
  }

  void _undo() {
    if (!_canUndo) return;
    setState(() {
      acceptedRequests = _prevAccepted!;
      rejectedRequests = _prevRejected!;
      completedTrips = _prevCompleted!;
      canceledTrips = _prevCanceled!;
      _clearUndo();
    });
    _scheduleSave();
  }

  void _change(String key, int delta) {
    setState(() {
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
    });
    _scheduleSave();
  }

  void _setCounter(String key, int value) {
    setState(() {
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
    });
    _scheduleSave();
  }

  Future<void> _setAutoCompleteTrips(bool enabled) async {
    setState(() => _autoCompleteTrips = enabled);
    final prefs = await _getPrefs();
    await prefs.setBool(_keyAutoComplete, enabled);
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
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: GoogleFonts.dmSans(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          autofocus: true,
          style: GoogleFonts.dmSans(
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
              style: GoogleFonts.dmSans(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              S.save,
              style: GoogleFonts.dmSans(
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
    final prefs = await _getPrefs();
    await prefs.setString(_keyLang, lang.name);
    if (!mounted) return;
    setState(() => _currentLang = lang);
  }

  Future<void> _showLanguageSelector() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
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

  Future<void> _toggleOverlay() async {
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

    if (!mounted) return;
    setState(() => _overlayActive = true);
  }

  List<Map<String, dynamic>> _parseTapHistory(String? raw) {
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList()
          .reversed
          .toList();
    } catch (_) {
      return [];
    }
  }

  String _formatTapDate(DateTime dt) {
    final months = S.months;
    return '${dt.day} ${months[dt.month]}';
  }

  Future<void> _showHistory() async {
    final prefs = await _getPrefs();
    await prefs.reload();
    final archive = (prefs.getStringList(_keyArchive) ?? []).reversed.toList();
    final taps = _parseTapHistory(prefs.getString(_keyTapHistory));

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
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
    String body = S.crashLogEmpty;
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

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF121212),
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
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2,
                  color: Colors.white54,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.5,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    body,
                    style: GoogleFonts.jetBrainsMono(
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
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(text: body));
                        if (!ctx.mounted) return;
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          SnackBar(
                            content: Text(S.crashLogCopied),
                            duration: const Duration(seconds: 1),
                            backgroundColor: const Color(0xFF1A1A1A),
                          ),
                        );
                      },
                      child: Text(
                        S.crashLogCopy,
                        style: GoogleFonts.dmSans(
                          color: Colors.white,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: TextButton(
                      onPressed: () async {
                        await CrashLogger.clear();
                        if (!ctx.mounted) return;
                        Navigator.of(ctx).pop();
                      },
                      child: Text(
                        S.crashLogClear,
                        style: GoogleFonts.dmSans(
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
          ),
        ),
      ),
    );
  }

  Future<void> _showManualResetDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          S.resetWeekTitle,
          style: GoogleFonts.dmSans(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          S.resetConfirm,
          style: GoogleFonts.dmSans(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              S.cancel,
              style: GoogleFonts.dmSans(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              S.reset,
              style: GoogleFonts.dmSans(
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
    final cancelColor = cancellationRate >= 5.0 ? _crimson : _emerald;
    final recovery = neededForRecovery;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            Icons.undo_rounded,
            color: _canUndo ? Colors.white : const Color(0x26FFFFFF),
          ),
          onPressed: _canUndo ? _undo : null,
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/logo.png',
                width: 28,
                height: 28,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _cardColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.local_taxi_rounded, color: Colors.white, size: 18),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'RateHelper',
              style: GoogleFonts.dmSans(
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
            color: const Color(0xFF1A1A1A),
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
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'setup',
                child: Text(
                  S.setupGuide,
                  style: GoogleFonts.dmSans(color: Colors.white),
                ),
              ),
              PopupMenuItem(
                value: 'crash',
                child: Text(
                  S.crashLogTitle,
                  style: GoogleFonts.dmSans(color: Colors.white),
                ),
              ),
              PopupMenuItem(
                value: 'driver_mode',
                child: Text(
                  S.driverModeLabel(activeDriverMode == DriverMode.paired),
                  style: GoogleFonts.dmSans(color: Colors.white),
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
                120 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
              _buildTripGoalSelectorChip(),
              const SizedBox(height: 12),
              SizedBox(
                height: 110,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 1,
                      child: _buildRateCard(
                        label: S.acceptRate,
                        value: S.formatPercent(acceptanceRate.toStringAsFixed(2)),
                        color: _acceptRateColor,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 1,
                      child: _buildRateCard(
                        label: S.cancelRate,
                        value: S.formatPercent(cancellationRate.toStringAsFixed(2)),
                        color: cancelColor,
                      ),
                    ),
                  ],
                ),
              ),

              if (recovery != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    border: _cardBorder,
                    borderRadius: _cardRadius,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.trending_up_rounded, color: _amber, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          S.recovery(recovery, _selectedGoal.requiredAcceptRate!),
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _amber,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ] else if (_selectedGoal.requiredAcceptRate != null &&
                  acceptanceRate >= _selectedGoal.requiredAcceptRate! &&
                  acceptanceRate < _selectedGoal.requiredAcceptRate! + AMBER_BUFFER) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    border: _cardBorder,
                    borderRadius: _cardRadius,
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.shield_outlined, color: _amber, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          S.safeButClose,
                          style: GoogleFonts.dmSans(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _amber,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 32),

              _sectionHeader(S.requests),
              const SizedBox(height: 12),
              _buildCounterRow(
                label: S.accepted,
                value: acceptedRequests,
                key: _keyAccepted,
                onValueTap: () => _showEditCounterDialog(
                  title: S.editAcceptedTitle,
                  currentValue: acceptedRequests,
                  onSave: (value) => _setCounter(_keyAccepted, value),
                ),
              ),
              const SizedBox(height: 10),
              _buildCounterRow(
                label: S.rejected,
                value: rejectedRequests,
                key: _keyRejected,
                onValueTap: () => _showEditCounterDialog(
                  title: S.editRejectedTitle,
                  currentValue: rejectedRequests,
                  onSave: (value) => _setCounter(_keyRejected, value),
                ),
              ),

              const SizedBox(height: 28),

              _sectionHeader(S.trips),
              const SizedBox(height: 12),
              _buildAutoCompleteSwitch(),
              const SizedBox(height: 10),
              _buildSteeringWheelSwitch(),
              const SizedBox(height: 10),
              _buildCounterRow(
                label: S.completed,
                value: completedTrips,
                key: _keyCompleted,
                onValueTap: () => _showEditCounterDialog(
                  title: S.editCompletedTitle,
                  currentValue: completedTrips,
                  onSave: (value) => _setCounter(_keyCompleted, value),
                ),
              ),
              const SizedBox(height: 10),
              _buildCounterRow(
                label: S.cancelled,
                value: canceledTrips,
                key: _keyCanceled,
                onValueTap: () => _showEditCounterDialog(
                  title: S.editCancelledTitle,
                  currentValue: canceledTrips,
                  onSave: (value) => _setCounter(_keyCanceled, value),
                ),
              ),

              const SizedBox(height: 40),

              GestureDetector(
                onTap: _showManualResetDialog,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  decoration: BoxDecoration(
                    color: _cardColor,
                    border: _cardBorder,
                    borderRadius: _cardRadius,
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    S.resetWeek,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: _crimson,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Center(child: _buildDesignerSignature()),

              if (_versionLabel.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  '${S.version} $_versionLabel',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: const Color(0x55FFFFFF),
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.w400,
                  ),
                ),
              ],
              if (!kReleaseMode &&
                  _debugBuildSignature != null &&
                  _debugBuildSignature!.isNotEmpty) ...[
                const SizedBox(height: 8),
                SelectableText(
                  'SIG: $_debugBuildSignature',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 8,
                    color: const Color(0x55FFFFFF),
                    letterSpacing: 0.5,
                    height: 1.3,
                  ),
                ),
              ],

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
                24 + MediaQuery.of(context).padding.bottom,
              ),
              child: _buildBottomActionBar(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Material(
      color: const Color(0xFF1E1E1E),
      elevation: 12,
      shadowColor: Colors.black54,
      borderRadius: BorderRadius.circular(32),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(32),
          border: Border.all(color: const Color(0x1AFFFFFF)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: _BottomBarAction(
                emoji: '🌐',
                label: S.navLang,
                onTap: _showLanguageSelector,
              ),
            ),
            Expanded(
              child: _BottomBarWidgetToggle(
                active: _overlayActive,
                onTap: _toggleOverlay,
              ),
            ),
            Expanded(
              child: _BottomBarAction(
                emoji: '📋',
                label: S.navLogs,
                onTap: _showHistory,
              ),
            ),
            Expanded(
              child: _BottomBarAction(
                emoji: '📡',
                label: 'Radar',
                onTap: _openRadar,
              ),
            ),
            Expanded(
              child: _BottomBarAction(
                emoji: '💰',
                label: S.navEarnings,
                onTap: _openEarnings,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openRadar() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const RadarScreen()),
    );
  }

  Future<void> _openEarnings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => const EarningsScreen()),
    );
    if (mounted) setState(() {});
  }

  Widget _buildDesignerSignature() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: _cardColor,
        border: Border.all(color: const Color(0x26FFFFFF), width: 1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'KK4181R',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 11,
              color: _designerGold,
              letterSpacing: 2.5,
              fontWeight: FontWeight.w500,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            S.designer,
            style: GoogleFonts.dmSans(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.5,
              color: _designerGold.withValues(alpha: 0.65),
              height: 1,
            ),
          ),
        ],
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
            Icon(Icons.flag_rounded, color: _amber, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                S.tripGoalChip(_selectedGoal.minTrips, _selectedGoal.requiredAcceptRate),
                style: GoogleFonts.dmSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ),
            const Icon(Icons.expand_more_rounded, color: Colors.white54, size: 20),
          ],
        ),
      ),
    );
  }

  void _showTripGoalSelector() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF161616),
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
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    S.tripGoalTitle,
                    style: GoogleFonts.dmSans(
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
                    selectedTileColor: const Color(0xFF242424),
                    leading: Icon(
                      Icons.outlined_flag_rounded,
                      color: _selectedGoal == goal ? _amber : Colors.white54,
                    ),
                    title: Text(
                      S.tripGoalOption(goal.minTrips, goal.requiredAcceptRate),
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        fontWeight: _selectedGoal == goal ? FontWeight.w800 : FontWeight.w500,
                        color: _selectedGoal == goal ? Colors.white : Colors.white70,
                      ),
                    ),
                    trailing: _selectedGoal == goal
                        ? Icon(Icons.check_circle_rounded, color: _amber, size: 20)
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
  }) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 18),
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 2,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  style: GoogleFonts.dmSans(
                    fontSize: 36,
                    fontWeight: FontWeight.w900,
                    color: color,
                    height: 1,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: GoogleFonts.dmSans(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          letterSpacing: 1.5,
          color: Colors.white38,
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
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
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
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white70,
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

  Future<void> _setSteeringWheelCounter(bool enabled) async {
    if (enabled) {
      final bool isServiceActive = await _kSysChannel.invokeMethod('isAccessibilityServiceEnabled') ?? false;
      if (!isServiceActive) {
        if (!mounted) return;
        final bool? open = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF1E2430),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text(
              S.steeringWheelDialogTitle,
              style: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            content: Text(
              S.steeringWheelDialogDesc,
              style: GoogleFonts.dmSans(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(S.cancel, style: GoogleFonts.dmSans(color: Colors.white54)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(S.openSettings, style: GoogleFonts.dmSans(color: _emerald, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
        if (open == true) {
          await _kSysChannel.invokeMethod('openAccessibilitySettings');
        }
      }
    }
    setState(() => _steeringWheelEnabled = enabled);
    final prefs = await _getPrefs();
    await prefs.setBool(_keySteeringWheel, enabled);
  }

  Widget _buildCounterRow({
    required String label,
    required int value,
    required String key,
    VoidCallback? onValueTap,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: _cardColor,
        border: _cardBorder,
        borderRadius: _cardRadius,
      ),
      padding: const EdgeInsets.only(left: 20, top: 16, bottom: 16, right: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white70,
                  ),
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: onValueTap == null
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          onValueTap();
                        },
                  onLongPress: onValueTap == null
                      ? null
                      : () {
                          HapticFeedback.mediumImpact();
                          onValueTap();
                        },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '$value',
                          style: GoogleFonts.dmSans(
                            fontSize: 48,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1,
                            decoration: onValueTap != null
                                ? TextDecoration.underline
                                : TextDecoration.none,
                            decorationColor: Colors.white38,
                          ),
                        ),
                      ),
                      if (onValueTap != null) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.edit_rounded,
                          size: 22,
                          color: Colors.white38,
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          _buildIconButton(Icons.remove_rounded, () {
            HapticFeedback.mediumImpact();
            _change(key, -1);
          }),
          const SizedBox(width: 6),
          _buildIconButton(Icons.add_rounded, () {
            HapticFeedback.lightImpact();
            _change(key, 1);
          }),
        ],
      ),
    );
  }

  Widget _buildIconButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0x0AFFFFFF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: Colors.white, size: 28),
      ),
    );
  }
}

class _BottomBarAction extends StatelessWidget {
  const _BottomBarAction({
    required this.emoji,
    required this.label,
    required this.onTap,
  });

  final String emoji;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(emoji, style: const TextStyle(fontSize: 22, height: 1.1)),
              const SizedBox(height: 4),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.white70,
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
    required this.onTap,
  });

  static const _emerald = Color(0xFF10B981);

  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
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
                child: Icon(
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
                style: GoogleFonts.dmSans(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: active ? _emerald : Colors.white70,
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
  static const _keyTapHistory = 'tapHistory';
  static const _emerald = Color(0xFF10B981);
  static const _crimson = Color(0xFFEF4444);

  late final TabController _tabController;
  late List<Map<String, dynamic>> _taps;
  bool _todayOnly = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _taps = List<Map<String, dynamic>>.from(widget.taps);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> get _filteredTaps {
    if (!_todayOnly) return _taps;
    final now = DateTime.now();
    return _taps.where((entry) {
      final ts = entry['timestamp']?.toString();
      if (ts == null) return false;
      final dt = DateTime.tryParse(ts);
      if (dt == null) return false;
      final local = dt.toLocal();
      return local.year == now.year &&
          local.month == now.month &&
          local.day == now.day;
    }).toList();
  }

  String _tapTimeLabel(Map<String, dynamic> entry) {
    final localTime = entry['localTime']?.toString();
    if (localTime == null || localTime.length < 5) return '';
    final hhmm = localTime.substring(0, 5);

    final ts = entry['timestamp']?.toString();
    if (ts == null) return hhmm;
    final dt = DateTime.tryParse(ts);
    if (dt == null) return hhmm;

    final local = dt.toLocal();
    final now = DateTime.now();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;
    if (isToday) return hhmm;
    return '$hhmm · ${widget.formatTapDate(local)}';
  }

  Future<void> _confirmClearTapHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          S.tapLogTab,
          style: GoogleFonts.dmSans(
            color: Colors.white,
            fontWeight: FontWeight.w900,
          ),
        ),
        content: Text(
          S.tapHistoryClearConfirm,
          style: GoogleFonts.dmSans(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(
              S.cancel,
              style: GoogleFonts.dmSans(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(
              S.tapHistoryClear,
              style: GoogleFonts.dmSans(
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
    await prefs.remove(_keyTapHistory);
    setState(() => _taps = []);
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
                    style: GoogleFonts.dmSans(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 2,
                      color: Colors.white38,
                    ),
                  ),
                ),
                if (_tabController.index == 0)
                  TextButton.icon(
                    onPressed: _taps.isEmpty ? null : _confirmClearTapHistory,
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(
                      S.tapHistoryClear,
                      style: GoogleFonts.dmSans(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    style: TextButton.styleFrom(
                      foregroundColor: _crimson,
                      disabledForegroundColor: Colors.white24,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            TabBar(
              controller: _tabController,
              indicatorColor: _emerald,
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white38,
              labelStyle: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
              unselectedLabelStyle: GoogleFonts.dmSans(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 1.5,
              ),
              tabs: [
                Tab(text: S.tapLogTab),
                Tab(text: S.weeklyTab),
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
              ? Align(
                  alignment: Alignment.topCenter,
                  child: Text(
                    S.noTapHistory,
                    style: GoogleFonts.dmSans(
                      color: Colors.white54,
                      fontSize: 15,
                    ),
                  ),
                )
              : ListView.separated(
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final entry = entries[i];
                    final accepted = entry['type'] == 'accepted';
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0x0DFFFFFF),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Text(
                            accepted ? '🟢' : '🔴',
                            style: const TextStyle(fontSize: 16),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              accepted ? S.tapAcceptShort : S.tapRejectShort,
                              style: GoogleFonts.dmSans(
                                color: accepted ? _emerald : _crimson,
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            _tapTimeLabel(entry),
                            style: GoogleFonts.jetBrainsMono(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
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
    if (widget.archive.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Text(
          S.noHistory,
          style: GoogleFonts.dmSans(color: Colors.white54, fontSize: 15),
        ),
      );
    }

    return ListView.separated(
      itemCount: widget.archive.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) => Text(
        widget.archive[i],
        style: GoogleFonts.dmSans(
          color: Colors.white,
          fontSize: 15,
          fontWeight: FontWeight.w600,
          height: 1.3,
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
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? const Color(0xFF10B981).withValues(alpha: 0.15)
              : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF10B981) : const Color(0x0DFFFFFF),
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.dmSans(
            fontSize: 13,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? const Color(0xFF10B981) : Colors.white54,
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
                  style: GoogleFonts.dmSans(
                    fontSize: 17,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? Colors.white : Colors.white70,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.check_rounded, color: Color(0xFF10B981), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeepAliveTabView extends StatefulWidget {
  const _KeepAliveTabView({
    required this.child,
    super.key,
  });

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
