import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../domain/entities.dart';

/// A deterministic Android notification derived from a supplement schedule.
///
/// [repeatsWeekly] notifications are only used when a schedule has no end
/// date. Date-bounded schedules are deliberately one-shot so they stop on the
/// selected end date without requiring a background worker.
class PlannedReminder {
  const PlannedReminder({
    required this.notificationId,
    required this.profileId,
    required this.scheduleId,
    required this.weekday,
    required this.scheduledAt,
    required this.repeatsWeekly,
    required this.title,
    required this.body,
  });

  final int notificationId;
  final String profileId;
  final String scheduleId;
  final int weekday;
  final DateTime scheduledAt;
  final bool repeatsWeekly;
  final String title;
  final String body;
}

class ReminderReconciliation {
  const ReminderReconciliation({
    required this.notificationIdsToCancel,
    required this.remindersToSchedule,
  });

  final Set<int> notificationIdsToCancel;
  final List<PlannedReminder> remindersToSchedule;
}

enum ReminderCoverageReason { complete, rollingHorizon, alarmBudget }

class ReminderPlan {
  const ReminderPlan({
    required this.reminders,
    required this.omittedOccurrenceCount,
    required this.coverageThrough,
    required this.coverageReason,
  });

  final List<PlannedReminder> reminders;
  final int omittedOccurrenceCount;
  final DateTime coverageThrough;
  final ReminderCoverageReason coverageReason;
}

class LowStockAlert {
  const LowStockAlert({
    required this.supplementId,
    required this.notificationId,
    required this.title,
    required this.body,
  });

  final String supplementId;
  final int notificationId;
  final String title;
  final String body;
}

class LowStockEvaluation {
  const LowStockEvaluation({
    required this.alertsToShow,
    required this.nextLatchedSupplementIds,
  });

  final List<LowStockAlert> alertsToShow;
  final Set<String> nextLatchedSupplementIds;
}

/// Pure planning logic so reminder eligibility can be tested without plugins.
class ReminderPlanner {
  const ReminderPlanner({
    this.boundedScheduleHorizon = const Duration(days: 90),
    this.maxOwnedDoseAlarms = 400,
  });

  /// Bounded schedules are renewed on the next app launch, not by a worker.
  final Duration boundedScheduleHorizon;

  /// Kept beneath common OEM limits for concurrently pending alarms.
  final int maxOwnedDoseAlarms;

  static const _weekdayNumbers = <String, int>{
    'monday': DateTime.monday,
    'tuesday': DateTime.tuesday,
    'wednesday': DateTime.wednesday,
    'thursday': DateTime.thursday,
    'friday': DateTime.friday,
    'saturday': DateTime.saturday,
    'sunday': DateTime.sunday,
  };

  ReminderPlan plan({
    required Iterable<Profile> profiles,
    required Iterable<Supplement> supplements,
    required Iterable<SupplementSchedule> schedules,
    required DateTime now,
  }) {
    final profilesById = {
      for (final profile in profiles.where((item) => !item.deleted))
        profile.id: profile,
    };
    final supplementsById = {
      for (final supplement in supplements.where(
        (item) => !item.deleted && item.active,
      ))
        supplement.id: supplement,
    };
    final recurring = <PlannedReminder>[];
    final bounded = <PlannedReminder>[];
    var omittedByHorizon = 0;
    final horizon = _dateOnly(now).add(boundedScheduleHorizon);
    for (final schedule in schedules) {
      final profile = profilesById[schedule.profileId];
      final supplement = supplementsById[schedule.supplementId];
      if (profile == null ||
          supplement == null ||
          schedule.deleted ||
          !schedule.active ||
          !schedule.reminderEnabled) {
        continue;
      }
      final candidates = _forSchedule(
        profile: profile,
        supplement: supplement,
        schedule: schedule,
        now: now,
        horizon: horizon,
      );
      recurring.addAll(candidates.recurring);
      bounded.addAll(candidates.bounded);
      omittedByHorizon += candidates.omittedByHorizon;
    }
    recurring.sort(_candidateOrder);
    bounded.sort(_candidateOrder);
    final selected = <PlannedReminder>[];
    final recurringCount = recurring.length.clamp(0, maxOwnedDoseAlarms);
    selected.addAll(recurring.take(recurringCount));
    final remaining = maxOwnedDoseAlarms - selected.length;
    selected.addAll(bounded.take(remaining.clamp(0, bounded.length)));
    final omittedByBudget =
        recurring.length -
        recurringCount +
        bounded.length -
        (selected.length - recurringCount);
    final collisionFree = _resolveNotificationIdCollisions(selected)
      ..sort(_candidateOrder);
    return ReminderPlan(
      reminders: List<PlannedReminder>.unmodifiable(collisionFree),
      omittedOccurrenceCount: omittedByHorizon + omittedByBudget,
      coverageThrough: horizon,
      coverageReason: omittedByBudget > 0
          ? ReminderCoverageReason.alarmBudget
          : omittedByHorizon > 0
          ? ReminderCoverageReason.rollingHorizon
          : ReminderCoverageReason.complete,
    );
  }

