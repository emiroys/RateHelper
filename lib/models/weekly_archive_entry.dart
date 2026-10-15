import 'dart:convert';
import '../l10n.dart';

/// Cancellation ceiling (percent) archived with a week.
///
/// The live budget in `maxAdditionalCancellations` uses the same number.
/// A weekly badge is green while the rate is within this limit (inclusive)
/// and red once the rate exceeds it.
const double kWeeklyCancelCeiling = 5.0;

/// One-decimal rate text for weekly archive badges (`80.3`, `3.8`).
String formatWeeklyRate(double rate) => rate.toStringAsFixed(1);

/// A trip-goal bracket used to grade a week that was saved before goals
/// were stored on the archive entry.
class WeeklyGoalFloor {
  const WeeklyGoalFloor({
    required this.name,
    required this.minTrips,
    required this.acceptRate,
  });

  final String name;
  final int minTrips;
  final double? acceptRate;
}

/// How a saved week scores against the goal that belonged to that week.
class WeeklyGoalAssessment {
  const WeeklyGoalAssessment({
    required this.tierName,
    required this.targetAcceptRate,
    required this.maxCancelRate,
    required this.acceptMet,
    required this.cancelMet,
  });

  final String? tierName;

  /// Null means the tier has no acceptance-rate requirement.
  final double? targetAcceptRate;
  final double maxCancelRate;
  final bool acceptMet;
  final bool cancelMet;

  bool get goalMet => acceptMet && cancelMet;
}

class WeeklyArchiveEntry {
  final DateTime? weekStart;
  final DateTime? weekEnd;
  final double acceptRate;
  final double cancelRate;
  final int acceptedCount;
  final int rejectedCount;
  final int completedTrips;
  final int canceledTrips;

  /// False on weeks saved before canceled trips were stored. The count is
  /// then recovered from [completedTrips] and [cancelRate].
  final bool canceledTripsStored;
  final bool isLegacy;
  final String? legacyDisplayString;

  /// [TripGoal.name] active when this week was archived. Null on older rows.
  final String? goalTier;

  /// Acceptance target (percent) for [goalTier]. Null with
  /// [targetAcceptRateStored] means the tier had no acceptance requirement.
  final double? targetAcceptRate;
  final bool targetAcceptRateStored;

  /// Cancellation ceiling (percent) that applied to this week.
  final double? maxCancelRate;

  /// Original prefs line. Kept so collapsing the list does not rewrite
  /// legacy rows and strip the rates out of the stored string.
  final String? originRaw;

  DateTime? get startDate => weekStart;
  DateTime? get endDate => weekEnd;

  /// Structured rows know their counters. Legacy strings only know rates.
  bool get hasCountableStats => !isLegacy;

  int get resolvedCanceledTrips => canceledTripsStored
      ? canceledTrips
      : inferCanceledTrips(completedTrips, cancelRate);

  int get totalRequests => acceptedCount + rejectedCount;

  const WeeklyArchiveEntry({
    DateTime? weekStart,
    DateTime? startDate,
    DateTime? weekEnd,
    DateTime? endDate,
    required this.acceptRate,
    required this.cancelRate,
    this.acceptedCount = 0,
    this.rejectedCount = 0,
    this.completedTrips = 0,
    this.canceledTrips = 0,
    this.canceledTripsStored = false,
    this.isLegacy = false,
    this.legacyDisplayString,
    this.goalTier,
    this.targetAcceptRate,
    this.targetAcceptRateStored = false,
    this.maxCancelRate,
    this.originRaw,
  }) : weekStart = weekStart ?? startDate,
       weekEnd = weekEnd ?? endDate;

  factory WeeklyArchiveEntry.legacy(String rawString) {
    double aRate = 0.0;
    double cRate = 0.0;
    String header = rawString;

    if (rawString.contains(':')) {
      final parts = rawString.split(':');
      header = parts.first.trim();
    }
    final matches = RegExp(
      r'%([0-9]+(?:\.[0-9]+)?)',
    ).allMatches(rawString).toList();
    if (matches.isNotEmpty) {
      aRate = double.tryParse(matches[0].group(1) ?? '') ?? 0.0;
    }
    if (matches.length > 1) {
      cRate = double.tryParse(matches[1].group(1) ?? '') ?? 0.0;
    }

    return WeeklyArchiveEntry(
      acceptRate: aRate,
      cancelRate: cRate,
      isLegacy: true,
      legacyDisplayString: header,
      originRaw: rawString,
    );
  }

