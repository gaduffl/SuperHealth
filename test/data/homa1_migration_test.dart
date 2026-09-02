import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/biomarkers/calculated_biomarker_service.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';

import 'legacy_schema.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test('v12 upgrades the legacy HOMA formula with an explicit HOMA1 name', () async {
    final directory = await Directory.systemTemp.createTemp('homa1-v12-');
    final databasePath = '${directory.path}/super_health_v1.db';
    final legacy = await databaseFactoryFfi.openDatabase(
      databasePath,
      options: OpenDatabaseOptions(
        version: 12,
        onCreate: (db, _) async {
          await db.execute(legacyBiomarkersTable);
          await db.insert('biomarkers', {
            'id': 'legacy-homa',
            'canonical_name': 'homa_ir',
            'display_name': 'HOMA-Index (Glucoexakt)',
            'default_unit': 'index',
            'description': 'Legacy calculated marker.',
            'synonyms_json': '["HOMA-IR"]',
            'created_at': '2026-01-01T00:00:00.000Z',
            'updated_at': '2026-01-01T00:00:00.000Z',
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
    final repository = HealthRepository(database);

    final homa1 = (await repository.biomarkers()).single;
    expect(homa1.id, 'legacy-homa');
    expect(
      homa1.canonicalName,
      CalculatedBiomarkerService.homa1CanonicalName,
    );
    expect(homa1.displayName, 'HOMA1-IR (berechnet)');
    expect(homa1.isCalculated, isTrue);
    expect(homa1.calculationFormula, CalculatedBiomarkerService.homa1Formula);
    expect(homa1.description, contains('not HOMA2-IR'));
    expect(homa1.synonyms, isNot(contains('HOMA-IR')));
  });
}