  ReminderReconciliation reconcile({
    required Iterable<int> managedNotificationIds,
    required Iterable<PlannedReminder> desired,
  }) {
    // Replacing all owned notifications makes changed copy, date ranges, and
    // timezone changes converge without needing plugin-specific inspection.
    return ReminderReconciliation(
      notificationIdsToCancel: Set<int>.from(managedNotificationIds),
      remindersToSchedule: List<PlannedReminder>.unmodifiable(desired),
    );
  }

  /// Identifies threshold crossings for the shared household inventory.
  ///
  /// A missing threshold has no unambiguous quantity to alert on, so it is not
  /// included here. The caller persists [nextLatchedSupplementIds], which
  /// suppresses repeats until stock recovers above the configured threshold.
  LowStockEvaluation evaluateLowStock({
    required Iterable<Supplement> supplements,
    required Map<String, double> stockLevels,
    required Set<String> latchedSupplementIds,
  }) {
    final eligible = supplements.where(
      (item) =>
          !item.deleted &&
          item.active &&
          item.lowStockAlerts &&
          item.lowStockThresholdUnits != null,
    );
    final low = <String>{};
    final alerts = <LowStockAlert>[];
    for (final supplement in eligible) {
      final threshold = supplement.lowStockThresholdUnits!;
      final stock = stockLevels[supplement.id] ?? 0;
      if (stock > threshold) continue;
      low.add(supplement.id);
      if (latchedSupplementIds.contains(supplement.id)) continue;
      alerts.add(
        LowStockAlert(
          supplementId: supplement.id,
          notificationId: notificationIdFor(
            profileId: 'low-stock',
            scheduleId: supplement.id,
            weekday: 0,
            occurrenceKey: 'threshold',
          ),
          title: 'Low supplement stock',
          body:
              '${supplement.name} has ${_formatDose(stock)} ${supplement.stockUnit} remaining (alert at ${_formatDose(threshold)}).',
        ),
      );
    }
    return LowStockEvaluation(
      alertsToShow: List<LowStockAlert>.unmodifiable(alerts),
      nextLatchedSupplementIds: Set<String>.unmodifiable(low),
    );
  }

  _ScheduleCandidates _forSchedule({
    required Profile profile,
    required Supplement supplement,
    required SupplementSchedule schedule,
    required DateTime now,
    required DateTime horizon,
  }) {
    final time = _parseTime(schedule.timeOfDay);
    if (time == null) return const _ScheduleCandidates();
    final today = _dateOnly(now);
    final start = schedule.startDate == null
        ? today
        : _dateOnly(schedule.startDate!);
    final end = schedule.endDate == null ? null : _dateOnly(schedule.endDate!);
    if (end != null && end.isBefore(today)) return const _ScheduleCandidates();
    final firstDay = start.isAfter(today) ? start : today;
    final weekdays =
        schedule.weekdays
            .map((item) => _weekdayNumbers[item.trim().toLowerCase()])
            .whereType<int>()
            .toSet()
            .toList()
          ..sort();
    final recurring = <PlannedReminder>[];
    final bounded = <PlannedReminder>[];
    var omittedByHorizon = 0;
    for (final weekday in weekdays) {
      final first = _nextOnWeekday(firstDay, weekday, time.$1, time.$2, now);
      if (end == null) {
        recurring.add(
          _reminder(
            profile: profile,
            supplement: supplement,
            schedule: schedule,
            weekday: weekday,
            scheduledAt: first,
            repeatsWeekly: true,
            occurrenceKey: 'weekly',
          ),
        );
        continue;
      }
      if (_dateOnly(first).isAfter(end)) continue;
      final totalOccurrences = _occurrenceCount(first, end);
      final boundedEnd = horizon.isBefore(end) ? horizon : end;
      final includedOccurrences = _dateOnly(first).isAfter(boundedEnd)
          ? 0
          : _occurrenceCount(first, boundedEnd);
      omittedByHorizon += totalOccurrences - includedOccurrences;
      for (
        var occurrence = first, index = 0;
        index < includedOccurrences;
        occurrence = occurrence.add(const Duration(days: 7)), index++
      ) {
        bounded.add(
          _reminder(
            profile: profile,
            supplement: supplement,
            schedule: schedule,
            weekday: weekday,
            scheduledAt: occurrence,
            repeatsWeekly: false,
            occurrenceKey: _dateKey(occurrence),
          ),
        );
      }
    }
    return _ScheduleCandidates(
      recurring: recurring,
      bounded: bounded,
      omittedByHorizon: omittedByHorizon,
    );
  }

  static int _candidateOrder(PlannedReminder a, PlannedReminder b) {
    final date = a.scheduledAt.compareTo(b.scheduledAt);
    if (date != 0) return date;
    final profile = a.profileId.compareTo(b.profileId);
    if (profile != 0) return profile;
    final schedule = a.scheduleId.compareTo(b.scheduleId);
    if (schedule != 0) return schedule;
    return a.weekday.compareTo(b.weekday);
  }

