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
            'units_per_container': 60,
            'num_containers': 2,
            'price': 12.5,
            'ingredients': [
              {'name': 'Magnesium glycinate', 'amount': 100, 'unit': 'mg'},
            ],
          },
          {
            'name': 'Zinc',
            'brand': 'Example',
            'form': 'tablet',
            'units_per_container': 30,
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
      expect(preview.counts['supplements'], 2);
      expect(preview.canImport, isTrue);

      final result = await service.commit(preview);
      expect(await repository.supplements(profile.id), hasLength(2));
      final db = await database.database;
      final movements = await db.query('inventory_movements');
      expect(movements, hasLength(1));
      expect(movements.single['quantity_units'], 120.0);

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
    expect(personalTarget['borderline_high'], 85.0);
    expect(personalTarget['unit'], 'mg/dL');
    expect(personalTarget['notes'], contains('old-profile'));
    await database.close();
  });

  test(
    'Biomarkers import aliases duplicate canonical names within one bundle',
    () async {
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
              'id': 'vitamin-d-first',
              'canonical_name': '1 25 dihydroxy vitamin d',
              'display_name': '1,25-Dihydroxy Vitamin D',
              'unit_primary': 'pg/mL',
            },
            {
              'id': 'vitamin-d-punctuation-variant',
              'canonical_name': '1,25-dihydroxy vitamin d',
              'display_name': '1,25-Dihydroxy Vitamin D',
              'unit_primary': 'pg/mL',
            },
          ]),
        ),
        ImportSourceFile(
          name: 'measurements.json',
          bytes: jsonBytes([
            {
              'id': 'measurement-first',
              'biomarker_id': 'vitamin-d-first',
              'value': 42,
              'unit': 'pg/mL',
            },
            {
              'id': 'measurement-variant',
              'biomarker_id': 'vitamin-d-punctuation-variant',
              'value': 43,
              'unit': 'pg/mL',
            },
          ]),
        ),
      ], fallbackProfile: profile);

      expect(preview.counts['biomarkers'], 1);
      expect(
        preview.duplicates,
        contains(
          contains('both use the canonical name “1_25_dihydroxy_vitamin_d”'),
        ),
      );
      await service.commit(preview);

      final biomarkers = await repository.biomarkers();
      expect(biomarkers, hasLength(1));
      expect(biomarkers.single.canonicalName, '1_25_dihydroxy_vitamin_d');
      final db = await database.database;
      final measurements = await db.query(
        'measurements',
        orderBy: 'value ASC',
      );
      expect(measurements, hasLength(2));
      expect(
        measurements.map((row) => row['biomarker_id']).toSet(),
        {biomarkers.single.id},
      );
      await database.close();
    },
  );

  test(
    'Biomarkers profile metadata imports numeric legacy height into a new profile',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final fallback = await repository.createProfile(displayName: 'Fallback');
      final service = LegacyImportService(database, repository);
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'profiles': [
              {
                'id': 'legacy-alex',
                'displayName': 'Alex',
                'date_of_birth': '1988-02-03',
                'sex': 'male',
                'heightCm': 181.5,
                'weight_kg': 79.2,
              },
            ],
            'rows': [
              {'id': 'apo_b', 'display_name': 'ApoB', 'unit_primary': 'mg/dL'},
            ],
          }),
        ),
      );

      final preview = await service.preview([
        ImportSourceFile(name: 'biomarkers.json', bytes: bytes),
      ], fallbackProfile: fallback);
      await service.commit(preview);

      final imported = (await repository.profiles()).singleWhere(
        (profile) => profile.displayName == 'Alex',
      );
      expect(imported.heightCm, 181.5);
      expect(imported.weightKg, 79.2);
      expect(imported.sex, 'male');
      await database.close();
    },
  );

  test(
    'Biomarkers profile metadata fills only missing same-name local fields',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final local = await repository.createProfile(
        displayName: 'Alex',
        notes: 'Keep this local note.',
      );
      final service = LegacyImportService(database, repository);
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'profiles': [
              {
                'id': 'old-alex',
                'display_name': 'Alex',
                'date_of_birth': '1980-01-02',
                'sex': 'female',
                'height_cm': 169,
                'weight': 62.5,
                'notes': 'Legacy notes must not replace local notes.',
              },
            ],
            'rows': [
              {'id': 'ldl', 'display_name': 'LDL'},
            ],
          }),
        ),
      );

      final preview = await service.preview([
        ImportSourceFile(name: 'biomarkers.json', bytes: bytes),
      ], fallbackProfile: local);
      expect(preview.duplicates, isNotEmpty);
      await service.commit(preview);

      final merged = (await repository.profiles()).single;
      expect(merged.id, local.id);
      expect(merged.displayName, 'Alex');
      expect(merged.notes, 'Keep this local note.');
      expect(merged.dateOfBirth, DateTime(1980, 1, 2));
      expect(merged.sex, 'female');
      expect(merged.heightCm, 169);
      expect(merged.weightKg, 62.5);
      await database.close();
    },
  );

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

  test(
    'legacy import excludes non-finite required values and omits optionals',
    () async {
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
              'id': 'apob',
              'display_name': 'ApoB',
              'unit_primary': 'mg/dL',
              'price': 'Infinity',
            },
          ]),
        ),
        ImportSourceFile(
          name: 'supplement_sync.json',
          bytes: jsonBytes({
            'products': [
              {
                'name': 'Example',
                'units_per_container': -30,
                'num_containers': -2,
                'price': -5,
              },
            ],
            'schedules': {
              'Me': {
                'Example': {
                  'Monday': {'AM': 0},
                },
              },
            },
            'intakeHistory': [
              {
                'productName': 'Example',
                'userName': 'Me',
                'timestamp': '2026-01-01T08:00:00Z',
                'amount': -1,
              },
              {
                'productName': 'Example',
                'userName': 'Me',
                'timestamp': '2026-01-02T08:00:00Z',
              },
            ],
            'profiles': [
              {'displayName': 'Invalid profile', 'heightCm': 301, 'weight': 0},
            ],
          }),
        ),
        ImportSourceFile(
          name: 'measurements.json',
          bytes: jsonBytes([
            {
              'id': 'nan',
              'biomarker_id': 'apob',
              'value': 'NaN',
              'unit': 'mg/dL',
            },
            {
              'id': 'infinite',
              'biomarker_id': 'apob',
              'value': '-Infinity',
              'unit': 'mg/dL',
            },
            {
              'id': 'negative-finite',
              'biomarker_id': 'apob',
              'value': '-4.5',
              'unit': 'mg/dL',
              'lab_ref_low': 'NaN',
              'lab_ref_high': 'Infinity',
              'extraction_confidence': 'NaN',
              'page': 'Infinity',
            },
            {
              'id': 'unordered',
              'biomarker_id': 'apob',
              'value': -3,
              'unit': 'mg/dL',
              'lab_ref_low': 10,
              'lab_ref_high': 5,
              'extraction_confidence': 2,
              'page': 0,
            },
          ]),
        ),
        ImportSourceFile(
          name: 'ranges.json',
          bytes: jsonBytes([
            {
              'id': 'apob-range',
              'biomarker_id': 'apob',
              'low': 'NaN',
              'high': 'Infinity',
              'optimal_low': -10,
              'age_min': 'Infinity',
              'evidence_url': 'file:///not-allowed',
            },
          ]),
        ),
        ImportSourceFile(
          name: 'biomarker_lists.json',
          bytes: jsonBytes([
            {'id': 'legacy-list', 'name': 'Retest', 'due_duration': 0},
          ]),
        ),
        ImportSourceFile(
          name: 'biomarker_list_entries.json',
          bytes: jsonBytes([
            {
              'list_id': 'legacy-list',
              'biomarker_id': 'apob',
              'due_duration': -14,
            },
          ]),
        ),
      ], fallbackProfile: profile);

      expect(preview.counts['measurements'], 2);
      expect(
        preview.warnings.join('\n'),
        contains('non-finite measurement value'),
      );
      expect(
        preview.warnings.join('\n'),
        contains('non-finite biomarker price'),
      );
      expect(preview.warnings.join('\n'), contains('non-finite range low'));
      expect(
        preview.warnings.join('\n'),
        contains('Ignored negative supplement price'),
      );
      expect(preview.warnings.join('\n'), contains('profile height outside'));
      expect(
        preview.warnings.join('\n'),
        contains('Skipped invalid intake dose'),
      );
      expect(
        preview.warnings.join('\n'),
        contains('Ignored unordered lab reference bounds'),
      );
      expect(preview.warnings.join('\n'), contains('invalid retest interval'));

      await service.commit(preview);
      final db = await database.database;
      final measurements = await db.query('measurements', orderBy: 'value');
      expect(measurements, hasLength(2));
      final measurement = measurements.first;
      expect(measurement['value'], -4.5);
      expect(measurement['lab_ref_low'], isNull);
      expect(measurement['lab_ref_high'], isNull);
      expect(measurement['extraction_confidence'], isNull);
      expect(measurement['page'], isNull);
      final unordered = measurements.last;
      expect(unordered['lab_ref_low'], isNull);
      expect(unordered['lab_ref_high'], isNull);
      expect(unordered['extraction_confidence'], isNull);
      expect(unordered['page'], isNull);
      final range = (await db.query('biomarker_ranges')).single;
      expect(range['low'], isNull);
      expect(range['high'], isNull);
      expect(range['optimal_low'], -10.0);
      expect(range['age_min'], isNull);
      expect(range['evidence_url'], isNull);
      final supplement = (await db.query('supplements')).single;
      expect(supplement['units_per_container'], isNull);
      expect(supplement['container_count'], isNull);
      expect(supplement['price_eur'], isNull);
      final intakes = await db.query('supplement_intakes');
      expect(intakes, hasLength(1));
      expect(intakes.single['dose'], 1.0);
      final importedProfile = (await db.query(
        'profiles',
        where: 'display_name = ?',
        whereArgs: ['Invalid profile'],
      )).single;
      expect(importedProfile['height_cm'], isNull);
      expect(importedProfile['weight_kg'], isNull);
      final listItem = (await db.query('biomarker_list_items')).single;
      expect(listItem['due_interval_days'], isNull);
      await database.close();
    },
  );

  test(
    'legacy ingredient amounts are finite positive doubles or omitted',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Me');
      final service = LegacyImportService(database, repository);
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'products': [
              {
                'name': 'Compound',
                'ingredients': [
                  {'name': 'Valid', 'amount': '12,5', 'unit': 'mg'},
                  {'name': 'Infinite', 'amount': 'Infinity', 'unit': 'mg'},
                  {'name': 'Zero', 'amount': 0, 'unit': 'mg'},
                  {'name': 'Negative', 'amount': -1, 'unit': 'mg'},
                  {'name': 'Missing', 'unit': 'mg'},
                ],
              },
            ],
            'intakeHistory': [
              {
                'productName': 'Compound',
                'timestamp': '2026-01-01T08:00:00Z',
                'ingredientsSnapshot': [
                  {'name': 'Intake valid', 'amount': '1,25', 'unit': 'g'},
                  {'name': 'Intake invalid', 'amount': 'NaN', 'unit': 'g'},
                ],
              },
            ],
          }),
        ),
      );

      final preview = await service.preview([
        ImportSourceFile(name: 'supplement_sync.json', bytes: bytes),
      ], fallbackProfile: profile);
      expect(
        preview.warnings.where(
          (warning) =>
              warning == 'Ignored invalid ingredient amount for Compound.',
        ),
        hasLength(1),
      );

      await service.commit(preview);
      final db = await database.database;
      final supplement = (await db.query('supplements')).single;
      final ingredients =
          jsonDecode(supplement['ingredients_json']! as String)
              as List<dynamic>;
      expect((ingredients.first as Map)['amount'], 12.5);
      for (final ingredient in ingredients.skip(1)) {
        expect((ingredient as Map).containsKey('amount'), isFalse);
      }
      final intake = (await db.query('supplement_intakes')).single;
      final snapshot =
          jsonDecode(intake['ingredients_json']! as String) as List<dynamic>;
      expect((snapshot.first as Map)['amount'], 1.25);
      expect((snapshot.last as Map).containsKey('amount'), isFalse);
      await database.close();
    },
  );
}
