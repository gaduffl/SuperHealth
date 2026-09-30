import 'dart:convert';

import '../analysis/exposure_analysis.dart';
import '../domain/entities.dart';
import '../domain/name_matching.dart';
import '../domain/substance_catalog.dart';
import 'agent_snapshot.dart';
import 'ai_models.dart';
import 'clinical_digest.dart';

/// Read-only functions the advisor can call to look past the digest.
///
/// They answer from the parsed snapshot held on the device — never from the
/// database, and never by writing — so the AI layer still holds data rather
/// than a handle. Each returns bounded JSON: a tool result is re-sent on every
/// later round of the turn, so an unbounded one would quietly rebuild the
/// oversized context the digest exists to replace.
class AdvisorToolbox {
  AdvisorToolbox({required this.snapshot, required this.exposure});

  final AgentSnapshot snapshot;
  final ExposureAnalysis exposure;

  /// Characters per result. Lists are cut, with the cut stated, to fit.
  static const maxResultChars = 30000;

  static const _catalog = SubstanceCatalog();

  static const specs = <AgentToolSpec>[
    AgentToolSpec(
      name: 'biomarker_history',
      description:
          'Every measurement of one biomarker, oldest first: value, unit, '
          'reference range, flag, note, lab report, plus catalog details, '
          'reference ranges and any personal target. Accepts an id or a name.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'biomarker': {
            'type': 'string',
            'description': 'Biomarker id from the digest, or its name.',
          },
        },
        'required': ['biomarker'],
        'additionalProperties': false,
      },
    ),
    AgentToolSpec(
      name: 'lab_report',
      description:
          'One lab report: date, lab, full comment and every result it '
          'contains with reference ranges and notes.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'report_id': {'type': 'string', 'description': 'Report id.'},
        },
        'required': ['report_id'],
        'additionalProperties': false,
      },
    ),
    AgentToolSpec(
      name: 'supplement_details',
      description:
          'One product: every recorded field, ingredients per unit, '
          'schedules, dose ledger totals and the most recent doses.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'supplement': {
            'type': 'string',
            'description': 'Product id from the digest, or its name.',
          },
        },
        'required': ['supplement'],
        'additionalProperties': false,
      },
    ),
    AgentToolSpec(
      name: 'supplement_intakes',
      description:
          'Individual doses, newest first, with time, product, amount and '
          'notes. Filter by product, by substance (every product containing '
          'it, with the substance amount per dose) and by date range.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'supplement': {
            'type': 'string',
            'description': 'Product id or name.',
          },
          'substance': {
            'type': 'string',
            'description': 'Substance name, e.g. "Biotin".',
          },
          'from': {'type': 'string', 'description': 'YYYY-MM-DD, inclusive.'},
          'to': {'type': 'string', 'description': 'YYYY-MM-DD, inclusive.'},
          'limit': {'type': 'integer', 'description': 'At most 500.'},
        },
        'additionalProperties': false,
      },
    ),
    AgentToolSpec(
      name: 'exposure_before',
      description:
          'Everything taken, and every symptom or tag logged, in the hours '
          'before a moment — typically a blood draw — plus medications '
          'recorded as current then. Anchor on a measurement id for its exact '
          'draw time, or give a local date-time.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'measurement_id': {
            'type': 'string',
            'description': 'Anchor at this measurement\'s draw time.',
          },
          'at': {
            'type': 'string',
            'description':
                'Local date-time YYYY-MM-DD HH:MM, or a date for the end of '
                'that day.',
          },
          'hours': {
            'type': 'number',
            'description': 'How far back to look. Default 72.',
          },
        },
        'additionalProperties': false,
      },
    ),
    AgentToolSpec(
      name: 'health_events',
      description:
          'Symptom and tag entries, newest first, with score, value, '
          'duration and notes. Filter by name, kind and date range.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'name': {'type': 'string', 'description': 'Series name.'},
          'kind': {
            'type': 'string',
            'enum': ['symptom', 'tag'],
          },
          'from': {'type': 'string', 'description': 'YYYY-MM-DD, inclusive.'},
          'to': {'type': 'string', 'description': 'YYYY-MM-DD, inclusive.'},
          'limit': {'type': 'integer', 'description': 'At most 500.'},
        },
        'additionalProperties': false,
      },
    ),
    AgentToolSpec(
      name: 'search_records',
      description:
          'Finds a word or phrase anywhere in the record: names, notes, lab '
          'comments, report lines, ingredients. Returns where it occurs.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {'type': 'string', 'description': 'Text to find.'},
        },
        'required': ['query'],
        'additionalProperties': false,
      },
    ),
    AgentToolSpec(
      name: 'biomarker_catalog',
      description:
          'The test catalog, including tests never measured: id, name, '
          'category, unit, price and whether this person has results.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'query': {
            'type': 'string',
            'description': 'Optional filter on name, synonym or category.',
          },
        },
        'additionalProperties': false,
      },
    ),
  ];

  /// Runs one call. Never throws: a failure is an error result the model can
  /// read and recover from, because an exception here would abort a turn the
  /// provider was answering fine.
  AgentToolResult run(AgentToolCall call) {
    if (call.inputError != null) {
      return _error(call, 'Arguments could not be read: ${call.inputError}');
    }
    try {
      final result = switch (call.name) {
        'biomarker_history' => _biomarkerHistory(call.input),
        'lab_report' => _labReport(call.input),
        'supplement_details' => _supplementDetails(call.input),
        'supplement_intakes' => _supplementIntakes(call.input),
        'exposure_before' => _exposureBefore(call.input),
        'health_events' => _healthEvents(call.input),
        'search_records' => _search(call.input),
        'biomarker_catalog' => _biomarkerCatalog(call.input),
        _ => throw _ToolInputError('Unknown tool "${call.name}".'),
      };
      return AgentToolResult(callId: call.id, content: _bounded(result));
    } on _ToolInputError catch (error) {
      return _error(call, error.message);
    } on Object catch (error) {
      return _error(call, 'The tool failed: $error');
    }
  }

  AgentToolResult _error(AgentToolCall call, String message) => AgentToolResult(
    callId: call.id,
    content: jsonEncode({'error': message}),
    isError: true,
  );

  // ------------------------------------------------------------- biomarkers

  Map<String, Object?> _biomarkerHistory(Map<String, Object?> input) {
    final query = _required(input, 'biomarker');
    final biomarker = _resolveBiomarker(query);
    final rows = [
      for (final row in snapshot.measurements)
        if (!row.deleted && row.biomarkerId == biomarker.id) row,
    ]..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final target = snapshot.targets
        .where((item) => !item.deleted && item.biomarkerId == biomarker.id)
        .firstOrNull;
    return {
      'biomarker': _clean({
        'id': biomarker.id,
        'name': biomarker.displayName,
        'canonical_name': biomarker.canonicalName,
        'category': biomarker.category,
        'default_unit': biomarker.defaultUnit,
        'synonyms': biomarker.synonyms,
        'description': biomarker.description,
        'calculated': biomarker.isCalculated ? true : null,
        'formula': biomarker.calculationFormula,
      }),
      'measurements': [for (final row in rows) _measurement(row)],
      'reference_ranges': [
        for (final range in snapshot.ranges)
          if (!range.deleted && range.biomarkerId == biomarker.id)
            _clean({
              'type': range.rangeType,
              'sex': range.sex,
              'age': range.ageMin == null && range.ageMax == null
                  ? null
                  : '${range.ageMin ?? ''}–${range.ageMax ?? ''}',
              'low': range.low,
              'high': range.high,
              'optimal_low': range.optimalLow,
              'optimal_high': range.optimalHigh,
              'unit': range.unit,
              'evidence': range.evidenceLabel,
              'notes': range.notes,
            }),
      ],
      'personal_target': target == null
          ? null
          : _clean({
              'low': target.low,
              'high': target.high,
              'borderline_low': target.borderlineLow,
              'borderline_high': target.borderlineHigh,
              'unit': target.unit,
              'notes': target.notes,
            }),
    };
  }

  Map<String, Object?> _measurement(Measurement row) {
    final document = row.documentId == null
        ? null
        : snapshot.documentsById[row.documentId];
    return _clean({
      'id': row.id,
      'taken': formatMoment(row.takenAt),
      'value': row.value,
      'unit': row.unit,
      'canonical_value': row.canonicalValue,
      'canonical_unit': row.canonicalUnit,
      'reference_low': row.labRefLow,
      'reference_high': row.labRefHigh,
      'flags': row.flags,
      'calculated': row.isCalculated ? true : null,
      'notes': row.notes,
      'report': document == null
          ? null
          : _clean({
              'id': document.id,
              'date': document.documentDate == null
                  ? null
                  : formatDay(document.documentDate!),
              'lab': document.labName,
            }),
      'line_on_report': row.rowText,
    });
  }

  Biomarker _resolveBiomarker(String query) {
    final byId = snapshot.biomarkersById[query.trim()];
    if (byId != null) return byId;
    final folded = foldForMatching(query);
    final exact = [
      for (final item in snapshot.biomarkers)
        if ([
          item.displayName,
          item.canonicalName,
          ...item.synonyms,
        ].any((name) => foldForMatching(name) == folded))
          item,
    ];
    if (exact.length == 1) return exact.single;
    final candidates = exact.isNotEmpty
        ? exact
        : [
            for (final item in snapshot.biomarkers)
              if (foldForMatching(item.displayName).contains(folded) ||
                  item.synonyms.any(
                    (name) => foldForMatching(name).contains(folded),
                  ))
                item,
          ];
    if (candidates.length == 1) return candidates.single;
    if (candidates.isEmpty) {
      throw _ToolInputError('No biomarker matches "$query".');
    }
    throw _ToolInputError(
      '"$query" matches several biomarkers; call again with one id: '
      '${candidates.take(20).map((item) => '${item.id} (${item.displayName})').join(', ')}.',
    );
  }

  Map<String, Object?> _labReport(Map<String, Object?> input) {
    final id = _required(input, 'report_id');
    final document = snapshot.documentsById[id];
    if (document == null || document.deleted) {
      throw _ToolInputError('No lab report with id "$id".');
    }
    final rows = [
      for (final row in snapshot.measurements)
        if (!row.deleted && row.documentId == id) row,
    ];
    return {
      'report': _clean({
        'id': document.id,
        'date': document.documentDate == null
            ? null
            : formatDay(document.documentDate!),
        'lab': document.labName,
        'file': document.fileName,
        'comment': document.reportComment,
        'parse_warnings': document.warnings,
      }),
      'results': [
        for (final row in rows)
          {
            'biomarker':
                snapshot.biomarkersById[row.biomarkerId]?.displayName ??
                row.biomarkerId,
            ..._measurement(row),
          },
      ],
    };
  }

  // ------------------------------------------------------------ supplements

  Map<String, Object?> _supplementDetails(Map<String, Object?> input) {
    final supplement = _resolveSupplement(_required(input, 'supplement'));
    final intakes = [
      for (final intake in snapshot.intakes)
        if (!intake.deleted && intake.supplementId == supplement.id) intake,
    ]..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    final taken = intakes.where((intake) => !intake.skipped).toList();
    return {
      'product': _clean({
        'id': supplement.id,
        'name': supplement.name,
        'brand': supplement.brand,
        'form': supplement.form,
        'active': supplement.active,
        'ingredients_per_unit': supplement.ingredients,
        'contents_recorded': supplement.ingredients.isNotEmpty,
        'units_per_container': supplement.unitsPerContainer,
        'bioavailability': supplement.bioavailability,
        'stock_unit': supplement.stockUnit,
        'notes': supplement.notes,
      }),
      'schedules': [
        for (final schedule in snapshot.schedules)
          if (!schedule.deleted && schedule.supplementId == supplement.id)
            _clean({
              'dose': schedule.dose,
              'unit': schedule.unit,
              'time_of_day': schedule.timeOfDay,
              'weekdays': schedule.weekdays,
              'start': schedule.startDate == null
                  ? null
                  : formatDay(schedule.startDate!),
              'end': schedule.endDate == null
                  ? null
                  : formatDay(schedule.endDate!),
              'active': schedule.active,
              'instructions': schedule.instructions,
            }),
      ],
      'ledger': _clean({
        'doses': taken.length,
        'skipped': intakes.length - taken.length,
        'first': taken.isEmpty ? null : formatMoment(taken.last.takenAt),
        'last': taken.isEmpty ? null : formatMoment(taken.first.takenAt),
      }),
      'recent_doses': [for (final intake in intakes.take(30)) _intake(intake)],
    };
  }

  Map<String, Object?> _intake(SupplementIntake intake) => _clean({
    'taken': formatMoment(intake.takenAt),
    'product': snapshot.supplementsById[intake.supplementId]?.name,
    'dose': intake.dose,
    'unit': intake.unit,
    'skipped': intake.skipped ? true : null,
    'notes': intake.notes,
  });

  Supplement _resolveSupplement(String query) {
    final byId = snapshot.supplementsById[query.trim()];
    if (byId != null) return byId;
    final folded = foldForMatching(query);
    final exact = [
      for (final item in snapshot.supplements)
        if (foldForMatching(item.name) == folded) item,
    ];
    if (exact.length == 1) return exact.single;
    final candidates = exact.isNotEmpty
        ? exact
        : [
            for (final item in snapshot.supplements)
              if (foldForMatching(
                '${item.name} ${item.brand}',
              ).contains(folded))
                item,
          ];
    if (candidates.length == 1) return candidates.single;
    if (candidates.isEmpty) {
      throw _ToolInputError('No product matches "$query".');
    }
    throw _ToolInputError(
      '"$query" matches several products; call again with one id: '
      '${candidates.map((item) => '${item.id} (${item.name})').join(', ')}.',
    );
  }

  Map<String, Object?> _supplementIntakes(Map<String, Object?> input) {
    final supplementQuery = _optional(input, 'supplement');
    final substanceQuery = _optional(input, 'substance');
    final from = _dayStart(_optional(input, 'from'));
    final to = _dayEnd(_optional(input, 'to'));
    final limit = _limit(input);
    final supplement = supplementQuery == null
        ? null
        : _resolveSupplement(supplementQuery);
    bool inRange(DateTime at) =>
        (from == null || !at.isBefore(from)) && (to == null || !at.isAfter(to));

    if (substanceQuery != null) {
      final key = _catalog.groupingKeyFor(substanceQuery);
      final folded = foldForMatching(substanceQuery);
      final events = [
        for (final event in exposure.events.reversed)
          if (inRange(event.at) &&
              (supplement == null || event.supplementId == supplement.id) &&
              (ExposureAnalysis.keyFor(event) == key ||
                  foldForMatching(event.name).contains(folded)))
            event,
      ];
      return {
        'substance': _catalog.displayNameFor(substanceQuery),
        'doses_found': events.length,
        'doses': [
          for (final event in events.take(limit))
            _clean({
              'taken': formatMoment(event.at),
              'product': snapshot.supplementsById[event.supplementId]?.name,
              'ingredient': event.name,
              'amount': event.amount,
              'unit': event.unit,
              'contents_recorded': event.fromProductName ? false : null,
            }),
        ],
        if (events.length > limit) 'not_shown': events.length - limit,
      };
    }
    final intakes = [
      for (final intake in snapshot.intakes)
        if (!intake.deleted &&
            inRange(intake.takenAt) &&
            (supplement == null || intake.supplementId == supplement.id))
          intake,
    ]..sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return {
      'doses_found': intakes.length,
      'doses': [for (final intake in intakes.take(limit)) _intake(intake)],
      if (intakes.length > limit) 'not_shown': intakes.length - limit,
    };
  }

  Map<String, Object?> _exposureBefore(Map<String, Object?> input) {
    final measurementId = _optional(input, 'measurement_id');
    final atText = _optional(input, 'at');
    DateTime at;
    String anchor;
    if (measurementId != null) {
      final measurement = snapshot.measurements
          .where((row) => row.id == measurementId)
          .firstOrNull;
      if (measurement == null) {
        throw _ToolInputError('No measurement with id "$measurementId".');
      }
      at = measurement.takenAt;
      anchor =
          'draw of ${snapshot.biomarkersById[measurement.biomarkerId]?.displayName ?? measurement.biomarkerId}';
    } else if (atText != null) {
      at = _moment(atText);
      anchor = 'given time';
    } else {
      throw _ToolInputError('Give measurement_id or at.');
    }
    final hoursInput = input['hours'];
    final hours = hoursInput is num && hoursInput > 0 ? hoursInput : 72;
    final from = at.subtract(Duration(minutes: (hours * 60).round()));
    bool inWindow(DateTime value) =>
        !value.isBefore(from) && !value.isAfter(at);
    final bySubstance = <String, List<DoseEvent>>{};
    for (final event in exposure.events) {
      if (!inWindow(event.at)) continue;
      bySubstance
          .putIfAbsent(ExposureAnalysis.keyFor(event), () => [])
          .add(event);
    }
    return {
      'anchor': anchor,
      'window': '${formatMoment(from)} – ${formatMoment(at)}',
      'substances': [
        for (final entry in bySubstance.entries)
          {
            'substance': entry.value.first.fromProductName
                ? '${entry.value.first.name} (contents not recorded)'
                : _catalog.displayNameFor(entry.value.first.name),
            'doses': [
              for (final event in entry.value)
                _clean({
                  'taken': formatMoment(event.at),
                  'hours_before': at.difference(event.at).inMinutes / 60,
                  'product': snapshot.supplementsById[event.supplementId]?.name,
                  'amount': event.amount,
                  'unit': event.unit,
                }),
            ],
          },
      ],
      'medications_recorded_as_current_then': [
        for (final medication in exposure.medications)
          if (_medicationActiveAt(medication.record, at))
            _clean({
              'name': medication.record.name,
              'dose': medication.record.dose,
              'unit': medication.record.unit,
              'schedule': medication.record.schedule,
            }),
      ],
      'symptoms_and_tags': [
        for (final event in snapshot.events)
          if (!event.deleted && inWindow(event.observedAt)) _event(event),
      ],
    };
  }

  /// A medication counts as current at [at] when its dates allow it; a record
  /// without dates counts by its status, which is the only evidence there is.
  bool _medicationActiveAt(NamedHealthRecord record, DateTime at) {
    final start = record.startDate;
    final end = record.endDate;
    if (start != null && at.isBefore(start)) return false;
    if (end != null && at.isAfter(end.add(const Duration(days: 1)))) {
      return false;
    }
    if (start == null && end == null) {
      return ExposureAnalysis.isCurrentMedication(record, at);
    }
    return true;
  }

  // ----------------------------------------------------------------- events

  Map<String, Object?> _healthEvents(Map<String, Object?> input) {
    final name = _optional(input, 'name');
    final kind = _optional(input, 'kind');
    final from = _dayStart(_optional(input, 'from'));
    final to = _dayEnd(_optional(input, 'to'));
    final limit = _limit(input);
    final folded = name == null ? null : foldForMatching(name);
    final rows = [
      for (final event in snapshot.events)
        if (!event.deleted &&
            (kind == null || event.kind.name == kind) &&
            (folded == null || foldForMatching(event.name).contains(folded)) &&
            (from == null || !event.observedAt.isBefore(from)) &&
            (to == null || !event.observedAt.isAfter(to)))
          event,
    ]..sort((a, b) => b.observedAt.compareTo(a.observedAt));
    return {
      'entries_found': rows.length,
      'entries': [for (final event in rows.take(limit)) _event(event)],
      if (rows.length > limit) 'not_shown': rows.length - limit,
    };
  }

  Map<String, Object?> _event(HealthEvent event) => _clean({
    'at': formatMoment(event.observedAt),
    'kind': event.kind.name,
    'name': event.name,
    'score': event.score,
    'value': event.numericValue,
    'unit': event.unit,
    'duration_minutes': event.durationMinutes,
    'notes': event.notes,
  });

  // ----------------------------------------------------------------- search

  Map<String, Object?> _search(Map<String, Object?> input) {
    final query = _required(input, 'query');
    final needle = foldForMatching(query);
    if (needle.length < 2) {
      throw _ToolInputError('Search for at least two letters.');
    }
    final hits = <Map<String, Object?>>[];
    void check(
      String section,
      String id,
      String field,
      String? text, [
      DateTime? at,
    ]) {
      if (text == null || text.trim().isEmpty) return;
      if (!foldForMatching(text).contains(needle)) return;
      hits.add(
        _clean({
          'section': section,
          'id': id,
          'field': field,
          'date': at == null ? null : formatDay(at),
          'text': text.length > 300 ? '${text.substring(0, 300)}…' : text,
        }),
      );
    }

    check('profile', snapshot.profileId, 'notes', snapshot.profile.notes);
    for (final record in snapshot.records) {
      if (record.deleted) continue;
      check(record.kind, record.id, 'name', record.name, record.startDate);
      check(record.kind, record.id, 'notes', record.notes, record.startDate);
    }
    for (final item in snapshot.supplements) {
      if (item.deleted) continue;
      check('supplement', item.id, 'name', '${item.name} ${item.brand}');
      check('supplement', item.id, 'notes', item.notes);
      for (final ingredient in item.ingredients) {
        check(
          'supplement',
          item.id,
          'ingredient',
          ingredient['name']?.toString(),
        );
      }
    }
    for (final intake in snapshot.intakes) {
      if (!intake.deleted) {
        check('dose', intake.id, 'notes', intake.notes, intake.takenAt);
      }
    }
    for (final event in snapshot.events) {
      if (event.deleted) continue;
      check(event.kind.name, event.id, 'name', event.name, event.observedAt);
      check(event.kind.name, event.id, 'notes', event.notes, event.observedAt);
    }
    for (final document in snapshot.documents) {
      if (document.deleted) continue;
      check(
        'lab_report',
        document.id,
        'comment',
        document.reportComment,
        document.documentDate,
      );
      check(
        'lab_report',
        document.id,
        'lab',
        document.labName,
        document.documentDate,
      );
    }
    for (final row in snapshot.measurements) {
      if (row.deleted) continue;
      check('measurement', row.id, 'notes', row.notes, row.takenAt);
      check('measurement', row.id, 'line_on_report', row.rowText, row.takenAt);
    }
    return {
      'query': query,
      'matches_found': hits.length,
      'matches': hits.take(60).toList(),
      if (hits.length > 60) 'not_shown': hits.length - 60,
    };
  }

  Map<String, Object?> _biomarkerCatalog(Map<String, Object?> input) {
    final query = _optional(input, 'query');
    final folded = query == null ? null : foldForMatching(query);
    final measured = {
      for (final row in snapshot.measurements)
        if (!row.deleted) row.biomarkerId,
    };
    final matches = [
      for (final item in snapshot.biomarkers)
        if (!item.deleted &&
            (folded == null ||
                [
                  item.displayName,
                  item.canonicalName,
                  item.category,
                  ...item.synonyms,
                ].any((text) => foldForMatching(text).contains(folded))))
          item,
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));
    return {
      'tests_found': matches.length,
      'tests': [
        for (final item in matches.take(80))
          _clean({
            'id': item.id,
            'name': item.displayName,
            'category': item.category,
            'unit': item.defaultUnit,
            'price_eur': item.hasPrice ? item.priceEur : null,
            'lab': item.labName,
            'measured': measured.contains(item.id),
            'calculated': item.isCalculated ? true : null,
          }),
      ],
      if (matches.length > 80) 'not_shown': matches.length - 80,
    };
  }

  // ---------------------------------------------------------------- helpers

  String _required(Map<String, Object?> input, String key) {
    final value = _optional(input, key);
    if (value == null) throw _ToolInputError('"$key" is required.');
    return value;
  }

  String? _optional(Map<String, Object?> input, String key) {
    final value = input[key]?.toString().trim();
    return value == null || value.isEmpty ? null : value;
  }

  int _limit(Map<String, Object?> input) {
    final value = input['limit'];
    if (value is num && value > 0) return value.toInt().clamp(1, 500);
    return 200;
  }

  DateTime? _dayStart(String? text) {
    if (text == null) return null;
    final day = _date(text);
    return DateTime(day.year, day.month, day.day);
  }

  DateTime? _dayEnd(String? text) {
    if (text == null) return null;
    final day = _date(text);
    return DateTime(day.year, day.month, day.day, 23, 59, 59, 999);
  }

  DateTime _date(String text) {
    final parsed = DateTime.tryParse(text.trim());
    if (parsed == null) throw _ToolInputError('"$text" is not a date.');
    return parsed;
  }

  /// A bare date means the end of that local day, so "before the draw on
  /// the 2nd" includes the whole of the 2nd.
  DateTime _moment(String text) {
    final trimmed = text.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
      return _dayEnd(trimmed)!;
    }
    final parsed = DateTime.tryParse(trimmed.replaceFirst(' ', 'T'));
    if (parsed == null) throw _ToolInputError('"$text" is not a date-time.');
    return parsed;
  }

  static Map<String, Object?> _clean(Map<String, Object?> row) => {
    for (final entry in row.entries)
      if (entry.value != null &&
          !(entry.value is String && (entry.value as String).trim().isEmpty) &&
          !(entry.value is Iterable && (entry.value as Iterable).isEmpty) &&
          !(entry.value is Map && (entry.value as Map).isEmpty))
        entry.key: entry.value,
  };

  /// Encodes [result], halving its longest list until it fits, and says so.
  static String _bounded(Map<String, Object?> result) {
    var encoded = jsonEncode(result);
    var current = Map<String, Object?>.from(result);
    while (encoded.length > maxResultChars) {
      final lists =
          [
            for (final entry in current.entries)
              if (entry.value is List && (entry.value as List).length > 1)
                entry,
          ]..sort(
            (a, b) =>
                (b.value as List).length.compareTo((a.value as List).length),
          );
      if (lists.isEmpty) {
        return jsonEncode({
          'error': 'The result is too large to return; narrow the request.',
        });
      }
      final longest = lists.first;
      final list = longest.value as List;
      final kept = list.take(list.length ~/ 2).toList();
      current = {
        ...current,
        longest.key: kept,
        'truncated':
            '${longest.key} cut to ${kept.length} entries to fit; narrow the '
            'request (dates, names) to see the rest.',
      };
      encoded = jsonEncode(current);
    }
    return encoded;
  }
}

class _ToolInputError implements Exception {
  const _ToolInputError(this.message);

  final String message;
}
