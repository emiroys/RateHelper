import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/services/github_http.dart';
import 'package:rate_helper/services/update_service.dart';
import 'package:rate_helper/update_dialog.dart';

class _RealHttp extends HttpOverrides {}

const _capitalizedApkUrl =
    'https://github.com/emiroys/RateHelper/releases/download/v5.1.0/app-arm64-v8a-release.apk';

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

  group('UpdateService.sweepUpdateCache', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('update_sweep');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('clears a previous download', () async {
      final apk = File('${tmp.path}${Platform.pathSeparator}old.apk');
      await apk.writeAsBytes(List<int>.filled(64, 0x50));
      final nested = Directory('${tmp.path}${Platform.pathSeparator}nested');
      await nested.create();
      await File(
        '${nested.path}${Platform.pathSeparator}a.tmp',
      ).writeAsString('x');

      await UpdateService.instance.sweepUpdateCache(tmp);

      expect(await tmp.list().isEmpty, isTrue);
      expect(await tmp.exists(), isTrue);
    });

    test('a non-empty directory sweep never throws', () async {
      // Regression: the sweep used to delete entries while the directory
      // stream was still open and treated any failure as a failed update, so
      // every attempt after the first one fell back to the browser.
      for (var i = 0; i < 25; i++) {
        await File(
          '${tmp.path}${Platform.pathSeparator}f$i.apk',
        ).writeAsString('payload $i');
      }
      await expectLater(
        UpdateService.instance.sweepUpdateCache(tmp),
        completes,
      );
      expect(await tmp.list().isEmpty, isTrue);
    });

    test('a missing directory is not an error', () async {
      final gone = Directory('${tmp.path}${Platform.pathSeparator}absent');
      await expectLater(
        UpdateService.instance.sweepUpdateCache(gone),
        completes,
      );
    });
  });

  group('APK URL allowlist', () {
    final service = UpdateService.instance;

    test('accepts the canonical repo capitalization used by the live Gist', () {
      // Regression: the live Gist published
      // github.com/emiroys/RateHelper/... and the old case-sensitive prefix
      // check rejected it, so a perfectly valid 200 manifest looked unreachable.
      expect(
        service.sanitizeApkUrlForTest(
          'https://github.com/emiroys/RateHelper/releases/download/v5.1.0/app-arm64-v8a-release.apk',
        ),
        isNotNull,
      );
    });

    test('accepts lowercase owner/repo and every known asset name', () {
      for (final file in [
        'app-arm64-v8a-release.apk',
        'app-universal-release.apk',
        'app-release.apk',
      ]) {
        expect(
          service.sanitizeApkUrlForTest(
            'https://github.com/emiroys/ratehelper/releases/download/v5.1.0/$file',
          ),
          isNotNull,
          reason: file,
        );
      }
    });

    test('rejects wrong hosts, paths, owners and asset names', () {
      for (final url in [
        'http://github.com/emiroys/RateHelper/releases/download/v5.1.0/app-arm64-v8a-release.apk',
        'https://evil.example/emiroys/ratehelper/releases/download/v5.1.0/app-arm64-v8a-release.apk',
        'https://github.com.evil.example/emiroys/ratehelper/releases/download/v5.1.0/app-arm64-v8a-release.apk',
        'https://github.com/evil/ratehelper/releases/download/v5.1.0/app-arm64-v8a-release.apk',
        'https://github.com/emiroys/other/releases/download/v5.1.0/app-arm64-v8a-release.apk',
        'https://github.com/emiroys/ratehelper/releases/tag/v5.1.0',
        'https://github.com/emiroys/ratehelper/releases/download/v5.1.0/steal.apk',
        'https://github.com/emiroys/ratehelper/releases/download/v5.1.0/app-arm64-v8a-release.apk/',
      ]) {
        expect(service.sanitizeApkUrlForTest(url), isNull, reason: url);
      }
    });
  });

  group('manifest parsing', () {
    final service = UpdateService.instance;

    Map<String, dynamic> manifest({Object? apkUrl = _capitalizedApkUrl}) => {
      'latest': '5.1.0',
      'build': 10,
      'apk_url': apkUrl,
      'mandatory': false,
      'notes_pl': 'Notatki',
      'notes_en': 'Notes',
    };

    test(
      'a valid 200-style payload is accepted with canonical casing',
      () async {
        final info = await service.parseManifestForTest(
          manifest(),
          languageCode: 'pl',
        );
        expect(info.version, const AppVersion(5, 1, 0, 10));
        expect(info.apkUrl.toString(), _capitalizedApkUrl);
        expect(info.mandatory, isFalse);
        expect(info.notes, 'Notatki');
      },
    );

    test('missing latest is an invalid manifest', () async {
      await expectLater(
        service.parseManifestForTest(manifest()..remove('latest')),
        throwsA(
          isA<UpdateFetchException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.invalidManifest,
          ),
        ),
      );
    });

    test('an unsafe apk_url is an invalid manifest', () async {
      await expectLater(
        service.parseManifestForTest(
          manifest(apkUrl: 'https://evil.example/app-arm64-v8a-release.apk'),
        ),
        throwsA(
          isA<UpdateFetchException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.invalidManifest,
          ),
        ),
      );
    });

    test('a non-version latest is an invalid manifest', () async {
      await expectLater(
        service.parseManifestForTest(manifest()..['latest'] = 'latest'),
        throwsA(
          isA<UpdateFetchException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.invalidManifest,
          ),
        ),
      );
    });
  });

  group('update HTTP failures', () {
    late HttpServer server;

    setUp(() async {
      GithubHttp.reset();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        switch (request.uri.path) {
          case '/ok':
            request.response.headers.contentType = ContentType.json;
            request.response.write('{"latest":"5.1.0","build":10}');
          case '/bad-json':
            request.response.write('not json');
          case '/array':
            request.response.write('[]');
          case '/error':
            request.response.statusCode = HttpStatus.serviceUnavailable;
            request.response.write('down');
          case '/redirect':
            request.response.statusCode = HttpStatus.found;
            request.response.headers.set(HttpHeaders.locationHeader, '/ok');
          default:
            request.response.statusCode = HttpStatus.notFound;
        }
        await request.response.close();
      });
    });

    tearDown(() async {
      await server.close(force: true);
      GithubHttp.reset();
    });

    Future<Map<String, dynamic>> fetch(String path) {
      return HttpOverrides.runWithHttpOverrides(
        () => UpdateService.instance.fetchJsonForTest(
          Uri.parse('http://127.0.0.1:${server.port}$path'),
        ),
        _RealHttp(),
      );
    }

    test('HTTP 200 with an object succeeds', () async {
      expect(await fetch('/ok'), {'latest': '5.1.0', 'build': 10});
    });

    test('non-200 is classified as httpStatus', () async {
      await expectLater(
        fetch('/error'),
        throwsA(
          isA<UpdateFetchException>()
              .having((e) => e.failure, 'failure', UpdateFailure.httpStatus)
              .having((e) => e.statusCode, 'statusCode', 503),
        ),
      );
    });

    test('invalid JSON is classified as invalidJson', () async {
      await expectLater(
        fetch('/bad-json'),
        throwsA(
          isA<UpdateFetchException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.invalidJson,
          ),
        ),
      );
    });

    test('valid JSON that is not an object is an invalid manifest', () async {
      await expectLater(
        fetch('/array'),
        throwsA(
          isA<UpdateFetchException>().having(
            (e) => e.failure,
            'failure',
            UpdateFailure.invalidManifest,
          ),
        ),
      );
    });

    test('a redirect is refused and classified as httpStatus', () async {
      await expectLater(
        fetch('/redirect'),
        throwsA(
          isA<UpdateFetchException>()
              .having((e) => e.failure, 'failure', UpdateFailure.httpStatus)
              .having((e) => e.statusCode, 'statusCode', 302),
        ),
      );
    });

    test('connection failures are classified as network', () async {
      final closed = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final port = closed.port;
      await closed.close(force: true);
      await HttpOverrides.runWithHttpOverrides(
        () => expectLater(
          UpdateService.instance.fetchJsonForTest(
            Uri.parse('http://127.0.0.1:$port/update.json'),
          ),
          throwsA(
            isA<UpdateFetchException>().having(
              (e) => e.failure,
              'failure',
              UpdateFailure.network,
            ),
          ),
        ),
        _RealHttp(),
      );
    });
  });

  group('update failure messages', () {
    tearDown(() => S.setLang(AppLang.tr));

    test('every failure reason has a distinct localized message', () {
      for (final lang in AppLang.values) {
        S.setLang(lang);
        final messages = UpdateFailure.values.map(updateFailureMessage).toSet();
        expect(messages.length, UpdateFailure.values.length, reason: lang.name);
        for (final message in messages) {
          expect(message.trim(), isNotEmpty);
        }
      }
    });

    test('an unknown failure keeps the generic message', () {
      S.setLang(AppLang.tr);
      expect(updateFailureMessage(null), S.updateUnreachable);
    });
  });
}
