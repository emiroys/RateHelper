import 'dart:convert';

/// Flat VAT rate applied directly to [WeekEarning.netIncome]. This constant
/// 11.5% deduction approximates the operator's real bank deposits closely
/// without reconstructing any per-line tax logic.
// ignore: constant_identifier_names
const double FLAT_VAT_RATE = 0.115;

/// Partner fuel discount applied at the pump (10% off pump price).
// ignore: constant_identifier_names
const double FUEL_PARTNER_DISCOUNT = 0.10;

/// Fixed weekly partnership (administrative) fee in PLN. Never changes, so it
/// is a constant applied automatically rather than an editable field.
// ignore: constant_identifier_names
const double ADMINISTRATIVE_COST = 40.0;

/// Rounds a PLN amount to 2 decimal places (whole cents). Applied at every
/// intermediate monetary step so chained double math (VAT + commission + fuel
/// discount) never compounds floating-point drift into the displayed totals.
/// Non-finite input is passed through untouched for the caller to handle.
double round2(double value) =>
    value.isFinite ? (value * 100).roundToDouble() / 100 : value;

/// Real fuel cost after the partner discount on [fuelPumpPaid].
double computeFuelAfterDiscount(double fuelPumpPaid) =>
    round2(fuelPumpPaid * (1 - FUEL_PARTNER_DISCOUNT));

/// A rental-fee bracket keyed purely on weekly trip count.
/// "Corolla exclusive with a fixed fee" price list (PLN).
class RentalTier {
  const RentalTier({
    required this.minTrips,
    required this.maxTrips,
    required this.fee,
  });

  /// Inclusive lower bound of the trip bracket.
  final int minTrips;

  /// Inclusive upper bound of the trip bracket.
  final int maxTrips;

  /// Expected weekly rental fee (PLN) for this bracket.
  final double fee;

  bool contains(int trips) => trips >= minTrips && trips <= maxTrips;
}

/// Corolla fixed-fee brackets, keyed on trip count alone.
// ignore: constant_identifier_names
const List<RentalTier> RENTAL_TIERS = [
  RentalTier(minTrips: 0, maxTrips: 120, fee: 850),
  RentalTier(minTrips: 121, maxTrips: 160, fee: 650),
  RentalTier(minTrips: 161, maxTrips: 199, fee: 450),
  RentalTier(minTrips: 200, maxTrips: 999999, fee: 250),
];

/// Expected rental bracket for [tripCount].
///
/// Trade-off: acceptance rate is intentionally NOT considered. We assume the
/// driver already qualifies for the tier's accept-rate requirement if they've
/// enabled the rental discount toggle (Uber wouldn't have granted the discount
/// otherwise), so trip count alone determines the tier.
RentalTier expectedRentalTier(int tripCount) {
  if (tripCount <= 120) return RENTAL_TIERS[0];
  if (tripCount <= 160) return RENTAL_TIERS[1];
  if (tripCount <= 199) return RENTAL_TIERS[2];
  return RENTAL_TIERS[3];
}

/// Expected weekly rental fee (PLN) for [tripCount]. Negative trip counts are
/// treated as the lowest bracket (0-120); callers clamp trips to >= 0.
double expectedRentalFee(int tripCount) => expectedRentalTier(tripCount).fee;

/// Human-readable trip bracket for [tier], e.g. `121-160` or `200+` for the
/// open-ended top tier.
String rentalTierRangeLabel(RentalTier tier) =>
    tier.maxTrips >= 999999 ? '${tier.minTrips}+' : '${tier.minTrips}-${tier.maxTrips}';

/// A commission bracket keyed on weekly turnover (net income, PLN).
class CommissionTier {
  const CommissionTier({
    required this.min,
    required this.max,
    required this.base,
    required this.percent,
  });

  /// Inclusive lower turnover bound (PLN).
  final double min;

  /// Exclusive upper turnover bound (PLN), or [double.infinity] for top tier.
  final double max;

