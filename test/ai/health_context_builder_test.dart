import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/health_context_builder.dart';

void main() {
  Map<String, Object?> snapshot({bool reverseMeasurements = false}) {
    final measurements = <Map<String, Object?>>[
      {
        'id': 'm-old',
        'profile_id': 'profile-1',
        'biomarker_id': 'apo-b',
        'taken_at': '2025-01-01T08:00:00Z',
        'value': 0.85,
        'unit_reported': 'g/L',
      },
      {
        'id': 'm-new',
        'profile_id': 'profile-1',
        'biomarker_id': 'apo-b',
        'taken_at': '2026-01-01T08:00:00Z',
        'value': 75,
        'unit_reported': 'mg/dL',
      },
    ];
    return {
      'schema': 'superhealth.health_context',
      'schema_version': 1,
      'generated_at': '2026-07-18T10:00:00Z',
      'active_profile_id': 'profile-1',
      'manifest': {
        'complete': true,
        'counts': {'measurements': 2, 'biomarker_catalog': 1},
        'excluded': ['api_keys', 'other_profiles'],
      },
      'data': {
        'profile': {
          'id': 'profile-1',
          'display_name': 'Sebastian',
          'created_at': '2026-01-01T00:00:00Z',
          'updated_at': '2026-01-01T00:00:00Z',
        },
        'biomarker_catalog': [
          {'id': 'apo-b', 'display_name': 'ApoB', 'default_unit': 'mg/dL'},
        ],
        'measurements': reverseMeasurements
            ? measurements.reversed.toList()
            : measurements,
        'supplements': <Map<String, Object?>>[],
        'supplement_intakes': <Map<String, Object?>>[],
        'health_events': <Map<String, Object?>>[],
        'conditions_medications_goals_history': <Map<String, Object?>>[],
      },
    };
  }

  test('package keeps every source row and adds integrity metadata', () async {
    final builder = HealthContextBuilder.fromLoader((_) async => snapshot());
    final envelope = await builder.build('profile-1');
    final decoded = jsonDecode(envelope.json) as Map<String, dynamic>;
    final ledger = decoded['raw_ledger'] as Map<String, dynamic>;
    final measurements = ledger['measurements'] as List<dynamic>;

    expect(measurements, hasLength(2));
    expect(
      measurements.map((row) => row['id']),
      containsAll(['m-old', 'm-new']),
    );
    expect(envelope.manifest['complete'], isTrue);
    expect(envelope.manifest['lossless'], isTrue);
    expect(envelope.recordCount, 4);
    expect(envelope.sha256, hasLength(64));
    expect(envelope.sectionHashes['measurements'], hasLength(64));
  });

  test(
    'attention index exposes mixed units without changing source values',
    () async {
      final builder = HealthContextBuilder.fromLoader((_) async => snapshot());
      final envelope = await builder.build('profile-1');
      final decoded = jsonDecode(envelope.json) as Map<String, dynamic>;
      final attention = decoded['attention_index'] as Map<String, dynamic>;
      final latest = (attention['latest_biomarkers'] as List<dynamic>).single;
      final flags = attention['data_quality_flags'] as List<dynamic>;

      expect(latest['latest_value'], 75);
      expect(latest['previous_value'], 0.85);
      expect(latest['reported_units_seen'], ['g/L', 'mg/dL']);
      expect(flags.single['type'], 'mixed_biomarker_units_unresolved');
    },
  );

  test('context hash is stable when source row order changes', () async {
    final normal = HealthContextBuilder.fromLoader((_) async => snapshot());
    final reversed = HealthContextBuilder.fromLoader(
      (_) async => snapshot(reverseMeasurements: true),
    );

    expect(
      (await normal.build('profile-1')).sha256,
      (await reversed.build('profile-1')).sha256,
    );
  });

  test(
    'count mismatch fails instead of silently sending partial context',
    () async {
      final value = snapshot();
      (value['manifest']! as Map<String, Object?>)['counts'] = {
        'measurements': 3,
      };
      final builder = HealthContextBuilder.fromLoader((_) async => value);

      await expectLater(builder.build('profile-1'), throwsA(isA<StateError>()));
    },
  );
}
