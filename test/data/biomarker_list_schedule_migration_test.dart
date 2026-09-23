import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';

import 'legacy_schema.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'v13 lists take the interval their items share, and gaps follow it',
    () async {
      final directory = await Directory.systemTemp.createTemp('lists-v13-');
      final databasePath = '${directory.path}/super_health_v1.db';
      const stamp = '2026-01-01T00:00:00.000Z';
      Map<String, Object?> item(
        String id,
        String listId,
        int? interval, {
        int deleted = 0,
      }) => {
        'id': id,
        'list_id': listId,
        'biomarker_id': id,
        'due_interval_days': interval,
        'created_at': stamp,
        'updated_at': stamp,
        'deleted': deleted,
      };
      final legacy = await databaseFactoryFfi.openDatabase(
        databasePath,
        options: OpenDatabaseOptions(
          version: 13,
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
            await db.execute(legacyBiomarkerListItemsTable);
            for (final id in ['annual', 'tie', 'checklist']) {
              await db.insert('biomarker_lists', {
                'id': id,
                'profile_id': 'profile',
                'name': id,
                'created_at': stamp,
                'updated_at': stamp,
              });
            }
            for (final row in [
              item('ferritin', 'annual', 365),
              item('tsh', 'annual', 365),
              item('hba1c', 'annual', 90),
              // Added from a package: no interval, so it was never due.
              item('psa', 'annual', null),
              // A deleted row does not get a vote.
              item('b12', 'annual', 90, deleted: 1),
              item('vitd', 'tie', 180),
              item('crp', 'tie', 90),
              item('lipase', 'checklist', null),
            ]) {
              await db.insert('biomarker_list_items', row);
            }
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
      Future<Object?> listInterval(String id) async => (await db.query(
        'biomarker_lists',
        where: 'id = ?',
        whereArgs: [id],
      )).single['due_interval_days'];
      Future<Object?> itemInterval(String id) async => (await db.query(
        'biomarker_list_items',
        where: 'id = ?',
        whereArgs: [id],
      )).single['due_interval_days'];

      expect(await listInterval('annual'), 365);
      // Copies of the list schedule are cleared so they follow it from now on.
      expect(await itemInterval('ferritin'), isNull);
      expect(await itemInterval('tsh'), isNull);
      expect(await itemInterval('psa'), isNull);
      // A genuinely different interval stays the item's own.
      expect(await itemInterval('hba1c'), 90);
      expect(await itemInterval('b12'), 90);
      // A tie takes the shorter, more cautious interval.
      expect(await listInterval('tie'), 90);
      expect(await itemInterval('vitd'), 180);
      expect(await itemInterval('crp'), isNull);
      // Nothing to infer from: the list stays a plain checklist.
      expect(await listInterval('checklist'), isNull);
    },
  );
}
