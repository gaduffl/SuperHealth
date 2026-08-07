import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/reminders/reminder_planner.dart';

void main() {
  final planner = ReminderPlanner();
  final createdAt = DateTime(2026, 1, 1);
  final magnesium = Supplement(
    id: 'magnesium',
    name: 'Magnesium glycinate',
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  Profile profile(String id, String name, {bool deleted = false}) => Profile(
    id: id,
    displayName: name,
    createdAt: createdAt,
    updatedAt: createdAt,
    deleted: deleted,
  );

  SupplementSchedule schedule({
    required String id,
    required String profileId,
    List<String> weekdays = const ['monday'],
    String timeOfDay = 'Morning',
    DateTime? startDate,
    DateTime? endDate,
    bool active = true,
    bool reminderEnabled = true,
    bool deleted = false,
  }) => SupplementSchedule(
    id: id,
    profileId: profileId,
    supplementId: magnesium.id,
    dose: 2,
    unit: 'capsules',
    timeOfDay: timeOfDay,
    weekdays: weekdays,
    startDate: startDate,
    endDate: endDate,
    active: active,
    reminderEnabled: reminderEnabled,
    createdAt: createdAt,
    updatedAt: createdAt,
    deleted: deleted,
  );

  test('plans named local time slots on selected weekdays', () {
    final plan = planner.plan(
      profiles: [profile('p1', 'Alex')],
      supplements: [magnesium],
      schedules: [
        schedule(id: 's1', profileId: 'p1', weekdays: ['monday', 'wednesday']),
      ],
      now: DateTime(2026, 3, 2, 7), // Monday
    );
    final reminders = plan.reminders;

    expect(reminders, hasLength(2));
    expect(reminders.map((item) => item.scheduledAt), [
      DateTime(2026, 3, 2, 8),
      DateTime(2026, 3, 4, 8),
    ]);
    expect(reminders.every((item) => item.repeatsWeekly), isTrue);
    expect(reminders.first.body, 'Alex: take 2 capsules Magnesium glycinate');
  });

  test('date-bounded schedules only produce in-range one-shot occurrences', () {
    final plan = planner.plan(
      profiles: [profile('p1', 'Alex')],
      supplements: [magnesium],
      schedules: [
        schedule(
          id: 's1',
          profileId: 'p1',
          weekdays: ['tuesday'],
          timeOfDay: '18:30',
          startDate: DateTime(2026, 3, 3),
          endDate: DateTime(2026, 3, 10),
        ),
      ],
      now: DateTime(2026, 3, 2, 9),
    );
    final reminders = plan.reminders;

    expect(reminders.map((item) => item.scheduledAt), [
      DateTime(2026, 3, 3, 18, 30),
      DateTime(2026, 3, 10, 18, 30),
    ]);
    expect(reminders.every((item) => !item.repeatsWeekly), isTrue);
  });

  test('stable IDs are profile-specific and positive', () {
    final first = ReminderPlanner.notificationIdFor(
      profileId: 'p1',
      scheduleId: 'schedule',
      weekday: DateTime.monday,
      occurrenceKey: 'weekly',
    );
    final same = ReminderPlanner.notificationIdFor(
      profileId: 'p1',
      scheduleId: 'schedule',
      weekday: DateTime.monday,
      occurrenceKey: 'weekly',
    );
    final otherProfile = ReminderPlanner.notificationIdFor(
      profileId: 'p2',
      scheduleId: 'schedule',
      weekday: DateTime.monday,
      occurrenceKey: 'weekly',
    );

    expect(same, first);
    expect(first, greaterThanOrEqualTo(0));
    expect(otherProfile, isNot(first));
  });

  test('plans multiple profiles and skips deleted or inactive inputs', () {
    final plan = planner.plan(
      profiles: [profile('p1', 'Alex'), profile('p2', 'Blair')],
      supplements: [magnesium],
      schedules: [
        schedule(id: 's1', profileId: 'p1'),
        schedule(id: 's2', profileId: 'p2'),
        schedule(id: 's3', profileId: 'p1', active: false),
        schedule(id: 's4', profileId: 'p1', reminderEnabled: false),
        schedule(id: 's5', profileId: 'missing'),
        schedule(id: 's6', profileId: 'p1', deleted: true),
      ],
      now: DateTime(2026, 3, 2, 7),
    );
    final reminders = plan.reminders;

    expect(reminders, hasLength(2));
    expect(reminders.map((item) => item.profileId).toSet(), {'p1', 'p2'});
  });

  test('skips invalid times and archived supplements', () {
    final archived = Supplement(
      id: magnesium.id,
      name: magnesium.name,
      active: false,
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    final invalidTime = planner.plan(
      profiles: [profile('p1', 'Alex')],
      supplements: [magnesium],
      schedules: [schedule(id: 's1', profileId: 'p1', timeOfDay: 'whenever')],
      now: DateTime(2026, 3, 2, 7),
    );
    final archivedSupplement = planner.plan(
      profiles: [profile('p1', 'Alex')],
      supplements: [archived],
      schedules: [schedule(id: 's1', profileId: 'p1')],
      now: DateTime(2026, 3, 2, 7),
    );

    expect(invalidTime.reminders, isEmpty);
    expect(archivedSupplement.reminders, isEmpty);
  });

  test('reconciliation cancels every previously managed reminder', () {
    final desired = planner.plan(
      profiles: [profile('p1', 'Alex')],
      supplements: [magnesium],
      schedules: [schedule(id: 's1', profileId: 'p1')],
      now: DateTime(2026, 3, 2, 7),
    );
    final reconciliation = planner.reconcile(
      managedNotificationIds: {12, 34},
      desired: desired.reminders,
    );

    expect(reconciliation.notificationIdsToCancel, {12, 34});
    expect(reconciliation.remindersToSchedule, desired.reminders);
  });

  test('multi-year bounded schedules report a rolling 90-day window', () {
    final plan = planner.plan(
      profiles: [profile('p1', 'Alex')],
      supplements: [magnesium],
      schedules: [
        schedule(
          id: 'long',
          profileId: 'p1',
          weekdays: ['monday'],
          startDate: DateTime(2026, 3, 2),
          endDate: DateTime(2030, 3, 2),
        ),
      ],
      now: DateTime(2026, 3, 2, 7),
    );

    expect(plan.reminders, hasLength(13));
    expect(plan.omittedOccurrenceCount, greaterThan(0));
    expect(plan.coverageThrough, DateTime(2026, 5, 31));
    expect(plan.coverageReason, ReminderCoverageReason.rollingHorizon);
  });

  test(
    'budget keeps recurring schedules then earliest bounded occurrences',
    () {
      final bounded = List.generate(
        6,
        (index) => schedule(
          id: 'bounded-${index.toString().padLeft(2, '0')}',
          profileId: 'p1',
          weekdays: const [
            'monday',
            'tuesday',
            'wednesday',
            'thursday',
            'friday',
            'saturday',
            'sunday',
          ],
          startDate: DateTime(2026, 3, 2),
          endDate: DateTime(2026, 5, 31),
        ),
      );
      final recurring = schedule(
        id: 'recurring',
        profileId: 'p1',
        weekdays: ['monday'],
      );
      final plan = planner.plan(
        profiles: [profile('p1', 'Alex')],
        supplements: [magnesium],
        schedules: [recurring, ...bounded],
        now: DateTime(2026, 3, 2, 7),
      );
      final reversedPlan = planner.plan(
        profiles: [profile('p1', 'Alex')],
        supplements: [magnesium],
        schedules: [...bounded.reversed, recurring],
        now: DateTime(2026, 3, 2, 7),
      );

      expect(plan.reminders, hasLength(400));
      expect(
        plan.reminders.any((item) => item.scheduleId == 'recurring'),
        isTrue,
      );
      expect(plan.omittedOccurrenceCount, greaterThan(0));
      expect(plan.coverageReason, ReminderCoverageReason.alarmBudget);
      expect(
        reversedPlan.reminders.map((item) => item.notificationId),
        plan.reminders.map((item) => item.notificationId),
      );
    },
  );

  test('low-stock latch notifies only when stock crosses and re-arms', () {
    final first = planner.evaluateLowStock(
      supplements: [
        Supplement(
          id: magnesium.id,
          name: magnesium.name,
          lowStockThresholdUnits: 10,
          stockUnit: 'capsules',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      stockLevels: {magnesium.id: 8},
      latchedSupplementIds: const {},
    );
    final repeated = planner.evaluateLowStock(
      supplements: [
        Supplement(
          id: magnesium.id,
          name: magnesium.name,
          lowStockThresholdUnits: 10,
          stockUnit: 'capsules',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      stockLevels: {magnesium.id: 8},
      latchedSupplementIds: first.nextLatchedSupplementIds,
    );
    final recovered = planner.evaluateLowStock(
      supplements: [
        Supplement(
          id: magnesium.id,
          name: magnesium.name,
          lowStockThresholdUnits: 10,
          stockUnit: 'capsules',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
      ],
      stockLevels: {magnesium.id: 11},
      latchedSupplementIds: first.nextLatchedSupplementIds,
    );

    expect(first.alertsToShow, hasLength(1));
    expect(first.alertsToShow.single.body, contains('8 capsules remaining'));
    expect(repeated.alertsToShow, isEmpty);
    expect(recovered.nextLatchedSupplementIds, isEmpty);
  });

  group('reminder-time readability', () {
    test('the named slots and HH:mm are schedulable', () {
      for (final value in [
        'Morning',
        'midday',
        'Evening',
        'BEDTIME',
        '07:30',
        '7:05',
        '23:59',
        ' 08:00 ',
      ]) {
        expect(
          ReminderPlanner.canScheduleReminder(value),
          isTrue,
          reason: value,
        );
      }
    });

    test('anything else is not, and the UI must be able to say so', () {
      // plan() silently skips these, so a reminder switched on against one
      // produces nothing. The screen asks this same question rather than
      // keeping its own copy of the rules.
      for (final value in [
        '',
        'Abends',
        '8am',
        '24:00',
        '12:60',
        'after gym',
      ]) {
        expect(
          ReminderPlanner.canScheduleReminder(value),
          isFalse,
          reason: value,
        );
      }
    });

    test('a schedule with an unreadable time yields no reminder', () {
      // The claim above only matters if plan() really drops it.
      final plan = planner.plan(
        profiles: [profile('p', 'P')],
        supplements: [magnesium],
        schedules: [schedule(id: 's', profileId: 'p', timeOfDay: 'after gym')],
        now: DateTime(2026, 8, 7, 9),
      );
      expect(plan.reminders, isEmpty);
      expect(
        planner
            .plan(
              profiles: [profile('p', 'P')],
              supplements: [magnesium],
              schedules: [
                schedule(id: 's', profileId: 'p', timeOfDay: '07:30'),
              ],
              now: DateTime(2026, 8, 7, 9),
            )
            .reminders,
        isNotEmpty,
      );
    });
  });
}