  static WeeklyArchiveEntry parse(String raw) {
    try {
      final trimmed = raw.trim();
      if (trimmed.startsWith('{')) {
        final decoded = jsonDecode(trimmed);
        if (decoded is Map<String, dynamic> && decoded['v'] == 2) {
          final start = decoded['weekStart'] ?? decoded['startDate'];
          final end = decoded['weekEnd'] ?? decoded['endDate'];
          final tier = decoded['goalTier'];
          return WeeklyArchiveEntry(
            weekStart: start != null
                ? DateTime.tryParse(start.toString())
                : null,
            weekEnd: end != null ? DateTime.tryParse(end.toString()) : null,
            acceptRate: (decoded['acceptRate'] as num?)?.toDouble() ?? 0.0,
            cancelRate: (decoded['cancelRate'] as num?)?.toDouble() ?? 0.0,
            acceptedCount: (decoded['acceptedCount'] as num?)?.toInt() ?? 0,
            rejectedCount: (decoded['rejectedCount'] as num?)?.toInt() ?? 0,
            completedTrips: (decoded['completedTrips'] as num?)?.toInt() ?? 0,
            canceledTrips: (decoded['canceledTrips'] as num?)?.toInt() ?? 0,
            canceledTripsStored: decoded.containsKey('canceledTrips'),
            goalTier: tier is String && tier.isNotEmpty ? tier : null,
            targetAcceptRate: (decoded['targetAcceptRate'] as num?)?.toDouble(),
            targetAcceptRateStored: decoded.containsKey('targetAcceptRate'),
            maxCancelRate: (decoded['maxCancelRate'] as num?)?.toDouble(),
            isLegacy: false,
            originRaw: trimmed,
          );
        }
      }
    } catch (_) {
      // Fall through to legacy string parsing
    }
    return WeeklyArchiveEntry.legacy(raw);
  }

  String encode() {
    if (isLegacy && legacyDisplayString != null) {
      return legacyDisplayString!;
    }
    final map = <String, dynamic>{
      'v': 2,
      'weekStart': weekStart?.toIso8601String(),
      'weekEnd': weekEnd?.toIso8601String(),
      'startDate': weekStart?.toIso8601String(),
      'endDate': weekEnd?.toIso8601String(),
      'acceptRate': acceptRate,
      'cancelRate': cancelRate,
      'acceptedCount': acceptedCount,
      'rejectedCount': rejectedCount,
      'completedTrips': completedTrips,
    };
    if (canceledTripsStored) {
      map['canceledTrips'] = canceledTrips;
    }
    if (goalTier != null) {
      map['goalTier'] = goalTier;
    }
    if (targetAcceptRateStored) {
      map['targetAcceptRate'] = targetAcceptRate;
    }
    if (maxCancelRate != null) {
      map['maxCancelRate'] = maxCancelRate;
    }
    return jsonEncode(map);
  }

  /// Prefs line for this entry. Untouched legacy rows keep [originRaw] so a
  /// collapse does not drop the rates from the stored text.
  String toStoredString() {
    if (isLegacy && originRaw != null) return originRaw!;
    return encode();
  }

  String getFormattedDateRange() {
    if (isLegacy) {
      return legacyDisplayString ?? '';
    }
    if (weekStart == null || weekEnd == null) {
      return '';
    }
    final months = S.months;
    final startMonth =
        (weekStart!.month >= 1 && weekStart!.month < months.length)
        ? months[weekStart!.month]
        : '';
    final endMonth = (weekEnd!.month >= 1 && weekEnd!.month < months.length)
        ? months[weekEnd!.month]
        : '';
    if (weekStart!.month == weekEnd!.month) {
      return '${weekStart!.day}-${weekEnd!.day} $endMonth';
    }
    return '${weekStart!.day} $startMonth - ${weekEnd!.day} $endMonth';
  }
}

