import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/overlay_sync.dart';
import 'package:rate_helper/overlay_widget.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
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
  });

  test('returns null when the payload has no counters', () {
    expect(
      OverlaySync.countersFromEvent(
        <String, String>{'action': OverlaySync.actionReloadCounters},
      ),
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

  test('PillOrientation.fromPrefs prefers the named key over the legacy bool',
      () async {
    SharedPreferences.setMockInitialValues({
      PillOrientation.prefsKey: 'horizontal',
      PillOrientation.legacyBoolKey: true,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(PillOrientation.fromPrefs(prefs), PillOrientation.horizontal);
  });

  test('PillOrientation.fromPrefs falls back to the legacy bool', () async {
    SharedPreferences.setMockInitialValues({
      PillOrientation.legacyBoolKey: true,
    });
    final prefs = await SharedPreferences.getInstance();
    expect(PillOrientation.fromPrefs(prefs), PillOrientation.vertical);
  });
}
