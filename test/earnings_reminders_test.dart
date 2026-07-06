import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_platform_interface/flutter_local_notifications_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rate_helper/earnings_reminders.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Verifies the Monday-reminder toggle actually drives the platform plugin:
/// turning it OFF cancels the pending scheduled notification, and turning it ON
/// (re)schedules exactly one — with the stable reminder id, so re-enabling can
/// never stack duplicate overlapping schedules.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('dexterous.com/flutter/local_notifications');
  final calls = <MethodCall>[];

  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Warsaw'));
    // The facade routes Android calls through this platform instance; without
    // it the plugin throws a LateInitializationError in a host unit test.
    FlutterLocalNotificationsPlatform.instance =
        AndroidFlutterLocalNotificationsPlugin();
  });

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getNotificationAppLaunchDetails') {
        return <String, dynamic>{'notificationLaunchedApp': false};
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  List<MethodCall> callsNamed(String name) =>
      calls.where((c) => c.method == name).toList();

  int idOf(MethodCall call) =>
      (call.arguments as Map<Object?, Object?>)['id'] as int;

  test('turning the reminder OFF cancels the pending notification', () async {
    final prefs = await SharedPreferences.getInstance();
    await EarningsReminders.setEnabled(prefs, false);

    expect(EarningsReminders.isEnabled(prefs), isFalse);
    expect(callsNamed('cancel'), hasLength(1));
    // OFF must not (re)schedule anything.
    expect(callsNamed('zonedSchedule'), isEmpty);
  });

  test('the cancel targets the single stable reminder id', () async {
    final prefs = await SharedPreferences.getInstance();
    await EarningsReminders.setEnabled(prefs, false);

    expect(idOf(callsNamed('cancel').single), 4181);
  });

  test('turning it ON schedules exactly one reminder', () async {
    final prefs = await SharedPreferences.getInstance();
    await EarningsReminders.setEnabled(prefs, true);

    expect(EarningsReminders.isEnabled(prefs), isTrue);
    expect(callsNamed('zonedSchedule'), hasLength(1));
    expect(callsNamed('cancel'), isEmpty);
  });

  test('re-enabling does not stack duplicate schedules (same id reused)',
      () async {
    final prefs = await SharedPreferences.getInstance();
    await EarningsReminders.setEnabled(prefs, true);
    await EarningsReminders.setEnabled(prefs, true);

    final schedules = callsNamed('zonedSchedule');
    // One schedule call per toggle, each with the same reminder id — the OS
    // treats a repeat id as a replace, so no overlapping duplicates accrue.
    expect(schedules, hasLength(2));
    for (final s in schedules) {
      expect(idOf(s), 4181);
    }
  });

  test('off then on cancels, then schedules (clean re-arm)', () async {
    final prefs = await SharedPreferences.getInstance();
    await EarningsReminders.setEnabled(prefs, false);
    await EarningsReminders.setEnabled(prefs, true);

    expect(callsNamed('cancel'), hasLength(1));
    expect(callsNamed('zonedSchedule'), hasLength(1));
    expect(EarningsReminders.isEnabled(prefs), isTrue);
  });
}
