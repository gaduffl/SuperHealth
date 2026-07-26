import 'dart:convert';

import 'package:csv/csv.dart';

import '../data/health_repository.dart';
import '../domain/entities.dart';

/// A portable, deliberately non-destructive representation of catalog ranges.
///
/// Imports resolve the owning biomarker before anything is written.  They never
/// carry a range id into the database, so importing a file cannot overwrite an
/// existing piece of evidence.
class BiomarkerRangeExchange {
  static const _columns = <String>[
    'range_id',
    'biomarker_id',
    'canonical_name',
    'display_name',
    'range_type',
    'sex',
    'age_min',
    'age_max',
    'low',
    'high',
    'optimal_low',
    'optimal_high',
    'unit',
    'evidence_label',
    'evidence_url',
    'notes',
  ];

  String exportJson(
    Iterable<BiomarkerReferenceRange> ranges,
    Iterable<Biomarker> biomarkers,
  ) => const JsonEncoder.withIndent('  ').convert({
    'schema': 'superhealth.biomarker_ranges',
    'schema_version': 1,
    'ranges': _rows(ranges, biomarkers),
  });

  String exportCsv(
    Iterable<BiomarkerReferenceRange> ranges,
    Iterable<Biomarker> biomarkers,
  ) {
    final rows = _rows(ranges, biomarkers);
    return const ListToCsvConverter().convert([
      _columns,
      for (final row in rows) [for (final column in _columns) row[column]],
    ]);
  }

  RangeImportPreview parse({
    required String text,
    required String extension,
    required Iterable<Biomarker> biomarkers,
    Iterable<BiomarkerReferenceRange> existingRanges = const [],
  }) {
    try {
      final rows = extension.toLowerCase() == 'json'
          ? _jsonRows(text)
          : extension.toLowerCase() == 'csv'
          ? _csvRows(text)
          : throw const FormatException('Choose a JSON or CSV range file.');
      return _resolve(
        rows,
        biomarkers.toList(growable: false),
        existingRanges.toList(growable: false),
      );
    } on FormatException catch (error) {
      return RangeImportPreview(
        records: const [],
        issues: [RangeImportIssue(row: 0, message: error.message.toString())],
      );
    } on Object catch (error) {
      return RangeImportPreview(
        records: const [],
        issues: [
          RangeImportIssue(row: 0, message: 'Could not read file: $error'),
        ],
      );
    }
  }

  List<Map<String, Object?>> _rows(
    Iterable<BiomarkerReferenceRange> ranges,
    Iterable<Biomarker> biomarkers,
  ) {
    final catalog = {
      for (final biomarker in biomarkers) biomarker.id: biomarker,
    };
    return [
      for (final range in ranges)
        {
          'range_id': range.id,
          'biomarker_id': range.biomarkerId,
          'canonical_name': catalog[range.biomarkerId]?.canonicalName ?? '',
          'display_name': catalog[range.biomarkerId]?.displayName ?? '',
          'range_type': range.rangeType,
          'sex': range.sex,
          'age_min': range.ageMin,
          'age_max': range.ageMax,
          'low': range.low,
          'high': range.high,
          'optimal_low': range.optimalLow,
          'optimal_high': range.optimalHigh,
          'unit': range.unit,
          'evidence_label': range.evidenceLabel,
          'evidence_url': range.evidenceUrl,
          'notes': range.notes,
        },
    ];
  }

