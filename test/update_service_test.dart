import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/services/update_service.dart';

void main() {
  group('AppVersion.parse', () {
    test('accepts the bare tags this repo has published', () {
      expect(AppVersion.parse('v4'), const AppVersion(4, 0, 0));
      expect(AppVersion.parse('V5.0'), const AppVersion(5, 0, 0));
      expect(AppVersion.parse('5.0.1'), const AppVersion(5, 0, 1));
    });

    test('splits build number and pre-release suffix', () {
      expect(AppVersion.parse('5.0.1+7'), const AppVersion(5, 0, 1, 7));
      expect(AppVersion.parse('5.0.1-beta.2'), const AppVersion(5, 0, 1));
    });

    test('an explicit build number wins over the +suffix', () {
      expect(
        AppVersion.parse('5.0.1+7', build: 9),
        const AppVersion(5, 0, 1, 9),
      );
    });

    test('garbage degrades to zero instead of throwing', () {
      expect(AppVersion.parse(''), AppVersion.zero);
      expect(AppVersion.parse('latest'), AppVersion.zero);
      expect(AppVersion.parse('5.x.1'), const AppVersion(5, 0, 0));
    });
  });

  group('AppVersion comparison', () {
    test('compares numerically, not lexically', () {
      expect(
        AppVersion.parse('1.0.10').isNewerThan(AppVersion.parse('1.0.9')),
        isTrue,
      );
      expect(
        AppVersion.parse('1.10.0').isNewerThan(AppVersion.parse('1.9.9')),
        isTrue,
      );
    });

    test('an equal version is never an update', () {
      expect(
        AppVersion.parse('5.0.0+5').isNewerThan(AppVersion.parse('5.0.0+5')),
        isFalse,
      );
      expect(
        AppVersion.parse('v5.0.0').isNewerThan(AppVersion.parse('5.0.0')),
        isFalse,
      );
    });

    test('build number breaks a semver tie so hotfix APKs still ship', () {
      expect(
        AppVersion.parse('5.0.0+6').isNewerThan(AppVersion.parse('5.0.0+5')),
        isTrue,
      );
    });

    test('a downgrade is never offered', () {
      expect(
        AppVersion.parse('4.9.9').isNewerThan(AppVersion.parse('5.0.0')),
        isFalse,
      );
    });

    test('label drops the build number, toString keeps it', () {
      expect(AppVersion.parse('5.0.1+7').label, '5.0.1');
      expect(AppVersion.parse('5.0.1+7').toString(), '5.0.1+7');
    });
  });
}
