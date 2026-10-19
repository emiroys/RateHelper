import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:shared_preferences/shared_preferences.dart';
// latest_10y, not latest_all: the app resolves exactly one zone
// (Europe/Warsaw) and only ever looks at the current week plus a 104-week
// archive, so historical transitions outside the 10-year window are dead
// weight. The trimmed database is ~66 KB of tzf against ~446 KB, and it is
// parsed synchronously before runApp.
import 'package:timezone/data/latest_10y.dart' as tz;

import 'github_consent_dialog.dart';
import 'home_screen.dart';
import 'crash_logger.dart';
import 'fonts.dart';
import 'log.dart';
import 'onboarding_screen.dart';
import 'overlay_widget.dart';
import 'services/backup_service.dart';
import 'services/github_access.dart';
import 'shade_controls.dart';
import 'startup_language.dart';
import 'survey_screen.dart';
import 'survey_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Parallelize independent boot work: timezone DB load, prefs warmup,  // and crash-logger file probe all hit different I/O queues.
  // Each boot task is independent and non-fatal: timezone falls back to
  // device-local math, prefs to defaults, crash logging to logcat-only.
  await Future.wait<void>([
    Future<void>(() => tz.initializeTimeZones()).catchError((Object e) {}),
    CrashLogger.install().catchError((Object e) {}),
  ]);

  SharedPreferences? prefs;
  try {
    prefs = await SharedPreferences.getInstance();
    await BackupService.recoverPendingRestoreIfNeeded(prefs: prefs);
  } catch (_) {
    /* run with defaults; HomeScreen re-tries lazily */
  }

  // Saved language first; only a fresh install follows the Android device
  // locale. Unsupported device languages fall back to English.
  await loadStartupLanguage(
    prefs: prefs,
    deviceLocale: PlatformDispatcher.instance.locale,
  );

  runApp(
    RateHelperApp(
      showOnboarding: shouldShowOnboarding(prefs),
      showSurvey: SurveyStore.shouldShowSurvey(prefs),
    ),
  );
}

@pragma('vm:entry-point')
void overlayMain() {
  if (!kReleaseMode) {
    developer.log('overlay isolate started', name: 'OVERLAY');
  }

  runZonedGuarded<void>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      DartPluginRegistrant.ensureInitialized();
      // Each isolate has its own statics: without this, CrashLogger._file
      // is null here and every overlay error is silently dropped in release.
      unawaited(CrashLogger.install());
      FlutterError.onError = (FlutterErrorDetails details) {
        FlutterError.presentError(details);
        loge(
          'OVERLAY_ISOLATE FlutterError',
          name: 'overlay',
          error: details.exception,
          stack: details.stack,
        );
      };

      PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
        loge(
          'OVERLAY_ISOLATE PlatformDispatcher error',
          name: 'overlay',
          error: error,
          stack: stack,
        );
        return true;
      };

      // Fresh isolate per overlay open, so getInstance() reads disk — no
      // reload needed. Capped so a slow read cannot hold the first frame.
      var startOrientation = PillOrientation.horizontal;
      var startShowCancel = false;
      var startCollapsed = false;
      var startHidden = false;
      try {
        final prefs = await SharedPreferences.getInstance().timeout(
          const Duration(milliseconds: 400),
        );
        await BackupService.recoverPendingRestoreIfNeeded(
          prefs: prefs,
        ).timeout(const Duration(milliseconds: 400));
        final layout = OverlayWidget.layoutFromPrefs(prefs);
        startOrientation = layout.orientation;
        startShowCancel = layout.showCancel;
        startCollapsed =
            prefs.getBool(OverlayWidget.collapsedPrefsKey) ?? false;
        startHidden = ShadeControls.pillHidden(
          notificationControls: prefs.getBool(ShadeControls.prefsKey) ?? false,
          hidePill: prefs.getBool(ShadeControls.hidePillPrefsKey) ?? false,
        );
      } catch (e) {
        logd('overlay collapsed pref read skipped: $e', name: 'overlay');
      }

      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          color: const Color(0x00000000),
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.transparent,
            canvasColor: Colors.transparent,
            splashFactory: InkRipple.splashFactory,
            colorScheme: const ColorScheme.dark(
              surface: Colors.transparent,
              primary: Colors.white,
            ),
            textTheme: ThemeData.dark().textTheme.apply(
              fontFamily: AppFonts.dmSans,
            ),
          ),
          builder: (BuildContext context, Widget? child) {
            return Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                data:
                    MediaQuery.maybeOf(context) ??
                    MediaQueryData.fromView(View.of(context)),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: OverlayWidget(
            initialOrientation: startOrientation,
            initialShowCancel: startShowCancel,
            initialCollapsed: startCollapsed,
            initialHidden: startHidden,
          ),
        ),
      );
    },
    (Object error, StackTrace stack) {
      // Single channel: loge writes to the internal crash file in
      // release and mirrors to logcat in debug. No raw debugPrint /
      // developer.log here — those would leak the zone exception to
      // `adb logcat` even on production builds.
      loge(
        'OVERLAY_ISOLATE zone error',
        name: 'overlay',
        error: error,
        stack: stack,
      );
    },
  );
}