  List<Map<String, Object?>> _jsonRows(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map ||
        decoded['schema'] != 'superhealth.biomarker_ranges' ||
        decoded['schema_version'] != 1) {
      throw const FormatException(
        'JSON must use schema superhealth.biomarker_ranges version 1.',
      );
    }
    final rawRows = decoded['ranges'];
    if (rawRows is! List) {
      throw const FormatException('JSON must contain a "ranges" list.');
    }
    return [
      for (final raw in rawRows)
        if (raw is Map)
          {for (final entry in raw.entries) '${entry.key}': entry.value}
        else
          throw const FormatException('Every JSON range must be an object.'),
    ];
  }

  List<Map<String, Object?>> _csvRows(String text) {
    final table = const CsvToListConverter(
      shouldParseNumbers: false,
    ).convert(text);
    if (table.isEmpty) throw const FormatException('The CSV file is empty.');
    final header = table.first
        .map((value) => '$value'.trim().toLowerCase())
        .toList();
    if (header.any((value) => value.isEmpty) ||
        header.toSet().length != header.length) {
      throw const FormatException('CSV headers must be unique and non-empty.');
    }
    if (!header.contains('range_type') || !header.contains('unit')) {
      throw const FormatException('CSV needs range_type and unit columns.');
    }
    return [
      for (final row in table.skip(1))
        {
          for (var index = 0; index < header.length; index++)
            header[index]: index < row.length ? row[index] : null,
        },
    ];
  }

  RangeImportPreview _resolve(
    List<Map<String, Object?>> rows,
    List<Biomarker> biomarkers,
    List<BiomarkerReferenceRange> existingRanges,
  ) {
    final records = <ImportedBiomarkerRange>[];
    final issues = <RangeImportIssue>[];
    final skipped = <RangeImportSkip>[];
    for (var index = 0; index < rows.length; index++) {
      final row = rows[index];
      try {
        final candidate = _record(row, biomarkers);
        if (existingRanges.any(candidate.matches) ||
            records.any(candidate.sameAs)) {
          skipped.add(
            RangeImportSkip(
              row: index + 1,
              record: candidate,
              message: 'An identical active range already exists.',
            ),
          );
        } else {
          records.add(candidate);
        }
      } on FormatException catch (error) {
        issues.add(
          RangeImportIssue(row: index + 1, message: error.message.toString()),
        );
      }
    }
    return RangeImportPreview(
      records: records,
      issues: issues,
      skipped: skipped,
    );
  }

  ImportedBiomarkerRange _record(
    Map<String, Object?> row,
    List<Biomarker> biomarkers,
  ) {
    final biomarker = _matchBiomarker(row, biomarkers);
    final rangeType = _required(row, 'range_type');
    final unit = _required(row, 'unit');
    final ageMin = _integer(row, 'age_min');
    final ageMax = _integer(row, 'age_max');
    final low = _number(row, 'low');
    final high = _number(row, 'high');
    final optimalLow = _number(row, 'optimal_low');
    final optimalHigh = _number(row, 'optimal_high');
    if (low == null &&
        high == null &&
        optimalLow == null &&
        optimalHigh == null) {
      throw const FormatException(
        'At least one reference or optimal bound is required.',
      );
    }
    if ((ageMin != null && (ageMin < 0 || ageMin > 150)) ||
        (ageMax != null && (ageMax < 0 || ageMax > 150))) {
      throw const FormatException('Ages must be between 0 and 150.');
    }
    _ordered('age', ageMin, ageMax);
    _ordered('reference bounds', low, high);
    _ordered('optimal bounds', optimalLow, optimalHigh);
    return ImportedBiomarkerRange(
      biomarkerId: biomarker.id,
      biomarkerName: biomarker.displayName,
      rangeType: rangeType,
      sex: _optional(row, 'sex'),
      ageMin: ageMin,
      ageMax: ageMax,
      low: low,
      high: high,
      optimalLow: optimalLow,
      optimalHigh: optimalHigh,
      unit: unit,
      evidenceLabel: _optional(row, 'evidence_label'),
      evidenceUrl: _httpUrl(_optional(row, 'evidence_url')),
      notes: _optional(row, 'notes') ?? '',
    );
  }

  Biomarker _matchBiomarker(Map<String, Object?> row, List<Biomarker> catalog) {
    final id = _optional(row, 'biomarker_id');
    final canonical = _optional(row, 'canonical_name');
    final display = _optional(row, 'display_name');
    if (id != null) {
      final byId = catalog.where((item) => item.id == id).toList();
      if (byId.isEmpty) {
        throw FormatException('No active catalog biomarker has id "$id".');
      }
      if (byId.length > 1) {
        throw FormatException('Ambiguous active catalog biomarker id "$id".');
      }
      if (!_identityAgrees(byId.single, canonical, display)) {
        throw const FormatException(
          'The supplied biomarker identity fields do not agree.',
        );
      }
      return byId.single;
    }
    final identity = canonical ?? display;
    if (identity == null) {
      throw const FormatException(
        'A biomarker_id, canonical_name, or display_name is required.',
      );
    }
    final matches = catalog
        .where((item) => _identityAgrees(item, canonical, display))
        .toList();
    if (matches.isEmpty) {
      throw FormatException('No catalog biomarker matches "$identity".');
    }
    if (matches.length > 1) {
      throw FormatException('Ambiguous biomarker match for "$identity".');
    }
    return matches.single;
  }

  bool _identityAgrees(Biomarker item, String? canonical, String? display) {
    final canonicalMatches =
        canonical == null ||
        item.canonicalName == HealthRepository.normalizeName(canonical);
    final displayMatches =
        display == null ||
        HealthRepository.normalizeName(item.displayName) ==
            HealthRepository.normalizeName(display) ||
        item.synonyms.any(
          (synonym) =>
              HealthRepository.normalizeName(synonym) ==
              HealthRepository.normalizeName(display),
        );
    return canonicalMatches && displayMatches;
  }

  String _required(Map<String, Object?> row, String field) {
    final value = _optional(row, field);
    if (value == null) throw FormatException('$field is required.');
    return value;
  }

  String? _optional(Map<String, Object?> row, String field) {
    final value = row[field]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  int? _integer(Map<String, Object?> row, String field) {
    final value = _optional(row, field);
    if (value == null) return null;
    final parsed = int.tryParse(value);
    if (parsed == null) throw FormatException('$field must be an integer.');
    return parsed;
  }

  double? _number(Map<String, Object?> row, String field) {
    final value = _optional(row, field);
    if (value == null) return null;
    final parsed = double.tryParse(value);
    if (parsed == null || !parsed.isFinite) {
      throw FormatException('$field must be a finite number.');
    }
    return parsed;
  }

  String? _httpUrl(String? value) {
    if (value == null) return null;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw const FormatException('evidence_url must be an http(s) URL.');
    }
    return value;
  }

  void _ordered(String label, num? low, num? high) {
    if (low != null && high != null && low > high) {
      throw FormatException('$label must be ordered low to high.');
    }
  }
}

