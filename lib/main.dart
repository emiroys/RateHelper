import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

import 'crash_logger.dart';
import 'home_screen.dart';
import 'log.dart';
import 'onboarding_screen.dart';
import 'overlay_widget.dart';
import 'secure_http.dart';
const _kKeyOnboardingComplete = 'onboardingComplete';

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

  runApp(UberTakipApp(showOnboarding: !seenOnboarding));
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

class UberTakipApp extends StatefulWidget {
  const UberTakipApp({super.key, required this.showOnboarding});

  final bool showOnboarding;

  @override
  State<UberTakipApp> createState() => _UberTakipAppState();
}

class _UberTakipAppState extends State<UberTakipApp> {
  late bool _needsOnboarding = widget.showOnboarding;

  Future<void> _completeOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKeyOnboardingComplete, true);
    if (!mounted) return;
    setState(() => _needsOnboarding = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Anti-Eres',
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