class RateHelperApp extends StatefulWidget {
  const RateHelperApp({
    super.key,
    required this.showOnboarding,
    this.showSurvey = false,
  });

  final bool showOnboarding;

  /// Production passes the versioned survey gate. Tests that pump the app
  /// without survey intent keep the existing home-screen behaviour.
  final bool showSurvey;

  @override
  State<RateHelperApp> createState() => _RateHelperAppState();
}

class _RateHelperAppState extends State<RateHelperApp>
    with WidgetsBindingObserver {
  late bool _needsOnboarding = widget.showOnboarding;
  late bool _needsSurvey = widget.showSurvey;
  final _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_needsOnboarding && !_needsSurvey) {
        unawaited(_askGithubOnce());
      }
      // One foreground retry for an answer queued while offline. No timer and
      // no background polling.
      unawaited(SurveyStore.syncPending());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(SurveyStore.syncPending());
    }
  }

  /// One question, before any GitHub read. Existing installs see it once
  /// because the answered flag is missing until this version writes it.
  /// A failure to read prefs leaves both switches off and still releases
  /// the gate, so startup cannot sit on a socket.
  Future<void> _askGithubOnce() async {
    final generation = GithubAccess.generation;
    try {
      final prefs = await SharedPreferences.getInstance();
      GithubAccess.publishLastCheck(GithubAccess.readLastCheck(prefs));
      if (GithubAccess.promptAnswered(prefs)) return;
      if (!mounted || generation != GithubAccess.generation) return;
      final navContext = _navigatorKey.currentContext;
      if (navContext == null || !navContext.mounted) return;
      final allow = await showDialog<bool>(
        context: navContext,
        barrierDismissible: false,
        builder: (_) => const GithubConsentDialog(),
      );
      if (!mounted || allow == null || generation != GithubAccess.generation) {
        return;
      }
      await GithubAccess.applyChoice(prefs, allow: allow);
    } catch (e, s) {
      loge('github consent failed', name: 'home', error: e, stack: s);
    } finally {
      if (generation == GithubAccess.generation) {
        GithubAccess.markPromptSettled();
      }
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kOnboardingCompletePrefsKey, true);
    if (!mounted) return;
    setState(() => _needsOnboarding = false);
    if (!_needsSurvey) {
      unawaited(_askGithubOnce());
    }
  }

  void _completeSurvey() {
    if (!mounted) return;
    setState(() => _needsSurvey = false);
    unawaited(_askGithubOnce());
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: _navigatorKey,
      title: 'RateHelper',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          surface: Colors.black,
          primary: Colors.white,
        ),
        useMaterial3: true,
        textTheme: ThemeData.dark().textTheme.apply(
          fontFamily: AppFonts.dmSans,
        ),
      ),
      builder: (BuildContext context, Widget? child) {
        // Above the Navigator, so pushed routes feed the wakelock idle timer
        // too. Home's own listener only saw home, which let the screen go dark
        // after 10 minutes of typing in the earnings form.
        return Listener(
          onPointerDown: (_) => HomeScreen.reportUserInteraction(),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: _needsOnboarding
          ? OnboardingScreen(onDone: _completeOnboarding)
          : _needsSurvey
          ? SurveyScreen(onCompleted: _completeSurvey)
          : const HomeScreen(),
    );
  }
}
