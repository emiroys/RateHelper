import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/app_widgets.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/main.dart';
import 'package:rate_helper/onboarding_screen.dart';
import 'package:rate_helper/services/backup_service.dart';
import 'package:rate_helper/services/github_access.dart';
import 'package:rate_helper/shift_counter_store.dart';
import 'package:rate_helper/startup_language.dart';
import 'package:rate_helper/survey_api.dart';
import 'package:rate_helper/survey_screen.dart';
import 'package:rate_helper/survey_store.dart';
import 'package:rate_helper/tap_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_10y.dart' as tz;

class _FakeSurveyApi implements SurveyApi {
  _FakeSurveyApi(this.outcomes);

  final List<SurveySubmitOutcome> outcomes;
  int calls = 0;
  Map<String, Object?>? lastPayload;

  @override
  Future<SurveySubmitOutcome> submit(Map<String, Object?> payload) async {
    lastPayload = payload;
    final result = outcomes[calls.clamp(0, outcomes.length - 1)];
    calls++;
    return result;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz.initializeTimeZones);

  const overlayChannel = MethodChannel('x-slayer/overlay_channel');
  const systemChannel = MethodChannel('com.ratehelper.app/system');

  setUp(() {
    S.setLang(AppLang.tr);
    SurveyStore.resetForTest();
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    S.setLang(AppLang.tr);
    SurveyStore.resetForTest();
  });

