import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/onboarding_screen.dart';
import 'package:rate_helper/settings_screen.dart';
import 'package:rate_helper/startup_language.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const overlayChannel = MethodChannel('x-slayer/overlay_channel');
  const systemChannel = MethodChannel('com.ratehelper.app/system');

  late bool overlayGranted;
  late bool batteryIgnored;
  late String manufacturer;
  late int permissionRequests;

  setUp(() {
    S.setLang(AppLang.tr);
    overlayGranted = false;
    batteryIgnored = false;
    manufacturer = 'samsung';
    permissionRequests = 0;
    SharedPreferences.setMockInitialValues({});

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(overlayChannel, (call) async {
      switch (call.method) {
        case 'checkPermission':
          return overlayGranted;
        case 'requestPermission':
          permissionRequests++;
          return overlayGranted;
        default:
          return null;
      }
    });
    messenger.setMockMethodCallHandler(systemChannel, (call) async {
      switch (call.method) {
        case 'manufacturer':
          return manufacturer;
        case 'isIgnoringBatteryOptimizations':
          return batteryIgnored;
        case 'openBatteryOptimizationSettings':
        case 'openAppDetails':
          return true;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(overlayChannel, null);
    messenger.setMockMethodCallHandler(systemChannel, null);
    S.setLang(AppLang.tr);
  });

  Future<SharedPreferences> pumpWizard(
    WidgetTester tester, {
    VoidCallback? onDone,
    Future<void> Function(AppLang lang)? onLanguageChanged,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      MaterialApp(
        home: OnboardingScreen(
          onDone: onDone ?? () {},
          onLanguageChanged: onLanguageChanged,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return prefs;
  }

  Future<void> tapNext(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('onboarding-primary')));
    await tester.pumpAndSettle();
  }

  group('startup language', () {
    test('fresh install follows Turkish device locale', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final lang = await loadStartupLanguage(
        prefs: prefs,
        deviceLocale: const Locale('tr', 'TR'),
      );

      expect(lang, AppLang.tr);
      expect(prefs.getString(kAppLanguagePrefsKey), 'tr');
    });

    test('fresh install follows Polish device locale', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final lang = await loadStartupLanguage(
        prefs: prefs,
        deviceLocale: const Locale('pl', 'PL'),
      );

      expect(lang, AppLang.pl);
      expect(prefs.getString(kAppLanguagePrefsKey), 'pl');
    });

    test('fresh install follows English device locale', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final lang = await loadStartupLanguage(
        prefs: prefs,
        deviceLocale: const Locale('en', 'GB'),
      );

      expect(lang, AppLang.en);
      expect(prefs.getString(kAppLanguagePrefsKey), 'en');
    });

    test('unsupported device locale falls back to English', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      final lang = await loadStartupLanguage(
        prefs: prefs,
        deviceLocale: const Locale('de', 'DE'),
      );

      expect(lang, AppLang.en);
      expect(prefs.getString(kAppLanguagePrefsKey), 'en');
    });

    test('saved language always overrides device language', () async {
      SharedPreferences.setMockInitialValues({'appLanguage': 'pl'});
      final prefs = await SharedPreferences.getInstance();

      final lang = await loadStartupLanguage(
        prefs: prefs,
        deviceLocale: const Locale('tr', 'TR'),
      );

      expect(lang, AppLang.pl);
      expect(prefs.getString(kAppLanguagePrefsKey), 'pl');
    });

    test('completed onboarding is not shown again after upgrade', () async {
      SharedPreferences.setMockInitialValues({'onboardingComplete': true});
      final prefs = await SharedPreferences.getInstance();

      expect(shouldShowOnboarding(prefs), isFalse);
    });

    test('a fresh install still needs onboarding', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(shouldShowOnboarding(prefs), isTrue);
    });
  });

  testWidgets('language selector changes and persists immediately', (
    tester,
  ) async {
    final prefs = await pumpWizard(tester);
    expect(S.lang, AppLang.tr);
    expect(find.text(S.onboardingWelcomeTitle), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-lang-en')));
    await tester.pumpAndSettle();

    expect(S.lang, AppLang.en);
    expect(find.text(S.onboardingWelcomeTitle), findsOneWidget);
    expect(prefs.getString(kAppLanguagePrefsKey), 'en');

    await tester.tap(find.byKey(const ValueKey('onboarding-lang-pl')));
    await tester.pumpAndSettle();

    expect(S.lang, AppLang.pl);
    expect(find.text(S.onboardingWelcomeTitle), findsOneWidget);
    expect(prefs.getString(kAppLanguagePrefsKey), 'pl');

    // A later launch must keep the manual choice even if the device is Turkish.
    final reloaded = await loadStartupLanguage(
      prefs: prefs,
      deviceLocale: const Locale('tr', 'TR'),
    );
    expect(reloaded, AppLang.pl);
  });

  testWidgets('wizard moves forward, backward and keeps the step count', (
    tester,
  ) async {
    await pumpWizard(tester);

    expect(find.byKey(const ValueKey('onboarding-step-1')), findsOneWidget);
    expect(find.text(S.onboardingStepOf(1, 5)), findsOneWidget);
    expect(find.text(S.onboardingWelcomeTitle), findsOneWidget);

    await tapNext(tester);
    expect(find.byKey(const ValueKey('onboarding-step-2')), findsOneWidget);
    expect(find.text(S.onboardingStepOf(2, 5)), findsOneWidget);
    expect(find.text(S.onboardingOverlayTitle), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-back')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('onboarding-step-1')), findsOneWidget);

    for (var step = 2; step <= 5; step++) {
      await tapNext(tester);
      expect(
        find.byKey(ValueKey('onboarding-step-$step')),
        findsOneWidget,
        reason: 'expected step $step',
      );
      expect(find.text(S.onboardingStepOf(step, 5)), findsOneWidget);
    }

    expect(find.text(S.onboardingReadyTitle), findsOneWidget);
    expect(find.text(S.onboardingOpenRateHelper), findsOneWidget);
  });

  testWidgets('skip explains the missing overlay permission first', (
    tester,
  ) async {
    var done = false;
    await pumpWizard(tester, onDone: () => done = true);

    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.text(S.onboardingSkipTitle), findsOneWidget);
    expect(find.text(S.onboardingSkipOverlayBody), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-skip-stay')));
    await tester.pumpAndSettle();
    expect(done, isFalse);
    expect(find.byKey(const ValueKey('onboarding-step-1')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-skip-confirm')));
    await tester.pumpAndSettle();

    expect(done, isTrue);
  });

  testWidgets('skip completes directly once both checks are verified', (
    tester,
  ) async {
    overlayGranted = true;
    batteryIgnored = true;
    var done = false;
    await pumpWizard(tester, onDone: () => done = true);

    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.text(S.onboardingSkipTitle), findsNothing);
    expect(done, isTrue);
  });

  testWidgets('skip warns when battery optimization is still unconfirmed', (
    tester,
  ) async {
    overlayGranted = true;
    var done = false;
    await pumpWizard(tester, onDone: () => done = true);

    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(find.text(S.onboardingSkipTitle), findsOneWidget);
    expect(find.text(S.onboardingSkipBatteryBody), findsOneWidget);
    expect(find.text(S.onboardingSkipOverlayBody), findsNothing);

    await tester.tap(find.byKey(const ValueKey('onboarding-skip-confirm')));
    await tester.pumpAndSettle();
    expect(done, isTrue);
  });

  testWidgets('permission status refreshes on resume without losing the step', (
    tester,
  ) async {
    await pumpWizard(tester);
    await tapNext(tester);
    expect(find.text(S.onboardingStepOf(2, 5)), findsOneWidget);
    expect(find.text(S.onboardingPermissionMissing), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey('onboarding-overlay-open-settings')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('onboarding-overlay-open-settings')),
    );
    await tester.pumpAndSettle();
    expect(permissionRequests, 1);

    overlayGranted = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text(S.onboardingStepOf(2, 5)), findsOneWidget);
    expect(find.text(S.onboardingPermissionGranted), findsOneWidget);
    expect(find.text(S.onboardingPermissionMissing), findsNothing);
  });

  testWidgets('battery status is verified independently of brand selection', (
    tester,
  ) async {
    await pumpWizard(tester);
    await tapNext(tester);
    await tapNext(tester);

    expect(find.text(S.onboardingBatteryNotVerified), findsOneWidget);
    expect(find.text(S.onboardingBatteryVerified), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('onboarding-brand-xiaomi')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('onboarding-brand-xiaomi')));
    await tester.pumpAndSettle();

    expect(find.text(S.xiaomiSteps), findsOneWidget);
    expect(find.text(S.onboardingBatteryNotVerified), findsOneWidget);
    expect(find.text(S.onboardingBatteryVerified), findsNothing);

    batteryIgnored = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text(S.onboardingBatteryVerified), findsOneWidget);
  });

  testWidgets('ready summary reflects real permission and battery state', (
    tester,
  ) async {
    await pumpWizard(tester);
    for (var i = 0; i < 4; i++) {
      await tapNext(tester);
    }

    expect(find.text(S.onboardingSummaryNotGranted), findsOneWidget);
    expect(find.text(S.onboardingSummaryBatteryUnverified), findsOneWidget);
    expect(find.text(S.onboardingSummaryOptionalValue), findsOneWidget);
  });

  testWidgets('all five steps render in every language without overflow', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final lang in AppLang.values) {
      S.setLang(lang);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2.0)),
            child: child ?? const SizedBox.shrink(),
          ),
          home: OnboardingScreen(
            key: ValueKey('onboarding-${lang.name}'),
            onDone: () {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      final titles = <String>[
        S.onboardingWelcomeTitle,
        S.onboardingOverlayTitle,
        S.onboardingBatteryTitle,
        S.onboardingOptionalTitle,
        S.onboardingReadyTitle,
      ];

      for (var step = 1; step <= 5; step++) {
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow at ${lang.name} step $step',
        );
        expect(
          find.text(titles[step - 1]),
          findsOneWidget,
          reason: 'missing label at ${lang.name} step $step',
        );
        if (step < 5) {
          await tester.tap(find.byKey(const ValueKey('onboarding-primary')));
          await tester.pumpAndSettle();
        }
      }
    }
  });

  test('every new onboarding label exists in TR, EN and PL', () {
    for (final lang in AppLang.values) {
      S.setLang(lang);
      final labels = <String>[
        S.onboardingContinue,
        S.onboardingBack,
        S.onboardingOpenRateHelper,
        S.onboardingCloseGuide,
        S.onboardingLanguageSelector,
        S.onboardingWelcomeTitle,
        S.onboardingWelcomeLead,
        S.onboardingFeatureRequestsTitle,
        S.onboardingFeatureRequestsBody,
        S.onboardingFeatureRatesTitle,
        S.onboardingFeatureRatesBody,
        S.onboardingFeatureOverlayTitle,
        S.onboardingFeatureOverlayBody,
        S.onboardingFeatureAltControlsTitle,
        S.onboardingFeatureAltControlsBody,
        S.onboardingFeatureToolsTitle,
        S.onboardingFeatureToolsBody,
        S.onboardingFeatureLocalTitle,
        S.onboardingFeatureLocalBody,
        S.onboardingOverlayTitle,
        S.onboardingOverlayLead,
        S.onboardingOverlayWhatTitle,
        S.onboardingOverlayWhatBody,
        S.onboardingOverlayWhyTitle,
        S.onboardingOverlayWhyBody,
        S.onboardingOverlayHowTitle,
        S.onboardingOverlayHowStep1,
        S.onboardingOverlayHowStep2,
        S.onboardingOverlayHowStep3,
        S.onboardingOverlayHowStep4,
        S.onboardingPermissionGranted,
        S.onboardingPermissionGrantedBody,
        S.onboardingPermissionMissing,
        S.onboardingPermissionMissingBody,
        S.onboardingPermissionChecking,
        S.onboardingOpenPermissionSettings,
        S.onboardingOverlayUnavailable,
        S.onboardingBatteryTitle,
        S.onboardingBatteryLead,
        S.onboardingBatterySystemStatus,
        S.onboardingBatteryVerified,
        S.onboardingBatteryVerifiedBody,
        S.onboardingBatteryNotVerified,
        S.onboardingBatteryNotVerifiedBody,
        S.onboardingBatteryChecking,
        S.onboardingBatteryBrandLabel,
        S.onboardingBatteryBrandNote,
        S.onboardingBatteryManualNote,
        S.onboardingBatteryOpenSettings,
        S.onboardingOpenAppInfo,
        S.onboardingOptionalTitle,
        S.onboardingOptionalLead,
        S.onboardingOptionalBadge,
        S.onboardingOptionalSteeringTitle,
        S.onboardingOptionalSteeringBody,
        S.onboardingOptionalNotificationsTitle,
        S.onboardingOptionalNotificationsBody,
        S.onboardingOptionalPillTitle,
        S.onboardingOptionalPillBody,
        S.onboardingOptionalToolsTitle,
        S.onboardingOptionalToolsBody,
        S.onboardingOptionalRadarTitle,
        S.onboardingOptionalRadarBody,
        S.onboardingReadyTitle,
        S.onboardingReadyLead,
        S.onboardingSummaryTitle,
        S.onboardingSummaryOverlay,
        S.onboardingSummaryBattery,
        S.onboardingSummaryOptional,
        S.onboardingSummaryGranted,
        S.onboardingSummaryNotGranted,
        S.onboardingSummaryBatteryVerified,
        S.onboardingSummaryBatteryUnverified,
        S.onboardingSummaryOptionalValue,
        S.onboardingReadySettingsHint,
        S.onboardingSkipTitle,
        S.onboardingSkipOverlayBody,
        S.onboardingSkipBatteryBody,
        S.onboardingSkipStay,
        S.onboardingSkipConfirm,
      ];
      for (final label in labels) {
        expect(label.trim(), isNotEmpty, reason: '${lang.name}: empty label');
      }
    }
  });

  testWidgets('setup guide closes without resetting onboarding state', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'onboardingComplete': true});
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              key: const ValueKey('open-guide'),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const SetupGuideScreen(),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('open-guide')));
    await tester.pumpAndSettle();

    expect(find.byType(SetupGuideScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('onboarding-skip')), findsNothing);
    expect(find.byKey(const ValueKey('onboarding-close')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-close')));
    await tester.pumpAndSettle();

    expect(find.byType(SetupGuideScreen), findsNothing);
    expect(prefs.getBool('onboardingComplete'), isTrue);
  });

  testWidgets('setup guide language change reaches the app callback', (
    tester,
  ) async {
    AppLang? changed;
    await tester.pumpWidget(
      MaterialApp(
        home: SetupGuideScreen(
          onLanguageChanged: (lang) async => changed = lang,
        ),
      ),
    );
    await tester.pumpAndSettle();
    final prefs = await SharedPreferences.getInstance();

    await tester.tap(find.byKey(const ValueKey('onboarding-lang-en')));
    await tester.pumpAndSettle();

    expect(changed, AppLang.en);
    expect(prefs.getString(kAppLanguagePrefsKey), 'en');
  });

  testWidgets('settings keeps backup, restore and setup guide entries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final snapshot = ValueNotifier(SettingsSnapshot.initial);
    addTearDown(snapshot.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: SettingsScreen(
          bindings: SettingsBindings(
            snapshot: snapshot,
            versionLabel: () => '5.0.4',
            setAutoComplete: (_) async {},
            setSteeringWheel: (_) async {},
            setKeepScreenOn: (_) async {},
            setAutoUpdate: (_) async {},
            setAutoEvents: (_) async {},
            setPillOrientation: (_) async {},
            setOverlayCancel: (_) async {},
            setNotificationControls: (_) async {},
            setHidePill: (_) async {},
            setLanguage: (_) async {},
            onDriverModeChanged: () {},
            onBackupData: (_) async {},
            onRestoreData: (_) async {},
          ),
        ),
      ),
    );

    final scrollable = find.descendant(
      of: find.byType(SettingsScreen),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-restore-data')),
      300,
      scrollable: scrollable,
    );
    await tester.ensureVisible(find.text(S.setupGuide));
    await tester.pump();

    expect(find.byKey(const ValueKey('settings-backup-data')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-restore-data')), findsOneWidget);
    expect(find.text(S.setupGuide), findsOneWidget);
  });

  testWidgets('finishing the wizard leaves existing data preferences intact', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'appLanguage': 'tr',
      'earnings_history': '[]',
      'weekly_archive': <String>[],
      'driver_name': 'Kowalski',
      'github_update_checks_enabled': true,
    });
    overlayGranted = true;
    batteryIgnored = true;
    final prefs = await SharedPreferences.getInstance();

    await pumpWizard(tester, onDone: () {});
    await tester.tap(find.byKey(const ValueKey('onboarding-skip')));
    await tester.pumpAndSettle();

    expect(prefs.getString('earnings_history'), '[]');
    expect(prefs.getStringList('weekly_archive'), isEmpty);
    expect(prefs.getString('driver_name'), 'Kowalski');
    expect(prefs.getBool('github_update_checks_enabled'), isTrue);
  });
}
