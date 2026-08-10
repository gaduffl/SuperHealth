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

  /// Sections that are reference data rather than this person's record.
  ///
  /// Identical across runs, across days, and across profiles on one device.
  /// These are the snapshot's own section names — see
  /// `completeProfileSnapshot`. Getting one wrong is not a small mistake: the
  /// fingerprint would silently collapse, so [catalogFingerprintOf] refuses to
  /// produce one rather than return a constant.
  static const invariantSections = {'biomarker_catalog', 'biomarker_ranges'};

  /// A fingerprint of the reference data alone.
  ///
  /// Used to route prompt caching, in place of the whole-context hash: that
  /// changes whenever any record changes, so every run would land on a fresh
  /// cache node and could never reuse the catalog the previous run prefilled.
  ///
  /// Routing is necessary but not sufficient. Draft and verify inside one run
  /// can never share a cache — their structured-output schemas differ, and the
  /// schema is a prefix to the system message, so the two prefixes diverge at
  /// position zero. Cross-run is the only win available, and it also needs the
  /// invariant data to *lead* the payload, which today it does not: `stableJson`
  /// sorts keys, so the volatile `attention_index` precedes `raw_ledger` and
  /// caps the shared prefix within the first few hundred bytes. Quantising
  /// `generated_at` to the day removed one cause of divergence, not the last.
  String get catalogFingerprint =>
      catalogFingerprintOf(sectionHashes) ?? sha256;

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
      '"record_count":$recordCount,'
      '"reviewed_sections":${jsonEncode(sectionNames)}}</context_coverage>. '
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

/// The package's generation date, as `YYYY-MM-DD` in UTC.
///
/// Quantised so that two runs on the same day produce a byte-identical payload
/// and can share a provider-side prompt cache. A full timestamp bought nothing
/// — nothing reasons about the minute a snapshot was taken — and cost a cold
/// prefill of the whole context on every run.
String packageDateFor(DateTime now) {
  final utc = now.toUtc();
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  return '${utc.year}-$month-$day';
}

