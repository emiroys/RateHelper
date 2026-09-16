import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../env.dart';

/// Outcome of a single update check.
enum UpdateStatus {
  /// Installed build is the newest published one.
  upToDate,

  /// A strictly newer build exists and [UpdateCheckResult.info] is set.
  available,

  /// Manifest and fallback were both unreachable (offline, DNS, timeout,
  /// malformed JSON, missing release asset). Never surfaced on startup.
  unreachable,

  /// No manifest URL is baked into this build, so checking is impossible.
  disabled,
}

/// `major.minor.patch` plus the pubspec build number, compared numerically.
///
/// String comparison would rank `1.0.10` below `1.0.9`, and tags in this repo
/// are published both bare (`v4`) and full (`v5.0.1`), so every field is
/// zero-filled before comparing.
class AppVersion implements Comparable<AppVersion> {
  const AppVersion(this.major, this.minor, this.patch, [this.build = 0]);

  final int major;
  final int minor;
  final int patch;

  /// Android `versionCode`. Only consulted when the semver triples tie, so a
  /// hotfix APK republished under the same version name still wins.
  final int build;

  static const AppVersion zero = AppVersion(0, 0, 0);

  /// Tolerates `v5`, `V5.0`, `5.0.1`, `5.0.1+7`, `5.0.1-beta.2`.
  /// Returns [zero] for anything unparseable so callers never throw.
  factory AppVersion.parse(String raw, {int? build}) {
    var core = raw.trim();
    if (core.startsWith('v') || core.startsWith('V')) {
      core = core.substring(1).trim();
    }

    final plusSplit = core.split('+');
    core = plusSplit.first.split('-').first.trim();

    final parsedBuild = build ??
        (plusSplit.length > 1 ? int.tryParse(plusSplit[1].trim()) ?? 0 : 0);

    final fields = <int>[];
    for (final segment in core.split('.')) {
      final value = int.tryParse(segment.trim());
      if (value == null) break;
      fields.add(value);
    }
    while (fields.length < 3) {
      fields.add(0);
    }

    return AppVersion(fields[0], fields[1], fields[2], parsedBuild);
  }

  @override
  int compareTo(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    if (patch != other.patch) return patch.compareTo(other.patch);
    return build.compareTo(other.build);
  }

  bool isNewerThan(AppVersion other) => compareTo(other) > 0;

  String get label => '$major.$minor.$patch';

  @override
  String toString() => build > 0 ? '$label+$build' : label;

  @override
  bool operator ==(Object other) =>
      other is AppVersion && compareTo(other) == 0;

  @override
  int get hashCode => Object.hash(major, minor, patch, build);
}

/// A published release the driver can install.
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.displayVersion,
    required this.apkUrl,
    required this.mandatory,
    this.notes,
  });

  final AppVersion version;

  /// Tag exactly as published (`v5.0.1`), for the dialog header.
  final String displayVersion;

  final Uri apkUrl;

  /// Blocks dismissal — reserved for releases that fix data corruption.
  final bool mandatory;

  /// Short localized changelog, already picked for the active language.
  final String? notes;
}

class UpdateCheckResult {
  const UpdateCheckResult(this.status, this.current, [this.info]);

  final UpdateStatus status;
  final AppVersion current;
  final UpdateInfo? info;
}

/// Checks GitHub for a newer sideloaded APK and hands the download to the
/// system browser.
///
/// Source of truth is a static JSON manifest (see [Env.gistUrl]) rather than
/// `api.github.com/releases/latest`: the API allows only 60 unauthenticated
/// requests per hour per IP, and shared mobile-carrier NAT makes that budget
/// unpredictable. A raw Gist / GitHub Pages file is CDN-served, unmetered, and
/// can carry fields the Releases API has no place for (`mandatory`, per-ABI
/// asset map, localized notes). The Releases API is kept only as a fallback
/// for when the manifest itself is unreachable.
class UpdateService {
  UpdateService._();

  static final UpdateService instance = UpdateService._();

  /// Repository that owns every release we are willing to install.
  static const String _repoSlug = 'emiroys/ratehelper';

  static const String _releasesPrefix =
      'https://github.com/$_repoSlug/releases/';

  static final Uri _releasesApi = Uri.https(
    'api.github.com',
    '/repos/$_repoSlug/releases/latest',
  );

  /// Hosts the hardened [HttpClient] may talk to. A hijacked manifest URL,
  /// hostile WiFi, or a 30x Location header cannot steer us off this list
  /// because the host is re-derived and redirects are refused per request.
  static const Set<String> _allowedMetadataHosts = {
    'gist.githubusercontent.com',
    'raw.githubusercontent.com',
    'api.github.com',
  };

