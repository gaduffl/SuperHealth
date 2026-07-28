import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  late AppDatabase database;
  late HealthRepository repository;
  final now = DateTime.now();

  setUp(() {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = HealthRepository(database);
  });

  tearDown(() => database.close());

  Future<void> addList({
    required String profileId,
    required String name,
    required String biomarkerId,
    required int intervalDays,
  }) async {
    final listId = repository.newId();
    await repository.saveBiomarkerList(
      BiomarkerList(
        id: listId,
        profileId: profileId,
        name: name,
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.saveBiomarkerListItem(
      BiomarkerListItem(
        id: repository.newId(),
        listId: listId,
        biomarkerId: biomarkerId,
        dueIntervalDays: intervalDays,
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  test('a biomarker on several lists is due once, not once per list', () async {
    final profile = await repository.createProfile(displayName: 'Alex');
    await repository.saveBiomarker(
      Biomarker(
        id: 'ferritin',
        canonicalName: 'ferritin',
        displayName: 'Ferritin',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.saveMeasurement(
      Measurement(
        id: repository.newId(),
        profileId: profile.id,
        biomarkerId: 'ferritin',
        takenAt: now.subtract(const Duration(days: 400)),
        value: 60,
        unit: 'ng/mL',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await addList(
      profileId: profile.id,
      name: 'Annual',
      biomarkerId: 'ferritin',
      intervalDays: 365,
    );
    await addList(
      profileId: profile.id,
      name: 'Iron panel',
      biomarkerId: 'ferritin',
      intervalDays: 90,
    );
    await addList(
      profileId: profile.id,
      name: 'Quarterly',
      biomarkerId: 'ferritin',
      intervalDays: 180,
    );

    final due = await repository.dueBiomarkers(profile.id);

    expect(due, hasLength(1));
    expect(due.single.biomarker.id, 'ferritin');
    // Every list that wants it is named, sorted so the display is stable.
    expect(due.single.listNames, ['Annual', 'Iron panel', 'Quarterly']);
    // The most demanding list sets the schedule: meeting 90 days satisfies
    // the longer intervals too.
    expect(due.single.intervalDays, 90);
  });

  test('a biomarker still within its interval is not due', () async {
    final profile = await repository.createProfile(displayName: 'Alex');
    await repository.saveBiomarker(
      Biomarker(
        id: 'tsh',
        canonicalName: 'tsh',
        displayName: 'TSH',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.saveMeasurement(
      Measurement(
        id: repository.newId(),
        profileId: profile.id,
        biomarkerId: 'tsh',
        takenAt: now.subtract(const Duration(days: 10)),
        value: 1.5,
        unit: 'mIU/L',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await addList(
      profileId: profile.id,
      name: 'Annual',
      biomarkerId: 'tsh',
      intervalDays: 365,
    );

    expect(await repository.dueBiomarkers(profile.id), isEmpty);
  });

  test('a never-measured biomarker is due once across its lists', () async {
    final profile = await repository.createProfile(displayName: 'Alex');
    await repository.saveBiomarker(
      Biomarker(
        id: 'b12',
        canonicalName: 'vitamin b12',
        displayName: 'Vitamin B12',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await addList(
      profileId: profile.id,
      name: 'Annual',
      biomarkerId: 'b12',
      intervalDays: 365,
    );
    await addList(
      profileId: profile.id,
      name: 'Energy',
      biomarkerId: 'b12',
      intervalDays: 120,
    );

    final due = await repository.dueBiomarkers(profile.id);

    expect(due, hasLength(1));
    expect(due.single.lastMeasuredAt, isNull);
    expect(due.single.listNames, ['Annual', 'Energy']);
  });

  test('distinct biomarkers stay separate and sort by due date', () async {
    final profile = await repository.createProfile(displayName: 'Alex');
    for (final id in ['ferritin', 'b12']) {
      await repository.saveBiomarker(
        Biomarker(
          id: id,
          canonicalName: id,
          displayName: id,
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
    await repository.saveMeasurement(
      Measurement(
        id: repository.newId(),
        profileId: profile.id,
        biomarkerId: 'ferritin',
        takenAt: now.subtract(const Duration(days: 100)),
        value: 60,
        unit: 'ng/mL',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await addList(
      profileId: profile.id,
      name: 'Panel',
      biomarkerId: 'ferritin',
      intervalDays: 90,
    );
    await addList(
      profileId: profile.id,
      name: 'Panel two',
      biomarkerId: 'b12',
      intervalDays: 90,
    );

    final due = await repository.dueBiomarkers(profile.id);

    expect(due.map((item) => item.biomarker.id), ['b12', 'ferritin']);
  });
}
