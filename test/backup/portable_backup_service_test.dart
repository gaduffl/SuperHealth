import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/backup/portable_backup_service.dart';
import 'package:super_health/data/app_database.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'round trips sanitized rows, verified PDFs, and clears sync state',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final source = await fixture.service.createJson();
      final bundle = _bundle(source);
      expect(source, isNot(contains('${fixture.directory.path}/source.pdf')));
      expect(source, isNot(contains('remote-item-that-must-not-backup')));
      final documentRow = _rows(bundle, 'documents').single;
      expect(documentRow.containsKey('local_path'), isFalse);
      expect(documentRow.containsKey('one_drive_item_id'), isFalse);

      await fixture.db.update(
        'profiles',
        {'display_name': 'Changed locally'},
        where: 'id = ?',
        whereArgs: ['profile-1'],
      );
      await fixture.service.restoreJson(
        source,
        confirmedReplaceCurrentData: true,
      );

      expect(
        (await fixture.db.query('profiles')).single['display_name'],
        'Alice',
      );
      final restored = (await fixture.db.query('documents')).single;
      final restoredPath = restored['local_path'] as String;
      expect(restoredPath, contains('backup-restored'));
      expect(await File(restoredPath).readAsBytes(), fixture.pdfBytes);
      expect(await fixture.db.query('sync_shadow'), isEmpty);
      expect(await fixture.db.query('sync_conflicts'), isEmpty);
      expect(await fixture.db.query('import_audit'), isEmpty);
      expect(await fixture.db.query('import_runs'), isEmpty);
    },
  );

  test('rejects replacement without explicit confirmation', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final source = await fixture.service.createJson();

    await expectLater(
      fixture.service.restoreJson(source, confirmedReplaceCurrentData: false),
      throwsA(isA<StateError>()),
    );
    expect(
      (await fixture.db.query('profiles')).single['display_name'],
      'Alice',
    );
  });

  test('rejects a wrong table checksum before replacing rows', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final bundle = _bundle(await fixture.service.createJson());
    (_object(_object(bundle['manifest'])['tables'])['profiles']
        as Map)['sha256'] = List<String>.filled(
      64,
      '0',
    ).join();
    _refreshCoreChecksum(bundle);

    await expectLater(
      fixture.service.restoreJson(
        jsonEncode(bundle),
        confirmedReplaceCurrentData: true,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      (await fixture.db.query('profiles')).single['display_name'],
      'Alice',
    );
  });

  test('rejects duplicate row ids before replacing rows', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final bundle = _bundle(await fixture.service.createJson());
    _rows(
      bundle,
      'profiles',
    ).add(Map<String, Object?>.from(_rows(bundle, 'profiles').single));
    _refreshCoreChecksum(bundle);

    await expectLater(
      fixture.service.restoreJson(
        jsonEncode(bundle),
        confirmedReplaceCurrentData: true,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      (await fixture.db.query('profiles')).single['display_name'],
      'Alice',
    );
  });

  test('rejects missing tables before replacing the current ledger', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final bundle = _bundle(await fixture.service.createJson());
    (bundle['tables'] as Map).remove('profiles');
    _refreshCoreChecksum(bundle);

    await expectLater(
      fixture.service.restoreJson(
        jsonEncode(bundle),
        confirmedReplaceCurrentData: true,
      ),
      throwsA(isA<FormatException>()),
    );
    expect(
      (await fixture.db.query('profiles')).single['display_name'],
      'Alice',
    );
  });

  test(
    'rejects semantic-invalid rows and document local paths before restore',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final invalidTimestamp = _bundle(await fixture.service.createJson());
      _rows(invalidTimestamp, 'profiles').single['updated_at'] = 'not-a-time';
      _refreshTableManifest(invalidTimestamp, 'profiles');
      _refreshCoreChecksum(invalidTimestamp);
      await expectLater(
        fixture.service.restoreJson(
          jsonEncode(invalidTimestamp),
          confirmedReplaceCurrentData: true,
        ),
        throwsA(isA<FormatException>()),
      );

      final invalidDomain = _bundle(await fixture.service.createJson());
      _rows(invalidDomain, 'profiles').single['height_cm'] = 301.0;
      _refreshTableManifest(invalidDomain, 'profiles');
      _refreshCoreChecksum(invalidDomain);
      await expectLater(
        fixture.service.restoreJson(
          jsonEncode(invalidDomain),
          confirmedReplaceCurrentData: true,
        ),
        throwsA(isA<FormatException>()),
      );

      final illegalDocumentPath = _bundle(await fixture.service.createJson());
      _rows(illegalDocumentPath, 'documents').single['local_path'] =
          '/another-device/lab.pdf';
      _refreshTableManifest(illegalDocumentPath, 'documents');
      _refreshCoreChecksum(illegalDocumentPath);
      await expectLater(
        fixture.service.restoreJson(
          jsonEncode(illegalDocumentPath),
          confirmedReplaceCurrentData: true,
        ),
        throwsA(isA<FormatException>()),
      );

      expect(
        (await fixture.db.query('profiles')).single['display_name'],
        'Alice',
      );
    },
  );

  test(
    'rejects unknown columns and broken references before restore',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final unexpectedColumn = _bundle(await fixture.service.createJson());
      _rows(unexpectedColumn, 'profiles').single['unexpected'] = 'nope';
      _refreshTableManifest(unexpectedColumn, 'profiles');
      _refreshCoreChecksum(unexpectedColumn);
      await expectLater(
        fixture.service.restoreJson(
          jsonEncode(unexpectedColumn),
          confirmedReplaceCurrentData: true,
        ),
        throwsA(isA<FormatException>()),
      );

      final brokenReference = _bundle(await fixture.service.createJson());
      _rows(brokenReference, 'documents').single['profile_id'] = 'missing';
      _refreshTableManifest(brokenReference, 'documents');
      _refreshCoreChecksum(brokenReference);
      await expectLater(
        fixture.service.restoreJson(
          jsonEncode(brokenReference),
          confirmedReplaceCurrentData: true,
        ),
        throwsA(isA<FormatException>()),
      );
      expect(
        (await fixture.db.query('profiles')).single['display_name'],
        'Alice',
      );
    },
  );

  test('rejects a bundle whose declared PDF payload is missing', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final bundle = _bundle(await fixture.service.createJson())
      ..['documents'] = [];
    _refreshCoreChecksum(bundle);

    await expectLater(
      fixture.service.restoreJson(
        jsonEncode(bundle),
        confirmedReplaceCurrentData: true,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a changed document manifest after core verification', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final bundle = _bundle(await fixture.service.createJson());
    final documentManifest = _object(bundle['manifest'])['documents'] as Map;
    documentManifest['sha256'] = List<String>.filled(64, '0').join();
    _refreshCoreChecksum(bundle);

    await expectLater(
      fixture.service.restoreJson(
        jsonEncode(bundle),
        confirmedReplaceCurrentData: true,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rolls back all row replacement when a database insert fails', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final bundle = _bundle(await fixture.service.createJson());
    await fixture.db.update(
      'profiles',
      {'display_name': 'Current local profile'},
      where: 'id = ?',
      whereArgs: ['profile-1'],
    );
    final biomarkers = _rows(bundle, 'biomarkers');
    biomarkers.addAll([_biomarker('bio-1'), _biomarker('bio-2')]);
    biomarkers.sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final manifest = _object(bundle['manifest'])['tables'] as Map;
    manifest['biomarkers'] = {
      'count': biomarkers.length,
      'sha256': _sha256(_stableJson(biomarkers)),
    };
    _refreshCoreChecksum(bundle);

    await expectLater(
      fixture.service.restoreJson(
        jsonEncode(bundle),
        confirmedReplaceCurrentData: true,
      ),
      throwsA(isA<DatabaseException>()),
    );
    expect(
      (await fixture.db.query('profiles')).single['display_name'],
      'Current local profile',
    );
  });

  test('rejects metadata tampering through the core checksum', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final bundle = _bundle(await fixture.service.createJson())
      ..['generated_at'] = '2026-07-18T13:00:00.000Z';

    await expectLater(
      fixture.service.restoreJson(
        jsonEncode(bundle),
        confirmedReplaceCurrentData: true,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('rejects a timestamp without UTC or numeric offset', () async {
    final fixture = await _Fixture.create();
    addTearDown(fixture.dispose);
    final bundle = _bundle(await fixture.service.createJson())
      ..['generated_at'] = '2026-07-18T12:00:00';
    _refreshCoreChecksum(bundle);

    await expectLater(
      fixture.service.restoreJson(
        jsonEncode(bundle),
        confirmedReplaceCurrentData: true,
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test(
    'restores an unavailable-at-export document with no local path',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      await File('${fixture.directory.path}/source.pdf').delete();
      final source = await fixture.service.createJson();
      final bundle = _bundle(source);
      expect(bundle['documents'], isEmpty);

      await fixture.service.restoreJson(
        source,
        confirmedReplaceCurrentData: true,
      );

      expect(
        (await fixture.db.query('documents')).single['local_path'],
        isNull,
      );
    },
  );
}

class _Fixture {
  _Fixture(this.directory, this.database, this.db, this.service, this.pdfBytes);

  final Directory directory;
  final AppDatabase database;
  final Database db;
  final PortableBackupService service;
  final List<int> pdfBytes;

  static Future<_Fixture> create() async {
    final directory = await Directory.systemTemp.createTemp(
      'portable-backup-test-',
    );
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final db = await database.database;
    const now = '2026-07-18T12:00:00.000Z';
    final pdfBytes = utf8.encode('%PDF-test-content');
    final sourcePdf = File('${directory.path}/source.pdf');
    await sourcePdf.writeAsBytes(pdfBytes);
    final digest = sha256.convert(pdfBytes).toString();
    await db.insert('profiles', {
      'id': 'profile-1',
      'display_name': 'Alice',
      'date_of_birth': null,
      'sex': null,
      'height_cm': null,
      'weight_kg': null,
      'notes': '',
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    });
    await db.insert('documents', {
      'id': 'document-1',
      'profile_id': 'profile-1',
      'file_name': 'lab.pdf',
      'mime_type': 'application/pdf',
      'sha256': digest,
      'local_path': sourcePdf.path,
      'one_drive_item_id': 'remote-item-that-must-not-backup',
      'document_date': null,
      'parsed_at': null,
      'parser_provider': null,
      'parser_model': null,
      'lab_name': null,
      'report_comment': '',
      'parse_status': 'saved',
      'warnings_json': '[]',
      'errors_json': '[]',
      'created_at': now,
      'updated_at': now,
      'deleted': 0,
    });
    await db.insert('sync_shadow', {
      'table_name': 'profiles',
      'row_id': 'profile-1',
      'updated_at': now,
    });
    await db.insert('sync_conflicts', {
      'table_name': 'profiles',
      'row_id': 'profile-1',
      'conflict_type': 'test',
      'detected_at': now,
    });
    await db.insert('import_runs', {
      'id': 'import-1',
      'source_type': 'legacy_json',
      'source_hash': 'source-hash-1',
      'profile_id': 'profile-1',
      'preview_json': '{}',
      'imported_at': now,
      'rolled_back_at': null,
    });
    await db.insert('import_audit', {
      'import_id': 'import-1',
      'sequence': 1,
      'table_name': 'profiles',
      'row_id': 'profile-1',
      'action': 'insert',
      'before_json': null,
    });
    return _Fixture(
      directory,
      database,
      db,
      PortableBackupService(
        database,
        documentsDirectory: () async => directory,
      ),
      pdfBytes,
    );
  }

  Future<void> dispose() async {
    await db.close();
    if (await directory.exists()) await directory.delete(recursive: true);
  }
}

Map<String, Object?> _bundle(String source) => _object(jsonDecode(source));

Map<String, Object?> _object(Object? value) =>
    Map<String, Object?>.from(value as Map);

List<Map<String, Object?>> _rows(Map<String, Object?> bundle, String table) =>
    (_object(bundle['tables'])[table] as List).cast<Map<String, Object?>>();

Map<String, Object?> _biomarker(String id) => {
  'id': id,
  'canonical_name': 'same-canonical-name',
  'display_name': 'Same canonical name',
  'category': '',
  'default_unit': '',
  'price_eur': null,
  'lab_name': null,
  'price_checked_at': null,
  'description': '',
  'synonyms_json': '[]',
  'is_temporary': 0,
  'created_at': '2026-07-18T12:00:00.000Z',
  'updated_at': '2026-07-18T12:00:00.000Z',
  'deleted': 0,
};

String _sha256(String value) => sha256.convert(utf8.encode(value)).toString();

void _refreshTableManifest(Map<String, Object?> bundle, String table) {
  final rows = _rows(bundle, table)
    ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
  final manifests = _object(bundle['manifest'])['tables'] as Map;
  manifests[table] = {
    'count': rows.length,
    'sha256': _sha256(_stableJson(rows)),
  };
}

void _refreshCoreChecksum(Map<String, Object?> bundle) {
  final manifest = bundle['manifest'] as Map;
  manifest['core_sha256'] = _coreChecksum(bundle);
}

String _coreChecksum(Map<String, Object?> bundle) {
  final copy = Map<String, Object?>.from(_canonical(bundle) as Map);
  final manifest = Map<String, Object?>.from(copy['manifest'] as Map)
    ..remove('core_sha256');
  copy['manifest'] = manifest;
  return _sha256(_stableJson(copy));
}

String _stableJson(Object? value) => jsonEncode(_canonical(value));

Object? _canonical(Object? value) {
  if (value is Map) {
    final entries =
        value.entries
            .map((entry) => MapEntry('${entry.key}', _canonical(entry.value)))
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    return Map<String, Object?>.fromEntries(entries);
  }
  if (value is Iterable) return [for (final item in value) _canonical(item)];
  return value;
}
