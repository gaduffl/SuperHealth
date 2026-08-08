import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'a v9 database gains package tables without losing biomarkers',
    () async {
      final directory = await Directory.systemTemp.createTemp('package-v9-');
      final databasePath = '${directory.path}/super_health_v1.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 9,
          onCreate: (db, _) async {
            // Only what this migration touches. A fixture that creates every
            // table would hide an ALTER against one it forgot.
            await db.execute('''
            CREATE TABLE biomarkers (
              id TEXT PRIMARY KEY,
              canonical_name TEXT NOT NULL,
              display_name TEXT NOT NULL,
              category TEXT NOT NULL DEFAULT '',
              default_unit TEXT NOT NULL DEFAULT '',
              price_eur REAL,
              lab_name TEXT,
              price_checked_at TEXT,
              description TEXT NOT NULL DEFAULT '',
              synonyms_json TEXT NOT NULL DEFAULT '[]',
              is_temporary INTEGER NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
            // v11 alters profiles, so a fixture without it fails here while
            // working fine against a real database of this version.
            await db.execute('''
              CREATE TABLE profiles (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                date_of_birth TEXT,
                sex TEXT,
                height_cm REAL,
                weight_kg REAL,
                notes TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.insert('biomarkers', {
              'id': 'hb',
              'canonical_name': 'haemoglobin',
              'display_name': 'Haemoglobin',
              'created_at': '2026-01-01T00:00:00.000Z',
              'updated_at': '2026-01-01T00:00:00.000Z',
            });
          },
        ),
      );
      await legacy.close();

      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: databasePath,
      );
      addTearDown(() async {
        await database.close();
        await directory.delete(recursive: true);
      });
      final repository = HealthRepository(database);

      // The pre-existing row survives the upgrade.
      expect((await repository.biomarkers()).single.id, 'hb');
      // And the new tables exist and are empty rather than absent.
      expect(await repository.biomarkerPackages(), isEmpty);
      expect(await repository.biomarkerPackageMembers(), isEmpty);

      final now = DateTime(2026, 8, 8);
      await repository.saveBiomarkerPackage(
        BiomarkerPackage(
          id: 'blutbild',
          name: 'Kleines Blutbild',
          priceEur: 15,
          createdAt: now,
          updatedAt: now,
        ),
        {'hb'},
      );
      expect(
        (await repository.biomarkerPackages()).single.name,
        'Kleines Blutbild',
      );
      expect(await repository.biomarkerPackageMembers(), {
        'blutbild': {'hb'},
      });
    },
  );

  test(
    'removing a member tombstones it rather than dropping the row',
    () async {
      // A dropped row is invisible to sync, so the old membership would win on
      // the next merge and the removed test would come back.
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final repository = HealthRepository(database);
      final now = DateTime(2026, 8, 8);
      for (final id in ['hb', 'wbc']) {
        await repository.saveBiomarker(
          Biomarker(
            id: id,
            canonicalName: id,
            displayName: id,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      final package = BiomarkerPackage(
        id: 'blutbild',
        name: 'Blutbild',
        priceEur: 15,
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveBiomarkerPackage(package, {'hb', 'wbc'});
      await repository.saveBiomarkerPackage(package, {'hb'});

      expect(await repository.biomarkerPackageMembers(), {
        'blutbild': {'hb'},
      });
      final db = await database.database;
      final rows = await db.query(
        'biomarker_package_items',
        columns: ['biomarker_id', 'deleted'],
        orderBy: 'biomarker_id',
      );
      expect(rows, [
        {'biomarker_id': 'hb', 'deleted': 0},
        {'biomarker_id': 'wbc', 'deleted': 1},
      ]);

      // Re-adding it revives the tombstone rather than creating a duplicate,
      // which the unique index would refuse anyway.
      await repository.saveBiomarkerPackage(package, {'hb', 'wbc'});
      expect((await db.query('biomarker_package_items')).length, 2);
    },
  );
}
