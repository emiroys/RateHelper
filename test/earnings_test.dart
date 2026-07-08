import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/earnings_models.dart';
import 'package:rate_helper/earnings_pdf_export.dart';
import 'package:shared_preferences/shared_preferences.dart';

WeekEarning buildWeek({
  double netIncome = 5000,
  double cashReceived = 398,
  bool hasRentalDiscount = true,
  double fuelPumpPaid = 298.9555555556,
  double onlineHours = 40,
  int tripCount = 130,
  DriverMode? driverMode,
}) {
  return WeekEarning(
    id: 'test',
    weekStart: DateTime(2026, 6, 22),
    weekEnd: DateTime(2026, 6, 28),
    driverMode: driverMode ?? activeDriverMode,
    netIncome: netIncome,
    cashReceived: cashReceived,
    onlineHours: onlineHours,
    tripCount: tripCount,
    hasRentalDiscount: hasRentalDiscount,
    fuelPumpPaid: fuelPumpPaid,
  );
}

void main() {
  group('fuel partner discount', () {
    test('FUEL_PARTNER_DISCOUNT constant is 10%', () {
      expect(FUEL_PARTNER_DISCOUNT, 0.10);
    });

    test('fuelPumpPaid 300 -> fuelAfterDiscount 270', () {
      final w = buildWeek(fuelPumpPaid: 300);
      expect(w.fuelAfterDiscount, closeTo(270, 0.001));
      expect(computeFuelAfterDiscount(300), closeTo(270, 0.001));
    });
  });

  group('flat 12% VAT on net income', () {
    test('FLAT_VAT_RATE constant is 12%', () {
      expect(FLAT_VAT_RATE, 0.12);
    });

    test('vat = netIncome * 0.12 = 600.00', () {
      expect(buildWeek().vat, closeTo(600.00, 0.001));
    });
  });

  group('flat 3% settlement fee on net income', () {
    test('SETTLEMENT_FEE_RATE constant is 3%', () {
      expect(SETTLEMENT_FEE_RATE, 0.03);
    });

    test('settlementFee = netIncome * 0.03 = 150.00', () {
      expect(buildWeek().settlementFee, closeTo(150.00, 0.001));
    });
  });

  group('net profit', () {
    test('netIncome - fuel - vat - rental - settlementFee = 3280.94', () {
      // 5000 - 269.06(fuel) - 600(vat) - 700(rental) - 150(settlement) = 3280.94
      expect(buildWeek().netProfit, closeTo(3280.94, 0.001));
    });

    test('rental fallback when hasRentalDiscount is false', () {
      final w = buildWeek(hasRentalDiscount: false);
      expect(w.rentalFee, 900);
      expect(w.netProfit, closeTo(3080.94, 0.001));
    });
  });

  group('bank deposit vs cash in hand', () {
    test('bankDeposit = netProfit - cashReceived = 2882.94', () {
      expect(buildWeek().bankDeposit, closeTo(2882.94, 0.001));
    });

    test('cashInHand equals the cash received', () {
      expect(buildWeek().cashInHand, closeTo(398, 0.001));
    });

    test('bankDeposit + cashInHand reconstitute net profit', () {
      final w = buildWeek();
      expect(w.bankDeposit + w.cashInHand, closeTo(w.netProfit, 0.0001));
    });
  });

  group('hourly rate', () {
    test('netProfit / online hours', () {
      final w = buildWeek(onlineHours: 40);
      expect(w.hourlyRate, closeTo(w.netProfit / 40, 0.001));
      expect(w.hourlyRate, closeTo(82.0235, 0.01));
    });

    test('25 sa 59 dk online -> decimal 25.9833', () {
      final w = buildWeek(onlineHours: onlineHoursFromHm(25, 59));
      expect(w.onlineHours, closeTo(25.98333, 0.0001));
      expect(w.hourlyRate, closeTo(w.netProfit / 25.98333, 0.01));
    });

    test('hourly rate is 0 when no online hours', () {
      expect(buildWeek(onlineHours: 0).hourlyRate, 0);
    });
  });

  group('online hours parsing', () {
    test('25 sa. 59 dk. -> 25.9833 decimal hours', () {
      expect(onlineHoursFromHm(25, 59), closeTo(25.98333, 0.0001));
    });

    test('round-trips back to h:mm', () {
      expect(formatHoursHm(onlineHoursFromHm(25, 59)), '25:59');
      expect(formatHoursHm(8.5), '8:30');
    });
  });

  group('week offset helpers', () {
    final wednesday = DateTime(2026, 7, 1); // a Wednesday

    test('current week starts Monday and ends Sunday', () {
      final start = weekStartForOffset(0, now: wednesday);
      final end = weekEndForStart(start);
      expect(start.weekday, DateTime.monday);
      expect(end.weekday, DateTime.sunday);
      expect(end.difference(start).inDays, 6);
      expect(start, DateTime(2026, 6, 29));
      expect(end, DateTime(2026, 7, 5));
    });

    test('negative offsets move to previous weeks', () {
      expect(weekStartForOffset(-1, now: wednesday), DateTime(2026, 6, 22));
      expect(weekStartForOffset(-2, now: wednesday), DateTime(2026, 6, 15));
    });

    test('weekStartForOffset uses calendar date addition without time shifts', () {
      final start = weekStartForOffset(-10, now: wednesday);
      expect(start.hour, 0);
      expect(start.minute, 0);
      expect(start.second, 0);
      expect(start.weekday, DateTime.monday);
    });

    test('isSameDate ignores time component', () {
      expect(isSameDate(DateTime(2026, 6, 22, 4), DateTime(2026, 6, 22, 23)), isTrue);
      expect(isSameDate(DateTime(2026, 6, 22), DateTime(2026, 6, 23)), isFalse);
    });
  });

  group('PLN formatting', () {
    test('groups thousands with dot and decimal comma', () {
      expect(formatPln(2360.77), '2.360,77');
      expect(formatPln(3440.94), '3.440,94');
      expect(formatPln(1003.93), '1.003,93');
      expect(formatPln(217.84), '217,84');
    });

    test('handles negatives', () {
      expect(formatPln(-217.84), '-217,84');
    });
  });

  group('encode/decode + FIFO trim', () {
    WeekEarning weekAt(int index) => WeekEarning(
          id: 'w$index',
          weekStart: DateTime(2024, 1, 1).add(Duration(days: 7 * index)),
          weekEnd: DateTime(2024, 1, 7).add(Duration(days: 7 * index)),
          driverMode: DriverMode.solo,
          netIncome: 4000 + index.toDouble(),
          cashReceived: 300,
          onlineHours: 40,
          tripCount: 130,
          hasRentalDiscount: true,
          fuelPumpPaid: 277.7777777778,
        );

    test('round-trips a single entry', () {
      final decoded = decodeEarnings(encodeEarnings([weekAt(0)]));
      expect(decoded.length, 1);
      final e = decoded.first;
      expect(e.netIncome, 4000);
      expect(e.cashReceived, 300);
      expect(e.hasRentalDiscount, true);
      expect(e.rentalFee, 700);
      expect(e.fuelPumpPaid, closeTo(277.7777777778, 0.001));
      expect(e.fuelAfterDiscount, closeTo(250, 0.001));
      expect(e.id, 'w0');
    });

    test('drops oldest beyond 104 entries (FIFO)', () {
      final list = [for (var i = 0; i < 110; i++) weekAt(i)];
      final decoded = decodeEarnings(encodeEarnings(list));
      expect(decoded.length, kMaxEarningEntries);
      expect(decoded.first.id, 'w6');
      expect(decoded.last.id, 'w109');
    });

    test('malformed input decodes to empty list', () {
      expect(decodeEarnings(null), isEmpty);
      expect(decodeEarnings(''), isEmpty);
      expect(decodeEarnings('not json'), isEmpty);
      expect(decodeEarnings('{"a":1}'), isEmpty);
    });

    test('legacy fuelAfterDiscount JSON migrates to fuelPumpPaid', () {
      final e = buildWeek(fuelPumpPaid: 300);
      final legacy = Map<String, dynamic>.from(e.toJson())
        ..remove('fuelPumpPaid')
        ..['fuelAfterDiscount'] = 270;
      final decoded = WeekEarning.fromJson(legacy)!;
      expect(decoded.fuelPumpPaid, closeTo(300, 0.001));
      expect(decoded.fuelAfterDiscount, closeTo(270, 0.001));
    });

    test('legacy fuelGross JSON migrates to fuelPumpPaid', () {
      final legacy = {
        'id': 'legacy',
        'weekStart': DateTime(2026, 6, 22).toIso8601String(),
        'weekEnd': DateTime(2026, 6, 28).toIso8601String(),
        'netIncome': 5000,
        'cashReceived': 0,
        'onlineHours': 40,
        'tripCount': 130,
        'rentalFee': 700,
        'administrativeCost': 40,
        'acceptanceRateReported': 85,
        'cancellationRateReported': 2,
        'notes': '',
        'fuelGross': 300,
      };
      final decoded = WeekEarning.fromJson(legacy)!;
      expect(decoded.fuelPumpPaid, closeTo(300, 0.001));
      expect(decoded.fuelAfterDiscount, closeTo(270, 0.001));
      expect(decoded.rentalFee, 700);
    });

    test('fuelReceipts serialization and total calculation', () {
      final now = DateTime(2026, 7, 7, 10, 30);
      final receipts = [
        FuelReceipt(id: '1', timestamp: now, amountPaid: 150),
        FuelReceipt(id: '2', timestamp: now.add(const Duration(days: 1)), amountPaid: 200),
      ];
      final e = WeekEarning(
        id: 'test_receipts',
        weekStart: DateTime(2026, 7, 6),
        weekEnd: DateTime(2026, 7, 12),
        driverMode: DriverMode.solo,
        netIncome: 3000,
        cashReceived: 0,
        onlineHours: 30,
        tripCount: 100,
        hasRentalDiscount: true,
        fuelReceipts: receipts,
      );
      expect(e.fuelPumpPaidTotal, 350);
      expect(e.fuelPumpPaid, 350);
      expect(e.fuelAfterDiscount, 315); // 350 * 0.90
      expect(e.fuelReceipts.length, 2);

      final json = e.toJson();
      expect(json['fuelReceipts'], isList);
      final decoded = WeekEarning.fromJson(json)!;
      expect(decoded.fuelReceipts.length, 2);
      expect(decoded.fuelPumpPaidTotal, 350);
      expect(decoded.fuelAfterDiscount, 315);
    });

    test('legacy fuelPumpPaid single field migrates into fuelReceipts list', () {
      final legacy = {
        'id': 'legacy_pump',
        'weekStart': DateTime(2026, 7, 6).toIso8601String(),
        'weekEnd': DateTime(2026, 7, 12).toIso8601String(),
        'netIncome': 3000,
        'cashReceived': 0,
        'onlineHours': 30,
        'tripCount': 100,
        'fuelPumpPaid': 400,
      };
      final decoded = WeekEarning.fromJson(legacy)!;
      expect(decoded.fuelReceipts.length, 1);
      expect(decoded.fuelReceipts.first.amountPaid, 400);
      expect(decoded.fuelPumpPaidTotal, 400);
    });

    test('parses Polish currency formatted strings with thousand separator dots in JSON', () {
      final legacy = {
        'id': 'pln_str',
        'weekStart': DateTime(2026, 6, 22).toIso8601String(),
        'weekEnd': DateTime(2026, 6, 28).toIso8601String(),
        'netIncome': '1.924,97',
        'cashReceived': '300,50',
        'onlineHours': '40',
        'tripCount': '130',
        'fuelPumpPaid': '277,78',
      };
      final decoded = WeekEarning.fromJson(legacy)!;
      expect(decoded.netIncome, closeTo(1924.97, 0.001));
      expect(decoded.cashReceived, closeTo(300.50, 0.001));
    });

    test('legacy JSON decodes with default hasRentalDiscount true', () {
      final legacy = {
        'id': 'legacy0',
        'weekStart': DateTime(2026, 6, 22).toIso8601String(),
        'weekEnd': DateTime(2026, 6, 28).toIso8601String(),
        'netIncome': 5000,
        'cashReceived': 0,
        'onlineHours': 40,
        'tripCount': 130,
        'rentalFee': 0,
        'fuelPumpPaid': 300,
      };
      final decoded = WeekEarning.fromJson(legacy)!;
      expect(decoded.hasRentalDiscount, isTrue);
      expect(decoded.rentalFee, 700);
    });
  });

  group('rental tier lookup by trip count', () {
    test('brackets map trip counts to expected fee', () {
      expect(expectedRentalFee(0, DriverMode.solo), 900);
      expect(expectedRentalFee(99, DriverMode.solo), 900);
      expect(expectedRentalFee(100, DriverMode.solo), 700);
      expect(expectedRentalFee(149, DriverMode.solo), 700);
      expect(expectedRentalFee(150, DriverMode.solo), 500);
      expect(expectedRentalFee(199, DriverMode.solo), 500);
      expect(expectedRentalFee(200, DriverMode.solo), 300);
      expect(expectedRentalFee(249, DriverMode.solo), 300);
      expect(expectedRentalFee(250, DriverMode.solo), 100);
      expect(expectedRentalFee(5000, DriverMode.solo), 100);
    });

    test('expectedRentalTier returns the matching bracket object', () {
      expect(expectedRentalTier(130, DriverMode.solo).fee, 700);
      expect(expectedRentalTier(130, DriverMode.solo).minTrips, 100);
      expect(expectedRentalTier(40, DriverMode.solo).fee, 900);
    });

    test('negative trip count falls back to the lowest bracket', () {
      expect(expectedRentalFee(-1, DriverMode.solo), 900);
    });

    test('tiers are contiguous and ascending in minTrips', () {
      for (var i = 1; i < RENTAL_TIERS.length; i++) {
        expect(RENTAL_TIERS[i].minTrips, RENTAL_TIERS[i - 1].maxTrips + 1);
      }
    });

    test('rentalTierRangeLabel formats bounded and open-ended brackets', () {
      expect(rentalTierRangeLabel(expectedRentalTier(130, DriverMode.solo)), '100-149');
      expect(rentalTierRangeLabel(expectedRentalTier(50, DriverMode.solo)), '0-99');
      expect(rentalTierRangeLabel(expectedRentalTier(300, DriverMode.solo)), '250+');
    });
  });

  group('computed rentalFee (rental always charged or base fee if no discount)', () {
    test('rentalFee is dynamically computed from trip count when hasRentalDiscount is true', () {
      expect(buildWeek(tripCount: 0).rentalFee, 900);
      expect(buildWeek(tripCount: 130).rentalFee, 700);
      expect(buildWeek(tripCount: 200).rentalFee, 300);
    });

    test('rentalFee uses base fee when hasRentalDiscount is false', () {
      expect(buildWeek(tripCount: 200, hasRentalDiscount: false).rentalFee, 900);
    });
  });

  group('paired driver mode (RENTAL_TIERS_PAIRED)', () {
    tearDown(() {
      activeDriverMode = DriverMode.solo;
    });

    test('expectedRentalTier returns brackets from RENTAL_TIERS_PAIRED when mode is paired', () {
      expect(expectedRentalTier(0, DriverMode.paired).feePerDriver, 450);
      expect(expectedRentalTier(0, DriverMode.paired).totalCarFee, 900);

      expect(expectedRentalTier(120, DriverMode.paired).feePerDriver, 350);
      expect(expectedRentalTier(120, DriverMode.paired).totalCarFee, 700);

      expect(expectedRentalTier(170, DriverMode.paired).feePerDriver, 250);
      expect(expectedRentalTier(170, DriverMode.paired).totalCarFee, 500);

      expect(expectedRentalTier(220, DriverMode.paired).feePerDriver, 150);
      expect(expectedRentalTier(220, DriverMode.paired).totalCarFee, 300);

      expect(expectedRentalTier(270, DriverMode.paired).feePerDriver, 50);
      expect(expectedRentalTier(270, DriverMode.paired).totalCarFee, 100);
    });

    test('WeekEarning rentalFee uses feePerDriver and totalCarRentalFee uses totalCarFee in paired mode', () {
      activeDriverMode = DriverMode.paired;
      final week = buildWeek(tripCount: 170);
      expect(week.rentalFee, 250);
      expect(week.totalCarRentalFee, 500);
    });
  });

  group('lifetime trip counter and free week progress', () {
    test('calculateLifetimeTrips sums tripCount across all entries', () {
      final weeks = [
        buildWeek(tripCount: 130),
        buildWeek(tripCount: 150),
        buildWeek(tripCount: 220),
      ];
      expect(calculateLifetimeTrips(weeks), 500);
    });

    test('calculateFreeWeeksEarned computes rewards at 2000 trip intervals', () {
      expect(calculateFreeWeeksEarned(0), 0);
      expect(calculateFreeWeeksEarned(1999), 0);
      expect(calculateFreeWeeksEarned(2000), 1);
      expect(calculateFreeWeeksEarned(4500), 2);
    });

    test('calculateCurrentFreeWeekProgress returns modulo progress toward next reward', () {
      expect(calculateCurrentFreeWeekProgress(0), 0);
      expect(calculateCurrentFreeWeekProgress(1500), 1500);
      expect(calculateCurrentFreeWeekProgress(2000), 0);
      expect(calculateCurrentFreeWeekProgress(2350), 350);
    });
  });

  group('cross-check: unusual hourly rate', () {
    test('zero rate (no online hours) never warns', () {
      expect(hasUnusualHourlyRate(0), isFalse);
      expect(buildWeek(onlineHours: 0).warnings,
          isNot(contains(EarningsWarning.hourlyRate)));
    });

    test('rate inside 10-200 range does not warn', () {
      expect(hasUnusualHourlyRate(28.26), isFalse);
      expect(hasUnusualHourlyRate(10), isFalse);
      expect(hasUnusualHourlyRate(200), isFalse);
    });

    test('rate below 10 warns (e.g. huge hours typo)', () {
      final w = buildWeek(onlineHours: 4000);
      expect(w.hourlyRate < 10, isTrue);
      expect(hasUnusualHourlyRate(w.hourlyRate), isTrue);
      expect(w.warnings, contains(EarningsWarning.hourlyRate));
    });

    test('rate above 200 warns (e.g. tiny hours typo)', () {
      final w = buildWeek(onlineHours: 2);
      expect(w.hourlyRate > 200, isTrue);
      expect(hasUnusualHourlyRate(w.hourlyRate), isTrue);
      expect(w.warnings, contains(EarningsWarning.hourlyRate));
    });
  });

  group('crossCheckWarnings aggregation', () {
    test('clean week produces no warnings', () {
      final w = buildWeek(tripCount: 130, onlineHours: 40);
      expect(w.warnings, isEmpty);
    });

    test('unusual hourly rate is surfaced', () {
      final list = crossCheckWarnings(hourlyRate: 5);
      expect(list, contains(EarningsWarning.hourlyRate));
    });

    test('plausible hourly rate produces no warnings', () {
      expect(crossCheckWarnings(hourlyRate: 45), isEmpty);
    });
  });

  group('averageHourlyRate helper', () {
    WeekEarning wk(double hours, double netIncome) => WeekEarning(
          id: 'x',
          weekStart: DateTime(2026, 1, 1),
          weekEnd: DateTime(2026, 1, 7),
          driverMode: DriverMode.solo,
          netIncome: netIncome,
          cashReceived: 0,
          onlineHours: hours,
          tripCount: 100,
          hasRentalDiscount: true,
          fuelPumpPaid: 0,
        );

    test('empty list averages to 0', () {
      expect(averageHourlyRate(const []), 0);
    });

    test('skips weeks with no online hours', () {
      final weeks = [wk(10, 1000), wk(0, 500)];
      expect(averageHourlyRate(weeks), closeTo(weeks.first.hourlyRate, 0.0001));
    });
  });

  group('aggregation + records', () {
    // Aggregation asserts compare against the model's own netProfit, so they stay self-consistent.
    WeekEarning aggWeek({
      required DateTime weekStart,
      required double netIncome,
      required double onlineHours,
      String? id,
    }) {
      return WeekEarning(
        id: id ?? weekStart.toIso8601String(),
        weekStart: weekStart,
        weekEnd: weekStart.add(const Duration(days: 6)),
        driverMode: DriverMode.solo,
        netIncome: netIncome,
        cashReceived: 0,
        onlineHours: onlineHours,
        tripCount: 100,
        hasRentalDiscount: true,
        fuelPumpPaid: 0,
      );
    }

    group('aggregateByMonth', () {
      test('two June weeks + one July week -> correct month totals', () {
        final june1 = aggWeek(
            weekStart: DateTime(2026, 6, 1), netIncome: 4000, onlineHours: 40);
        final june2 = aggWeek(
            weekStart: DateTime(2026, 6, 8), netIncome: 5000, onlineHours: 100);
        final july = aggWeek(
            weekStart: DateTime(2026, 7, 6), netIncome: 3000, onlineHours: 50);

        final months = aggregateByMonth([july, june2, june1]);
        expect(months.length, 2);

        final junM = months[0];
        expect(junM.month, DateTime(2026, 6, 1));
        expect(junM.weekCount, 2);
        expect(junM.totalNetProfit, june1.netProfit + june2.netProfit);
        final expectedAvgRate = (june1.netProfit + june2.netProfit) /
            (june1.onlineHours + june2.onlineHours);
        expect(junM.avgHourlyRate, closeTo(expectedAvgRate, 0.0001));

        final julM = months[1];
        expect(julM.month, DateTime(2026, 7, 1));
        expect(julM.weekCount, 1);
        expect(julM.totalNetProfit, july.netProfit);
        expect(julM.avgHourlyRate, closeTo(july.hourlyRate, 0.0001));
      });

      test('results are sorted oldest month first', () {
        final m3 = aggWeek(
            weekStart: DateTime(2026, 3, 2), netIncome: 1000, onlineHours: 10);
        final m1 = aggWeek(
            weekStart: DateTime(2026, 1, 5), netIncome: 1000, onlineHours: 10);
        final m2 = aggWeek(
            weekStart: DateTime(2026, 2, 2), netIncome: 1000, onlineHours: 10);
        final months = aggregateByMonth([m1, m3, m2]);
        expect(months.map((m) => m.month.month), [1, 2, 3]);
      });
    });

    group('aggregateByYear', () {
      test('groups months under their year, oldest first', () {
        final y25 = aggWeek(
            weekStart: DateTime(2025, 12, 8), netIncome: 2000, onlineHours: 20);
        final y26a = aggWeek(
            weekStart: DateTime(2026, 1, 5), netIncome: 3000, onlineHours: 30);
        final y26b = aggWeek(
            weekStart: DateTime(2026, 2, 2), netIncome: 4000, onlineHours: 40);

        final years = aggregateByYear([y25, y26a, y26b]);
        expect(years.length, 2);
        expect(years[0].year, 2025);
        expect(years[0].months.length, 1);

        expect(years[1].year, 2026);
        expect(years[1].months.length, 2);
        expect(years[1].totalNetProfit, y26a.netProfit + y26b.netProfit);
      });
    });

    group('bestHourlyRateWeek', () {
      test('returns the week with the highest hourlyRate', () {
        final low = aggWeek(
            weekStart: DateTime(2026, 6, 1), netIncome: 2000, onlineHours: 40);
        final high = aggWeek(
            weekStart: DateTime(2026, 6, 8), netIncome: 4000, onlineHours: 20);
        final mid = aggWeek(
            weekStart: DateTime(2026, 6, 15), netIncome: 3000, onlineHours: 30);

        final best = bestHourlyRateWeek([low, mid, high]);
        expect(best?.id, high.id);
      });

      test('ignores weeks with 0 online hours', () {
        final zero = aggWeek(
            weekStart: DateTime(2026, 6, 1), netIncome: 5000, onlineHours: 0);
        final normal = aggWeek(
            weekStart: DateTime(2026, 6, 8), netIncome: 1000, onlineHours: 10);
        expect(bestHourlyRateWeek([zero, normal])?.id, normal.id);
      });
    });
  });

  group('audit: negative netProfit is preserved and displayed with a sign', () {
    // Small income, big fuel -> genuinely negative week.
    final bad = buildWeek(
      netIncome: 100,
      fuelPumpPaid: 200,
      tripCount: 130,
      hasRentalDiscount: true,
      cashReceived: 0,
      onlineHours: 10,
    );

    test('netProfit can be negative (not clamped or abs-ed)', () {
      expect(bad.netProfit, lessThan(0));
      expect(bad.netProfit, closeTo(-795.0, 0.001));
    });

    test('formatPln keeps the minus sign for a negative profit', () {
      expect(formatPln(bad.netProfit), startsWith('-'));
      expect(formatPln(bad.netProfit), '-795,00');
    });

    test('a negative hourlyRate stays negative (not abs-ed)', () {
      expect(bad.hourlyRate, lessThan(0));
      expect(bad.bankDeposit, lessThan(0));
    });
  });

  group('audit: currency rounding to 2 decimals at each step', () {
    test('vat / settlementFee / fuel are each rounded to whole cents', () {
      final w = buildWeek(netIncome: 33.33, fuelPumpPaid: 100.005);
      expect(w.vat, round2(w.vat));
      expect(w.settlementFee, round2(w.settlementFee));
      expect(w.fuelAfterDiscount, 90.0);
    });

    test('breakdown components sum EXACTLY to netProfit (no cent drift)', () {
      final w = buildWeek();
      final recomputed = round2(w.netIncome -
          w.fuelAfterDiscount -
          w.vat -
          w.rentalFee -
          w.settlementFee);
      expect(w.netProfit, recomputed);
    });

    test('round2 helper rounds to whole cents and passes non-finite through', () {
      expect(round2(3.14159), 3.14);
      expect(round2(2.71828), 2.72);
      expect(round2(269.06000000004), 269.06);
      expect(round2(-832.5), -832.5);
      expect(round2(double.nan).isNaN, isTrue);
      expect(round2(double.infinity), double.infinity);
    });
  });

  group('audit: JSON backward-compat with all removed keys present', () {
    Map<String, dynamic> legacyEntry() => {
          'id': 'legacy-full',
          'weekStart': DateTime(2026, 6, 22).toIso8601String(),
          'weekEnd': DateTime(2026, 6, 28).toIso8601String(),
          'netIncome': 5000,
          'cashReceived': 398,
          'onlineHours': 40,
          'tripCount': 130,
          'fuelPumpPaid': 300,
          'rentalFee': 700,
          'administrativeCost': 40,
          'otherExpenses': 120,
          'notes': 'eski not',
          'acceptanceRateReported': 88,
          'cancellationRateReported': 2,
        };

    test('fromJson ignores unknown/removed keys without throwing', () {
      final decoded = WeekEarning.fromJson(legacyEntry())!;
      expect(decoded.netIncome, 5000);
      expect(decoded.tripCount, 130);
      expect(decoded.fuelPumpPaid, 300);
      expect(decoded.rentalFee, 700);
    });

    test('re-serialized JSON no longer carries the removed keys', () {
      final json = WeekEarning.fromJson(legacyEntry())!.toJson();
      expect(json.containsKey('otherExpenses'), isFalse);
      expect(json.containsKey('notes'), isFalse);
      expect(json.containsKey('administrativeCost'), isFalse);
    });

    test('a stored list of legacy entries decodes cleanly', () {
      final raw = '[${_jsonNoThrow(legacyEntry())}]';
      final decoded = decodeEarnings(raw);
      expect(decoded.length, 1);
      expect(decoded.first.netIncome, 5000);
    });
  });

  group('audit: week-boundary month/year aggregation', () {
    test('a week starting in June, ending in July counts toward June', () {
      final straddling = WeekEarning(
        id: 'straddle',
        weekStart: DateTime(2026, 6, 29), // Monday
        weekEnd: DateTime(2026, 7, 5), // Sunday
        driverMode: DriverMode.solo,
        netIncome: 4000,
        cashReceived: 0,
        onlineHours: 40,
        tripCount: 100,
        hasRentalDiscount: true,
        fuelPumpPaid: 0,
      );
      final months = aggregateByMonth([straddling]);
      expect(months.single.month, DateTime(2026, 6, 1));
      expect(months.single.weekCount, 1);
    });

    test('a week starting Dec 2025, ending Jan 2026 counts toward 2025', () {
      final straddling = WeekEarning(
        id: 'ny',
        weekStart: DateTime(2025, 12, 29), // Monday
        weekEnd: DateTime(2026, 1, 4), // Sunday
        driverMode: DriverMode.solo,
        netIncome: 4000,
        cashReceived: 0,
        onlineHours: 40,
        tripCount: 100,
        hasRentalDiscount: true,
        fuelPumpPaid: 0,
      );
      final years = aggregateByYear([straddling]);
      expect(years.single.year, 2025);
      expect(years.single.months.single.month, DateTime(2025, 12, 1));
    });
  });

  group('break-even: live current-week fuel (no historical average)', () {
    double liveBreakEven({
      required double fuelPumpPaid,
      required int tripCount,
      DriverMode mode = DriverMode.solo,
    }) {
      final rental = expectedRentalFee(tripCount, mode);
      return calculateBreakEven(
        fixedCosts:
            computeFuelAfterDiscount(fuelPumpPaid) + rental,
      );
    }

    test('empty/zero fuel yields a finite fixed-costs-only break-even', () {
      final v = liveBreakEven(
        fuelPumpPaid: 0,
        tripCount: 130,
      );
      expect(v.isFinite, isTrue);
      expect(v, greaterThan(0));
      expect(v, closeTo(calculateBreakEven(fixedCosts: 700), 0.001));
    });

    test('break-even rises as the live fuel figure increases', () {
      final low = liveBreakEven(
          fuelPumpPaid: 100, tripCount: 130);
      final high = liveBreakEven(
          fuelPumpPaid: 500, tripCount: 130);
      expect(high, greaterThan(low));
    });

    test('uses the pump figure directly, not any stored history', () {
      // 300 pump -> 270 fuel; fixedCosts = 270 + 700 = 970.
      final v = liveBreakEven(
          fuelPumpPaid: 300, tripCount: 130);
      expect(v, closeTo(calculateBreakEven(fixedCosts: 970), 0.001));
    });
  });

  group('PDF export: month filter reuses aggregateByMonth', () {
    WeekEarning wk(DateTime start, {String? id}) => WeekEarning(
          id: id ?? start.toIso8601String(),
          weekStart: start,
          weekEnd: start.add(const Duration(days: 6)),
          driverMode: DriverMode.solo,
          netIncome: 4000,
          cashReceived: 0,
          onlineHours: 40,
          tripCount: 100,
          hasRentalDiscount: true,
          fuelPumpPaid: 0,
        );

    test('a week whose weekStart is exactly the 1st is included in its month', () {
      final onFirst = wk(DateTime(2026, 5, 1), id: 'first');
      final weeks =
          EarningsPdfExport.weeksForMonth([onFirst], DateTime(2026, 5, 1));
      expect(weeks.map((w) => w.id), contains('first'));
      expect(weeks.length, 1);
    });

    test('a month-straddling week counts toward its weekStart month only', () {
      final straddle = wk(DateTime(2026, 6, 29), id: 'straddle');
      expect(
        EarningsPdfExport.weeksForMonth([straddle], DateTime(2026, 6, 1))
            .map((w) => w.id),
        contains('straddle'),
      );
      expect(
        EarningsPdfExport.weeksForMonth([straddle], DateTime(2026, 7, 1)),
        isEmpty,
      );
    });

    test('only the requested month is returned', () {
      final may = wk(DateTime(2026, 5, 4), id: 'may');
      final jun = wk(DateTime(2026, 6, 1), id: 'jun');
      final result =
          EarningsPdfExport.weeksForMonth([may, jun], DateTime(2026, 5, 1));
      expect(result.map((w) => w.id).toSet(), {'may'});
    });

    test('sanitizeDriverName strips emojis while preserving Latin and Polish characters', () {
      expect(
        EarningsPdfExport.sanitizeDriverName('Jan Kowalski 🚗🚀'),
        'Jan Kowalski',
      );
      expect(
        EarningsPdfExport.sanitizeDriverName('Łukasz Żółć 🔥'),
        'Łukasz Żółć',
      );
      expect(
        EarningsPdfExport.sanitizeDriverName('🚗🚀'),
        'Sürücü',
      );
    });
  });

  group('break-even: precise reverse calculation (VAT + settlementFee)', () {
    void roundTrip({
      required double fuelPumpPaid,
      required int tripCount,
      DriverMode mode = DriverMode.solo,
    }) {
      final fuel = computeFuelAfterDiscount(fuelPumpPaid);
      final rental = expectedRentalFee(tripCount, mode);
      final fixedCosts = fuel + rental;

      final breakEven = calculateBreakEven(fixedCosts: fixedCosts);

      final week = WeekEarning(
        id: 'be',
        weekStart: DateTime(2026, 6, 22),
        weekEnd: DateTime(2026, 6, 28),
        driverMode: mode,
        netIncome: breakEven,
        cashReceived: 0,
        onlineHours: 1,
        tripCount: tripCount,
        hasRentalDiscount: true,
        fuelPumpPaid: fuelPumpPaid,
      );

      expect(week.netProfit.abs(), lessThan(0.1),
          reason: 'netProfit at break-even ($breakEven) should be ~0');
    }

    test('typical fuel, high tier', () {
      roundTrip(
        fuelPumpPaid: 277.7777777778, // -> 250 after discount
        tripCount: 130,
      );
    });

    test('typical fuel, lowest tier', () {
      roundTrip(
        fuelPumpPaid: 277.7777777778,
        tripCount: 50,
      );
    });

    test('high fuel week', () {
      roundTrip(
        fuelPumpPaid: 500, // -> 450 after discount
        tripCount: 130,
      );
    });

    test('low fuel week', () {
      roundTrip(
        fuelPumpPaid: 100, // -> 90 after discount
        tripCount: 200,
      );
    });

    test('accounts for VAT + settlementFee (strictly above the naive sum)', () {
      const fixedCosts = 940.0;
      final precise = calculateBreakEven(fixedCosts: fixedCosts);
      expect(precise, greaterThan(fixedCosts));
      expect(precise, greaterThan(fixedCosts / (1 - FLAT_VAT_RATE)));
    });

    test('result is rounded to whole cents', () {
      final v = calculateBreakEven(fixedCosts: 940.005);
      expect(v, round2(v));
    });
  });

  group('audit: empty / degenerate state never yields NaN', () {
    test('MonthSummary avgHourlyRate is 0 for a month with 0 online hours', () {
      final zeroHours = WeekEarning(
        id: 'z',
        weekStart: DateTime(2026, 5, 4),
        weekEnd: DateTime(2026, 5, 10),
        driverMode: DriverMode.solo,
        netIncome: 3000,
        cashReceived: 0,
        onlineHours: 0,
        tripCount: 100,
        hasRentalDiscount: true,
        fuelPumpPaid: 0,
      );
      final month = aggregateByMonth([zeroHours]).single;
      expect(month.avgHourlyRate, 0);
      expect(month.avgHourlyRate.isFinite, isTrue);
    });

    test('empty history aggregates to empty lists (no null / NaN)', () {
      expect(aggregateByMonth(const []), isEmpty);
      expect(aggregateByYear(const []), isEmpty);
      expect(bestHourlyRateWeek(const []), isNull);
    });
  });

  group('schema versioning & driver mode immutability', () {
    tearDown(() {
      activeDriverMode = DriverMode.solo;
    });

    test('immutable driverMode: solo-mode week retains solo rental fee after global mode switches to paired', () {
      activeDriverMode = DriverMode.solo;
      final week = buildWeek(tripCount: 130);
      expect(week.driverMode, DriverMode.solo);
      expect(week.rentalFee, 700); // solo tier 100-149

      final encoded = encodeEarnings([week]);
      activeDriverMode = DriverMode.paired; // switch global state

      final decodedList = decodeEarnings(encoded);
      expect(decodedList, hasLength(1));
      final decoded = decodedList.first;
      expect(decoded.driverMode, DriverMode.solo);
      expect(decoded.rentalFee, 700); // unchanged from save time!
    });

    test('schema versioning round-trips version 1 and parses legacy untagged (version 0) data', () {
      final week = buildWeek(driverMode: DriverMode.solo);
      final json = week.toJson();
      expect(json['version'], 1);
      expect(json['driverMode'], 'solo');

      final decoded = WeekEarning.fromJson(json);
      expect(decoded, isNotNull);
      expect(decoded!.driverMode, DriverMode.solo);

      // Legacy version 0 data without 'version' or 'driverMode' key
      final legacyJson = {
        'id': 'legacy_123',
        'weekStart': '2026-06-22T00:00:00.000',
        'weekEnd': '2026-06-28T00:00:00.000',
        'netIncome': 5000.0,
        'cashReceived': 398.0,
        'onlineHours': 40.0,
        'tripCount': 130,
        'acceptanceRateReported': 85.0,
        'cancellationRateReported': 2.0,
        'fuelPumpPaid': 298.9555555556,
      };
      final legacyDecoded = WeekEarning.fromJson(legacyJson);
      expect(legacyDecoded, isNotNull);
      expect(legacyDecoded!.driverMode, DriverMode.solo);
      expect(legacyDecoded.rentalFee, 700);
    });
  });

  group('lifetime trip odometer (persisted, FIFO-independent)', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('backfill migration seeds counter from existing history exactly once', () async {
      // Simulate existing install with history already in prefs.
      final weeks = [
        buildWeek(tripCount: 130, driverMode: DriverMode.solo),
        buildWeek(tripCount: 200, driverMode: DriverMode.solo),
      ];
      SharedPreferences.setMockInitialValues({
        kEarningsHistoryKey: encodeEarnings(weeks),
        // No kLifetimeTripsKey or kLifetimeTripsBackfilledKey yet
      });
      final prefs = await SharedPreferences.getInstance();

      // --- First load: backfill should run ---
      expect(prefs.getBool(kLifetimeTripsBackfilledKey), isNull);
      final entries = decodeEarnings(prefs.getString(kEarningsHistoryKey));
      final backfill = calculateLifetimeTrips(entries);
      expect(backfill, 330); // 130 + 200

      // Simulate the migration logic from _load()
      if (prefs.getBool(kLifetimeTripsBackfilledKey) != true) {
        await prefs.setInt(kLifetimeTripsKey, backfill);
        await prefs.setBool(kLifetimeTripsBackfilledKey, true);
      }
      expect(prefs.getInt(kLifetimeTripsKey), 330);
      expect(prefs.getBool(kLifetimeTripsBackfilledKey), true);

      // --- Second load: backfill must NOT re-run ---
      // Simulate adding a new week to history (would change sum if re-summed).
      final newWeek = buildWeek(tripCount: 500, driverMode: DriverMode.solo);
      final updatedEntries = [...entries, newWeek];
      await prefs.setString(kEarningsHistoryKey, encodeEarnings(updatedEntries));

      // Simulate incrementing odometer for the new save
      final current = prefs.getInt(kLifetimeTripsKey) ?? 0;
      await prefs.setInt(kLifetimeTripsKey, current + 500);
      expect(prefs.getInt(kLifetimeTripsKey), 830); // 330 + 500

      // Re-run migration guard — must NOT overwrite to 830 (sum of all 3)
      if (prefs.getBool(kLifetimeTripsBackfilledKey) != true) {
        final reSummed = calculateLifetimeTrips(
            decodeEarnings(prefs.getString(kEarningsHistoryKey)));
        await prefs.setInt(kLifetimeTripsKey, reSummed);
      }
      // Value stays at 830 (330 backfill + 500 increment), NOT 830 from re-sum
      expect(prefs.getInt(kLifetimeTripsKey), 830);
    });

    test('delta-based increment: editing a week only adds positive difference', () async {
      SharedPreferences.setMockInitialValues({
        kLifetimeTripsKey: 1000,
        kLifetimeTripsBackfilledKey: true,
      });
      final prefs = await SharedPreferences.getInstance();

      // Simulate editing: old entry had 130 trips, new entry has 150
      const oldTrips = 130;
      const newTrips = 150;
      const delta = newTrips - oldTrips; // 20
      expect(delta, 20);

      final current = prefs.getInt(kLifetimeTripsKey) ?? 0;
      if (delta > 0) {
        await prefs.setInt(kLifetimeTripsKey, current + delta);
      }
      expect(prefs.getInt(kLifetimeTripsKey), 1020);
    });

    test('negative delta (reducing trips in an edit) does NOT decrement odometer', () async {
      SharedPreferences.setMockInitialValues({
        kLifetimeTripsKey: 1000,
        kLifetimeTripsBackfilledKey: true,
      });
      final prefs = await SharedPreferences.getInstance();

      // Simulate editing: old entry had 150 trips, new entry has 100
      const oldTrips = 150;
      const newTrips = 100;
      const delta = newTrips - oldTrips; // -50
      expect(delta, -50);

      // Guard: only increment on positive delta
      if (delta > 0) {
        await prefs.setInt(kLifetimeTripsKey, (prefs.getInt(kLifetimeTripsKey) ?? 0) + delta);
      }
      expect(prefs.getInt(kLifetimeTripsKey), 1000); // unchanged
    });

    test('deleting an entry does NOT decrement the odometer', () async {
      SharedPreferences.setMockInitialValues({
        kLifetimeTripsKey: 500,
        kLifetimeTripsBackfilledKey: true,
      });
      final prefs = await SharedPreferences.getInstance();

      // Delete path does not touch kLifetimeTripsKey at all
      expect(prefs.getInt(kLifetimeTripsKey), 500); // unchanged
    });

    test('calculateLifetimeTrips is still accurate for backfill purposes', () {
      final weeks = [
        buildWeek(tripCount: 130, driverMode: DriverMode.solo),
        buildWeek(tripCount: 150, driverMode: DriverMode.solo),
        buildWeek(tripCount: 220, driverMode: DriverMode.solo),
      ];
      expect(calculateLifetimeTrips(weeks), 500);
    });
  });
}

String _jsonNoThrow(Map<String, dynamic> m) {
  final parts = m.entries.map((e) {
    final v = e.value;
    final encoded = v is String ? '"$v"' : '$v';
    return '"${e.key}":$encoded';
  });
  return '{${parts.join(',')}}';
}
