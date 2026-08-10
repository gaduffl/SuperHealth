import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/health_context_builder.dart';

/// A snapshot with one row of every shape the trimming has to get right.
Map<String, Object?> source({String activeProfile = 'profile-1'}) => {
  'schema': 'superhealth.health_context',
  'schema_version': 1,
  'active_profile_id': activeProfile,
  'manifest': {
    'complete': true,
    'counts': {'measurements': 1, 'health_events': 1, 'inventory_movements': 1},
  },
  'data': {
    'measurements': [
      {
        'id': 'm1',
        'profile_id': 'profile-1',
        'biomarker_id': 'bio-1',
        'taken_at': '2026-01-01T00:00:00Z',
        'value': 0,
        'unit_reported': 'mg/dL',
        'lab_ref_low': null,
        'lab_ref_high': null,
        'notes': '',
        'flags_json': '[]',
        'created_at': '2026-02-01T00:00:00Z',
        'updated_at': '2026-02-02T00:00:00Z',
        'deleted': 0,
      },
    ],
    'health_events': [
      {
        'id': 'e1',
        'profile_id': 'profile-1',
        'name': 'Tremor',
        'observed_at': '2026-01-02T00:00:00Z',
        'score': 0,
        'color_value': 4279150057,
        'archived': 0,
        'created_at': '2026-02-01T00:00:00Z',
        'updated_at': '2026-02-01T00:00:00Z',
        'deleted': 0,
      },
    ],
    // Household-shared: its profile_id is provenance, not a repeat of the
    // active profile.
    'inventory_movements': [
      {
        'id': 'mv1',
        'profile_id': 'someone-else',
        'supplement_id': 'supp-1',
        'quantity_units': 30,
      },
    ],
  },
};

Future<Map<String, Object?>> ledgerOf(Map<String, Object?> snapshot) async {
  final envelope = await HealthContextBuilder.fromLoader(
    (_) async => snapshot,
  ).build('${snapshot['active_profile_id']}');
  return (jsonDecode(envelope.json) as Map<String, Object?>)['raw_ledger']!
      as Map<String, Object?>;
}

void main() {
  test('a key that would state nothing is left out', () async {
    final ledger = await ledgerOf(source());
    final measurement = (ledger['measurements']! as List).single as Map;

    // Nulls, empty strings and empty JSON collections say exactly what an
    // absent key says, and the coverage contract states that they mean the
    // same thing.
    for (final key in ['lab_ref_low', 'lab_ref_high', 'notes', 'flags_json']) {
      expect(measurement.containsKey(key), isFalse, reason: key);
    }
  });

  test('a zero is a recorded observation, not an empty field', () async {
    final ledger = await ledgerOf(source());

    expect(((ledger['measurements']! as List).single as Map)['value'], 0);
    expect(((ledger['health_events']! as List).single as Map)['score'], 0);
  });

  test('bookkeeping columns never reach the model', () async {
    final ledger = await ledgerOf(source());
    final measurement = (ledger['measurements']! as List).single as Map;
    final event = (ledger['health_events']! as List).single as Map;

    // When a row was written is not when the thing happened, and every section
    // carries its own clinical date.
    for (final key in HealthContextBuilder.omittedRowKeys) {
      expect(measurement.containsKey(key), isFalse, reason: key);
      expect(event.containsKey(key), isFalse, reason: key);
    }
    expect(measurement['taken_at'], '2026-01-01T00:00:00Z');
    expect(event['observed_at'], '2026-01-02T00:00:00Z');
    // `archived` is a decision the user made, not bookkeeping.
    expect(event['archived'], 0);
  });

  test('profile_id goes only where it repeats the active profile', () async {
    final ledger = await ledgerOf(source());

    expect(
      ((ledger['measurements']! as List).single as Map).containsKey(
        'profile_id',
      ),
      isFalse,
    );
    // On household-shared evidence it is real provenance, so it stays.
    expect(
      ((ledger['inventory_movements']! as List).single as Map)['profile_id'],
      'someone-else',
    );
  });

  test('the package states every encoding rule it applies', () async {
    final envelope = await HealthContextBuilder.fromLoader(
      (_) async => source(),
    ).build('profile-1');
    final contract =
        (jsonDecode(envelope.json)
                as Map<String, Object?>)['coverage_contract']!
            as Map<String, Object?>;
    final encoding = contract['row_encoding']! as Map<String, Object?>;

    // The reading protocol forbids inferring that a record is absent. That is
    // only true if the reasons a *key* can be absent are spelled out.
    expect('${encoding['omitted_when_empty']}', contains('nothing recorded'));
    expect('${encoding['omitted_always']}', contains('created_at'));
    expect('${encoding['profile_id']}', contains('active_profile_id'));
    expect('${encoding['numbers_are_never_omitted']}', contains('zero'));
  });

  test('the attention index no longer transcribes the ledger', () async {
    final envelope = await HealthContextBuilder.fromLoader(
      (_) async => source(),
    ).build('profile-1');
    final index =
        (jsonDecode(envelope.json) as Map<String, Object?>)['attention_index']!
            as Map<String, Object?>;

    // `chronology` listed one entry per record — at, section, record_ref,
    // date_field — all four already in the row it pointed at. 446 KB on a real
    // profile, a quarter of the package, to sort rows the model can sort.
    expect(index.containsKey('chronology'), isFalse);
    // What it actually summarised survives, per section, in the manifest.
    final sections = envelope.manifest['sections']! as Map<String, Object?>;
    expect(
      (sections['measurements']! as Map)['earliest'],
      '2026-01-01T00:00:00.000Z',
    );
  });
}
