import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../earnings_models.dart';
import '../earnings_screen.dart' show kDriverNameKey;
import '../l10n.dart';
import '../log.dart';
import '../models/weekly_archive_entry.dart';
import '../overlay_widget.dart';
import '../shade_controls.dart';
import '../shift_counter_store.dart';
import '../tap_history_store.dart';
import 'github_access.dart';

/// Errors surfaced when validating or restoring a backup file.
enum BackupErrorCode {
  tooLarge,
  invalidJson,
  unsupportedFormat,
  unsupportedVersion,
  corruptChecksum,
  invalidSchema,
  futureTimestamp,
}

class BackupValidationException implements Exception {
  const BackupValidationException(this.code, [this.detail]);

  final BackupErrorCode code;
  final String? detail;

  @override
  String toString() =>
      'BackupValidationException(${code.name}${detail != null ? ': $detail' : ''})';
}

/// Summary of a validated backup shown to the driver before overwriting data.
@immutable
class BackupPreview {
  const BackupPreview({
    required this.createdAt,
    required this.appVersion,
    required this.schemaVersion,
    required this.shiftCounters,
    required this.shiftWeekStart,
    required this.isFromOlderWeek,
    required this.weeklyArchiveCount,
    required this.earningsWeekCount,
    required this.fuelReceiptCount,
    required this.lifetimeTrips,
    required this.tapHistoryCount,
    required this.driverMode,
    required this.language,
  });

  final DateTime createdAt;
  final String appVersion;
  final int schemaVersion;
  final ShiftCounters shiftCounters;
  final tz.TZDateTime shiftWeekStart;

  /// True when [shiftWeekStart] is earlier than the current Monday 04:00
  /// `Europe/Warsaw` boundary. When restored, non-zero [shiftCounters] will
  /// be archived under [shiftWeekStart] and the current week's active shift
  /// counters will start at zero.
  final bool isFromOlderWeek;
  final int weeklyArchiveCount;
  final int earningsWeekCount;
  final int fuelReceiptCount;
  final int lifetimeTrips;
  final int tapHistoryCount;
  final DriverMode driverMode;
  final AppLang language;

  bool get hasShiftActivity =>
      shiftCounters.accepted > 0 ||
      shiftCounters.rejected > 0 ||
      shiftCounters.completed > 0 ||
      shiftCounters.canceled > 0;
}

/// Validated, ready-to-restore backup bundle.
@immutable
class ValidatedBackup {
  const ValidatedBackup({
    required this.preview,
    required this.lastResetTimestamp,
    required this.weeklyArchive,
    required this.earningsHistory,
    required this.lifetimeTripsTotal,
    required this.lifetimeTripsBackfilled,
    required this.driverName,
    required this.driverMode,
    required this.driverModeAsked,
    required this.settings,
    required this.tapHistory,
  });

  final BackupPreview preview;
  final int lastResetTimestamp;
  final List<String> weeklyArchive;
  final List<WeekEarning> earningsHistory;
  final int lifetimeTripsTotal;
  final bool lifetimeTripsBackfilled;
  final String driverName;
  final DriverMode driverMode;
  final bool driverModeAsked;
  final Map<String, Object> settings;
  final List<Map<String, dynamic>> tapHistory;
}

/// Full local backup & restore service with a persistent transaction journal
/// (`restore_journal.json`) for crash/kill recovery.
abstract final class BackupService {
  static const String appIdentifier = 'RateHelper';
  static const int currentSchemaVersion = 1;

  /// Hard cap on imported backup files (5 MB). Enforced natively and in Dart.
  static const int maxBackupBytes = 5 * 1024 * 1024;

  static const int maxCounterValue = 99999;
  static const int maxWeeklyArchiveItems = 104;
  static const int maxArchiveLineChars = 2048;
  static const int maxLifetimeTrips = 10000000;
  static const int maxDriverNameChars = 80;
  static const double maxMoneyPln = 1000000.0;
  static const double maxWeeklyOnlineHours = 168.0;

  static const String journalFileName = 'restore_journal.json';
  static const String journalActivePrefsKey = 'restore_journal_active';

  static const String _keyLang = 'appLanguage';
  static const String _keyTripGoal = 'trip_goal_tier';
  static const String _keyAutoComplete = 'autoCompleteTrips';
  static const String _keySteeringWheel = 'steeringWheelEnabled';
  static const String _keyKeepScreenOn = 'keepScreenOn';
  static const String _keyOnboardingComplete = 'onboardingComplete';
  static const String _keyLastReset = 'lastResetTimestamp';
  static const String _keyArchive = 'weekly_archive';

  static const Set<String> _allowedLangs = {'tr', 'en', 'pl'};
  static const Set<String> _allowedGoalTiers = {
    'tier0',
    'tier1',
    'tier2',
    'tier3',
    'tier4',
  };
  static const Set<String> _allowedOrientations = {'horizontal', 'vertical'};
  static const Set<String> _allowedDriverModes = {'solo', 'paired', 'trio'};
  static const Set<String> _allowedTapTypes = {
    'accepted',
    'rejected',
    'canceled',
  };

  static const Set<String> _rootKeys = {
    'app',
    'schemaVersion',
    'createdAt',
    'appVersion',
    'sha256',
    'payload',
  };

  static const Set<String> _payloadKeys = {
    'shiftCounters',
    'weeklyArchive',
    'earningsHistory',
    'lifetimeTrips',
    'driverProfile',
    'settings',
    'tapHistory',
  };

  static const Set<String> _shiftCounterKeys = {
    'a',
    'r',
    'c',
    'k',
    'lastResetTimestamp',
    'weekStart',
  };

  static const Set<String> _settingsBoolKeys = {
    _keyAutoComplete,
    _keySteeringWheel,
    _keyKeepScreenOn,
    OverlayWidget.cancelButtonPrefsKey,
    OverlayWidget.collapsedPrefsKey,
    ShadeControls.prefsKey,
    ShadeControls.hidePillPrefsKey,
    GithubAccess.autoUpdateKey,
    GithubAccess.autoEventsKey,
    GithubAccess.promptAnsweredKey,
    _keyOnboardingComplete,
  };

