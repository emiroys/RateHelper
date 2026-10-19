import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/overlay_sync.dart';
import 'package:rate_helper/overlay_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses counter payload without requiring a full prefs reload', () {
    final event = <String, String>{
      'action': OverlaySync.actionReloadCounters,
      'accepted': '12',
      'rejected': '3',
      'completed': '8',
    };
    expect(OverlaySync.shouldReloadCounters(event), isTrue);
    final counters = OverlaySync.countersFromEvent(event);
    expect(counters, isNotNull);
    expect(counters!.accepted, 12);
    expect(counters.rejected, 3);
    expect(counters.completed, 8);
    expect(counters.canceled, isNull);
  });

  test(
    'parses a canceledTrips update without touching the request counters',
    () {
      final counters = OverlaySync.countersFromEvent(<String, String>{
        'action': OverlaySync.actionReloadCounters,
        'accepted': '12',
        'rejected': '3',
        'completed': '8',
        OverlaySync.keyCanceled: '4',
      });
      expect(counters, isNotNull);
      expect(counters!.canceled, 4);
    },
  );

  test('returns null when the payload has no counters', () {
    expect(
      OverlaySync.countersFromEvent(<String, String>{
        'action': OverlaySync.actionReloadCounters,
      }),
      isNull,
    );
  });

  test('parses a settings payload', () {
    final event = <String, String>{
      'action': OverlaySync.actionSettingsChanged,
      OverlaySync.keyLang: 'pl',
      OverlaySync.keyGoalTier: 'tier2',
      OverlaySync.keyAutoComplete: 'true',
    };
    // A settings message must not be mistaken for a counters reload: that
    // path early-returns on unchanged counters and would drop the settings.
    expect(OverlaySync.shouldReloadCounters(event), isFalse);
    final settings = OverlaySync.settingsFromEvent(event);
    expect(settings, isNotNull);
    expect(settings!.lang, 'pl');
    expect(settings.goalTier, 'tier2');
    expect(settings.autoComplete, isTrue);
  });

  test('settingsFromEvent returns null for a counters message', () {
    expect(
      OverlaySync.settingsFromEvent(<String, String>{
        'action': OverlaySync.actionReloadCounters,
        'accepted': '1',
        'rejected': '1',
        'completed': '1',
      }),
      isNull,
    );
  });

  test('settingsFromEvent returns null when a field is missing', () {
    expect(
      OverlaySync.settingsFromEvent(<String, String>{
        'action': OverlaySync.actionSettingsChanged,
        OverlaySync.keyLang: 'tr',
      }),
      isNull,
    );
  });

  test('settingsFromEvent rejects unknown keys', () {
    expect(
      OverlaySync.settingsFromEvent(<String, String>{
        'action': OverlaySync.actionSettingsChanged,
        OverlaySync.keyLang: 'tr',
        OverlaySync.keyGoalTier: 'tier1',
        OverlaySync.keyAutoComplete: 'true',
        'extra': 'nope',
      }),
      isNull,
    );
  });

  test('settingsFromEvent rejects invalid lang and goal tier', () {
    expect(
      OverlaySync.settingsFromEvent(<String, String>{
        'action': OverlaySync.actionSettingsChanged,
        OverlaySync.keyLang: 'de',
        OverlaySync.keyGoalTier: 'tier1',
        OverlaySync.keyAutoComplete: 'true',
      }),
      isNull,
    );
    expect(
      OverlaySync.settingsFromEvent(<String, String>{
        'action': OverlaySync.actionSettingsChanged,
        OverlaySync.keyLang: 'tr',
        OverlaySync.keyGoalTier: 'tier9',
        OverlaySync.keyAutoComplete: 'true',
      }),
      isNull,
    );
  });

  test('settingsFromEvent accepts bool autoComplete', () {
    final settings = OverlaySync.settingsFromEvent(<String, Object>{
      'action': OverlaySync.actionSettingsChanged,
      OverlaySync.keyLang: 'en',
      OverlaySync.keyGoalTier: 'tier0',
      OverlaySync.keyAutoComplete: false,
    });
    expect(settings, isNotNull);
    expect(settings!.autoComplete, isFalse);
  });

  test('settings carry the notification-controls flag when present', () {
    final on = OverlaySync.settingsFromEvent(<String, String>{
      'action': OverlaySync.actionSettingsChanged,
      OverlaySync.keyLang: 'tr',
      OverlaySync.keyGoalTier: 'tier1',
      OverlaySync.keyAutoComplete: 'false',
      OverlaySync.keyNotificationControls: 'true',
    });
    expect(on, isNotNull);
    expect(on!.notificationControls, isTrue);

    final absent = OverlaySync.settingsFromEvent(<String, String>{
      'action': OverlaySync.actionSettingsChanged,
      OverlaySync.keyLang: 'tr',
      OverlaySync.keyGoalTier: 'tier1',
      OverlaySync.keyAutoComplete: 'false',
    });
    expect(absent, isNotNull);
    expect(absent!.notificationControls, isNull);

    expect(
      OverlaySync.settingsFromEvent(<String, String>{
        'action': OverlaySync.actionSettingsChanged,
        OverlaySync.keyLang: 'tr',
        OverlaySync.keyGoalTier: 'tier1',
        OverlaySync.keyAutoComplete: 'false',
        OverlaySync.keyNotificationControls: 'maybe',
      }),
      isNull,
    );
  });

  test('settings carry the shade-only flag when present', () {
    Map<String, String> event([String? hide]) => {
      'action': OverlaySync.actionSettingsChanged,
      OverlaySync.keyLang: 'tr',
      OverlaySync.keyGoalTier: 'tier1',
      OverlaySync.keyAutoComplete: 'false',
      OverlaySync.keyNotificationControls: 'true',
      OverlaySync.keyHidePill: ?hide,
    };
    expect(OverlaySync.settingsFromEvent(event('true'))!.hidePill, isTrue);
    expect(OverlaySync.settingsFromEvent(event('false'))!.hidePill, isFalse);
    expect(OverlaySync.settingsFromEvent(event())!.hidePill, isNull);
    expect(OverlaySync.settingsFromEvent(event('1')), isNull);
  });

  test('countersFromEvent rejects out-of-range and unknown keys', () {
    expect(
      OverlaySync.countersFromEvent(<String, String>{
        'action': OverlaySync.actionReloadCounters,
        'accepted': '-1',
        'rejected': '0',
        'completed': '0',
      }),
      isNull,
    );
    expect(
      OverlaySync.countersFromEvent(<String, String>{
        'action': OverlaySync.actionReloadCounters,
        'accepted': '${OverlaySync.maxCounterValue + 1}',
        'rejected': '0',
        'completed': '0',
      }),
      isNull,
    );
    expect(
      OverlaySync.countersFromEvent(<String, String>{
        'action': OverlaySync.actionReloadCounters,
        'accepted': '1',
        'rejected': '1',
        'completed': '1',
        'unknown': 'x',
      }),
      isNull,
    );
  });

  test('mediaKeyTargetFromEvent validates action, key and shape', () {
    expect(
      OverlaySync.mediaKeyTargetFromEvent(<String, String>{
        'action': OverlaySync.actionMediaKeyIncrement,
        OverlaySync.keyMediaKey: 'accepted',
      }),
      'accepted',
    );
    expect(
      OverlaySync.mediaKeyTargetFromEvent(<String, String>{
        'action': OverlaySync.actionMediaKeyIncrement,
        OverlaySync.keyMediaKey: 'bogus',
      }),
      isNull,
    );
    expect(
      OverlaySync.mediaKeyTargetFromEvent(<String, String>{
        'action': OverlaySync.actionMediaKeyIncrement,
        OverlaySync.keyMediaKey: 'accepted',
        'extra': '1',
      }),
      isNull,
    );
  });

  test('isFlushRequest matches only the close-time flush action', () {
    expect(
      OverlaySync.isFlushRequest(<String, String>{
        'action': OverlaySync.actionFlushCounters,
      }),
      isTrue,
    );
    expect(
      OverlaySync.isFlushRequest(<String, String>{
        'action': OverlaySync.actionMediaKeyIncrement,
        OverlaySync.keyMediaKey: 'accepted',
      }),
      isFalse,
    );
    expect(OverlaySync.isFlushRequest(null), isFalse);
  });

  test('deliver never throws on malformed input', () {
    expect(() => OverlaySync.deliver(null), returnsNormally);
    expect(() => OverlaySync.deliver(42), returnsNormally);
    expect(
      () => OverlaySync.deliver(<String, Object>{
        'action': 'not_a_real_action',
        'nonsense': true,
      }),
      returnsNormally,
    );
  });

  test('deliver routes validated messages to callbacks', () {
    var countersSeen = false;
    var settingsSeen = false;
    var mediaSeen = false;
    OverlaySync.deliver(<String, String>{
      'action': OverlaySync.actionSettingsChanged,
      OverlaySync.keyLang: 'pl',
      OverlaySync.keyGoalTier: 'tier2',
      OverlaySync.keyAutoComplete: 'false',
    }, onSettings: (_) => settingsSeen = true);
    expect(settingsSeen, isTrue);

    OverlaySync.deliver(<String, String>{
      'action': OverlaySync.actionMediaKeyIncrement,
      OverlaySync.keyMediaKey: 'rejected',
    }, onMediaKey: (_) => mediaSeen = true);
    expect(mediaSeen, isTrue);

    OverlaySync.deliver(<String, String>{
      'action': OverlaySync.actionReloadCounters,
      'accepted': '2',
      'rejected': '1',
      'completed': '3',
    }, onCounters: (_) => countersSeen = true);
    expect(countersSeen, isTrue);
  });

  test(
    'PillOrientation.fromPrefs prefers the named key over the legacy bool',
    () async {
      SharedPreferences.setMockInitialValues({
        PillOrientation.prefsKey: 'horizontal',
        PillOrientation.legacyBoolKey: true,
      });
      final prefs = await SharedPreferences.getInstance();
      expect(PillOrientation.fromPrefs(prefs), PillOrientation.horizontal);
    },
  );

  test('PillOrientation.fromPrefs falls back to the legacy bool', () async {
    SharedPreferences.setMockInitialValues({
      PillOrientation.legacyBoolKey: true,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(PillOrientation.fromPrefs(prefs), PillOrientation.vertical);
  });

  test('a burst of counter pings flushes once with the latest snapshot', () {
    final pending = <void Function()>[];
    final burst = OverlayCounterBurst(schedule: pending.add);
    final applied = <OverlayCounters?>[];

    for (var i = 1; i <= 10; i++) {
      burst.add(
        OverlayCounters(accepted: i, rejected: 1, completed: i - 1),
        applied.add,
      );
    }

    expect(applied, isEmpty);
    expect(pending, hasLength(1));
    pending.single();
    expect(applied, hasLength(1));
    expect(applied.single!.accepted, 10);
    expect(applied.single!.rejected, 1);
    expect(applied.single!.completed, 9);
  });

  test('an empty ping after a payload in the same burst reads the store', () {
    final pending = <void Function()>[];
    final burst = OverlayCounterBurst(schedule: pending.add);
    final applied = <OverlayCounters?>[];

    burst.add(
      const OverlayCounters(accepted: 2, rejected: 0, completed: 2),
      applied.add,
    );
    burst.add(null, applied.add);
    pending.single();
    expect(applied, hasLength(1));
    expect(applied.single, isNull);
  });

  test('pingCountersChanged sends the counter payload', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const channel = 'x-slayer/overlay_messenger';
    const codec = JSONMessageCodec();
    addTearDown(() => messenger.setMockMessageHandler(channel, null));

    ByteData? captured;
    messenger.setMockMessageHandler(channel, (data) async {
      captured = data;
      return null;
    });

    OverlaySync.pingCountersChanged(
      accepted: 4,
      rejected: 1,
      completed: 3,
      canceled: 2,
    );
    await Future<void>.delayed(Duration.zero);

    final decoded = codec.decodeMessage(captured);
    final counters = OverlaySync.countersFromEvent(decoded);
    expect(counters, isNotNull);
    expect(counters!.accepted, 4);
    expect(counters.rejected, 1);
    expect(counters.completed, 3);
    expect(counters.canceled, 2);
  });

  test('overlayListener is broadcast and accepts a new subscription', () async {
    final stream = FlutterOverlayWindow.overlayListener;
    expect(stream.isBroadcast, isTrue);

    final first = <Object?>[];
    final second = <Object?>[];
    final sub = stream.listen(first.add);
    final other = stream.listen(second.add);
    final payload = OverlaySync.counterPayload(
      accepted: 5,
      rejected: 1,
      completed: 4,
    );
    await _deliverOverlayMessage(payload);
    expect(OverlaySync.countersFromEvent(first.single)?.accepted, 5);
    expect(OverlaySync.countersFromEvent(second.single)?.accepted, 5);
    await sub.cancel();
    await other.cancel();

    final reopened = <Object?>[];
    final again = stream.listen(reopened.add);
    await _deliverOverlayMessage(payload);
    expect(reopened, isNotEmpty);
    expect(OverlaySync.countersFromEvent(reopened.single)?.completed, 4);
    await again.cancel();
  });
}

Future<void> _deliverOverlayMessage(Object payload) async {
  const codec = JSONMessageCodec();
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'x-slayer/overlay_messenger',
        codec.encodeMessage(payload),
        (_) {},
      );
}
