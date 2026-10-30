// SET — reminders (S6, §R5.6/§R8.1): defaults OFF, toggle-on is
// the only permission request, toggle-off cancels reliably,
// time changes reschedule, next-fire math is wall-clock, the
// ≥7-day-absence self-watch suggests turning reminders off,
// and the tap router buffers cold-start payloads.
import 'package:daily_life_app/core/db/app_database.dart';
import 'package:daily_life_app/features/settings/reminders.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeGateway implements ReminderGateway {
  bool permissionResult = true;
  int permissionRequests = 0;
  final List<({int id, int hour, int minute, String payload})> scheduled = [];
  final List<int> cancelled = [];

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return permissionResult;
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
    scheduled.add((id: id, hour: hour, minute: minute, payload: payload));
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
}

void main() {
  late Database db;
  late FakeGateway gateway;
  late ReminderController controller;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    db = await AppDatabase.openInMemory();
    await db.delete('app_settings');
    gateway = FakeGateway();
    controller = ReminderController(db, gateway);
  });

  group('defaults', () {
    test('both reminders OFF by default with 08:00 / 21:00 times', () async {
      final s = await controller.load();
      expect(s.morningEnabled, isFalse);
      expect(s.eveningEnabled, isFalse);
      expect(s.morningTime, const TimeOfDay(hour: 8, minute: 0));
      expect(s.eveningTime, const TimeOfDay(hour: 21, minute: 0));
    });

    test('applyAll with defaults schedules nothing, cancels both', () async {
      await controller.applyAll();
      expect(gateway.scheduled, isEmpty);
      expect(gateway.cancelled,
          [ReminderIds.morningPlan, ReminderIds.eveningClose]);
      expect(gateway.permissionRequests, 0); // never at apply time
    });
  });

  group('toggling', () {
    test('toggle ON requests permission once and schedules inexact daily', () async {
      final granted = await controller.setMorningEnabled(true);
      expect(granted, isTrue);
      expect(gateway.permissionRequests, 1);
      expect(gateway.scheduled.length, 1);
      final call = gateway.scheduled.single;
      expect(call.id, ReminderIds.morningPlan);
      expect(call.hour, 8);
      expect(call.minute, 0);
      expect(call.payload, ReminderPayloads.morningPlan);
      expect((await controller.load()).morningEnabled, isTrue);
    });

    test('toggle OFF cancels reliably and asks for no permission', () async {
      await controller.setEveningEnabled(true);
      gateway.scheduled.clear();
      gateway.cancelled.clear();
      final granted = await controller.setEveningEnabled(false);
      expect(granted, isTrue);
      expect(gateway.permissionRequests, 1); // only from the ON
      // applyAll cancels every disabled reminder — the evening
      // one included, reliably.
      expect(gateway.cancelled, contains(ReminderIds.eveningClose));
      expect(gateway.scheduled, isEmpty);
      expect((await controller.load()).eveningEnabled, isFalse);
    });

    test('permission denied: intent is saved, setter reports it', () async {
      gateway.permissionResult = false;
      final granted = await controller.setMorningEnabled(true);
      expect(granted, isFalse);
      expect((await controller.load()).morningEnabled, isTrue);
    });

    test('changing the time reschedules with the new time', () async {
      await controller.setEveningEnabled(true);
      gateway.scheduled.clear();
      await controller.setEveningTime(const TimeOfDay(hour: 20, minute: 30));
      final call = gateway.scheduled.single;
      expect(call.id, ReminderIds.eveningClose);
      expect(call.hour, 20);
      expect(call.minute, 30);
      expect((await controller.load()).eveningTime,
          const TimeOfDay(hour: 20, minute: 30));
    });

    test('applyAll (app start) re-schedules persisted ON reminders without a permission request', () async {
      await controller.setMorningEnabled(true);
      final freshGateway = FakeGateway();
      final fresh = ReminderController(db, freshGateway);
      await fresh.applyAll();
      expect(freshGateway.permissionRequests, 0);
      expect(freshGateway.scheduled.single.id, ReminderIds.morningPlan);
      expect(freshGateway.cancelled, [ReminderIds.eveningClose]);
    });
  });

  group('nextDailyFire (pure)', () {
    test('later today when the time is still ahead', () {
      expect(nextDailyFire(DateTime(2026, 11, 1, 7, 59), 8, 0),
          DateTime(2026, 11, 1, 8, 0));
    });

    test('exactly at the time means tomorrow (strictly after)', () {
      expect(nextDailyFire(DateTime(2026, 11, 1, 8, 0), 8, 0),
          DateTime(2026, 11, 2, 8, 0));
    });

    test('after the time means tomorrow, across a month boundary', () {
      expect(nextDailyFire(DateTime(2026, 10, 31, 23, 30), 6, 15),
          DateTime(2026, 11, 1, 6, 15));
    });
  });

  group('self-watch (§R5.6)', () {
    test('a ≥7-day gap with a reminder on raises the suggestion; turnAllOff clears it', () async {
      final day0 = DateTime(2026, 10, 20, 9);
      await controller.recordAppOpen(now: day0);
      await controller.setMorningEnabled(true);
      await controller.recordAppOpen(now: day0.add(const Duration(days: 8)));
      expect(await controller.shouldSuggestTurningOff(), isTrue);

      gateway.cancelled.clear();
      await controller.turnAllOff();
      expect(await controller.shouldSuggestTurningOff(), isFalse);
      final s = await controller.load();
      expect(s.anyEnabled, isFalse);
      expect(gateway.cancelled,
          containsAll([ReminderIds.morningPlan, ReminderIds.eveningClose]));
    });

    test('a 6-day gap does not raise the suggestion', () async {
      final day0 = DateTime(2026, 10, 20, 9);
      await controller.recordAppOpen(now: day0);
      await controller.setMorningEnabled(true);
      await controller.recordAppOpen(now: day0.add(const Duration(days: 6)));
      expect(await controller.shouldSuggestTurningOff(), isFalse);
    });

    test('a long gap with reminders OFF raises nothing', () async {
      final day0 = DateTime(2026, 10, 20, 9);
      await controller.recordAppOpen(now: day0);
      await controller.recordAppOpen(now: day0.add(const Duration(days: 30)));
      expect(await controller.shouldSuggestTurningOff(), isFalse);
    });
  });

  group('tap router', () {
    test('dispatch before register is buffered and delivered on register', () {
      final router = ReminderTapRouter();
      router.dispatch(ReminderPayloads.eveningClose);
      final seen = <String>[];
      router.register(seen.add);
      expect(seen, [ReminderPayloads.eveningClose]);
      router.dispatch(ReminderPayloads.morningPlan);
      expect(seen, [ReminderPayloads.eveningClose, ReminderPayloads.morningPlan]);
    });
  });
}
