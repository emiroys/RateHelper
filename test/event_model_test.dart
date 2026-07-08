import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/models/event_model.dart';

void main() {
  group('EventModel localization fallback', () {
    test('uses localized fallback strings for missing title and venue', () {
      S.setLang(AppLang.en);
      final eventEn = EventModel.fromJson({});
      expect(eventEn.title, 'Unknown Event');
      expect(eventEn.venue, 'Unknown Venue');

      S.setLang(AppLang.tr);
      final eventTr = EventModel.fromJson({});
      expect(eventTr.title, 'Bilinmeyen Etkinlik');
      expect(eventTr.venue, 'Bilinmeyen Mekan');

      S.setLang(AppLang.pl);
      final eventPl = EventModel.fromJson({});
      expect(eventPl.title, 'Nieznane wydarzenie');
      expect(eventPl.venue, 'Nieznane miejsce');
    });
  });
}
