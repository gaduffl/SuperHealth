import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/sync/snapshot_service.dart';

void main() {
  test('document snapshots exclude and preserve device-local paths', () async {
    sqfliteFfiInit();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final profile = await repository.createProfile(displayName: 'Me');
    final createdAt = DateTime.utc(2026, 1, 1);
    await repository.saveDocumentBundle(
      document: HealthDocument(
        id: 'document-1',
        profileId: profile.id,
        fileName: 'lab.pdf',
        sha256: 'abc123',
        localPath: '/device/one/lab.pdf',
        oneDriveItemId: 'remote-item-1',
        labName: 'Local lab',
        createdAt: createdAt,
        updatedAt: createdAt,
      ),
      newBiomarkers: const [],
      measurements: const [],
    );

    final snapshot = await repository.fullSyncSnapshot();
    final tables = snapshot['tables']! as Map<String, Object?>;
    final snapshotDocuments =
        tables['documents']! as List<Map<String, Object?>>;
    final snapshotDocument = snapshotDocuments.single;
    expect(snapshotDocument.containsKey('local_path'), isFalse);
    expect(snapshotDocument['one_drive_item_id'], 'remote-item-1');

    final remote = jsonDecode(jsonEncode(snapshot)) as Map<String, dynamic>;
    final remoteDocument =
        ((remote['tables'] as Map<String, dynamic>)['documents'] as List).single
            as Map<String, dynamic>;
    remoteDocument['lab_name'] = 'Remote lab';
    remoteDocument['updated_at'] = DateTime.utc(2026, 1, 2).toIso8601String();

    final snapshotService = SnapshotService(database, repository);
    await snapshotService.merge(Map<String, Object?>.from(remote));

    final merged = (await repository.documents(profile.id)).single;
    expect(merged.labName, 'Remote lab');
    expect(merged.localPath, '/device/one/lab.pdf');
    expect(merged.oneDriveItemId, 'remote-item-1');

    await database.close();
  });

  test(
    'rejects a snapshot that tries to supply a device-local document path',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(database.close);
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Me');
      final createdAt = DateTime.utc(2026, 1, 1);
      await repository.saveDocumentBundle(
        document: HealthDocument(
          id: 'document-1',
          profileId: profile.id,
          fileName: 'lab.pdf',
          localPath: '/device/one/lab.pdf',
          createdAt: createdAt,
          updatedAt: createdAt,
        ),
        newBiomarkers: const [],
        measurements: const [],
      );
      final remote =
          jsonDecode(jsonEncode(await repository.fullSyncSnapshot()))
              as Map<String, dynamic>;
      final document =
          ((remote['tables'] as Map<String, dynamic>)['documents'] as List)
                  .single
              as Map<String, dynamic>;
      document['local_path'] = '/attacker/path.pdf';

      await expectLater(
        SnapshotService(
          database,
          repository,
        ).merge(Map<String, Object?>.from(remote)),
        throwsA(isA<FormatException>()),
      );
      expect(
        (await repository.documents(profile.id)).single.localPath,
        '/device/one/lab.pdf',
      );
    },
  );
}
