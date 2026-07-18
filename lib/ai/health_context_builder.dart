import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/health_repository.dart';
import 'ai_models.dart';

typedef HealthSnapshotLoader =
    Future<Map<String, Object?>> Function(String profileId);

class HealthContextEnvelope {
  const HealthContextEnvelope({
    required this.json,
    required this.sha256,
    required this.byteLength,
    required this.estimatedTokens,
    required this.recordCount,
    required this.manifest,
    required this.sectionHashes,
  });

  /// The complete, lossless health evidence package. Nothing in the source
  /// snapshot is removed or replaced by a summary.
  final String json;
  final String sha256;
  final int byteLength;
  final int estimatedTokens;
  final int recordCount;
  final Map<String, Object?> manifest;
  final Map<String, String> sectionHashes;

  String get receiptInstruction =>
      'Context receipt: sha256=$sha256, records=$recordCount. '
      'Treat the attention index as navigation only and verify claims against '
      'the complete raw ledger.';
}

/// Builds a layered, lossless package instead of pasting an unstructured
/// database dump into the prompt.
///
/// The package contains:
///  * a count/hash/date/unit manifest that proves what was supplied;
///  * deterministic attention indexes that make longitudinal changes visible;
///  * a complete canonical raw ledger for verification and code execution.
///
/// The indexes never substitute for source rows. If the package cannot fit a
/// model and no lossless provider-file path is available, the request fails.
class HealthContextBuilder {
  HealthContextBuilder(HealthRepository repository)
    : _loadSnapshot = repository.completeProfileSnapshot;

  HealthContextBuilder.fromLoader(HealthSnapshotLoader loader)
    : _loadSnapshot = loader;

  final HealthSnapshotLoader _loadSnapshot;

  static const packageSchema = 'superhealth.health_evidence_package';
  static const packageVersion = 2;

  Future<HealthContextEnvelope> build(String profileId) async {
    final source = await _loadSnapshot(profileId);
    _validateSource(source, profileId);

    final rawData = _canonicalData(source['data']);
    final sections = <String, Object?>{};
    final sectionHashes = <String, String>{};
    var recordCount = 0;
    for (final entry in rawData.entries) {
      final metadata = _sectionMetadata(entry.key, entry.value);
      sections[entry.key] = metadata;
      sectionHashes[entry.key] = metadata['sha256']! as String;
      recordCount += metadata['records']! as int;
    }

    _validateDeclaredCounts(source['manifest'], sections);
    final attentionIndex = _attentionIndex(rawData);
    final stableCore = <String, Object?>{
      'schema': packageSchema,
      'schema_version': packageVersion,
      'active_profile_id': profileId,
      'source_schema': source['schema'],
      'source_schema_version': source['schema_version'],
      'source_exclusions': _sourceExclusions(source['manifest']),
      'sections': sections,
      'attention_index': attentionIndex,
      'raw_ledger': rawData,
    };
    final digest = sha256
        .convert(utf8.encode(HealthRepository.stableJson(stableCore)))
        .toString();
    final manifest = <String, Object?>{
      'complete': true,
      'lossless': true,
      'profile_isolated': true,
      'record_count': recordCount,
      'section_count': sections.length,
      'sections': sections,
      'excluded': _sourceExclusions(source['manifest']),
      'integrity_algorithm': 'sha256',
      'context_sha256': digest,
    };
    final package = <String, Object?>{
      'schema': packageSchema,
      'schema_version': packageVersion,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'active_profile_id': profileId,
      'coverage_contract': {
        'raw_ledger_is_complete': true,
        'attention_index_is_not_a_summary_replacement': true,
        'required_reading_protocol': [
          'Check the manifest and its section counts before reasoning.',
          'Use attention_index to locate changes, mixed units, gaps, and links.',
          'Verify every material claim against raw_ledger source rows.',
          'Scan every manifest section for interactions and contradictions.',
          'Never infer that a record is absent without checking its section count.',
          'Reference source rows as section:id when explaining important findings.',
        ],
      },
      'manifest': manifest,
      'attention_index': attentionIndex,
      'raw_ledger': rawData,
    };
    final json = HealthRepository.stableJson(package);
    final bytes = utf8.encode(json);
    return HealthContextEnvelope(
      json: json,
      sha256: digest,
      byteLength: bytes.length,
      // A conservative display estimate. Providers remain authoritative.
      estimatedTokens: (bytes.length / 3.5).ceil(),
      recordCount: recordCount,
      manifest: manifest,
      sectionHashes: sectionHashes,
    );
  }

