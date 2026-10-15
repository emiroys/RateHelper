import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/services/apk_install_check.dart';
import 'package:rate_helper/services/update_service.dart';

void main() {
  final releaseCert = 'ab' * 32;
  final debugCert = 'cd' * 32;
  final digest = '11' * 32;

  ApkInstallDecision trusted({
    String? archiveCert,
    String? installedCert,
    int archiveVersionCode = 2010,
    int installedVersionCode = 2009,
    String? manifestSha256,
    bool manifestHash = true,
    String? streamedSha256,
    String archivePackage = kUpdatePackageName,
  }) {
    return decideApkInstall(
      archivePackage: archivePackage,
      archiveVersionCode: archiveVersionCode,
      archiveCertSha256: archiveCert ?? releaseCert,
      installedPackage: kUpdatePackageName,
      installedVersionCode: installedVersionCode,
      installedCertSha256: installedCert ?? releaseCert,
      streamedSha256: streamedSha256 ?? digest,
      manifestSha256: manifestHash ? (manifestSha256 ?? digest) : null,
    );
  }

  group('decideApkInstall', () {
    test('a higher versionCode with the same certificate may install', () {
      expect(trusted().shouldInstall, isTrue);
    });

    test('a missing manifest hash is not a failure', () {
      expect(trusted(manifestHash: false).shouldInstall, isTrue);
      expect(parseOptionalApkSha256(null), isNull);
      expect(parseOptionalApkSha256('   '), isNull);
    });

    test('a published hash must match the streamed digest', () {
      final decision = trusted(manifestSha256: '22' * 32);
      expect(decision.shouldInstall, isFalse);
      expect(decision.reason, ApkRejectReason.hashMismatch);
    });

    test('colon-separated certificate hashes still match', () {
      final colonated = releaseCert
          .toUpperCase()
          .replaceAllMapped(RegExp(r'..'), (m) => '${m[0]}:')
          .replaceFirst(RegExp(r':$'), '');
      expect(
        trusted(archiveCert: colonated, manifestHash: false).shouldInstall,
        isTrue,
      );
    });

    test('versionCode must be strictly higher', () {
      expect(
        trusted(archiveVersionCode: 2009, installedVersionCode: 2009).reason,
        ApkRejectReason.versionNotNewer,
      );
      expect(
        trusted(archiveVersionCode: 2008, installedVersionCode: 2009).reason,
        ApkRejectReason.versionNotNewer,
      );
    });

    test('a different package name is rejected', () {
      expect(
        trusted(archivePackage: 'com.example.other').reason,
        ApkRejectReason.packageMismatch,
      );
    });
  });

  group('finishApkInstall', () {
    test('a valid update launches the installer and then deletes the file', () async {
      final order = <String>[];
      final result = await finishApkInstall(
        decision: trusted(),
        launchInstaller: () async {
          order.add('launch');
          return true;
        },
        deleteFile: () async {
          order.add('delete');
        },
      );

      expect(result, UpdateInstallResult.launched);
      expect(order, ['launch', 'delete']);
    });

    test('a debug-signed APK is rejected before the installer opens', () async {
      var launched = false;
      var deleted = false;
      final result = await finishApkInstall(
        decision: trusted(archiveCert: debugCert, manifestHash: false),
        launchInstaller: () async {
          launched = true;
          return true;
        },
        deleteFile: () async {
          deleted = true;
        },
      );

      expect(trusted(archiveCert: debugCert, manifestHash: false).reason,
          ApkRejectReason.signatureMismatch);
      expect(result, UpdateInstallResult.signatureMismatch);
      expect(launched, isFalse);
      expect(deleted, isTrue);
    });
  });

  group('consumeApkDownload', () {
    late Directory tmp;

    setUp(() async {
      tmp = await Directory.systemTemp.createTemp('apk_download');
    });

    tearDown(() async {
      try {
        await tmp.delete(recursive: true);
      } catch (_) {}
    });

    test('a complete zip-like body is kept and hashed in one pass', () async {
      final payload = <int>[0x50, 0x4B, 3, 4, 9, 8, 7];
      final file = File('${tmp.path}${Platform.pathSeparator}update.apk');

      final write = await UpdateService.consumeApkDownload(
        bytes: Stream<List<int>>.value(payload),
        file: file,
        contentLength: payload.length,
      );

      expect(write.accepted, isTrue);
      expect(write.sha256, sha256.convert(payload).toString());
      expect(await file.exists(), isTrue);
      expect(await file.length(), payload.length);
    });

    test('a truncated download is rejected and the file is deleted', () async {
      final file = File('${tmp.path}${Platform.pathSeparator}partial.apk');
      final write = await UpdateService.consumeApkDownload(
        bytes: Stream<List<int>>.value(<int>[0x50, 0x4B, 1, 2]),
        file: file,
        contentLength: 100,
      );

      expect(write.accepted, isFalse);
      expect(write.reject, ApkRejectReason.truncated);
      expect(await file.exists(), isFalse);
    });

    test('a body over the size cap is rejected', () async {
      final file = File('${tmp.path}${Platform.pathSeparator}huge.apk');
      final write = await UpdateService.consumeApkDownload(
        bytes: Stream<List<int>>.value(<int>[0x50, 0x4B, 1, 2, 3, 4, 5, 6, 7]),
        file: file,
        maxBytes: 8,
      );

      expect(write.reject, ApkRejectReason.tooLarge);
      expect(await file.exists(), isFalse);
    });
  });
}