class ImportedBiomarkerRange {
  const ImportedBiomarkerRange({
    required this.biomarkerId,
    required this.biomarkerName,
    required this.rangeType,
    required this.unit,
    required this.notes,
    this.sex,
    this.ageMin,
    this.ageMax,
    this.low,
    this.high,
    this.optimalLow,
    this.optimalHigh,
    this.evidenceLabel,
    this.evidenceUrl,
  });

  final String biomarkerId;
  final String biomarkerName;
  final String rangeType;
  final String? sex;
  final int? ageMin;
  final int? ageMax;
  final double? low;
  final double? high;
  final double? optimalLow;
  final double? optimalHigh;
  final String unit;
  final String? evidenceLabel;
  final String? evidenceUrl;
  final String notes;

  bool matches(BiomarkerReferenceRange existing) =>
      biomarkerId == existing.biomarkerId &&
      rangeType == existing.rangeType &&
      sex == existing.sex &&
      ageMin == existing.ageMin &&
      ageMax == existing.ageMax &&
      low == existing.low &&
      high == existing.high &&
      optimalLow == existing.optimalLow &&
      optimalHigh == existing.optimalHigh &&
      unit == existing.unit &&
      evidenceLabel == existing.evidenceLabel &&
      evidenceUrl == existing.evidenceUrl &&
      notes == existing.notes;

  bool sameAs(ImportedBiomarkerRange other) =>
      biomarkerId == other.biomarkerId &&
      rangeType == other.rangeType &&
      sex == other.sex &&
      ageMin == other.ageMin &&
      ageMax == other.ageMax &&
      low == other.low &&
      high == other.high &&
      optimalLow == other.optimalLow &&
      optimalHigh == other.optimalHigh &&
      unit == other.unit &&
      evidenceLabel == other.evidenceLabel &&
      evidenceUrl == other.evidenceUrl &&
      notes == other.notes;
}

class RangeImportIssue {
  const RangeImportIssue({required this.row, required this.message});

  final int row;
  final String message;
}

class RangeImportPreview {
  const RangeImportPreview({
    required this.records,
    required this.issues,
    this.skipped = const [],
  });

  final List<ImportedBiomarkerRange> records;
  final List<RangeImportIssue> issues;
  final List<RangeImportSkip> skipped;

  bool get canImport => records.isNotEmpty && issues.isEmpty;
}

class RangeImportSkip {
  const RangeImportSkip({
    required this.row,
    required this.record,
    required this.message,
  });

  final int row;
  final ImportedBiomarkerRange record;
  final String message;
}
