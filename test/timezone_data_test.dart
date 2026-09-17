import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

void main() {
  // main.dart loads the 10-year timezone database instead of the full IANA set
  // to keep it off the cold-start critical path. The app resolves exactly one
  // zone and never looks further back than the 104-week archive, so this pins
  // both the zone's presence and the DST transitions inside that window.
  setUpAll(tzdata.initializeTimeZones);

  test('Europe/Warsaw resolves from the trimmed database', () {
    expect(() => tz.getLocation('Europe/Warsaw'), returnsNormally);
  });

  test('CET/CEST transitions are correct across the archive window', () {
    final warsaw = tz.getLocation('Europe/Warsaw');
    final thisYear = DateTime.now().year;
    for (var year = thisYear - 2; year <= thisYear + 1; year++) {
      expect(
        tz.TZDateTime(warsaw, year, 1, 15).timeZoneOffset,
        const Duration(hours: 1),
        reason: 'CET expected in January $year',
      );
      expect(
        tz.TZDateTime(warsaw, year, 7, 15).timeZoneOffset,
        const Duration(hours: 2),
        reason: 'CEST expected in July $year',
      );
    }
  });
}
