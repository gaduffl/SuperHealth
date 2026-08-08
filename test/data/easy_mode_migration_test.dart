import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'an existing profile keeps the full app; a new one starts easy',
    () async {
      // Someone already using the whole app would experience a default-on easy
      // mode as features vanishing, so v11 back-fills existing rows to off.
      final directory = await Directory.systemTemp.createTemp('easy-v10-');
      final databasePath = '${directory.path}/super_health_v1.db';
      final legacy = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 10,
          onCreate: (db, _) async {
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
            await db.insert('profiles', {
              'id': 'existing',
              'display_name': 'Existing',
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

      final existing = (await repository.profiles()).single;
      expect(existing.id, 'existing');
      expect(existing.easyMode, isFalse);

      final created = await repository.createProfile(displayName: 'New');
      expect(created.easyMode, isTrue);
    },
  );
}
