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

/// Android-only adapter around OS-scheduled local notifications.
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

  /// The `v2` suffix is load-bearing. Android freezes a channel's importance,
  /// sound and vibration the moment it is first created and ignores every later
  /// change, for the life of the install. The original channel was created at
  /// default importance, which on Android means no heads-up banner and, on
  /// several OEM skins, no sound — so raising the importance in code could not
  /// reach any device that had already run the app. A new id is the only way to
  /// deliver corrected settings without asking the owner to reinstall.
  static const _channelId = 'supplement_dose_reminders_v2';
  static const _legacyChannelId = 'supplement_dose_reminders';
  static const _channelName = 'Supplement dose reminders';
  static const _channelDescription = 'Reminders for scheduled supplement doses';
  static const _managedIdsPreference = 'supplement_reminder_notification_ids';
  static const _lowStockLatchPreference = 'low_stock_alert_latches';

  /// A dose reminder is a timed alert the owner asked for, so it is delivered
  /// at high importance: heads-up, with sound. A silent entry in the shade is
  /// indistinguishable from no reminder at all.
  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      category: AndroidNotificationCategory.reminder,
    ),
  );

  final FlutterLocalNotificationsPlugin _notifications;
  final ReminderPlanner _planner;
  bool _initialized = false;

  /// Whether Android is currently letting this app post exact alarms.
  ///
  /// Null until the first [initialize]. Surfaced so settings can explain a
  /// reminder that arrives late rather than leaving it a mystery.
  bool? exactAlarmsAllowed;

  bool get isSupported => !kIsWeb && Platform.isAndroid;

  AndroidFlutterLocalNotificationsPlugin? get _android => _notifications
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<ReminderPermissionStatus> initialize() async {
    if (!isSupported) return ReminderPermissionStatus.unsupported;
    if (!_initialized) {
      tz_data.initializeTimeZones();
      final localTimezone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTimezone.identifier));
      await _notifications.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
      );
      final android = _android;
      // Created up front rather than implicitly on the first notification, so
      // the channel exists with these settings even before anything is due.
      await android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
        ),
      );
      // The old channel would otherwise sit in Android's notification settings
      // forever, showing the owner a control that no longer routes anything.
      await android?.deleteNotificationChannel(channelId: _legacyChannelId);
      _initialized = true;
    }
    exactAlarmsAllowed = await _android?.canScheduleExactNotifications();
    return permissionStatus();
  }

  /// Asks Android for the exact-alarm right, which it grants through a settings
  /// screen rather than a dialog. Without it a reminder is only a hint: Doze
  /// batches inexact alarms and can hold one for hours past its time.
  Future<bool> requestExactAlarms() async {
    if (!isSupported) return false;
    await initialize();
    await _android?.requestExactAlarmsPermission();
    exactAlarmsAllowed = await _android?.canScheduleExactNotifications();
    return exactAlarmsAllowed ?? false;
  }

  /// Posts a notification immediately so delivery can be checked end to end.
  ///
  /// Scheduling is the part that silently fails — permissions, channels, OEM
  /// battery managers — and none of it is visible from inside the app. This
  /// separates "nothing was scheduled" from "nothing gets through".
  Future<bool> sendTestNotification() async {
    if (!isSupported) return false;
    await initialize();
    if (await permissionStatus() != ReminderPermissionStatus.granted) {
      return false;
    }
    await _notifications.show(
      id: _testNotificationId,
      title: 'SuperHealth reminders are working',
      body: 'This is a test notification. Dose reminders arrive the same way.',
      notificationDetails: _details,
    );
    return true;
  }

  /// The Android scheduling mode a reminder is registered under.
  ///
  /// Unknown means unknown, not allowed: scheduling an exact alarm the OS has
  /// not granted throws, and losing every reminder is worse than a late one.
  @visibleForTesting
  static AndroidScheduleMode scheduleModeFor({required bool? exactAllowed}) =>
      exactAllowed ?? false
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;

  /// Planner ids are SHA-256 derived across the whole 31-bit space, so this is
  /// low-collision rather than reserved. A collision would only replace one
  /// pending reminder, and the next reconcile reschedules every one of them.
  static const _testNotificationId = 1;

  Future<ReminderPermissionStatus> permissionStatus() async {
    if (!isSupported) return ReminderPermissionStatus.unsupported;
    if (!_initialized) await initialize();
    final enabled = await _android?.areNotificationsEnabled();
    return enabled == true
        ? ReminderPermissionStatus.granted
        : ReminderPermissionStatus.denied;
  }

  Future<ReminderPermissionStatus> requestPermission() async {
    if (!isSupported) return ReminderPermissionStatus.unsupported;
    await initialize();
    await _android?.requestNotificationsPermission();
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
      await _notifications.cancel(id: notificationId);
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
        id: alert.notificationId,
        title: alert.title,
        body: alert.body,
        notificationDetails: _details,
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
      id: reminder.notificationId,
      title: reminder.title,
      body: reminder.body,
      scheduledDate: scheduledAt,
      notificationDetails: _details,
      // A dose reminder names a time, so it has to arrive at that time. Inexact
      // alarms are batched by Doze and routinely land hours late, which reads
      // as a reminder that never came. Inexact remains the fallback for a
      // device that withholds the exact-alarm right, because a late reminder
      // still beats none.
      androidScheduleMode: scheduleModeFor(exactAllowed: exactAlarmsAllowed),
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