  static int _occurrenceCount(DateTime first, DateTime last) =>
      _dateOnly(last).difference(_dateOnly(first)).inDays ~/ 7 + 1;

  PlannedReminder _reminder({
    required Profile profile,
    required Supplement supplement,
    required SupplementSchedule schedule,
    required int weekday,
    required DateTime scheduledAt,
    required bool repeatsWeekly,
    required String occurrenceKey,
  }) {
    final id = notificationIdFor(
      profileId: profile.id,
      scheduleId: schedule.id,
      weekday: weekday,
      occurrenceKey: occurrenceKey,
    );
    return PlannedReminder(
      notificationId: id,
      profileId: profile.id,
      scheduleId: schedule.id,
      weekday: weekday,
      scheduledAt: scheduledAt,
      repeatsWeekly: repeatsWeekly,
      title: 'Supplement reminder',
      body:
          '${profile.displayName}: take ${_formatDose(schedule.dose)} ${schedule.unit} ${supplement.name}',
    );
  }

  List<PlannedReminder> _resolveNotificationIdCollisions(
    List<PlannedReminder> reminders,
  ) {
    final ordered = List<PlannedReminder>.from(reminders)
      ..sort((a, b) {
        final profile = a.profileId.compareTo(b.profileId);
        if (profile != 0) return profile;
        final schedule = a.scheduleId.compareTo(b.scheduleId);
        if (schedule != 0) return schedule;
        final weekday = a.weekday.compareTo(b.weekday);
        if (weekday != 0) return weekday;
        return a.scheduledAt.compareTo(b.scheduledAt);
      });
    final usedIds = <int>{};
    return [
      for (final reminder in ordered)
        _withAvailableNotificationId(reminder, usedIds),
    ];
  }

  PlannedReminder _withAvailableNotificationId(
    PlannedReminder reminder,
    Set<int> usedIds,
  ) {
    final occurrenceKey = reminder.repeatsWeekly
        ? 'weekly'
        : _dateKey(reminder.scheduledAt);
    var collision = 0;
    var id = reminder.notificationId;
    while (!usedIds.add(id)) {
      collision++;
      id = notificationIdFor(
        profileId: reminder.profileId,
        scheduleId: reminder.scheduleId,
        weekday: reminder.weekday,
        occurrenceKey: '$occurrenceKey#$collision',
      );
    }
    if (id == reminder.notificationId) return reminder;
    return PlannedReminder(
      notificationId: id,
      profileId: reminder.profileId,
      scheduleId: reminder.scheduleId,
      weekday: reminder.weekday,
      scheduledAt: reminder.scheduledAt,
      repeatsWeekly: reminder.repeatsWeekly,
      title: reminder.title,
      body: reminder.body,
    );
  }

  /// A positive 31-bit SHA-256-derived Android notification id. The input
  /// includes profile, schedule, weekday and bounded occurrence date.
  static int notificationIdFor({
    required String profileId,
    required String scheduleId,
    required int weekday,
    required String occurrenceKey,
  }) {
    final digest = sha256.convert(
      utf8.encode(
        '$profileId\u0000$scheduleId\u0000$weekday\u0000$occurrenceKey',
      ),
    );
    final bytes = digest.bytes;
    final value =
        (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return value & 0x7fffffff;
  }

  /// Built-in dialog slots use these local defaults: Morning 08:00, Midday
  /// 12:00, Evening 18:00, Bedtime 22:00. HH:mm is also accepted for callers
  /// that need a precise time; malformed values are safely ignored.
  static (int, int)? _parseTime(String value) {
    switch (value.trim().toLowerCase()) {
      case 'morning':
        return (8, 0);
      case 'midday':
        return (12, 0);
      case 'evening':
        return (18, 0);
      case 'bedtime':
        return (22, 0);
    }
    final match = RegExp(
      r'^(?:[01]?\d|2[0-3]):[0-5]\d$',
    ).firstMatch(value.trim());
    if (match == null) return null;
    final pieces = value.trim().split(':');
    return (int.parse(pieces[0]), int.parse(pieces[1]));
  }

  static DateTime _nextOnWeekday(
    DateTime firstDay,
    int weekday,
    int hour,
    int minute,
    DateTime now,
  ) {
    var day = _dateOnly(firstDay);
    day = day.add(Duration(days: (weekday - day.weekday + 7) % 7));
    var result = DateTime(day.year, day.month, day.day, hour, minute);
    if (!result.isAfter(now)) {
      result = result.add(const Duration(days: 7));
    }
    return result;
  }

  static DateTime _dateOnly(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static String _formatDose(double dose) =>
      dose == dose.roundToDouble() ? dose.toInt().toString() : dose.toString();
}

class _ScheduleCandidates {
  const _ScheduleCandidates({
    this.recurring = const [],
    this.bounded = const [],
    this.omittedByHorizon = 0,
  });

  final List<PlannedReminder> recurring;
  final List<PlannedReminder> bounded;
  final int omittedByHorizon;
}
