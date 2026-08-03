import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/analysis/supplement_insights.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  const insights = SupplementInsights();

  test('average daily dose divides by every day in the bucket', () {
    // Seven days, one 1000 IU capsule taken on three of them.
    final series = insights.doseSeries(
      intakes: [
        for (final day in [1, 3, 5])
          _intake(DateTime(2026, 3, day), amount: 1000, unit: 'IU'),
      ],
      target: const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
      from: DateTime(2026, 3, 1),
      through: DateTime(2026, 3, 7),
      targetBuckets: 1,
    );

    expect(series.buckets, hasLength(1));
    expect(series.bucketDays, 7);
    // 3000 IU spread over seven calendar days, not over the three dosed days.
    expect(series.buckets.single.averageDailyDose, closeTo(3000 / 7, 1e-9));
    expect(series.hasDose, isTrue);
  });

  test('a mismatched unit is a different series and never converted', () {
    final series = insights.doseSeries(
      intakes: [
        _intake(DateTime(2026, 3, 1), amount: 1000, unit: 'IU'),
        // 25 µg is the same real dose as 1000 IU, but the app must not know
        // that: an unconverted unit is a separate series.
        _intake(DateTime(2026, 3, 2), amount: 25, unit: 'µg'),
      ],
      target: const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
      from: DateTime(2026, 3, 1),
      through: DateTime(2026, 3, 2),
      targetBuckets: 1,
    );

    expect(series.buckets.single.averageDailyDose, closeTo(1000 / 2, 1e-9));
  });

  test('skipped and deleted intakes contribute no dose', () {
    final series = insights.doseSeries(
      intakes: [
        _intake(DateTime(2026, 3, 1), amount: 1000, unit: 'IU', skipped: true),
        _intake(DateTime(2026, 3, 1), amount: 1000, unit: 'IU', deleted: true),
      ],
      target: const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
      from: DateTime(2026, 3, 1),
      through: DateTime(2026, 3, 1),
      targetBuckets: 1,
    );

    expect(series.buckets.single.averageDailyDose, 0);
    // The skipped intake still proves the day was tracked; the deleted one
    // would not have on its own.
    expect(series.buckets.single.tracked, isTrue);
    expect(series.hasDose, isFalse);
  });

  test('an untracked bucket is distinguishable from a genuine zero', () {
    final series = insights.doseSeries(
      intakes: [
        // Tracking happened only in the first week, and of a different
        // ingredient, so week one is a genuine zero and week two is a gap.
        _intake(
          DateTime(2026, 3, 2),
          amount: 400,
          unit: 'mg',
          name: 'Magnesium',
        ),
      ],
      target: const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
      from: DateTime(2026, 3, 1),
      through: DateTime(2026, 3, 14),
      targetBuckets: 2,
    );

    expect(series.buckets, hasLength(2));
    expect(series.buckets.first.averageDailyDose, 0);
    expect(series.buckets.first.tracked, isTrue);
    expect(series.buckets.last.averageDailyDose, 0);
    expect(series.buckets.last.tracked, isFalse);
  });

  test('bucket boundaries stay on local midnight across a DST change', () {
    // Central European DST begins 2026-03-29. Stepping by Duration would drift
    // an hour and pull a dose into the neighbouring bucket.
    final series = insights.doseSeries(
      intakes: const [],
      target: const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
      from: DateTime(2026, 3, 25),
      through: DateTime(2026, 4, 3),
      targetBuckets: 10,
    );

    expect(series.bucketDays, 1);
    for (final bucket in series.buckets) {
      expect(bucket.start.hour, 0);
      expect(bucket.start.minute, 0);
      expect(bucket.end.hour, 0);
    }
    expect(series.buckets.first.start, DateTime(2026, 3, 25));
    expect(series.buckets.last.start, DateTime(2026, 4, 3));
  });

  test('buckets cover the span exactly once with no gap or overlap', () {
    final series = insights.doseSeries(
      intakes: const [],
      target: const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
      from: DateTime(2026, 1, 1),
      through: DateTime(2026, 12, 31),
      targetBuckets: 40,
    );

    expect(series.buckets.first.start, DateTime(2026, 1, 1));
    expect(series.buckets.last.end, DateTime(2027, 1, 1));
    for (var index = 1; index < series.buckets.length; index++) {
      expect(series.buckets[index].start, series.buckets[index - 1].end);
    }
    // A year at ~40 buckets should land on a readable stride, not 365 bars.
    expect(series.buckets.length, lessThanOrEqualTo(40));
    expect(series.bucketDays, greaterThan(1));
  });

  test('known ingredients are deduplicated per name and unit', () {
    final ingredients = insights.knownIngredients([
      _intake(DateTime(2026, 3, 1), amount: 1000, unit: 'IU'),
      _intake(DateTime(2026, 3, 2), amount: 2000, unit: 'IU'),
      _intake(DateTime(2026, 3, 3), amount: 25, unit: 'µg'),
      _intake(DateTime(2026, 3, 4), amount: 400, unit: 'mg', name: 'Magnesium'),
      _intake(DateTime(2026, 3, 5), amount: 1, unit: 'mg', deleted: true),
    ]);

    expect(ingredients, [
      (name: 'Magnesium', unit: 'mg'),
      (name: 'Vitamin D3', unit: 'IU'),
      (name: 'Vitamin D3', unit: 'µg'),
    ]);
  });

  group('ingredient suggestion', () {
    const vitaminD = DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU');
    const b12 = DoseTarget.ingredient(name: 'Vitamin B12', unit: '\u00b5g');
    const magnesium = DoseTarget.ingredient(name: 'Magnesium', unit: 'mg');
    const available = [vitaminD, b12, magnesium];

    DoseTarget? suggest(List<String> trendNames) =>
        insights.suggestDoseTarget(targets: available, trendNames: trendNames);

    test('an assay-qualified biomarker finds its plain ingredient', () {
      expect(suggest(['Vitamin D (25-OH)']), vitaminD);
      expect(suggest(['25-Hydroxyvitamin D', 'Vitamin D']), vitaminD);
      expect(suggest(['Magnesium, serum']), magnesium);
    });

    test('different forms of the same vitamin never collide', () {
      // B12 and B6 are different vitamins; matching them would put the wrong
      // dose under the trend.
      expect(suggest(['Vitamin B6']), isNull);
      expect(suggest(['Vitamin B12']), b12);
    });

    test('an unrelated marker suggests nothing rather than guessing', () {
      expect(suggest(['Ferritin']), isNull);
      expect(suggest(['Vitamin C']), isNull);
      expect(suggest(['']), isNull);
      expect(suggest([]), isNull);
    });
  });

  group('what the picker offers', () {
    // The ingredient editor stores no 'unit' key at all when the unit box is
    // left empty, and no 'amount' key when the amount is empty.
    final unitless = _rawIntake(
      DateTime(2026, 3, 1),
      supplementId: 'ashwa',
      unit: 'capsule',
      snapshot: const [
        {'name': 'Ashwagandha', 'amount': 600},
      ],
    );
    final bare = _rawIntake(
      DateTime(2026, 3, 1),
      supplementId: 'creatine',
      unit: 'scoop',
      snapshot: const [],
    );
    final supplements = [
      _supplement('ashwa', 'Ashwagandha KSM-66'),
      _supplement('creatine', 'Creatine monohydrate'),
    ];

    test('an ingredient saved without a unit is still offered', () {
      final targets = insights.knownDoseTargets(
        intakes: [unitless],
        supplements: supplements,
      );
      expect(
        targets.where((target) => !target.isSupplement).map((t) => t.name),
        contains('Ashwagandha'),
      );
    });

    test('a product with no ingredient rows is still offered', () {
      final targets = insights.knownDoseTargets(
        intakes: [bare],
        supplements: supplements,
      );
      expect(
        targets.where((target) => target.isSupplement).map((t) => t.name),
        ['Creatine monohydrate'],
      );
    });

    test('a product dose follows what was actually logged', () {
      final series = insights.doseSeries(
        intakes: [
          for (var day = 0; day < 4; day++)
            _rawIntake(
              DateTime(2026, 3, 1 + day),
              supplementId: 'creatine',
              unit: 'scoop',
              snapshot: const [],
              dose: 2,
            ),
        ],
        target: const DoseTarget.supplement(
          supplementId: 'creatine',
          name: 'Creatine monohydrate',
          unit: 'scoop',
        ),
        from: DateTime(2026, 3, 1),
        through: DateTime(2026, 3, 4),
        targetBuckets: 1,
      );

      // Two scoops a day for four days, with no ingredient breakdown needed.
      expect(series.buckets.single.averageDailyDose, closeTo(2, 1e-9));
    });

    test('an intake with no snapshot falls back to its product ingredients', () {
      // Intakes recorded before a product was broken down carry no snapshot;
      // dropping them would show a gap in supplementation that never happened.
      final series = insights.doseSeries(
        intakes: [
          _rawIntake(
            DateTime(2026, 3, 1),
            supplementId: 'd3',
            unit: 'drop',
            snapshot: const [],
          ),
        ],
        supplements: [
          Supplement(
            id: 'd3',
            name: 'D3 drops',
            ingredients: const [
              {'name': 'Vitamin D3', 'unit': 'IU', 'amount': 1000},
            ],
            createdAt: DateTime(2026, 1, 1),
            updatedAt: DateTime(2026, 1, 1),
          ),
        ],
        target: const DoseTarget.ingredient(name: 'Vitamin D3', unit: 'IU'),
        from: DateTime(2026, 3, 1),
        through: DateTime(2026, 3, 1),
        targetBuckets: 1,
      );

      expect(series.buckets.single.averageDailyDose, closeTo(1000, 1e-9));
    });

    test('doseSpan reports where a target was actually taken', () {
      final span = insights.doseSpan(
        intakes: [
          for (var day = 0; day < 10; day++)
            _rawIntake(
              DateTime(2026, 4, 1 + day),
              supplementId: 'creatine',
              unit: 'scoop',
              snapshot: const [],
            ),
        ],
        target: const DoseTarget.supplement(
          supplementId: 'creatine',
          name: 'Creatine monohydrate',
          unit: 'scoop',
        ),
      );

      expect(span?.from, DateTime(2026, 4, 1));
      expect(span?.through, DateTime(2026, 4, 10));
    });
  });
}