/// Canceled trips implied by a stored cancellation rate.
///
/// Older JSON rows saved [completedTrips] and [cancelRate] but not the
/// canceled count. `rate = canceled / (completed + canceled)`.
int inferCanceledTrips(int completed, double cancelRate) {
  if (completed <= 0 || cancelRate <= 0 || cancelRate >= 100) return 0;
  final canceled = completed * (cancelRate / (100.0 - cancelRate));
  if (!canceled.isFinite || canceled < 0) return 0;
  return canceled.round();
}

/// Calendar identity of a saved week, ignoring the time of day.
String? weeklyArchiveKey(WeeklyArchiveEntry entry) {
  final start = entry.weekStart;
  if (start != null) {
    return 'week:${start.year}-${start.month}-${start.day}';
  }
  final label = _normalizedLabel(entry);
  if (label.isEmpty) return null;
  return 'label:$label';
}

bool _sameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

String _normalizedLabel(WeeklyArchiveEntry entry) {
  return entry
      .getFormattedDateRange()
      .trim()
      .replaceAll('–', '-')
      .replaceAll('—', '-')
      .replaceAll(RegExp(r'\s+'), ' ');
}

/// True when two rows are the same Monday–Sunday week.
///
/// Dated rows match on the week-start calendar day. A legacy line has no
/// date, so it matches a row with the same visible range unless the years
/// disagree.
bool sameArchiveWeek(WeeklyArchiveEntry a, WeeklyArchiveEntry b) {
  final aStart = a.weekStart;
  final bStart = b.weekStart;
  if (aStart != null && bStart != null) {
    return _sameCalendarDay(aStart, bStart);
  }
  final labelA = _normalizedLabel(a);
  final labelB = _normalizedLabel(b);
  // Legacy rows have no weekStart. The same visible range is one week.
  return labelA.isNotEmpty && labelA == labelB;
}

bool _sameSnapshot(WeeklyArchiveEntry a, WeeklyArchiveEntry b) {
  return a.acceptedCount == b.acceptedCount &&
      a.rejectedCount == b.rejectedCount &&
      a.completedTrips == b.completedTrips &&
      a.resolvedCanceledTrips == b.resolvedCanceledTrips &&
      (a.acceptRate - b.acceptRate).abs() < 0.0001 &&
      (a.cancelRate - b.cancelRate).abs() < 0.0001;
}

double? _preferredTarget(WeeklyArchiveEntry newer, WeeklyArchiveEntry older) {
  if (newer.targetAcceptRateStored) return newer.targetAcceptRate;
  if (older.targetAcceptRateStored) return older.targetAcceptRate;
  return null;
}

/// Combines two saves of one week.
///
/// A second reset in the same week only has the trips taken after the first
/// reset, so differing counters are added. An exact duplicate is kept once.
WeeklyArchiveEntry mergeWeeklyArchiveEntries(
  WeeklyArchiveEntry older,
  WeeklyArchiveEntry newer,
) {
  if (older.hasCountableStats &&
      newer.hasCountableStats &&
      !_sameSnapshot(older, newer)) {
    final accepted = older.acceptedCount + newer.acceptedCount;
    final rejected = older.rejectedCount + newer.rejectedCount;
    final completed = older.completedTrips + newer.completedTrips;
    final canceled = older.resolvedCanceledTrips + newer.resolvedCanceledTrips;
    final requests = accepted + rejected;
    final trips = completed + canceled;
    return WeeklyArchiveEntry(
      weekStart: newer.weekStart ?? older.weekStart,
      weekEnd: newer.weekEnd ?? older.weekEnd,
      acceptRate: requests == 0 ? 100.0 : (accepted / requests) * 100,
      cancelRate: trips == 0 ? 0.0 : (canceled / trips) * 100,
      acceptedCount: accepted,
      rejectedCount: rejected,
      completedTrips: completed,
      canceledTrips: canceled,
      canceledTripsStored: true,
      goalTier: newer.goalTier ?? older.goalTier,
      targetAcceptRate: _preferredTarget(newer, older),
      targetAcceptRateStored:
          newer.targetAcceptRateStored || older.targetAcceptRateStored,
      maxCancelRate: newer.maxCancelRate ?? older.maxCancelRate,
    );
  }

  final useNewer = newer.hasCountableStats || !older.hasCountableStats;
  final counts = useNewer ? newer : older;
  return WeeklyArchiveEntry(
    weekStart:
        counts.weekStart ?? (useNewer ? older.weekStart : newer.weekStart),
    weekEnd: counts.weekEnd ?? (useNewer ? older.weekEnd : newer.weekEnd),
    acceptRate: counts.acceptRate,
    cancelRate: counts.cancelRate,
    acceptedCount: counts.acceptedCount,
    rejectedCount: counts.rejectedCount,
    completedTrips: counts.completedTrips,
    canceledTrips: counts.canceledTripsStored
        ? counts.canceledTrips
        : counts.resolvedCanceledTrips,
    canceledTripsStored: counts.canceledTripsStored,
    isLegacy: counts.isLegacy,
    legacyDisplayString: counts.legacyDisplayString,
    originRaw: counts.originRaw,
    goalTier: newer.goalTier ?? older.goalTier,
    targetAcceptRate: _preferredTarget(newer, older),
    targetAcceptRateStored:
        newer.targetAcceptRateStored || older.targetAcceptRateStored,
    maxCancelRate: newer.maxCancelRate ?? older.maxCancelRate,
  );
}

