import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  late AppDatabase database;
  late HealthRepository repository;
  late Profile profile;
  late Biomarker biomarker;
  final now = DateTime.utc(2026, 7, 18);

  setUp(() async {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = HealthRepository(database);
    profile = await repository.createProfile(displayName: 'Numeric test');
    biomarker = Biomarker(
      id: repository.newId(),
      canonicalName: 'test_marker',
      displayName: 'Test marker',
      defaultUnit: 'unit',
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveBiomarker(biomarker);
  });

  tearDown(() => database.close());

  Measurement measurement({
    required String id,
    required double value,
    double? labRefLow,
    double? labRefHigh,
  }) => Measurement(
    id: id,
    profileId: profile.id,
    biomarkerId: biomarker.id,
    takenAt: now,
    value: value,
    unit: 'unit',
    labRefLow: labRefLow,
    labRefHigh: labRefHigh,
    createdAt: now,
    updatedAt: now,
  );

  test('rejects non-finite values before representative writes', () async {
    await expectLater(
      repository.saveMeasurement(
        measurement(id: repository.newId(), value: double.nan),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveSupplement(
        Supplement(
          id: repository.newId(),
          name: 'Invalid price',
          priceEur: double.infinity,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveInventoryMovement(
        InventoryMovement(
          id: repository.newId(),
          supplementId: 'invalid-supplement',
          quantityUnits: double.negativeInfinity,
          occurredAt: now,
          reason: 'correction',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveSchedule(
        SupplementSchedule(
          id: repository.newId(),
          profileId: profile.id,
          supplementId: 'invalid-supplement',
          dose: double.nan,
          unit: 'mg',
          timeOfDay: 'morning',
          weekdays: const ['monday'],
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveEvent(
        HealthEvent(
          id: repository.newId(),
          profileId: profile.id,
          kind: EventKind.symptom,
          name: 'Invalid event',
          observedAt: now,
          numericValue: double.infinity,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveProfileTarget(
        ProfileBiomarkerTarget(
          id: repository.newId(),
          profileId: profile.id,
          biomarkerId: biomarker.id,
          low: 1,
          high: double.nan,
          unit: 'unit',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveDocumentBundle(
        document: HealthDocument(
          id: repository.newId(),
          profileId: profile.id,
          fileName: 'invalid.pdf',
          createdAt: now,
          updatedAt: now,
        ),
        newBiomarkers: const [],
        measurements: [
          measurement(id: repository.newId(), value: double.negativeInfinity),
        ],
      ),
      throwsArgumentError,
    );

    expect(await repository.measurements(profile.id), isEmpty);
    expect(await repository.supplements(), isEmpty);
    expect(await repository.documents(profile.id), isEmpty);
  });

  test('rejects reversed target, lab, and stored reference bounds', () async {
    await expectLater(
      repository.saveProfileTarget(
        ProfileBiomarkerTarget(
          id: repository.newId(),
          profileId: profile.id,
          biomarkerId: biomarker.id,
          low: 20,
          high: 10,
          unit: 'unit',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveMeasurement(
        measurement(
          id: repository.newId(),
          value: 10,
          labRefLow: 12,
          labRefHigh: 11,
        ),
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.saveBiomarkerRange(
        BiomarkerReferenceRange(
          id: repository.newId(),
          biomarkerId: biomarker.id,
          rangeType: 'reference',
          low: 5,
          high: 4,
          unit: 'unit',
          createdAt: now,
          updatedAt: now,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('persists a finite negative biomarker measurement', () async {
    final value = measurement(id: repository.newId(), value: -1.5);

    await repository.saveMeasurement(value);

    expect((await repository.measurements(profile.id)).single.value, -1.5);
  });

  test('keeps a finite source measurement when conversion overflows', () async {
    final overflowBiomarker = Biomarker(
      id: repository.newId(),
      canonicalName: 'overflow_marker',
      displayName: 'Overflow marker',
      defaultUnit: '%',
      createdAt: now,
      updatedAt: now,
    );
    await repository.saveBiomarker(overflowBiomarker);
    final source = Measurement(
      id: repository.newId(),
      profileId: profile.id,
      biomarkerId: overflowBiomarker.id,
      takenAt: now,
      value: double.maxFinite,
      unit: 'ratio',
      createdAt: now,
      updatedAt: now,
    );

    await repository.saveMeasurement(source);

    final db = await database.database;
    final row = (await db.query(
      'measurements',
      columns: const ['value', 'canonical_value', 'conversion_status'],
      where: 'id = ?',
      whereArgs: [source.id],
    )).single;
    expect(row['value'], double.maxFinite);
    expect(row['canonical_value'], isNull);
    expect(row['conversion_status'], 'unsupported');
  });
}