  group('survey gate', () {
    test('a fresh installation needs the survey exactly once', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(SurveyStore.shouldShowSurvey(prefs), isTrue);

      await SurveyStore.markCompleted(prefs);
      expect(SurveyStore.shouldShowSurvey(prefs), isFalse);
    });

    test('completion survives language changes and restarts', () async {
      SharedPreferences.setMockInitialValues({
        kSurveyCompletedPrefsKey: true,
        kAppLanguagePrefsKey: 'pl',
      });
      final prefs = await SharedPreferences.getInstance();

      expect(SurveyStore.shouldShowSurvey(prefs), isFalse);
      // A settings/backup restore leaves these keys untouched because they
      // are not part of BackupService's managed set.
      final dir = await Directory.systemTemp.createTemp('ratehelper-survey-');
      addTearDown(() async {
        if (await dir.exists()) await dir.delete(recursive: true);
      });
      final backup = await BackupService.createBackupJson(
        appVersion: '5.1.0',
        prefs: prefs,
        shiftStore: ShiftCounterStore(
          file: File('${dir.path}${Platform.pathSeparator}shift.json'),
        ),
        tapStore: TapHistoryStore(
          file: File('${dir.path}${Platform.pathSeparator}tap.jsonl'),
        ),
      );
      expect(backup, isNot(contains(kSurveyCompletedPrefsKey)));
      expect(SurveyStore.shouldShowSurvey(prefs), isFalse);
    });

    test('the installation id is stable and anonymous', () async {
      final prefs = await SharedPreferences.getInstance();
      final first = await SurveyStore.installationId(prefs);
      final second = await SurveyStore.installationId(prefs);

      expect(first, second);
      expect(first, matches(RegExp(r'^[a-f0-9]{32}$')));
    });

    test('the payload has exactly the allowed anonymous fields', () {
      const answers = SurveyAnswers(
        continueChoice: SurveyContinueChoice.maybe,
        priceChoice: SurveyPriceChoice.ten,
        featureChoice: SurveyFeatureChoice.fuelOrlen,
      );
      final payload = answers.toJson('abcdefabcdefabcdefabcdefabcdef12');

      expect(payload.keys.toSet(), {
        'schemaVersion',
        'installationId',
        'continueUsing',
        'monthlyPrice',
        'mostValuableFeature',
      });
      expect(payload['schemaVersion'], 1);
      expect(payload['continueUsing'], 'maybe');
      expect(payload['monthlyPrice'], '10');
      expect(payload['mostValuableFeature'], 'fuel_orlen');
      for (final forbidden in [
        'name',
        'phone',
        'email',
        'location',
        'trip',
        'earnings',
        'chatId',
      ]) {
        expect(payload.keys, isNot(contains(forbidden)));
      }
    });
  });

  group('survey screen', () {
    Future<void> tapOption(WidgetTester tester, String key) async {
      final finder = find.byKey(ValueKey(key));
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      await tester.tap(finder);
      await tester.pump();
    }

    Future<SharedPreferences> pumpSurvey(
      WidgetTester tester, {
      SurveyApi? api,
      VoidCallback? onCompleted,
    }) async {
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        MaterialApp(
          home: SurveyScreen(
            onCompleted: onCompleted ?? () {},
            api: api ?? _FakeSurveyApi([SurveySubmitOutcome.sent]),
            prefs: prefs,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return prefs;
    }

    testWidgets('has no Skip, Later or Don\'t show again controls', (
      tester,
    ) async {
      await pumpSurvey(tester);
      expect(find.text(S.skip), findsNothing);
      expect(find.text('Later'), findsNothing);
      expect(find.textContaining('show again'), findsNothing);
      expect(find.textContaining('Don\'t show'), findsNothing);
    });

    testWidgets('blocks Android back and has no outside dismissal', (
      tester,
    ) async {
      await pumpSurvey(tester);
      final popScope = tester.widget<PopScope>(
        find.byKey(const ValueKey('survey-pop-scope')),
      );
      expect(popScope.canPop, isFalse);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets(
      'submit stays disabled until all three questions are answered',
      (tester) async {
        await pumpSurvey(tester);
        expect(
          tester
              .widget<AppPrimaryButton>(
                find.byKey(const ValueKey('survey-submit')),
              )
              .enabled,
          isFalse,
        );

        await tapOption(tester, 'survey-continue-yes');
        await tapOption(tester, 'survey-price-fifteen');
        expect(
          tester
              .widget<AppPrimaryButton>(
                find.byKey(const ValueKey('survey-submit')),
              )
              .enabled,
          isFalse,
        );

        await tapOption(tester, 'survey-feature-overlayCounters');
        expect(
          tester
              .widget<AppPrimaryButton>(
                find.byKey(const ValueKey('survey-submit')),
              )
              .enabled,
          isTrue,
        );
      },
    );

    testWidgets('answers can be switched among Turkish, English and Polish', (
      tester,
    ) async {
      final prefs = await pumpSurvey(tester);
      expect(find.text(S.surveyTitle), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('survey-lang-en')));
      await tester.pumpAndSettle();
      expect(S.lang, AppLang.en);
      expect(find.text(S.surveyTitle), findsOneWidget);
      expect(prefs.getString(kAppLanguagePrefsKey), 'en');

      await tester.tap(find.byKey(const ValueKey('survey-lang-pl')));
      await tester.pumpAndSettle();
      expect(S.lang, AppLang.pl);
      expect(find.text(S.surveyTitle), findsOneWidget);
      expect(prefs.getString(kAppLanguagePrefsKey), 'pl');
    });

    testWidgets('offline answer is queued, completed and retried later', (
      tester,
    ) async {
      final prefs = await pumpSurvey(
        tester,
        api: _FakeSurveyApi([SurveySubmitOutcome.retryable]),
      );

      await tapOption(tester, 'survey-continue-maybe');
      await tapOption(tester, 'survey-price-ten');
      await tapOption(tester, 'survey-feature-fuelOrlen');
      await tester.tap(find.byKey(const ValueKey('survey-submit')));
      await tester.pumpAndSettle();

      expect(find.text(S.surveyQueuedTitle), findsOneWidget);
      expect(prefs.getBool(kSurveyCompletedPrefsKey), isTrue);
      expect(SurveyStore.pendingJson(prefs), isNotNull);

      SurveyStore.resetForTest();
      final retryApi = _FakeSurveyApi([SurveySubmitOutcome.sent]);
      final result = await SurveyStore.syncPending(
        prefs: prefs,
        api: retryApi,
        force: true,
      );
      expect(result, SurveySyncResult.delivered);
      expect(retryApi.calls, 1);
      expect(SurveyStore.pendingJson(prefs), isNull);
      expect(prefs.getBool(kSurveyCompletedPrefsKey), isTrue);
    });

    testWidgets('a duplicate retry never queues a second answer', (
      tester,
    ) async {
      final prefs = await pumpSurvey(tester);
      await tapOption(tester, 'survey-continue-yes');
      await tapOption(tester, 'survey-price-five');
      await tapOption(tester, 'survey-feature-other');
      await tester.tap(find.byKey(const ValueKey('survey-submit')));
      await tester.pumpAndSettle();

      SurveyStore.resetForTest();
      final noWork = _FakeSurveyApi([SurveySubmitOutcome.sent]);
      expect(
        await SurveyStore.syncPending(prefs: prefs, api: noWork, force: true),
        SurveySyncResult.none,
      );
      expect(noWork.calls, 0);
    });

    testWidgets('fits a small screen with enlarged text in all languages', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final prefs = await SharedPreferences.getInstance();

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
            home: SurveyScreen(
              key: ValueKey('survey-${lang.name}'),
              onCompleted: () {},
              api: _FakeSurveyApi([SurveySubmitOutcome.sent]),
              prefs: prefs,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: lang.name);
      }
    });
  });

  group('startup gate', () {
    testWidgets('an existing user sees the mandatory survey after update', (
      tester,
    ) async {
      await tester.pumpWidget(
        const RateHelperApp(showOnboarding: false, showSurvey: true),
      );
      await tester.pumpAndSettle();
      expect(find.byType(SurveyScreen), findsOneWidget);
    });

    testWidgets('a fresh install sees the survey after finishing onboarding', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        kAppLanguagePrefsKey: 'en',
        GithubAccess.promptAnsweredKey: true,
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(overlayChannel, (call) async {
        if (call.method == 'checkPermission') return true;
        if (call.method == 'requestPermission') return true;
        return null;
      });
      messenger.setMockMethodCallHandler(systemChannel, (call) async {
        if (call.method == 'manufacturer') return 'samsung';
        if (call.method == 'isIgnoringBatteryOptimizations') return true;
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(overlayChannel, null);
        messenger.setMockMethodCallHandler(systemChannel, null);
      });

      await tester.pumpWidget(
        const RateHelperApp(showOnboarding: true, showSurvey: true),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OnboardingScreen), findsOneWidget);

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('onboarding-primary')));
        await tester.pumpAndSettle();
      }
      expect(find.byType(SurveyScreen), findsOneWidget);
    });

    testWidgets('a completed survey is not shown again after restart', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        kSurveyCompletedPrefsKey: true,
        kAppLanguagePrefsKey: 'en',
        GithubAccess.promptAnsweredKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(SurveyStore.shouldShowSurvey(prefs), isFalse);
    });
  });
}
