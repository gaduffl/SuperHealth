import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../data/health_repository.dart';
import 'ai_models.dart';

typedef HealthSnapshotLoader =
    Future<Map<String, Object?>> Function(String profileId);

enum HealthContextDelivery { inline, providerFile }

class HealthContextEnvelope {
  const HealthContextEnvelope({
    required this.json,
    required this.sha256,
    required this.fileSha256,
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

  /// SHA-256 of the exact UTF-8 JSON payload sent inline or as a file.
  final String fileSha256;
  final int byteLength;
  final int estimatedTokens;
  final int recordCount;
  final Map<String, Object?> manifest;
  final Map<String, String> sectionHashes;

  String get receiptInstruction =>
      'Context receipt: package_sha256=$sha256, file_sha256=$fileSha256, '
      'records=$recordCount. '
      'Treat the attention index as navigation only and verify claims against '
      'the complete raw ledger.';

  List<String> get sectionNames {
    final sections = manifest['sections'];
    if (sections is! Map) {
      return const [];
    }
    return sections.keys.map((key) => key.toString()).toList()..sort();
  }

  /// Section names and byte sizes, largest first, as `name=bytes` pairs.
  ///
  /// For diagnostics. The whole point of shrinking a context is knowing which
  /// section to shrink, and that is invisible from a single total.
  String largestSectionsDescription({int take = 8}) {
    final sections = manifest['sections'];
    if (sections is! Map) return '';
    final sized = <MapEntry<String, int>>[];
    for (final entry in sections.entries) {
      final value = entry.value;
      final bytes = value is Map ? value['bytes'] : null;
      if (bytes is int) sized.add(MapEntry(entry.key.toString(), bytes));
    }
    sized.sort((a, b) => b.value.compareTo(a.value));
    return sized
        .take(take)
        .map((entry) => '${entry.key}=${entry.value}')
        .join(', ');
  }

  String get coverageInstruction =>
      'Before answering, review every manifest section and verify material '
      'claims against raw_ledger. End with exactly one hidden receipt: '
      '<context_coverage>{"sha256":"$sha256","file_sha256":"$fileSha256",'
      '"record_count":$recordCount,"reviewed_sections":${jsonEncode(sectionNames)},'
      '"section_hashes":${jsonEncode(sectionHashes)}}</context_coverage>. '
      'Do not mention the receipt in the visible answer.';
}

/// Bytes per token for the dense JSON this app sends.
///
/// Not a guess: a 2,020,279-byte package measured 847,443 input tokens on a
/// real run, which is 2.38 bytes per token. Prose runs nearer 4, and the old
/// 3.5 estimate under-counted by 46% — enough that [HealthContextBuilder
/// .deliveryFor] passed a package as "inline" whose true size overshot the
/// working-room budget the check exists to defend.
///
/// Deliberately a little below the measurement, because the failure directions
/// are not symmetric: over-estimating routes to the lossless file path, while
/// under-estimating silently degrades answer quality near the context limit.
const jsonBytesPerToken = 2.3;

int estimatedJsonTokens(int byteLength) =>
    (byteLength / jsonBytesPerToken).ceil();

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
  /// [scope] decides how much of the record the built package carries. The
  /// advisor and the lab planner need different amounts, so each constructs
  /// its own builder rather than sharing one oversized context.
  HealthContextBuilder(
    HealthRepository repository, {
    HealthContextScope scope = HealthContextScope.labPlanning,
  }) : _loadSnapshot = ((profileId) =>
           repository.completeProfileSnapshot(profileId, scope: scope));

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

    _validateDeclaredCounts(source['manifest'], rawData, sections);
    final windows = _sourceWindows(source['manifest']);
    final attentionIndex = _attentionIndex(rawData);
    final stableCore = <String, Object?>{
      'schema': packageSchema,
      'schema_version': packageVersion,
      'active_profile_id': profileId,
      'source_schema': source['schema'],
      'source_schema_version': source['schema_version'],
      'source_exclusions': _sourceExclusions(source['manifest']),
      'source_windows': windows,
      'sections': sections,
      'attention_index': attentionIndex,
      'raw_ledger': rawData,
    };
    final digest = sha256
        .convert(utf8.encode(HealthRepository.stableJson(stableCore)))
        .toString();
    final manifest = <String, Object?>{
      // "Complete" has to mean what a reader would take it to mean. With a
      // windowed section it is only complete within the declared window, and
      // saying so plainly costs nothing next to a model that trusts the word.
      'complete': windows.isEmpty,
      'complete_within_declared_windows': true,
      // Still lossless: what is carried is carried verbatim. Windowing removes
      // rows; it never summarises or rewrites the ones that remain.
      'lossless': true,
      // Clinical evidence is isolated to the active profile. The supplement
      // catalog, inventory movements, and derived stock levels are deliberate
      // household-shared evidence so stock stays correct for shared use.
      'profile_isolated': false,
      'clinical_evidence_profile_isolated': true,
      'household_shared_supplement_inventory': true,
      'evidence_scope': {
        'clinical_evidence': 'active_profile_only',
        'supplement_catalog_and_inventory': 'household_shared',
        'inventory_movement_profile_id': 'provenance_only',
      },
      'record_count': recordCount,
      'section_count': sections.length,
      'sections': sections,
      'excluded': _sourceExclusions(source['manifest']),
      'windowed': windows,
      'integrity_algorithm': 'sha256',
      'context_sha256': digest,
    };
    final package = <String, Object?>{
      'schema': packageSchema,
      'schema_version': packageVersion,
      'generated_at': DateTime.now().toUtc().toIso8601String(),
      'active_profile_id': profileId,
      'coverage_contract': {
        // True only of the sections that are not windowed, which is why the
        // window list sits beside this claim rather than somewhere the model
        // might not read. A blanket "complete" over a windowed ledger is the
        // one way this package could actively mislead.
        'raw_ledger_is_complete': windows.isEmpty,
        'windowed_sections': windows,
        'attention_index_is_not_a_summary_replacement': true,
        'evidence_scope': {
          'clinical_evidence': 'active_profile_only',
          'supplement_catalog_and_inventory': 'household_shared',
          'inventory_movement_profile_id': 'provenance_only',
        },
        'required_reading_protocol': [
          'Check the manifest and its section counts before reasoning.',
          'Use attention_index to locate changes, mixed units, gaps, and links.',
          'Verify every material claim against raw_ledger source rows.',
          'Scan every manifest section for interactions and contradictions.',
          'Never infer that a record is absent without checking its section count.',
          if (windows.isNotEmpty)
            'Sections listed in windowed_sections carry only a recent slice. '
                'Read their stated replacement for anything older, and never '
                'treat the start of a window as the start of a behaviour.',
          'Treat inventory_movements as household stock provenance only. '
              'Only active-profile supplement_intakes establish this person\'s '
              'supplement intake.',
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
      fileSha256: sha256.convert(bytes).toString(),
      byteLength: bytes.length,
      estimatedTokens: estimatedJsonTokens(bytes.length),
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
    int? measuredContextTokens,
  }) {
    deliveryFor(
      context: context,
      capabilities: capabilities,
      maxOutputTokens: maxOutputTokens,
      promptReserveTokens: promptReserveTokens,
      additionalInputTokens: additionalInputTokens,
      measuredContextTokens: measuredContextTokens,
    );
  }

  HealthContextDelivery deliveryFor({
    required HealthContextEnvelope context,
    required ModelCapabilities capabilities,
    required int maxOutputTokens,
    int promptReserveTokens = 3000,
    int additionalInputTokens = 0,
    // An exact provider-side count when available; the local byte-based
    // estimate remains the fallback.
    int? measuredContextTokens,
  }) {
    final limit = capabilities.contextWindowTokens;
    if (limit == null) {
      throw StateError(
        'This model does not expose a documented context limit. The complete '
        'profile was not sent because SuperHealth cannot prove that it and '
        'the reserved working room would fit. '
        'Choose a model with documented long-context support.',
      );
    }
    final required =
        (measuredContextTokens ?? context.estimatedTokens) +
        additionalInputTokens +
        maxOutputTokens +
        promptReserveTokens;
    // Preserve substantial working room for reasoning and tool output instead
    // of filling the window until answer quality collapses near the hard limit.
    final inlineBudget = (limit * 0.72).floor();
    if (required <= inlineBudget) {
      return HealthContextDelivery.inline;
    }
    if (capabilities.losslessContextFile && capabilities.codeExecution) {
      return HealthContextDelivery.providerFile;
    }
    throw StateError(
      'The complete profile needs about $required tokens and would leave too '
      'little working context in this model ($limit tokens). No health data was '
      'truncated. Choose a larger-context model or one with lossless '
      'context-file analysis.',
    );
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
    if (value is! Map) {
      throw StateError('Health data is not an object.');
    }
    final result = <String, Object?>{};
    final entries = <MapEntry<String, Object?>>[];
    for (final entry in value.entries) {
      if (entry.key is! String) {
        throw StateError('Health data has a non-string section name.');
      }
      entries.add(MapEntry(entry.key as String, entry.value));
    }
    entries.sort((a, b) => a.key.compareTo(b.key));
    for (final entry in entries) {
      final key = entry.key;
      final section = entry.value;
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
      final entries = <MapEntry<String, Object?>>[];
      for (final entry in value.entries) {
        if (entry.key is! String) {
          throw StateError('Health data has a non-string object key.');
        }
        entries.add(MapEntry(entry.key as String, entry.value));
      }
      entries.sort((a, b) => a.key.compareTo(b.key));
      return <String, Object?>{
        for (final entry in entries) entry.key: _canonicalValue(entry.value),
      };
    }
    if (value is List) {
      return value.map(_canonicalValue).toList();
    }
    return value;
  }

  Map<String, Object?> _sectionMetadata(String name, Object? value) {
    final rows = value is List ? value : [value];
    final ids = <String>[];
    final units = <String>{};
    DateTime? earliest;
    DateTime? latest;
    for (final raw in rows) {
      if (raw is! Map) {
        continue;
      }
      final row = Map<String, Object?>.from(raw);
      final id = row['id']?.toString();
      if (id != null && id.isNotEmpty) {
        ids.add(id);
      }
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
      if (!seen.add(id)) {
        duplicateIds.add(id);
      }
    }
    if (duplicateIds.isNotEmpty) {
      throw StateError(
        'Context section $name contains duplicate record IDs: '
        '${duplicateIds.take(5).join(', ')}',
      );
    }
    final stable = HealthRepository.stableJson(value);
    final stableBytes = utf8.encode(stable);
    return {
      'records': rows.length,
      // Recorded so it is possible to answer "which section is the context"
      // from a diagnostic log, rather than guessing which one to shrink.
      'bytes': stableBytes.length,
      'sha256': sha256.convert(stableBytes).toString(),
      if (ids.isNotEmpty) 'record_ids': ids..sort(),
      if (earliest != null) 'earliest': earliest.toUtc().toIso8601String(),
      if (latest != null) 'latest': latest.toUtc().toIso8601String(),
      if (units.isNotEmpty) 'units': units.toList()..sort(),
    };
  }

  void _validateDeclaredCounts(
    Object? rawManifest,
    Map<String, Object?> rawData,
    Map<String, Object?> sections,
  ) {
    if (rawManifest is! Map || rawManifest['counts'] is! Map) {
      throw StateError('Repository did not provide section counts.');
    }
    final counts = rawManifest['counts']! as Map;
    for (final entry in rawData.entries) {
      if (entry.value is List && !counts.containsKey(entry.key)) {
        throw StateError(
          'Context completeness check failed: repository did not declare a '
          'count for ${entry.key}.',
        );
      }
    }
    for (final entry in counts.entries) {
      if (entry.key is! String || entry.value is! num) {
        throw StateError(
          'Context completeness check failed: a declared count is invalid.',
        );
      }
      final name = entry.key as String;
      final rawCount = entry.value as num;
      if (!rawCount.isFinite) {
        throw StateError(
          'Context completeness check failed: invalid declared count for '
          '$name.',
        );
      }
      final declared = rawCount.toInt();
      final section = sections[name];
      if (rawCount != declared || declared < 0 || section is! Map) {
        throw StateError(
          'Context completeness check failed: invalid declared count for '
          '$name.',
        );
      }
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

  /// Sections carried only for a bounded period, with the reason and the
  /// replacement for what falls outside.
  ///
  /// Carried verbatim into the package, because the reading protocol tells the
  /// model never to infer that a record is absent — a window it cannot see
  /// would turn that instruction into a lie.
  Map<String, Object?> _sourceWindows(Object? rawManifest) {
    if (rawManifest is! Map || rawManifest['windows'] is! Map) {
      return const {};
    }
    return Map<String, Object?>.from(rawManifest['windows']! as Map);
  }

  Map<String, Object?> _attentionIndex(Map<String, Object?> data) => {
    'latest_biomarkers': _latestBiomarkers(data),
    'supplement_exposure': _supplementExposure(data),
    'household_stock': _householdStock(data),
    'event_series': _eventSeries(data),
    'active_health_records': _activeHealthRecords(data),
    'chronology': _chronology(data),
    'data_quality_flags': _dataQualityFlags(data),
  };

  List<Map<String, Object?>> _householdStock(Map<String, Object?> data) {
    final movementIdsBySupplement = <String, List<String>>{};
    for (final movement in _mapRows(data['inventory_movements'])) {
      final supplementId = movement['supplement_id']?.toString();
      final movementId = movement['id']?.toString();
      if (supplementId == null || movementId == null || movementId.isEmpty) {
        continue;
      }
      movementIdsBySupplement
          .putIfAbsent(supplementId, () => [])
          .add(movementId);
    }

    final result = <Map<String, Object?>>[];
    for (final row in _mapRows(data['household_stock_levels'])) {
      final supplementId = row['supplement_id']?.toString();
      final id = row['id']?.toString();
      if (supplementId == null || id == null || id.isEmpty) {
        continue;
      }
      final currentUnits = (row['current_units'] as num?)?.toDouble();
      final threshold = (row['low_stock_threshold_units'] as num?)?.toDouble();
      final movementIds = List<String>.from(
        movementIdsBySupplement[supplementId] ?? const [],
      )..sort();
      result.add({
        'supplement_id': supplementId,
        'name': row['name']?.toString() ?? supplementId,
        'current_units': currentUnits,
        'stock_unit': row['stock_unit'],
        'low_stock_threshold_units': threshold,
        'is_low_stock':
            threshold != null &&
            currentUnits != null &&
            currentUnits <= threshold,
        'stock_record_ref': 'household_stock_levels:$id',
        'inventory_movement_record_refs': [
          for (final movementId in movementIds)
            'inventory_movements:$movementId',
        ],
        'inventory_movement_record_count': movementIds.length,
        'personal_intake_inference':
            'not_permitted; use active-profile supplement_intakes only',
      });
    }
    result.sort((a, b) {
      final byName = '${a['name']}'.compareTo('${b['name']}');
      return byName != 0
          ? byName
          : '${a['supplement_id']}'.compareTo('${b['supplement_id']}');
    });
    return result;
  }

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
      if (id != null) {
        names[id] = row['name']?.toString() ?? id;
      }
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
      if (row['status']?.toString() != 'active') {
        continue;
      }
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
          if (value == null || DateTime.tryParse(value.toString()) == null) {
            continue;
          }
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
    if (value is! List) {
      return const [];
    }
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
