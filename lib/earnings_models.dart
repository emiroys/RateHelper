import 'dart:convert';

/// Flat VAT rate applied directly to [WeekEarning.netIncome]. This constant
/// 12% deduction approximates the operator's real bank deposits closely
/// without reconstructing any per-line tax logic.
// ignore: constant_identifier_names
const double FLAT_VAT_RATE = 0.12;

/// Flat settlement fee rate applied directly to [WeekEarning.netIncome] (3%).
// ignore: constant_identifier_names
const double SETTLEMENT_FEE_RATE = 0.03;

/// Partner fuel discount applied at the pump (10% off pump price).
// ignore: constant_identifier_names
const double FUEL_PARTNER_DISCOUNT = 0.10;


/// Rounds a PLN amount to 2 decimal places (whole cents). Applied at every
/// intermediate monetary step so chained double math (VAT + commission + fuel
/// discount) never compounds floating-point drift into the displayed totals.
/// Non-finite input is passed through untouched for the caller to handle.
double round2(double value) =>
    value.isFinite ? (value * 100).roundToDouble() / 100 : value;

/// Real fuel cost after the partner discount on [fuelPumpPaid].
double computeFuelAfterDiscount(double fuelPumpPaid) =>
    round2(fuelPumpPaid * (1 - FUEL_PARTNER_DISCOUNT));

enum DriverMode {
  solo,
  paired;

  static const key = 'driver_mode';
  static const askedKey = 'driver_mode_asked';
}

/// Global active driver mode, backed by SharedPreferences.
DriverMode activeDriverMode = DriverMode.solo;

DriverMode get driverMode => activeDriverMode;

/// A rental-fee bracket keyed on weekly trip count.
class RentalTier {
  const RentalTier({
    required this.minTrips,
    required this.maxTrips,
    required this.feePerDriver,
    double? totalCarFee,
  }) : totalCarFee = totalCarFee ?? feePerDriver;

  /// Inclusive lower bound of the trip bracket.
  final int minTrips;

  /// Inclusive upper bound of the trip bracket.
  final int maxTrips;

  /// Expected weekly rental fee per driver (PLN) for this bracket.
  final double feePerDriver;

  /// Total weekly rental fee for the car (PLN) for this bracket.
  final double totalCarFee;

  /// For backward compatibility:
  double get fee => feePerDriver;

  bool contains(int trips) => trips >= minTrips && trips <= maxTrips;
}

/// New ERES rental fee schedule (PLN), keyed on trip count.
// ignore: constant_identifier_names
const List<RentalTier> RENTAL_TIERS = [
  RentalTier(minTrips: 0,   maxTrips: 99,  feePerDriver: 900),
  RentalTier(minTrips: 100, maxTrips: 149, feePerDriver: 700),
  RentalTier(minTrips: 150, maxTrips: 199, feePerDriver: 500),
  RentalTier(minTrips: 200, maxTrips: 249, feePerDriver: 300),
  RentalTier(minTrips: 250, maxTrips: 999999, feePerDriver: 100),
];

/// New ERES rental fee schedule (PLN) for paired drivers (2 drivers sharing a car).
// ignore: constant_identifier_names
const List<RentalTier> RENTAL_TIERS_PAIRED = [
  RentalTier(minTrips: 0,   maxTrips: 119, feePerDriver: 450, totalCarFee: 900),
  RentalTier(minTrips: 120, maxTrips: 169, feePerDriver: 350, totalCarFee: 700),
  RentalTier(minTrips: 170, maxTrips: 219, feePerDriver: 250, totalCarFee: 500),
  RentalTier(minTrips: 220, maxTrips: 269, feePerDriver: 150, totalCarFee: 300),
  RentalTier(minTrips: 270, maxTrips: 999999, feePerDriver: 50, totalCarFee: 100),
];

/// Expected rental bracket for [tripCount] and [mode].
RentalTier expectedRentalTier(int tripCount, DriverMode mode) {
  final tiers = mode == DriverMode.paired ? RENTAL_TIERS_PAIRED : RENTAL_TIERS;
  final trips = tripCount < 0 ? 0 : tripCount;
  return tiers.firstWhere(
    (t) => trips >= t.minTrips && trips <= t.maxTrips,
    orElse: () => tiers.last,
  );
}

/// Expected weekly rental fee (PLN) for [tripCount] and [mode].
double expectedRentalFee(int tripCount, DriverMode mode) =>
    expectedRentalTier(tripCount, mode).feePerDriver;

