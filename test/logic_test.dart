import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/l10n.dart';

// Pure logic extracted for testing — mirrors _HomeScreenState getters and helpers.

double acceptanceRate(int accepted, int rejected) {
  final total = accepted + rejected;
  return total == 0 ? 100.0 : (accepted / total) * 100;
}

double cancellationRate(int completed, int canceled) {
  final total = completed + canceled;
  return total == 0 ? 0.0 : (canceled / total) * 100;
}

List<int> parseVersionParts(String version) {
  var core = version.trim();
  if (core.startsWith('v') || core.startsWith('V')) {
    core = core.substring(1).trim();
  }
  core = core.split('+').first.split('-').first.trim();
  final parts = <int>[];
  for (final segment in core.split('.')) {
    final parsed = int.tryParse(segment.trim());
    if (parsed == null) break;
    parts.add(parsed);
  }
  while (parts.length < 3) {
    parts.add(0);
  }
  return parts.take(3).toList();
}

bool isVersionNewer(String latest, String current) {
  final latestParts = parseVersionParts(latest);
  final currentParts = parseVersionParts(current);
  for (var i = 0; i < 3; i++) {
    if (latestParts[i] > currentParts[i]) return true;
    if (latestParts[i] < currentParts[i]) return false;
  }
  return false;
}

DateTime lastMonday4am(DateTime now) {
  final daysFromMonday = (now.weekday - DateTime.monday) % 7;
  final monday = DateTime(now.year, now.month, now.day - daysFromMonday, 4, 0, 0);
  if (now.isBefore(monday)) {
    return monday.subtract(const Duration(days: 7));
  }
  return monday;
}

