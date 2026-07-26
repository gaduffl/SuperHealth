import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/biomarkers/reference_range_exchange.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  late AppDatabase database;
  late HealthRepository repository;
  final now = DateTime.utc(2026, 7, 18, 10);

  setUp(() {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = HealthRepository(database);
  });

  tearDown(() => database.close());

  Biomarker biomarker(
    String id,
    String name, {
    bool temporary = false,
    List<String> synonyms = const [],
  }) => Biomarker(
    id: id,
    canonicalName: HealthRepository.normalizeName(name),
    displayName: name,
    defaultUnit: 'mg/dL',
    isTemporary: temporary,
    synonyms: synonyms,
    createdAt: now,
    updatedAt: now,
  );

  BiomarkerReferenceRange range(String id, String biomarkerId) =>
      BiomarkerReferenceRange(
        id: id,
        biomarkerId: biomarkerId,
        rangeType: 'reference',
        sex: 'female',
        ageMin: 18,
        ageMax: 65,
        low: 10,
        high: 20,
        optimalLow: 12,
        optimalHigh: 18,
        unit: 'mg/dL',
        evidenceLabel: 'Lab guide',
        evidenceUrl: 'https://example.test/range',
        notes: 'same evidence',
        createdAt: now,
        updatedAt: now,
      );

  test(
    'range JSON and CSV exports round-trip without losing evidence fields',
    () {
      final catalog = [biomarker('lipid', 'Lipid marker')];
      final source = range('range-1', 'lipid');
      final exchange = BiomarkerRangeExchange();

      final json = exchange.parse(
        text: exchange.exportJson([source], catalog),
        extension: 'json',
        biomarkers: catalog,
      );
      final csv = exchange.parse(
        text: exchange.exportCsv([source], catalog),
        extension: 'csv',
        biomarkers: catalog,
      );

      for (final preview in [json, csv]) {
        expect(preview.canImport, isTrue);
        final imported = preview.records.single;
        expect(imported.biomarkerId, 'lipid');
        expect(imported.evidenceUrl, source.evidenceUrl);
        expect(imported.evidenceLabel, source.evidenceLabel);
        expect(imported.sex, source.sex);
        expect(imported.ageMax, source.ageMax);
        expect(imported.optimalHigh, source.optimalHigh);
        expect(imported.notes, source.notes);
      }
    },
  );

  test('range import rejects invalid bounds and ambiguous biomarker matches', () {
    final exchange = BiomarkerRangeExchange();
    final invalid = exchange.parse(
      text:
          '''{"schema":"superhealth.biomarker_ranges","schema_version":1,"ranges":[{"canonical_name":"apob","range_type":"reference","unit":"mg/dL","low":"NaN","high":20}]}''',
      extension: 'json',
      biomarkers: [biomarker('apo', 'ApoB')],
    );
    final ambiguous = exchange.parse(
      text:
          '''{"schema":"superhealth.biomarker_ranges","schema_version":1,"ranges":[{"display_name":"ApoB","range_type":"reference","unit":"mg/dL","low":1,"high":2}]}''',
      extension: 'json',
      biomarkers: [biomarker('one', 'ApoB'), biomarker('two', 'ApoB')],
    );

    expect(invalid.canImport, isFalse);
    expect(invalid.issues.single.message, contains('finite'));
    expect(ambiguous.canImport, isFalse);
    expect(ambiguous.issues.single.message, contains('Ambiguous'));
  });

  test('range import enforces file identity and skips existing exact ranges', () {
    final exchange = BiomarkerRangeExchange();
    final catalog = [biomarker('apo', 'ApoB')];
    final source = range('range-1', 'apo');
    final schema = exchange.parse(
      text: '''{"schema":"wrong","schema_version":1,"ranges":[]}''',
      extension: 'json',
      biomarkers: catalog,
    );
    final identity = exchange.parse(
      text:
          '''{"schema":"superhealth.biomarker_ranges","schema_version":1,"ranges":[{"biomarker_id":"apo","canonical_name":"different","range_type":"reference","unit":"mg/dL","low":1}]}''',
      extension: 'json',
      biomarkers: catalog,
    );
    final duplicate = exchange.parse(
      text: exchange.exportJson([source], catalog),
      extension: 'json',
      biomarkers: catalog,
      existingRanges: [source],
    );

    expect(schema.canImport, isFalse);
    expect(schema.issues.single.message, contains('schema'));
    expect(identity.canImport, isFalse);
    expect(identity.issues.single.message, contains('identity'));
    expect(duplicate.records, isEmpty);
    expect(duplicate.skipped, hasLength(1));
    expect(duplicate.skipped.single.message, contains('identical'));
  });

  test('range import fails closed when an explicit biomarker id disagrees', () {
    final exchange = BiomarkerRangeExchange();
    final catalog = [biomarker('apo', 'ApoB'), biomarker('ldl', 'LDL')];
    RangeImportPreview parse(String identity) => exchange.parse(
      text:
          '{"schema":"superhealth.biomarker_ranges","schema_version":1,"ranges":[{$identity,"range_type":"reference","unit":"mg/dL","low":1}]}',
      extension: 'json',
      biomarkers: catalog,
    );

    final unknownId = parse('"biomarker_id":"missing","canonical_name":"apob"');
    final mismatchedDisplay = parse(
      '"biomarker_id":"apo","display_name":"LDL"',
    );
    final agreeing = parse(
      '"biomarker_id":"apo","canonical_name":"apob","display_name":"ApoB"',
    );

    expect(unknownId.canImport, isFalse);
    expect(unknownId.issues.single.message, contains('id'));
    expect(mismatchedDisplay.canImport, isFalse);
    expect(mismatchedDisplay.issues.single.message, contains('identity'));
    expect(agreeing.canImport, isTrue);
    expect(agreeing.records.single.biomarkerId, 'apo');
  });

  test(
    'range import rejects unsafe URLs, invalid ages, and duplicate CSV headers',
    () {
      final exchange = BiomarkerRangeExchange();
      final catalog = [biomarker('apo', 'ApoB')];
      final unsafe = exchange.parse(
        text:
            '''{"schema":"superhealth.biomarker_ranges","schema_version":1,"ranges":[{"biomarker_id":"apo","range_type":"reference","unit":"mg/dL","low":1,"evidence_url":"ftp://example.test/range"}]}''',
        extension: 'json',
        biomarkers: catalog,
      );
      final invalidAge = exchange.parse(
        text:
            '''{"schema":"superhealth.biomarker_ranges","schema_version":1,"ranges":[{"biomarker_id":"apo","range_type":"reference","unit":"mg/dL","low":1,"age_max":151}]}''',
        extension: 'json',
        biomarkers: catalog,
      );
      final duplicateHeaders = exchange.parse(
        text: 'biomarker_id,range_type,unit,low,low\napo,reference,mg/dL,1,1',
        extension: 'csv',
        biomarkers: catalog,
      );

      expect(unsafe.canImport, isFalse);
      expect(unsafe.issues.single.message, contains('http'));
      expect(invalidAge.canImport, isFalse);
      expect(invalidAge.issues.single.message, contains('Ages'));
      expect(duplicateHeaders.canImport, isFalse);
      expect(duplicateHeaders.issues.single.message, contains('headers'));
    },
  );

  test(
    'temporary merge reassigns every biomarker relation and tombstones duplicates',
    () async {
      final profile = await repository.createProfile(displayName: 'Alex');
      final temporary = biomarker(
        'temporary',
        'Apo B imported',
        temporary: true,
        synonyms: const ['Apo-B lab'],
      );
      final canonical = biomarker(
        'canonical',
        'ApoB',
        synonyms: const ['Apolipoprotein B'],
      );
      await repository.saveBiomarker(temporary);
      await repository.saveBiomarker(canonical);
      await repository.saveMeasurement(
        Measurement(
          id: 'measurement',
          profileId: profile.id,
          biomarkerId: temporary.id,
          takenAt: now,
          value: 81.4,
          unit: 'mg/dL',
          canonicalValue: 81.4,
          canonicalUnit: 'mg/dL',
          conversionStatus: 'not_required',
          rowText: 'Apo B 81.4 mg/dL',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repository.saveProfileTarget(
        ProfileBiomarkerTarget(
          id: 'target-temp',
          profileId: profile.id,
          biomarkerId: temporary.id,
          low: 50,
          high: 80,
          unit: 'mg/dL',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repository.saveProfileTarget(
        ProfileBiomarkerTarget(
          id: 'target-canonical',
          profileId: profile.id,
          biomarkerId: canonical.id,
          low: 45,
          high: 75,
          unit: 'mg/dL',
          createdAt: now,
          updatedAt: now,
        ),
      );
      final list = BiomarkerList(
        id: 'list',
        profileId: profile.id,
        name: 'Core',
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveBiomarkerList(list);
      await repository.saveBiomarkerListItem(
        BiomarkerListItem(
          id: 'list-temp',
          listId: list.id,
          biomarkerId: temporary.id,
          dueIntervalDays: 90,
          notes: 'temporary cadence',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repository.saveBiomarkerListItem(
        BiomarkerListItem(
          id: 'list-canonical',
          listId: list.id,
          biomarkerId: canonical.id,
          dueIntervalDays: 120,
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repository.saveBiomarkerRange(range('range-temp', temporary.id));
      await repository.saveBiomarkerRange(
        range('range-canonical', canonical.id),
      );
      await repository.saveLabPlan(
        LabPlan(
          id: 'plan',
          profileId: profile.id,
          title: 'Plan',
          contextHash: 'hash',
          createdAt: now,
          updatedAt: now,
          items: [
            LabPlanItem(
              id: 'plan-item',
              planId: 'plan',
              biomarkerId: temporary.id,
              biomarkerName: temporary.displayName,
              tier: LabTier.values.first,
              priority: 1,
              rationale: 'track',
              evidenceClass: EvidenceClass.values.first,
              createdAt: now,
              updatedAt: now,
            ),
          ],
        ),
      );

      final result = await repository.mergeTemporaryBiomarker(
        temporaryBiomarkerId: temporary.id,
        canonicalBiomarkerId: canonical.id,
      );

      expect(result.movedMeasurements, 1);
      expect(
        (await repository.measurements(profile.id)).single,
        isA<Measurement>(),
      );
      final measurement = (await repository.measurements(profile.id)).single;
      expect(measurement.biomarkerId, canonical.id);
      expect(measurement.value, 81.4);
      expect(measurement.canonicalValue, 81.4);
      expect(measurement.rowText, 'Apo B 81.4 mg/dL');
      expect(
        (await repository.profileTargets(profile.id)).single.id,
        'target-canonical',
      );
      expect(
        (await repository.biomarkerLists(profile.id)).single.items.single.id,
        'list-canonical',
      );
      expect(
        (await repository.biomarkerRanges(biomarkerId: canonical.id)),
        hasLength(1),
      );
      expect(
        (await repository.labPlans(profile.id)).single.items.single.biomarkerId,
        canonical.id,
      );
      expect(
        (await repository.labPlans(
          profile.id,
        )).single.items.single.biomarkerName,
        canonical.displayName,
      );
      final mergedCanonical = (await repository.biomarkers()).singleWhere(
        (item) => item.id == canonical.id,
      );
      expect(
        mergedCanonical.synonyms,
        containsAll([
          'Apolipoprotein B',
          'Apo B imported',
          'apo_b_imported',
          'Apo-B lab',
        ]),
      );

      final db = await database.database;
      expect(
        (await db.query(
          'biomarkers',
          where: 'id = ?',
          whereArgs: [temporary.id],
        )).single['deleted'],
        1,
      );
      expect(
        (await db.query(
          'profile_biomarker_targets',
          where: 'id = ?',
          whereArgs: ['target-temp'],
        )).single,
        containsPair('deleted', 1),
      );
      expect(
        (await db.query(
          'profile_biomarker_targets',
          where: 'id = ?',
          whereArgs: ['target-temp'],
        )).single['biomarker_id'],
        canonical.id,
      );
      expect(
        (await db.query(
          'biomarker_list_items',
          where: 'id = ?',
          whereArgs: ['list-temp'],
        )).single,
        containsPair('deleted', 1),
      );
      expect(
        (await db.query(
          'biomarker_list_items',
          where: 'id = ?',
          whereArgs: ['list-temp'],
        )).single['biomarker_id'],
        canonical.id,
      );
      expect(
        (await db.query(
          'biomarker_ranges',
          where: 'id = ?',
          whereArgs: ['range-temp'],
        )).single,
        containsPair('deleted', 1),
      );
      expect(
        (await db.query(
          'biomarker_ranges',
          where: 'id = ?',
          whereArgs: ['range-temp'],
        )).single['biomarker_id'],
        canonical.id,
      );
    },
  );

  test(
    'temporary biomarker can become permanent without changing its id',
    () async {
      final temporary = biomarker(
        'temporary',
        'Imported only',
        temporary: true,
      );
      await repository.saveBiomarker(temporary);

      await repository.makeTemporaryBiomarkerPermanent(temporary.id);

      final permanent = (await repository.biomarkers()).single;
      expect(permanent.id, temporary.id);
      expect(permanent.isTemporary, isFalse);
    },
  );
}