  void ensureFits({
    required HealthContextEnvelope context,
    required ModelCapabilities capabilities,
    required int maxOutputTokens,
    int promptReserveTokens = 3000,
    int additionalInputTokens = 0,
  }) {
    final limit = capabilities.contextWindowTokens;
    if (limit == null) return;
    final required =
        context.estimatedTokens +
        additionalInputTokens +
        maxOutputTokens +
        promptReserveTokens;
    if (required > limit) {
      throw StateError(
        'The complete profile needs about $required tokens but this model has a '
        '$limit-token context window. No health data was truncated. Choose a '
        'larger-context model or a model with lossless context-file analysis.',
      );
    }
  }

  void _validateSource(Map<String, Object?> source, String profileId) {
    if (source['active_profile_id'] != profileId) {
      throw StateError('Health context returned the wrong active profile.');
    }
    final manifest = source['manifest'];
    if (manifest is! Map || manifest['complete'] != true) {
      throw StateError(
        'Repository did not declare a complete health snapshot.',
      );
    }
    if (source['data'] is! Map) {
      throw StateError('Repository returned no health data map.');
    }
  }

  Map<String, Object?> _canonicalData(Object? value) {
    if (value is! Map) throw StateError('Health data is not an object.');
    final result = <String, Object?>{};
    final keys = value.keys.map((key) => '$key').toList()..sort();
    for (final key in keys) {
      final section = value[key];
      if (section is List) {
        final rows = section.map(_canonicalValue).toList();
        rows.sort(
          (a, b) => HealthRepository.stableJson(
            a,
          ).compareTo(HealthRepository.stableJson(b)),
        );
        result[key] = rows;
      } else {
        result[key] = _canonicalValue(section);
      }
    }
    return result;
  }

