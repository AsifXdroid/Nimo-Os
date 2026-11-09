// SET — PluginReminderGateway timezone behaviour (audit Step 3,
// finding 001): when the flutter_timezone lookup FAILS, the
// gateway must NOT schedule against the timezone package's
// default location (UTC) — that fired reminders shifted by the
// device's UTC offset, silently. Scheduling is skipped, the
// lookup is retried on the next call, and once it succeeds,
// scheduling proceeds in the real zone. Both platform plugins
// are mocked at their method channels; nothing here touches a
// real device service.
import 'package:daily_life_app/features/settings/reminder_gateway.dart';
import 'package:daily_life_app/features/settings/reminders.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Normally registered by the Android embedding's GeneratedPlugin
  // Registrant; in a host test nothing registers it, and the
  // plugin's platform instance is a late field — register the
  // method-channel implementation explicitly.
  FlutterLocalNotificationsPlatform.instance =
      AndroidFlutterLocalNotificationsPlugin();

  const tzChannel = MethodChannel('flutter_timezone');
  const notifChannel = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  var tzFails = true;
  var tzCalls = 0;
  final notifMethods = <String>[];
  final zonedArgs = <Map<dynamic, dynamic>>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    tzFails = true;
    tzCalls = 0;
    notifMethods.clear();
    zonedArgs.clear();
    messenger.setMockMethodCallHandler(tzChannel, (call) async {
      tzCalls++;
      if (tzFails) {
        throw PlatformException(code: 'unavailable');
      }
      return 'Asia/Kolkata';
    });
    messenger.setMockMethodCallHandler(notifChannel, (call) async {
      notifMethods.add(call.method);
      switch (call.method) {
        case 'initialize':
          return true;
        case 'getNotificationAppLaunchDetails':
          return <String, dynamic>{
            'notificationLaunchedApp': false,
            'notificationResponse': null,
          };
        case 'zonedSchedule':
          zonedArgs.add(call.arguments as Map<dynamic, dynamic>);
          return null;
        default:
          return null;
      }
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(tzChannel, null);
    messenger.setMockMethodCallHandler(notifChannel, null);
  });

  Future<void> schedule(PluginReminderGateway gateway) => gateway.scheduleDaily(
    id: 601,
    title: 'Plan',
    body: 'Plan the day',
    hour: 8,
    minute: 0,
    payload: 'today',
  );

  test('failed timezone lookup: nothing is scheduled', () async {
    final gateway = PluginReminderGateway(ReminderTapRouter());
    await schedule(gateway);
    expect(notifMethods, isNot(contains('zonedSchedule')));
    // Cancelling still works while the timezone is unknown —
    // turning a reminder OFF must never depend on the lookup.
    await gateway.cancel(601);
    expect(notifMethods, contains('cancel'));
  });

  test('lookup is retried next call; recovery restores scheduling', () async {
    final gateway = PluginReminderGateway(ReminderTapRouter());
    await schedule(gateway);
    expect(notifMethods, isNot(contains('zonedSchedule')));
    final callsBefore = tzCalls;
    tzFails = false;
    await schedule(gateway);
    expect(tzCalls, greaterThan(callsBefore)); // retried
    expect(notifMethods, contains('zonedSchedule'));
    // Scheduled in the device's real zone, not the UTC default.
    expect(zonedArgs.single['timeZoneName'], 'Asia/Kolkata');
  });
}
