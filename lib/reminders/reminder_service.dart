import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/entities.dart';
import 'reminder_planner.dart';

enum ReminderPermissionStatus { unknown, granted, denied, unsupported }

/// Android-only adapter around OS-scheduled, inexact local notifications.
///
/// It intentionally does not use a background worker. Open-ended schedules
/// repeat weekly; bounded schedules are scheduled as one-shot occurrences so
/// their end date is honored by Android even while the app is not running.
class ReminderService {
  ReminderService({
    FlutterLocalNotificationsPlugin? notifications,
    ReminderPlanner? planner,
  }) : _notifications = notifications ?? FlutterLocalNotificationsPlugin(),
       _planner = planner ?? ReminderPlanner();

  static const _channelId = 'supplement_dose_reminders';
  static const _managedIdsPreference = 'supplement_reminder_notification_ids';
  static const _lowStockLatchPreference = 'low_stock_alert_latches';

  final FlutterLocalNotificationsPlugin _notifications;
  final ReminderPlanner _planner;
  bool _initialized = false;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  Future<ReminderPermissionStatus> initialize() async {
    if (!isSupported) return ReminderPermissionStatus.unsupported;
    if (!_initialized) {
      tz_data.initializeTimeZones();
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.name));
      await _notifications.initialize(
        const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      _initialized = true;
    }
    return permissionStatus();
  }

  Future<ReminderPermissionStatus> permissionStatus() async {
    if (!isSupported) return ReminderPermissionStatus.unsupported;
    if (!_initialized) await initialize();
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final enabled = await android?.areNotificationsEnabled();
    return enabled == true
        ? ReminderPermissionStatus.granted
        : ReminderPermissionStatus.denied;
  }

  Future<ReminderPermissionStatus> requestPermission() async {
    if (!isSupported) return ReminderPermissionStatus.unsupported;
    await initialize();
    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await android?.requestNotificationsPermission();
    return permissionStatus();
  }

  Future<ReminderPlan> reconcile({
    required Iterable<Profile> profiles,
    required Iterable<Supplement> supplements,
    required Iterable<SupplementSchedule> schedules,
    DateTime? now,
  }) async {
    final planned = _planner.plan(
      profiles: profiles,
      supplements: supplements,
      schedules: schedules,
      now: now ?? DateTime.now(),
    );
    if (!isSupported) return planned;
    await initialize();
    final preferences = await SharedPreferences.getInstance();
    final managedIds = _readManagedIds(preferences);
    final reconciliation = _planner.reconcile(
      managedNotificationIds: managedIds,
      desired: planned.reminders,
    );
    for (final notificationId in reconciliation.notificationIdsToCancel) {
      await _notifications.cancel(notificationId);
    }
    for (final reminder in reconciliation.remindersToSchedule) {
      await _schedule(reminder);
    }
    await preferences.setStringList(
      _managedIdsPreference,
      planned.reminders.map((item) => item.notificationId.toString()).toList(),
    );
    return planned;
  }

  Future<int> reconcileLowStockAlerts({
    required Iterable<Supplement> supplements,
    required Map<String, double> stockLevels,
  }) async {
    if (!isSupported) return 0;
    await initialize();
    // Do not latch an alert the user could not receive. Once permission is
    // granted, the next reconciliation will still surface the current low
    // stock state.
    if (await permissionStatus() != ReminderPermissionStatus.granted) {
      return 0;
    }
    final preferences = await SharedPreferences.getInstance();
    final evaluation = _planner.evaluateLowStock(
      supplements: supplements,
      stockLevels: stockLevels,
      latchedSupplementIds: _readLowStockLatches(preferences),
    );
    for (final alert in evaluation.alertsToShow) {
      await _notifications.show(
        alert.notificationId,
        alert.title,
        alert.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            'Supplement dose reminders',
            channelDescription: 'Reminders for scheduled supplement doses',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
        ),
      );
    }
    await preferences.setString(
      _lowStockLatchPreference,
      jsonEncode(evaluation.nextLatchedSupplementIds.toList()..sort()),
    );
    return evaluation.alertsToShow.length;
  }

  Future<void> _schedule(PlannedReminder reminder) {
    final scheduledAt = tz.TZDateTime(
      tz.local,
      reminder.scheduledAt.year,
      reminder.scheduledAt.month,
      reminder.scheduledAt.day,
      reminder.scheduledAt.hour,
      reminder.scheduledAt.minute,
    );
    return _notifications.zonedSchedule(
      reminder.notificationId,
      reminder.title,
      reminder.body,
      scheduledAt,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Supplement dose reminders',
          channelDescription: 'Reminders for scheduled supplement doses',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: reminder.repeatsWeekly
          ? DateTimeComponents.dayOfWeekAndTime
          : null,
    );
  }

  Set<int> _readManagedIds(SharedPreferences preferences) {
    return preferences
            .getStringList(_managedIdsPreference)
            ?.map(int.tryParse)
            .whereType<int>()
            .toSet() ??
        <int>{};
  }

  Set<String> _readLowStockLatches(SharedPreferences preferences) {
    final raw = preferences.getString(_lowStockLatchPreference);
    if (raw == null) return <String>{};
    try {
      final decoded = jsonDecode(raw);
      return decoded is List ? decoded.whereType<String>().toSet() : <String>{};
    } on FormatException {
      return <String>{};
    }
  }
}
