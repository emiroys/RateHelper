import 'dart:convert';
import '../l10n.dart';

class WeeklyArchiveEntry {
  final DateTime? weekStart;
  final DateTime? weekEnd;
  final double acceptRate;
  final double cancelRate;
  final int acceptedCount;
  final int rejectedCount;
  final int completedTrips;
  final bool isLegacy;
  final String? legacyDisplayString;

  DateTime? get startDate => weekStart;
  DateTime? get endDate => weekEnd;

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
    this.isLegacy = false,
    this.legacyDisplayString,
  })  : weekStart = weekStart ?? startDate,
        weekEnd = weekEnd ?? endDate;

  factory WeeklyArchiveEntry.legacy(String rawString) {
    double aRate = 0.0;
    double cRate = 0.0;
    String header = rawString;

    if (rawString.contains(':')) {
      final parts = rawString.split(':');
      header = parts.first.trim();
    }
    final matches =
        RegExp(r'%([0-9]+(?:\.[0-9]+)?)').allMatches(rawString).toList();
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
          return WeeklyArchiveEntry(
            weekStart:
                start != null ? DateTime.tryParse(start.toString()) : null,
            weekEnd: end != null ? DateTime.tryParse(end.toString()) : null,
            acceptRate: (decoded['acceptRate'] as num?)?.toDouble() ?? 0.0,
            cancelRate: (decoded['cancelRate'] as num?)?.toDouble() ?? 0.0,
            acceptedCount: (decoded['acceptedCount'] as num?)?.toInt() ?? 0,
            rejectedCount: (decoded['rejectedCount'] as num?)?.toInt() ?? 0,
            completedTrips: (decoded['completedTrips'] as num?)?.toInt() ?? 0,
            isLegacy: false,
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
    return jsonEncode({
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
    });
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
    final endMonth =
        (weekEnd!.month >= 1 && weekEnd!.month < months.length)
            ? months[weekEnd!.month]
            : '';
    if (weekStart!.month == weekEnd!.month) {
      return '${weekStart!.day}-${weekEnd!.day} $endMonth';
    }
    return '${weekStart!.day} $startMonth - ${weekEnd!.day} $endMonth';
  }
}
