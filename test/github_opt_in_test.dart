import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/main.dart';
import 'package:rate_helper/services/event_service.dart';
import 'package:rate_helper/services/github_access.dart';
import 'package:rate_helper/services/github_http.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fails closed if any code path still constructs an [HttpClient].
class _DenyHttp extends HttpOverrides {
  int clients = 0;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    clients++;
    throw StateError('GitHub HTTP is opt-in');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    EventService.clearCache();
    GithubHttp.reset();
    GithubAccess.resetPromptGate();
    S.setLang(AppLang.en);
  });

  Future<void> pumpHome(
    WidgetTester tester,
    Map<String, Object> prefs,
  ) async {
    SharedPreferences.setMockInitialValues(prefs);
    await tester.pumpWidget(const RateHelperApp(showOnboarding: false));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('both switches off and no tap means zero GitHub requests', (
    tester,
  ) async {
    final deny = _DenyHttp();
    HttpOverrides.global = deny;
    addTearDown(() => HttpOverrides.global = null);

    await pumpHome(tester, {
      'appLanguage': 'en',
      'driver_mode_asked': true,
      GithubAccess.promptAnsweredKey: true,
      GithubAccess.autoUpdateKey: false,
      GithubAccess.autoEventsKey: false,
    });

    expect(find.text('Radar'), findsOneWidget);
    await tester.tap(find.text('Radar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text(S.loadEvents), findsOneWidget);
    expect(find.text(S.eventsNotLoadedTitle), findsOneWidget);
    expect(GithubHttp.requests, isEmpty);
    expect(deny.clients, 0);
  });

  testWidgets('a stored event list shows its age without a request', (
    tester,
  ) async {
    final deny = _DenyHttp();
    HttpOverrides.global = deny;
    addTearDown(() => HttpOverrides.global = null);

    final fetchedAt = DateTime.now().subtract(const Duration(hours: 5));
    await pumpHome(tester, {
      'appLanguage': 'en',
      'driver_mode_asked': true,
      GithubAccess.promptAnsweredKey: true,
      GithubAccess.autoUpdateKey: false,
      GithubAccess.autoEventsKey: false,
      EventService.eventsCacheJsonKey: jsonEncode([
        {
          'title': 'Concert',
          'venue': 'Arena',
          'date': '2026-10-20T18:00:00',
          'surgeLevel': 'High',
        },
      ]),
      EventService.eventsCacheAtKey: fetchedAt.millisecondsSinceEpoch,
    });

    await tester.tap(find.text('Radar'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();

    expect(find.text('Concert'), findsOneWidget);
    expect(find.text(S.eventsCacheAge(const Duration(hours: 5))), findsOneWidget);
    expect(find.text(S.loadEvents), findsNothing);
    expect(GithubHttp.requests, isEmpty);
    expect(deny.clients, 0);
  });

  testWidgets('the first-launch question is answered before any request', (
    tester,
  ) async {
    final deny = _DenyHttp();
    HttpOverrides.global = deny;
    addTearDown(() => HttpOverrides.global = null);

    await pumpHome(tester, {
      'appLanguage': 'en',
      'driver_mode_asked': true,
    });
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text(S.githubConsentBody), findsOneWidget);
    expect(find.text(S.githubConsentAllow), findsOneWidget);
    expect(find.text(S.githubConsentDeny), findsOneWidget);
    expect(GithubHttp.requests, isEmpty);
    expect(deny.clients, 0);
  });
}