/// One row per week, oldest first. The merged row keeps the later position.
///
/// Lines that are not merged are returned unchanged, so legacy text keeps
/// the rates that [WeeklyArchiveEntry.encode] would otherwise drop.
List<String> collapseWeeklyArchive(List<String> raw) {
  final entries = <WeeklyArchiveEntry>[];
  final raws = <String?>[];
  for (final line in raw) {
    final entry = WeeklyArchiveEntry.parse(line);
    var index = -1;
    for (var i = entries.length - 1; i >= 0; i--) {
      if (sameArchiveWeek(entries[i], entry)) {
        index = i;
        break;
      }
    }
    if (index < 0) {
      entries.add(entry);
      raws.add(line);
      continue;
    }
    final previous = entries[index];
    final keepLine = _sameSnapshot(previous, entry);
    final merged = mergeWeeklyArchiveEntries(previous, entry);
    entries
      ..removeAt(index)
      ..add(merged);
    raws
      ..removeAt(index)
      ..add(keepLine ? line : null);
  }
  return [
    for (var i = 0; i < entries.length; i++)
      raws[i] ?? entries[i].toStoredString(),
  ];
}

WeeklyGoalFloor _inferWeeklyGoalFloor(int trips, List<WeeklyGoalFloor> floors) {
  var best = floors.first;
  for (final floor in floors) {
    if (trips >= floor.minTrips && floor.minTrips >= best.minTrips) {
      best = floor;
    }
  }
  return best;
}

/// Grades [entry] against the goal saved with it.
///
/// Older rows have no [WeeklyArchiveEntry.goalTier]. A week with completed
/// trips is graded on the bracket those trips land in. A week with no trip
/// count falls back to the goal the driver has selected now.
WeeklyGoalAssessment assessWeeklyGoal(
  WeeklyArchiveEntry entry, {
  required List<WeeklyGoalFloor> floors,
  String? fallbackTier,
  double? fallbackAcceptRate,
  double defaultCancelCeiling = kWeeklyCancelCeiling,
}) {
  final ceiling = entry.maxCancelRate ?? defaultCancelCeiling;
  String? tier = entry.goalTier;
  double? target;
  var resolved = false;

  if (entry.goalTier != null) {
    if (entry.targetAcceptRateStored) {
      target = entry.targetAcceptRate;
      resolved = true;
    } else {
      for (final floor in floors) {
        if (floor.name == entry.goalTier) {
          target = floor.acceptRate;
          resolved = true;
          break;
        }
      }
    }
  }

  if (!resolved) {
    if (entry.completedTrips > 0 && floors.isNotEmpty) {
      final inferred = _inferWeeklyGoalFloor(entry.completedTrips, floors);
      tier = inferred.name;
      target = inferred.acceptRate;
    } else {
      tier = fallbackTier;
      target = fallbackAcceptRate;
    }
  }

  return WeeklyGoalAssessment(
    tierName: tier,
    targetAcceptRate: target,
    maxCancelRate: ceiling,
    acceptMet: target == null || entry.acceptRate >= target,
    cancelMet: entry.cancelRate <= ceiling,
  );
}
