import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'profile height round-trips through the repository and health context',
    () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(
        displayName: 'Height test',
        heightCm: 174.5,
      );

      final restored = (await repository.profiles()).single;
      expect(restored.heightCm, 174.5);
      final snapshot = await repository.completeProfileSnapshot(profile.id);
      final data = snapshot['data']! as Map<String, Object?>;
      final profileRow = data['profile']! as Map<String, Object?>;
      expect(profileRow['height_cm'], 174.5);

      await repository.saveProfile(
        Profile(
          id: restored.id,
          displayName: restored.displayName,
          heightCm: 180,
          createdAt: restored.createdAt,
          updatedAt: DateTime.now(),
        ),
      );
      expect((await repository.profiles()).single.heightCm, 180);
      await database.close();
    },
  );

  test('v3 database upgrades by adding nullable profile height', () async {
    final directory = await Directory.systemTemp.createTemp('height-v3-');
    final databasePath = '${directory.path}/super_health_v1.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 3,
        onCreate: (db, _) async {
          await db.execute('''
            CREATE TABLE profiles (
              id TEXT PRIMARY KEY,
              display_name TEXT NOT NULL,
              date_of_birth TEXT,
              sex TEXT,
              weight_kg REAL,
              notes TEXT NOT NULL DEFAULT '',
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              deleted INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await db.execute('''
            CREATE TABLE lab_plans (
              id TEXT PRIMARY KEY,
              profile_id TEXT NOT NULL REFERENCES profiles(id),
              title TEXT NOT NULL,
              created_at TEXT NOT NULL,
              updated_at TEXT NOT NULL,
              planned_for TEXT,
              currency TEXT NOT NULL DEFAULT 'EUR',
              context_hash TEXT NOT NULL,
              provider TEXT,
              model TEXT,
              status TEXT NOT NULL DEFAULT 'draft',
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
        },
      ),
    );
    await legacy.close();

    final upgraded = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: databasePath,
    );
    final db = await upgraded.database;
    final columns = await db.rawQuery('PRAGMA table_info(profiles)');
    expect(columns.map((column) => column['name']), contains('height_cm'));
    expect((await db.query('profiles')).single['height_cm'], isNull);

    await upgraded.close();
    await directory.delete(recursive: true);
  });
}