  static const Set<String> _settingsAllKeys = {
    _keyLang,
    _keyTripGoal,
    PillOrientation.prefsKey,
    ..._settingsBoolKeys,
  };

  /// All SharedPreferences keys owned by user data that a restore snapshots
  /// and replaces. Cache keys, OTA timers, and secrets are never touched.
  static const List<String> _managedPrefsKeys = [
    _keyLastReset,
    _keyArchive,
    kEarningsHistoryKey,
    kLifetimeTripsKey,
    kLifetimeTripsBackfilledKey,
    kDriverNameKey,
    DriverMode.key,
    DriverMode.askedKey,
    _keyLang,
    _keyTripGoal,
    PillOrientation.prefsKey,
    PillOrientation.legacyBoolKey,
    ..._settingsBoolKeys,
  ];

  static File? _journalFileOverride;
  static Future<bool>? _recoveryInFlight;

  @visibleForTesting
  static void resetForTest({File? journalFile}) {
    _journalFileOverride = journalFile;
    _recoveryInFlight = null;
  }

  /// Resolves `Europe/Warsaw`, falling back to `tz.local` only if timezone
  /// initialization has not run.
  static tz.Location warsawLocation() {
    try {
      return tz.getLocation('Europe/Warsaw');
    } catch (_) {
      return tz.local;
    }
  }

  /// Most recent Monday 04:00 `Europe/Warsaw` at or before [instant].
  ///
  /// Uses calendar-date constructors rather than `Duration(days: ...)` so
  /// spring/autumn DST transitions in Poland always land on 04:00 local time.
  static tz.TZDateTime lastMonday4amWarsaw(
    DateTime instant, {
    tz.Location? location,
  }) {
    final loc = location ?? warsawLocation();
    final now = instant is tz.TZDateTime && instant.location == loc
        ? instant
        : tz.TZDateTime.from(instant, loc);
    final daysFromMonday = (now.weekday - DateTime.monday) % 7;
    final monday = tz.TZDateTime(
      loc,
      now.year,
      now.month,
      now.day - daysFromMonday,
      4,
      0,
      0,
    );
    if (now.isBefore(monday)) {
      return tz.TZDateTime(
        loc,
        monday.year,
        monday.month,
        monday.day - 7,
        4,
        0,
        0,
      );
    }
    return monday;
  }

  /// Sunday 04:00 `Europe/Warsaw` end marker for a week starting at
  /// [weekStart], matching `HomeScreen._buildArchiveEntry`.
  static tz.TZDateTime warsawWeekEndFromStart(
    tz.TZDateTime weekStart, {
    tz.Location? location,
  }) {
    final loc = location ?? warsawLocation();
    return tz.TZDateTime(
      loc,
      weekStart.year,
      weekStart.month,
      weekStart.day + 6,
      4,
      0,
      0,
    );
  }

  static String suggestedFileName({DateTime? now}) {
    final dt = (now ?? DateTime.now()).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final date = '${dt.year}${two(dt.month)}${two(dt.day)}';
    final time = '${two(dt.hour)}${two(dt.minute)}';
    return 'ratehelper_backup_${date}_$time.json';
  }

