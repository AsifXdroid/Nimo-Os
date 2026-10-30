/// SET — reminders (S6, §R5.6/§R8.1): TWO opt-in toggles, OFF
/// by default, inexact scheduling, invitational copy. Reminders
/// are garnish — the daily loop works without them, nothing in
/// the product depends on delivery (OEM killing is expected,
/// §R9.7), and no permission is requested until the owner turns
/// a toggle on.
///
/// This file holds the testable logic: settings persistence
/// (app_settings keys), the pure next-fire computation, and the
/// controller that drives a [ReminderGateway]. The plugin-backed
/// gateway lives in reminder_gateway.dart; tests drive a fake.
library;

import 'package:flutter/material.dart' show TimeOfDay;
import 'package:sqflite/sqflite.dart';

/// Stable notification ids for the two reminders.
abstract final class ReminderIds {
  static const int morningPlan = 601;
  static const int eveningClose = 602;
}

/// Notification payloads; a tap routes on these (today tab /
/// Day Close).
abstract final class ReminderPayloads {
  static const String morningPlan = 'today';
  static const String eveningClose = 'day_close';
}

abstract final class ReminderCopy {
  static const String morningTitle = 'Your plan is ready when you are';
  static const String morningBody =
      'Open Nimo to see today\'s plan — no rush.';
  static const String eveningTitle = 'Close your day — 2 minutes';
  static const String eveningBody =
      'One major point, one score. That\'s the whole review.';
}

/// The two reminder settings. Defaults are OFF (§R5.6 locked).
class ReminderSettings {
  const ReminderSettings({
    this.morningEnabled = false,
    this.morningTime = const TimeOfDay(hour: 8, minute: 0),
    this.eveningEnabled = false,
    this.eveningTime = const TimeOfDay(hour: 21, minute: 0),
  });

  final bool morningEnabled;
  final TimeOfDay morningTime;
  final bool eveningEnabled;
  final TimeOfDay eveningTime;

  bool get anyEnabled => morningEnabled || eveningEnabled;

  ReminderSettings copyWith({
    bool? morningEnabled,
    TimeOfDay? morningTime,
    bool? eveningEnabled,
    TimeOfDay? eveningTime,
  }) =>
      ReminderSettings(
        morningEnabled: morningEnabled ?? this.morningEnabled,
        morningTime: morningTime ?? this.morningTime,
        eveningEnabled: eveningEnabled ?? this.eveningEnabled,
        eveningTime: eveningTime ?? this.eveningTime,
      );
}

/// The next local fire time for a daily reminder at [hour]:[minute]
/// strictly after [now]. Pure — calendar arithmetic in local
/// time, so DST days resolve to the wall-clock time the owner
/// picked, never a shifted instant.
DateTime nextDailyFire(DateTime now, int hour, int minute) {
  var t = DateTime(now.year, now.month, now.day, hour, minute);
  if (!t.isAfter(now)) {
    t = DateTime(now.year, now.month, now.day + 1, hour, minute);
  }
  return t;
}

/// The platform boundary for notifications. The plugin
/// implementation schedules INEXACT daily alarms
/// (AndroidScheduleMode.inexactAllowWhileIdle) — exact alarms
/// need a special Android 14+ permission a gentle nudge must
/// not demand (§R8.1).
abstract interface class ReminderGateway {
  /// Ask for the notifications permission (Android 13+ runtime
  /// permission). Returns true when granted or not required.
  /// Called ONLY from an owner toggle-on action — never at app
  /// start, never before a toggle exists.
  Future<bool> requestPermission();

  /// Schedule (or replace) a daily inexact reminder.
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required String payload,
  });

  /// Cancel a scheduled reminder; cancelling an absent one is a
  /// no-op.
  Future<void> cancel(int id);
}

/// A gateway that does nothing — widget tests and platforms
/// without a wired plugin. Scheduling silently no-ops; the
/// settings still persist.
class NoopReminderGateway implements ReminderGateway {
  const NoopReminderGateway();

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> scheduleDaily({
    required int id,
    required String title,
    required String body,
    required int hour,
    required int minute,
    required String payload,
  }) async {}

  @override
  Future<void> cancel(int id) async {}
}

/// Persistence + scheduling coordination for the two reminders.
class ReminderController {
  ReminderController(this._db, this._gateway);

  final Database _db;
  final ReminderGateway _gateway;

  static const _kMorningEnabled = 'reminder_morning_enabled';
  static const _kMorningTime = 'reminder_morning_time';
  static const _kEveningEnabled = 'reminder_evening_enabled';
  static const _kEveningTime = 'reminder_evening_time';
  static const _kLastOpen = 'reminders_last_open_ms';
  static const _kSuggestOff = 'reminder_suggest_off';