  /// Flat base commission (PLN) for this bracket.
  final double base;

  /// Percentage of turnover added on top of [base].
  final double percent;
}

/// Official weekly turnover commission schedule (PLN).
// ignore: constant_identifier_names
const List<CommissionTier> COMMISSION_TIERS = [
  CommissionTier(min: 0, max: 1000, base: 50, percent: 1),
  CommissionTier(min: 1000, max: 2000, base: 25, percent: 1),
  CommissionTier(min: 2000, max: 3000, base: 0, percent: 1),
  CommissionTier(min: 3000, max: double.infinity, base: 0, percent: 0),
];

/// Commission (PLN) for [turnover] looked up from [COMMISSION_TIERS].
double computeFromTier(double turnover) {
  final tier = COMMISSION_TIERS.firstWhere(
    (t) => turnover >= t.min && turnover < t.max,
    orElse: () => COMMISSION_TIERS.last,
  );
  return tier.base + (turnover * tier.percent / 100);
}

/// Kinds of informational cross-check warnings surfaced to the driver. None of
/// these ever block saving — a legitimate reason may exist (promo week, tiny
/// online time on a slow week, etc.).
enum EarningsWarning {
  /// Hourly rate is implausibly low or high — likely a data-entry error.
  hourlyRate,
}

/// True when [hourlyRate] is outside a plausible working range. A rate of `0`
/// (no online hours recorded yet) is never flagged.
bool hasUnusualHourlyRate(double hourlyRate, {double min = 10, double max = 200}) {
  if (hourlyRate <= 0) return false;
  return hourlyRate < min || hourlyRate > max;
}

/// Collects every applicable [EarningsWarning] for the given raw figures. Pure
/// so it can drive both the live entry form and the saved summary card.
List<EarningsWarning> crossCheckWarnings({required double hourlyRate}) {
  return [
    if (hasUnusualHourlyRate(hourlyRate)) EarningsWarning.hourlyRate,
  ];
}

/// Weekly net-income break-even point (PLN): the turnover at which
/// [WeekEarning.netProfit] is exactly 0.
///
/// Unlike a naive fixed-cost sum, this accounts for the two costs that scale
/// with turnover: the flat [FLAT_VAT_RATE] VAT and the tiered commission. For
/// each [COMMISSION_TIERS] bracket we assume the solution lands in that bracket
/// and solve algebraically:
///
///   netIncome - fixedCosts - netIncome*VAT - (base + netIncome*percent/100) = 0
///   => netIncome * (1 - VAT - percent/100) = fixedCosts + base
///
/// then keep the first candidate that actually falls inside the bracket it was
/// solved for (making the tier assumption self-consistent). [fixedCosts] is the
/// turnover-independent portion: ADMINISTRATIVE_COST + fuel + rental.
double calculateBreakEven({required double fixedCosts}) {
  for (final tier in COMMISSION_TIERS) {
    final denominator = 1 - FLAT_VAT_RATE - (tier.percent / 100);
    if (denominator <= 0) continue; // guard against degenerate tiers
    final candidate = (fixedCosts + tier.base) / denominator;
    if (candidate >= tier.min && candidate < tier.max) {
      return round2(candidate);
    }
  }
  // Fallback (should not trigger with well-formed tiers): VAT-only estimate.
  return round2(fixedCosts / (1 - FLAT_VAT_RATE));
}

/// Average hourly rate across [weeks], skipping weeks with no online time.
/// Returns `0` when there is nothing to average.
double averageHourlyRate(Iterable<WeekEarning> weeks) {
  var sum = 0.0;
  var count = 0;
  for (final w in weeks) {
    if (w.onlineHours > 0) {
      sum += w.hourlyRate;
      count++;
    }
  }
  return count > 0 ? sum / count : 0;
}

/// Aggregated earnings for a single calendar month.
class MonthSummary {
  MonthSummary({
    required this.month,
    required this.totalNetProfit,
    required this.totalOnlineHours,
    required this.avgHourlyRate,
    required this.totalBankDeposit,
    required this.totalCash,
    required this.weekCount,
    required this.weeks,
  });

