import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/ai_models.dart';
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
        'counts': {
          'measurements': 2,
          'biomarker_catalog': 1,
          'supplements': 0,
          'supplement_intakes': 0,
          'health_events': 0,
          'conditions_medications_goals_history': 0,
        },
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
    expect(
      envelope.fileSha256,
      sha256.convert(utf8.encode(envelope.json)).toString(),
    );
    expect(envelope.sectionHashes['measurements'], hasLength(64));
    expect(envelope.coverageInstruction, contains('"file_sha256"'));
    // The receipt never asks the model to transcribe the per-section digests.
    // It cannot compute them, so echoing them proved nothing the section
    // enumeration does not already prove — and one dropped character out of
    // more than a thousand discarded a finished answer.
    expect(envelope.coverageInstruction, isNot(contains('section_hashes')));
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
    'household stock is explicit navigation evidence and never personal intake evidence',
    () async {
      final value = snapshot();
      final data = value['data']! as Map<String, Object?>;
      final manifest = value['manifest']! as Map<String, Object?>;
      data['inventory_movements'] = [
        {
          'id': 'movement-spouse',
          'supplement_id': 'magnesium',
          'profile_id': 'profile-2',
          'quantity_units': -0.25,
        },
        {
          'id': 'movement-active',
          'supplement_id': 'magnesium',
          'profile_id': 'profile-1',
          'quantity_units': -0.125,
        },
      ];
      data['household_stock_levels'] = [
        {
          'id': 'household-stock:magnesium',
          'supplement_id': 'magnesium',
          'name': 'Magnesium',
          'stock_unit': 'capsules',
          'low_stock_threshold_units': 2.25,
          'current_units': 2.125,
        },
      ];
      (manifest['counts']! as Map<String, int>)['inventory_movements'] = 2;
      (manifest['counts']! as Map<String, int>)['household_stock_levels'] = 1;

      final envelope = await HealthContextBuilder.fromLoader(
        (_) async => value,
      ).build('profile-1');
      final decoded = jsonDecode(envelope.json) as Map<String, dynamic>;
      final attention = decoded['attention_index'] as Map<String, dynamic>;
      final stock =
          (attention['household_stock'] as List<dynamic>).single
              as Map<String, dynamic>;
      final contract = decoded['coverage_contract'] as Map<String, dynamic>;

      expect(stock['current_units'], 2.125);
      expect(stock['is_low_stock'], isTrue);
      expect(stock['inventory_movement_record_count'], 2);
      expect(stock['inventory_movement_record_refs'], [
        'inventory_movements:movement-active',
        'inventory_movements:movement-spouse',
      ]);
      expect(stock['personal_intake_inference'], contains('not_permitted'));
      expect(
        (contract['evidence_scope']
            as Map<String, dynamic>)['clinical_evidence'],
        'active_profile_only',
      );
      expect(
        contract['required_reading_protocol'].join(' '),
        contains('Only active-profile supplement_intakes'),
      );
      expect(envelope.manifest['profile_isolated'], isFalse);
      expect(envelope.manifest['clinical_evidence_profile_isolated'], isTrue);
      expect(
        envelope.manifest['household_shared_supplement_inventory'],
        isTrue,
      );
      expect(
        (envelope.manifest['evidence_scope']
            as Map<String, Object?>)['inventory_movement_profile_id'],
        'provenance_only',
      );
    },
  );

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

  test(
    'missing declared list count fails instead of assuming completeness',
    () async {
      final value = snapshot();
      final counts =
          (value['manifest']! as Map<String, Object?>)['counts']!
              as Map<String, int>;
      counts.remove('health_events');
      final builder = HealthContextBuilder.fromLoader((_) async => value);

      await expectLater(builder.build('profile-1'), throwsA(isA<StateError>()));
    },
  );

  test(
    'only uses a documented file path when inline working room is exhausted',
    () async {
      final context = await HealthContextBuilder.fromLoader(
        (_) async => snapshot(),
      ).build('profile-1');
      final builder = HealthContextBuilder.fromLoader((_) async => snapshot());
      final fileCapable = const ModelCapabilities(
        codeExecution: true,
        losslessContextFile: true,
        contextWindowTokens: 12000,
      );

      expect(
        builder.deliveryFor(
          context: context,
          capabilities: fileCapable,
          maxOutputTokens: 11000,
        ),
        HealthContextDelivery.providerFile,
      );
      expect(
        () => builder.deliveryFor(
          context: context,
          capabilities: const ModelCapabilities(),
          maxOutputTokens: 100,
        ),
        throwsA(isA<StateError>()),
      );
    },
  );
}
