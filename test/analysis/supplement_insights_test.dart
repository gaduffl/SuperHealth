import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/analysis/supplement_insights.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  test('normalizes duplicate legacy weekday labels to one seven-day week', () {
    expect(
      normalizeWeekdays(const [
        'Monday',
        'monday',
        'Tuesday',
        'tuesday',
        'Wednesday',
        'wednesday',
        'Thursday',
        'thursday',
        'Friday',
        'friday',
        'Saturday',
        'saturday',
        'Sunday',
        'sunday',
      ]),
      const [
        'monday',
        'tuesday',
        'wednesday',
        'thursday',
        'friday',
        'saturday',
        'sunday',
      ],
    );
  });

  final service = SupplementInsights();
  final monday = DateTime(2026, 7, 13);
  final supplement = Supplement(
    id: 'magnesium',
    name: 'Magnesium',
    stockUnit: 'capsule',
    unitsPerContainer: 60,
    priceEur: 12,
    lowStockThresholdUnits: 20,
    createdAt: monday,
    updatedAt: monday,
  );
  final schedule = SupplementSchedule(
    id: 'schedule',
    profileId: 'profile',
    supplementId: supplement.id,
    dose: 2,
    unit: 'capsules',
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
    createdAt: monday,
    updatedAt: monday,
  );

  test('matches a legacy intake to a scheduled time bucket', () {
    final intake = SupplementIntake(
      id: 'intake',
      profileId: 'profile',
      supplementId: supplement.id,
      takenAt: DateTime(2026, 7, 13, 8),
      dose: 2,
      unit: 'capsules',
      createdAt: monday,
      updatedAt: monday,
    );
    final result = service.dosesForDay(
      day: monday,
      schedules: [schedule],
      supplements: [supplement],
      intakes: [intake],
    );
    expect(result.single.taken, isTrue);
  });

  SupplementSchedule exactSchedule(String id, String time) =>
      SupplementSchedule(
        id: id,
        profileId: 'profile',
        supplementId: supplement.id,
        dose: 1,
        unit: 'capsule',
        timeOfDay: time,
        weekdays: const ['monday'],
        createdAt: monday,
        updatedAt: monday,
      );

  SupplementIntake legacyIntake(String id, DateTime takenAt) =>
      SupplementIntake(
        id: id,
        profileId: 'profile',
        supplementId: supplement.id,
        takenAt: takenAt,
        dose: 1,
        unit: 'capsule',
        createdAt: monday,
        updatedAt: monday,
      );

  test('exact schedule selects the nearest legacy intake in its window', () {
    final result = service.dosesForDay(
      day: monday,
      schedules: [exactSchedule('exact', '08:00')],
      supplements: [supplement],
      intakes: [
        legacyIntake('farther', DateTime(2026, 7, 13, 7, 30)),
        legacyIntake('nearest', DateTime(2026, 7, 13, 8, 20)),
      ],
    );
    expect(result.single.intake?.id, 'nearest');
  });

  test(
    'exact schedule does not match an intake outside its 90-minute window',
    () {
      final result = service.dosesForDay(
        day: monday,
        schedules: [exactSchedule('exact', '08:00')],
        supplements: [supplement],
        intakes: [legacyIntake('late', DateTime(2026, 7, 13, 9, 31))],
      );
      expect(result.single.intake, isNull);
    },
  );

  test('exact schedules match legacy intakes one-to-one deterministically', () {
    final schedules = [
      exactSchedule('late', '08:30'),
      exactSchedule('early', '08:00'),
    ];
    final intakes = [
      legacyIntake('second', DateTime(2026, 7, 13, 8, 20)),
      legacyIntake('first', DateTime(2026, 7, 13, 8, 10)),
    ];
    final first = service.dosesForDay(
      day: monday,
      schedules: schedules,
      supplements: [supplement],
      intakes: intakes,
    );
    final second = service.dosesForDay(
      day: monday,
      schedules: schedules.reversed.toList(),
      supplements: [supplement],
      intakes: intakes.reversed.toList(),
    );
    expect(first.map((item) => item.intake?.id), ['first', 'second']);
    expect(second.map((item) => item.intake?.id), ['first', 'second']);
    expect(first.map((item) => item.intake?.id).toSet().length, 2);
  });

  test('named slots retain legacy period matching', () {
    final result = service.dosesForDay(
      day: monday,
      schedules: [schedule],
      supplements: [supplement],
      intakes: [legacyIntake('morning', DateTime(2026, 7, 13, 10, 45))],
    );
    expect(result.single.intake?.id, 'morning');
  });

  test(
    'exact matching remains local-calendar safe on a DST transition day',
    () {
      final dstSunday = DateTime(2026, 3, 29);
      final result = service.dosesForDay(
        day: dstSunday,
        schedules: [
          SupplementSchedule(
            id: 'dst',
            profileId: 'profile',
            supplementId: supplement.id,
            dose: 1,
            unit: 'capsule',
            timeOfDay: '08:00',
            weekdays: const ['sunday'],
            createdAt: monday,
            updatedAt: monday,
          ),
        ],
        supplements: [supplement],
        intakes: [legacyIntake('dst-intake', DateTime(2026, 3, 29, 8, 45))],
      );
      expect(result.single.intake?.id, 'dst-intake');
      expect(result.single.dueAt, DateTime(2026, 3, 29, 8));
    },
  );

  test('injected evaluation time determines pending and missed dose state', () {
    final beforeDose = service.dosesForDay(
      day: monday,
      schedules: [schedule],
      supplements: [supplement],
      intakes: const [],
      now: DateTime(2026, 7, 13, 7, 59),
    );
    expect(beforeDose.single.pending, isTrue);
    expect(beforeDose.single.missed, isFalse);

    final afterDose = service.dosesForDay(
      day: monday,
      schedules: [schedule],
      supplements: [supplement],
      intakes: const [],
      now: DateTime(2026, 7, 13, 8, 1),
    );
    expect(afterDose.single.pending, isFalse);
    expect(afterDose.single.missed, isTrue);
  });

  test('projects household stock from all profile schedules', () {
    final projection = service
        .stockProjections(
          supplements: [supplement],
          householdSchedules: [schedule],
          stockLevels: {supplement.id: 14},
        )
        .single;
    expect(projection.weeklyScheduledUnits, 14);
    expect(projection.daysRemaining, 7);
    expect(projection.low, isTrue);
    expect(projection.suggestedPurchaseUnits, 154);
  });

  test('monthly cost uses package price and scheduled units', () {
    final cost = service.monthlyCostEstimate(
      supplements: [supplement],
      householdSchedules: [schedule],
    );
    expect(cost, closeTo(12.1333, 0.001));
  });

  test(
    'history ranges use inclusive local days and never include future dates',
    () {
      final range = service.historyRange(
        selection: '30',
        now: DateTime(2026, 1, 30, 23),
        historyDates: const [],
      );
      expect(range.from, DateTime(2026, 1, 1));
      expect(range.through, DateTime(2026, 1, 30));

      final all = service.historyRange(
        selection: 'all',
        now: DateTime(2026, 1, 30),
        historyDates: [DateTime(2024, 2, 3), DateTime(2027, 1, 1)],
      );
      expect(all.from, DateTime(2024, 2, 3));
      expect(all.through, DateTime(2026, 1, 30));
    },
  );

  test('weekly adherence carries buckets across a year boundary', () {
    final values = service.weeklyAdherence(
      from: DateTime(2025, 12, 29),
      through: DateTime(2026, 1, 4),
      schedules: [schedule],
      supplements: [supplement],
      intakes: const [],
      now: DateTime(2026, 1, 5),
    );
    expect(values, hasLength(1));
    expect(values.single.weekStarting, DateTime(2025, 12, 29));
    expect(values.single.scheduled, 7);
    expect(values.single.missed, 7);
  });

  test(
    'weekly buckets use Monday local dates on either side of a new year',
    () {
      final values = service.weeklyAdherence(
        from: DateTime(2026, 1, 4), // Sunday, in the final 2025 week.
        through: DateTime(2026, 1, 5), // Monday, first new week.
        schedules: [schedule],
        supplements: [supplement],
        intakes: const [],
        now: DateTime(2026, 1, 6),
      );
      expect(values.map((item) => item.weekStarting), [
        DateTime(2025, 12, 29),
        DateTime(2026, 1, 5),
      ]);
    },
  );

  test('future scheduled doses are not counted as missed', () {
    final evening = SupplementSchedule(
      id: 'evening',
      profileId: 'profile',
      supplementId: supplement.id,
      dose: 1,
      unit: 'capsule',
      timeOfDay: 'Evening',
      weekdays: const ['monday'],
      createdAt: monday,
      updatedAt: monday,
    );
    final day = service.dailyAdherence(
      from: monday,
      through: monday,
      schedules: [evening],
      supplements: [supplement],
      intakes: const [],
      now: DateTime(2026, 7, 13, 9),
    );
    expect(day.single.scheduled, 0);
    expect(day.single.missed, 0);
  });

  test(
    'exposure never combines mixed reported units and sorts deterministically',
    () {
      final zinc = Supplement(
        id: 'zinc',
        name: 'Zinc',
        stockUnit: 'tablet',
        createdAt: monday,
        updatedAt: monday,
      );
      SupplementIntake intake(
        String id,
        String supplementId,
        double dose,
        String unit,
      ) => SupplementIntake(
        id: id,
        profileId: 'profile',
        supplementId: supplementId,
        takenAt: monday,
        dose: dose,
        unit: unit,
        createdAt: monday,
        updatedAt: monday,
      );
      final values = service.supplementExposure(
        intakes: [
          intake('one', supplement.id, 2, 'capsule'),
          intake('two', supplement.id, 500, 'mg'),
          intake('three', zinc.id, 2, 'tablet'),
        ],
        supplements: [supplement, zinc],
        from: monday,
        through: monday,
      );
      expect(values.map((item) => '${item.name}:${item.unit}:${item.total}'), [
        'Magnesium:mg:500.0',
        'Magnesium:capsule:2.0',
        'Zinc:tablet:2.0',
      ]);
    },
  );

  test(
    'ingredient exposure keeps component units separate at range boundaries',
    () {
      SupplementIntake intake(String id, DateTime takenAt, String unit) =>
          SupplementIntake(
            id: id,
            profileId: 'profile',
            supplementId: supplement.id,
            takenAt: takenAt,
            dose: 1,
            unit: 'capsule',
            ingredientSnapshot: [
              {'name': 'Vitamin C', 'amount': 500, 'unit': unit},
            ],
            createdAt: monday,
            updatedAt: monday,
          );
      final values = service.ingredientExposure(
        intakes: [
          intake('start', DateTime(2026, 7, 10, 23), 'mg'),
          intake('end', DateTime(2026, 7, 13, 1), 'g'),
          intake('outside', DateTime(2026, 7, 14), 'mg'),
        ],
        from: DateTime(2026, 7, 10),
        to: DateTime(2026, 7, 13),
      );
      expect(values.map((item) => '${item.total} ${item.unit}'), [
        '500.0 g',
        '500.0 mg',
      ]);
    },
  );

  test(
    'ingredient exposure ignores non-finite malformed historical amounts',
    () {
      final intake = SupplementIntake(
        id: 'malformed-ingredients',
        profileId: 'profile',
        supplementId: supplement.id,
        takenAt: monday,
        dose: 2,
        unit: 'capsule',
        ingredientSnapshot: [
          {'name': 'Finite string', 'amount': '1,5', 'unit': 'mg'},
          {'name': 'NaN number', 'amount': double.nan, 'unit': 'mg'},
          {'name': 'Infinity number', 'amount': double.infinity, 'unit': 'mg'},
          {'name': 'Infinity string', 'amount': 'Infinity', 'unit': 'mg'},
        ],
        createdAt: monday,
        updatedAt: monday,
      );

      final values = service.ingredientExposure(
        intakes: [
          intake,
          SupplementIntake(
            id: 'non-finite-dose',
            profileId: 'profile',
            supplementId: supplement.id,
            takenAt: monday,
            dose: double.nan,
            unit: 'capsule',
            ingredientSnapshot: const [
              {'name': 'Finite string', 'amount': 10, 'unit': 'mg'},
            ],
            createdAt: monday,
            updatedAt: monday,
          ),
        ],
        from: monday,
        to: monday,
      );

      expect(values, hasLength(1));
      expect(values.single.name, 'Finite string');
      expect(values.single.total, 3);
      expect(values.single.total.isFinite, isTrue);
    },
  );

  test(
    'known intake cost reports coverage instead of treating exclusions as a total',
    () {
      final valid = SupplementIntake(
        id: 'valid',
        profileId: 'profile',
        supplementId: supplement.id,
        takenAt: monday,
        dose: 2,
        unit: 'capsules',
        createdAt: monday,
        updatedAt: monday,
      );
      final incompatible = SupplementIntake(
        id: 'incompatible',
        profileId: 'profile',
        supplementId: supplement.id,
        takenAt: monday,
        dose: 500,
        unit: 'mg',
        createdAt: monday,
        updatedAt: monday,
      );
      final value = service.actualIntakeCost(
        intakes: [valid, incompatible],
        supplements: [supplement],
        from: monday,
        through: monday,
      );
      expect(value.knownEur, closeTo(0.4, 0.0001));
      expect(value.eligibleIntakes, 2);
      expect(value.knownIntakes, 1);
      expect(value.unknownIntakes, 1);
      expect(value.completeCoverage, isFalse);
      expect(value.daily.single.knownEur, closeTo(0.4, 0.0001));
    },
  );

  test('maps named schedule slots and clock hours onto day blocks', () {
    expect(service.periodOfSlot('Morning'), DosePeriod.morning);
    expect(service.periodOfSlot('bedtime'), DosePeriod.bedtime);
    expect(service.periodOfSlot('PM'), DosePeriod.evening);
    // An exact time is not a named block, so callers fall back to the hour.
    expect(service.periodOfSlot('08:30'), isNull);
    expect(service.periodOfHour(9), DosePeriod.morning);
    expect(service.periodOfHour(13), DosePeriod.midday);
    expect(service.periodOfHour(19), DosePeriod.evening);
    expect(service.periodOfHour(23), DosePeriod.bedtime);
  });

  test('weekly series buckets intakes into Monday-anchored weeks', () {
    final nextMonday = monday.add(const Duration(days: 7));
    final intakes = [
      for (final day in [monday, monday.add(const Duration(days: 3))])
        SupplementIntake(
          id: 'a-${day.day}',
          profileId: 'profile',
          supplementId: supplement.id,
          takenAt: day,
          dose: 2,
          unit: 'capsules',
          ingredientSnapshot: const [
            {'name': 'Magnesium', 'amount': 100, 'unit': 'mg'},
          ],
          createdAt: day,
          updatedAt: day,
        ),
      SupplementIntake(
        id: 'b',
        profileId: 'profile',
        supplementId: supplement.id,
        takenAt: nextMonday,
        dose: 1,
        unit: 'capsules',
        ingredientSnapshot: const [
          {'name': 'Magnesium', 'amount': 100, 'unit': 'mg'},
        ],
        createdAt: nextMonday,
        updatedAt: nextMonday,
      ),
    ];

    final weeks = service.weeksIn(from: monday, through: nextMonday);
    expect(weeks, [monday, nextMonday]);

    final products = service.weeklySupplementSeries(
      intakes: intakes,
      supplements: [supplement],
      from: monday,
      through: nextMonday,
    );
    expect(products, hasLength(1));
    expect(products.single.weeklyTotals[monday], 4);
    expect(products.single.weeklyTotals[nextMonday], 1);
    expect(products.single.total, 5);

    final components = service.weeklyIngredientSeries(
      intakes: intakes,
      from: monday,
      through: nextMonday,
    );
    expect(components.single.label, 'Magnesium (mg)');
    expect(components.single.weeklyTotals[monday], 400);
    expect(components.single.weeklyTotals[nextMonday], 100);
  });

  test('purchase plan rounds up to whole packages and flags unknown sizes', () {
    final noPackageSize = Supplement(
      id: 'vitamin-d',
      name: 'Vitamin D',
      stockUnit: 'capsule',
      createdAt: monday,
      updatedAt: monday,
    );
    final noPackageSchedule = SupplementSchedule(
      id: 'vitamin-d-schedule',
      profileId: 'profile',
      supplementId: noPackageSize.id,
      dose: 1,
      unit: 'capsule',
      timeOfDay: 'Morning',
      weekdays: const ['monday'],
      createdAt: monday,
      updatedAt: monday,
    );

    final plan = service.purchasePlan(
      supplements: [supplement, noPackageSize],
      householdSchedules: [schedule, noPackageSchedule],
      stockLevels: {supplement.id: 10},
      months: 1,
    );

    final magnesium = plan.firstWhere(
      (item) => item.supplement.id == supplement.id,
    );
    // 2 capsules on all seven days is 14 a week, so 14 * 52 / 12 a month.
    expect(magnesium.requiredUnits, closeTo(60.667, 0.01));
    expect(magnesium.missingUnits, closeTo(50.667, 0.01));
    expect(magnesium.containersToBuy, 1);
    expect(magnesium.estimatedCostEur, closeTo(12, 0.0001));
    expect(magnesium.covered, isFalse);

    final vitaminD = plan.firstWhere(
      (item) => item.supplement.id == noPackageSize.id,
    );
    expect(vitaminD.containersToBuy, isNull);
    expect(vitaminD.estimatedCostEur, isNull);
  });

  test('purchase plan reports full cover without asking for a purchase', () {
    final plan = service.purchasePlan(
      supplements: [supplement],
      householdSchedules: [schedule],
      stockLevels: {supplement.id: 500},
      months: 1,
    );
    expect(plan.single.covered, isTrue);
    expect(plan.single.missingUnits, 0);
    expect(plan.single.containersToBuy, 0);
  });

  test('planned weekly components read the schedule, not adherence', () {
    final values = service.plannedWeeklyIngredients(
      supplements: [
        Supplement(
          id: supplement.id,
          name: supplement.name,
          stockUnit: supplement.stockUnit,
          unitsPerContainer: supplement.unitsPerContainer,
          priceEur: supplement.priceEur,
          ingredients: const [
            {'name': 'Magnesium', 'amount': 100, 'unit': 'mg'},
          ],
          createdAt: monday,
          updatedAt: monday,
        ),
      ],
      schedules: [schedule],
    );
    // 2 capsules on seven days, each carrying 100 mg.
    expect(values.single.name, 'Magnesium');
    expect(values.single.unit, 'mg');
    expect(values.single.total, 1400);
  });

  test('monthly cost breaks down per product and omits unpriced ones', () {
    final unpriced = Supplement(
      id: 'zinc',
      name: 'Zinc',
      stockUnit: 'capsule',
      createdAt: monday,
      updatedAt: monday,
    );
    final unpricedSchedule = SupplementSchedule(
      id: 'zinc-schedule',
      profileId: 'profile',
      supplementId: unpriced.id,
      dose: 1,
      unit: 'capsule',
      timeOfDay: 'Morning',
      weekdays: const ['monday'],
      createdAt: monday,
      updatedAt: monday,
    );

    final values = service.monthlyCostByProduct(
      supplements: [supplement, unpriced],
      householdSchedules: [schedule, unpricedSchedule],
    );

    expect(values, hasLength(1));
    expect(values.single.supplement.id, supplement.id);
    expect(values.single.eur, closeTo(14 * 52 / 12 * 12 / 60, 0.0001));
    expect(
      service.monthlyCostEstimate(
        supplements: [supplement, unpriced],
        householdSchedules: [schedule, unpricedSchedule],
      ),
      closeTo(values.single.eur, 0.0001),
    );
  });
}
