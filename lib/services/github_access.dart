import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Opt-in switches for the two GitHub reads that can happen on their own.
///
/// Both default off. The one-time question writes them together; the driver
/// can change either later. Nothing in this file opens a socket.
class GithubAccess {
  static const autoUpdateKey = 'github_auto_update';
  static const autoEventsKey = 'github_auto_events';
  static const promptAnsweredKey = 'github_network_prompt_answered';
  static const lastUpdateCheckKey = 'update_last_checked_ms';

  static final ValueNotifier<DateTime?> lastUpdateCheck = ValueNotifier(null);

  static Completer<void>? _promptGate;
  static int _generation = 0;

  /// Completes once the one-time question has been answered, skipped because
  /// it was already answered, or abandoned because prefs could not be read.
  /// Startup update checks wait on this so they cannot race the dialog.
  static Future<void> get promptSettled {
    return (_promptGate ??= Completer<void>()).future;
  }

  static int get generation => _generation;

  static void markPromptSettled() {
    final gate = _promptGate ??= Completer<void>();
    if (!gate.isCompleted) gate.complete();
  }

  static bool promptAnswered(SharedPreferences prefs) =>
      prefs.getBool(promptAnsweredKey) ?? false;

  static bool autoUpdate(SharedPreferences prefs) =>
      prefs.getBool(autoUpdateKey) ?? false;

  static bool autoEvents(SharedPreferences prefs) =>
      prefs.getBool(autoEventsKey) ?? false;

  static DateTime? readLastCheck(SharedPreferences prefs) {
    final ms = prefs.getInt(lastUpdateCheckKey);
    if (ms == null || ms <= 0) return null;
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }

  static void publishLastCheck(DateTime? when) {
    lastUpdateCheck.value = when;
  }

  static Future<void> applyChoice(
    SharedPreferences prefs, {
    required bool allow,
  }) async {
    await prefs.setBool(promptAnsweredKey, true);
    await prefs.setBool(autoUpdateKey, allow);
    await prefs.setBool(autoEventsKey, allow);
  }

  static Future<void> setAutoUpdate(SharedPreferences prefs, bool value) =>
      prefs.setBool(autoUpdateKey, value);

  static Future<void> setAutoEvents(SharedPreferences prefs, bool value) =>
      prefs.setBool(autoEventsKey, value);

  static Future<void> markUpdateChecked(
    SharedPreferences prefs,
    DateTime when,
  ) async {
    await prefs.setInt(lastUpdateCheckKey, when.millisecondsSinceEpoch);
    publishLastCheck(when);
  }

  /// Drops the in-memory gate so a later test does not inherit a completed
  /// prompt. A stale caller still holding the old generation must not complete
  /// the new gate.
  @visibleForTesting
  static void resetPromptGate() {
    _generation++;
    final gate = _promptGate;
    _promptGate = null;
    if (gate != null && !gate.isCompleted) gate.complete();
    lastUpdateCheck.value = null;
  }
}
