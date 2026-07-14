import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  late AppDatabase database;
  late HealthRepository repository;

  setUp(() {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = HealthRepository(database);
  });

  tearDown(() => database.close());

  test(
    'complete health context is profile-isolated and declares exclusions',
    () async {
      final alpha = await repository.createProfile(displayName: 'Alpha');
      final beta = await repository.createProfile(displayName: 'Beta');
      final now = DateTime.now();
      await repository.saveSupplement(
        Supplement(
          id: repository.newId(),
          profileId: alpha.id,
          name: 'Alpha only',
          createdAt: now,
          updatedAt: now,
        ),
      );
      await repository.saveSupplement(
        Supplement(
          id: repository.newId(),
          profileId: beta.id,
          name: 'Beta secret',
          createdAt: now,
          updatedAt: now,
        ),
      );

      final snapshot = await repository.completeProfileSnapshot(alpha.id);
      final encoded = HealthRepository.stableJson(snapshot);
      expect(encoded, contains('Alpha only'));
      expect(encoded, isNot(contains('Beta secret')));
      expect(encoded, contains('api_keys'));
      expect(encoded, contains('other_profiles'));
      expect((snapshot['manifest']! as Map)['complete'], isTrue);
    },
  );

  test('context envelope hashes the full stable snapshot', () async {
    final profile = await repository.createProfile(displayName: 'Hash test');
    final builder = HealthContextBuilder(repository);
    final first = await builder.build(profile.id);
    expect(first.byteLength, greaterThan(100));
    expect(first.sha256, hasLength(64));
    final unchanged = await builder.build(profile.id);
    expect(unchanged.sha256, first.sha256);

    final now = DateTime.now();
    await repository.saveNamedRecord(
      NamedHealthRecord(
        id: repository.newId(),
        profileId: profile.id,
        name: 'Longevity',
        kind: 'goal',
        createdAt: now,
        updatedAt: now,
      ),
    );
    final second = await builder.build(profile.id);
    expect(second.sha256, isNot(first.sha256));
    expect(second.byteLength, greaterThan(first.byteLength));
  });

  test(
    'reviewed document bundles persist provenance but hide device paths from AI',
    () async {
      final profile = await repository.createProfile(
        displayName: 'Document test',
      );
      final now = DateTime(2026, 2, 3);
      final biomarker = Biomarker(
        id: repository.newId(),
        canonicalName: 'apo_b',
        displayName: 'ApoB',
        defaultUnit: 'mg/dL',
        isTemporary: true,
        createdAt: now,
        updatedAt: now,
      );
      final document = HealthDocument(
        id: repository.newId(),
        profileId: profile.id,
        fileName: 'lab.pdf',
        sha256: 'abc123',
        localPath: '/private/device/path/lab.pdf',
        oneDriveItemId: 'cloud-secret-id',
        documentDate: now,
        parserProvider: 'openai',
        parserModel: 'model',
        createdAt: now,
        updatedAt: now,
      );
      final measurement = Measurement(
        id: repository.newId(),
        profileId: profile.id,
        biomarkerId: biomarker.id,
        documentId: document.id,
        takenAt: now,
        value: 85,
        unit: 'mg/dL',
        extractionConfidence: 0.97,
        page: 2,
        rowText: 'ApoB 85 mg/dL',
        createdAt: now,
        updatedAt: now,
      );
      await repository.saveDocumentBundle(
        document: document,
        newBiomarkers: [biomarker],
        measurements: [measurement],
      );

      expect(await repository.documents(profile.id), hasLength(1));
      expect((await repository.measurements(profile.id)).single.page, 2);
      final context = HealthRepository.stableJson(
        await repository.completeProfileSnapshot(profile.id),
      );
      expect(context, contains('ApoB 85 mg/dL'));
      expect(context, isNot(contains('/private/device/path')));
      expect(context, isNot(contains('cloud-secret-id')));
    },
  );
}
