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
}
