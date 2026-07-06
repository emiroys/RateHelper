import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/earnings_models.dart';
import 'package:rate_helper/earnings_pdf_export.dart';

WeekEarning buildWeek({
  double netIncome = 5000,
  double cashReceived = 398,
  bool rentalDiscountEnabled = true,
  double fuelPumpPaid = 298.9555555556,
  double onlineHours = 40,
  int tripCount = 130,
}) {
  return WeekEarning(
    id: 'test',
    weekStart: DateTime(2026, 6, 22),
    weekEnd: DateTime(2026, 6, 28),
    netIncome: netIncome,
    cashReceived: cashReceived,
    onlineHours: onlineHours,
    tripCount: tripCount,
    rentalDiscountEnabled: rentalDiscountEnabled,
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

  group('flat 11.5% VAT on net income', () {
    test('FLAT_VAT_RATE constant is 11.5%', () {
      expect(FLAT_VAT_RATE, 0.115);
    });

    test('vat = netIncome * 0.115 = 575.00', () {
      // 5000 * 0.115
      expect(buildWeek().vat, closeTo(575.00, 0.001));
    });
  });

  group('commission from tier(netIncome)', () {
    test('turnover 5000 falls in the 3000+ bracket -> 0 PLN', () {
      expect(computeFromTier(5000), 0);
      expect(buildWeek().commission, 0);
    });

    test('brackets map turnover to base + percent continuously without gaps', () {
      expect(computeFromTier(0), 50);
      expect(computeFromTier(500), closeTo(55, 0.001));
      expect(computeFromTier(999), closeTo(59.99, 0.001));
      expect(computeFromTier(999.50), closeTo(59.995, 0.001));
      expect(computeFromTier(1000), 35);
      expect(computeFromTier(1999), closeTo(44.99, 0.001));
      expect(computeFromTier(1999.50), closeTo(44.995, 0.001));
      expect(computeFromTier(2000), 20);
      expect(computeFromTier(2999), closeTo(29.99, 0.001));
      expect(computeFromTier(2999.50), closeTo(29.995, 0.001));
      expect(computeFromTier(3000), 0);
      expect(computeFromTier(50000), 0);
    });
  });

  group('administrative cost', () {
    test('ADMINISTRATIVE_COST constant is fixed at 40 PLN', () {
      expect(ADMINISTRATIVE_COST, 40.0);
    });
  });

  group('net profit', () {
    test('netIncome - admin - fuel - vat - rental - commission = 3465.94', () {
      // 5000 - 40 - 269.06 - 575 - 650 - 0
      expect(buildWeek().netProfit, closeTo(3465.94, 0.001));
    });

    test('rental (flat 850) is always charged even with no discount', () {
      // 5000 - 40 - 269.06 - 575 - 850(flat rental) - 0
      final w = buildWeek(rentalDiscountEnabled: false);
      expect(w.rentalFee, 850);
      expect(w.netProfit, closeTo(3265.94, 0.001));
    });
  });

  group('bank deposit vs cash in hand', () {
    test('bankDeposit = netProfit - cashReceived = 3067.94', () {
      // 3465.94 - 398
      expect(buildWeek().bankDeposit, closeTo(3067.94, 0.001));
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
      expect(w.hourlyRate, closeTo(86.6485, 0.01));
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
          netIncome: 4000 + index.toDouble(),
          cashReceived: 300,
          onlineHours: 40,
          tripCount: 130,
          rentalDiscountEnabled: true,
          fuelPumpPaid: 277.7777777778,
        );

    test('round-trips a single entry', () {
      final decoded = decodeEarnings(encodeEarnings([weekAt(0)]));
      expect(decoded.length, 1);
      final e = decoded.first;
      expect(e.netIncome, 4000);
      expect(e.cashReceived, 300);
      expect(e.rentalDiscountEnabled, isTrue);
      // 130 trips -> 650 PLN tier, computed live.
      expect(e.rentalFee, 650);
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
        'rentalFee': 650,
        'administrativeCost': 40,
        'acceptanceRateReported': 85,
        'cancellationRateReported': 2,
        'otherExpenses': 0,
        'notes': '',
        'fuelGross': 300,
      };
      final decoded = WeekEarning.fromJson(legacy)!;
      expect(decoded.fuelPumpPaid, closeTo(300, 0.001));
      expect(decoded.fuelAfterDiscount, closeTo(270, 0.001));
      // Legacy rentalFee > 0 infers the discount was enabled.
      expect(decoded.rentalDiscountEnabled, isTrue);
      expect(decoded.rentalFee, 650);
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

    test('legacy rentalFee 0 infers rental discount disabled', () {
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
        'acceptanceRateReported': 85,
        'cancellationRateReported': 2,
      };
      final decoded = WeekEarning.fromJson(legacy)!;
      expect(decoded.rentalDiscountEnabled, isFalse);
      // Discount off -> flat 850 base rate is charged.
      expect(decoded.rentalFee, 850);
    });
  });

  group('rental tier lookup (trip count only, no accept rate)', () {
    test('brackets map trip counts to expected fee', () {
      expect(expectedRentalFee(0), 850);
      expect(expectedRentalFee(120), 850);
      expect(expectedRentalFee(100), 850);
      expect(expectedRentalFee(121), 650);
      expect(expectedRentalFee(130), 650);
      expect(expectedRentalFee(160), 650);
      expect(expectedRentalFee(161), 450);
      expect(expectedRentalFee(199), 450);
      expect(expectedRentalFee(200), 250);
      expect(expectedRentalFee(5000), 250);
    });

    test('expectedRentalTier returns the matching bracket object', () {
      expect(expectedRentalTier(130).fee, 650);
      expect(expectedRentalTier(130).minTrips, 121);
      expect(expectedRentalTier(40).fee, 850);
    });

    test('negative trip count falls back to the lowest bracket', () {
      // Callers clamp trips to >= 0; a stray negative must not crash or return
      // null — it maps to the 0-120 (850 PLN) tier.
      expect(expectedRentalFee(-1), 850);
      expect(expectedRentalTier(-5).fee, 850);
    });

    test('tiers are contiguous and ascending', () {
      for (var i = 1; i < RENTAL_TIERS.length; i++) {
        expect(RENTAL_TIERS[i].minTrips, RENTAL_TIERS[i - 1].maxTrips + 1);
      }
    });

    test('rentalTierRangeLabel formats bounded and open-ended brackets', () {
      expect(rentalTierRangeLabel(expectedRentalTier(130)), '121-160');
      expect(rentalTierRangeLabel(expectedRentalTier(100)), '0-120');
      expect(rentalTierRangeLabel(expectedRentalTier(500)), '200+');
    });
  });

  group('computed rentalFee (rental always charged)', () {
    test('disabled discount -> flat 850 regardless of trip count', () {
      expect(buildWeek(rentalDiscountEnabled: false, tripCount: 0).rentalFee, 850);
      expect(buildWeek(rentalDiscountEnabled: false, tripCount: 130).rentalFee, 850);
      expect(buildWeek(rentalDiscountEnabled: false, tripCount: 200).rentalFee, 850);
      expect(buildWeek(rentalDiscountEnabled: false, tripCount: 5000).rentalFee, 850);
    });

    test('enabled discount -> rentalFee from the trip tier', () {
      expect(buildWeek(tripCount: 130).rentalFee, 650);
      expect(buildWeek(tripCount: 100).rentalFee, 850);
      expect(buildWeek(tripCount: 200).rentalFee, 250);
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
          netIncome: netIncome,
          cashReceived: 0,
          onlineHours: hours,
          tripCount: 100,
          rentalDiscountEnabled: false,
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
    // No rental / fuel so netProfit = netIncome * 0.885 - ADMINISTRATIVE_COST
    // (commission is 0 for turnover >= 3000). Aggregation asserts compare
    // against the model's own netProfit, so they stay self-consistent.
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
        netIncome: netIncome,
        cashReceived: 0,
        onlineHours: onlineHours,
        tripCount: 100,
        rentalDiscountEnabled: false,
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

        // History is stored newest-first; aggregation must not depend on order.
        final months = aggregateByMonth([july, june2, june1]);
        expect(months.length, 2);

        final june = months.first;
        expect(june.month, DateTime(2026, 6, 1));
        expect(june.weekCount, 2);
        expect(june.totalNetProfit,
            closeTo(june1.netProfit + june2.netProfit, 0.0001));
        expect(june.totalOnlineHours, closeTo(140, 0.0001));
        expect(
          june.avgHourlyRate,
          closeTo((june1.netProfit + june2.netProfit) / 140, 0.0001),
        );
        expect(june.totalBankDeposit,
            closeTo(june1.bankDeposit + june2.bankDeposit, 0.0001));
        // Weeks kept oldest -> newest within a month.
        expect(june.weeks.map((w) => w.id).toList(),
            [june1.id, june2.id]);

        final julyMonth = months.last;
        expect(julyMonth.month, DateTime(2026, 7, 1));
        expect(julyMonth.weekCount, 1);
        expect(julyMonth.avgHourlyRate,
            closeTo(july.netProfit / 50, 0.0001));
      });

      test('avgHourlyRate is blended, not the mean of weekly rates', () {
        // Rates: 88.5 and 35.4; blended = 3540+3540... use different hours.
        final a = aggWeek(
            weekStart: DateTime(2026, 3, 2), netIncome: 4000, onlineHours: 40);
        final b = aggWeek(
            weekStart: DateTime(2026, 3, 9), netIncome: 4000, onlineHours: 10);
        final months = aggregateByMonth([a, b]);
        final blended = (a.netProfit + b.netProfit) / (40 + 10);
        expect(months.single.avgHourlyRate, closeTo(blended, 0.0001));
        // Simple mean would be higher, confirming we blend by hours.
        final mean = (a.hourlyRate + b.hourlyRate) / 2;
        expect(months.single.avgHourlyRate, lessThan(mean));
      });

      test('empty list -> empty', () {
        expect(aggregateByMonth(const []), isEmpty);
      });
    });

    group('aggregateByYear', () {
      test('weeks across two years -> one summary per year', () {
        final y2025 = aggWeek(
            weekStart: DateTime(2025, 12, 1), netIncome: 4000, onlineHours: 40);
        final y2026a = aggWeek(
            weekStart: DateTime(2026, 1, 5), netIncome: 5000, onlineHours: 50);
        final y2026b = aggWeek(
            weekStart: DateTime(2026, 2, 2), netIncome: 3000, onlineHours: 30);

        final years = aggregateByYear([y2026b, y2026a, y2025]);
        expect(years.length, 2);
        expect(years.first.year, 2025);
        expect(years.last.year, 2026);

        final y26 = years.last;
        expect(y26.weekCount, 2);
        expect(y26.months.length, 2);
        expect(y26.totalNetProfit,
            closeTo(y2026a.netProfit + y2026b.netProfit, 0.0001));
        expect(
          y26.avgHourlyRate,
          closeTo((y2026a.netProfit + y2026b.netProfit) / 80, 0.0001),
        );
      });

      test('empty list -> empty', () {
        expect(aggregateByYear(const []), isEmpty);
      });
    });

    group('record functions', () {
      // rates: w3=13.275, w1=88.5, w2=44.25 ; w4 incomplete (0 hours)
      final w3 = aggWeek(
          weekStart: DateTime(2026, 6, 1),
          netIncome: 3000,
          onlineHours: 200,
          id: 'w3');
      final w1 = aggWeek(
          weekStart: DateTime(2026, 6, 8),
          netIncome: 4000,
          onlineHours: 40,
          id: 'w1');
      final w2 = aggWeek(
          weekStart: DateTime(2026, 6, 15),
          netIncome: 5000,
          onlineHours: 100,
          id: 'w2');
      final w4 = aggWeek(
          weekStart: DateTime(2026, 6, 22),
          netIncome: 0,
          onlineHours: 0,
          id: 'w4');
      final fixture = [w2, w4, w1, w3];

      test('bestHourlyRateWeek picks the highest rate', () {
        expect(bestHourlyRateWeek(fixture)?.id, 'w1');
      });

      test('worstHourlyRateWeek excludes incomplete (zero-hour) weeks', () {
        expect(worstHourlyRateWeek(fixture)?.id, 'w3');
      });

      test('highestNetProfitWeek picks the biggest single-week profit', () {
        expect(highestNetProfitWeek(fixture)?.id, 'w2');
      });

      test('empty list -> null', () {
        expect(bestHourlyRateWeek(const []), isNull);
        expect(worstHourlyRateWeek(const []), isNull);
        expect(highestNetProfitWeek(const []), isNull);
      });
    });

    group('month filtering (selected month subset)', () {
      // Two months of data; the "best week" of each month differs from the
      // best week of the full history, so filtering to a month must change it.
      final mayLow = aggWeek(
          weekStart: DateTime(2026, 5, 4),
          netIncome: 3000,
          onlineHours: 200,
          id: 'may-low');
      final mayHigh = aggWeek(
          weekStart: DateTime(2026, 5, 11),
          netIncome: 5000,
          onlineHours: 60,
          id: 'may-high');
      final junTop = aggWeek(
          weekStart: DateTime(2026, 6, 1),
          netIncome: 5000,
          onlineHours: 40,
          id: 'jun-top');
      final all = [mayLow, mayHigh, junTop];

      test('aggregateByMonth returns only that month\'s weeks', () {
        final months = aggregateByMonth(all);
        final may = months.firstWhere((m) => m.month.month == 5);
        expect(may.weeks.map((w) => w.id).toSet(), {'may-low', 'may-high'});
        final june = months.firstWhere((m) => m.month.month == 6);
        expect(june.weeks.map((w) => w.id).toList(), ['jun-top']);
      });

      test('best week of the selected month differs from full-history best', () {
        // Across everything, jun-top has the highest hourly rate.
        expect(bestHourlyRateWeek(all)?.id, 'jun-top');
        // Filtered to May, the best week is may-high, not jun-top.
        final may =
            aggregateByMonth(all).firstWhere((m) => m.month.month == 5);
        expect(bestHourlyRateWeek(may.weeks)?.id, 'may-high');
      });
    });
  });

  // ---------------------------------------------------------------------------
  // Audit findings: regression tests for the specific bugs / bad defaults the
  // full-feature audit looked for.
  // ---------------------------------------------------------------------------

  group('audit: division by zero / NaN guard', () {
    test('hourlyRate with 0 online hours is 0, finite (never NaN/Infinity)', () {
      final w = buildWeek(onlineHours: 0);
      expect(w.hourlyRate, 0);
      expect(w.hourlyRate.isFinite, isTrue);
    });

    test('averageHourlyRate over all-zero-hour weeks is 0, not NaN', () {
      final avg = averageHourlyRate([buildWeek(onlineHours: 0)]);
      expect(avg, 0);
      expect(avg.isFinite, isTrue);
    });

    test('formatPln renders non-finite values as an em dash', () {
      expect(formatPln(double.nan), '—');
      expect(formatPln(double.infinity), '—');
      expect(formatPln(double.negativeInfinity), '—');
    });
  });

  group('audit: negative netProfit is preserved and displayed with a sign', () {
    // Small income, big fuel + rental -> genuinely negative week.
    final bad = buildWeek(
      netIncome: 100,
      fuelPumpPaid: 200,
      rentalDiscountEnabled: true,
      tripCount: 130,
      cashReceived: 0,
      onlineHours: 10,
    );

    test('netProfit can be negative (not clamped or abs-ed)', () {
      expect(bad.netProfit, lessThan(0));
      expect(bad.netProfit, closeTo(-832.5, 0.001));
    });

    test('formatPln keeps the minus sign for a negative profit', () {
      expect(formatPln(bad.netProfit), startsWith('-'));
      expect(formatPln(bad.netProfit), '-832,50');
    });

    test('a negative hourlyRate stays negative (not abs-ed)', () {
      expect(bad.hourlyRate, lessThan(0));
      expect(bad.bankDeposit, lessThan(0));
    });
  });

  group('audit: currency rounding to 2 decimals at each step', () {
    test('vat / commission / fuel are each rounded to whole cents', () {
      // 33.33 * 0.115 = 3.83295 -> 3.83
      final w = buildWeek(netIncome: 33.33, fuelPumpPaid: 100.005);
      expect(w.vat, 3.83);
      expect(w.vat, round2(w.vat));
      expect(w.commission, round2(w.commission));
      // 100.005 * 0.9 = 90.0045 -> 90.00
      expect(w.fuelAfterDiscount, 90.0);
    });

    test('breakdown components sum EXACTLY to netProfit (no cent drift)', () {
      final w = buildWeek();
      final recomputed = round2(w.netIncome -
          ADMINISTRATIVE_COST -
          w.fuelAfterDiscount -
          w.vat -
          w.rentalFee -
          w.commission);
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
          // Keys removed across the two simplification passes:
          'rentalFee': 650,
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
      expect(decoded.rentalDiscountEnabled, isTrue); // inferred from rentalFee>0
      expect(decoded.rentalFee, 650);
    });

    test('re-serialized JSON no longer carries the removed keys', () {
      final json = WeekEarning.fromJson(legacyEntry())!.toJson();
      expect(json.containsKey('otherExpenses'), isFalse);
      expect(json.containsKey('notes'), isFalse);
      expect(json.containsKey('administrativeCost'), isFalse);
      expect(json.containsKey('acceptanceRateReported'), isFalse);
      expect(json.containsKey('cancellationRateReported'), isFalse);
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
        netIncome: 4000,
        cashReceived: 0,
        onlineHours: 40,
        tripCount: 100,
        rentalDiscountEnabled: false,
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
        netIncome: 4000,
        cashReceived: 0,
        onlineHours: 40,
        tripCount: 100,
        rentalDiscountEnabled: false,
        fuelPumpPaid: 0,
      );
      final years = aggregateByYear([straddling]);
      expect(years.single.year, 2025);
      expect(years.single.months.single.month, DateTime(2025, 12, 1));
    });
  });

  group('break-even: live current-week fuel (no historical average)', () {
    // Fix 1: the break-even reference reads the LIVE pump-paid figure (× 0.90),
    // NOT a 4-week average or 250 default. This mirrors the exact expression the
    // entry form and breakdown card feed into calculateBreakEven.
    double liveBreakEven({
      required double fuelPumpPaid,
      required bool rentalDiscountEnabled,
      required int tripCount,
    }) {
      final rental =
          rentalDiscountEnabled ? expectedRentalFee(tripCount) : 850.0;
      return calculateBreakEven(
        fixedCosts:
            ADMINISTRATIVE_COST + computeFuelAfterDiscount(fuelPumpPaid) + rental,
      );
    }

    test('empty/zero fuel yields a finite fixed-costs-only break-even', () {
      final v = liveBreakEven(
        fuelPumpPaid: 0,
        rentalDiscountEnabled: true,
        tripCount: 130,
      );
      expect(v.isFinite, isTrue);
      expect(v, greaterThan(0));
      // With 0 fuel the only fixed costs are admin (40) + rental (650).
      expect(v, closeTo(calculateBreakEven(fixedCosts: 40 + 650), 0.001));
    });

    test('break-even rises as the live fuel figure increases', () {
      final low = liveBreakEven(
          fuelPumpPaid: 100, rentalDiscountEnabled: true, tripCount: 130);
      final high = liveBreakEven(
          fuelPumpPaid: 500, rentalDiscountEnabled: true, tripCount: 130);
      expect(high, greaterThan(low));
    });

    test('uses the pump figure directly, not any stored history', () {
      // 300 pump -> 270 fuel; fixedCosts = 40 + 270 + 650 = 960.
      final v = liveBreakEven(
          fuelPumpPaid: 300, rentalDiscountEnabled: true, tripCount: 130);
      expect(v, closeTo(calculateBreakEven(fixedCosts: 960), 0.001));
    });

    test('rental toggle off (flat 850) still degrades gracefully at 0 fuel', () {
      final v = liveBreakEven(
          fuelPumpPaid: 0, rentalDiscountEnabled: false, tripCount: 0);
      expect(v.isFinite, isTrue);
      expect(v, closeTo(calculateBreakEven(fixedCosts: 40 + 850), 0.001));
    });
  });

  group('PDF export: month filter reuses aggregateByMonth', () {
    WeekEarning wk(DateTime start, {String? id}) => WeekEarning(
          id: id ?? start.toIso8601String(),
          weekStart: start,
          weekEnd: start.add(const Duration(days: 6)),
          netIncome: 4000,
          cashReceived: 0,
          onlineHours: 40,
          tripCount: 100,
          rentalDiscountEnabled: false,
          fuelPumpPaid: 0,
        );

    test('a week whose weekStart is exactly the 1st is included in its month',
        () {
      // Fix 2 regression: a boundary week starting on the 1st must NOT be
      // excluded by an off-by-one / strict-comparison filter.
      final onFirst = wk(DateTime(2026, 5, 1), id: 'first');
      final weeks =
          EarningsPdfExport.weeksForMonth([onFirst], DateTime(2026, 5, 1));
      expect(weeks.map((w) => w.id), contains('first'));
      expect(weeks.length, 1);
    });

    test('a month-straddling week counts toward its weekStart month only', () {
      // Mon Jun 29 -> Sun Jul 5 belongs to JUNE (weekStart convention).
      final straddle = wk(DateTime(2026, 6, 29), id: 'straddle');
      expect(
        EarningsPdfExport.weeksForMonth([straddle], DateTime(2026, 6, 1))
            .map((w) => w.id),
        contains('straddle'),
      );
      // ...and is absent from July.
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

    test('a month with no weeks returns empty (graceful no-data path)', () {
      expect(
        EarningsPdfExport.weeksForMonth([wk(DateTime(2026, 5, 4))],
            DateTime(2026, 8, 1)),
        isEmpty,
      );
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

  group('break-even: precise reverse calculation (VAT + commission)', () {
    // Round-trip: solve break-even for a set of fixed costs, then build the
    // exact week that produces those fixed costs and confirm the forward
    // netProfit() function returns ~0. This validates the inverse against the
    // forward function directly rather than a hardcoded expected number.
    //
    // fixedCosts = ADMINISTRATIVE_COST + fuelAfterDiscount + rentalFee, so the
    // fixture week must reproduce the same fuel + rental used to derive them.
    void roundTrip({
      required double fuelPumpPaid,
      required bool rentalDiscountEnabled,
      required int tripCount,
    }) {
      final fuel = computeFuelAfterDiscount(fuelPumpPaid);
      final rental = rentalDiscountEnabled ? expectedRentalFee(tripCount) : 850.0;
      final fixedCosts = ADMINISTRATIVE_COST + fuel + rental;

      final breakEven = calculateBreakEven(fixedCosts: fixedCosts);

      final week = WeekEarning(
        id: 'be',
        weekStart: DateTime(2026, 6, 22),
        weekEnd: DateTime(2026, 6, 28),
        netIncome: breakEven,
        cashReceived: 0,
        onlineHours: 1,
        tripCount: tripCount,
        rentalDiscountEnabled: rentalDiscountEnabled,
        fuelPumpPaid: fuelPumpPaid,
      );

      // The forward function must agree the week breaks even.
      expect(week.netProfit.abs(), lessThan(0.1),
          reason: 'netProfit at break-even ($breakEven) should be ~0');
    }

    test('rental discount ON, typical fuel', () {
      roundTrip(
        fuelPumpPaid: 277.7777777778, // -> 250 after discount
        rentalDiscountEnabled: true,
        tripCount: 130, // -> 650 rental
      );
    });

    test('rental discount OFF (flat 850), typical fuel', () {
      roundTrip(
        fuelPumpPaid: 277.7777777778,
        rentalDiscountEnabled: false,
        tripCount: 130,
      );
    });

    test('high fuel week', () {
      roundTrip(
        fuelPumpPaid: 500, // -> 450 after discount
        rentalDiscountEnabled: true,
        tripCount: 130,
      );
    });

    test('low fuel week', () {
      roundTrip(
        fuelPumpPaid: 100, // -> 90 after discount
        rentalDiscountEnabled: true,
        tripCount: 200, // -> 250 rental (cheapest tier)
      );
    });

    test('very high fixed costs push break-even into a higher bracket', () {
      // Discount off (850) + big fuel -> break-even lands above the 1000
      // commission bracket boundary, exercising tier selection.
      roundTrip(
        fuelPumpPaid: 1000, // -> 900 after discount
        rentalDiscountEnabled: false,
        tripCount: 130,
      );
    });

    test('accounts for VAT + commission (strictly above the naive sum)', () {
      const fixedCosts = 940.0; // 40 + 250 + 650
      final precise = calculateBreakEven(fixedCosts: fixedCosts);
      // The naive estimate ignored VAT/commission entirely.
      expect(precise, greaterThan(fixedCosts));
      // And also above the VAT-only fallback, because commission adds cost.
      expect(precise, greaterThan(fixedCosts / (1 - FLAT_VAT_RATE)));
    });

    test('result is rounded to whole cents', () {
      final v = calculateBreakEven(fixedCosts: 940.005);
      expect(v, round2(v));
    });

    test('the chosen candidate is self-consistent with its commission tier', () {
      final breakEven = calculateBreakEven(fixedCosts: 940);
      // computeFromTier on the solution must be the same commission the solve
      // assumed — i.e. plugging the answer back is consistent.
      final tier = COMMISSION_TIERS.firstWhere(
        (t) => breakEven >= t.min && breakEven <= t.max,
      );
      final expectedCommission = tier.base + breakEven * tier.percent / 100;
      expect(computeFromTier(breakEven), closeTo(expectedCommission, 0.001));
    });
  });

  group('audit: empty / degenerate state never yields NaN', () {
    test('MonthSummary avgHourlyRate is 0 for a month with 0 online hours', () {
      final zeroHours = WeekEarning(
        id: 'z',
        weekStart: DateTime(2026, 5, 4),
        weekEnd: DateTime(2026, 5, 10),
        netIncome: 3000,
        cashReceived: 0,
        onlineHours: 0,
        tripCount: 100,
        rentalDiscountEnabled: false,
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
}

/// Minimal JSON encoder for the legacy-map decode test (avoids importing
/// dart:convert into the test just for one string).
String _jsonNoThrow(Map<String, dynamic> m) {
  final parts = m.entries.map((e) {
    final v = e.value;
    final encoded = v is String ? '"$v"' : '$v';
    return '"${e.key}":$encoded';
  });
  return '{${parts.join(',')}}';
}
