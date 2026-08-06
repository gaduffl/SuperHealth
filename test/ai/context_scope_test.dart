import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/ai_models.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'the advisor sees measured markers, the planner sees the catalog',
    () async {
      final database = AppDatabase(
        factory: databaseFactoryFfi,
        databasePath: inMemoryDatabasePath,
      );
      final repository = HealthRepository(database);
      final now = DateTime(2026, 8, 6);
      final profile = await repository.createProfile(displayName: 'Scope');

      for (final id in ['measured', 'never-measured']) {
        await repository.saveBiomarker(
          Biomarker(
            id: id,
            canonicalName: id,
            displayName: id,
            createdAt: now,
            updatedAt: now,
          ),
        );
        await repository.saveBiomarkerRange(
          BiomarkerReferenceRange(
            id: 'range-$id',
            biomarkerId: id,
            rangeType: 'lab',
            unit: 'mg/dL',
            low: 1,
            high: 10,
            createdAt: now,
            updatedAt: now,
          ),
        );
      }
      await repository.saveMeasurement(
        Measurement(
          id: 'm',
          profileId: profile.id,
          biomarkerId: 'measured',
          takenAt: now,
          value: 1,
          unit: 'mg/dL',
          createdAt: now,
          updatedAt: now,
        ),
      );

      List<Object?> catalog(Map<String, Object?> snapshot) =>
          (snapshot['data']! as Map<String, Object?>)['biomarker_catalog']!
              as List<Object?>;

      final planning = await repository.completeProfileSnapshot(
        profile.id,
        scope: HealthContextScope.labPlanning,
      );
      final advisory = await repository.completeProfileSnapshot(
        profile.id,
        scope: HealthContextScope.advisory,
      );

      // The planner has to be able to propose a test that has never been run.
      expect(catalog(planning), hasLength(2));
      // Advice reasons about results that exist, so an unmeasured marker is
      // context the advisor pays for and cannot use.
      expect(catalog(advisory), hasLength(1));
      expect((catalog(advisory).single as Map)['id'], 'measured');
      expect(
        ((advisory['data']! as Map<String, Object?>)['biomarker_ranges']!
                as List<Object?>)
            .length,
        1,
      );

      await database.close();
    },
  );

  test('another profile\'s supplements stay out of the context', () async {
    final database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    final repository = HealthRepository(database);
    final now = DateTime(2026, 8, 6);
    final mine = await repository.createProfile(displayName: 'Mine');
    final theirs = await repository.createProfile(displayName: 'Theirs');

    for (final id in ['ours', 'theirs-only', 'nobody-takes']) {
      await repository.saveSupplement(
        Supplement(id: id, name: id, createdAt: now, updatedAt: now),
      );
    }
    await repository.saveIntake(
      SupplementIntake(
        id: 'i1',
        profileId: mine.id,
        supplementId: 'ours',
        takenAt: now,
        dose: 1,
        unit: 'capsule',
        createdAt: now,
        updatedAt: now,
      ),
    );
    await repository.saveIntake(
      SupplementIntake(
        id: 'i2',
        profileId: theirs.id,
        supplementId: 'theirs-only',
        takenAt: now,
        dose: 1,
        unit: 'capsule',
        createdAt: now,
        updatedAt: now,
      ),
    );

    final snapshot = await repository.completeProfileSnapshot(mine.id);
    final data = snapshot['data']! as Map<String, Object?>;
    final supplements = (data['supplements']! as List<Object?>)
        .map((row) => (row! as Map)['id'])
        .toSet();

    // The catalog is household-shared, but someone else's supplement is not
    // evidence about this profile — it was only filling context.
    expect(supplements, {'ours'});
    // And the raw movement ledger is gone entirely.
    expect(data['inventory_movements'], isEmpty);

    await database.close();
  });

  group('reported token usage', () {
    test('reads the shape each provider actually returns', () {
      // OpenAI Responses and Anthropic Messages.
      expect(
        TokenUsage.fromResponse({
          'usage': {'input_tokens': 120, 'output_tokens': 45},
        })?.inputTokens,
        120,
      );
      // The older prompt/completion naming.
      expect(
        TokenUsage.fromResponse({
          'usage': {'prompt_tokens': 7, 'completion_tokens': 3},
        })?.totalTokens,
        10,
      );
      // Gemini.
      final gemini = TokenUsage.fromResponse({
        'usageMetadata': {'promptTokenCount': 9, 'candidatesTokenCount': 4},
      });
      expect(gemini?.inputTokens, 9);
      expect(gemini?.outputTokens, 4);
    });

    test('a response without usage reports nothing rather than zero', () {
      // Zero would read as "this cost nothing", which is a different claim
      // from "the provider did not say".
      expect(TokenUsage.fromResponse({}), isNull);
      expect(TokenUsage.fromResponse({'usage': 'unexpected'}), isNull);
      expect(const TokenUsage().isEmpty, isTrue);
      expect(const TokenUsage().totalTokens, isNull);
    });
  });
}
