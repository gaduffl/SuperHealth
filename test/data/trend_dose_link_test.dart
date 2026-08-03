import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('a dose underlay round-trips and is scoped to its profile', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final mine = await repository.createProfile(displayName: 'Mine');
    final other = await repository.createProfile(displayName: 'Other');
    final now = DateTime(2026, 8, 3);
    final biomarker = Biomarker(
      id: 'vitamin-d',
      canonicalName: 'vitamin d',
      displayName: 'Vitamin D (25-OH)',
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveBiomarker(biomarker);

    await repository.saveTrendDoseLink(
      TrendDoseLink(
        id: repository.newId(),
        profileId: mine.id,
        biomarkerId: biomarker.id,
        ingredientName: 'Vitamin D3',
        ingredientUnit: 'IU',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final restored = (await repository.trendDoseLinks(mine.id)).single;
    expect(restored.biomarkerId, biomarker.id);
    expect(restored.definitionId, isNull);
    expect(restored.ingredientName, 'Vitamin D3');
    expect(restored.ingredientUnit, 'IU');
    // The exposure key has to match how ingredient totals are aggregated, or
    // a saved link silently resolves to no dose series.
    expect(restored.exposureKey, 'vitamin d3|iu');
    expect(await repository.trendDoseLinks(other.id), isEmpty);

    await database.close();
  });

  test('a dose underlay belongs to exactly one trend', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final profile = await repository.createProfile(displayName: 'Guard');
    final now = DateTime(2026, 8, 3);

    TrendDoseLink link({String? biomarkerId, String? definitionId}) =>
        TrendDoseLink(
          id: repository.newId(),
          profileId: profile.id,
          biomarkerId: biomarkerId,
          definitionId: definitionId,
          ingredientName: 'Magnesium',
          ingredientUnit: 'mg',
          createdAt: now,
          updatedAt: now,
        );

    await expectLater(
      repository.saveTrendDoseLink(link()),
      throwsA(isA<FormatException>()),
    );
    await expectLater(
      repository.saveTrendDoseLink(
        link(biomarkerId: 'a-biomarker', definitionId: 'a-definition'),
      ),
      throwsA(isA<FormatException>()),
    );

    await database.close();
  });

  test('v6 database upgrades by adding the dose underlay table', () async {
    final directory = await Directory.systemTemp.createTemp('dose-link-v6-');
    final databasePath = '${directory.path}/super_health_v1.db';

    // Build a v6 database through the real schema, then re-open it through the
    // current AppDatabase so the upgrade path is what actually runs.
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 6,
        onConfigure: (db) async => db.execute('PRAGMA foreign_keys = ON'),
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE profiles (
              id TEXT PRIMARY KEY,
              display_name TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.insert('profiles', {
            'id': 'profile',
            'display_name': 'Legacy',
            'created_at': '2026-01-01T00:00:00.000Z',
            'updated_at': '2026-01-01T00:00:00.000Z',
            'deleted': 0,
          });
        },
      ),
    );
    await legacy.close();

    final upgraded = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final db = await upgraded.database;
    final columns = await db.rawQuery('PRAGMA table_info(trend_dose_links)');
    expect(columns.map((column) => column['name']), <String>[
      'id',
      'profile_id',
      'biomarker_id',
      'definition_id',
      'supplement_id',
      'ingredient_name',
      'ingredient_unit',
      'created_at',
      'updated_at',
      'deleted',
    ]);
    // Nothing to back-fill: no underlay exists until the user confirms one.
    expect(await db.query('trend_dose_links'), isEmpty);

    await upgraded.close();
    await directory.delete(recursive: true);
  });
}
