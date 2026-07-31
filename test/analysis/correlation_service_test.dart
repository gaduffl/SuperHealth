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
    expect(results.single.spearmanCoefficient, closeTo(1, 0.0001));
    expect(results.single.pValue, lessThan(0.001));
    expect(results.single.adjustedPValue, lessThan(0.001));
    expect(results.single.isStatisticallySignificant, isTrue);
    await database.close();
  });

  test(
    'reports rank correlation for monotonic non-linear associations',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Rank');
      final start = DateTime(2026, 2, 1);
      final doses = [1, 2, 3, 4, 5, 6, 100];
      for (var index = 0; index < doses.length; index++) {
        final day = start.add(Duration(days: index));
        await _saveTag(repository, profile.id, 'Dose', day, doses[index]);
        await _saveSymptom(repository, profile.id, 'Energy', day, index + 1);
      }

      final result = (await CorrelationService(
        repository,
      ).analyze(profile.id, lags: const [0])).single;

      expect(result.coefficient, lessThan(0.8));
      expect(result.spearmanCoefficient, closeTo(1, 0.0001));
      await database.close();
    },
  );

  test(
    'skips constant and insufficient series without producing invalid values',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Safe');
      final shortProfile = await repository.createProfile(displayName: 'Short');
      final start = DateTime(2026, 3, 1);
      for (var index = 0; index < 7; index++) {
        final day = start.add(Duration(days: index));
        await _saveTag(repository, profile.id, 'Constant', day, 1);
        await _saveSymptom(repository, profile.id, 'Pain', day, index + 1);
      }
      for (var index = 0; index < 2; index++) {
        final day = start.add(Duration(days: index));
        await _saveTag(repository, shortProfile.id, 'Short', day, index + 1);
        await _saveSymptom(
          repository,
          shortProfile.id,
          'Short pain',
          day,
          index + 1,
        );
      }

      final results = await CorrelationService(
        repository,
      ).analyze(profile.id, minimumPairs: 2, lags: const [0]);
      final shortResults = await CorrelationService(
        repository,
      ).analyze(shortProfile.id, minimumPairs: 2, lags: const [0]);

      expect(results, isEmpty);
      expect(shortResults, isEmpty);
      await database.close();
    },
  );

  test(
    'uses Benjamini-Hochberg adjustment and deterministic result ordering',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Adjusted');
      final start = DateTime(2026, 4, 1);
      final strong = [1, 1, 2, 2, 3, 3, 4, 4, 5, 5];
      final noisy = [0, 1, 0, 1, 0, 1, 0, 1, 0, 1];
      for (var index = 0; index < 10; index++) {
        final day = start.add(Duration(days: index));
        await _saveTag(repository, profile.id, 'Z strong', day, strong[index]);
        await _saveTag(repository, profile.id, 'A noisy', day, noisy[index]);
        await _saveSymptom(repository, profile.id, 'Focus', day, index + 1);
      }

      final results = await CorrelationService(
        repository,
      ).analyze(profile.id, lags: const [0, 0]);
      final strongResult = results.singleWhere(
        (result) => result.exposure == 'Tag: Z strong',
      );
      final noisyResult = results.singleWhere(
        (result) => result.exposure == 'Tag: A noisy',
      );

      expect(results, hasLength(2));
      expect(results.first.exposure, 'Tag: Z strong');
      expect(strongResult.pValue, isNotNull);
      expect(strongResult.adjustedPValue, isNotNull);
      expect(noisyResult.pValue, isNotNull);
      expect(noisyResult.adjustedPValue, isNotNull);
      expect(
        strongResult.adjustedPValue,
        greaterThanOrEqualTo(strongResult.pValue!),
      );
      expect(
        noisyResult.adjustedPValue,
        greaterThanOrEqualTo(noisyResult.pValue!),
      );
      expect(
        strongResult.adjustedPValue,
        closeTo(strongResult.pValue! * 2, 1e-10),
      );
      expect(noisyResult.adjustedPValue, closeTo(noisyResult.pValue!, 1e-10));
      await database.close();
    },
  );

  test(
    'occurrence-mode tags count daily occurrences, ignoring any stray numeric value',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Occurs');
      final definition = HealthEventDefinition(
        id: repository.newId(),
        profileId: profile.id,
        kind: EventKind.tag,
        name: 'Walk outside',
        valueMode: TagValueMode.occurrence,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await repository.saveEventDefinition(definition);
      final start = DateTime(2026, 6, 1);
      final counts = [0, 1, 2, 3, 4, 5, 6];
      for (var index = 0; index < counts.length; index++) {
        final day = start.add(Duration(days: index));
        for (var occurrence = 0; occurrence < counts[index]; occurrence++) {
          await repository.saveEvent(
            HealthEvent(
              id: repository.newId(),
              profileId: profile.id,
              definitionId: definition.id,
              kind: EventKind.tag,
              name: definition.name,
              observedAt: day,
              numericValue: 999,
              createdAt: day,
              updatedAt: day,
            ),
          );
        }
        await _saveSymptom(
          repository,
          profile.id,
          'Mood',
          day,
          counts[index] + 1,
        );
      }

      final result = (await CorrelationService(
        repository,
      ).analyze(profile.id, lags: const [0])).single;

      expect(result.exposure, 'Tag: Walk outside');
      expect(result.sampleSize, counts.length);
      expect(result.spearmanCoefficient, closeTo(1, 0.0001));
      await database.close();
    },
  );

  test(
    'intensity-mode tags average same-day felt-strength scores instead of summing them',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Intensity');
      final definition = HealthEventDefinition(
        id: repository.newId(),
        profileId: profile.id,
        kind: EventKind.tag,
        name: 'Stress',
        valueMode: TagValueMode.intensity,
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await repository.saveEventDefinition(definition);
      final start = DateTime(2026, 7, 1);
      for (var index = 0; index < 7; index++) {
        final day = start.add(Duration(days: index));
        final level = index + 1;
        if (index == 2) {
          // Two same-day readings that average back to the plain level, so
          // a wrongly-summed reduction would break the otherwise-perfect
          // monotonic pattern below.
          for (final score in [level - 1, level + 1]) {
            await repository.saveEvent(
              HealthEvent(
                id: repository.newId(),
                profileId: profile.id,
                definitionId: definition.id,
                kind: EventKind.tag,
                name: definition.name,
                observedAt: day,
                score: score,
                createdAt: day,
                updatedAt: day,
              ),
            );
          }
        } else {
          await repository.saveEvent(
            HealthEvent(
              id: repository.newId(),
              profileId: profile.id,
              definitionId: definition.id,
              kind: EventKind.tag,
              name: definition.name,
              observedAt: day,
              score: level,
              createdAt: day,
              updatedAt: day,
            ),
          );
        }
        await _saveSymptom(repository, profile.id, 'Headache', day, level);
      }

      final result = (await CorrelationService(
        repository,
      ).analyze(profile.id, lags: const [0])).single;

      expect(result.exposure, 'Tag: Stress');
      expect(result.coefficient, closeTo(1, 0.0001));
      expect(result.spearmanCoefficient, closeTo(1, 0.0001));
      await database.close();
    },
  );

  test(
    'amount-mode tags sum entries in the canonical unit and ignore mismatched units',
    () async {
      sqfliteFfiInit();
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final profile = await repository.createProfile(displayName: 'Amount');
      final definition = HealthEventDefinition(
        id: repository.newId(),
        profileId: profile.id,
        kind: EventKind.tag,
        name: 'Coffee',
        valueMode: TagValueMode.amount,
        defaultUnit: 'g',
        createdAt: DateTime(2026, 1, 1),
        updatedAt: DateTime(2026, 1, 1),
      );
      await repository.saveEventDefinition(definition);
      final start = DateTime(2026, 8, 1);
      final grams = [0, 2, 4, 6, 8, 10, 12];
      for (var index = 0; index < grams.length; index++) {
        final day = start.add(Duration(days: index));
        if (grams[index] > 0) {
          await repository.saveEvent(
            HealthEvent(
              id: repository.newId(),
              profileId: profile.id,
              definitionId: definition.id,
              kind: EventKind.tag,
              name: definition.name,
              observedAt: day,
              numericValue: grams[index].toDouble(),
              unit: 'g',
              createdAt: day,
              updatedAt: day,
            ),
          );
        }
        if (index == 3) {
          // A mismatched-unit entry that must not contribute to the "g"
          // series; if it wrongly did, its huge value would break rank
          // order below.
          await repository.saveEvent(
            HealthEvent(
              id: repository.newId(),
              profileId: profile.id,
              definitionId: definition.id,
              kind: EventKind.tag,
              name: definition.name,
              observedAt: day,
              numericValue: 999,
              unit: 'ml',
              createdAt: day,
              updatedAt: day,
            ),
          );
        }
        await _saveSymptom(repository, profile.id, 'Jitters', day, index + 1);
      }

      final result = (await CorrelationService(
        repository,
      ).analyze(profile.id, lags: const [0])).single;

      expect(result.exposure, 'Tag: Coffee (g)');
      expect(result.spearmanCoefficient, closeTo(1, 0.0001));
      await database.close();
    },
  );

  test('keeps results isolated to the requested profile', () async {
    sqfliteFfiInit();
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final selected = await repository.createProfile(displayName: 'Selected');
    final other = await repository.createProfile(displayName: 'Other');
    final start = DateTime(2026, 5, 1);
    for (var index = 0; index < 7; index++) {
      final day = start.add(Duration(days: index));
      await _saveTag(
        repository,
        selected.id,
        'Selected tag',
        day,
        index.isEven ? 1 : 0,
      );
      await _saveSymptom(
        repository,
        selected.id,
        'Selected symptom',
        day,
        index.isEven ? 9 : 1,
      );
      await _saveTag(repository, other.id, 'Other tag', day, index + 1);
      await _saveSymptom(repository, other.id, 'Other symptom', day, 7 - index);
    }

    final results = await CorrelationService(
      repository,
    ).analyze(selected.id, lags: const [0]);

    expect(results, hasLength(1));
    expect(results.single.exposure, 'Tag: Selected tag');
    expect(results.single.outcome, 'Selected symptom');
    await database.close();
  });
}

Future<void> _saveTag(
  HealthRepository repository,
  String profileId,
  String name,
  DateTime day,
  num value,
) => repository.saveEvent(
  HealthEvent(
    id: repository.newId(),
    profileId: profileId,
    kind: EventKind.tag,
    name: name,
    observedAt: day,
    numericValue: value.toDouble(),
    createdAt: day,
    updatedAt: day,
  ),
);

Future<void> _saveSymptom(
  HealthRepository repository,
  String profileId,
  String name,
  DateTime day,
  int score,
) => repository.saveEvent(
  HealthEvent(
    id: repository.newId(),
    profileId: profileId,
    kind: EventKind.symptom,
    name: name,
    observedAt: day,
    score: score,
    createdAt: day,
    updatedAt: day,
  ),
);