  /// Serializes all user-owned persistent data into a portable JSON string.
  ///
  /// Callers on the live UI must quiesce active saves, the overlay, and
  /// pending native taps before invoking this method.
  static Future<String> createBackupJson({
    required String appVersion,
    DateTime? now,
    SharedPreferences? prefs,
    ShiftCounterStore? shiftStore,
    TapHistoryStore? tapStore,
  }) async {
    await recoverPendingRestoreIfNeeded(
      prefs: prefs,
      shiftStore: shiftStore,
      tapStore: tapStore,
    );

    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    final resolvedShiftStore = shiftStore ?? ShiftCounterStore.instance;
    final resolvedTapStore = tapStore ?? TapHistoryStore.instance;

    await resolvedTapStore.migrateFromPrefs(resolvedPrefs);
    await resolvedShiftStore.migrateFromPrefs(resolvedPrefs);

    final clock = (now ?? DateTime.now()).toUtc();
    final shiftWeekStart = lastMonday4amWarsaw(clock);
    final counters = await resolvedShiftStore.read();
    final taps = await resolvedTapStore.readAll();

    final rawArchive = resolvedPrefs.getStringList(_keyArchive) ?? const [];
    final collapsedArchive = collapseWeeklyArchive(rawArchive);
    final trimmedArchive = collapsedArchive.length > maxWeeklyArchiveItems
        ? collapsedArchive.sublist(
            collapsedArchive.length - maxWeeklyArchiveItems,
          )
        : collapsedArchive;

    final earningsEntries = decodeEarnings(
      resolvedPrefs.getString(kEarningsHistoryKey),
    )..sort((a, b) => a.weekStart.compareTo(b.weekStart));
    final trimmedEarnings = earningsEntries.length > kMaxEarningEntries
        ? earningsEntries.sublist(earningsEntries.length - kMaxEarningEntries)
        : earningsEntries;

    final notifControls =
        resolvedPrefs.getBool(ShadeControls.prefsKey) ?? false;
    final hidePill = ShadeControls.pillHidden(
      notificationControls: notifControls,
      hidePill: resolvedPrefs.getBool(ShadeControls.hidePillPrefsKey) ?? false,
    );

    final langRaw = resolvedPrefs.getString(_keyLang);
    final lang = _allowedLangs.contains(langRaw) ? langRaw! : S.lang.name;

    final goalRaw = resolvedPrefs.getString(_keyTripGoal);
    final goal = _allowedGoalTiers.contains(goalRaw) ? goalRaw! : 'tier1';

    final orientation = PillOrientation.fromPrefs(resolvedPrefs).name;
    final mode = DriverMode.parse(
      resolvedPrefs.getString(DriverMode.key),
    ).name;

    final lastResetMs = resolvedPrefs.getInt(_keyLastReset) ?? 0;

    final payload = <String, Object?>{
      'shiftCounters': <String, Object?>{
        'a': counters.accepted.clamp(0, maxCounterValue),
        'r': counters.rejected.clamp(0, maxCounterValue),
        'c': counters.completed.clamp(0, maxCounterValue),
        'k': counters.canceled.clamp(0, maxCounterValue),
        'lastResetTimestamp': math.max(0, lastResetMs),
        'weekStart': shiftWeekStart.toIso8601String(),
      },
      'weeklyArchive': trimmedArchive,
      'earningsHistory': trimmedEarnings.map((e) => e.toJson()).toList(),
      'lifetimeTrips': <String, Object?>{
        'total': (resolvedPrefs.getInt(kLifetimeTripsKey) ?? 0).clamp(
          0,
          maxLifetimeTrips,
        ),
        'backfilled':
            resolvedPrefs.getBool(kLifetimeTripsBackfilledKey) ?? false,
      },
      'driverProfile': <String, Object?>{
        'name': _sanitizeDriverName(
          resolvedPrefs.getString(kDriverNameKey) ?? '',
        ),
        'mode': mode,
        'modeAsked': resolvedPrefs.getBool(DriverMode.askedKey) ?? false,
      },
      'settings': <String, Object?>{
        _keyLang: lang,
        _keyTripGoal: goal,
        PillOrientation.prefsKey: orientation,
        _keyAutoComplete: resolvedPrefs.getBool(_keyAutoComplete) ?? false,
        _keySteeringWheel: resolvedPrefs.getBool(_keySteeringWheel) ?? false,
        _keyKeepScreenOn: resolvedPrefs.getBool(_keyKeepScreenOn) ?? false,
        OverlayWidget.cancelButtonPrefsKey:
            resolvedPrefs.getBool(OverlayWidget.cancelButtonPrefsKey) ?? false,
        OverlayWidget.collapsedPrefsKey:
            resolvedPrefs.getBool(OverlayWidget.collapsedPrefsKey) ?? false,
        ShadeControls.prefsKey: notifControls,
        ShadeControls.hidePillPrefsKey: hidePill,
        GithubAccess.autoUpdateKey: GithubAccess.autoUpdate(resolvedPrefs),
        GithubAccess.autoEventsKey: GithubAccess.autoEvents(resolvedPrefs),
        GithubAccess.promptAnsweredKey: GithubAccess.promptAnswered(
          resolvedPrefs,
        ),
        _keyOnboardingComplete:
            resolvedPrefs.getBool(_keyOnboardingComplete) ?? true,
      },
      'tapHistory': taps
          .where(_isValidTapMap)
          .map(
            (e) => <String, String>{
              'type': e['type'].toString(),
              'timestamp': e['timestamp'].toString(),
              'localTime': e['localTime'].toString(),
            },
          )
          .toList(),
    };

    final digest = _computePayloadSha256(payload);
    final envelope = <String, Object?>{
      'app': appIdentifier,
      'schemaVersion': currentSchemaVersion,
      'createdAt': clock.toIso8601String(),
      'appVersion': appVersion.trim().isEmpty ? 'unknown' : appVersion.trim(),
      'sha256': digest,
      'payload': payload,
    };

    return const JsonEncoder.withIndent('  ').convert(envelope);
  }

  /// Parses and strictly validates [rawJson] before any live data is touched.
  ///
  /// Throws [BackupValidationException] on any size, format, checksum, schema,
  /// or range violation.
  static ValidatedBackup validateBackupJson(
    String rawJson, {
    DateTime? now,
  }) {
    final byteLen = utf8.encode(rawJson).length;
    if (byteLen > maxBackupBytes) {
      throw const BackupValidationException(BackupErrorCode.tooLarge);
    }
    if (rawJson.trim().isEmpty) {
      throw const BackupValidationException(BackupErrorCode.invalidJson);
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(rawJson);
    } catch (_) {
      throw const BackupValidationException(BackupErrorCode.invalidJson);
    }

    if (decoded is! Map) {
      throw const BackupValidationException(BackupErrorCode.unsupportedFormat);
    }

    for (final k in decoded.keys) {
      if (k is! String || !_rootKeys.contains(k)) {
        throw BackupValidationException(
          BackupErrorCode.invalidSchema,
          'Unexpected root key: $k',
        );
      }
    }

    if (decoded['app'] != appIdentifier) {
      throw const BackupValidationException(BackupErrorCode.unsupportedFormat);
    }

    final schemaVersion = decoded['schemaVersion'];
    if (schemaVersion is! int) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    if (schemaVersion != currentSchemaVersion) {
      throw BackupValidationException(
        BackupErrorCode.unsupportedVersion,
        'v$schemaVersion',
      );
    }

    final createdAtRaw = decoded['createdAt'];
    if (createdAtRaw is! String || createdAtRaw.trim().isEmpty) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    final createdAt = DateTime.tryParse(createdAtRaw);
    if (createdAt == null || createdAt.year < 2020) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }

    final clock = now ?? DateTime.now();
    if (createdAt.isAfter(clock.add(const Duration(minutes: 10)))) {
      throw const BackupValidationException(BackupErrorCode.futureTimestamp);
    }

