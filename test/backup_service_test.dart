import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/earnings_models.dart';
import 'package:rate_helper/earnings_screen.dart' show kDriverNameKey;
import 'package:rate_helper/l10n.dart';
import 'package:rate_helper/models/weekly_archive_entry.dart';
import 'package:rate_helper/overlay_widget.dart';
import 'package:rate_helper/services/backup_service.dart';
import 'package:rate_helper/services/github_access.dart';
import 'package:rate_helper/shade_controls.dart';
import 'package:rate_helper/shift_counter_store.dart';
import 'package:rate_helper/tap_history_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_10y.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(tz_data.initializeTimeZones);

  late Directory tmpDir;
  late File shiftFile;
  late File tapFile;
  late File journalFile;
  late tz.Location warsaw;

  setUp(() async {
    warsaw = tz.getLocation('Europe/Warsaw');
    tmpDir = await Directory.systemTemp.createTemp('ratehelper_backup_test_');
    shiftFile = File(
      '${tmpDir.path}${Platform.pathSeparator}shift_counters.json',
    );
    tapFile = File('${tmpDir.path}${Platform.pathSeparator}tap_history.jsonl');
    journalFile = File(
      '${tmpDir.path}${Platform.pathSeparator}restore_journal.json',
    );

    ShiftCounterStore.resetInstanceForTest(file: shiftFile);
    TapHistoryStore.resetInstanceForTest(file: tapFile);
    BackupService.resetForTest(journalFile: journalFile);
    SharedPreferences.setMockInitialValues({});
    S.setLang(AppLang.tr);
    activeDriverMode = DriverMode.solo;
  });

  tearDown(() async {
    BackupService.resetForTest();
    ShiftCounterStore.resetInstanceForTest();
    TapHistoryStore.resetInstanceForTest();
    if (await tmpDir.exists()) {
      await tmpDir.delete(recursive: true);
    }
  });

  /// Re-computes the envelope SHA-256 so tests can verify that schema and range
  /// checks reject malicious payloads even when their checksum matches.
  String resignEnvelope(Map<String, dynamic> envelope) {
    final payload = envelope['payload'] as Map<String, dynamic>;
    final digest = BackupService.computePayloadSha256ForTest(payload);
    final copy = Map<String, dynamic>.from(envelope)..['sha256'] = digest;
    return const JsonEncoder.withIndent('  ').convert(copy);
  }

  test(
    'full backup & restore round-trip preserves all user data and excludes caches',
    () async {
      final now = tz.TZDateTime(warsaw, 2026, 5, 13, 14, 30); // Wednesday
      final monday4am = BackupService.lastMonday4amWarsaw(now);
      final prevMonday = tz.TZDateTime(warsaw, 2026, 5, 4, 4, 0);
      final prevSunday = tz.TZDateTime(warsaw, 2026, 5, 10, 4, 0);

      final archiveEntry = WeeklyArchiveEntry(
        weekStart: prevMonday,
        weekEnd: prevSunday,
        acceptRate: 88.0,
        cancelRate: 4.0,
        acceptedCount: 88,
        rejectedCount: 12,
        completedTrips: 84,
        canceledTrips: 4,
        canceledTripsStored: true,
        goalTier: 'tier2',
        targetAcceptRate: 70.0,
        targetAcceptRateStored: true,
        maxCancelRate: 10.0,
      );

      final earningsEntry = WeekEarning(
        id: '${prevMonday.millisecondsSinceEpoch}_${prevSunday.millisecondsSinceEpoch}',
        weekStart: DateTime(2026, 5, 4),
        weekEnd: DateTime(2026, 5, 10),
        driverMode: DriverMode.paired,
        netIncome: 4250.50,
        cashReceived: 620.00,
        onlineHours: 48.5,
        driverTripCount: 112,
        carTripCountOverride: 210,
        hasRentalDiscount: false,
        fuelReceipts: [
          FuelReceipt(
            timestamp: DateTime(2026, 5, 5, 9, 15),
            amountPaid: 210.40,
          ),
          FuelReceipt(
            timestamp: DateTime(2026, 5, 8, 18, 45),
            amountPaid: 185.60,
          ),
        ],
      );

      SharedPreferences.setMockInitialValues({
        'lastResetTimestamp': monday4am.millisecondsSinceEpoch,
        'weekly_archive': [archiveEntry.encode()],
        kEarningsHistoryKey: encodeEarnings([earningsEntry]),
        kLifetimeTripsKey: 1450,
        kLifetimeTripsBackfilledKey: true,
        kDriverNameKey: 'Emir Test',
        DriverMode.key: 'paired',
        DriverMode.askedKey: true,
        'trip_goal_tier': 'tier2',
        'autoCompleteTrips': true,
        'steeringWheelEnabled': true,
        'keepScreenOn': true,
        PillOrientation.prefsKey: 'vertical',
        OverlayWidget.cancelButtonPrefsKey: true,
        OverlayWidget.collapsedPrefsKey: true,
        ShadeControls.prefsKey: true,
        ShadeControls.hidePillPrefsKey: false,
        'appLanguage': 'pl',
        'onboardingComplete': true,
        GithubAccess.promptAnsweredKey: true,
        GithubAccess.autoUpdateKey: true,
        GithubAccess.autoEventsKey: false,
        // Ephemeral cache keys that MUST NOT be exported:
        'fuel_prices_poland_cache_v1': '{"cached":true}',
        'events_cache_json': '[{"title":"Cached"}]',
        'events_cache_timestamp': 1700000000000,
        GithubAccess.lastUpdateCheckKey: 1700000000000,
        kEarningsCorruptBackupKey: 'corrupt_raw_blob',
      });

      final prefs = await SharedPreferences.getInstance();
      await ShiftCounterStore.instance.writeVerified(
        const ShiftCounters(
          accepted: 34,
          rejected: 6,
          completed: 31,
          canceled: 2,
        ),
      );
      await TapHistoryStore.instance.append(
        'accepted',
        at: DateTime.utc(2026, 5, 13, 10, 0, 0),
      );
      await TapHistoryStore.instance.append(
        'rejected',
        at: DateTime.utc(2026, 5, 13, 10, 5, 0),
      );

      final jsonStr = await BackupService.createBackupJson(
        prefs: prefs,
        appVersion: '5.0.5',
        now: now,
      );

      // Verify excluded cache keys are absent from the exported JSON.
      expect(jsonStr, isNot(contains('fuel_prices_poland_cache_v1')));
      expect(jsonStr, isNot(contains('events_cache_json')));
      expect(jsonStr, isNot(contains('github_last_update_check_ms')));
      expect(jsonStr, isNot(contains('corrupt_raw_blob')));

      // Wipe all local stores to simulate a fresh install on a new phone.
      await prefs.clear();
      await ShiftCounterStore.instance.writeVerified(const ShiftCounters());
      await TapHistoryStore.instance.clear();

      final validated = BackupService.validateBackupJson(jsonStr, now: now);
      expect(validated.preview.isFromOlderWeek, isFalse);
      expect(validated.preview.weeklyArchiveCount, 1);
      expect(validated.preview.earningsWeekCount, 1);
      expect(validated.preview.fuelReceiptCount, 2);
      expect(validated.preview.lifetimeTrips, 1450);
      expect(validated.preview.tapHistoryCount, 2);
      expect(validated.preview.driverMode, DriverMode.paired);
      expect(validated.preview.language, AppLang.pl);

      await BackupService.restoreBackup(validated, prefs: prefs, now: now);

      // Verify all stores are restored identically.
      final restoredCounters = await ShiftCounterStore.instance.read();
      expect(
        restoredCounters,
        const ShiftCounters(
          accepted: 34,
          rejected: 6,
          completed: 31,
          canceled: 2,
        ),
      );

      final restoredTaps = await TapHistoryStore.instance.readAll();
      expect(restoredTaps, hasLength(2));
      expect(restoredTaps[0]['type'], 'accepted');
      expect(restoredTaps[1]['type'], 'rejected');

      expect(prefs.getString(kDriverNameKey), 'Emir Test');
      expect(prefs.getString(DriverMode.key), 'paired');
      expect(prefs.getBool(DriverMode.askedKey), isTrue);
      expect(prefs.getInt(kLifetimeTripsKey), 1450);
      expect(prefs.getBool(kLifetimeTripsBackfilledKey), isTrue);
      expect(prefs.getString('trip_goal_tier'), 'tier2');
      expect(prefs.getBool('autoCompleteTrips'), isTrue);
      expect(prefs.getBool('steeringWheelEnabled'), isTrue);
      expect(prefs.getBool('keepScreenOn'), isTrue);
      expect(prefs.getString(PillOrientation.prefsKey), 'vertical');
      expect(prefs.getBool(OverlayWidget.cancelButtonPrefsKey), isTrue);
      expect(prefs.getBool(OverlayWidget.collapsedPrefsKey), isTrue);
      expect(prefs.getBool(ShadeControls.prefsKey), isTrue);
      expect(prefs.getBool(ShadeControls.hidePillPrefsKey), isFalse);
      expect(prefs.getString('appLanguage'), 'pl');
      expect(prefs.getBool('onboardingComplete'), isTrue);
      expect(prefs.getBool(GithubAccess.promptAnsweredKey), isTrue);
      expect(prefs.getBool(GithubAccess.autoUpdateKey), isTrue);
      expect(prefs.getBool(GithubAccess.autoEventsKey), isFalse);

      final restoredEarnings = decodeEarnings(
        prefs.getString(kEarningsHistoryKey),
      );
      expect(restoredEarnings, hasLength(1));
      expect(restoredEarnings.first.netIncome, 4250.50);
      expect(restoredEarnings.first.carTripCountOverride, 210);
      expect(restoredEarnings.first.fuelReceipts, hasLength(2));
      expect(restoredEarnings.first.fuelReceipts[0].amountPaid, 210.40);
      expect(restoredEarnings.first.fuelReceipts[1].amountPaid, 185.60);

      final restoredArchive = prefs.getStringList('weekly_archive')!;
      expect(restoredArchive, hasLength(1));
      final decodedArchive = WeeklyArchiveEntry.parse(restoredArchive.first);
      expect(decodedArchive.acceptedCount, 88);
      expect(decodedArchive.completedTrips, 84);
      expect(decodedArchive.goalTier, 'tier2');

      // Journal must be cleaned up after a successful restore.
      expect(await journalFile.exists(), isFalse);
      expect(prefs.getBool(BackupService.journalActivePrefsKey), isNull);
    },
  );

  group('validation & tamper resistance', () {
    late String validBackupJson;
    late tz.TZDateTime now;

    setUp(() async {
      now = tz.TZDateTime(warsaw, 2026, 5, 13, 12, 0);
      final prefs = await SharedPreferences.getInstance();
      await ShiftCounterStore.instance.writeVerified(
        const ShiftCounters(accepted: 10, rejected: 2, completed: 9),
      );
      validBackupJson = await BackupService.createBackupJson(
        prefs: prefs,
        appVersion: '5.0.5',
        now: now,
      );
    });

    test('rejects corrupt JSON and checksum mismatch', () {
      expect(
        () => BackupService.validateBackupJson('{not valid json', now: now),
        throwsA(
          isA<BackupValidationException>().having(
            (e) => e.code,
            'code',
            BackupErrorCode.invalidJson,
          ),
        ),
      );

      final tampered = validBackupJson.replaceFirst(
        '"a": 10',
        '"a": 99',
      );
      expect(
        () => BackupService.validateBackupJson(tampered, now: now),
        throwsA(
          isA<BackupValidationException>().having(
            (e) => e.code,
            'code',
            BackupErrorCode.corruptChecksum,
          ),
        ),
      );
    });

    test('rejects unsupported schemaVersion and app identifier', () {
      final map = jsonDecode(validBackupJson) as Map<String, dynamic>;
      map['schemaVersion'] = 99;
      expect(
        () => BackupService.validateBackupJson(jsonEncode(map), now: now),
        throwsA(
          isA<BackupValidationException>().having(
            (e) => e.code,
            'code',
            BackupErrorCode.unsupportedVersion,
          ),
        ),
      );

      final badFormat = jsonDecode(validBackupJson) as Map<String, dynamic>;
      badFormat['app'] = 'OtherApp';
      expect(
        () => BackupService.validateBackupJson(jsonEncode(badFormat), now: now),
        throwsA(
          isA<BackupValidationException>().having(
            (e) => e.code,
            'code',
            BackupErrorCode.unsupportedFormat,
          ),
        ),
      );
    });

    test('rejects out-of-range counters even with a valid SHA-256', () {
      final map = jsonDecode(validBackupJson) as Map<String, dynamic>;
      final payload = map['payload'] as Map<String, dynamic>;
      (payload['shiftCounters'] as Map<String, dynamic>)['a'] = 100000;
      final forged = resignEnvelope(map);

      expect(
        () => BackupService.validateBackupJson(forged, now: now),
        throwsA(
          isA<BackupValidationException>().having(
            (e) => e.code,
            'code',
            BackupErrorCode.invalidSchema,
          ),
        ),
      );
    });

    test(
      'rejects unknown settings keys or secret injections even with valid SHA-256',
      () {
        final map = jsonDecode(validBackupJson) as Map<String, dynamic>;
        final payload = map['payload'] as Map<String, dynamic>;
        (payload['settings'] as Map<String, dynamic>)['FUEL_PROXY_TOKEN'] =
            'leaked';
        final forged = resignEnvelope(map);

        expect(
          () => BackupService.validateBackupJson(forged, now: now),
          throwsA(
            isA<BackupValidationException>().having(
              (e) => e.code,
              'code',
              BackupErrorCode.invalidSchema,
            ),
          ),
        );
      },
    );

    test('rejects backups with future timestamps > 24h ahead', () {
      final map = jsonDecode(validBackupJson) as Map<String, dynamic>;
      map['createdAt'] = now
          .add(const Duration(days: 3))
          .toUtc()
          .toIso8601String();
      final forged = resignEnvelope(map);

      expect(
        () => BackupService.validateBackupJson(forged, now: now),
        throwsA(
          isA<BackupValidationException>().having(
            (e) => e.code,
            'code',
            BackupErrorCode.futureTimestamp,
          ),
        ),
      );
    });
  });

  group('historical backups, Monday 04:00 Europe/Warsaw & DST boundaries', () {
    test(
      'restoring a backup from 3 weeks ago archives its shift counters into that week and starts current week at 0',
      () async {
        // Backup created on Wednesday 2026-04-22 15:00 Warsaw (week of Mon 2026-04-20 04:00)
        final backupTime = tz.TZDateTime(warsaw, 2026, 4, 22, 15, 0);
        // Even if lastResetTimestamp was 0 (first week after install), weekStart
        // must be classified as 2026-04-20 04:00 Warsaw, never 1970 or current week.
        SharedPreferences.setMockInitialValues({
          'lastResetTimestamp': 0,
          'trip_goal_tier': 'tier3',
        });
        final prefs = await SharedPreferences.getInstance();
        await ShiftCounterStore.instance.writeVerified(
          const ShiftCounters(
            accepted: 60,
            rejected: 15,
            completed: 55,
            canceled: 5,
          ),
        );

        final oldBackupJson = await BackupService.createBackupJson(
          prefs: prefs,
          appVersion: '5.0.4',
          now: backupTime,
        );

        // Now it is 3 weeks later: Wednesday 2026-05-13 18:00 Warsaw
        final restoreTime = tz.TZDateTime(warsaw, 2026, 5, 13, 18, 0);
        final currentMonday4am = BackupService.lastMonday4amWarsaw(restoreTime);

        final validated = BackupService.validateBackupJson(
          oldBackupJson,
          now: restoreTime,
        );
        expect(validated.preview.isFromOlderWeek, isTrue);
        expect(
          validated.preview.shiftWeekStart,
          tz.TZDateTime(warsaw, 2026, 4, 20, 4, 0),
        );

        await BackupService.restoreBackup(
          validated,
          prefs: prefs,
          now: restoreTime,
        );

        // Active shift counters for the current week must start at 0.
        final activeCounters = await ShiftCounterStore.instance.read();
        expect(activeCounters, const ShiftCounters());

        // lastResetTimestamp must be set to current week's Monday 04:00 so Home
        // does not perform a duplicate reset.
        expect(
          prefs.getInt('lastResetTimestamp'),
          currentMonday4am.millisecondsSinceEpoch,
        );

        // The old shift counters must be archived under 2026-04-20 .. 2026-04-26.
        final archiveRaw = prefs.getStringList('weekly_archive') ?? [];
        expect(archiveRaw, hasLength(1));
        final archived = WeeklyArchiveEntry.parse(archiveRaw.first);
        expect(archived.acceptedCount, 60);
        expect(archived.rejectedCount, 15);
        expect(archived.completedTrips, 55);
        expect(archived.canceledTrips, 5);
        expect(archived.goalTier, 'tier3');
        expect(archived.weekStart!.year, 2026);
        expect(archived.weekStart!.month, 4);
        expect(archived.weekStart!.day, 20);
      },
    );

    test(
      'Monday 03:59:59 vs 04:00:00 Europe/Warsaw boundary classifies weeks accurately',
      () async {
        final before4am = tz.TZDateTime(warsaw, 2026, 5, 11, 3, 59, 59);
        final at4am = tz.TZDateTime(warsaw, 2026, 5, 11, 4, 0, 0);

        final weekBefore = BackupService.lastMonday4amWarsaw(before4am);
        final weekAt = BackupService.lastMonday4amWarsaw(at4am);

        expect(weekBefore, tz.TZDateTime(warsaw, 2026, 5, 4, 4, 0));
        expect(weekAt, tz.TZDateTime(warsaw, 2026, 5, 11, 4, 0));

        // A backup taken at Monday 03:55 and restored 10 minutes later at
        // Monday 04:05 crosses the weekly reset boundary and must archive its
        // counters into the week of May 4.
        final prefs = await SharedPreferences.getInstance();
        await ShiftCounterStore.instance.writeVerified(
          const ShiftCounters(accepted: 12, rejected: 3, completed: 12),
        );
        final jsonAt0355 = await BackupService.createBackupJson(
          prefs: prefs,
          appVersion: '5.0.5',
          now: tz.TZDateTime(warsaw, 2026, 5, 11, 3, 55),
        );

        final validatedAt0405 = BackupService.validateBackupJson(
          jsonAt0355,
          now: tz.TZDateTime(warsaw, 2026, 5, 11, 4, 5),
        );
        expect(validatedAt0405.preview.isFromOlderWeek, isTrue);
        expect(
          validatedAt0405.preview.shiftWeekStart,
          tz.TZDateTime(warsaw, 2026, 5, 4, 4, 0),
        );
      },
    );

    test(
      'Spring (CET->CEST) and Autumn (CEST->CET) DST transitions preserve Monday 04:00 Warsaw boundaries',
      () {
        // Spring forward in Europe/Warsaw: Sunday 2026-03-29 02:00 -> 03:00.
        final afterSpringDst = tz.TZDateTime(warsaw, 2026, 3, 30, 3, 30);
        final springPrevMonday = BackupService.lastMonday4amWarsaw(
          afterSpringDst,
        );
        expect(springPrevMonday, tz.TZDateTime(warsaw, 2026, 3, 23, 4, 0));
        expect(springPrevMonday.hour, 4);

        final springNextMonday = BackupService.lastMonday4amWarsaw(
          tz.TZDateTime(warsaw, 2026, 3, 30, 4, 0),
        );
        expect(springNextMonday, tz.TZDateTime(warsaw, 2026, 3, 30, 4, 0));
        expect(springNextMonday.hour, 4);

        // Fall back in Europe/Warsaw: Sunday 2026-10-25 03:00 -> 02:00.
        final afterFallDst = tz.TZDateTime(warsaw, 2026, 10, 26, 3, 30);
        final fallPrevMonday = BackupService.lastMonday4amWarsaw(afterFallDst);
        expect(fallPrevMonday, tz.TZDateTime(warsaw, 2026, 10, 19, 4, 0));
        expect(fallPrevMonday.hour, 4);

        final fallNextMonday = BackupService.lastMonday4amWarsaw(
          tz.TZDateTime(warsaw, 2026, 10, 26, 4, 0),
        );
        expect(fallNextMonday, tz.TZDateTime(warsaw, 2026, 10, 26, 4, 0));
        expect(fallNextMonday.hour, 4);
      },
    );
  });

  group('interrupted restore & startup journal recovery', () {
    test(
      'process termination mid-restore is detected on next startup and recovers pre-restore data across all 3 stores',
      () async {
        final now = tz.TZDateTime(warsaw, 2026, 5, 13, 16, 0);
        final monday4am = BackupService.lastMonday4amWarsaw(now);

        // 1. Seed Backup B (the incoming backup we will attempt to restore).
        SharedPreferences.setMockInitialValues({
          'lastResetTimestamp': monday4am.millisecondsSinceEpoch,
          kDriverNameKey: 'Incoming Backup Driver',
          DriverMode.key: 'trio',
          kLifetimeTripsKey: 9999,
          kLifetimeTripsBackfilledKey: true,
          'appLanguage': 'en',
        });
        var prefs = await SharedPreferences.getInstance();
        await ShiftCounterStore.instance.writeVerified(
          const ShiftCounters(
            accepted: 90,
            rejected: 10,
            completed: 85,
            canceled: 5,
          ),
        );
        await TapHistoryStore.instance.replaceAll([
          {
            'type': 'accepted',
            'timestamp': '2026-05-13T12:00:00.000Z',
            'localTime': '14:00:00',
          },
        ]);

        final incomingBackupJson = await BackupService.createBackupJson(
          prefs: prefs,
          appVersion: '5.0.5',
          now: now,
        );
        final validatedIncoming = BackupService.validateBackupJson(
          incomingBackupJson,
          now: now,
        );

        // 2. Now set up the user's CURRENT live data (Pre-Restore State A).
        await prefs.clear();
        await prefs.setInt(
          'lastResetTimestamp',
          monday4am.millisecondsSinceEpoch,
        );
        await prefs.setString(kDriverNameKey, 'Original Live Driver');
        await prefs.setString(DriverMode.key, 'solo');
        await prefs.setInt(kLifetimeTripsKey, 321);
        await prefs.setBool(kLifetimeTripsBackfilledKey, true);
        await prefs.setString('appLanguage', 'tr');
        // Also seed a non-backup cache key to ensure recovery doesn't break it.
        await prefs.setString('fuel_prices_poland_cache_v1', '{"keep":1}');

        await ShiftCounterStore.instance.writeVerified(
          const ShiftCounters(
            accepted: 17,
            rejected: 3,
            completed: 16,
            canceled: 1,
          ),
        );
        await TapHistoryStore.instance.replaceAll([
          {
            'type': 'rejected',
            'timestamp': '2026-05-13T08:00:00.000Z',
            'localTime': '10:00:00',
          },
          {
            'type': 'accepted',
            'timestamp': '2026-05-13T08:05:00.000Z',
            'localTime': '10:05:00',
          },
        ]);

        // 3. Simulate process kill (`_SimulatedProcessKill`) halfway through
        //    restoreBackup — AFTER SharedPreferences and ShiftCounterStore have
        //    already been overwritten with Incoming Backup B, but BEFORE
        //    TapHistoryStore is written or the journal is deleted!
        //    To simulate hard process death (where the catch block in Dart
        //    never gets to run), we snapshot the journal file inside the fault
        //    hook and re-materialize it before startup recovery runs.
        late String journalSnapshotOnCrash;
        await expectLater(
          () => BackupService.restoreBackup(
            validatedIncoming,
            prefs: prefs,
            now: now,
            onMidRestoreFault: () async {
              // At this exact point in restoreBackup:
              // - journalFile exists on disk
              // - prefs has been overwritten with 'Incoming Backup Driver'
              // - ShiftCounterStore has been overwritten with 90/10/85/5
              expect(await journalFile.exists(), isTrue);
              expect(
                prefs.getString(kDriverNameKey),
                'Incoming Backup Driver',
              );
              expect(
                (await ShiftCounterStore.instance.read()).accepted,
                90,
              );
              journalSnapshotOnCrash = await journalFile.readAsString();
              throw StateError('Simulated Android process kill mid-restore');
            },
          ),
          throwsStateError,
        );

        // Even if the process was killed by SIGKILL before Dart's catch block
        // could run, the stores on disk would hold the half-restored state and
        // `restore_journal.json` would still sit on disk. Let's put the stores
        // into that exact half-restored SIGKILL state and verify startup
        // recovery (`recoverPendingRestoreIfNeeded`) heals everything!
        await prefs.setString(kDriverNameKey, 'Incoming Backup Driver');
        await prefs.setInt(kLifetimeTripsKey, 9999);
        await prefs.setBool(BackupService.journalActivePrefsKey, true);
        await ShiftCounterStore.instance.writeVerified(
          const ShiftCounters(
            accepted: 90,
            rejected: 10,
            completed: 85,
            canceled: 5,
          ),
        );
        await journalFile.writeAsString(journalSnapshotOnCrash, flush: true);

        // 4. Simulate next app launch: startup recovery runs before any screen
        //    or overlay reads user data.
        BackupService.resetForTest(journalFile: journalFile);
        final recovered = await BackupService.recoverPendingRestoreIfNeeded(
          prefs: prefs,
        );
        expect(recovered, isTrue);

        // Verify all 3 stores are back to Original Live State A!
        expect(prefs.getString(kDriverNameKey), 'Original Live Driver');
        expect(prefs.getString(DriverMode.key), 'solo');
        expect(prefs.getInt(kLifetimeTripsKey), 321);
        expect(prefs.getString('appLanguage'), 'tr');
        expect(prefs.getString('fuel_prices_poland_cache_v1'), '{"keep":1}');

        final countersAfterRecovery = await ShiftCounterStore.instance.read();
        expect(
          countersAfterRecovery,
          const ShiftCounters(
            accepted: 17,
            rejected: 3,
            completed: 16,
            canceled: 1,
          ),
        );

        final tapsAfterRecovery = await TapHistoryStore.instance.readAll();
        expect(tapsAfterRecovery, hasLength(2));
        expect(tapsAfterRecovery[0]['type'], 'rejected');
        expect(tapsAfterRecovery[1]['type'], 'accepted');

        // Journal and active flag must be removed after recovery completes.
        expect(await journalFile.exists(), isFalse);
        expect(prefs.getBool(BackupService.journalActivePrefsKey), isNull);
      },
    );
  });
}