/// Human-readable trip bracket for [tier], e.g. `100-149` or `250+` for the
/// open-ended top tier.
String rentalTierRangeLabel(RentalTier tier) =>
    tier.maxTrips >= 999999 ? '${tier.minTrips}+' : '${tier.minTrips}-${tier.maxTrips}';

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
/// Accounts for the flat [FLAT_VAT_RATE] VAT that scales with turnover:
///
///   netIncome - fixedCosts - netIncome*VAT = 0
///   => netIncome * (1 - VAT) = fixedCosts
///
/// [fixedCosts] is the turnover-independent portion: fuel + rental.
double calculateBreakEven({required double fixedCosts}) {
  final double denominator = 1 - FLAT_VAT_RATE - SETTLEMENT_FEE_RATE;
  return round2(fixedCosts / denominator);
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

class FuelReceipt {
  FuelReceipt({
    String? id,
    required this.timestamp,
    required this.amountPaid,
  }) : id = id ?? '${timestamp.millisecondsSinceEpoch}_${amountPaid.hashCode}';

  String id;
  DateTime timestamp;
  double amountPaid;

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'amountPaid': amountPaid,
      };

  factory FuelReceipt.fromJson(Map<String, dynamic> json) => FuelReceipt(
        id: json['id']?.toString(),
        timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ?? DateTime.now(),
        amountPaid: _toDoubleHelper(json['amountPaid']),
      );

  static double _toDoubleHelper(Object? v) {
    if (v is num) return v.toDouble();
    return double.tryParse(v?.toString().replaceAll(' ', '').replaceAll('.', '').replaceAll(',', '.') ?? '') ?? 0.0;
  }
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
    required this.driverMode,
    required this.netIncome,
    required this.cashReceived,
    required this.onlineHours,
    required this.tripCount,
    this.hasRentalDiscount = true,
    List<FuelReceipt>? fuelReceipts,
    double? fuelPumpPaid,
  }) : fuelReceipts = fuelReceipts ??
            (fuelPumpPaid != null && fuelPumpPaid > 0
                ? [FuelReceipt(timestamp: weekStart, amountPaid: fuelPumpPaid)]
                : []);

  /// Stable identifier so edits/deletes target the right entry.
  final String id;

  /// Always a Monday (auto-computed from the selected week offset).
  final DateTime weekStart;

  /// Always the following Sunday.
  final DateTime weekEnd;

  /// Driver mode captured at creation time (immutable).
  final DriverMode driverMode;

  /// "Net Gelir" — the single big number at the top of Uber's earnings screen.
  final double netIncome;

  /// "Alınan Nakit". Cash physically collected on the road; subtracted from the
  /// bank deposit.
  final double cashReceived;

  /// Online hours as a decimal (from "Çevrimiçi: X sa. Y dk.").
  final double onlineHours;

  /// Weekly trip count.
  final int tripCount;

  /// Whether rental discount is active for this entry.
  final bool hasRentalDiscount;

  /// List of fuel receipts recorded during this week.
  final List<FuelReceipt> fuelReceipts;

  /// Total pump fuel paid across all [fuelReceipts].
  double get fuelPumpPaidTotal => fuelReceipts.fold(0.0, (sum, r) => sum + r.amountPaid);

  /// For backward compatibility with legacy single-value references:
  double get fuelPumpPaid => fuelPumpPaidTotal;

  /// Real fuel cost after the 10% partner discount (not stored), rounded to
  /// whole cents.
  double get fuelAfterDiscount => computeFuelAfterDiscount(fuelPumpPaidTotal);

  /// Rental deduction (PLN).
  double get rentalFee => hasRentalDiscount
      ? expectedRentalFee(tripCount, driverMode)
      : (driverMode == DriverMode.paired ? 450.0 : 900.0);

  /// Total car rental fee (PLN) across both drivers if paired, or solo fee if solo.
  double get totalCarRentalFee => hasRentalDiscount
      ? expectedRentalTier(tripCount, driverMode).totalCarFee
      : 900.0;

  WeekEarning copyWith({
    DateTime? weekStart,
    DateTime? weekEnd,
    DriverMode? driverMode,
    double? netIncome,
    double? cashReceived,
    double? onlineHours,
    int? tripCount,
    bool? hasRentalDiscount,
    List<FuelReceipt>? fuelReceipts,
    double? fuelPumpPaid,
  }) {
    return WeekEarning(
      id: id,
      weekStart: weekStart ?? this.weekStart,
      weekEnd: weekEnd ?? this.weekEnd,
      driverMode: driverMode ?? this.driverMode,
      netIncome: netIncome ?? this.netIncome,
      cashReceived: cashReceived ?? this.cashReceived,
      onlineHours: onlineHours ?? this.onlineHours,
      tripCount: tripCount ?? this.tripCount,
      hasRentalDiscount: hasRentalDiscount ?? this.hasRentalDiscount,
      fuelReceipts: fuelReceipts ?? (fuelPumpPaid != null ? null : this.fuelReceipts),
      fuelPumpPaid: fuelPumpPaid,
    );
  }

  /// Flat 12% VAT charged on [netIncome], rounded to whole cents.
  double get vat => round2(netIncome * FLAT_VAT_RATE);

  /// Flat 3% settlement fee charged on [netIncome], rounded to whole cents.
  double get settlementFee => round2(netIncome * SETTLEMENT_FEE_RATE);

  /// Real net profit after the fixed admin fee, VAT, rental, and settlement fee.
  /// Computed from the already-rounded components so the breakdown card lines
  /// always add up exactly to this figure (no off-by-a-cent display drift).
  double get netProfit => round2(
        netIncome -
            fuelAfterDiscount -
            vat -
            rentalFee -
            settlementFee,
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
        'version': 1,
        'id': id,
        'weekStart': weekStart.toIso8601String(),
        'weekEnd': weekEnd.toIso8601String(),
        'driverMode': driverMode.name,
        'netIncome': netIncome,
        'cashReceived': cashReceived,
        'onlineHours': onlineHours,
        'tripCount': tripCount,
        'hasRentalDiscount': hasRentalDiscount,
        'fuelReceipts': fuelReceipts.map((r) => r.toJson()).toList(),
      };

  /// Rebuilds an entry from stored JSON. Reads only the keys it still needs, so
  /// OLD entries carrying now-removed keys (`administrativeCost`,
  /// `otherExpenses`, `notes`, `rentalDiscountEnabled`, `commission`,
  /// `rentalFee`) are ignored gracefully rather than throwing.
  static WeekEarning? fromJson(Map<String, dynamic> json) {
    // ignore: unused_local_variable
    final int version = _toInt(json['version'] ?? 0);
    final start = DateTime.tryParse(json['weekStart']?.toString() ?? '');
    final end = DateTime.tryParse(json['weekEnd']?.toString() ?? '');
    if (start == null || end == null) return null;

    final modeStr = json['driverMode']?.toString();
    final mode = modeStr == 'paired' ? DriverMode.paired : DriverMode.solo;

    List<FuelReceipt> receipts = [];
    if (json.containsKey('fuelReceipts') && json['fuelReceipts'] is List) {
      final list = json['fuelReceipts'] as List<dynamic>;
      receipts = list
          .whereType<Map>()
          .map((e) => FuelReceipt.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    } else {
      final legacyPump = _fuelPumpPaidFromJson(json);
      if (legacyPump > 0) {
        receipts = [
          FuelReceipt(
            id: 'legacy_${start.millisecondsSinceEpoch}',
            timestamp: start,
            amountPaid: legacyPump,
          )
        ];
      }
    }

    final hasRentalDiscount = json.containsKey('hasRentalDiscount')
        ? _toBool(json['hasRentalDiscount'])
        : (json.containsKey('rentalDiscountEnabled')
            ? _toBool(json['rentalDiscountEnabled'])
            : true);

    return WeekEarning(
      id: json['id']?.toString() ??
          '${start.millisecondsSinceEpoch}_${end.millisecondsSinceEpoch}',
      weekStart: start,
      weekEnd: end,
      driverMode: mode,
      netIncome: _toDouble(json['netIncome']),
      cashReceived: _toDouble(json['cashReceived']),
      onlineHours: _toDouble(json['onlineHours']),
      tripCount: _toInt(json['tripCount']),
      hasRentalDiscount: hasRentalDiscount,
      fuelReceipts: receipts,
    );
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

  static bool _toBool(Object? v) {
    if (v is bool) return v;
    if (v == null) return true;
    final s = v.toString().trim().toLowerCase();
    return s == 'true' || s == '1';
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

/// SharedPreferences key for the persistent lifetime trip odometer.
/// This value is ONLY incremented — never decremented by FIFO eviction —
/// so the free-week milestone never regresses as old weeks are trimmed.
const String kLifetimeTripsKey = 'lifetime_trips_total';

/// SharedPreferences key (bool) guarding the one-time backfill migration.
/// Once set to `true`, the backfill from existing history is never re-run.
const String kLifetimeTripsBackfilledKey = 'lifetime_trips_backfilled';

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

/// Threshold of lifetime trips required to earn one free week of rental.
const int kFreeWeekTripThreshold = 2000;

/// Sum of [WeekEarning.tripCount] across all stored [weeks].
int calculateLifetimeTrips(Iterable<WeekEarning> weeks) {
  var total = 0;
  for (final w in weeks) {
    total += w.tripCount;
  }
  return total;
}

/// Total number of free car rental weeks earned over the lifetime ([lifetimeTrips ~/ 2000]).
int calculateFreeWeeksEarned(int lifetimeTrips) =>
    lifetimeTrips ~/ kFreeWeekTripThreshold;

/// Progress (in trips) toward the next free car rental week (from 0 to 1999).
int calculateCurrentFreeWeekProgress(int lifetimeTrips) =>
    lifetimeTrips % kFreeWeekTripThreshold;