  /// First day (00:00) of the month this summary covers.
  final DateTime month;
  final double totalNetProfit;
  final double totalOnlineHours;

  /// Blended hourly rate: [totalNetProfit] / [totalOnlineHours] (0 if no hours).
  final double avgHourlyRate;
  final double totalBankDeposit;
  final double totalCash;
  final int weekCount;

  /// Weeks that fall in this month, ordered oldest → newest.
  final List<WeekEarning> weeks;
}

/// Aggregated earnings for a single calendar year.
class YearSummary {
  YearSummary({
    required this.year,
    required this.totalNetProfit,
    required this.totalOnlineHours,
    required this.avgHourlyRate,
    required this.weekCount,
    required this.months,
  });

  final int year;
  final double totalNetProfit;
  final double totalOnlineHours;

  /// Blended hourly rate: [totalNetProfit] / [totalOnlineHours] (0 if no hours).
  final double avgHourlyRate;
  final int weekCount;

  /// Months with data in this year, ordered oldest → newest.
  final List<MonthSummary> months;
}

/// Groups [weeks] by the calendar month of their [WeekEarning.weekStart] and
/// returns one [MonthSummary] per month, ordered oldest → newest.
///
/// Week-boundary rule (intentional & consistent): a Monday-Sunday week that
/// straddles a month/year boundary counts entirely toward the month of its
/// [WeekEarning.weekStart] (the Monday). A week starting Mon Jun 29 and ending
/// Sun Jul 5 is a June week; [aggregateByYear] inherits the same rule.
List<MonthSummary> aggregateByMonth(List<WeekEarning> weeks) {
  final buckets = <String, List<WeekEarning>>{};
  for (final w in weeks) {
    final key = '${w.weekStart.year}-${w.weekStart.month}';
    buckets.putIfAbsent(key, () => <WeekEarning>[]).add(w);
  }

  final summaries = <MonthSummary>[];
  for (final entry in buckets.entries) {
    final list = [...entry.value]
      ..sort((a, b) => a.weekStart.compareTo(b.weekStart));
    var netProfit = 0.0;
    var hours = 0.0;
    var bank = 0.0;
    var cash = 0.0;
    for (final w in list) {
      netProfit += w.netProfit;
      hours += w.onlineHours;
      bank += w.bankDeposit;
      cash += w.cashInHand;
    }
    final first = list.first.weekStart;
    summaries.add(MonthSummary(
      month: DateTime(first.year, first.month, 1),
      totalNetProfit: netProfit,
      totalOnlineHours: hours,
      avgHourlyRate: hours > 0 ? netProfit / hours : 0,
      totalBankDeposit: bank,
      totalCash: cash,
      weekCount: list.length,
      weeks: list,
    ));
  }

  summaries.sort((a, b) => a.month.compareTo(b.month));
  return summaries;
}

/// Groups [weeks] by calendar year and returns one [YearSummary] per year,
/// ordered oldest → newest. Each year carries its [MonthSummary] breakdown.
List<YearSummary> aggregateByYear(List<WeekEarning> weeks) {
  final months = aggregateByMonth(weeks);
  final buckets = <int, List<MonthSummary>>{};
  for (final m in months) {
    buckets.putIfAbsent(m.month.year, () => <MonthSummary>[]).add(m);
  }

  final summaries = <YearSummary>[];
  for (final entry in buckets.entries) {
    final list = [...entry.value]
      ..sort((a, b) => a.month.compareTo(b.month));
    var netProfit = 0.0;
    var hours = 0.0;
    var weekCount = 0;
    for (final m in list) {
      netProfit += m.totalNetProfit;
      hours += m.totalOnlineHours;
      weekCount += m.weekCount;
    }
    summaries.add(YearSummary(
      year: entry.key,
      totalNetProfit: netProfit,
      totalOnlineHours: hours,
      avgHourlyRate: hours > 0 ? netProfit / hours : 0,
      weekCount: weekCount,
      months: list,
    ));
  }

  summaries.sort((a, b) => a.year.compareTo(b.year));
  return summaries;
}