/// Hashes the invariant sections into one stable routing key, or null when
/// none of them are present.
///
/// Null rather than a fingerprint over absences, because a constant is the one
/// genuinely dangerous answer here: every profile and every catalog state would
/// share a single cache key, and a stale prefix could serve a plan. The caller
/// falls back to the whole-context hash, which is merely less cacheable.
///
/// Top level because `HealthContextEnvelope` has its own `sha256` field, which
/// shadows the crypto library's inside the class.
String? catalogFingerprintOf(Map<String, String> sectionHashes) {
  final parts = [
    for (final name in HealthContextEnvelope.invariantSections.toList()..sort())
      if (sectionHashes[name] != null) '$name=${sectionHashes[name]}',
  ];
  if (parts.isEmpty) return null;
  return sha256.convert(utf8.encode(parts.join(' '))).toString();
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

    final rawData = _canonicalData(source['data'], profileId);
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
    final summaries = _sourceSummaries(source['manifest']);
    final attentionIndex = _attentionIndex(rawData);
    final stableCore = <String, Object?>{
      'schema': packageSchema,
      'schema_version': packageVersion,
      'active_profile_id': profileId,
      'source_schema': source['schema'],
      'source_schema_version': source['schema_version'],
      'source_exclusions': _sourceExclusions(source['manifest']),
      'source_windows': windows,
      'source_summaries': summaries,
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
      // Lossless means what is carried is carried verbatim. Windowing removes
      // rows and declares it; that leaves the survivors untouched. A *summary*
      // does not — it keeps every record but stops carrying it row by row — so
      // the claim has to be withdrawn the moment one is present, or the word
      // is a lie in exactly the case a reader would rely on it.
      'lossless': summaries.isEmpty,
      'summarised': summaries,
      'lossless_outside_declared_summaries': true,
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
      // The UTC *date*, not the instant. The model needs this — how old a
      // result is decides whether to re-order the test — but a timestamp that
      // moves every build changes the payload every build, and OpenAI caches
      // the longest matching prefix. `generated_at` sorts ahead of
      // `raw_ledger`, so a fresh instant here made every run a guaranteed cache
      // miss on the entire ~600k-token context. To the day is precise enough
      // for reasoning about result age and byte-identical across a day's runs.
      'generated_at': packageDateFor(DateTime.now()),
      'active_profile_id': profileId,
      'coverage_contract': {
        // True only of the sections that are not windowed, which is why the
        // window list sits beside this claim rather than somewhere the model
        // might not read. A blanket "complete" over a windowed ledger is the
        // one way this package could actively mislead.
        'raw_ledger_is_complete': windows.isEmpty,
        'windowed_sections': windows,
        // A summarised section is still complete coverage — no record is
        // missing — but it is no longer verbatim, and the two are different
        // promises.
        'summarised_sections': summaries,
        'attention_index_is_not_a_summary_replacement': true,
        // Absence has to be unambiguous. Every omission below is a rule about
        // *encoding*, never about evidence, and stating them is what keeps
        // "never infer that a record is absent" true after the trimming.
        'row_encoding': {
          'omitted_when_empty':
              'A key whose value would be null, an empty string, or an empty '
              'JSON list/object is omitted from the row. An absent key means '
              '"nothing recorded", exactly as an explicit null did.',
          'omitted_always': _omittedRowKeysDescription,
          'profile_id':
              'Omitted where it equals active_profile_id, which is every '
              'clinical row. Present only where it differs, and there it is '
              'provenance for household-shared data.',
          'numbers_are_never_omitted':
              'A zero dose, score or value is a recorded observation and is '
              'always carried.',
        },
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
          if (summaries.isNotEmpty)
            'Sections listed in summarised_sections account for every record '
                'in their period, at the stated grain. Nothing is missing '
                'there, so counts and totals from them are exact — but the '
                'detail named under "loses" is genuinely gone, so do not '
                'assert anything that would need it.',
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

  /// Columns a row carries for the database's benefit, not the reader's.
  ///
  /// `created_at` and `updated_at` record when a row was written or corrected,
  /// which is never the clinical date — every section that has one carries
  /// `taken_at`, `observed_at`, `document_date` or `start_date` instead.
  /// `deleted` is 0 on every carried row, because the queries filter on it.
  /// `color_value` is the colour a tag is drawn in. Together they were 23% of
  /// the advisor's package on a real profile.
  static const omittedRowKeys = {
    'created_at',
    'updated_at',
    'deleted',
    'color_value',
  };

  static const _omittedRowKeysDescription =
      'created_at and updated_at (when the row was written or corrected, '
      'never the clinical date — read taken_at, observed_at, document_date or '
      'start_date), deleted (0 on every carried row; deleted rows are not '
      'sent at all), and color_value (display only).';

  Map<String, Object?> _canonicalData(Object? value, String profileId) {
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
        final rows = section
            .map((row) => _leanValue(_canonicalValue(row), profileId))
            .toList();
        rows.sort(
          (a, b) => HealthRepository.stableJson(
            a,
          ).compareTo(HealthRepository.stableJson(b)),
        );
        result[key] = rows;
      } else {
        result[key] = _leanValue(_canonicalValue(section), profileId);
      }
    }
    return result;
  }

  /// Drops what a row says twice, or does not say at all.
  ///
  /// Three rules, each lossless in what the reader can conclude:
  ///  * a key whose value is null or an empty string/list/object states
  ///    nothing — `"lab_ref_high":null` and an absent `lab_ref_high` mean the
  ///    same thing, and the coverage contract says so explicitly;
  ///  * [omittedRowKeys] are database bookkeeping;
  ///  * `profile_id` repeats `active_profile_id` on every clinical row — 36
  ///    characters times every record. It is kept where it *differs*, because
  ///    on a household-shared row it is real provenance.
  ///
  /// Worth 31% of the advisor's package before anything is summarised, which
  /// is more than any single section except the dose ledger.
  Object? _leanValue(Object? value, String profileId) {
    if (value is List) {
      return value.map((item) => _leanValue(item, profileId)).toList();
    }
    if (value is! Map<String, Object?>) return value;
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (omittedRowKeys.contains(entry.key)) continue;
      if (entry.key == 'profile_id' && entry.value == profileId) continue;
      final lean = _leanValue(entry.value, profileId);
      if (_statesNothing(lean)) continue;
      result[entry.key] = lean;
    }
    return result;
  }

  /// Whether a value carries no information a missing key would not.
  ///
  /// Numbers are never empty — a `0` dose and an absent dose are different
  /// facts, and a `score: 0` is a recorded observation. `[]` and `{}` as
  /// *strings* count, because several columns hold JSON in a TEXT field
  /// (`ingredients_json`, `flags_json`, `synonyms_json`) and an empty one there
  /// is the same "nothing recorded" as an absent key.
  static bool _statesNothing(Object? value) {
    if (value == null) return true;
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty || trimmed == '[]' || trimmed == '{}';
    }
    return (value is Iterable && value.isEmpty) ||
        (value is Map && value.isEmpty);
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
      // No `record_ids` here. Every one of those ids is already in the row it
      // belongs to, so listing them again shipped ~113 KB — roughly 48k tokens
      // on a real profile — of pure duplication in every call. The manifest's
      // job is to prove what was supplied, and a count plus a content hash
      // does that completely; an id list adds nothing the hash does not
      // already cover. `ids` is still collected above, to reject duplicates.
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

  /// Sections that cover every record but no longer carry them one by one.
  ///
  /// Separate from [_sourceWindows] because they make different promises. A
  /// window says "rows before this date are not here"; a summary says "every
  /// row is accounted for, at a coarser grain, and here is what that grain
  /// drops". Conflating them would let the package keep calling itself
  /// lossless while shipping aggregates.
  Map<String, Object?> _sourceSummaries(Object? rawManifest) {
    if (rawManifest is! Map || rawManifest['summaries'] is! Map) {
      return const {};
    }
    return Map<String, Object?>.from(rawManifest['summaries']! as Map);
  }

  /// Derived navigation over the ledger — never a replacement for it.
  ///
  /// There is no `chronology` here any more. It listed one entry per record —
  /// `{at, section, record_ref, date_field}` — and every one of those four
  /// values was already in the row it pointed at. On a real profile that was
  /// 446 KB, a quarter of the whole package, to sort rows the model can sort
  /// itself; the per-section date range it summarised is in `manifest.sections`
  /// as `earliest`/`latest`. It was the `record_ids` mistake again, four times
  /// the size.
  Map<String, Object?> _attentionIndex(Map<String, Object?> data) => {
    'latest_biomarkers': _latestBiomarkers(data),
    'supplement_exposure': _supplementExposure(data),
    'household_stock': _householdStock(data),
    'event_series': _eventSeries(data),
    'active_health_records': _activeHealthRecords(data),
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

  /// Per-supplement exposure, labelled by which part of the ledger it counts.
  ///
  /// The dose rows are windowed for both callers, so the counts derived from
  /// them describe the window and nothing else. Naming them `carried_*` and
  /// putting the whole-ledger figures beside them under `ledger_*` is the
  /// difference between "started three weeks ago" and "the ledger only goes
  /// back three weeks here" — which is exactly the confusion a window creates
  /// and the one this index existed to prevent.
  List<Map<String, Object?>> _supplementExposure(Map<String, Object?> data) {
    final names = <String, String>{};
    for (final row in _mapRows(data['supplements'])) {
      final id = row['id']?.toString();
      if (id != null) {
        names[id] = row['name']?.toString() ?? id;
      }
    }
    final history = <String, Map<String, Object?>>{
      for (final row in _mapRows(data['supplement_intake_history']))
        '${row['supplement_id']}': row,
    };
    final weeklyBySupplement = <String, List<Map<String, Object?>>>{};
    for (final row in _mapRows(data['supplement_intakes_weekly'])) {
      weeklyBySupplement
          .putIfAbsent('${row['supplement_id']}', () => [])
          .add(row);
    }
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in _mapRows(data['supplement_intakes'])) {
      final id = row['supplement_id']?.toString() ?? 'unknown';
      grouped.putIfAbsent(id, () => []).add(row);
    }
    final ids = <String>{...grouped.keys, ...history.keys}..remove('null');
    final result = <Map<String, Object?>>[];
    for (final id in ids) {
      final rows = (grouped[id] ?? <Map<String, Object?>>[])
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
      final ledger = history[id];
      final weeks = weeklyBySupplement[id] ?? const <Map<String, Object?>>[];
      result.add({
        'supplement_id': id,
        'name': names[id] ?? id,
        'carried_intake_record_count': rows.length,
        'carried_skipped_count': skipped,
        if (rows.isNotEmpty) 'carried_first_at': rows.first['taken_at'],
        if (rows.isNotEmpty) 'carried_latest_at': rows.last['taken_at'],
        'carried_dose_totals_by_reported_unit': totals,
        if (weeks.isNotEmpty) 'summarised_week_count': weeks.length,
        // From `supplement_intake_history`, which spans the entire ledger
        // regardless of any window. These are the numbers to answer "how long
        // has this been taken" with.
        if (ledger != null) ...{
          'ledger_first_dose_at': ledger['first_dose_at'],
          'ledger_last_dose_at': ledger['last_dose_at'],
          'ledger_dose_count': ledger['dose_count'],
          'ledger_skipped_count': ledger['skipped_count'],
        },
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
