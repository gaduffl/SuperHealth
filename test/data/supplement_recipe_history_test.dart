import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/analysis/supplement_insights.dart';
import 'package:super_health/analysis/exposure_analysis.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/domain/ingredient_composition.dart';

final _before = DateTime.utc(2026, 5, 1);
final _after = DateTime.utc(2026, 10, 27);
List<Map<String, Object?>> _recipe(num amount) => [
  {'name': 'B12', 'amount': amount, 'unit': 'microgram'},
];
Supplement _product(List<Map<String, Object?>> recipe) => Supplement(
  id: 'b12',
  name: 'B12',
  ingredients: recipe,
  stockUnit: 'capsule',
  createdAt: _before,
  updatedAt: _after,
);

void main() {
  setUpAll(sqfliteFfiInit);
  late AppDatabase database;
  late HealthRepository repository;
  late String alpha;
  late String beta;
  setUp(() async {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = HealthRepository(database);
    alpha = (await repository.createProfile(displayName: 'Alpha')).id;
    beta = (await repository.createProfile(displayName: 'Beta')).id;
    await repository.saveSupplement(_product(_recipe(1001)));
  });
  tearDown(() => database.close());

  Future<void> intake(
    String id, {
    String? profile,
    List<Map<String, Object?>> recipe = const [],
    bool recorded = false,
    bool deleted = false,
  }) => repository.saveIntake(
    SupplementIntake(
      id: id,
      profileId: profile ?? alpha,
      supplementId: 'b12',
      takenAt: _before,
      dose: 2,
      unit: 'capsule',
      notes: 'Keep this note',
      ingredientSnapshot: recipe,
      ingredientSnapshotRecorded: recorded,
      createdAt: _before,
      updatedAt: _before,
      deleted: deleted,
    ),
    inventoryUnits: deleted ? null : 2,
  );
  Future<Map<String, SupplementIntake>> all() async => {
    for (final row in await (await database.database).query(
      'supplement_intakes',
    ))
      row['id']! as String: SupplementIntake.fromMap(row),
  };

  test(
    'a recipe change requires a choice before any record is changed',
    () async {
      await intake('missing');
      await expectLater(
        repository.updateSupplement(_product(_recipe(1000))),
        throwsStateError,
      );
      expect(
        (await repository.supplements()).single.ingredients.single['amount'],
        1001,
      );
      expect((await all())['missing']!.hasIngredientSnapshot, isFalse);
    },
  );

  test(
    'starting now freezes missing snapshots for every profile and preserves existing recipes',
    () async {
      await intake('missing');
      await intake('other-profile', profile: beta);
      await intake('earlier-recipe', recipe: _recipe(900));
      await intake('empty-frozen', recorded: true);
      await intake('deleted', deleted: true);
      final stock = await repository.stockLevels();
      await repository.updateSupplement(
        _product(_recipe(1000)),
        historyUpdate: SupplementHistoryUpdate.startingNow,
      );
      final rows = await all();
      for (final id in ['missing', 'other-profile']) {
        expect(rows[id]!.ingredientSnapshot.single['amount'], 1001);
        expect(rows[id]!.ingredientSnapshot.single['unit'], 'µg');
        expect(rows[id]!.ingredientSnapshotRecorded, isTrue);
      }
      expect(rows['earlier-recipe']!.ingredientSnapshot.single['amount'], 900);
      expect(rows['earlier-recipe']!.updatedAt, _before.toLocal());
      expect(rows['empty-frozen']!.ingredientSnapshot, isEmpty);
      expect(rows['empty-frozen']!.hasIngredientSnapshot, isTrue);
      expect(rows['deleted']!.hasIngredientSnapshot, isFalse);
      expect(await repository.stockLevels(), stock);
      expect(
        (await repository.supplements()).single.ingredients.single['amount'],
        1000,
      );
    },
  );

  test(
    'correct history rewrites snapshots across profiles without changing intake details or inventory',
    () async {
      await intake('missing');
      await intake('captured', recipe: _recipe(1001));
      await intake('other-profile', profile: beta, recipe: _recipe(900));
      await intake('empty-frozen', recorded: true);
      await intake('deleted', recipe: _recipe(1001), deleted: true);
      final original = await all();
      final db = await database.database;
      final ledger = await db.query('inventory_movements');
      await repository.updateSupplement(
        _product(_recipe(1000)),
        historyUpdate: SupplementHistoryUpdate.correctHistory,
      );
      final rows = await all();
      for (final id in [
        'missing',
        'captured',
        'other-profile',
        'empty-frozen',
      ]) {
        expect(rows[id]!.ingredientSnapshot.single['amount'], 1000);
        expect(rows[id]!.ingredientSnapshotRecorded, isTrue);
        final actual = rows[id]!.toMap()
          ..remove('ingredients_json')
          ..remove('ingredient_snapshot_recorded')
          ..remove('updated_at');
        final expected = original[id]!.toMap()
          ..remove('ingredients_json')
          ..remove('ingredient_snapshot_recorded')
          ..remove('updated_at');
        expect(actual, expected);
        expect(rows[id]!.updatedAt, _after.toLocal());
      }
      expect(rows['deleted']!.toMap(), original['deleted']!.toMap());
      expect(await db.query('inventory_movements'), ledger);
      const insights = SupplementInsights();
      final totals = insights.ingredientExposure(
        intakes: await repository.intakes(alpha),
        supplements: await repository.supplements(),
        from: _before,
        to: _after,
      );
      expect(totals.single.total, 6000);
      final weekly = insights.weeklyIngredientSeries(
        intakes: await repository.intakes(alpha),
        supplements: await repository.supplements(),
        from: _before,
        through: _after,
      );
      expect(weekly.single.total, totals.single.total);
    },
  );

  test(
    'the already-corrected product can explicitly repair its history',
    () async {
      await intake('captured', recipe: _recipe(1001));
      await repository.saveSupplement(_product(_recipe(1000)));
      await repository.updateSupplement(
        _product(_recipe(1000)),
        historyUpdate: SupplementHistoryUpdate.correctHistory,
      );
      expect(
        (await all())['captured']!.ingredientSnapshot.single['amount'],
        1000,
      );
    },
  );

  test(
    'frozen empty recipes stay empty in totals, charts, targets and clinical exposure',
    () async {
      await repository.saveSupplement(_product(const []));
      await intake('empty');
      await repository.updateSupplement(
        _product(_recipe(1000)),
        historyUpdate: SupplementHistoryUpdate.startingNow,
      );
      final intakes = await repository.intakes(alpha);
      final supplements = await repository.supplements();
      expect(intakes.single.ingredientSnapshotRecorded, isTrue);
      const insights = SupplementInsights();
      expect(
        insights.ingredientExposure(
          intakes: intakes,
          supplements: supplements,
          from: _before,
          to: _after,
        ),
        isEmpty,
      );
      expect(
        insights.weeklyIngredientSeries(
          intakes: intakes,
          supplements: supplements,
          from: _before,
          through: _after,
        ),
        isEmpty,
      );
      final clinical = ExposureAnalysis.build(
        supplements: supplements,
        schedules: [],
        intakes: intakes,
        records: [],
        now: _after,
      );
      expect(clinical.events.single.fromProductName, isTrue);
      expect(clinical.events.single.amount, isNull);
      expect(
        insights
            .knownDoseTargets(intakes: intakes, supplements: supplements)
            .where((target) => target.supplementId == null),
        isEmpty,
      );
    },
  );

  test('recipe save failure rolls back every historical snapshot', () async {
    await intake('missing');
    final db = await database.database;
    await db.execute(
      "CREATE TRIGGER fail_recipe BEFORE UPDATE ON supplements BEGIN SELECT RAISE(ABORT, 'test rollback'); END",
    );
    await expectLater(
      repository.updateSupplement(
        _product(_recipe(1000)),
        historyUpdate: SupplementHistoryUpdate.correctHistory,
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect((await all())['missing']!.hasIngredientSnapshot, isFalse);
    expect(
      (await repository.supplements()).single.ingredients.single['amount'],
      1001,
    );
  });

  test('aliases and row ordering do not require a history decision', () {
    expect(
      ingredientRecipesEqual(
        [
          ..._recipe(1000),
          {'name': 'Magnesium', 'amount': 40, 'unit': 'mg'},
        ],
        [
          {'name': 'Magnesium', 'amount': 40.0, 'unit': 'mg'},
          {'name': 'Vitamin B12', 'amount': 1000.0, 'unit': 'µg'},
        ],
      ),
      isTrue,
    );
    expect(ingredientRecipesEqual(_recipe(1001), _recipe(1000)), isFalse);
    expect(
      ingredientRecipesEqual(_recipe(1000), [
        {'name': 'B12', 'amount': 1000, 'unit': 'mg'},
      ]),
      isFalse,
    );
  });
}
