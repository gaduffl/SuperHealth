import 'dart:convert';
import 'dart:typed_data';

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
    ], fallbackProfile: profile);

    expect(preview.counts['biomarkers'], 1);
    expect(preview.counts['ranges'], 1);
    await service.commit(preview);

    final biomarker = (await repository.biomarkers()).single;
    expect(biomarker.displayName, 'LDL-C');
    expect(biomarker.defaultUnit, 'mg/dL');
    expect(biomarker.priceEur, 4.2);
    expect(biomarker.description, 'Atherogenic cholesterol marker.');
    expect(biomarker.synonyms, containsAll(['LDL-Cholesterin', 'LDL']));

    final db = await database.database;
    final range = (await db.query('biomarker_ranges')).single;
    expect(range['range_type'], 'longevity_target');
    expect(range['optimal_high'], 100.0);
    expect(range['evidence_label'], 'Imported personal catalog');
    await database.close();
  });
}
