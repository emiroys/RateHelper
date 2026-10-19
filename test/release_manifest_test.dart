import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/services/update_service.dart';

/// Guards the local OTA manifest before it is copied to the live Gist.
///
/// It mirrors the parts of `UpdateService` that decide whether a manifest is
/// usable: version parsing, the release-URL allowlist and the localized notes.
/// It does not pin a version, so it also protects future release bumps.
void main() {
  group('release/update.json', () {
    late Map<String, dynamic> json;

    setUpAll(() {
      final file = File('release/update.json');
      expect(
        file.existsSync(),
        isTrue,
        reason: 'release/update.json must exist for release checks',
      );
      final decoded = jsonDecode(file.readAsStringSync());
      expect(decoded, isA<Map<String, dynamic>>());
      json = decoded as Map<String, dynamic>;
    });

    test('version and build parse with the updater rules', () {
      final latest = json['latest']?.toString().trim() ?? '';
      expect(latest, isNotEmpty);
      final rawBuild = json['build'];
      final build = rawBuild is num
          ? rawBuild.toInt()
          : int.tryParse(rawBuild?.toString().trim() ?? '');
      expect(build, isNotNull);
      expect(build, greaterThan(0));

      final version = AppVersion.parse(latest, build: build);
      expect(version.major, greaterThanOrEqualTo(5));
      expect(version.build, build);
    });

    test('apk_url passes the updater release-URL allowlist', () {
      const releasesPrefix = 'https://github.com/emiroys/ratehelper/releases/';
      final raw = json['apk_url']?.toString().trim() ?? '';
      expect(raw, isNotEmpty);
      expect(raw.startsWith(releasesPrefix), isTrue);

      final uri = Uri.tryParse(raw);
      expect(uri, isNotNull);
      expect(uri!.scheme, 'https');
      expect(uri.host, 'github.com');
      expect(uri.pathSegments, contains('download'));
      expect(uri.pathSegments.last, 'app-arm64-v8a-release.apk');
    });

    test('mandatory flag and all localized OTA notes are present', () {
      expect(json['mandatory'], isA<bool>());
      for (final key in ['notes_tr', 'notes_pl', 'notes_en']) {
        final value = json[key];
        expect(value, isA<String>(), reason: key);
        expect((value! as String).trim(), isNotEmpty, reason: key);
      }
    });

    test('an optional apk_sha256 is either absent or valid lowercase hex', () {
      final raw = json['apk_sha256'];
      if (raw == null) return;
      final value = raw.toString().trim();
      expect(RegExp(r'^[a-f0-9]{64}$').hasMatch(value), isTrue);
    });
  });
}
