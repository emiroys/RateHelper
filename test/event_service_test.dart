import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/services/event_service.dart';

void main() {
  final now = DateTime(2026, 10, 14, 12);

  Map<String, Object?> event({
    Object? title = 'Concert',
    Object? venue = 'Arena',
    Object? date = '2026-10-20T18:00:00',
    Object? surgeLevel = 'High',
    bool includeVenue = true,
  }) {
    return {
      'title': title,
      'date': date,
      'surgeLevel': surgeLevel,
      if (includeVenue) 'venue': venue,
    };
  }

  group('EventService.parseRemoteEvents', () {
    test('caps title and venue and keeps a valid item', () {
      final parsed = EventService.parseRemoteEvents(
        [
          event(
            title: 'A' * 121,
            venue: 'B' * 130,
          ),
        ],
        now: now,
      );

      expect(parsed, hasLength(1));
      expect(parsed.single.title, 'A' * EventService.maxTitleChars);
      expect(parsed.single.venue, 'B' * EventService.maxVenueChars);
      expect(parsed.single.surgeLevel, 'High');
      expect(parsed.single.date, DateTime.parse('2026-10-20T18:00:00'));
    });

    test('skips malformed items and still returns the valid ones', () {
      final parsed = EventService.parseRemoteEvents(
        [
          event(title: 'bad date', date: 'not-a-date'),
          event(title: 'Good', date: '2026-11-01T20:00:00', surgeLevel: 'Low'),
          'nope',
          5,
          event(title: '   ', date: '2026-11-02T20:00:00'),
          event(title: 12, date: '2026-11-03T20:00:00'),
          {'venue': 'missing title', 'date': '2026-11-04T20:00:00'},
        ],
        now: now,
      );

      expect(parsed.map((e) => e.title).toList(), ['Good']);
    });

    test('rejects dates more than 365 days away and keeps the boundary', () {
      final parsed = EventService.parseRemoteEvents(
        [
          event(title: 'edge future', date: '2027-10-14T12:00:00'),
          event(title: 'too future', date: '2027-10-15T12:00:00'),
          event(title: 'edge past', date: '2025-10-14T12:00:00'),
          event(title: 'too past', date: '2025-10-13T12:00:00'),
        ],
        now: now,
      );

      expect(
        parsed.map((e) => e.title).toList(),
        ['edge future', 'edge past'],
      );
    });

    test('uses the localized venue fallback when venue is missing', () {
      S.setLang(AppLang.en);
      final parsed = EventService.parseRemoteEvents(
        [
          event(includeVenue: false),
        ],
        now: now,
      );

      expect(parsed.single.venue, 'Unknown Venue');
    });

    test('throws when the document is not a JSON array', () {
      expect(
        () => EventService.parseRemoteEvents({'title': 'x'}, now: now),
        throwsA(isA<FormatException>()),
      );
    });

    test('an all-malformed array is empty and does not throw', () {
      expect(
        EventService.parseRemoteEvents([1, null, {}], now: now),
        isEmpty,
      );
    });
  });
}
