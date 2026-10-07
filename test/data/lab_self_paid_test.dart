import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/backup/portable_backup_service.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/sync/snapshot_service.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'IGeL edits affect only selected results and preserve extraction evidence',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.database.close);
      final before = await f.rows();
      await f.mark(['a'], true);
      final marked = await f.rows();
      expect(marked['a']!.isSelfPaid, isTrue);
      expect(marked['b']!.isSelfPaid, isFalse);
      expect(marked['other']!.toMap(), before['other']!.toMap());
      final original = before['a']!.toMap()
        ..remove('updated_at')
        ..remove('flags_json');
      final current = marked['a']!.toMap()
        ..remove('updated_at')
        ..remove('flags_json');
      expect(current, original);
      expect(marked['a']!.flags, contains('low_confidence'));

      await f.mark(['a', 'b'], true);
      final all = await f.rows();
      expect(all['a']!.updatedAt, marked['a']!.updatedAt);
      expect(all['b']!.isSelfPaid, isTrue);
      await f.mark(['a', 'b'], false);
      final cleared = await f.rows();
      expect(cleared['a']!.isSelfPaid, isFalse);
      expect(cleared['a']!.flags, ['low_confidence']);
      expect(cleared['b']!.isSelfPaid, isFalse);
    },
  );

  test('a stale or foreign selection rejects the whole payment edit', () async {
    final f = await _Fixture.create();
    addTearDown(f.database.close);
    final before = await f.rows();
    for (final invalid in ['other', 'missing']) {
      await expectLater(f.mark(['a', invalid], true), throwsStateError);
      expect((await f.rows())['a']!.toMap(), before['a']!.toMap());
    }
    await f.repository.softDelete('documents', 'doc');
    await expectLater(f.mark(['a'], true), throwsStateError);
    expect((await f.rows())['a']!.toMap(), before['a']!.toMap());
  });

  test(
    'payment marks survive value edits, snapshot sync and portable restore',
    () async {
      final f = await _Fixture.create();
      addTearDown(f.database.close);
      await f.mark(['a'], true);
      final marked = (await f.rows())['a']!;
      await f.repository.saveMeasurement(
        marked.copyWith(value: 97, notes: 'Reviewed'),
      );
      final edited = (await f.rows())['a']!;
      expect(edited.isSelfPaid, isTrue);
      expect(edited.page, marked.page);
      expect(edited.rowText, marked.rowText);
      expect(Measurement.fromMap(edited.toMap()).isSelfPaid, isTrue);

      final target = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      addTearDown(target.close);
      final targetRepository = HealthRepository(target);
      await SnapshotService(
        target,
        targetRepository,
      ).merge(await f.repository.fullSyncSnapshot());
      final synced = (await targetRepository.reportedMeasurements(
        f.profile.id,
      )).singleWhere((row) => row.id == 'a');
      expect(synced.isSelfPaid, isTrue);
      expect(synced.flags, contains('low_confidence'));

      final directory = await Directory.systemTemp.createTemp('igel-backup-');
      addTearDown(() => directory.delete(recursive: true));
      final backup = PortableBackupService(
        f.database,
        documentsDirectory: () async => directory,
      );
      final source = await backup.createJson();
      await f.mark(['a'], false);
      await backup.restoreJson(source, confirmedReplaceCurrentData: true);
      expect((await f.rows())['a']!.isSelfPaid, isTrue);
      expect((await f.rows())['b']!.isSelfPaid, isFalse);
    },
  );
}

class _Fixture {
  _Fixture(this.database, this.repository, this.profile);

  final AppDatabase database;
  final HealthRepository repository;
  final Profile profile;

  static Future<_Fixture> create() async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final profile = await repository.createProfile(displayName: 'Alex');
    final now = DateTime.utc(2026, 1, 1);
    await repository.saveBiomarker(
      Biomarker(
        id: 'marker',
        canonicalName: 'fixture_marker',
        displayName: 'Marker',
        defaultUnit: 'mg/dL',
        createdAt: now,
        updatedAt: now,
      ),
    );
    for (final doc in ['doc', 'other-doc']) {
      await repository.saveDocument(
        HealthDocument(
          id: doc,
          profileId: profile.id,
          fileName: '$doc.pdf',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    for (final id in ['a', 'b', 'other']) {
      await repository.saveMeasurement(
        Measurement(
          id: id,
          profileId: profile.id,
          biomarkerId: 'marker',
          documentId: id == 'other' ? 'other-doc' : 'doc',
          takenAt: now,
          value: 95,
          unit: 'mg/dL',
          labRefLow: 70,
          labRefHigh: 99,
          page: 2,
          rowText: 'Marker 95 mg/dL',
          extractionConfidence: 0.7,
          flags: const ['low_confidence'],
          notes: 'Original note',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    return _Fixture(database, repository, profile);
  }

  Future<Map<String, Measurement>> rows() async => {
    for (final row in await repository.reportedMeasurements(profile.id))
      row.id: row,
  };

  Future<void> mark(List<String> ids, bool value) =>
      repository.setLabReportSelfPaid(
        profileId: profile.id,
        documentId: 'doc',
        measurementIds: ids,
        isSelfPaid: value,
      );
}
