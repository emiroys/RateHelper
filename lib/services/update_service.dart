import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../crash_logger.dart';
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
  const AppVersion(this.major, this.minor, this.patch, [this.build]);

  final int major;
  final int minor;
  final int patch;

  /// Pubspec build number, or null when the metadata does not publish one.
  ///
  /// Git tags carry no build number, so null genuinely means "unknown" rather
  /// than "zero" — conflating the two made the tag `v5.0.0` rank below the
  /// installed `5.0.0+5` and silently reported "up to date".
  final int? build;

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
        (plusSplit.length > 1 ? int.tryParse(plusSplit[1].trim()) : null);

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

  /// Total order over all four fields, consistent with [operator ==].
  /// Use [isNewerThan] to decide whether to offer an update.
  @override
  int compareTo(AppVersion other) {
    final triple = _compareTriple(other);
    if (triple != 0) return triple;
    return (build ?? -1).compareTo(other.build ?? -1);
  }

  int _compareTriple(AppVersion other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  /// True when this version should be offered as an update over [installed].
  ///
  /// When either side has no published build number the semver triple alone
  /// decides, so a bare release tag is never mistaken for a downgrade.
  bool isNewerThan(AppVersion installed) {
    final triple = _compareTriple(installed);
    if (triple != 0) return triple > 0;

    final mine = build;
    final theirs = installed.build;
    if (mine == null || theirs == null) return false;
    return mine > theirs;
  }

  String get label => '$major.$minor.$patch';

  @override
  String toString() {
    final b = build;
    return b != null && b > 0 ? '$label+$b' : label;
  }

  @override
  bool operator ==(Object other) =>
      other is AppVersion &&
      major == other.major &&
      minor == other.minor &&
      patch == other.patch &&
      build == other.build;

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

  /// Cache subfolder the APK is downloaded into. Must stay in sync with
  /// `res/xml/file_provider_paths.xml` and `MainActivity.UPDATE_APK_DIR`.
  static const String _apkCacheDirName = 'updates';

  static const MethodChannel _systemChannel =
      MethodChannel('com.ratehelper.app/system');

  /// GitHub serves release assets from a signed CDN URL behind one or two
  /// redirects, so unlike the metadata fetch the download must follow them.
  static const int _maxDownloadRedirects = 5;

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
        build: pubspecBuildNumber(info.buildNumber),
      );
      _installed = resolved;
      return resolved;
    } catch (_) {
      return AppVersion.zero;
    }
  }

  /// Recovers the pubspec build number from an Android `versionCode`.
  ///
  /// `flutter build apk --split-per-abi` offsets the code per architecture
  /// (`abiIndex * 1000 + build`), so the arm64 APK of build 5 reports 2005.
  /// The manifest is hand-written against the pubspec number, so the offset is
  /// stripped here instead of forcing whoever edits the manifest to know about
  /// it. Build numbers must therefore stay below 1000.
  ///
  /// Returns null when the platform reports no usable code, so the comparison
  /// falls back to the semver triple instead of assuming build 0.
  @visibleForTesting
  static int? pubspecBuildNumber(String rawVersionCode) {
    final code = int.tryParse(rawVersionCode.trim());
    if (code == null || code <= 0) return null;
    return code % 1000;
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

    final manifest = await _fromManifest(languageCode: languageCode);
    final info = manifest ?? await _fromReleasesApi();

    if (info == null) {
      return UpdateCheckResult(UpdateStatus.unreachable, current);
    }
    if (info.version.isNewerThan(current)) {
      return UpdateCheckResult(UpdateStatus.available, current, info);
    }

    // The manifest is the source of truth. When it could not be read, the
    // fallback's "nothing newer" is a guess — the Releases API only knows
    // about tags, which lag behind a manifest bump. Reporting "up to date"
    // here is how a broken manifest used to hide in plain sight.
    if (manifest == null) {
      await _logFailure('manifest unreadable; releases fallback not newer');
      return UpdateCheckResult(UpdateStatus.unreachable, current);
    }
    return UpdateCheckResult(UpdateStatus.upToDate, current);
  }

  /// Whether Android will let us open the package installer at all.
  ///
  /// "Install unknown apps" is off by default, and without it the installer
  /// intent opens a dead end, so the dialog asks for it up front.
  Future<bool> canInstallPackages() async {
    try {
      final granted =
          await _systemChannel.invokeMethod<bool>('canInstallPackages');
      return granted ?? false;
    } catch (e) {
      await _logFailure('canInstallPackages: ${e.runtimeType}', e);
      return false;
    }
  }

  /// Opens the per-app "install unknown apps" system page.
  Future<bool> openInstallPermissionSettings() async {
    try {
      final opened = await _systemChannel
          .invokeMethod<bool>('openInstallPermissionSettings');
      return opened ?? false;
    } catch (e) {
      await _logFailure('openInstallPermission: ${e.runtimeType}', e);
      return false;
    }
  }

  /// Downloads the APK into the app's own cache and returns the file.
  ///
  /// Chrome receives the whole file on this device but stalls before handing
  /// it to the installer, which is why the download is done here instead.
  /// Returns null on any failure so the caller can fall back to the browser.
  ///
  /// [onProgress] reports received/total bytes (total is null when the server
  /// omits `Content-Length`). [isCancelled] is polled per chunk so the driver
  /// can abort a 22 MB download started by accident on mobile data.
  Future<File?> downloadApk(
    UpdateInfo info, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (!_isTrustedApkUrl(info.apkUrl)) {
      await _logFailure('download: apk url failed the allowlist');
      return null;
    }

    final dir = await _prepareApkCacheDir();
    if (dir == null) return null;

    final file = File(
      '${dir.path}${Platform.pathSeparator}${info.apkUrl.pathSegments.last}',
    );

    final client = HttpClient();
    IOSink? sink;
    try {
      client.connectionTimeout = _connectTimeout;

      final response = await _openDownloadStream(client, info.apkUrl);
      if (response == null) return null;

      final declared = response.contentLength;
      final total = declared > 0 ? declared : null;
      var received = 0;
      var cancelled = false;

      sink = file.openWrite();
      await for (final chunk in response) {
        if (isCancelled?.call() ?? false) {
          cancelled = true;
          break;
        }
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (cancelled) {
        await _deleteQuietly(file);
        return null;
      }

      // A dropped connection yields a short file that Android would reject
      // with an unhelpful "package appears to be invalid", so check here.
      final written = await file.length();
      if (total != null && written != total) {
        await _logFailure('download: got $written of $total bytes');
        await _deleteQuietly(file);
        return null;
      }
      if (!await _looksLikeApk(file)) {
        await _logFailure('download: payload is not a zip/apk');
        await _deleteQuietly(file);
        return null;
      }
      return file;
    } catch (e) {
      await _logFailure('download: ${e.runtimeType}', e);
      try {
        await sink?.close();
      } catch (_) {}
      await _deleteQuietly(file);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Opens Android's package installer on a downloaded APK. The user still
  /// confirms in the system dialog.
  Future<bool> installApk(File file) async {
    try {
      final started = await _systemChannel.invokeMethod<bool>(
        'installApk',
        <String, dynamic>{'path': file.path},
      );
      if (started != true) {
        await _logFailure('install: installer intent refused the file');
      }
      return started ?? false;
    } catch (e) {
      await _logFailure('install: ${e.runtimeType}', e);
      return false;
    }
  }

  /// Follows GitHub's redirect chain to the signed asset URL, re-validating
  /// every hop so the chain cannot leave GitHub's own hosts.
  Future<HttpClientResponse?> _openDownloadStream(
    HttpClient client,
    Uri start,
  ) async {
    var uri = start;
    for (var hop = 0; hop <= _maxDownloadRedirects; hop++) {
      final request = await client.getUrl(uri).timeout(_connectTimeout);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.userAgentHeader, 'RateHelper-Updater');
      final response = await request.close().timeout(_readTimeout);

      if (response.isRedirect) {
        final location = response.headers.value(HttpHeaders.locationHeader);
        await response.drain<void>().catchError((Object _) {});
        if (location == null || location.isEmpty) {
          await _logFailure('download: redirect without a location header');
          return null;
        }
        final next = uri.resolve(location);
        if (!_isTrustedDownloadHost(next)) {
          await _logFailure('download: redirect left GitHub (${next.host})');
          return null;
        }
        uri = next;
        continue;
      }

      if (response.statusCode != HttpStatus.ok) {
        await _logFailure('download: HTTP ${response.statusCode}');
        await response.drain<void>().catchError((Object _) {});
        return null;
      }
      return response;
    }
    await _logFailure('download: more than $_maxDownloadRedirects redirects');
    return null;
  }

  /// GitHub's asset CDN hostname has changed more than once
  /// (`objects.` then `release-assets.`), so the allowlist is a suffix match
  /// on the domain itself rather than a list of hostnames that will rot.
  bool _isTrustedDownloadHost(Uri uri) {
    if (uri.scheme != 'https') return false;
    final host = uri.host.toLowerCase();
    return host == 'github.com' ||
        host == 'githubusercontent.com' ||
        host.endsWith('.githubusercontent.com');
  }

  /// Fresh directory per download: a half-written APK left by a dropped
  /// connection must never be offered to the installer.
  Future<Directory?> _prepareApkCacheDir() async {
    try {
      final base = await getTemporaryDirectory();
      final dir = Directory(
        '${base.path}${Platform.pathSeparator}$_apkCacheDirName',
      );
      if (await dir.exists()) {
        await for (final entry in dir.list()) {
          try {
            await entry.delete(recursive: true);
          } catch (_) {}
        }
      } else {
        await dir.create(recursive: true);
      }
      return dir;
    } catch (e) {
      await _logFailure('download: cache dir ${e.runtimeType}', e);
      return null;
    }
  }

  /// Cheap sanity check: an APK is a zip, so it starts with `PK`. Catches a
  /// captive-portal HTML page saved under an `.apk` name.
  Future<bool> _looksLikeApk(File file) async {
    try {
      final head = await file.openRead(0, 2).first;
      return head.length >= 2 && head[0] == 0x50 && head[1] == 0x4B;
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }

  /// Fallback path: hands the URL to the system browser.
  ///
  /// Kept because the in-app installer needs a permission the driver can
  /// decline, and because Chrome's download manager survives the app being
  /// killed mid-shift. On this device the browser reaches 100% and then
  /// stalls before the install hand-off, so it is no longer the default.
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
    final base = Uri.tryParse(Env.gistUrl.trim());
    if (base == null) {
      await _logFailure('manifest URL is not a valid URI');
      return null;
    }

    // GitHub serves the raw gist through a CDN with `cache-control:
    // max-age=300`, so a freshly edited manifest keeps returning the previous
    // `latest` for up to five minutes — long enough to look like a bug, and it
    // did. A unique query parameter forces a cache miss without touching the
    // host or path that the allowlist in [_getJson] validates.
    final uri = base.replace(
      queryParameters: <String, String>{
        ...base.queryParameters,
        '_': DateTime.now().millisecondsSinceEpoch.toString(),
      },
    );

    final json = await _getJson(uri, 'manifest');
    if (json == null) return null;

    final latest = json['latest']?.toString().trim();
    if (latest == null || latest.isEmpty) {
      await _logFailure('manifest has no usable "latest" field');
      return null;
    }

    final apkUrl = _pickApkUrl(json);
    if (apkUrl == null) {
      await _logFailure('manifest "apk_url" failed the allowlist');
      return null;
    }

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
    final json = await _getJson(_releasesApi, 'releases-api');
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
  ///
  /// Every failure is logged (never the URL itself, which is a build secret)
  /// so a driver can read the reason from "Çökme Kayıtları" instead of
  /// guessing why the check came back empty.
  Future<Map<String, dynamic>?> _getJson(Uri uri, String label) async {
    if (uri.scheme != 'https') {
      await _logFailure('$label: scheme is not https');
      return null;
    }
    if (!_allowedMetadataHosts.contains(uri.host)) {
      await _logFailure('$label: host ${uri.host} is not allowlisted');
      return null;
    }

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
        // A 30x here means the URL needs a redirect we refuse to follow;
        // surfacing the code makes that distinguishable from a 404.
        await _logFailure('$label: HTTP ${response.statusCode}');
        await response.drain<void>().catchError((Object _) {});
        return null;
      }

      final body =
          await response.transform(utf8.decoder).join().timeout(_readTimeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        await _logFailure('$label: body is ${decoded.runtimeType}, not an object');
        return null;
      }
      return decoded.cast<String, dynamic>();
    } catch (e) {
      await _logFailure('$label: ${e.runtimeType}', e);
      return null;
    } finally {
      client.close(force: true);
    }
  }

  /// Update failures are expected (tunnels, dead zones, hotel WiFi) so they
  /// never reach the user as an error — they land in the crash log, which the
  /// settings screen can already display and copy.
  Future<void> _logFailure(String message, [Object? error]) async {
    try {
      await CrashLogger.appendError('UPDATE', message, error, null);
    } catch (_) {}
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