  /// Release assets we know how to install, most specific first. The driver's
  /// device is arm64, but a fat APK still installs correctly, so a manifest
  /// that only ships `app-release.apk` keeps working.
  static const List<String> _apkAssetPreference = [
    'app-arm64-v8a-release.apk',
    'app-universal-release.apk',
    'app-release.apk',
  ];

  /// Per-ABI keys understood inside the manifest's optional `apk_urls` map.
  static const List<String> _abiPreference = [
    'arm64-v8a',
    'universal',
    'armeabi-v7a',
  ];

  static const String _keySkippedVersion = 'update_skipped_version';
  static const String _keyLastPromptMs = 'update_last_prompt_ms';

  /// A dismissed prompt stays quiet this long, so a driver who taps "Daha
  /// Sonra" mid-shift is not nagged at every cold start.
  static const Duration _promptCooldown = Duration(hours: 12);

  static const Duration _connectTimeout = Duration(seconds: 8);
  static const Duration _readTimeout = Duration(seconds: 10);

  AppVersion? _installed;

  /// Installed version from the APK itself — never from a hardcoded constant,
  /// which is how the footer and the release tags drifted apart before.
  Future<AppVersion> installedVersion() async {
    final cached = _installed;
    if (cached != null) return cached;
    try {
      final info = await PackageInfo.fromPlatform();
      final resolved = AppVersion.parse(
        info.version,
        build: int.tryParse(info.buildNumber.trim()) ?? 0,
      );
      _installed = resolved;
      return resolved;
    } catch (_) {
      return AppVersion.zero;
    }
  }

  /// Startup path: silent, non-blocking, and suppressed by the cooldown or by
  /// a version the driver chose to skip. Mandatory releases ignore both.
  Future<UpdateCheckResult> checkOnStartup({String? languageCode}) async {
    final result = await check(languageCode: languageCode);
    if (result.status != UpdateStatus.available) return result;

    final info = result.info!;
    if (info.mandatory) return result;

    final prefs = await _prefs();
    if (prefs != null) {
      if (prefs.getString(_keySkippedVersion) == info.displayVersion) {
        return UpdateCheckResult(UpdateStatus.upToDate, result.current);
      }
      final lastPrompt = prefs.getInt(_keyLastPromptMs) ?? 0;
      final elapsed = DateTime.now().millisecondsSinceEpoch - lastPrompt;
      if (lastPrompt > 0 && elapsed < _promptCooldown.inMilliseconds) {
        return UpdateCheckResult(UpdateStatus.upToDate, result.current);
      }
    }
    return result;
  }

  /// Manual path: ignores cooldown and skip state, and reports failures so the
  /// footer tile can say "sunucuya ulaşılamadı" instead of lying.
  Future<UpdateCheckResult> check({String? languageCode}) async {
    final current = await installedVersion();

    if (Env.gistUrl.trim().isEmpty) {
      return UpdateCheckResult(UpdateStatus.disabled, current);
    }

    var info = await _fromManifest(languageCode: languageCode);
    info ??= await _fromReleasesApi();
    if (info == null) return UpdateCheckResult(UpdateStatus.unreachable, current);

    if (!info.version.isNewerThan(current)) {
      return UpdateCheckResult(UpdateStatus.upToDate, current);
    }
    return UpdateCheckResult(UpdateStatus.available, current, info);
  }

