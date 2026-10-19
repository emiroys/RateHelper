import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'survey_api.dart';

/// Versioned, installation-scoped survey state.
///
/// Completion is deliberately independent of the app language, onboarding
/// flag, backup/restore settings and overlay isolate. These keys are not part
/// of `BackupService`'s managed-preference set, so restoring an old backup
/// cannot make the questionnaire appear again.
const int kSurveySchemaVersion = 1;
const String kSurveyCompletedPrefsKey = 'survey_v1_completed';
const String kSurveyInstallationIdPrefsKey = 'survey_v1_installation_id';
const String kSurveyPendingPrefsKey = 'survey_v1_pending';
const String kSurveyLastAttemptPrefsKey = 'survey_v1_last_attempt_ms';

enum SurveyContinueChoice { yes, maybe, no }

enum SurveyPriceChoice { five, ten, fifteen, twenty, twentyFivePlus, notPay }

enum SurveyFeatureChoice {
  overlayCounters,
  steeringNotifications,
  earningsRental,
  fuelOrlen,
  weeklyReports,
  other,
}

extension SurveyContinueChoiceWire on SurveyContinueChoice {
  String get wireName => switch (this) {
    SurveyContinueChoice.yes => 'yes',
    SurveyContinueChoice.maybe => 'maybe',
    SurveyContinueChoice.no => 'no',
  };
}

extension SurveyPriceChoiceWire on SurveyPriceChoice {
  String get wireName => switch (this) {
    SurveyPriceChoice.five => '5',
    SurveyPriceChoice.ten => '10',
    SurveyPriceChoice.fifteen => '15',
    SurveyPriceChoice.twenty => '20',
    SurveyPriceChoice.twentyFivePlus => '25_plus',
    SurveyPriceChoice.notPay => 'not_pay',
  };
}

extension SurveyFeatureChoiceWire on SurveyFeatureChoice {
  String get wireName => switch (this) {
    SurveyFeatureChoice.overlayCounters => 'overlay_counters',
    SurveyFeatureChoice.steeringNotifications => 'steering_notifications',
    SurveyFeatureChoice.earningsRental => 'earnings_rental',
    SurveyFeatureChoice.fuelOrlen => 'fuel_orlen',
    SurveyFeatureChoice.weeklyReports => 'weekly_reports',
    SurveyFeatureChoice.other => 'other',
  };
}

@immutable
class SurveyAnswers {
  const SurveyAnswers({
    required this.continueChoice,
    required this.priceChoice,
    required this.featureChoice,
  });

  final SurveyContinueChoice continueChoice;
  final SurveyPriceChoice priceChoice;
  final SurveyFeatureChoice featureChoice;

  /// The exact anonymous payload accepted by the Worker. It contains no name,
  /// phone, email, earnings, trip, location, advertising or Telegram data.
  Map<String, Object> toJson(String installationId) => {
    'schemaVersion': kSurveySchemaVersion,
    'installationId': installationId,
    'continueUsing': continueChoice.wireName,
    'monthlyPrice': priceChoice.wireName,
    'mostValuableFeature': featureChoice.wireName,
  };
}

enum SurveySyncResult { none, delivered, queued }

/// Local queue + retry logic for the one-time survey.
///
/// A completed answer is always written to the local pending slot before the
/// completion flag is set. Network failures therefore never make the survey
/// reappear, and the answer is retried only when the app is foregrounded.
abstract final class SurveyStore {
  static Future<SurveySyncResult>? _syncInFlight;

  static const Duration retryInterval = Duration(minutes: 5);

  static bool isCompleted(SharedPreferences? prefs) =>
      prefs?.getBool(kSurveyCompletedPrefsKey) ?? false;

  /// Existing installs with no versioned flag, and fresh installs after
  /// onboarding, see the survey exactly once.
  static bool shouldShowSurvey(SharedPreferences? prefs) => !isCompleted(prefs);

  static Future<String> installationId(SharedPreferences prefs) async {
    final saved = prefs.getString(kSurveyInstallationIdPrefsKey);
    if (saved != null && RegExp(r'^[a-f0-9]{32}$').hasMatch(saved)) {
      return saved;
    }
    final random = Random.secure();
    final id = List<String>.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    try {
      await prefs.setString(kSurveyInstallationIdPrefsKey, id);
    } catch (_) {
      // The in-memory id still lets this submission proceed. A later launch
      // would generate a new id, which only makes dedupe best-effort.
    }
    return id;
  }

  static Future<bool> savePending(
    SharedPreferences prefs,
    Map<String, Object> payload,
  ) async {
    try {
      return await prefs.setString(kSurveyPendingPrefsKey, jsonEncode(payload));
    } catch (_) {
      return false;
    }
  }

  static Future<bool> markCompleted(SharedPreferences prefs) async {
    try {
      return await prefs.setBool(kSurveyCompletedPrefsKey, true);
    } catch (_) {
      return false;
    }
  }

  static Future<void> clearPending(SharedPreferences prefs) async {
    try {
      await prefs.remove(kSurveyPendingPrefsKey);
      await prefs.remove(kSurveyLastAttemptPrefsKey);
    } catch (_) {}
  }

  static String? pendingJson(SharedPreferences prefs) =>
      prefs.getString(kSurveyPendingPrefsKey);

  /// Retries one queued answer. There is no timer and no background polling:
  /// callers invoke this on app startup/resume, or after a fresh submission.
  static Future<SurveySyncResult> syncPending({
    SharedPreferences? prefs,
    SurveyApi? api,
    bool force = false,
    DateTime? now,
  }) {
    final active = _syncInFlight;
    if (active != null) return active;
    final run = _syncNow(prefs: prefs, api: api, force: force, now: now);
    _syncInFlight = run.whenComplete(() {
      _syncInFlight = null;
    });
    return _syncInFlight!;
  }

  static Future<SurveySyncResult> _syncNow({
    SharedPreferences? prefs,
    SurveyApi? api,
    required bool force,
    DateTime? now,
  }) async {
    SharedPreferences? resolvedPrefs = prefs;
    try {
      resolvedPrefs ??= await SharedPreferences.getInstance();
      final raw = resolvedPrefs.getString(kSurveyPendingPrefsKey);
      if (raw == null) return SurveySyncResult.none;

      Map<String, dynamic> payload;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          await clearPending(resolvedPrefs);
          return SurveySyncResult.none;
        }
        payload = Map<String, dynamic>.from(decoded);
      } catch (_) {
        await clearPending(resolvedPrefs);
        return SurveySyncResult.none;
      }

      final clock = now ?? DateTime.now();
      if (!force) {
        final last = resolvedPrefs.getInt(kSurveyLastAttemptPrefsKey) ?? 0;
        if (clock.millisecondsSinceEpoch - last <
            retryInterval.inMilliseconds) {
          return SurveySyncResult.queued;
        }
      }

      final client = api ?? SurveyApi.fromEnvironment();
      if (client == null) return SurveySyncResult.queued;

      final outcome = await client.submit(payload);
      if (outcome == SurveySubmitOutcome.sent ||
          outcome == SurveySubmitOutcome.duplicate) {
        await clearPending(resolvedPrefs);
        return SurveySyncResult.delivered;
      }

      try {
        await resolvedPrefs.setInt(
          kSurveyLastAttemptPrefsKey,
          clock.millisecondsSinceEpoch,
        );
      } catch (_) {}
      return SurveySyncResult.queued;
    } catch (_) {
      return SurveySyncResult.queued;
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _syncInFlight = null;
  }
}
