import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  late AppDatabase database;
  late HealthRepository repository;

  setUp(() {
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = HealthRepository(database);
  });

  tearDown(() => database.close());

  test('supplement-side units are canonicalised on write', () async {
    final profile = await repository.createProfile(displayName: 'Units');
    final now = DateTime(2026, 8, 6);
    await repository.saveSupplement(
      Supplement(
        id: 's',
        name: 'D3',
        stockUnit: 'Capsule',
        ingredients: const [
          // The three spellings that coexisted in one real library.
          {'name': 'Vitamin D3', 'unit': 'IE', 'amount': 1000},
          {'name': 'Vitamin B12', 'unit': 'microgram', 'amount': 500},
          {'name': 'Magnesium', 'unit': 'mg', 'amount': 300},
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.saveIntake(
      SupplementIntake(
        id: 'i',
        profileId: profile.id,
        supplementId: 's',
        takenAt: now,
        dose: 1,
        unit: 'Kapseln',
        ingredientSnapshot: const [
          {'name': 'Vitamin D3', 'unit': 'IE', 'amount': 1000},
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );

    final db = await database.database;
    final supplement = (await db.query('supplements')).single;
    expect(supplement['stock_unit'], 'capsule');
    final ingredients =
        jsonDecode(supplement['ingredients_json']! as String) as List;
    expect(ingredients.map((i) => (i as Map)['unit']), ['IU', 'µg', 'mg']);
    // Names are untouched — renaming a substance is the review screen's job.
    expect(ingredients.map((i) => (i as Map)['name']), [
      'Vitamin D3',
      'Vitamin B12',
      'Magnesium',
    ]);

    final intake = (await db.query('supplement_intakes')).single;
    expect(intake['unit'], 'capsule');
    expect(jsonDecode(intake['ingredients_json']! as String), [
      {'name': 'Vitamin D3', 'unit': 'IU', 'amount': 1000},
    ]);
  });

  test('biomarker-side units are canonicalised on write', () async {
    final now = DateTime(2026, 8, 6);
    final profile = await repository.createProfile(displayName: 'Labs');
    await repository.saveBiomarker(
      Biomarker(
        id: 'b',
        canonicalName: 'ferritin',
        displayName: 'Ferritin',
        defaultUnit: 'ug/l',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.saveMeasurement(
      Measurement(
        id: 'm',
        profileId: profile.id,
        biomarkerId: 'b',
        takenAt: now,
        value: 42,
        // The lowercase-litre spelling a German lab report actually uses.
        unit: 'ug/l',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final db = await database.database;
    expect((await db.query('biomarkers')).single['default_unit'], 'ug/L');
    expect((await db.query('measurements')).single['unit_reported'], 'ug/L');
  });

  test('an unrecognised unit is preserved, not coerced', () async {
    final now = DateTime(2026, 8, 6);
    await repository.saveSupplement(
      Supplement(
        id: 's',
        name: 'Odd',
        // A dosage form, not a unit. It must survive rather than being bent
        // into the nearest countable thing.
        stockUnit: 'Powder',
        ingredients: const [
          {'name': 'Mystery', 'unit': 'bananas', 'amount': 1},
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );

    final db = await database.database;
    final row = (await db.query('supplements')).single;
    expect(row['stock_unit'], 'Powder');
    expect((jsonDecode(row['ingredients_json']! as String) as List).single, {
      'name': 'Mystery',
      'unit': 'bananas',
      'amount': 1,
    });
  });

  test('an ingredient with no unit key keeps none', () async {
    final now = DateTime(2026, 8, 6);
    await repository.saveSupplement(
      Supplement(
        id: 's',
        name: 'Unitless',
        // IngredientEditor omits the key entirely when the box is empty.
        ingredients: const [
          {'name': 'Ashwagandha', 'amount': 600},
        ],
        createdAt: now,
        updatedAt: now,
      ),
    );

    final db = await database.database;
    final ingredient =
        (jsonDecode(
                  (await db.query('supplements')).single['ingredients_json']!
                      as String,
                )
                as List)
            .single;
    expect(ingredient, {'name': 'Ashwagandha', 'amount': 600});
    expect((ingredient as Map).containsKey('unit'), isFalse);
  });

  test('a dose link stores one spelling however it was written', () async {
    final now = DateTime(2026, 8, 6);
    final profile = await repository.createProfile(displayName: 'Link');
    await repository.saveBiomarker(
      Biomarker(
        id: 'b',
        canonicalName: 'b12',
        displayName: 'B12',
        createdAt: now,
        updatedAt: now,
      ),
    );
    // The exact drift found in real data: the same ingredient linked once as
    // "microgram" and once as "µg", which split it into two series.
    for (final (id, unit) in [('l1', 'microgram'), ('l2', 'µg')]) {
      await repository.saveTrendDoseLink(
        TrendDoseLink(
          id: id,
          profileId: profile.id,
          biomarkerId: 'b',
          ingredientName: 'B12',
          ingredientUnit: unit,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }

    final db = await database.database;
    final units = (await db.query(
      'trend_dose_links',
    )).map((r) => r['ingredient_unit']).toSet();
    expect(units, {'µg'});
  });
}
