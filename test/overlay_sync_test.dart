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
