import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/main.dart';
import 'package:rate_helper/services/github_access.dart';
import 'package:rate_helper/settings_screen.dart';
import 'package:rate_helper/shift_counter_store.dart';
import 'package:rate_helper/update_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const systemChannel = MethodChannel('com.ratehelper.app/system');
  const packageInfoChannel = MethodChannel(
    'dev.fluttercommunity.plus/package_info',
  );

  setUp(() {
    S.setLang(AppLang.tr);
    GithubAccess.resetPromptGate();
    ShiftCounterStore.instance = _MemoryShiftStore();
    SharedPreferences.setMockInitialValues({
      'appLanguage': 'tr',
      'driver_mode_asked': true,
      GithubAccess.promptAnsweredKey: true,
      GithubAccess.autoUpdateKey: false,
      GithubAccess.autoEventsKey: false,
    });
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(systemChannel, (call) async {
      if (call.method == 'isAccessibilityServiceEnabled') return false;
      return null;
    });
    messenger.setMockMethodCallHandler(packageInfoChannel, (call) async {
      if (call.method != 'getAll') return null;
      return <String, dynamic>{
        'appName': 'RateHelper',
        'packageName': 'com.ratehelper.app',
        'version': '5.0.4',
        'buildNumber': '9',
        'buildSignature': '',
      };
    });
  });

  tearDown(() async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(systemChannel, null);
    messenger.setMockMethodCallHandler(packageInfoChannel, null);
    ShiftCounterStore.resetInstanceForTest();
    S.setLang(AppLang.tr);
    GithubAccess.resetPromptGate();
  });

  Future<void> pumpHome(WidgetTester tester) async {
    await tester.pumpWidget(const RateHelperApp(showOnboarding: false));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('gear opens settings and home no longer lists them', (
    tester,
  ) async {
    await pumpHome(tester);

    expect(find.byIcon(Icons.more_vert_rounded), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(find.text(S.autoCompleteTrips), findsNothing);
    expect(find.text(S.steeringWheelCounter), findsNothing);
    expect(find.text(S.updateCheckAction), findsNothing);
    expect(find.text(S.resetWeek), findsOneWidget);
    expect(find.text('KK383CT'), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text(S.settingsTitle), findsOneWidget);
    expect(find.text(S.settingsDriving), findsOneWidget);
    expect(find.text(S.settingsOverlay), findsOneWidget);
    expect(find.text(S.autoCompleteTrips), findsOneWidget);
    expect(find.text(S.drivingMode), findsOneWidget);
    expect(find.text(S.keepScreenOn), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text(S.crashLogTitle),
      300,
      scrollable: find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();

    expect(find.text(S.settingsPreferences), findsOneWidget);
    expect(find.text(S.settingsSystem), findsOneWidget);
    expect(find.text(S.navLang), findsOneWidget);
    expect(find.text(S.setupGuide), findsOneWidget);
    expect(find.text(S.updateCheckAction), findsOneWidget);
    expect(find.text(S.updateLastCheckedLabel(null)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('auto-complete from settings applies on the next home accept', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpHome(tester);
    expect(find.text('0'), findsWidgets);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const ValueKey('settings-auto-complete')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('autoCompleteTrips'), isTrue);

    final settingsContext = tester.element(find.byType(SettingsScreen));
    final nav = Navigator.of(settingsContext);
    expect(nav.canPop(), isTrue, reason: 'settings should be a pushed route');
    nav.pop();
    await tester.pumpAndSettle(
      const Duration(milliseconds: 50),
      EnginePhase.sendSemanticsUpdate,
      const Duration(seconds: 3),
    );
    expect(find.byType(SettingsScreen), findsNothing);

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();

    expect(find.text('1'), findsNWidgets(2));
    await tester.pump(const Duration(milliseconds: 400));
  });

  testWidgets('language chosen in settings relabels home', (tester) async {
    await pumpHome(tester);
    expect(find.text('Yakıt'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.scrollUntilVisible(
      find.text(S.navLang),
      300,
      scrollable: find.descendant(
        of: find.byType(SettingsScreen),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text(S.navLang));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('English'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('appLanguage'), 'en');

    await tester.pageBack();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Fuel'), findsOneWidget);
    expect(find.text('REQUESTS'), findsOneWidget);
  });

  testWidgets('steering-wheel toggle still asks for accessibility', (
    tester,
  ) async {
    await pumpHome(tester);
    await tester.tap(find.byIcon(Icons.settings_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const ValueKey('settings-steering-wheel')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text(S.steeringWheelDialogTitle), findsOneWidget);
    await tester.tap(find.text(S.cancel));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('steeringWheelEnabled'), isNot(true));
    final sw = tester.widget<Switch>(
      find.byKey(const ValueKey('settings-steering-wheel')),
    );
    expect(sw.value, isFalse);
  });

  testWidgets('update tile shows the version and the last check together', (
    tester,
  ) async {
    final when = DateTime(2026, 10, 15, 1, 20);
    GithubAccess.publishLastCheck(when);
    addTearDown(() => GithubAccess.publishLastCheck(null));

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: UpdateCheckTile(versionLabel: '5.0.4')),
      ),
    );

    expect(find.text(S.updateCheckAction), findsOneWidget);
    expect(find.text('v5.0.4'), findsOneWidget);
    expect(find.text(S.updateLastCheckedLabel(when)), findsOneWidget);
    expect(find.text(S.updateCheckAction), findsOneWidget);
  });
}

/// Widget tests cannot finish real file IO under the fake async zone, and
/// home stays on its skeletons until the shift store answers.
class _MemoryShiftStore extends ShiftCounterStore {
  ShiftCounters data = const ShiftCounters();

  @override
  Future<void> migrateFromPrefs(SharedPreferences prefs) async {}

  @override
  Future<ShiftCounters> read() async => data;

  @override
  Future<void> write(ShiftCounters counters) async {
    data = counters;
  }

  @override
  Future<ShiftCounters> applyDelta({
    int acceptedDelta = 0,
    int rejectedDelta = 0,
    int completedDelta = 0,
    int canceledDelta = 0,
    int max = 99999,
  }) async {
    data = ShiftCounters(
      accepted: (data.accepted + acceptedDelta).clamp(0, max),
      rejected: (data.rejected + rejectedDelta).clamp(0, max),
      completed: (data.completed + completedDelta).clamp(0, max),
      canceled: (data.canceled + canceledDelta).clamp(0, max),
    );
    return data;
  }
}
