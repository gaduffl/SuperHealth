import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/sync/snapshot_service.dart';

void main() {
  late AppDatabase database;
  late HealthRepository repository;
  late SnapshotService snapshots;

  setUp(() {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = HealthRepository(database);
    snapshots = SnapshotService(database, repository);
  });

  tearDown(() => database.close());

  test(
    'keeps divergent rows unresolved without advancing their shadow',
    () async {
      final conflict = await _createProfileConflict(
        repository: repository,
        snapshots: snapshots,
      );

      expect(conflict.localSummary, contains('Local version'));
      expect(conflict.localSummary, isNot(contains('do-not-display')));
      expect(conflict.incomingSummary, contains('Incoming version'));
      expect(await snapshots.unresolvedConflicts(), hasLength(1));

      final db = await database.database;
      final profile = await db.query(
        'profiles',
        where: 'id = ?',
        whereArgs: ['profile-1'],
      );
      expect(profile.single['display_name'], 'Local version');
      final shadow = await db.query(
        'sync_shadow',
        where: 'table_name = ? AND row_id = ?',
        whereArgs: ['profiles', 'profile-1'],
      );
      expect(shadow.single['updated_at'], _time(1));
    },
  );

  test(
    'keep local resolves transactionally and retains remote shadow baseline',
    () async {
      final conflict = await _createProfileConflict(
        repository: repository,
        snapshots: snapshots,
      );

      await snapshots.resolveConflict(
        conflictId: conflict.id,
        resolution: SyncConflictResolution.keepLocal,
      );

      final db = await database.database;
      final profile = await db.query(
        'profiles',
        where: 'id = ?',
        whereArgs: ['profile-1'],
      );
      expect(profile.single['display_name'], 'Local version');
      final shadow = await db.query(
        'sync_shadow',
        where: 'table_name = ? AND row_id = ?',
        whereArgs: ['profiles', 'profile-1'],
      );
      expect(shadow.single['updated_at'], _time(3));
      final conflictRow = await db.query(
        'sync_conflicts',
        where: 'id = ?',
        whereArgs: [conflict.id],
      );
      expect(conflictRow.single['resolution'], 'keep_local');
      expect(conflictRow.single['resolved_at'], isNotNull);
      expect(await snapshots.unresolvedConflicts(), isEmpty);
    },
  );

  test(
    'accept incoming applies a deletion tombstone and records resolution',
    () async {
      final conflict = await _createProfileConflict(
        repository: repository,
        snapshots: snapshots,
        incomingDeleted: true,
      );

      await snapshots.resolveConflict(
        conflictId: conflict.id,
        resolution: SyncConflictResolution.acceptIncoming,
      );

      final db = await database.database;
      final profile = await db.query(
        'profiles',
        where: 'id = ?',
        whereArgs: ['profile-1'],
      );
      expect(profile.single['deleted'], 1);
      final conflictRow = await db.query(
        'sync_conflicts',
        where: 'id = ?',
        whereArgs: [conflict.id],
      );
      expect(conflictRow.single['resolution'], 'accept_incoming');
      expect(await snapshots.unresolvedConflicts(), isEmpty);
    },
  );
}

Future<SnapshotConflict> _createProfileConflict({
  required HealthRepository repository,
  required SnapshotService snapshots,
  bool incomingDeleted = false,
}) async {
  await repository.saveProfile(
    Profile(
      id: 'profile-1',
      displayName: 'Original',
      notes: 'do-not-display',
      createdAt: DateTime.parse(_time(1)),
      updatedAt: DateTime.parse(_time(1)),
    ),
  );
  await snapshots.markCurrentAsSynchronized();
  await repository.saveProfile(
    Profile(
      id: 'profile-1',
      displayName: 'Local version',
      notes: 'do-not-display',
      createdAt: DateTime.parse(_time(1)),
      updatedAt: DateTime.parse(_time(2)),
    ),
  );

  final remote =
      jsonDecode(jsonEncode(await repository.fullSyncSnapshot()))
          as Map<String, dynamic>;
  final remoteProfile =
      ((remote['tables'] as Map<String, dynamic>)['profiles'] as List).single
          as Map<String, dynamic>;
  remoteProfile['display_name'] = 'Incoming version';
  remoteProfile['updated_at'] = _time(3);
  remoteProfile['deleted'] = incomingDeleted ? 1 : 0;

  final merge = await snapshots.merge(Map<String, Object?>.from(remote));
  expect(merge.conflicts, 1);
  return (await snapshots.unresolvedConflicts()).single;
}

String _time(int day) => DateTime.utc(2026, 1, day).toIso8601String();
