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

  group('UpdateService.pubspecBuildNumber', () {
    test('strips the --split-per-abi versionCode offset', () {
      // armeabi-v7a, arm64-v8a and x86_64 codes for pubspec build 5.
      expect(UpdateService.pubspecBuildNumber('1005'), 5);
      expect(UpdateService.pubspecBuildNumber('2005'), 5);
      expect(UpdateService.pubspecBuildNumber('4005'), 5);
    });

    test('leaves a universal APK versionCode alone', () {
      expect(UpdateService.pubspecBuildNumber('5'), 5);
    });

    test('a manifest build matching pubspec is not seen as an update', () {
      // Regression: the arm64 APK reports 2005, so an un-normalized compare
      // made manifest build 5 look older than the installed build.
      final installed = AppVersion.parse(
        '5.0.0',
        build: UpdateService.pubspecBuildNumber('2005'),
      );
      expect(
        AppVersion.parse('5.0.0', build: 5).isNewerThan(installed),
        isFalse,
      );
      expect(
        AppVersion.parse('5.0.0', build: 6).isNewerThan(installed),
        isTrue,
      );
    });

    test('unparseable or missing versionCode is unknown, not zero', () {
      expect(UpdateService.pubspecBuildNumber(''), isNull);
      expect(UpdateService.pubspecBuildNumber('unknown'), isNull);
    });
  });

  group('unknown build numbers', () {
    test('a bare release tag is not treated as a downgrade', () {
      // Regression: git tags publish no build number. Treating the missing
      // value as 0 made `v5.0.0` rank below the installed `5.0.0+5`, so a
      // failed manifest fetch fell through to the Releases API and reported
      // "you are on the latest version" instead of admitting it had failed.
      final installed = AppVersion.parse('5.0.0', build: 5);
      final tagged = AppVersion.parse('v5.0.0');

      expect(tagged.build, isNull);
      expect(tagged.isNewerThan(installed), isFalse);
      expect(installed.isNewerThan(tagged), isFalse);
    });

    test('the semver triple still decides when a build is unknown', () {
      final installed = AppVersion.parse('5.0.0', build: 5);
      expect(AppVersion.parse('v5.0.1').isNewerThan(installed), isTrue);
      expect(AppVersion.parse('v4').isNewerThan(installed), isFalse);
    });

    test('equality stays strict even though ordering is lenient', () {
      expect(AppVersion.parse('5.0.0+5') == AppVersion.parse('5.0.0'), isFalse);
      expect(AppVersion.parse('5.0.0') == AppVersion.parse('5.0.0'), isTrue);
    });
  });
}
