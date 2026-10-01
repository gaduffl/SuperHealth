import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

import 'legacy_schema.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v15 gives plans a coverage column and leaves existing plans as never '
      'checked, not as checked and empty', () async {
    final directory = await Directory.systemTemp.createTemp('coverage-v14-');
    final databasePath = '${directory.path}/super_health_v1.db';
    const stamp = '2026-01-01T00:00:00.000Z';
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 14,
        onCreate: (db, _) async {
          await db.execute(legacyBiomarkersTable);
          await db.execute(
            'ALTER TABLE biomarkers '
            'ADD COLUMN is_calculated INTEGER NOT NULL DEFAULT 0',
          );
          await db.execute(
            'ALTER TABLE biomarkers ADD COLUMN calculation_formula TEXT',
          );
          await db.execute(legacyBiomarkerListsTable);
          await db.execute(
            'ALTER TABLE biomarker_lists ADD COLUMN due_interval_days INTEGER',
          );
          await db.execute(legacyBiomarkerListItemsTable);
          await db.execute(legacyLabPlansV12Table);
          await db.insert('lab_plans', {
            'id': 'old-plan',
            'profile_id': 'profile',
            'title': 'Before coverage',
            'created_at': stamp,
            'updated_at': stamp,
            'context_hash': 'hash',
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
    final db = await database.database;

    final columns = await db.rawQuery('PRAGMA table_info(lab_plans)');
    final coverage = columns.singleWhere(
      (column) => column['name'] == 'coverage_json',
    );
    expect(coverage['notnull'], 0);
    final row = (await db.query('lab_plans')).single;
    expect(row['coverage_json'], isNull);
    expect(LabPlan.fromMap(row, const []).coverage, isNull);
  });

  test(
    'a fresh install has the same coverage column as an upgraded one',
    () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final db = await database.database;

      final columns = await db.rawQuery('PRAGMA table_info(lab_plans)');
      final coverage = columns.singleWhere(
        (column) => column['name'] == 'coverage_json',
      );
      expect(coverage['type'], 'TEXT');
      expect(coverage['notnull'], 0);
      expect(AppDatabase.schemaVersion, 15);
    },
  );

  test(
    'a synchronized plan row must carry coverage as a list of objects',
    () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Alex');
      final now = DateTime(2026, 1, 1);
      await repository.saveLabPlan(
        LabPlan(
          id: 'plan',
          profileId: profile.id,
          title: 'Plan',
          createdAt: now,
          updatedAt: now,
          items: const [],
          coverage: const [
            PlanCoverage(
              id: 'exp:biotin',
              kind: 'substance',
              label: 'Biotin',
              verdict: PlanCoverageVerdict.notNeeded,
              why: 'Pausiert.',
            ),
          ],
        ),
      );
      final tables = (await repository.fullSyncSnapshot())['tables']! as Map;
      final snapshot = {
        for (final entry in tables.entries)
          '${entry.key}': [
            for (final row in entry.value as List)
              Map<String, Object?>.from(row as Map),
          ],
      };

      // The plan as stored is valid.
      await repository.validateSynchronizedRows(
        snapshot,
        portableBackup: false,
      );

      // A remote row whose coverage is a list of strings is not.
      final tampered = {
        for (final entry in snapshot.entries)
          entry.key: entry.key == 'lab_plans'
              ? [
                  for (final row in entry.value)
                    {...row, 'coverage_json': '["exp:biotin"]'},
                ]
              : entry.value,
      };
      await expectLater(
        repository.validateSynchronizedRows(tampered, portableBackup: false),
        throwsA(isA<FormatException>()),
      );
    },
  );
}