  /// Hands the APK to the system browser, which downloads it and offers
  /// "Open" — Android then shows its own package-installer confirmation.
  ///
  /// Deliberately not an in-app OTA download: that would require the
  /// `REQUEST_INSTALL_PACKAGES` permission (flagged by Play Protect and
  /// Samsung Auto Blocker on this exact device), a `FileProvider`, and a
  /// foreground download that survives the app being backgrounded mid-shift.
  /// The browser already does all of that, with resume on flaky mobile data.
  Future<bool> launchDownload(UpdateInfo info) async {
    if (!_isTrustedApkUrl(info.apkUrl)) return false;
    try {
      return await launchUrl(
        info.apkUrl,
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      // Last resort: no browser resolved the intent. Let the caller surface
      // the release page instead of dying on an unhandled PlatformException.
      try {
        return await launchUrl(
          Uri.parse('https://github.com/$_repoSlug/releases/latest'),
          mode: LaunchMode.externalApplication,
        );
      } catch (_) {
        return false;
      }
    }
  }

  /// Records that the driver saw a prompt, starting the [_promptCooldown].
  Future<void> markPrompted() async {
    final prefs = await _prefs();
    await prefs?.setInt(
      _keyLastPromptMs,
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  /// Silences one specific version forever (until a newer one ships).
  Future<void> skipVersion(String displayVersion) async {
    final prefs = await _prefs();
    await prefs?.setString(_keySkippedVersion, displayVersion);
  }

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  // ---------------------------------------------------------------- sources

  Future<UpdateInfo?> _fromManifest({String? languageCode}) async {
    final uri = Uri.tryParse(Env.gistUrl.trim());
    if (uri == null) return null;

    final json = await _getJson(uri);
    if (json == null) return null;

    final latest = json['latest']?.toString().trim();
    if (latest == null || latest.isEmpty) return null;

    final apkUrl = _pickApkUrl(json);
    if (apkUrl == null) return null;

    final build = json['build'] is num
        ? (json['build'] as num).toInt()
        : int.tryParse(json['build']?.toString().trim() ?? '');

    return UpdateInfo(
      version: AppVersion.parse(latest, build: build),
      displayVersion: latest,
      apkUrl: apkUrl,
      mandatory: json['mandatory'] == true,
      notes: _pickNotes(json, languageCode),
    );
  }

  /// Fallback for a deleted or corrupted manifest. Rate-limited to 60/hour per
  /// IP, which is why it is never the primary source.
  Future<UpdateInfo?> _fromReleasesApi() async {
    final json = await _getJson(_releasesApi);
    if (json == null) return null;

    final tag = json['tag_name']?.toString().trim();
    if (tag == null || tag.isEmpty) return null;
    if (json['draft'] == true || json['prerelease'] == true) return null;

    final assets = json['assets'];
    if (assets is! List) return null;

    // Walk our preference list rather than the response order, so a release
    // carrying both per-ABI and fat APKs still yields the arm64 one.
    for (final wanted in _apkAssetPreference) {
      for (final asset in assets) {
        if (asset is! Map) continue;
        if (asset['name']?.toString().trim() != wanted) continue;
        final url = _sanitizeApkUrl(asset['browser_download_url']?.toString());
        if (url != null) {
          return UpdateInfo(
            version: AppVersion.parse(tag),
            displayVersion: tag,
            apkUrl: url,
            mandatory: false,
            notes: null,
          );
        }
      }
    }
    // Tag exists but no installable asset — treat as "nothing to offer"
    // instead of sending the driver to a release page with no APK.
    return null;
  }

  // ------------------------------------------------------------- transport

  /// Single hardened GET used by both sources. Returns null on any failure:
  /// offline, DNS, TLS, timeout, non-200, non-JSON, or non-object body.
  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    if (uri.scheme != 'https') return null;
    if (!_allowedMetadataHosts.contains(uri.host)) return null;

    final client = HttpClient();
    try {
      client.connectionTimeout = _connectTimeout;
      client.autoUncompress = true;

      final request = await client.getUrl(uri).timeout(_connectTimeout);
      // No redirect chasing: a Location header pointing at attacker.example
      // would otherwise slip past the host allowlist checked above.
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      // api.github.com rejects requests without a User-Agent.
      request.headers.set(HttpHeaders.userAgentHeader, 'RateHelper-Updater');

      final response = await request.close().timeout(_readTimeout);
      if (response.statusCode != HttpStatus.ok) {
        await response.drain<void>().catchError((Object _) {});
        return null;
      }

      final body =
          await response.transform(utf8.decoder).join().timeout(_readTimeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) return null;
      return decoded.cast<String, dynamic>();
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }

  // -------------------------------------------------------------- manifest

  /// Prefers the per-ABI map when present, else the flat `apk_url`.
  Uri? _pickApkUrl(Map<String, dynamic> json) {
    final perAbi = json['apk_urls'];
    if (perAbi is Map) {
      for (final abi in _abiPreference) {
        final candidate = _sanitizeApkUrl(perAbi[abi]?.toString());
        if (candidate != null) return candidate;
      }
    }
    return _sanitizeApkUrl(json['apk_url']?.toString());
  }

  String? _pickNotes(Map<String, dynamic> json, String? languageCode) {
    final keys = <String>[
      if (languageCode != null) 'notes_$languageCode',
      'notes_en',
      'notes',
    ];
    for (final key in keys) {
      final value = json[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// Parses and allowlists an APK URL. Everything else is dropped silently,
  /// so a compromised manifest can at worst stop updates — never redirect the
  /// driver to an attacker-controlled installer.
  Uri? _sanitizeApkUrl(String? raw) {
    final trimmed = raw?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    if (!trimmed.startsWith(_releasesPrefix)) return null;

    final uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    if (uri.scheme != 'https' || uri.host != 'github.com') return null;

    final segments = uri.pathSegments;
    if (!segments.contains('download')) return null;

    final fileName = segments.isEmpty ? '' : segments.last;
    if (!_apkAssetPreference.contains(fileName)) return null;

    return uri;
  }

  bool _isTrustedApkUrl(Uri uri) => _sanitizeApkUrl(uri.toString()) != null;
}