  Object? _canonicalValue(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return <String, Object?>{
        for (final key in keys) key: _canonicalValue(value[key]),
      };
    }
    if (value is List) return value.map(_canonicalValue).toList();
    return value;
  }

  Map<String, Object?> _sectionMetadata(String name, Object? value) {
    final rows = value is List ? value : [value];
    final ids = <String>[];
    final units = <String>{};
    DateTime? earliest;
    DateTime? latest;
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = Map<String, Object?>.from(raw);
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty) ids.add(id);
      for (final entry in row.entries) {
        final key = entry.key.toLowerCase();
        final text = entry.value?.toString().trim();
        if (key.contains('unit') && text != null && text.isNotEmpty) {
          units.add(text);
        }
        if (_dateKeys.contains(key) && text != null) {
          final parsed = DateTime.tryParse(text);
          if (parsed != null) {
            earliest = earliest == null || parsed.isBefore(earliest)
                ? parsed
                : earliest;
            latest = latest == null || parsed.isAfter(latest) ? parsed : latest;
          }
        }
      }
    }
    final duplicateIds = <String>[];
    final seen = <String>{};
    for (final id in ids) {
      if (!seen.add(id)) duplicateIds.add(id);
    }
    if (duplicateIds.isNotEmpty) {
      throw StateError(
        'Context section $name contains duplicate record IDs: '
        '${duplicateIds.take(5).join(', ')}',
      );
    }
    final stable = HealthRepository.stableJson(value);
    return {
      'records': rows.length,
      'sha256': sha256.convert(utf8.encode(stable)).toString(),
      if (ids.isNotEmpty) 'record_ids': ids..sort(),
      if (earliest != null) 'earliest': earliest.toUtc().toIso8601String(),
      if (latest != null) 'latest': latest.toUtc().toIso8601String(),
      if (units.isNotEmpty) 'units': units.toList()..sort(),
    };
  }

  void _validateDeclaredCounts(
    Object? rawManifest,
    Map<String, Object?> sections,
  ) {
    if (rawManifest is! Map || rawManifest['counts'] is! Map) return;
    final counts = rawManifest['counts']! as Map;
    for (final entry in counts.entries) {
      final name = entry.key.toString();
      final declared = (entry.value as num?)?.toInt();
      final section = sections[name];
      if (declared == null || section is! Map) continue;
      final actual = (section['records'] as num?)?.toInt();
      if (actual != declared) {
        throw StateError(
          'Context completeness check failed for $name: repository declared '
          '$declared records but supplied $actual.',
        );
      }
    }
  }

  List<Object?> _sourceExclusions(Object? rawManifest) {
    if (rawManifest is! Map || rawManifest['excluded'] is! List) {
      return const [];
    }
    return List<Object?>.from(rawManifest['excluded']! as List);
  }

  Map<String, Object?> _attentionIndex(Map<String, Object?> data) => {
    'latest_biomarkers': _latestBiomarkers(data),
    'supplement_exposure': _supplementExposure(data),
    'event_series': _eventSeries(data),
    'active_health_records': _activeHealthRecords(data),
    'chronology': _chronology(data),
    'data_quality_flags': _dataQualityFlags(data),
  };

  List<Map<String, Object?>> _latestBiomarkers(Map<String, Object?> data) {
    final catalog = <String, String>{};
    for (final row in _mapRows(data['biomarker_catalog'])) {
      final id = row['id']?.toString();
      if (id != null) {
        catalog[id] = row['display_name']?.toString() ?? id;
      }
    }
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in _mapRows(data['measurements'])) {
      final id = row['biomarker_id']?.toString() ?? 'unknown';
      grouped.putIfAbsent(id, () => []).add(row);
    }
    final result = <Map<String, Object?>>[];
    for (final entry in grouped.entries) {
      final rows = entry.value
        ..sort(
          (a, b) => _dateOf(a, 'taken_at').compareTo(_dateOf(b, 'taken_at')),
        );
      final latest = rows.last;
      final previous = rows.length > 1 ? rows[rows.length - 2] : null;
      final units =
          rows
              .map((row) => row['unit_reported']?.toString())
              .whereType<String>()
              .toSet()
              .toList()
            ..sort();
      result.add({
        'biomarker_id': entry.key,
        'name': catalog[entry.key] ?? entry.key,
        'measurement_count': rows.length,
        'first_taken_at': rows.first['taken_at'],
        'latest_taken_at': latest['taken_at'],
        'latest_value': latest['canonical_value'] ?? latest['value'],
        'latest_unit': latest['canonical_unit'] ?? latest['unit_reported'],
        'latest_reported_value': latest['value'],
        'latest_reported_unit': latest['unit_reported'],
        'previous_value': previous?['canonical_value'] ?? previous?['value'],
        'previous_unit':
            previous?['canonical_unit'] ?? previous?['unit_reported'],
        'previous_reported_value': previous?['value'],
        'previous_reported_unit': previous?['unit_reported'],
        'reported_units_seen': units,
        'canonical_units_seen':
            rows
                .map((row) => row['canonical_unit']?.toString())
                .whereType<String>()
                .toSet()
                .toList()
              ..sort(),
        'comparison_ready': rows.every((row) => row['canonical_value'] != null),
        'latest_record_ref': 'measurements:${latest['id']}',
      });
    }
    result.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return result;
  }

  List<Map<String, Object?>> _supplementExposure(Map<String, Object?> data) {
    final names = <String, String>{};
    for (final row in _mapRows(data['supplements'])) {
      final id = row['id']?.toString();
      if (id != null) names[id] = row['name']?.toString() ?? id;
    }
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in _mapRows(data['supplement_intakes'])) {
      final id = row['supplement_id']?.toString() ?? 'unknown';
      grouped.putIfAbsent(id, () => []).add(row);
    }
    final result = <Map<String, Object?>>[];
    for (final entry in grouped.entries) {
      final rows = entry.value
        ..sort(
          (a, b) => _dateOf(a, 'taken_at').compareTo(_dateOf(b, 'taken_at')),
        );
      final totals = <String, double>{};
      var skipped = 0;
      for (final row in rows) {
        if (row['skipped'] == 1 || row['skipped'] == true) {
          skipped++;
          continue;
        }
        final unit = row['unit']?.toString() ?? 'unspecified';
        totals[unit] =
            (totals[unit] ?? 0) + ((row['dose'] as num?)?.toDouble() ?? 0);
      }
      result.add({
        'supplement_id': entry.key,
        'name': names[entry.key] ?? entry.key,
        'intake_record_count': rows.length,
        'skipped_count': skipped,
        'first_recorded_at': rows.first['taken_at'],
        'latest_recorded_at': rows.last['taken_at'],
        'dose_totals_by_reported_unit': totals,
      });
    }
    result.sort((a, b) => '${a['name']}'.compareTo('${b['name']}'));
    return result;
  }

  List<Map<String, Object?>> _eventSeries(Map<String, Object?> data) {
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in _mapRows(data['health_events'])) {
      final key = '${row['kind']}:${row['name']}';
      grouped.putIfAbsent(key, () => []).add(row);
    }
    final result = <Map<String, Object?>>[];
    for (final entry in grouped.entries) {
      final rows = entry.value
        ..sort(
          (a, b) =>
              _dateOf(a, 'observed_at').compareTo(_dateOf(b, 'observed_at')),
        );
      final scores = rows.map((row) => row['score']).whereType<num>().toList();
      final values = rows
          .map((row) => row['numeric_value'])
          .whereType<num>()
          .toList();
      result.add({
        'series': entry.key,
        'record_count': rows.length,
        'first_observed_at': rows.first['observed_at'],
        'latest_observed_at': rows.last['observed_at'],
        if (scores.isNotEmpty)
          'mean_score':
              scores.fold<double>(0, (sum, value) => sum + value.toDouble()) /
              scores.length,
        if (values.isNotEmpty)
          'mean_numeric_value':
              values.fold<double>(0, (sum, value) => sum + value.toDouble()) /
              values.length,
        'units_seen':
            rows
                .map((row) => row['unit']?.toString())
                .whereType<String>()
                .toSet()
                .toList()
              ..sort(),
      });
    }
    result.sort((a, b) => '${a['series']}'.compareTo('${b['series']}'));
    return result;
  }

  Map<String, List<Map<String, Object?>>> _activeHealthRecords(
    Map<String, Object?> data,
  ) {
    final result = <String, List<Map<String, Object?>>>{};
    for (final row in _mapRows(data['conditions_medications_goals_history'])) {
      if (row['status']?.toString() != 'active') continue;
      final kind = row['kind']?.toString() ?? 'other';
      result.putIfAbsent(kind, () => []).add(row);
    }
    return result;
  }

  List<Map<String, Object?>> _chronology(Map<String, Object?> data) {
    final result = <Map<String, Object?>>[];
    for (final entry in data.entries) {
      for (final row in _mapRows(entry.value)) {
        for (final dateKey in _dateKeys) {
          final value = row[dateKey];
          if (value == null || DateTime.tryParse(value.toString()) == null)
            continue;
          result.add({
            'at': value,
            'section': entry.key,
            'record_ref': '${entry.key}:${row['id'] ?? 'no-id'}',
            'date_field': dateKey,
          });
          break;
        }
      }
    }
    result.sort((a, b) => '${a['at']}'.compareTo('${b['at']}'));
    return result;
  }

  List<Map<String, Object?>> _dataQualityFlags(Map<String, Object?> data) {
    final flags = <Map<String, Object?>>[];
    final unitsByBiomarker = <String, Set<String>>{};
    final canonicalUnitsByBiomarker = <String, Set<String>>{};
    final unresolvedByBiomarker = <String, int>{};
    for (final row in _mapRows(data['measurements'])) {
      final id = row['biomarker_id']?.toString() ?? 'unknown';
      final unit = row['unit_reported']?.toString().trim();
      if (unit != null && unit.isNotEmpty) {
        unitsByBiomarker.putIfAbsent(id, () => {}).add(unit);
      }
      final canonicalUnit = row['canonical_unit']?.toString().trim();
      if (canonicalUnit != null &&
          canonicalUnit.isNotEmpty &&
          row['canonical_value'] != null) {
        canonicalUnitsByBiomarker.putIfAbsent(id, () => {}).add(canonicalUnit);
      } else {
        unresolvedByBiomarker[id] = (unresolvedByBiomarker[id] ?? 0) + 1;
      }
    }
    for (final entry in unitsByBiomarker.entries) {
      if (entry.value.length > 1) {
        final canonicalUnits = canonicalUnitsByBiomarker[entry.key] ?? const {};
        final unresolved = unresolvedByBiomarker[entry.key] ?? 0;
        flags.add({
          'type': canonicalUnits.length == 1 && unresolved == 0
              ? 'mixed_reported_units_normalized'
              : 'mixed_biomarker_units_unresolved',
          'biomarker_id': entry.key,
          'reported_units': entry.value.toList()..sort(),
          'canonical_units': canonicalUnits.toList()..sort(),
          'unresolved_measurements': unresolved,
          'instruction': canonicalUnits.length == 1 && unresolved == 0
              ? 'Compare canonical values and retain reported values as evidence.'
              : 'Do not compare unresolved numeric values across units.',
        });
      }
    }
    final normalizedEvents = <String, Set<String>>{};
    for (final row in _mapRows(data['health_events'])) {
      final name = row['name']?.toString() ?? '';
      final key = '${row['kind']}:${HealthRepository.normalizeName(name)}';
      normalizedEvents.putIfAbsent(key, () => {}).add(name);
    }
    for (final entry in normalizedEvents.entries) {
      if (entry.value.length > 1) {
        flags.add({
          'type': 'event_name_variants',
          'normalized_series': entry.key,
          'names': entry.value.toList()..sort(),
        });
      }
    }
    return flags;
  }

  List<Map<String, Object?>> _mapRows(Object? value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((row) => Map<String, Object?>.from(row))
        .toList();
  }

  DateTime _dateOf(Map<String, Object?> row, String key) =>
      DateTime.tryParse(row[key]?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  static const _dateKeys = <String>{
    'taken_at',
    'observed_at',
    'document_date',
    'planned_for',
    'target_date',
    'start_date',
    'end_date',
    'parsed_at',
    'price_checked_at',
    'created_at',
    'updated_at',
  };
}