Supplement _supplement(String id, String name) => Supplement(
  id: id,
  name: name,
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

SupplementIntake _rawIntake(
  DateTime takenAt, {
  required String supplementId,
  required String unit,
  required List<Map<String, Object?>> snapshot,
  double dose = 1,
}) => SupplementIntake(
  id: 'raw-$supplementId-${takenAt.millisecondsSinceEpoch}',
  profileId: 'profile',
  supplementId: supplementId,
  takenAt: takenAt,
  dose: dose,
  unit: unit,
  ingredientSnapshot: snapshot,
  createdAt: takenAt,
  updatedAt: takenAt,
);

SupplementIntake _intake(
  DateTime takenAt, {
  required double amount,
  required String unit,
  String name = 'Vitamin D3',
  bool skipped = false,
  bool deleted = false,
}) => SupplementIntake(
  id: 'intake-${takenAt.millisecondsSinceEpoch}-$name-$unit-$deleted',
  profileId: 'profile',
  supplementId: 'supplement',
  takenAt: takenAt,
  dose: 1,
  unit: 'capsule',
  skipped: skipped,
  deleted: deleted,
  ingredientSnapshot: [
    {'name': name, 'unit': unit, 'amount': amount},
  ],
  createdAt: takenAt,
  updatedAt: takenAt,
);
