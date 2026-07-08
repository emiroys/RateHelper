import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/models/weekly_archive_entry.dart';

void main() {
  group('WeeklyArchiveEntry structured data round-trip', () {
    test('encodes and decodes structured JSON v2 correctly including weekStart/weekEnd and completedTrips', () {
      final entry = WeeklyArchiveEntry(
        weekStart: DateTime(2026, 5, 11),
        weekEnd: DateTime(2026, 5, 17),
        acceptRate: 85.0,
        cancelRate: 2.0,
        acceptedCount: 47,
        rejectedCount: 8,
        completedTrips: 55,
      );

      final encoded = entry.encode();
      expect(encoded, startsWith('{'));

      final decoded = WeeklyArchiveEntry.parse(encoded);
      expect(decoded.isLegacy, isFalse);
      expect(decoded.weekStart, DateTime(2026, 5, 11));
      expect(decoded.weekEnd, DateTime(2026, 5, 17));
      expect(decoded.startDate, DateTime(2026, 5, 11));
      expect(decoded.endDate, DateTime(2026, 5, 17));
      expect(decoded.acceptRate, 85.0);
      expect(decoded.cancelRate, 2.0);
      expect(decoded.acceptedCount, 47);
      expect(decoded.rejectedCount, 8);
      expect(decoded.completedTrips, 55);
    });

    test('parses legacy format and extracts clean header + rate chips without duplication', () {
      const legacyRaw = '11-17 May: %85.00 Kabul | %2.00 İptal';
      final entry = WeeklyArchiveEntry.parse(legacyRaw);

      expect(entry.isLegacy, isTrue);
      expect(entry.legacyDisplayString, '11-17 May');
      expect(entry.getFormattedDateRange(), '11-17 May');
      expect(entry.acceptRate, 85.0);
      expect(entry.cancelRate, 2.0);
      expect(entry.encode(), '11-17 May');
    });
  });

  group('WeeklyArchiveEntry dynamic render-time formatting on locale switch', () {
    test('formats date range dynamically according to active language', () {
      final entry = WeeklyArchiveEntry(
        startDate: DateTime(2026, 5, 11),
        endDate: DateTime(2026, 5, 17),
        acceptRate: 85.0,
        cancelRate: 2.0,
      );

      S.setLang(AppLang.en);
      expect(entry.getFormattedDateRange(), '11-17 May');

      S.setLang(AppLang.pl);
      expect(entry.getFormattedDateRange(), '11-17 Maj');

      S.setLang(AppLang.tr);
      expect(entry.getFormattedDateRange(), '11-17 May');
    });

    test('formats straddling month date range dynamically', () {
      final entry = WeeklyArchiveEntry(
        startDate: DateTime(2026, 5, 28),
        endDate: DateTime(2026, 6, 3),
        acceptRate: 90.0,
        cancelRate: 1.0,
      );

      S.setLang(AppLang.en);
      expect(entry.getFormattedDateRange(), '28 May - 3 Jun');

      S.setLang(AppLang.pl);
      expect(entry.getFormattedDateRange(), '28 Maj - 3 Cze');

      S.setLang(AppLang.tr);
      expect(entry.getFormattedDateRange(), '28 May - 3 Haz');
    });
  });

  group('Weekly archive clear strings localization', () {
    test('provides correct translated clear label and confirmation strings across locales', () {
      S.setLang(AppLang.tr);
      expect(S.weeklyArchiveClear, 'Temizle');
      expect(S.weeklyArchiveClearConfirm, 'Tüm haftalık kayıtlar silinecek. Emin misin?');

      S.setLang(AppLang.en);
      expect(S.weeklyArchiveClear, 'Clear');
      expect(S.weeklyArchiveClearConfirm, 'All weekly archive records will be deleted. Are you sure?');

      S.setLang(AppLang.pl);
      expect(S.weeklyArchiveClear, 'Wyczyść');
      expect(S.weeklyArchiveClearConfirm, 'Wszystkie cotygodniowe wpisy zostaną usunięte. Na pewno?');
    });
  });
}
