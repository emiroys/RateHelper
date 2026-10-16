import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/overlay_sync.dart';
import 'package:rate_helper/overlay_widget.dart';
import 'package:rate_helper/shade_controls.dart';
import 'package:rate_helper/shift_counter_store.dart';
import 'package:rate_helper/tap_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  tearDown(() => S.setLang(AppLang.tr));

  group('ShadeControls.content', () {
    test('acceptance rate with two decimals and the raw counts', () {
      S.setLang(AppLang.tr);
      final c = ShadeControls.content(accepted: 6, rejected: 1);
      expect(c['title'], 'Kabul oranı %85.71');
      expect(c['text'], 'Kabul: 6 · Red: 1');
      expect(c['accept'], 'Kabul +1');
      expect(c['reject'], 'Red +1');
      expect(c['channel'], isNotEmpty);
    });

    test('empty shift reads 100.00 like the home rate card', () {
      S.setLang(AppLang.en);
      final c = ShadeControls.content(accepted: 0, rejected: 0);
      expect(c['title'], 'Acceptance 100.00%');
      expect(c['text'], 'Accepted: 0 · Rejected: 0');
    });

    test('no money figures in any language', () {
      for (final lang in AppLang.values) {
        S.setLang(lang);
        final c = ShadeControls.content(accepted: 120, rejected: 30);
        final all = c.values.join(' ').toLowerCase();
        expect(all, isNot(contains('pln')), reason: lang.name);
        expect(all, isNot(contains('zł')), reason: lang.name);
        expect(c['title'], contains('80.00'), reason: lang.name);
        expect(c.keys.toSet(), {
          'channel',
          'title',
          'text',
          'rate',
          'rateLabel',
          'tone',
          'accept',
          'reject',
        });
      }
    });

    test('tone follows the pill colour rule', () {
      S.setLang(AppLang.tr);
      String tone(int a, int r, double? req) =>
          ShadeControls.content(
                accepted: a,
                rejected: r,
                requiredRate: req,
              )['tone']
              as String;
      expect(tone(9, 1, 80), 'green'); // 90.00
      expect(tone(81, 19, 80), 'amber'); // 81.00, inside the 2-pt buffer
      expect(tone(79, 21, 80), 'red'); // 79.00
      expect(tone(1, 9, null), 'green', reason: 'tier0 has no goal');
      expect(ShadeControls.content(accepted: 6, rejected: 1)['rate'], '%85.71');
    });
  });

  group('ShadeNotificationThrottle', () {
    testWidgets('first change posts at once, a burst collapses to one', (
      tester,
    ) async {
      final sent = <Map<String, Object?>?>[];
      final throttle = ShadeNotificationThrottle(
        send: (c) async {
          sent.add(c);
          return true;
        },
      );
      addTearDown(throttle.dispose);

      throttle.update({'title': 'a'});
      expect(sent, [
        {'title': 'a'},
      ]);

      for (var i = 0; i < 10; i++) {
        throttle.update({'title': 'b$i'});
      }
      await tester.pump(const Duration(milliseconds: 999));
      expect(sent, hasLength(1));

      await tester.pump(const Duration(milliseconds: 1));
      expect(sent, hasLength(2));
      expect(sent.last, {'title': 'b9'});

      // Cooldown re-armed by the trailing post; nothing new → nothing sent.
      await tester.pump(const Duration(seconds: 2));
      expect(sent, hasLength(2));
    });

    testWidgets('identical content is not re-posted', (tester) async {
      var calls = 0;
      final throttle = ShadeNotificationThrottle(
        send: (_) async {
          calls++;
          return true;
        },
      );
      addTearDown(throttle.dispose);

      throttle.update(null);
      expect(calls, 0, reason: 'service already shows the plain notification');

      throttle.update({'title': 'x'});
      await tester.pump(const Duration(seconds: 1));
      throttle.update({'title': 'x'});
      await tester.pump(const Duration(seconds: 1));
      expect(calls, 1);

      throttle.update(null);
      expect(calls, 2, reason: 'switching off restores the plain one');
      throttle.dispose();
    });

    testWidgets('a failed post is retried on the next change', (tester) async {
      var calls = 0;
      final throttle = ShadeNotificationThrottle(
        send: (_) async {
          calls++;
          if (calls == 1) throw PlatformException(code: 'x');
          return true;
        },
      );
      addTearDown(throttle.dispose);

      throttle.update({'title': 'x'});
      await tester.pump(const Duration(seconds: 1));
      throttle.update({'title': 'x'});
      expect(calls, 2);
      throttle.dispose();
    });

    testWidgets('dispose drops a pending trailing post', (tester) async {
      var calls = 0;
      final throttle = ShadeNotificationThrottle(
        send: (_) async {
          calls++;
          return true;
        },
      );
      throttle.update({'title': 'a'});
      throttle.update({'title': 'b'});
      throttle.dispose();
      await tester.pump(const Duration(seconds: 2));
      expect(calls, 1);
    });
  });

  group('overlay pill', () {
    late List<Object?> posts;

    setUp(() {
      posts = [];
      ShiftCounterStore.instance = _MemoryShiftStore();
      TapHistoryStore.instance = _NoopTapHistory();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('x-slayer/overlay_channel'),
        (call) async => false,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('x-slayer/overlay'),
        (call) async {
          if (call.method == 'updateNotification') posts.add(call.arguments);
          return true;
        },
      );
      messenger.setMockMessageHandler(
        'x-slayer/overlay_messenger',
        (_) async => null,
      );
    });

    tearDown(() {
      ShiftCounterStore.resetInstanceForTest();
      TapHistoryStore.resetInstanceForTest();
    });

    testWidgets('setting off: taps never touch the notification', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({'appLanguage': 'tr'});
      await tester.pumpWidget(const MaterialApp(home: OverlayWidget()));
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(seconds: 2));
      expect(posts, isEmpty);
    });

    testWidgets(
      'setting on: rapid taps update the text at most once a second',
      (tester) async {
        SharedPreferences.setMockInitialValues({
          'appLanguage': 'tr',
          ShadeControls.prefsKey: true,
        });
        await tester.pumpWidget(const MaterialApp(home: OverlayWidget()));
        await tester.pump();
        await tester.pump();
        expect(posts, hasLength(1));
        expect((posts.single as Map)['title'], 'Kabul oranı %100.00');

        for (var i = 0; i < 5; i++) {
          await tester.tap(find.byIcon(Icons.add_rounded));
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.tap(find.byIcon(Icons.remove_rounded));
        await tester.pump(const Duration(milliseconds: 50));
        expect(posts, hasLength(1));

        await tester.pump(const Duration(seconds: 1));
        expect(posts, hasLength(2));
        final latest = posts.last as Map;
        expect(latest['title'], 'Kabul oranı %83.33');
        expect(latest['text'], 'Kabul: 5 · Red: 1');
        await tester.pump(const Duration(seconds: 2));
      },
    );
  });

  test('pillHidden needs both flags', () {
    expect(
      ShadeControls.pillHidden(notificationControls: true, hidePill: true),
      isTrue,
    );
    expect(
      ShadeControls.pillHidden(notificationControls: false, hidePill: true),
      isFalse,
    );
    expect(
      ShadeControls.pillHidden(notificationControls: true, hidePill: false),
      isFalse,
    );
  });

  group('shade-only window', () {
    late List<MethodCall> window;
    late List<Object?> posts;

    setUp(() {
      window = [];
      posts = [];
      ShiftCounterStore.instance = _MemoryShiftStore();
      TapHistoryStore.instance = _NoopTapHistory();
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('x-slayer/overlay_channel'),
        (call) async => false,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('x-slayer/overlay'),
        (call) async {
          if (call.method == 'updateNotification') {
            posts.add(call.arguments);
          } else {
            window.add(call);
          }
          return true;
        },
      );
      messenger.setMockMessageHandler(
        'x-slayer/overlay_messenger',
        (_) async => null,
      );
    });

    tearDown(() {
      ShiftCounterStore.resetInstanceForTest();
      TapHistoryStore.resetInstanceForTest();
    });

    List<Object?> hiddenCalls() => window
        .where((c) => c.method == 'setWindowHidden')
        .map((c) => (c.arguments as Map)['hidden'])
        .toList();

    Future<void> receive(WidgetTester tester, Map<String, String> msg) async {
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            'x-slayer/overlay_messenger',
            const JSONMessageCodec().encodeMessage(msg),
            (_) {},
          );
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    Map<String, String> settings({
      required bool controls,
      required bool hide,
    }) => {
      'action': OverlaySync.actionSettingsChanged,
      OverlaySync.keyLang: 'tr',
      OverlaySync.keyGoalTier: 'tier1',
      OverlaySync.keyAutoComplete: 'false',
      OverlaySync.keyNotificationControls: '$controls',
      OverlaySync.keyHidePill: '$hide',
    };

    testWidgets('starts hidden: no pill drawn, steering-wheel taps still '
        'count and reach the notification', (tester) async {
      SharedPreferences.setMockInitialValues({
        'appLanguage': 'tr',
        ShadeControls.prefsKey: true,
        ShadeControls.hidePillPrefsKey: true,
      });
      await tester.pumpWidget(
        const MaterialApp(home: OverlayWidget(initialHidden: true)),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.text('R'), findsNothing);
      expect(hiddenCalls(), [true]);
      expect(window.where((c) => c.method == 'resizeOverlay'), isEmpty);
      expect(posts, hasLength(1));

      await receive(tester, {
        'action': OverlaySync.actionMediaKeyIncrement,
        OverlaySync.keyMediaKey: 'accepted',
      });
      await receive(tester, {
        'action': OverlaySync.actionMediaKeyIncrement,
        OverlaySync.keyMediaKey: 'rejected',
      });
      await tester.pump(const Duration(seconds: 2));

      expect((posts.last as Map)['text'], 'Kabul: 1 · Red: 1');
      expect((posts.last as Map)['title'], 'Kabul oranı %50.00');
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('toggling while running hides and restores the same pill', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'appLanguage': 'tr',
        ShadeControls.prefsKey: true,
      });
      await tester.pumpWidget(const MaterialApp(home: OverlayWidget()));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump(const Duration(milliseconds: 50));
      window.clear();

      await receive(tester, settings(controls: true, hide: true));
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(hiddenCalls(), [true]);

      await receive(tester, settings(controls: true, hide: false));
      expect(hiddenCalls(), [true, false]);
      final resize = window.lastWhere((c) => c.method == 'resizeOverlay');
      expect((resize.arguments as Map)['width'], OverlayWidget.pillWidthDp);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      expect(find.text('%66.7'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('notification controls off while hidden shows the pill', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'appLanguage': 'tr',
        ShadeControls.prefsKey: true,
        ShadeControls.hidePillPrefsKey: true,
      });
      await tester.pumpWidget(
        const MaterialApp(home: OverlayWidget(initialHidden: true)),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byIcon(Icons.add_rounded), findsNothing);

      // A sender that still says hide=true must not keep a pill-less,
      // button-less service: the rule needs both flags.
      await receive(tester, settings(controls: false, hide: true));

      expect(hiddenCalls(), [true, false]);
      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(posts.last, isNull);
    });

    testWidgets('a collapsed pill comes back as the bubble', (tester) async {
      SharedPreferences.setMockInitialValues({
        'appLanguage': 'tr',
        ShadeControls.prefsKey: true,
        ShadeControls.hidePillPrefsKey: true,
        OverlayWidget.collapsedPrefsKey: true,
      });
      await tester.pumpWidget(
        const MaterialApp(
          home: OverlayWidget(initialHidden: true, initialCollapsed: true),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(window.where((c) => c.method == 'resizeOverlay'), isEmpty);

      await receive(tester, settings(controls: true, hide: false));

      final resize = window.lastWhere((c) => c.method == 'resizeOverlay');
      expect((resize.arguments as Map)['width'], OverlayWidget.bubbleSizeDp);
      expect(find.text('R'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });
}

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
  Future<ShiftCounters> merge({
    int? accepted,
    int? rejected,
    int? completed,
    int? canceled,
  }) async {
    data = data.copyWith(
      accepted: accepted,
      rejected: rejected,
      completed: completed,
      canceled: canceled,
    );
    return data;
  }
}

class _NoopTapHistory extends TapHistoryStore {
  @override
  Future<void> append(String type, {DateTime? at}) async {}

  @override
  Future<void> migrateFromPrefs(SharedPreferences prefs) async {}
}