  Future<String?> _get(String key) async {
    final rows = await _db.query('app_settings',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.single['value'] as String;
  }

  Future<void> _set(String key, String value) => _db.insert(
        'app_settings',
        {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  static String _fmtTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay _parseTime(String? v, TimeOfDay fallback) {
    if (v == null) return fallback;
    final parts = v.split(':');
    if (parts.length != 2) return fallback;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null || h < 0 || h > 23 || m < 0 || m > 59) {
      return fallback;
    }
    return TimeOfDay(hour: h, minute: m);
  }

  Future<ReminderSettings> load() async {
    const defaults = ReminderSettings();
    return ReminderSettings(
      morningEnabled: (await _get(_kMorningEnabled)) == '1',
      morningTime: _parseTime(await _get(_kMorningTime), defaults.morningTime),
      eveningEnabled: (await _get(_kEveningEnabled)) == '1',
      eveningTime: _parseTime(await _get(_kEveningTime), defaults.eveningTime),
    );
  }

  Future<void> _save(ReminderSettings s) async {
    await _set(_kMorningEnabled, s.morningEnabled ? '1' : '0');
    await _set(_kMorningTime, _fmtTime(s.morningTime));
    await _set(_kEveningEnabled, s.eveningEnabled ? '1' : '0');
    await _set(_kEveningTime, _fmtTime(s.eveningTime));
  }

  /// (Re)applies the persisted settings to the gateway: enabled
  /// reminders are scheduled, disabled ones are cancelled.
  /// Never requests permission — scheduling with a not-yet-granted
  /// permission simply doesn't fire until the owner grants it;
  /// the request itself happens only in the toggle-on setters.
  Future<void> applyAll() async {
    final s = await load();
    if (s.morningEnabled) {
      await _gateway.scheduleDaily(
        id: ReminderIds.morningPlan,
        title: ReminderCopy.morningTitle,
        body: ReminderCopy.morningBody,
        hour: s.morningTime.hour,
        minute: s.morningTime.minute,
        payload: ReminderPayloads.morningPlan,
      );
    } else {
      await _gateway.cancel(ReminderIds.morningPlan);
    }
    if (s.eveningEnabled) {
      await _gateway.scheduleDaily(
        id: ReminderIds.eveningClose,
        title: ReminderCopy.eveningTitle,
        body: ReminderCopy.eveningBody,
        hour: s.eveningTime.hour,
        minute: s.eveningTime.minute,
        payload: ReminderPayloads.eveningClose,
      );
    } else {
      await _gateway.cancel(ReminderIds.eveningClose);
    }
  }

  /// Toggle the morning reminder. Turning ON requests the
  /// permission first and reports whether it was granted (the
  /// setting is saved either way — the owner's intent stands;
  /// scheduling takes effect once permission exists). Turning
  /// OFF cancels reliably.
  Future<bool> setMorningEnabled(bool enabled) async {
    var granted = true;
    if (enabled) granted = await _gateway.requestPermission();
    final s = (await load()).copyWith(morningEnabled: enabled);
    await _save(s);
    await applyAll();
    return granted;
  }

  Future<bool> setEveningEnabled(bool enabled) async {
    var granted = true;
    if (enabled) granted = await _gateway.requestPermission();
    final s = (await load()).copyWith(eveningEnabled: enabled);
    await _save(s);
    await applyAll();
    return granted;
  }

  Future<void> setMorningTime(TimeOfDay time) async {
    await _save((await load()).copyWith(morningTime: time));
    await applyAll(); // reschedules when enabled; no-op cancel otherwise
  }

  Future<void> setEveningTime(TimeOfDay time) async {
    await _save((await load()).copyWith(eveningTime: time));
    await applyAll();
  }

  /// Records an app open for the §R5.6 self-watch: if the
  /// previous open was ≥7 days ago and any reminder is on, the
  /// next Settings visit gently suggests turning them off —
  /// reminders that don't work become annoyance debt (§R9.7).
  Future<void> recordAppOpen({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final prev = await _get(_kLastOpen);
    if (prev != null) {
      final prevMs = int.tryParse(prev);
      if (prevMs != null &&
          at.millisecondsSinceEpoch - prevMs >=
              const Duration(days: 7).inMilliseconds &&
          (await load()).anyEnabled) {
        await _set(_kSuggestOff, '1');
      }
    }
    await _set(_kLastOpen, '${at.millisecondsSinceEpoch}');
  }

  Future<bool> shouldSuggestTurningOff() async =>
      (await _get(_kSuggestOff)) == '1';

  Future<void> dismissSuggestion() async {
    await _db.delete('app_settings',
        where: 'key = ?', whereArgs: [_kSuggestOff]);
  }

  /// Turns both reminders off and clears the suggestion.
  Future<void> turnAllOff() async {
    final s = (await load())
        .copyWith(morningEnabled: false, eveningEnabled: false);
    await _save(s);
    await dismissSuggestion();
    await applyAll();
  }
}

/// Routes notification taps into the app. The plugin gateway
/// dispatches payloads here; the app shell registers the handler
/// (select Today / open Day Close). Unregistered = taps just
/// open the app, which is the safe default.
class ReminderTapRouter {
  void Function(String payload)? _handler;
  String? _pending;

  void register(void Function(String payload) handler) {
    _handler = handler;
    final pending = _pending;
    if (pending != null) {
      _pending = null;
      handler(pending);
    }
  }

  void dispatch(String payload) {
    final handler = _handler;
    if (handler == null) {
      // Cold start: the tap launched the app before the shell
      // existed. Buffer the latest payload; register() delivers.
      _pending = payload;
      return;
    }
    handler(payload);
  }
}
