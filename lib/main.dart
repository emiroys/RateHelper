import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'crash_logger.dart';
import 'earnings_reminders.dart';
import 'earnings_screen.dart';
import 'home_screen.dart';
import 'log.dart';
import 'onboarding_screen.dart';
import 'overlay_widget.dart';
import 'secure_http.dart';
const _kKeyOnboardingComplete = 'onboardingComplete';

/// Root navigator, used to route a tapped Monday reminder to the earnings
/// screen even when the tap arrives while the app is already running.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// Handles a foreground/resumed tap on the Monday reminder.
@pragma('vm:entry-point')
void _onReminderTap(NotificationResponse response) {
  if (response.payload == EarningsReminders.tapPayload) {
    _openEarningsAddWeek();
  }
}

/// Pushes the earnings screen with the "add new week" form pre-triggered.
void _openEarningsAddWeek() {
  final nav = rootNavigatorKey.currentState;
  if (nav == null) return;
  nav.push(
    MaterialPageRoute<void>(
      builder: (_) => const EarningsScreen(autoAddWeek: true),
    ),
  );
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = StrictSecurityHttpOverrides();

  // Parallelize independent boot work: timezone DB load, prefs warmup,  // and crash-logger file probe all hit different I/O queues.
  final results = await Future.wait<Object?>([
    Future<void>(() => tz.initializeTimeZones()),
    SharedPreferences.getInstance(),
    CrashLogger.install(),
  ]);

  // Prefer bundled / cached fonts; never block first paint on a network
  // round-trip for diacritics. If the user is offline on cold install the
  // app degrades to the platform default font instead of stuck loading.
  GoogleFonts.config.allowRuntimeFetching = false;

  final prefs = results[1] as SharedPreferences;
  final bool seenOnboarding = prefs.getBool(_kKeyOnboardingComplete) ?? false;

  // Local timezone for the weekly reminder. Falls back to Warsaw (the app's
  // operating region) if the platform lookup fails on some OEM builds.
  await _configureLocalTimeZone();

  await EarningsReminders.init(onTap: _onReminderTap);
  await EarningsReminders.applyFromPrefs(prefs);

  final launchDetails = await EarningsReminders.launchDetails();
  final launchedFromReminder =
      (launchDetails?.didNotificationLaunchApp ?? false) &&
          launchDetails?.notificationResponse?.payload ==
              EarningsReminders.tapPayload;

  runApp(RateHelperApp(
    showOnboarding: !seenOnboarding,
    openEarningsOnLaunch: launchedFromReminder,
  ));
}

Future<void> _configureLocalTimeZone() async {
  try {
    final info = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(info.identifier));
  } catch (_) {
    try {
      tz.setLocalLocation(tz.getLocation('Europe/Warsaw'));
    } catch (_) {
      // Leave the timezone package default in place.
    }
  }
}

@pragma('vm:entry-point')
void overlayMain() {
  if (!kReleaseMode) {
    developer.log('overlay isolate started', name: 'OVERLAY');
  }

  runZonedGuarded<void>(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      HttpOverrides.global = StrictSecurityHttpOverrides();
      GoogleFonts.config.allowRuntimeFetching = false;
      DartPluginRegistrant.ensureInitialized();
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

      runApp(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          color: const Color(0x00000000),
          theme: ThemeData(
            brightness: Brightness.dark,
            useMaterial3: true,
            scaffoldBackgroundColor: Colors.transparent,
            splashFactory: InkRipple.splashFactory,
            colorScheme: const ColorScheme.dark(
              surface: Colors.transparent,
              primary: Colors.white,
            ),
            textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme),
          ),
          builder: (BuildContext context, Widget? child) {
            return Directionality(
              textDirection: TextDirection.ltr,
              child: MediaQuery(
                data: MediaQuery.maybeOf(context) ??
                    MediaQueryData.fromView(View.of(context)),
                child: child ?? const SizedBox.shrink(),
              ),
            );
          },
          home: const OverlayWidget(),
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
    this.openEarningsOnLaunch = false,
  });

  final bool showOnboarding;

  /// True when the app was cold-started by tapping the Monday reminder; routes
  /// straight to the earnings screen with "add new week" pre-triggered.
  final bool openEarningsOnLaunch;

  @override
  State<RateHelperApp> createState() => _RateHelperAppState();
}

class _RateHelperAppState extends State<RateHelperApp> {
  late bool _needsOnboarding = widget.showOnboarding;

  @override
  void initState() {
    super.initState();
    if (widget.openEarningsOnLaunch && !_needsOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openEarningsAddWeek();
      });
    }
  }

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeyOnboardingComplete, true);
    if (!mounted) return;
    setState(() => _needsOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RateHelper',
      navigatorKey: rootNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          surface: Colors.black,
          primary: Colors.white,
        ),
        useMaterial3: true,
        textTheme: GoogleFonts.dmSansTextTheme(ThemeData.dark().textTheme),
      ),
      home: _needsOnboarding
          ? OnboardingScreen(onDone: _completeOnboarding)
          : const HomeScreen(),
    );
  }
}
