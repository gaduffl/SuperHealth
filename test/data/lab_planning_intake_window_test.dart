import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:super_health/ai/health_context_builder.dart';
import 'package:super_health/data/app_database.dart';
import 'package:super_health/data/health_repository.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  late AppDatabase database;
  late HealthRepository repository;
  late Profile profile;

  setUp(() async {
    sqfliteFfiInit();
    database = AppDatabase(
      factory: databaseFactoryFfi,
      databasePath: inMemoryDatabasePath,
    );
    repository = HealthRepository(database);
    profile = await repository.createProfile(displayName: 'Window');
    final now = DateTime.now().toUtc();
    await repository.saveSupplement(
      Supplement(
        id: 'supp-old',
        name: 'Long standing',
        stockUnit: 'capsules',
        createdAt: now,
        updatedAt: now,
      ),
    );
    // Three years of monthly doses, ending today: the case a window is most
    // likely to misrepresent.
    for (var monthsAgo = 0; monthsAgo < 36; monthsAgo++) {
      final takenAt = now.subtract(Duration(days: monthsAgo * 30));
      await repository.saveIntake(
        SupplementIntake(
          id: 'intake-$monthsAgo',
          profileId: profile.id,
          supplementId: 'supp-old',
          takenAt: takenAt,
          dose: 1,
          unit: 'capsule',
          createdAt: now,
          updatedAt: now,
        ),
      );
    }
  });

  tearDown(() => database.close());

  Future<Map<String, Object?>> snapshot(HealthContextScope scope) =>
      repository.completeProfileSnapshot(profile.id, scope: scope);

  test('lab planning carries only recent doses', () async {
    final data =
        (await snapshot(HealthContextScope.labPlanning))['data']!
            as Map<String, Object?>;
    final intakes = data['supplement_intakes']! as List;

    // 122 days at one dose per 30 days.
    expect(intakes, hasLength(5));
    expect(intakes.length, lessThan(36));
  });

  test('advisory still carries the whole ledger', () async {
    // Adherence and long-run patterns are the advisor's question; windowing
    // there would remove the evidence rather than the noise.
    final data =
        (await snapshot(HealthContextScope.advisory))['data']!
            as Map<String, Object?>;

    expect(data['supplement_intakes'], hasLength(36));
  });

  test('the window never makes a long habit look newly started', () async {
    // The failure the window would otherwise cause: three years of exposure
    // and a month of it are clinically different, and inside a four-month
    // slice they are identical.
    final data =
        (await snapshot(HealthContextScope.labPlanning))['data']!
            as Map<String, Object?>;
    final history = (data['supplement_intake_history']! as List).single as Map;

    expect(history['supplement_id'], 'supp-old');
    expect(history['dose_count'], 36);
    final firstDose = DateTime.parse(history['first_dose_at']! as String);
    expect(
      DateTime.now().toUtc().difference(firstDose).inDays,
      greaterThan(1000),
    );
  });

  test('the package declares the window rather than hiding it', () async {
    final envelope = await HealthContextBuilder(repository).build(profile.id);
    final package = jsonDecode(envelope.json) as Map<String, Object?>;
    final contract = package['coverage_contract']! as Map<String, Object?>;

    // The reading protocol tells the model never to infer absence. That
    // instruction is only true if the window is visible to it.
    expect(contract['raw_ledger_is_complete'], isFalse);
    final windows = contract['windowed_sections']! as Map<String, Object?>;
    expect(windows.keys, contains('supplement_intakes'));
    final window = windows['supplement_intakes']! as Map<String, Object?>;
    expect(window['days'], 122);
    expect(window['reason'], contains('supplement_intake_history'));
    expect(
      (contract['required_reading_protocol']! as List).join(' '),
      contains('windowed_sections'),
    );
    expect((envelope.manifest['complete']), isFalse);
    expect(envelope.manifest['complete_within_declared_windows'], isTrue);
  });

  test('the advisory package claims completeness, because it is', () async {
    final envelope = await HealthContextBuilder(
      repository,
      scope: HealthContextScope.advisory,
    ).build(profile.id);
    final contract =
        (jsonDecode(envelope.json)
                as Map<String, Object?>)['coverage_contract']!
            as Map<String, Object?>;

    expect(contract['raw_ledger_is_complete'], isTrue);
    expect(envelope.manifest['complete'], isTrue);
  });

  test('the window bound is stable across builds on the same day', () async {
    // The context hash identifies a body of evidence — the receipt, and now the
    // prompt cache key, both depend on it. An instant-based bound made two
    // builds a second apart disagree.
    final builder = HealthContextBuilder(repository);
    final first = await builder.build(profile.id);
    final second = await builder.build(profile.id);

    expect(second.sha256, first.sha256);
  });

  test('the cutoff snaps to a UTC midnight', () {
    final cutoff = HealthRepository.labPlanningIntakeCutoff(
      DateTime.utc(2026, 8, 9, 17, 43, 12),
    );

    expect(cutoff, DateTime.utc(2026, 4, 9));
    expect(cutoff.isUtc, isTrue);
  });

  test('section sizes are recorded so the big one can be found', () async {
    final envelope = await HealthContextBuilder(repository).build(profile.id);
    final sections = envelope.manifest['sections']! as Map<String, Object?>;

    for (final entry in sections.entries) {
      expect((entry.value! as Map)['bytes'], isA<int>(), reason: entry.key);
    }
    // Shrinking a context needs to know which section to shrink, and a single
    // total never says.
    expect(envelope.largestSectionsDescription(), contains('='));
  });
}