/// Week with the highest [WeekEarning.hourlyRate], skipping weeks with no
/// online time. Returns `null` when no qualifying week exists.
WeekEarning? bestHourlyRateWeek(List<WeekEarning> weeks) {
  WeekEarning? best;
  for (final w in weeks) {
    if (w.onlineHours <= 0) continue;
    if (best == null || w.hourlyRate > best.hourlyRate) best = w;
  }
  return best;
}

/// Week with the lowest [WeekEarning.hourlyRate], excluding zero/incomplete
/// entries (no online time). Returns `null` when no qualifying week exists.
WeekEarning? worstHourlyRateWeek(List<WeekEarning> weeks) {
  WeekEarning? worst;
  for (final w in weeks) {
    if (w.onlineHours <= 0) continue;
    if (worst == null || w.hourlyRate < worst.hourlyRate) worst = w;
  }
  return worst;
}

/// Week with the highest single-week [WeekEarning.netProfit]. Returns `null`
/// for an empty list.
WeekEarning? highestNetProfitWeek(List<WeekEarning> weeks) {
  WeekEarning? best;
  for (final w in weeks) {
    if (best == null || w.netProfit > best.netProfit) best = w;
  }
  return best;
}

/// A single archived week of earnings. One entry per Monday-Sunday week.
///
/// Every figure is read directly from the Uber Driver app earnings screen; the
/// single [netIncome] number at the top drives all calculations.
class WeekEarning {
  WeekEarning({
    required this.id,
    required this.weekStart,
    required this.weekEnd,
    required this.netIncome,
    required this.cashReceived,
    required this.onlineHours,
    required this.tripCount,
    required this.rentalDiscountEnabled,
    required this.fuelPumpPaid,
  });

  /// Stable identifier so edits/deletes target the right entry.
  final String id;

  /// Always a Monday (auto-computed from the selected week offset).
  final DateTime weekStart;

  /// Always the following Sunday.
  final DateTime weekEnd;

  /// "Net Gelir" — the single big number at the top of Uber's earnings screen.
  final double netIncome;

  /// "Alınan Nakit". Cash physically collected on the road; subtracted from the
  /// bank deposit.
  final double cashReceived;

  /// Online hours as a decimal (from "Çevrimiçi: X sa. Y dk.").
  final double onlineHours;

  /// Weekly trip count.
  final int tripCount;

  /// Whether the rental discount applies this week. When `false` there is no
  /// rental deduction; when `true` the fee is derived from [RENTAL_TIERS].
  final bool rentalDiscountEnabled;

  /// "Pompada Ödenen" — what the driver actually paid at the pump.
  final double fuelPumpPaid;

  /// Real fuel cost after the 10% partner discount (not stored), rounded to
  /// whole cents.
  double get fuelAfterDiscount => computeFuelAfterDiscount(fuelPumpPaid);

  /// Rental deduction (PLN). Rental is ALWAYS charged; the toggle only decides
  /// whether the driver qualifies for the trip-count discount tiers. When the
  /// discount is off the driver pays the flat base rate (850 PLN) regardless of
  /// trip count; when on, the fee comes from the [RENTAL_TIERS] bracket.
  double get rentalFee =>
      rentalDiscountEnabled ? expectedRentalFee(tripCount) : 850.0;

  WeekEarning copyWith({
    DateTime? weekStart,
    DateTime? weekEnd,
    double? netIncome,
    double? cashReceived,
    double? onlineHours,
    int? tripCount,
    bool? rentalDiscountEnabled,
    double? fuelPumpPaid,
  }) {
    return WeekEarning(
      id: id,
      weekStart: weekStart ?? this.weekStart,
      weekEnd: weekEnd ?? this.weekEnd,
      netIncome: netIncome ?? this.netIncome,
      cashReceived: cashReceived ?? this.cashReceived,
      onlineHours: onlineHours ?? this.onlineHours,
      tripCount: tripCount ?? this.tripCount,
      rentalDiscountEnabled:
          rentalDiscountEnabled ?? this.rentalDiscountEnabled,
      fuelPumpPaid: fuelPumpPaid ?? this.fuelPumpPaid,
    );
  }