    final appVersion = decoded['appVersion'];
    if (appVersion is! String ||
        appVersion.trim().isEmpty ||
        appVersion.length > 64) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }

    final sha256Raw = decoded['sha256'];
    if (sha256Raw is! String ||
        !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(sha256Raw)) {
      throw const BackupValidationException(BackupErrorCode.corruptChecksum);
    }

    final payloadRaw = decoded['payload'];
    if (payloadRaw is! Map) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }

    // Verify integrity checksum against canonical payload encoding.
    // Note: SHA-256 detects accidental corruption/truncation only; every
    // field inside payload is still strictly validated below.
    final expectedSha = _computePayloadSha256(payloadRaw);
    if (expectedSha.toLowerCase() != sha256Raw.toLowerCase()) {
      throw const BackupValidationException(BackupErrorCode.corruptChecksum);
    }

    for (final k in payloadRaw.keys) {
      if (k is! String || !_payloadKeys.contains(k)) {
        throw BackupValidationException(
          BackupErrorCode.invalidSchema,
          'Unexpected payload key: $k',
        );
      }
    }
    if (!payloadRaw.keys.toSet().containsAll(_payloadKeys)) {
      throw const BackupValidationException(
        BackupErrorCode.invalidSchema,
        'Missing required payload section',
      );
    }

    // 1. Shift counters & unambiguous shift week resolution
    final shiftRaw = payloadRaw['shiftCounters'];
    if (shiftRaw is! Map) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    for (final k in shiftRaw.keys) {
      if (k is! String || !_shiftCounterKeys.contains(k)) {
        throw const BackupValidationException(BackupErrorCode.invalidSchema);
      }
    }
    final accepted = _requireIntInRange(shiftRaw['a'], 0, maxCounterValue);
    final rejected = _requireIntInRange(shiftRaw['r'], 0, maxCounterValue);
    final completed = _requireIntInRange(shiftRaw['c'], 0, maxCounterValue);
    final canceled = _requireIntInRange(shiftRaw['k'], 0, maxCounterValue);
    final lastResetMs = _requireIntInRange(
      shiftRaw['lastResetTimestamp'],
      0,
      clock.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
    );

    final createdWeekStart = lastMonday4amWarsaw(createdAt);
    tz.TZDateTime shiftWeekStart = createdWeekStart;
    if (shiftRaw.containsKey('weekStart') && shiftRaw['weekStart'] != null) {
      final wsRaw = shiftRaw['weekStart'];
      if (wsRaw is! String) {
        throw const BackupValidationException(BackupErrorCode.invalidSchema);
      }
      final parsedWs = DateTime.tryParse(wsRaw);
      if (parsedWs == null || parsedWs.year < 2020) {
        throw const BackupValidationException(BackupErrorCode.invalidSchema);
      }
      final normalizedWs = lastMonday4amWarsaw(parsedWs);
      final inWarsaw = tz.TZDateTime.from(parsedWs, warsawLocation());
      // weekStart must be an exact Monday 04:00 Europe/Warsaw boundary and
      // must match the backup creation week so a tampered timestamp cannot
      // misroute shift counters into an arbitrary week.
      if (!inWarsaw.isAtSameMomentAs(normalizedWs) ||
          !normalizedWs.isAtSameMomentAs(createdWeekStart)) {
        throw const BackupValidationException(
          BackupErrorCode.invalidSchema,
          'Inconsistent shift weekStart',
        );
      }
      shiftWeekStart = normalizedWs;
    }

    final currentWeekStart = lastMonday4amWarsaw(clock);
    if (shiftWeekStart.isAfter(currentWeekStart)) {
      throw const BackupValidationException(BackupErrorCode.futureTimestamp);
    }
    final isFromOlderWeek = shiftWeekStart.isBefore(currentWeekStart);

    // 2. Weekly archive
    final archiveRaw = payloadRaw['weeklyArchive'];
    if (archiveRaw is! List || archiveRaw.length > maxWeeklyArchiveItems) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    final validatedArchive = <String>[];
    for (final item in archiveRaw) {
      if (item is! String ||
          item.trim().isEmpty ||
          item.length > maxArchiveLineChars) {
        throw const BackupValidationException(BackupErrorCode.invalidSchema);
      }
      final entry = WeeklyArchiveEntry.parse(item);
      if (!entry.acceptRate.isFinite ||
          entry.acceptRate < 0 ||
          entry.acceptRate > 100 ||
          !entry.cancelRate.isFinite ||
          entry.cancelRate < 0 ||
          entry.cancelRate > 100 ||
          entry.acceptedCount < 0 ||
          entry.acceptedCount > maxCounterValue ||
          entry.rejectedCount < 0 ||
          entry.rejectedCount > maxCounterValue ||
          entry.completedTrips < 0 ||
          entry.completedTrips > maxCounterValue ||
          entry.canceledTrips < 0 ||
          entry.canceledTrips > maxCounterValue) {
        throw const BackupValidationException(BackupErrorCode.invalidSchema);
      }
      if (!entry.isLegacy) {
        if (entry.weekStart == null || entry.weekEnd == null) {
          throw const BackupValidationException(BackupErrorCode.invalidSchema);
        }
        if (entry.goalTier != null &&
            !_allowedGoalTiers.contains(entry.goalTier)) {
          throw const BackupValidationException(BackupErrorCode.invalidSchema);
        }
      }
      validatedArchive.add(entry.toStoredString());
    }

    // 3. Earnings history & fuel receipts
    final earningsRaw = payloadRaw['earningsHistory'];
    if (earningsRaw is! List || earningsRaw.length > kMaxEarningEntries) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    final validatedEarnings = <WeekEarning>[];
    var totalFuelReceipts = 0;
    for (final item in earningsRaw) {
      if (item is! Map) {
        throw const BackupValidationException(BackupErrorCode.invalidSchema);
      }
      final map = Map<String, dynamic>.from(item);
      if (!_isValidEarningMap(map)) {
        throw const BackupValidationException(BackupErrorCode.invalidSchema);
      }
      final earning = WeekEarning.fromJson(map);
      if (earning == null) {
        throw const BackupValidationException(BackupErrorCode.invalidSchema);
      }
      totalFuelReceipts += earning.fuelReceipts.length;
      validatedEarnings.add(earning);
    }

    // 4. Lifetime trips odometer
    final lifetimeRaw = payloadRaw['lifetimeTrips'];
    if (lifetimeRaw is! Map ||
        !lifetimeRaw.keys.toSet().containsAll({'total', 'backfilled'}) ||
        lifetimeRaw.keys.length != 2) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    final lifetimeTotal = _requireIntInRange(
      lifetimeRaw['total'],
      0,
      maxLifetimeTrips,
    );
    final lifetimeBackfilled = _requireBool(lifetimeRaw['backfilled']);

    // 5. Driver profile
    final profileRaw = payloadRaw['driverProfile'];
    if (profileRaw is! Map ||
        !profileRaw.keys.toSet().containsAll({'name', 'mode', 'modeAsked'}) ||
        profileRaw.keys.length != 3) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    final rawName = profileRaw['name'];
    if (rawName is! String || rawName.length > maxDriverNameChars) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    final rawMode = profileRaw['mode'];
    if (rawMode is! String || !_allowedDriverModes.contains(rawMode)) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    final modeAsked = _requireBool(profileRaw['modeAsked']);

    // 6. Settings allowlist
    final settingsRaw = payloadRaw['settings'];
    if (settingsRaw is! Map) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    final validatedSettings = <String, Object>{};
    for (final entry in settingsRaw.entries) {
      final k = entry.key;
      final v = entry.value;
      if (k is! String || !_settingsAllKeys.contains(k)) {
        throw BackupValidationException(
          BackupErrorCode.invalidSchema,
          'Invalid settings key: $k',
        );
      }
      if (k == _keyLang) {
        if (v is! String || !_allowedLangs.contains(v)) {
          throw const BackupValidationException(BackupErrorCode.invalidSchema);
        }
        validatedSettings[k] = v;
      } else if (k == _keyTripGoal) {
        if (v is! String || !_allowedGoalTiers.contains(v)) {
          throw const BackupValidationException(BackupErrorCode.invalidSchema);
        }
        validatedSettings[k] = v;
      } else if (k == PillOrientation.prefsKey) {
        if (v is! String || !_allowedOrientations.contains(v)) {
          throw const BackupValidationException(BackupErrorCode.invalidSchema);
        }
        validatedSettings[k] = v;
      } else if (_settingsBoolKeys.contains(k)) {
        validatedSettings[k] = _requireBool(v);
      }
    }
    if (!validatedSettings.keys.toSet().containsAll(_settingsAllKeys)) {
      throw const BackupValidationException(
        BackupErrorCode.invalidSchema,
        'Missing required setting',
      );
    }

    // Enforce the shade-only invariant (`pillHidden` requires `notificationControls`).
    final notifEnabled = validatedSettings[ShadeControls.prefsKey] as bool;
    final hidePillReq =
        validatedSettings[ShadeControls.hidePillPrefsKey] as bool;
    validatedSettings[ShadeControls.hidePillPrefsKey] =
        ShadeControls.pillHidden(
          notificationControls: notifEnabled,
          hidePill: hidePillReq,
        );

    // 7. Tap history
    final tapRaw = payloadRaw['tapHistory'];
    if (tapRaw is! List || tapRaw.length > TapHistoryStore.maxEntries) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    final validatedTaps = <Map<String, dynamic>>[];
    for (final item in tapRaw) {
      if (item is! Map || !_isValidTapMap(item)) {
        throw const BackupValidationException(BackupErrorCode.invalidSchema);
      }
      validatedTaps.add(<String, dynamic>{
        'type': item['type'].toString(),
        'timestamp': item['timestamp'].toString(),
        'localTime': item['localTime'].toString(),
      });
    }

    final parsedLang = AppLang.values.firstWhere(
      (l) => l.name == validatedSettings[_keyLang],
      orElse: () => AppLang.tr,
    );
    final parsedMode = DriverMode.parse(rawMode);
    final shiftCounters = ShiftCounters(
      accepted: accepted,
      rejected: rejected,
      completed: completed,
      canceled: canceled,
    );

    final preview = BackupPreview(
      createdAt: createdAt,
      appVersion: appVersion.trim(),
      schemaVersion: schemaVersion,
      shiftCounters: shiftCounters,
      shiftWeekStart: shiftWeekStart,
      isFromOlderWeek: isFromOlderWeek,
      weeklyArchiveCount: validatedArchive.length,
      earningsWeekCount: validatedEarnings.length,
      fuelReceiptCount: totalFuelReceipts,
      lifetimeTrips: lifetimeTotal,
      tapHistoryCount: validatedTaps.length,
      driverMode: parsedMode,
      language: parsedLang,
    );

    return ValidatedBackup(
      preview: preview,
      lastResetTimestamp: lastResetMs,
      weeklyArchive: collapseWeeklyArchive(validatedArchive),
      earningsHistory: validatedEarnings,
      lifetimeTripsTotal: lifetimeTotal,
      lifetimeTripsBackfilled: lifetimeBackfilled,
      driverName: _sanitizeDriverName(rawName),
      driverMode: parsedMode,
      driverModeAsked: modeAsked,
      settings: validatedSettings,
      tapHistory: validatedTaps,
    );
  }

  /// Restores [backup] across SharedPreferences, [ShiftCounterStore], and
  /// [TapHistoryStore], guarded by a persistent restore journal.
  ///
  /// If an error occurs mid-restore, this method rolls back to the pre-restore
  /// snapshot and rethrows. If the OS terminates the process mid-restore, the
  /// next launch detects the journal in [recoverPendingRestoreIfNeeded] and
  /// completes the rollback before any screen consumes partial state.
  static Future<void> restoreBackup(
    ValidatedBackup backup, {
    DateTime? now,
    SharedPreferences? prefs,
    ShiftCounterStore? shiftStore,
    TapHistoryStore? tapStore,
    @visibleForTesting Future<void> Function()? onMidRestoreFault,
  }) async {
    await recoverPendingRestoreIfNeeded(
      prefs: prefs,
      shiftStore: shiftStore,
      tapStore: tapStore,
    );

    final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
    final resolvedShiftStore = shiftStore ?? ShiftCounterStore.instance;
    final resolvedTapStore = tapStore ?? TapHistoryStore.instance;

    await resolvedTapStore.migrateFromPrefs(resolvedPrefs);
    await resolvedShiftStore.migrateFromPrefs(resolvedPrefs);

    // 1. Capture pre-restore snapshot and write persistent journal first.
    final journalData = await _capturePreRestoreSnapshot(
      prefs: resolvedPrefs,
      shiftStore: resolvedShiftStore,
      tapStore: resolvedTapStore,
    );
    await _writeJournal(journalData, resolvedPrefs);

    try {
      final clockWarsaw = tz.TZDateTime.from(
        now ?? DateTime.now(),
        warsawLocation(),
      );
      final currentWeekStart = lastMonday4amWarsaw(clockWarsaw);
      final isOlderWeek = backup.preview.shiftWeekStart.isBefore(
        currentWeekStart,
      );

      // Compute final weekly archive and shift counters based on whether the
      // backup belongs to the current Warsaw week or an earlier week.
      var archiveToWrite = List<String>.from(backup.weeklyArchive);
      final ShiftCounters countersToWrite;
      final int resetTimestampToWrite;

      if (isOlderWeek) {
        if (backup.preview.hasShiftActivity) {
          final archivedShift = _buildShiftArchiveEntry(
            counters: backup.preview.shiftCounters,
            weekStart: backup.preview.shiftWeekStart,
            goalTierName: backup.settings[_keyTripGoal] as String? ?? 'tier1',
          );
          if (archivedShift != null) {
            archiveToWrite = collapseWeeklyArchive([
              ...archiveToWrite,
              archivedShift,
            ]);
          }
        }
        countersToWrite = const ShiftCounters();
        resetTimestampToWrite = currentWeekStart.millisecondsSinceEpoch;
      } else {
        countersToWrite = backup.preview.shiftCounters;
        resetTimestampToWrite = math.max(
          backup.lastResetTimestamp,
          currentWeekStart.millisecondsSinceEpoch,
        );
      }

      if (archiveToWrite.length > maxWeeklyArchiveItems) {
        archiveToWrite = archiveToWrite.sublist(
          archiveToWrite.length - maxWeeklyArchiveItems,
        );
      }

      // 2. Write SharedPreferences
      await resolvedPrefs.setInt(_keyLastReset, resetTimestampToWrite);
      await resolvedPrefs.setStringList(_keyArchive, archiveToWrite);
      await resolvedPrefs.setString(
        kEarningsHistoryKey,
        encodeEarnings(backup.earningsHistory),
      );
      if (resolvedPrefs.containsKey(kEarningsCorruptBackupKey)) {
        await resolvedPrefs.remove(kEarningsCorruptBackupKey);
      }
      await resolvedPrefs.setInt(kLifetimeTripsKey, backup.lifetimeTripsTotal);
      await resolvedPrefs.setBool(
        kLifetimeTripsBackfilledKey,
        backup.lifetimeTripsBackfilled,
      );
      await resolvedPrefs.setString(kDriverNameKey, backup.driverName);
      await resolvedPrefs.setString(DriverMode.key, backup.driverMode.name);
      await resolvedPrefs.setBool(DriverMode.askedKey, backup.driverModeAsked);

      if (resolvedPrefs.containsKey(PillOrientation.legacyBoolKey)) {
        await resolvedPrefs.remove(PillOrientation.legacyBoolKey);
      }
      for (final entry in backup.settings.entries) {
        final key = entry.key;
        final val = entry.value;
        if (val is String) {
          await resolvedPrefs.setString(key, val);
        } else if (val is bool) {
          await resolvedPrefs.setBool(key, val);
        }
      }

      // 3. Write verified shift counters
      await resolvedShiftStore.writeVerified(countersToWrite);

      // Test hook to simulate process termination or I/O failure mid-restore.
      if (onMidRestoreFault != null) {
        await onMidRestoreFault();
      }

      // 4. Write verified tap history
      await resolvedTapStore.replaceAll(backup.tapHistory);

      // 5. Commit: remove persistent journal
      await _clearJournal(resolvedPrefs);
    } catch (e, s) {
      loge(
        'restore failed — rolling back from journal',
        name: 'backup',
        error: e,
        stack: s,
      );
      await _applyRollbackSnapshot(
        journalData,
        prefs: resolvedPrefs,
        shiftStore: resolvedShiftStore,
        tapStore: resolvedTapStore,
      );
      await _clearJournal(resolvedPrefs);
      rethrow;
    }
  }

  /// Checks for an incomplete `restore_journal.json` left behind by a crashed
  /// or killed restore, and rolls all stores back to their pre-restore state.
  ///
  /// Must be awaited at app entry points (`main`, `overlayMain`, and store
  /// loaders) before any component reads user data. Returns `true` when a
  /// pending journal was found and recovered.
  static Future<bool> recoverPendingRestoreIfNeeded({
    SharedPreferences? prefs,
    ShiftCounterStore? shiftStore,
    TapHistoryStore? tapStore,
  }) {
    final active = _recoveryInFlight;
    if (active != null) return active;
    if (prefs != null &&
        _journalFileOverride == null &&
        !prefs.containsKey(journalActivePrefsKey)) {
      return Future<bool>.value(false);
    }
    final run = _recoverNow(
      prefs: prefs,
      shiftStore: shiftStore,
      tapStore: tapStore,
    );
    _recoveryInFlight = run.whenComplete(() {
      _recoveryInFlight = null;
    });
    return _recoveryInFlight!;
  }

  static Future<bool> _recoverNow({
    SharedPreferences? prefs,
    ShiftCounterStore? shiftStore,
    TapHistoryStore? tapStore,
  }) async {
    try {
      final resolvedPrefs = prefs ?? await SharedPreferences.getInstance();
      final rawPrefsJournal = resolvedPrefs.get(journalActivePrefsKey);
      final hasPrefsJournal = rawPrefsJournal is bool
          ? rawPrefsJournal
          : (rawPrefsJournal is String && rawPrefsJournal.trim().isNotEmpty);

      if (!hasPrefsJournal && _journalFileOverride == null) {
        return false;
      }

      final file = await _resolveJournalFile();
      Map<String, dynamic>? journal;
      if (file != null && await file.exists()) {
        final raw = await file.readAsString();
        if (raw.trim().isNotEmpty) {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            journal = Map<String, dynamic>.from(decoded);
          }
        }
      }

      if (journal == null && rawPrefsJournal is String) {
        final trimmed = rawPrefsJournal.trim();
        if (trimmed.isNotEmpty) {
          final decoded = jsonDecode(trimmed);
          if (decoded is Map) {
            journal = Map<String, dynamic>.from(decoded);
          }
        }
      }

      if (journal == null) return false;

      final resolvedShiftStore = shiftStore ?? ShiftCounterStore.instance;
      final resolvedTapStore = tapStore ?? TapHistoryStore.instance;

      await _applyRollbackSnapshot(
        journal,
        prefs: resolvedPrefs,
        shiftStore: resolvedShiftStore,
        tapStore: resolvedTapStore,
      );
      await _clearJournal(resolvedPrefs);
      return true;
    } catch (e, s) {
      loge(
        'pending restore recovery failed',
        name: 'backup',
        error: e,
        stack: s,
      );
      return false;
    }
  }

  static bool _isRunningInTestZone() {
    if (Zone.current[#test.declarer] != null) return true;
    try {
      return WidgetsBinding.instance.runtimeType.toString().contains('Test');
    } catch (_) {
      return false;
    }
  }

  static Future<File?> _resolveJournalFile() async {
    final override = _journalFileOverride;
    if (override != null) return override;
    if (_isRunningInTestZone()) {
      return null;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      return File('${dir.path}${Platform.pathSeparator}$journalFileName');
    } catch (_) {
      return null;
    }
  }

  static Future<Map<String, dynamic>> _capturePreRestoreSnapshot({
    required SharedPreferences prefs,
    required ShiftCounterStore shiftStore,
    required TapHistoryStore tapStore,
  }) async {
    final counters = await shiftStore.read();
    final taps = await tapStore.readAll();
    final prefsSnapshot = <String, Map<String, Object?>>{};
    final absentKeys = <String>[];

    for (final key in _managedPrefsKeys) {
      if (!prefs.containsKey(key)) {
        absentKeys.add(key);
        continue;
      }
      final val = prefs.get(key);
      if (val is int) {
        prefsSnapshot[key] = {'t': 'int', 'v': val};
      } else if (val is bool) {
        prefsSnapshot[key] = {'t': 'bool', 'v': val};
      } else if (val is double) {
        prefsSnapshot[key] = {'t': 'double', 'v': val};
      } else if (val is String) {
        prefsSnapshot[key] = {'t': 'string', 'v': val};
      } else if (val is List) {
        final list = prefs.getStringList(key);
        if (list != null) {
          prefsSnapshot[key] = {'t': 'list', 'v': list};
        }
      }
    }

    return <String, dynamic>{
      'state': 'in_progress',
      'startedAt': DateTime.now().toUtc().toIso8601String(),
      'shiftCounters': <String, int>{
        'a': counters.accepted,
        'r': counters.rejected,
        'c': counters.completed,
        'k': counters.canceled,
      },
      'tapHistory': taps,
      'prefs': prefsSnapshot,
      'absentKeys': absentKeys,
    };
  }

  static Future<void> _writeJournal(
    Map<String, dynamic> journal,
    SharedPreferences prefs,
  ) async {
    final encoded = jsonEncode(journal);
    await prefs.setString(journalActivePrefsKey, encoded);
    final file = await _resolveJournalFile();
    if (file == null) return;
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(encoded, flush: true);
    try {
      await tmp.rename(file.path);
    } catch (_) {
      if (await file.exists()) await file.delete();
      await tmp.rename(file.path);
    }
  }

  static Future<void> _clearJournal(SharedPreferences prefs) async {
    final file = await _resolveJournalFile();
    if (file != null) {
      try {
        if (await file.exists()) await file.delete();
      } catch (_) {}
    }
    if (prefs.containsKey(journalActivePrefsKey)) {
      await prefs.remove(journalActivePrefsKey);
    }
  }

  static Future<void> _applyRollbackSnapshot(
    Map<String, dynamic> journal, {
    required SharedPreferences prefs,
    required ShiftCounterStore shiftStore,
    required TapHistoryStore tapStore,
  }) async {
    final absentRaw = journal['absentKeys'];
    if (absentRaw is List) {
      for (final key in absentRaw) {
        if (key is String && prefs.containsKey(key)) {
          await prefs.remove(key);
        }
      }
    }

    final prefsRaw = journal['prefs'];
    if (prefsRaw is Map) {
      for (final entry in prefsRaw.entries) {
        final key = entry.key.toString();
        final desc = entry.value;
        if (desc is! Map) continue;
        final type = desc['t'];
        final value = desc['v'];
        if (type == 'int' && value is int) {
          await prefs.setInt(key, value);
        } else if (type == 'bool' && value is bool) {
          await prefs.setBool(key, value);
        } else if (type == 'double' && value is num) {
          await prefs.setDouble(key, value.toDouble());
        } else if (type == 'string' && value is String) {
          await prefs.setString(key, value);
        } else if (type == 'list' && value is List) {
          await prefs.setStringList(
            key,
            value.map((e) => e.toString()).toList(),
          );
        }
      }
    }

    final shiftRaw = journal['shiftCounters'];
    if (shiftRaw is Map) {
      final restoredCounters = ShiftCounters(
        accepted: (shiftRaw['a'] as num?)?.toInt() ?? 0,
        rejected: (shiftRaw['r'] as num?)?.toInt() ?? 0,
        completed: (shiftRaw['c'] as num?)?.toInt() ?? 0,
        canceled: (shiftRaw['k'] as num?)?.toInt() ?? 0,
      );
      await shiftStore.writeVerified(restoredCounters);
    }

    final tapRaw = journal['tapHistory'];
    if (tapRaw is List) {
      final restoredTaps = <Map<String, dynamic>>[
        for (final item in tapRaw)
          if (item is Map) Map<String, dynamic>.from(item),
      ];
      await tapStore.replaceAll(restoredTaps);
    }
  }

  static String? _buildShiftArchiveEntry({
    required ShiftCounters counters,
    required tz.TZDateTime weekStart,
    required String goalTierName,
  }) {
    final total = counters.accepted + counters.rejected;
    final totalTrips = counters.completed + counters.canceled;
    if (total == 0 && totalTrips == 0) return null;

    final aRate = total == 0 ? 100.0 : (counters.accepted / total) * 100.0;
    final cRate =
        totalTrips == 0 ? 0.0 : (counters.canceled / totalTrips) * 100.0;
    final weekEnd = warsawWeekEndFromStart(weekStart);

    final targetRate = switch (goalTierName) {
      'tier0' => null,
      'tier2' => 70.0,
      'tier3' => 60.0,
      'tier4' => 50.0,
      _ => 80.0,
    };

    final entry = WeeklyArchiveEntry(
      weekStart: weekStart,
      weekEnd: weekEnd,
      acceptRate: aRate,
      cancelRate: cRate,
      acceptedCount: counters.accepted,
      rejectedCount: counters.rejected,
      completedTrips: counters.completed,
      canceledTrips: counters.canceled,
      canceledTripsStored: true,
      goalTier: goalTierName,
      targetAcceptRate: targetRate,
      targetAcceptRateStored: true,
      maxCancelRate: kWeeklyCancelCeiling,
    );
    return entry.encode();
  }

  @visibleForTesting
  static String computePayloadSha256ForTest(Object? payload) =>
      _computePayloadSha256(payload);

  static String _computePayloadSha256(Object? payload) {
    final canonical = jsonEncode(_canonicalizeJson(payload));
    return sha256.convert(utf8.encode(canonical)).toString();
  }

  static Object? _canonicalizeJson(Object? value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      final out = <String, Object?>{};
      for (final k in sortedKeys) {
        out[k] = _canonicalizeJson(value[k]);
      }
      return out;
    }
    if (value is List) {
      return value.map(_canonicalizeJson).toList();
    }
    return value;
  }

  static int _requireIntInRange(Object? value, int min, int max) {
    if (value is! int || value < min || value > max) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    return value;
  }

  static bool _requireBool(Object? value) {
    if (value is! bool) {
      throw const BackupValidationException(BackupErrorCode.invalidSchema);
    }
    return value;
  }

  static bool _isValidMoney(Object? value) {
    if (value is! num) return false;
    final d = value.toDouble();
    return d.isFinite && d >= 0 && d <= maxMoneyPln;
  }

  static bool _isValidRate(Object? value) {
    if (value == null) return true;
    if (value is! num) return false;
    final d = value.toDouble();
    return d.isFinite && d >= 0 && d <= 1.0;
  }

  static bool _isValidEarningMap(Map<String, dynamic> map) {
    final id = map['id'];
    if (id is! String || id.trim().isEmpty || id.length > 120) return false;
    final start = DateTime.tryParse(map['weekStart']?.toString() ?? '');
    final end = DateTime.tryParse(map['weekEnd']?.toString() ?? '');
    if (start == null || end == null || start.year < 2020 || end.year < 2020) {
      return false;
    }
    final mode = map['driverMode'];
    if (mode is! String || !_allowedDriverModes.contains(mode)) return false;
    if (!_isValidMoney(map['netIncome'])) return false;
    if (!_isValidMoney(map['cashReceived'])) return false;
    final hours = map['onlineHours'];
    if (hours is! num ||
        !hours.toDouble().isFinite ||
        hours.toDouble() < 0 ||
        hours.toDouble() > maxWeeklyOnlineHours) {
      return false;
    }
    final trips = map['driverTripCount'] ?? map['tripCount'];
    if (trips is! int || trips < 0 || trips > maxCounterValue) return false;
    if (map.containsKey('carTripCountOverride') &&
        map['carTripCountOverride'] != null) {
      final carTrips = map['carTripCountOverride'];
      if (carTrips is! int || carTrips < 0 || carTrips > maxCounterValue) {
        return false;
      }
    }
    if (map.containsKey('hasRentalDiscount') &&
        map['hasRentalDiscount'] is! bool) {
      return false;
    }
    if (!_isValidRate(map['vatRate']) ||
        !_isValidRate(map['settlementFeeRate']) ||
        !_isValidRate(map['fuelDiscountRate'])) {
      return false;
    }
    if (map.containsKey('rentalFeeSnapshot') &&
        map['rentalFeeSnapshot'] != null &&
        !_isValidMoney(map['rentalFeeSnapshot'])) {
      return false;
    }
    if (map.containsKey('totalCarRentalFeeSnapshot') &&
        map['totalCarRentalFeeSnapshot'] != null &&
        !_isValidMoney(map['totalCarRentalFeeSnapshot'])) {
      return false;
    }
    if (map.containsKey('fuelReceipts')) {
      final receipts = map['fuelReceipts'];
      if (receipts is! List || receipts.length > kMaxFuelReceipts) return false;
      for (final r in receipts) {
        if (r is! Map) return false;
        final rId = r['id'];
        if (rId != null && (rId is! String || rId.length > 120)) return false;
        final rTs = DateTime.tryParse(r['timestamp']?.toString() ?? '');
        if (rTs == null || rTs.year < 2020) return false;
        final amt = r['amountPaid'];
        if (amt is! num ||
            !amt.toDouble().isFinite ||
            amt.toDouble() <= 0 ||
            amt.toDouble() > maxMoneyPln) {
          return false;
        }
      }
    }
    return true;
  }

  static bool _isValidTapMap(Map<dynamic, dynamic> map) {
    if (map.length != 3) return false;
    final type = map['type'];
    final ts = map['timestamp'];
    final localTime = map['localTime'];
    if (type is! String || !_allowedTapTypes.contains(type)) return false;
    if (ts is! String || ts.length > 64 || DateTime.tryParse(ts) == null) {
      return false;
    }
    if (localTime is! String ||
        !RegExp(r'^\d{2}:\d{2}:\d{2}$').hasMatch(localTime)) {
      return false;
    }
    return true;
  }

  static String _sanitizeDriverName(String raw) {
    final trimmed = raw.trim();
    if (trimmed.length <= maxDriverNameChars) return trimmed;
    return trimmed.substring(0, maxDriverNameChars);
  }
}