void main() {
  group('acceptanceRate', () {
    test('returns 100.0 when both are 0 (no data)', () {
      expect(acceptanceRate(0, 0), 100.0);
    });

    test('returns 100.0 when all accepted, none rejected', () {
      expect(acceptanceRate(10, 0), 100.0);
    });

    test('returns 0.0 when all rejected, none accepted', () {
      expect(acceptanceRate(0, 10), 0.0);
    });

    test('returns 80.0 for 8 accepted, 2 rejected', () {
      expect(acceptanceRate(8, 2), closeTo(80.0, 0.001));
    });

    test('returns 50.0 for equal accepted and rejected', () {
      expect(acceptanceRate(5, 5), closeTo(50.0, 0.001));
    });

    test('handles large values without overflow', () {
      expect(acceptanceRate(99999, 1), closeTo(99.999, 0.001));
    });

    test('never returns NaN or Infinity', () {
      final result = acceptanceRate(0, 0);
      expect(result.isNaN, false);
      expect(result.isInfinite, false);
    });
  });

  group('cancellationRate', () {
    test('returns 0.0 when both are 0 (no data)', () {
      expect(cancellationRate(0, 0), 0.0);
    });

    test('returns 0.0 when all completed, none canceled', () {
      expect(cancellationRate(10, 0), 0.0);
    });

    test('returns 100.0 when all canceled, none completed', () {
      expect(cancellationRate(0, 10), 100.0);
    });

    test('returns 5.0 for 1 canceled out of 20 trips', () {
      expect(cancellationRate(19, 1), closeTo(5.0, 0.001));
    });

    test('handles large values without overflow', () {
      expect(cancellationRate(1, 99999), closeTo(99.999, 0.01));
    });

    test('never returns NaN or Infinity', () {
      final result = cancellationRate(0, 0);
      expect(result.isNaN, false);
      expect(result.isInfinite, false);
    });
  });

  group('isVersionNewer', () {
    test('1.0.1 is newer than 1.0.0', () {
      expect(isVersionNewer('1.0.1', '1.0.0'), true);
    });

    test('1.0.0 is not newer than 1.0.0 (equal)', () {
      expect(isVersionNewer('1.0.0', '1.0.0'), false);
    });

    test('1.0.0 is not newer than 1.0.1 (older)', () {
      expect(isVersionNewer('1.0.0', '1.0.1'), false);
    });

    test('1.0.10 is newer than 1.0.9 (numeric not string)', () {
      expect(isVersionNewer('1.0.10', '1.0.9'), true);
    });

    test('1.0.9 is not newer than 1.0.10', () {
      expect(isVersionNewer('1.0.9', '1.0.10'), false);
    });

    test('strips v prefix and build metadata from current', () {
      expect(isVersionNewer('1.0.2', 'v1.0.1+5'), true);
      expect(isVersionNewer('1.0.2', '1.0.2+99'), false);
    });
  });

  group('lastMonday4am', () {
    test('Monday at 04:01 returns same Monday 04:00', () {
      final now = DateTime(2024, 6, 3, 4, 1); // Mon Jun 3, 2024, 04:01
      final result = lastMonday4am(now);
      expect(result, DateTime(2024, 6, 3, 4, 0, 0));
    });

    test('Monday at exactly 04:00 returns same Monday 04:00', () {
      final now = DateTime(2024, 6, 3, 4, 0, 0);
      final result = lastMonday4am(now);
      expect(result, DateTime(2024, 6, 3, 4, 0, 0));
    });

    test('Monday at 03:59 returns PREVIOUS Monday 04:00', () {
      final now = DateTime(2024, 6, 3, 3, 59); // Mon Jun 3, 2024, 03:59
      final result = lastMonday4am(now);
      expect(result, DateTime(2024, 5, 27, 4, 0, 0));
    });

    test('Sunday returns the Monday that started that week', () {
      final now = DateTime(2024, 6, 9, 22, 0); // Sun Jun 9, 2024
      final result = lastMonday4am(now);
      expect(result, DateTime(2024, 6, 3, 4, 0, 0));
    });

    test('Wednesday mid-week returns preceding Monday', () {
      final now = DateTime(2024, 6, 5, 15, 30); // Wed Jun 5, 2024
      final result = lastMonday4am(now);
      expect(result, DateTime(2024, 6, 3, 4, 0, 0));
    });

    test('handles month boundary — e.g. Tuesday March 1', () {
      final now = DateTime(2024, 3, 1, 12, 0); // Fri actually, but let's use a Tue
      // March 1, 2024 is a Friday. daysFromMonday = 4. Monday = Feb 26.
      final result = lastMonday4am(now);
      expect(result, DateTime(2024, 2, 26, 4, 0, 0));
    });

    test('handles year boundary — e.g. Wednesday January 1, 2025', () {
      // Jan 1, 2025 is a Wednesday. Previous Monday = Dec 30, 2024.
      final now = DateTime(2025, 1, 1, 10, 0);
      final result = lastMonday4am(now);
      expect(result, DateTime(2024, 12, 30, 4, 0, 0));
    });

    test('handles Saturday at midnight', () {
      final now = DateTime(2024, 6, 8, 0, 0); // Sat Jun 8, 2024 midnight
      final result = lastMonday4am(now);
      expect(result, DateTime(2024, 6, 3, 4, 0, 0));
    });

    test('result weekday is always Monday', () {
      for (int day = 1; day <= 31; day++) {
        final now = DateTime(2024, 7, day, 12, 0);
        final result = lastMonday4am(now);
        expect(result.weekday, DateTime.monday,
            reason: 'Failed for July $day, 2024');
        expect(result.hour, 4);
        expect(result.minute, 0);
      }
    });
  });

  group('S.formatPercent locale percentage placement', () {
    test('Turkish uses leading percent sign', () {
      S.setLang(AppLang.tr);
      expect(S.formatPercent('100'), '%100');
      expect(S.formatPercent('85.5'), '%85.5');
    });

    test('English uses trailing percent sign', () {
      S.setLang(AppLang.en);
      expect(S.formatPercent('100'), '100%');
      expect(S.formatPercent('85.5'), '85.5%');
    });

    test('Polish uses trailing percent sign', () {
      S.setLang(AppLang.pl);
      expect(S.formatPercent('100'), '100%');
      expect(S.formatPercent('85.5'), '85.5%');
    });
  });
}
