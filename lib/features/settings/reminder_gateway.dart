/// SET — the plugin-backed [ReminderGateway] (S6).
/// flutter_local_notifications, scheduled INEXACTLY
/// (AndroidScheduleMode.inexactAllowWhileIdle — no exact-alarm
/// permission is ever requested, §R8.1), repeating daily by
/// wall-clock time so the owner's chosen time survives DST.
///
/// Everything here degrades quietly: a platform without the
/// plugin or a denied permission must never break app start —
/// reminders are garnish (§R9.7). One exception, learned the hard
/// way (audit finding 001): if the timezone LOOKUP fails, the
/// timezone package's local location stays at its default (UTC),
/// and scheduling against it would fire at the wrong wall-clock
/// time, silently. So a failed lookup does not degrade to UTC —
/// scheduling is skipped (the setting stays on) and the lookup is
/// retried on the next gateway call, e.g. the next app start's
/// applyAll. Host tests cover this gateway only through mocked
/// platform channels (see reminder_gateway_test.dart); the
/// controller is tested against a fake gateway.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'reminders.dart';

class PluginReminderGateway implements ReminderGateway {
  PluginReminderGateway(this._router);

  final ReminderTapRouter _router;
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _tzDataReady = false;
  bool _localTimezoneReady = false;

  static const _channelId = 'nimo_reminders';
  static const _channelName = 'Reminders';

  Future<void> _ensureInitialized() async {
    if (!_localTimezoneReady) {
      try {
        if (!_tzDataReady) {
          tzdata.initializeTimeZones();
          _tzDataReady = true;
        }
        final name = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(name.identifier));
        _localTimezoneReady = true;
      } catch (e) {
        if (kDebugMode) {
          debugPrint('ReminderGateway: timezone lookup failed: $e');
        }
      }
    }
    if (_initialized) return;
    _initialized = true; // set first: a failure must not retry-loop
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null) _router.dispatch(payload);
        },
      );
      // Cold start from a notification tap: the response callback
      // does not fire for the launch itself — read it here.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && payload != null) {
        _router.dispatch(payload);
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ReminderGateway: init failed: $e');
      }
    }
  }

  @override
  Future<bool> requestPermission() async {
    await _ensureInitialized();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android == null) return true; // not Android: nothing to ask
      return await android.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required String payload,
  }) async {
    await _ensureInitialized();
    if (!_localTimezoneReady) {
      // Audit finding 001: tz.local is the package default (UTC),
      // not the device's zone — a schedule now would fire shifted
      // by the UTC offset. Skip; the lookup retries next call.
      if (kDebugMode) {
        debugPrint(
          'ReminderGateway: schedule skipped — local timezone unknown',
        );
      }
      return;
    }
    try {
      final next = nextDailyFire(DateTime.now(), hour, minute);
      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(next, tz.local),
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription:
                'Gentle, opt-in nudges for the daily plan and Day Close.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
        // Inexact on purpose (§R8.1): may land a little after the
        // chosen time; never demands SCHEDULE_EXACT_ALARM.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: payload,
        matchDateTimeComponents: DateTimeComponents.time,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ReminderGateway: schedule failed: $e');
      }
    }
  }

  @override
  Future<void> cancel(int id) async {
    await _ensureInitialized();
    try {
      await _plugin.cancel(id: id);
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ReminderGateway: cancel failed: $e');
      }
    }
  }
}
