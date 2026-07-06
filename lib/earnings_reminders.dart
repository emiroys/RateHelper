import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import 'l10n.dart';

/// Fully-local weekly "log last week's earnings" reminder. No server, no
/// internet: a single repeating local notification fired every Monday.
///
/// Robustness trade-off (per product decision): the reminder is scheduled
/// unconditionally rather than trying to check whether last week was already
/// logged. A "check-and-skip" can't run reliably while the app is closed, so
/// an occasional false positive (reminding when already logged) is accepted.
class EarningsReminders {
  EarningsReminders._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Stable id for the single repeating Monday reminder.
  static const int _reminderId = 4181;

  static const String _channelId = 'earnings_weekly_reminder';

  /// SharedPreferences flag: reminder on/off. Defaults to ON.
  static const String kEnabledKey = 'mondayReminderEnabled';

  /// Payload delivered on tap so the app can route to the earnings screen and
  /// pre-trigger "add new week".
  static const String tapPayload = 'earnings_add_week';

  /// Default fire time: Monday 09:00 local.
  static const int defaultHour = 9;
  static const int defaultMinute = 0;

  /// Initializes the plugin and requests the runtime notification permission
  /// (Android 13+). [onTap] handles foreground/resumed taps.
  static Future<void> init({
    DidReceiveNotificationResponseCallback? onTap,
  }) async {
    const androidInit =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: onTap,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  /// Details for the app-launch case (cold start from a tapped notification).
  static Future<NotificationAppLaunchDetails?> launchDetails() =>
      _plugin.getNotificationAppLaunchDetails();

  /// Reads the stored on/off flag (defaults to ON when unset).
  static bool isEnabled(SharedPreferences prefs) =>
      prefs.getBool(kEnabledKey) ?? true;

  /// Applies whatever the stored flag says: schedules when ON, cancels when
  /// OFF. Called at boot/app-start so the reminder self-heals after reinstalls
  /// or plugin data resets.
  static Future<void> applyFromPrefs(SharedPreferences prefs) async {
    if (isEnabled(prefs)) {
      await scheduleMondayReminder();
    } else {
      await cancel();
    }
  }

  /// Persists [enabled] and (re)schedules or cancels accordingly.
  static Future<void> setEnabled(
    SharedPreferences prefs,
    bool enabled,
  ) async {
    await prefs.setBool(kEnabledKey, enabled);
    if (enabled) {
      await scheduleMondayReminder();
    } else {
      await cancel();
    }
  }

  static Future<void> cancel() => _plugin.cancel(_reminderId);

  /// Schedules the repeating Monday reminder at [hour]:[minute] local time.
  ///
  /// Uses [DateTimeComponents.dayOfWeekAndTime] so the OS repeats it weekly on
  /// the same weekday/time, and inexact scheduling so no exact-alarm runtime
  /// permission is needed (a weekly nudge does not need to-the-minute timing).
  static Future<void> scheduleMondayReminder({
    int hour = defaultHour,
    int minute = defaultMinute,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      S.reminderChannelName,
      channelDescription: S.reminderChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
    );
    final details = NotificationDetails(android: androidDetails);

    await _plugin.zonedSchedule(
      _reminderId,
      S.reminderNotificationTitle,
      S.reminderNotificationBody,
      _nextMondayInstance(hour, minute),
      details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
      payload: tapPayload,
    );
  }

  /// Next Monday at [hour]:[minute] in the local timezone (strictly in the
  /// future so a reminder set on a Monday after the time still lands next week).
  static tz.TZDateTime _nextMondayInstance(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    while (scheduled.weekday != DateTime.monday ||
        !scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
