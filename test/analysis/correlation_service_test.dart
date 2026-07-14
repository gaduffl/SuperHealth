import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/analysis/correlation_service.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  test('daily correlation includes zero-exposure symptom days', () async {
    sqfliteFfiInit();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final profile = await repository.createProfile(displayName: 'Correlation');
    final created = DateTime(2026, 1, 1);
    for (var index = 0; index < 10; index++) {
      final day = created.add(Duration(days: index));
      final exposed = index.isEven;
      if (exposed) {
        await repository.saveEvent(
          HealthEvent(
            id: repository.newId(),
            profileId: profile.id,
            kind: EventKind.tag,
            name: 'Caffeine',
            observedAt: day,
            numericValue: 1,
            createdAt: day,
            updatedAt: day,
          ),
        );
      }
      await repository.saveEvent(
        HealthEvent(
          id: repository.newId(),
          profileId: profile.id,
          kind: EventKind.symptom,
          name: 'Headache',
          observedAt: day,
          score: exposed ? 8 : 2,
          createdAt: day,
          updatedAt: day,
        ),
      );
    }

    final results = await CorrelationService(
      repository,
    ).analyze(profile.id, lags: const [0]);
    expect(results, hasLength(1));
    expect(results.single.sampleSize, 10);
    expect(results.single.coefficient, closeTo(1, 0.0001));
    await database.close();
  });
}