  /// Flat 11.5% VAT charged on [netIncome], rounded to whole cents.
  double get vat => round2(netIncome * FLAT_VAT_RATE);

  /// Commission for this week's turnover ([netIncome]) from [COMMISSION_TIERS],
  /// rounded to whole cents.
  double get commission => round2(computeFromTier(netIncome));

  /// Real net profit after the fixed admin fee, VAT, rental and commission.
  /// Computed from the already-rounded components so the breakdown card lines
  /// always add up exactly to this figure (no off-by-a-cent display drift).
  double get netProfit => round2(
        netIncome -
            ADMINISTRATIVE_COST -
            fuelAfterDiscount -
            vat -
            rentalFee -
            commission,
      );

  /// What actually lands in the bank once the cash already collected on the
  /// road is accounted for. Can legitimately be negative on a bad/low week.
  double get bankDeposit => round2(netProfit - cashReceived);

  /// Cash physically held by the driver ("Elde Nakit").
  double get cashInHand => cashReceived;

  /// Real hourly profit. Zero when no online time is recorded (guards against
  /// division by zero producing NaN/Infinity). Not pre-rounded — [netProfit] is
  /// already clean to the cent and the display formatter rounds for the UI.
  double get hourlyRate => onlineHours > 0 ? netProfit / onlineHours : 0;

  /// Non-blocking, informational cross-check warnings for this week.
  List<EarningsWarning> get warnings =>
      crossCheckWarnings(hourlyRate: hourlyRate);

  Map<String, dynamic> toJson() => {
        'id': id,
        'weekStart': weekStart.toIso8601String(),
        'weekEnd': weekEnd.toIso8601String(),
        'netIncome': netIncome,
        'cashReceived': cashReceived,
        'onlineHours': onlineHours,
        'tripCount': tripCount,
        'rentalDiscountEnabled': rentalDiscountEnabled,
        'fuelPumpPaid': fuelPumpPaid,
      };

  /// Rebuilds an entry from stored JSON. Reads only the keys it still needs, so
  /// OLD entries carrying now-removed keys (`administrativeCost`,
  /// `otherExpenses`, `notes`, `acceptanceRateReported`,
  /// `cancellationRateReported`, `rentalFee`) are ignored gracefully rather
  /// than throwing. Returns `null` only when the week dates can't be parsed.
  static WeekEarning? fromJson(Map<String, dynamic> json) {
    final start = DateTime.tryParse(json['weekStart']?.toString() ?? '');
    final end = DateTime.tryParse(json['weekEnd']?.toString() ?? '');
    if (start == null || end == null) return null;

    return WeekEarning(
      id: json['id']?.toString() ??
          '${start.millisecondsSinceEpoch}_${end.millisecondsSinceEpoch}',
      weekStart: start,
      weekEnd: end,
      netIncome: _toDouble(json['netIncome']),
      cashReceived: _toDouble(json['cashReceived']),
      onlineHours: _toDouble(json['onlineHours']),
      tripCount: _toInt(json['tripCount']),
      rentalDiscountEnabled: _rentalDiscountFromJson(json),
      fuelPumpPaid: _fuelPumpPaidFromJson(json),
    );
  }

  /// Reads [rentalDiscountEnabled], inferring it from a legacy stored
  /// `rentalFee > 0` when the flag is absent (older entries).
  static bool _rentalDiscountFromJson(Map<String, dynamic> json) {
    final flag = json['rentalDiscountEnabled'];
    if (flag is bool) return flag;
    if (flag != null) return flag.toString().toLowerCase() == 'true';
    return _toDouble(json['rentalFee']) > 0;
  }

