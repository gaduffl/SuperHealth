import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/analysis/supplement_insights.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/reminders/reminder_planner.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  const insights = SupplementInsights();
  final created = DateTime(2026, 1, 1);
  // A Monday, so the Monday-only schedules below are due.
  final monday = DateTime(2026, 3, 2, 7);

  Supplement product({
    bool active = true,
    List<String> pausedProfileIds = const [],
  }) => Supplement(
    id: 'zinc',
    name: 'Zinc',
    stockUnit: 'capsule',
    unitsPerContainer: 30,
    priceEur: 9,
    active: active,
    pausedProfileIds: pausedProfileIds,
    createdAt: created,
    updatedAt: created,
  );

  SupplementSchedule schedule(String profileId) => SupplementSchedule(
    id: 'schedule-$profileId',
    profileId: profileId,
    supplementId: 'zinc',
    dose: 1,
    unit: 'capsule',
    timeOfDay: 'Morning',
    weekdays: const [
      'monday',
      'tuesday',
      'wednesday',
      'thursday',
      'friday',
      'saturday',
      'sunday',
    ],
    reminderEnabled: true,
    createdAt: created,
    updatedAt: created,
  );

  final alpha = schedule('alpha');
  final beta = schedule('beta');

  test('a profile pause removes the dose only from that profile’s day', () {
    final paused = product(pausedProfileIds: ['alpha']);
    List<ScheduledDoseStatus> due(SupplementSchedule item) =>
        insights.dosesForDay(
          day: monday,
          schedules: [item],
          supplements: [paused],
          intakes: const [],
          now: monday,
        );

    expect(due(alpha), isEmpty);
    expect(due(beta), hasLength(1));

    final everyone = product(active: false);
    expect(
      insights.dosesForDay(
        day: monday,
        schedules: [beta],
        supplements: [everyone],
        intakes: const [],
        now: monday,
      ),
      isEmpty,
    );
  });

  test('the planned week leaves out the paused profile’s doses', () {
    final planned = insights.plannedWeeklyIngredients(
      supplements: [
        Supplement(
          id: 'zinc',
          name: 'Zinc',
          ingredients: const [
            {'name': 'Zinc', 'amount': 10, 'unit': 'mg'},
          ],
          pausedProfileIds: const ['alpha'],
          createdAt: created,
          updatedAt: created,
        ),
      ],
      schedules: [alpha, beta],
    );
    expect(planned.single.total, 70);
  });

  test(
    'stock, cost and the shopping list count only profiles still taking it',
    () {
      final paused = product(pausedProfileIds: ['alpha']);
      final projection = insights
          .stockProjections(
            supplements: [paused],
            householdSchedules: [alpha, beta],
            stockLevels: const {'zinc': 14},
            now: monday,
          )
          .single;
      expect(projection.weeklyScheduledUnits, 7);
      expect(projection.daysRemaining, 14);

      final plan = insights.purchasePlan(
        supplements: [paused],
        householdSchedules: [alpha, beta],
        stockLevels: const {'zinc': 0},
        months: 1,
        now: monday,
      );
      expect(plan.single.requiredUnits, closeTo(7 * 52 / 12, 1e-9));

      final cost = insights.monthlyCostEstimate(
        supplements: [paused],
        householdSchedules: [alpha, beta],
        now: monday,
      );
      expect(cost, closeTo(7 * 52 / 12 * 9 / 30, 1e-9));

      // Paused for every profile on its own is the same as paused for all.
      final nobody = product(pausedProfileIds: ['alpha', 'beta']);
      expect(
        insights
            .stockProjections(
              supplements: [nobody],
              householdSchedules: [alpha, beta],
              stockLevels: const {'zinc': 14},
              now: monday,
            )
            .single
            .daysRemaining,
        isNull,
      );
      expect(
        insights.purchasePlan(
          supplements: [nobody],
          householdSchedules: [alpha, beta],
          stockLevels: const {},
          months: 1,
          now: monday,
        ),
        isEmpty,
      );
    },
  );

  test('a paused profile gets no reminder while the other keeps theirs', () {
    Profile profile(String id) => Profile(
      id: id,
      displayName: id,
      createdAt: created,
      updatedAt: created,
    );
    final plan = ReminderPlanner().plan(
      profiles: [profile('alpha'), profile('beta')],
      supplements: [
        product(pausedProfileIds: ['alpha']),
      ],
      schedules: [alpha, beta],
      now: monday,
    );
    expect(plan.reminders, isNotEmpty);
    expect(plan.reminders.every((item) => item.profileId == 'beta'), isTrue);
  });

  test('the pause list round-trips sorted and without duplicates', () {
    final stored = Supplement.fromMap(
      product(pausedProfileIds: ['beta', 'alpha', 'beta']).toMap(),
    );
    expect(stored.pausedProfileIds, ['alpha', 'beta']);
    expect(Supplement.fromMap(product().toMap()).pausedProfileIds, isEmpty);
  });

  test(
    'an AI context sees its own pause as paused and never other profiles',
    () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final repository = HealthRepository(database);
      final first = await repository.createProfile(displayName: 'First');
      final second = await repository.createProfile(displayName: 'Second');
      await repository.saveSupplement(product(pausedProfileIds: [first.id]));
      for (final id in [first.id, second.id]) {
        await repository.saveSchedule(
          SupplementSchedule(
            id: 'schedule-$id',
            profileId: id,
            supplementId: 'zinc',
            dose: 1,
            unit: 'capsule',
            timeOfDay: 'Morning',
            weekdays: const ['monday'],
            createdAt: created,
            updatedAt: created,
          ),
        );
      }

      Future<Map<String, Object?>> row(String profileId) async {
        final snapshot = await repository.completeProfileSnapshot(profileId);
        final data = snapshot['data']! as Map;
        return Map<String, Object?>.from((data['supplements'] as List).single);
      }

      final firstRow = await row(first.id);
      expect(firstRow['active'], 0);
      expect(firstRow['paused_profile_ids_json'], '[]');
      final secondRow = await row(second.id);
      expect(secondRow['active'], 1);
      expect(secondRow['paused_profile_ids_json'], '[]');
    },
  );

  test('v17 databases gain an empty pause list on every product', () async {
    final directory = await Directory.systemTemp.createTemp('pause-v17-');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}/ledger.db';
    final old = AppDatabase(factory: databaseFactoryFfi, databasePath: path);
    await HealthRepository(old).saveSupplement(product());
    final db = await old.database;
    await db.execute(
      'ALTER TABLE supplements DROP COLUMN paused_profile_ids_json',
    );
    await db.execute('PRAGMA user_version = 17');
    await old.close();

    final upgraded = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: path,
    );
    addTearDown(upgraded.close);
    final stored = (await HealthRepository(upgraded).supplements()).single;
    expect(stored.active, isTrue);
    expect(stored.pausedProfileIds, isEmpty);
  });
}
