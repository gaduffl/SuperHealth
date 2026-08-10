import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/domain/entities.dart';
import 'legacy_schema.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'v5 database backfills value_mode from prior score/unit semantics',
    () async {
      final directory = await Directory.systemTemp.createTemp('tag-mode-v5-');
      final databasePath = '${directory.path}/super_health_v1.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 5,
          onCreate: (db, _) async {
            // Present in a real database at this version; the v12 upgrade
            // adds a column to it.
            await db.execute(legacyLabPlansTable);
            await db.execute('''
              CREATE TABLE profiles (
                id TEXT PRIMARY KEY,
                display_name TEXT NOT NULL,
                date_of_birth TEXT,
                sex TEXT,
                weight_kg REAL,
                height_cm REAL,
                notes TEXT NOT NULL DEFAULT '',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE supplements (
                id TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                form TEXT NOT NULL DEFAULT '',
                stock_unit TEXT NOT NULL DEFAULT 'unit',
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.execute('''
              CREATE TABLE health_event_definitions (
                id TEXT PRIMARY KEY,
                profile_id TEXT NOT NULL REFERENCES profiles(id),
                kind TEXT NOT NULL CHECK(kind IN ('symptom', 'tag')),
                name TEXT NOT NULL,
                default_unit TEXT,
                use_score INTEGER NOT NULL DEFAULT 0,
                color_value INTEGER,
                archived INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL,
                updated_at TEXT NOT NULL,
                deleted INTEGER NOT NULL DEFAULT 0
              )
            ''');
            await db.insert('profiles', {
              'id': 'profile',
              'display_name': 'Legacy',
              'notes': '',
              'created_at': '2026-01-01T00:00:00.000Z',
              'updated_at': '2026-01-01T00:00:00.000Z',
              'deleted': 0,
            });
            // A scored symptom (e.g. Headache 0-10) must become intensity.
            await db.insert('health_event_definitions', {
              'id': 'scored',
              'profile_id': 'profile',
              'kind': 'symptom',
              'name': 'Headache',
              'use_score': 1,
              'created_at': '2026-01-01T00:00:00.000Z',
              'updated_at': '2026-01-01T00:00:00.000Z',
              'deleted': 0,
            });
            // A unit-bearing tag with free-text amounts (e.g. Caffeine in
            // mg) must become amount, keeping its stored unit as canonical.
            await db.insert('health_event_definitions', {
              'id': 'unit',
              'profile_id': 'profile',
              'kind': 'tag',
              'name': 'Caffeine',
              'default_unit': 'mg',
              'use_score': 0,
              'created_at': '2026-01-01T00:00:00.000Z',
              'updated_at': '2026-01-01T00:00:00.000Z',
              'deleted': 0,
            });
            // A plain unscored, unitless tag (e.g. a walk) must default to
            // occurrence.
            await db.insert('health_event_definitions', {
              'id': 'plain',
              'profile_id': 'profile',
              'kind': 'tag',
              'name': 'Walk',
              'use_score': 0,
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
      final rows = await db.query('health_event_definitions', orderBy: 'id');
      final byId = {for (final row in rows) row['id']: row};

      expect(byId['scored']!['value_mode'], TagValueMode.intensity.name);
      expect(byId['unit']!['value_mode'], TagValueMode.amount.name);
      expect(byId['plain']!['value_mode'], TagValueMode.occurrence.name);
      expect(byId['plain']!['portion_amount'], isNull);
      expect(byId['plain']!['portion_label'], isNull);
      expect(byId['plain']!['include_in_check_in'], 0);

      await upgraded.close();
      await directory.delete(recursive: true);
    },
  );
}