  /// Reads [fuelPumpPaid], falling back to legacy stored discounted/gross fuel.
  static double _fuelPumpPaidFromJson(Map<String, dynamic> json) {
    if (json.containsKey('fuelPumpPaid')) {
      return _toDouble(json['fuelPumpPaid']);
    }
    final legacyDiscounted = _toDouble(json['fuelAfterDiscount']);
    if (legacyDiscounted != 0) {
      return legacyDiscounted / (1 - FUEL_PARTNER_DISCOUNT);
    }
    return _toDouble(json['fuelGross']);
  }

  static double _toDouble(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(' ', '').replaceAll('.', '').replaceAll(',', '.') ?? '') ?? 0;
  }

  static int _toInt(Object? v) {
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '') ?? 0;
  }
}

/// Maximum number of stored weeks (2 years). Oldest entries are dropped FIFO.
const int kMaxEarningEntries = 104;

/// SharedPreferences key for the earnings history JSON list.
const String kEarningsHistoryKey = 'earnings_history';

/// Monday (00:00, date-only) of the week identified by [offset] relative to
/// [now]. `0` == current week, `-1` == last week, `1` == next week.
DateTime weekStartForOffset(int offset, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final daysSinceMonday = (n.weekday - DateTime.monday) % 7;
  final base = DateTime(n.year, n.month, n.day - daysSinceMonday);
  return DateTime(base.year, base.month, base.day + (7 * offset));
}

/// Sunday of the week that starts on [monday].
DateTime weekEndForStart(DateTime monday) =>
    DateTime(monday.year, monday.month, monday.day + 6);

/// True when [a] and [b] fall on the same calendar day.
bool isSameDate(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Formats a PLN amount using Polish/Turkish grouping: `1.924,97`.
///
/// Non-finite values (NaN / Infinity, e.g. from an unexpected divide-by-zero)
/// render as an em dash instead of leaking "NaN"/"Infinity" into the UI.
String formatPln(double value) {
  if (!value.isFinite) return '—';
  final negative = value < 0;
  final fixed = value.abs().toStringAsFixed(2);
  final dotIndex = fixed.indexOf('.');
  final intPart = fixed.substring(0, dotIndex);
  final decPart = fixed.substring(dotIndex + 1);

  final grouped = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) grouped.write('.');
    grouped.write(intPart[i]);
  }
  return '${negative ? '-' : ''}$grouped,$decPart';
}

/// Converts hours + minutes into a decimal hour value.
double onlineHoursFromHm(int hours, int minutes) => hours + (minutes / 60.0);

/// Formats decimal hours back into an "h:mm" style label (e.g. 25.98 -> 25:59).
String formatHoursHm(double hours) {
  final total = (hours * 60).round();
  final h = total ~/ 60;
  final m = total % 60;
  return '$h:${m.toString().padLeft(2, '0')}';
}

/// Decodes the stored JSON list into [WeekEarning] objects. Returns an empty
/// list on any parse failure.
List<WeekEarning> decodeEarnings(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! List) return [];
    final result = <WeekEarning>[];
    for (final item in decoded) {
      if (item is Map) {
        final entry = WeekEarning.fromJson(Map<String, dynamic>.from(item));
        if (entry != null) result.add(entry);
      }
    }
    return result;
  } catch (_) {
    return [];
  }
}

/// Encodes [entries] to a JSON string, trimming to [kMaxEarningEntries]
/// (FIFO, dropping the oldest by [WeekEarning.weekStart]).
String encodeEarnings(List<WeekEarning> entries) {
  final sorted = [...entries]..sort((a, b) => a.weekStart.compareTo(b.weekStart));
  final trimmed = sorted.length > kMaxEarningEntries
      ? sorted.sublist(sorted.length - kMaxEarningEntries)
      : sorted;
  return jsonEncode(trimmed.map((e) => e.toJson()).toList());
}
