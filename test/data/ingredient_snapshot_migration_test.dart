import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/domain/entities.dart';
import 'legacy_schema.dart';

void main() {
  setUpAll(sqfliteFfiInit);
  test(
    'v17 preserves the distinction between old missing and recorded recipes',
    () async {
      final directory = await Directory.systemTemp.createTemp('recipe-v16-');
      final path = '${directory.path}/test.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        path,
        options: OpenDatabaseOptions(
          version: 16,
          onCreate: (db, _) async {
            await db.execute(legacySupplementIntakesTable);
            for (final recipe in [
              '[]',
              '[ ]',
              '[{"name":"B12","amount":1001,"unit":"µg"}]',
            ]) {
              await db.insert('supplement_intakes', {
                'id': recipe,
                'profile_id': 'p',
                'supplement_id': 's',
                'dose': 1,
                'unit': 'capsule',
                'ingredients_json': recipe,
                'taken_at': '2026-05-01T00:00:00.000Z',
                'created_at': '2026-05-01T00:00:00.000Z',
                'updated_at': '2026-05-01T00:00:00.000Z',
              });
            }
          },
        ),
      );
      final before = await legacy.query('supplement_intakes');
      await legacy.close();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: path,
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      final db = await database.database;
      final after = await db.query('supplement_intakes');
      for (var i = 0; i < before.length; i++) {
        final row = Map<String, Object?>.from(after[i]);
        expect(row.remove('ingredient_snapshot_recorded'), i == 2 ? 1 : 0);
        expect(row, before[i]);
        expect(
          SupplementIntake.fromMap(after[i]).hasIngredientSnapshot,
          i == 2,
        );
      }
      final fresh = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(fresh.close);
      final column = (await db.rawQuery(
        'PRAGMA table_info(supplement_intakes)',
      )).singleWhere((row) => row['name'] == 'ingredient_snapshot_recorded');
      final freshColumn = (await (await fresh.database).rawQuery(
        'PRAGMA table_info(supplement_intakes)',
      )).singleWhere((row) => row['name'] == 'ingredient_snapshot_recorded');
      expect(column['type'], freshColumn['type']);
      expect(column['notnull'], freshColumn['notnull']);
      expect(column['dflt_value'], freshColumn['dflt_value']);
    },
  );
}
