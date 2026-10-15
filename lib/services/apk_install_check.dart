/// Pure checks applied to a downloaded update APK before the system
/// installer is allowed to open. No network and no platform calls, so the
/// hash and version rules can be tested without a device.
enum ApkRejectReason {
  cancelled,
  truncated,
  tooLarge,
  notAnApk,
  hashMismatch,
  packageMismatch,
  versionNotNewer,
  signatureMismatch,
  unreadable,
}

enum UpdateInstallResult { launched, signatureMismatch, rejected }

class ApkInstallDecision {
  const ApkInstallDecision.install() : reason = null;

  const ApkInstallDecision.reject(this.reason);

  final ApkRejectReason? reason;

  bool get shouldInstall => reason == null;
}

/// Package id the downloaded archive must carry. Matches the applicationId.
const String kUpdatePackageName = 'com.ratehelper.app';

/// 64 hex chars, colons and whitespace ignored. Null when [raw] is not a
/// SHA-256 digest.
String? normalizeSha256(String raw) {
  final hex = raw.replaceAll(':', '').replaceAll(RegExp(r'\s'), '').toLowerCase();
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(hex)) return null;
  return hex;
}

/// Manifest field `apk_sha256`. Blank or missing → null (skip the check).
/// A present but unusable value is returned unchanged so the compare fails
/// closed instead of being treated as "field absent".
String? parseOptionalApkSha256(Object? raw) {
  if (raw == null) return null;
  final text = raw.toString().trim();
  if (text.isEmpty) return null;
  return normalizeSha256(text) ?? text;
}

/// One or more SHA-256 cert digests, comma-separated, order-independent.
String? normalizeCertSet(String raw) {
  final parts = raw.split(',');
  final hashes = <String>[];
  for (final part in parts) {
    final hash = normalizeSha256(part);
    if (hash == null) return null;
    hashes.add(hash);
  }
  if (hashes.isEmpty) return null;
  hashes.sort();
  return hashes.join(',');
}

/// Whether [archive] may be handed to the installer.
///
/// [manifestSha256] null means the manifest did not publish `apk_sha256`.
/// That check is skipped. A published hash that does not match the streamed
/// digest is a hard reject.
///
/// [archiveVersionCode] and [installedVersionCode] are Android `versionCode`
/// values (including the split-per-abi offset), not the pubspec build number.
/// The archive must be strictly higher.
ApkInstallDecision decideApkInstall({
  required String archivePackage,
  required int archiveVersionCode,
  required String archiveCertSha256,
  required String installedPackage,
  required int installedVersionCode,
  required String installedCertSha256,
  required String streamedSha256,
  String? manifestSha256,
}) {
  if (manifestSha256 != null) {
    final expected = normalizeSha256(manifestSha256);
    final actual = normalizeSha256(streamedSha256);
    if (expected == null || actual == null || expected != actual) {
      return const ApkInstallDecision.reject(ApkRejectReason.hashMismatch);
    }
  }

  if (archivePackage != kUpdatePackageName ||
      installedPackage != kUpdatePackageName) {
    return const ApkInstallDecision.reject(ApkRejectReason.packageMismatch);
  }

  final archiveCert = normalizeCertSet(archiveCertSha256);
  final installedCert = normalizeCertSet(installedCertSha256);
  if (archiveCert == null ||
      installedCert == null ||
      archiveCert != installedCert) {
    return const ApkInstallDecision.reject(ApkRejectReason.signatureMismatch);
  }

  if (archiveVersionCode <= installedVersionCode) {
    return const ApkInstallDecision.reject(ApkRejectReason.versionNotNewer);
  }

  return const ApkInstallDecision.install();
}

/// Launches the installer only when [decision] allows it, and always drops
/// the cache file. [deleteAfterLaunch] runs only after a successful launch
/// so a rejection never opens the installer first.
Future<UpdateInstallResult> finishApkInstall({
  required ApkInstallDecision decision,
  required Future<bool> Function() launchInstaller,
  required Future<void> Function() deleteFile,
  Future<void> Function()? deleteAfterLaunch,
}) async {
  if (!decision.shouldInstall) {
    await deleteFile();
    if (decision.reason == ApkRejectReason.signatureMismatch) {
      return UpdateInstallResult.signatureMismatch;
    }
    return UpdateInstallResult.rejected;
  }

  final started = await launchInstaller();
  if (!started) {
    await deleteFile();
    return UpdateInstallResult.rejected;
  }

  final after = deleteAfterLaunch;
  if (after != null) {
    await after();
  } else {
    await deleteFile();
  }
  return UpdateInstallResult.launched;
}
