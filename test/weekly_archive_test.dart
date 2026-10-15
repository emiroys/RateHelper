import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/models/weekly_archive_entry.dart';

void main() {
  group('WeeklyArchiveEntry structured data round-trip', () {
    test(
      'encodes and decodes structured JSON v2 correctly including weekStart/weekEnd and completedTrips',
      () {
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
      },
    );

    test(
      'parses legacy format and extracts clean header + rate chips without duplication',
      () {
        const legacyRaw = '11-17 May: %85.00 Kabul | %2.00 İptal';
        final entry = WeeklyArchiveEntry.parse(legacyRaw);

        expect(entry.isLegacy, isTrue);
        expect(entry.legacyDisplayString, '11-17 May');
        expect(entry.getFormattedDateRange(), '11-17 May');
        expect(entry.acceptRate, 85.0);
        expect(entry.cancelRate, 2.0);
        expect(entry.encode(), '11-17 May');
      },
    );
  });

  group(
    'WeeklyArchiveEntry dynamic render-time formatting on locale switch',
    () {
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
    },
  );

  group('Weekly archive clear strings localization', () {
    test(
      'provides correct translated clear label and confirmation strings across locales',
      () {
        S.setLang(AppLang.tr);
        expect(S.weeklyArchiveClear, 'Temizle');
        expect(
          S.weeklyArchiveClearConfirm,
          'Tüm haftalık kayıtlar silinecek. Emin misin?',
        );

        S.setLang(AppLang.en);
        expect(S.weeklyArchiveClear, 'Clear');
        expect(
          S.weeklyArchiveClearConfirm,
          'All weekly archive records will be deleted. Are you sure?',
        );

        S.setLang(AppLang.pl);
        expect(S.weeklyArchiveClear, 'Wyczyść');
        expect(
          S.weeklyArchiveClearConfirm,
          'Wszystkie cotygodniowe wpisy zostaną usunięte. Na pewno?',
        );
      },
    );
  });

  group('weekly archive rates, goals, and duplicate weeks', () {
    const floors = [
      WeeklyGoalFloor(name: 'tier0', minTrips: 0, acceptRate: null),
      WeeklyGoalFloor(name: 'tier1', minTrips: 100, acceptRate: 80),
      WeeklyGoalFloor(name: 'tier2', minTrips: 150, acceptRate: 70),
      WeeklyGoalFloor(name: 'tier3', minTrips: 200, acceptRate: 60),
    ];

    tearDown(() => S.setLang(AppLang.tr));

    test('formats acceptance and cancellation rates to 1 decimal', () {
      expect(formatWeeklyRate(80.34), '80.3');
      expect(formatWeeklyRate(3.76), '3.8');
      expect(formatWeeklyRate(80), '80.0');
    });

    test('round-trips the goal tier, thresholds, and canceled trips', () {
      final entry = WeeklyArchiveEntry(
        weekStart: DateTime(2026, 9, 7, 4),
        weekEnd: DateTime(2026, 9, 13, 4),
        acceptRate: 80.34,
        cancelRate: 3.76,
        acceptedCount: 106,
        rejectedCount: 26,
        completedTrips: 102,
        canceledTrips: 4,
        canceledTripsStored: true,
        goalTier: 'tier0',
        targetAcceptRateStored: true,
        maxCancelRate: kWeeklyCancelCeiling,
      );

      final decoded = WeeklyArchiveEntry.parse(entry.encode());
      expect(decoded.goalTier, 'tier0');
      expect(decoded.targetAcceptRateStored, isTrue);
      expect(decoded.targetAcceptRate, isNull);
      expect(decoded.maxCancelRate, kWeeklyCancelCeiling);
      expect(decoded.canceledTrips, 4);
      expect(decoded.canceledTripsStored, isTrue);
      expect(decoded.acceptRate, 80.34);
      expect(decoded.cancelRate, 3.76);
    });

    test('grades a stored goal instead of a fixed 80 percent', () {
      final metAt70 = assessWeeklyGoal(
        _week(acceptRate: 75, target: 70, tier: 'tier2'),
        floors: floors,
        fallbackTier: 'tier1',
        fallbackAcceptRate: 80,
      );
      expect(metAt70.acceptMet, isTrue);
      expect(metAt70.targetAcceptRate, 70);

      final missedAt90 = assessWeeklyGoal(
        _week(acceptRate: 85, target: 90, tier: 'tier4'),
        floors: floors,
        fallbackTier: 'tier1',
        fallbackAcceptRate: 80,
      );
      expect(missedAt90.acceptMet, isFalse);

      final cancelWithinRaisedLimit = assessWeeklyGoal(
        _week(acceptRate: 90, target: 80, cancelRate: 6, maxCancel: 10),
        floors: floors,
      );
      expect(cancelWithinRaisedLimit.cancelMet, isTrue);

      final cancelOverDefault = assessWeeklyGoal(
        _week(acceptRate: 90, target: 80, cancelRate: 5.1),
        floors: floors,
      );
      expect(cancelOverDefault.cancelMet, isFalse);
      expect(cancelOverDefault.maxCancelRate, kWeeklyCancelCeiling);

      final exactlyOnCeiling = assessWeeklyGoal(
        _week(acceptRate: 90, target: 80, cancelRate: 5),
        floors: floors,
      );
      expect(exactlyOnCeiling.cancelMet, isTrue);
    });

    test('infers a missing goal from completed trips, else the current goal', () {
      const oldJson =
          '{"v":2,"weekStart":"2026-09-07T04:00:00.000","weekEnd":"2026-09-13T04:00:00.000",'
          '"acceptRate":75.0,"cancelRate":3.0,"acceptedCount":75,"rejectedCount":25,"completedTrips":160}';
      final old = WeeklyArchiveEntry.parse(oldJson);
      expect(old.goalTier, isNull);
      expect(old.targetAcceptRateStored, isFalse);

      final inferred = assessWeeklyGoal(
        old,
        floors: floors,
        fallbackTier: 'tier1',
        fallbackAcceptRate: 80,
      );
      expect(inferred.tierName, 'tier2');
      expect(inferred.targetAcceptRate, 70);
      expect(inferred.acceptMet, isTrue);

      final noTrips = assessWeeklyGoal(
        _week(acceptRate: 75, completed: 0),
        floors: floors,
        fallbackTier: 'tier1',
        fallbackAcceptRate: 80,
      );
      expect(noTrips.tierName, 'tier1');
      expect(noTrips.targetAcceptRate, 80);
      expect(noTrips.acceptMet, isFalse);
    });

    test(
      'recovers canceled trips from the stored rate when the count is absent',
      () {
        final rate = 4 / 106 * 100;
        expect(inferCanceledTrips(102, rate), 4);
      },
    );

    test('merges two saves of the same week and keeps a different week', () {
      final first = _week(
        start: DateTime(2026, 9, 7),
        acceptRate: 80,
        cancelRate: 4,
        accepted: 80,
        rejected: 20,
        completed: 96,
        canceled: 4,
        tier: 'tier1',
        target: 80,
      );
      final second = _week(
        start: DateTime(2026, 9, 7, 4),
        acceptRate: 40,
        cancelRate: 10,
        accepted: 10,
        rejected: 15,
        completed: 9,
        canceled: 1,
        tier: 'tier2',
        target: 70,
      );
      final other = _week(
        start: DateTime(2026, 9, 14),
        accepted: 5,
        rejected: 1,
      );

      final collapsed = collapseWeeklyArchive([
        first.encode(),
        other.encode(),
        second.encode(),
      ]);
      expect(collapsed, hasLength(2));

      final merged = WeeklyArchiveEntry.parse(collapsed.last);
      expect(merged.weekStart?.day, 7);
      expect(merged.acceptedCount, 90);
      expect(merged.rejectedCount, 35);
      expect(merged.completedTrips, 105);
      expect(merged.canceledTrips, 5);
      expect(merged.acceptRate, closeTo(90 / 125 * 100, 0.0001));
      expect(merged.cancelRate, closeTo(5 / 110 * 100, 0.0001));
      expect(merged.goalTier, 'tier2');
      expect(merged.targetAcceptRate, 70);

      final kept = WeeklyArchiveEntry.parse(collapsed.first);
      expect(kept.weekStart?.day, 14);
      expect(kept.acceptedCount, 5);
    });

    test('keeps one copy of an identical week and does not rewrite it', () {
      final line = _week(
        accepted: 10,
        rejected: 2,
        completed: 9,
        canceled: 1,
      ).encode();
      expect(collapseWeeklyArchive([line, line]), [line]);
      expect(collapseWeeklyArchive([line]), [line]);
    });

    test(
      'collapses a legacy line into the structured week with the same range',
      () {
        S.setLang(AppLang.tr);
        const legacy = '7-13 Eyl: %80.00 Kabul | %4.00 İptal';
        final structured = _week(
          start: DateTime(2026, 9, 7),
          end: DateTime(2026, 9, 13),
          acceptRate: 75,
          accepted: 30,
          rejected: 10,
          completed: 28,
          canceled: 1,
          tier: 'tier1',
          target: 80,
        );
        final collapsed = collapseWeeklyArchive([legacy, structured.encode()]);
        expect(collapsed, hasLength(1));
        final parsed = WeeklyArchiveEntry.parse(collapsed.single);
        expect(parsed.isLegacy, isFalse);
        expect(parsed.acceptedCount, 30);
        expect(parsed.completedTrips, 28);
        expect(parsed.goalTier, 'tier1');
      },
    );

    test('does not merge the same calendar days from different years', () {
      final y2025 = _week(
        start: DateTime(2025, 9, 7),
        end: DateTime(2025, 9, 13),
      );
      final y2026 = _week(
        start: DateTime(2026, 9, 7),
        end: DateTime(2026, 9, 13),
      );
      expect(
        collapseWeeklyArchive([y2025.encode(), y2026.encode()]),
        hasLength(2),
      );
    });

    test('localizes the weekly breakdown labels', () {
      S.setLang(AppLang.tr);
      expect(
        S.archiveWeekSummary(102, 106, 26),
        'Yolculuk: 102 • Kabul: 106 • Red: 26',
      );
      expect(S.archiveCompletedTrips, 'Tamamlanan Yolculuk');
      expect(S.archiveCancelledTrips, 'İptal Edilen Yolculuk');
      expect(S.archiveAcceptedRequests, 'Kabul Edilen İstek');
      expect(S.archiveRejectedRequests, 'Reddedilen İstek');
      expect(S.archiveTotalRequests, 'Toplam İstek');
      expect(S.archiveWeeklyGoal, 'Haftalık Hedef');
      expect(S.archiveGoalMet, 'Hedef Tuttu');
      expect(S.archiveGoalMissed, 'Hedef Tutmadı');
      expect(S.archiveGoalLine('%80', true), '%80 • Hedef Tuttu');

      S.setLang(AppLang.en);
      expect(
        S.archiveWeekSummary(102, 106, 26),
        'Trips: 102 • Accept: 106 • Reject: 26',
      );
      expect(S.archiveCompletedTrips, 'Completed Trips');
      expect(S.archiveCancelledTrips, 'Cancelled Trips');
      expect(S.archiveGoalMet, 'Goal Met');
      expect(S.archiveGoalMissed, 'Goal Missed');
      expect(S.archiveGoalLine('80%', false), '80% • Goal Missed');

      S.setLang(AppLang.pl);
      expect(
        S.archiveWeekSummary(102, 106, 26),
        'Przejazdy: 102 • Akceptacja: 106 • Odrzucenie: 26',
      );
      expect(S.archiveCompletedTrips, 'Ukończone przejazdy');
      expect(S.archiveCancelledTrips, 'Anulowane przejazdy');
      expect(S.archiveWeeklyGoal, 'Cel tygodniowy');
      expect(S.archiveGoalMet, 'Cel osiągnięty');
      expect(S.archiveGoalMissed, 'Cel nieosiągnięty');
    });
  });
}

WeeklyArchiveEntry _week({
  DateTime? start,
  DateTime? end,
  double acceptRate = 80,
  double cancelRate = 2,
  int accepted = 0,
  int rejected = 0,
  int completed = 0,
  int canceled = 0,
  String? tier,
  double? target,
  double? maxCancel,
}) {
  return WeeklyArchiveEntry(
    weekStart: start ?? DateTime(2026, 9, 7),
    weekEnd: end ?? DateTime(2026, 9, 13),
    acceptRate: acceptRate,
    cancelRate: cancelRate,
    acceptedCount: accepted,
    rejectedCount: rejected,
    completedTrips: completed,
    canceledTrips: canceled,
    canceledTripsStored: true,
    goalTier: tier,
    targetAcceptRate: target,
    targetAcceptRateStored: tier != null,
    maxCancelRate: maxCancel ?? (tier != null ? kWeeklyCancelCeiling : null),
  );
}
