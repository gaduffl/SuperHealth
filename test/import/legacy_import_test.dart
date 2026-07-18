import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/import/legacy_import_service.dart';

void main() {
  test(
    'Supplement Manager import previews, commits, deduplicates, and rolls back',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Me');
      final service = LegacyImportService(database, repository);
      final payload = {
        'products': [
          {
            'name': 'Magnesium',
            'brand': 'Example',
            'form': 'capsule',
            'price': 12.5,
            'ingredients': [
              {'name': 'Magnesium glycinate', 'amount': 100, 'unit': 'mg'},
            ],
          },
        ],
        'schedules': <String, Object?>{},
        'intakeHistory': <Object?>[],
        'symptomEntries': <Object?>[],
        'symptomTags': <Object?>[],
      };
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(payload)));
      final preview = await service.preview([
        ImportSourceFile(name: 'supplement_sync.json', bytes: bytes),
      ], fallbackProfile: profile);
      expect(preview.sourceKinds, contains('Supplement Manager'));
      expect(preview.counts['supplements'], 1);
      expect(preview.canImport, isTrue);

      final result = await service.commit(preview);
      expect(await repository.supplements(profile.id), hasLength(1));

      final duplicatePreview = await service.preview([
        ImportSourceFile(name: 'supplement_sync.json', bytes: bytes),
      ], fallbackProfile: profile);
      expect(duplicatePreview.alreadyImported, isTrue);
      expect(duplicatePreview.canImport, isFalse);

      await service.rollback(result.importId);
      expect(await repository.supplements(profile.id), isEmpty);
      await database.close();
    },
  );

  test('Biomarkers import preserves metadata and range semantics', () async {
    sqfliteFfiInit();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final profile = await repository.createProfile(displayName: 'Me');
    final service = LegacyImportService(database, repository);

    Uint8List jsonBytes(Object value) =>
        Uint8List.fromList(utf8.encode(jsonEncode(value)));

    final preview = await service.preview([
      ImportSourceFile(
        name: 'biomarkers.json',
        bytes: jsonBytes([
          {
            'id': 'ldl',
            'display_name': 'LDL cholesterol',
            'display_name_custom': 'LDL-C',
            'category': 'lipids',
            'unit_primary': 'mg/dL',
            'price': 4.2,
            'notes': 'Atherogenic cholesterol marker.',
            'parser_synonyms': ['LDL-Cholesterin'],
            'common_abbr': ['LDL'],
          },
        ]),
      ),
      ImportSourceFile(
        name: 'ranges.json',
        bytes: jsonBytes([
          {
            'id': 'ldl_target',
            'biomarker_id': 'ldl',
            'kind': 'longevity_target',
            'low': 0,
            'high': 80,
            'borderline_high': 100,
            'unit': 'mg/dL',
            'source': 'Imported personal catalog',
          },
        ]),
      ),
      ImportSourceFile(
        name: 'user_overrides.json',
        bytes: jsonBytes([
          {
            'id': 'ldl_override',
            'biomarker_id': 'ldl',
            'profile_id': 'old-profile',
            'low': 0,
            'high': 70,
            'borderline_high': 85,
            'notes': 'Personal LDL target.',
          },
        ]),
      ),
    ], fallbackProfile: profile);

    expect(preview.counts['biomarkers'], 1);
    expect(preview.counts['ranges'], 1);
    expect(preview.counts['target_overrides'], 1);
    await service.commit(preview);

    final biomarker = (await repository.biomarkers()).single;
    expect(biomarker.displayName, 'LDL-C');
    expect(biomarker.defaultUnit, 'mg/dL');
    expect(biomarker.priceEur, 4.2);
    expect(biomarker.description, 'Atherogenic cholesterol marker.');
    expect(biomarker.synonyms, containsAll(['LDL-Cholesterin', 'LDL']));

    final db = await database.database;
    final ranges = await db.query('biomarker_ranges');
    expect(ranges, hasLength(1));
    final catalogRange = ranges.singleWhere(
      (row) => row['range_type'] == 'longevity_target',
    );
    expect(catalogRange['optimal_high'], 100.0);
    expect(catalogRange['evidence_label'], 'Imported personal catalog');
    final personalTarget = (await db.query('profile_biomarker_targets')).single;
    expect(personalTarget['high'], 70.0);
    expect(personalTarget['optimal_high'], 85.0);
    expect(personalTarget['unit'], 'mg/dL');
    expect(personalTarget['notes'], contains('old-profile'));
    await database.close();
  });

  test('Biomarkers PDFs are hash-matched and attached idempotently', () async {
    sqfliteFfiInit();
    final temporaryDirectory = await Directory.systemTemp.createTemp(
      'superhealth-pdf-import-',
    );
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final profile = await repository.createProfile(displayName: 'Me');
    final service = LegacyImportService(
      database,
      repository,
      documentsDirectory: () async => temporaryDirectory,
    );
    final pdfBytes = Uint8List.fromList(
      utf8.encode('%PDF-1.4\nlegacy report\n%%EOF'),
    );
    final hash = sha256.convert(pdfBytes).toString();
    Uint8List jsonBytes(Object value) =>
        Uint8List.fromList(utf8.encode(jsonEncode(value)));

    final dataPreview = await service.preview([
      ImportSourceFile(
        name: 'documents.json',
        bytes: jsonBytes([
          {
            'id': 'legacy-document',
            'file_name': 'blood-test.pdf',
            'sha256': hash,
            'report_date': '2026-01-15',
            'lab_name': 'Example Lab',
          },
        ]),
      ),
    ], fallbackProfile: profile);
    await service.commit(dataPreview);

    final pdfPreview = await service.previewPdfs([
      ImportSourceFile(name: '$hash.pdf', bytes: pdfBytes),
    ]);
    expect(pdfPreview.selectedFiles, 1);
    expect(pdfPreview.matchedDocuments, 1);
    expect(pdfPreview.alreadyAvailable, 0);
    expect(pdfPreview.unmatchedFiles, 0);
    expect(pdfPreview.canImport, isTrue);

    final result = await service.commitPdfs(pdfPreview);
    expect(result.attachedDocuments, 1);
    final document = (await repository.documents(profile.id)).single;
    expect(document.labName, 'Example Lab');
    expect(document.documentDate, DateTime(2026, 1, 15));
    expect(document.localPath, isNotNull);
    expect(await File(document.localPath!).readAsBytes(), pdfBytes);

    final repeatedPreview = await service.previewPdfs([
      ImportSourceFile(name: '$hash.pdf', bytes: pdfBytes),
    ]);
    expect(repeatedPreview.alreadyAvailable, 1);
    expect(repeatedPreview.canImport, isFalse);

    await database.close();
    await temporaryDirectory.delete(recursive: true);
  });
}
