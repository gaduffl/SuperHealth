import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../analysis/exposure_analysis.dart';
import '../analysis/interaction_findings.dart';
import '../data/health_repository.dart';
import '../domain/entities.dart';
import '../domain/interaction_rules.dart';
import 'agent_snapshot.dart';
import 'health_context_builder.dart';

/// One thing a model must explicitly judge: the advisor before answering, the
/// lab planner in its plan's coverage.
class ReviewItem {
  const ReviewItem({required this.id, required this.label, this.kind = ''});

  final String id;

  /// How the item is named to the reader — never the id.
  final String label;

  /// `substance`, `medication`, `condition`, `goal`, `family_history`,
  /// `finding` or `overdue_test`.
  final String kind;
}

/// Who reads the digest, which decides what it lists and what must be judged.
enum ClinicalDigestPurpose {
  /// The advisor judges what is taken and what was found; the record's other
  /// entries are context for a question, not items every answer must address.
  advisor,

  /// The lab planner additionally accounts for every current condition, goal,
  /// family history entry and optional overdue test, because each of those is
  /// a reason to order a test — and carries the whole test catalog inline,
  /// since choosing from it is the job.
  labPlanner,
}

/// The advisor's always-present picture of the whole record.
///
/// The old advisor sent every row (~310k tokens) and hoped attention would
/// find the connection that mattered. A long context guarantees that data is
/// *sent*, not that it is *used*: biotin inside an ingredient string shares no
/// word with a question about TSH. The digest inverts that. Every entity —
/// each medication, condition, product, substance, measured biomarker, lab
/// comment and symptom series — is listed, so nothing can be missed for not
/// having been retrieved; only detail (individual doses, full series, older
/// notes) sits behind tools. Completeness is a property of this code, pinned
/// by tests, not of the model's reading.
class ClinicalDigest {
  const ClinicalDigest({
    required this.json,
    required this.checklist,
    required this.sha256,
  });

  final String json;

  /// Everything current the advisor must give a verdict on.
  final List<ReviewItem> checklist;
  final String sha256;

  int get byteLength => utf8.encode(json).length;
  int get estimatedTokens => estimatedJsonTokens(byteLength);
}

class ClinicalDigestBuilder {
  const ClinicalDigestBuilder();

  static const schema = 'superhealth.clinical_digest';
  static const schemaVersion = 1;

  /// Notes kept verbatim per symptom or tag series; older ones are counted and
  /// reachable through `health_events`.
  static const eventNotesPerSeries = 5;

  /// Measurement notes kept per biomarker; the rest via `biomarker_history`.
  static const measurementNotesPerBiomarker = 10;

  /// [overdueTests] are overdue list tests the plan is free to leave out;
  /// each then needs a verdict. Tests the plan must include are enforced by
  /// validation instead, so they are not passed here.
  ClinicalDigest build({
    required AgentSnapshot snapshot,
    required ExposureAnalysis exposure,
    required List<InteractionFinding> findings,
    ClinicalDigestPurpose purpose = ClinicalDigestPurpose.advisor,
    List<DueBiomarker> overdueTests = const [],
  }) {
    final now = exposure.now;
    final planning = purpose == ClinicalDigestPurpose.labPlanner;
    final records = [
      for (final record in snapshot.records)
        if (!record.deleted && ExposureAnalysis.isCurrentRecord(record, now))
          record,
    ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    final checklist = <ReviewItem>[
      for (final substance in exposure.substances)
        if (substance.current)
          ReviewItem(
            id: substance.id,
            kind: 'substance',
            label: substance.ingredientsRecorded
                ? substance.displayName
                : '${substance.displayName} (contents not recorded)',
          ),
      for (final medication in exposure.medications)
        if (medication.current)
          ReviewItem(
            id: medication.id,
            kind: 'medication',
            label: medication.record.name,
          ),
      if (planning)
        for (final kind in const ['condition', 'goal', 'family_history'])
          for (final record in records)
            if (record.kind == kind)
              ReviewItem(id: record.id, kind: kind, label: record.name),
      for (final finding in findings)
        ReviewItem(
          id: finding.id,
          kind: 'finding',
          label: _findingLabel(finding),
        ),
      if (planning)
        for (final due in overdueTests)
          ReviewItem(
            id: 'due:${due.biomarker.id}',
            kind: 'overdue_test',
            label: due.biomarker.displayName,
          ),
    ];
    final digest = <String, Object?>{
      'schema': schema,
      'schema_version': schemaVersion,
      'as_of': _day(now),
      'utc_offset': _offset(now),
      'how_to_read': [
        'Built by the app from the complete record of this profile. Every '
            'list below is complete: every recorded medication, condition, '
            'goal and family history entry; every product this person '
            'schedules or has taken; every substance taken; every measured '
            'biomarker; every lab report; every symptom and tag series. If '
            'something is not listed, it is not recorded.',
        'What is abbreviated is detail, never an entity: individual doses, '
            'full measurement series, reference ranges and older notes. '
            'not_in_this_digest names the tool that returns each.',
        'findings are deterministic checks against a curated interaction '
            'table, computed from the record. Their facts are not guesses. '
            'The table is not exhaustive: a missing finding means no rule, '
            'not no interaction.',
        'exposures group every product\'s ingredients by substance. Amounts '
            'are per day on days taken, per unit, and never added across '
            'units. A product whose contents were never recorded appears as '
            'its own exposure: its substances are unknown, not absent.',
        'Times are local to the person (utc_offset). Dates are YYYY-MM-DD.',
        if (planning)
          'test_catalog lists every orderable and calculated test in the '
              'catalog, measured or not, with its exact id, name and price. '
              'A plan can only use these ids.',
      ],
      'profile': _profile(snapshot.profile, now),
      'health_records': _records(snapshot.records, exposure),
      'supplements': _supplements(snapshot, exposure),
      'exposures': [
        for (final substance in exposure.substances)
          _exposure(substance, snapshot.supplementsById),
      ],
      'findings': [for (final finding in findings) findingJson(finding)],
      'biomarkers': _biomarkers(snapshot, findings),
      'lab_reports': _reports(snapshot),
      'symptoms_and_tags': _eventSeries(snapshot.events, now),
      'retest_lists': _lists(snapshot),
      'lab_plans': _plans(snapshot),
      if (planning) 'test_catalog': _testCatalog(snapshot),
      'review_checklist': [
        for (final item in checklist)
          {'id': item.id, 'kind': item.kind, 'what': item.label},
      ],
      'not_in_this_digest': {
        'every measurement of a biomarker, with notes, reference ranges and '
                'report links':
            'biomarker_history',
        'a lab report with all of its results': 'lab_report',
        'individual doses with times and notes': 'supplement_intakes',
        'what was taken in the hours or days before a moment, e.g. a blood '
                'draw':
            'exposure_before',
        'a product\'s full record, schedules and dose ledger':
            'supplement_details',
        'every symptom or tag entry with notes': 'health_events',
        'any word in any name, note or comment across the record':
            'search_records',
        if (!planning)
          'catalog tests never measured, with prices': 'biomarker_catalog',
      },
    };
    final json = HealthRepository.stableJson(digest);
    return ClinicalDigest(
      json: json,
      checklist: checklist,
      sha256: sha256.convert(utf8.encode(json)).toString(),
    );
  }

  Map<String, Object?> _profile(Profile profile, DateTime now) {
    final birth = profile.dateOfBirth;
    return _lean({
      'sex': profile.sex,
      'date_of_birth': birth == null ? null : _day(birth),
      'age_years': birth == null ? null : _age(birth, now),
      'height_cm': profile.heightCm,
      'weight_kg': profile.weightKg,
      'notes': profile.notes,
    });
  }

  List<Map<String, Object?>> _records(
    List<NamedHealthRecord> records,
    ExposureAnalysis exposure,
  ) {
    final medicationIds = {
      for (final medication in exposure.medications)
        medication.record.id: medication,
    };
    final sorted =
        [
          for (final record in records)
            if (!record.deleted) record,
        ]..sort((a, b) {
          final kind = a.kind.compareTo(b.kind);
          if (kind != 0) return kind;
          final status = a.status.compareTo(b.status);
          return status != 0
              ? status
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
    return [
      for (final record in sorted)
        _lean({
          'id': medicationIds[record.id]?.id ?? record.id,
          'kind': record.kind,
          'name': record.name,
          'status': record.status,
          'dose': record.dose,
          'unit': record.unit,
          'schedule': record.schedule,
          'start': record.startDate == null ? null : _day(record.startDate!),
          'end': record.endDate == null ? null : _day(record.endDate!),
          'priority': record.priority,
          'target_date': record.targetDate == null
              ? null
              : _day(record.targetDate!),
          'drug_classes': medicationIds[record.id]?.classIds.toList()?..sort(),
          'notes': record.notes,
        }),
    ];
  }

  List<Map<String, Object?>> _supplements(
    AgentSnapshot snapshot,
    ExposureAnalysis exposure,
  ) {
    final ledger = <String, _Ledger>{};
    for (final intake in snapshot.intakes) {
      if (intake.deleted) continue;
      ledger.putIfAbsent(intake.supplementId, _Ledger.new).add(intake);
    }
    final schedules = <String, List<SupplementSchedule>>{};
    for (final schedule in snapshot.schedules) {
      if (schedule.deleted) continue;
      schedules.putIfAbsent(schedule.supplementId, () => []).add(schedule);
    }
    final sorted = [...snapshot.supplements]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return [
      for (final supplement in sorted)
        if (!supplement.deleted)
          _lean({
            'id': supplement.id,
            'name': supplement.name,
            'brand': supplement.brand,
            'form': supplement.form,
            'active': supplement.active,
            'contents': _contents(supplement.ingredients),
            'contents_recorded': supplement.ingredients.isNotEmpty,
            'schedules': [
              for (final schedule in schedules[supplement.id] ?? const [])
                _schedule(schedule),
            ],
            'doses_logged': ledger[supplement.id]?.doses,
            'doses_skipped': ledger[supplement.id]?.skipped,
            'first_dose': _at(ledger[supplement.id]?.first),
            'last_dose': _at(ledger[supplement.id]?.last),
            'notes': supplement.notes,
          }),
    ];
  }

  String? _contents(List<Map<String, Object?>> ingredients) {
    final parts = [
      for (final ingredient in ingredients)
        [
          ingredient['name']?.toString().trim() ?? '',
          ingredient['amount']?.toString().trim() ?? '',
          ingredient['unit']?.toString().trim() ?? '',
        ].where((part) => part.isNotEmpty).join(' '),
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? null : '${parts.join('; ')} (per unit)';
  }

  String _schedule(SupplementSchedule schedule) {
    final days = schedule.weekdays.length == 7
        ? 'daily'
        : schedule.weekdays.map((day) => day.substring(0, 3)).join(',');
    final window = [
      if (schedule.startDate != null) 'from ${_day(schedule.startDate!)}',
      if (schedule.endDate != null) 'until ${_day(schedule.endDate!)}',
      if (!schedule.active) 'inactive',
    ];
    return [
      '${_number(schedule.dose)} ${schedule.unit} at ${schedule.timeOfDay}, '
          '$days',
      ...window,
      if (schedule.instructions.trim().isNotEmpty) schedule.instructions.trim(),
    ].join('; ');
  }

  Map<String, Object?> _exposure(
    SubstanceExposure substance,
    Map<String, Supplement> products,
  ) => _lean({
    'id': substance.id,
    'substance': substance.displayName,
    'current': substance.current,
    'planned_only': substance.plannedOnly ? true : null,
    'contents_recorded': substance.ingredientsRecorded ? null : false,
    'per_day_when_taken': _amounts(substance.recentDailyAmountByUnit),
    'planned_per_day': _amounts(substance.plannedDailyAmountByUnit),
    'days_taken_last_28': substance.recentDaysTaken,
    'amount_missing_for_some_doses': substance.amountMissing ? true : null,
    'first_taken': _at(substance.firstTakenAt),
    'last_taken': _at(substance.lastTakenAt),
    'products': [
      for (final id in substance.supplementIds) products[id]?.name ?? id,
    ]..sort(),
  });

  List<String> _amounts(Map<String, double> byUnit) {
    final units = byUnit.keys.toList()..sort();
    return [for (final unit in units) '${_number(byUnit[unit]!)} $unit'];
  }

  /// A past-measurement finding exists once per affected test, so its title
  /// alone would read like the same item listed twice.
  static String _findingLabel(InteractionFinding finding) {
    final tests = {
      for (final affected in finding.measurements)
        affected.biomarker.displayName,
    }.toList()..sort();
    return finding.scope == FindingScope.pastMeasurement && tests.isNotEmpty
        ? '${finding.rule.title.en} (${tests.join(', ')})'
        : finding.rule.title.en;
  }

  /// One finding as the models read it — shared with the lab planner, so a
  /// finding reads the same in both prompts.
  static Map<String, Object?> findingJson(InteractionFinding finding) => _lean({
    'id': finding.id,
    'severity': finding.severity.name,
    'kind': finding.rule.kind.name,
    'scope': finding.scope.name,
    'title': finding.rule.title.en,
    'explanation': finding.rule.explanation.en,
    'advice': finding.rule.advice.en,
    'because_of': finding.subjects,
    'together_with': finding.partners,
    'highest_daily_amount': finding.dailyAmount == null
        ? null
        : '${_number(finding.dailyAmount!)} ${finding.amountUnit!.symbol}',
    'dose_known': finding.doseKnown ? null : false,
    'window_before_draw_hours': finding.window?.inHours,
    'last_exposure': _at(finding.lastExposureAt),
    'affected_tests': [
      for (final test in finding.rule.affects)
        '${test.concept.name.en}: ${_direction(test.direction)}',
    ],
    'measurements_possibly_affected': [
      for (final affected in finding.measurements)
        _lean({
          'biomarker_id': affected.biomarker.id,
          'test': affected.biomarker.displayName,
          'value':
              '${_number(affected.measurement.value)} ${affected.measurement.unit}',
          'taken': _at(affected.measurement.takenAt),
          'hours_after_last_exposure': affected.exposureBeforeDraw?.inHours,
          'likely_effect': _direction(affected.direction),
        }),
    ],
    'spacing': finding.spacing == null
        ? null
        : '${finding.spacing!.daysTooClose} of '
              '${finding.spacing!.daysTogether} days with both logged were '
              'closer than ${finding.rule.minimumSpacing!.inHours} h',
    'source': finding.rule.source,
  });

  static String _direction(EffectDirection direction) => switch (direction) {
    EffectDirection.falselyLow => 'can read falsely low',
    EffectDirection.falselyHigh => 'can read falsely high',
    EffectDirection.raises => 'raised',
    EffectDirection.lowers => 'lowered',
    EffectDirection.masks => 'can look normal despite a deficiency',
    EffectDirection.unpredictable => 'can shift either way',
  };

  List<Map<String, Object?>> _biomarkers(
    AgentSnapshot snapshot,
    List<InteractionFinding> findings,
  ) {
    final byBiomarker = <String, List<Measurement>>{};
    for (final measurement in snapshot.measurements) {
      if (measurement.deleted) continue;
      byBiomarker
          .putIfAbsent(measurement.biomarkerId, () => [])
          .add(measurement);
    }
    final targets = {
      for (final target in snapshot.targets)
        if (!target.deleted) target.biomarkerId: target,
    };
    final result = <Map<String, Object?>>[];
    for (final entry in byBiomarker.entries) {
      final rows = entry.value..sort((a, b) => a.takenAt.compareTo(b.takenAt));
      final latest = rows.last;
      final previous = rows.length > 1 ? rows[rows.length - 2] : null;
      final biomarker = snapshot.biomarkersById[entry.key];
      final notes = [
        for (final row in rows.reversed)
          if (row.notes.trim().isNotEmpty)
            '${_day(row.takenAt)}: ${row.notes.trim()}',
      ];
      final target = targets[entry.key];
      result.add(
        _lean({
          'id': entry.key,
          'name': biomarker?.displayName ?? entry.key,
          'category': biomarker?.category,
          'calculated': latest.isCalculated ? true : null,
          'measurements': rows.length,
          'first': _day(rows.first.takenAt),
          'latest': _value(latest, snapshot),
          'previous': previous == null ? null : _value(previous, snapshot),
          'personal_target': target == null
              ? null
              : '${_bound(target.low)}–${_bound(target.high)} ${target.unit}',
          'notes': notes.take(measurementNotesPerBiomarker).toList(),
          'older_notes': notes.length > measurementNotesPerBiomarker
              ? notes.length - measurementNotesPerBiomarker
              : null,
          'findings': [
            for (final finding in findings)
              if (finding.affectedBiomarkerIds.contains(entry.key)) finding.id,
          ],
        }),
      );
    }
    result.sort(
      (a, b) =>
          '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase()),
    );
    return result;
  }

  Map<String, Object?> _value(Measurement row, AgentSnapshot snapshot) {
    final low = row.labRefLow;
    final high = row.labRefHigh;
    final flag = low != null && row.value < low
        ? 'below reference'
        : high != null && row.value > high
        ? 'above reference'
        : low != null || high != null
        ? 'within reference'
        : null;
    final document = row.documentId == null
        ? null
        : snapshot.documentsById[row.documentId];
    return _lean({
      'value': '${_number(row.value)} ${row.unit}',
      'canonical': row.canonicalValue == null || row.canonicalUnit == null
          ? null
          : '${_number(row.canonicalValue!)} ${row.canonicalUnit}',
      'taken': _at(row.takenAt),
      'reference': low == null && high == null
          ? null
          : '${_bound(low)}–${_bound(high)}',
      'flag': flag,
      'report': document?.id,
    });
  }

  List<Map<String, Object?>> _reports(AgentSnapshot snapshot) {
    final counts = <String, int>{};
    for (final measurement in snapshot.measurements) {
      final id = measurement.documentId;
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    final sorted =
        [
          for (final document in snapshot.documents)
            if (!document.deleted) document,
        ]..sort((a, b) {
          final date = (a.documentDate ?? a.createdAt).compareTo(
            b.documentDate ?? b.createdAt,
          );
          return date != 0 ? date : a.id.compareTo(b.id);
        });
    return [
      for (final document in sorted)
        _lean({
          'id': document.id,
          'date': document.documentDate == null
              ? null
              : _day(document.documentDate!),
          'lab': document.labName,
          'file': document.fileName,
          'results': counts[document.id] ?? 0,
          'comment': document.reportComment,
        }),
    ];
  }

  List<Map<String, Object?>> _eventSeries(
    List<HealthEvent> events,
    DateTime now,
  ) {
    final series = <String, List<HealthEvent>>{};
    for (final event in events) {
      if (event.deleted) continue;
      series
          .putIfAbsent('${event.kind.name}|${event.name.trim()}', () => [])
          .add(event);
    }
    final recentFrom = now.subtract(const Duration(days: 30));
    final result = <Map<String, Object?>>[];
    for (final entry in series.entries) {
      final rows = entry.value
        ..sort((a, b) => a.observedAt.compareTo(b.observedAt));
      final scores = [
        for (final row in rows)
          if (row.score != null) row.score!,
      ];
      final values = [
        for (final row in rows)
          if (row.numericValue != null) row.numericValue!,
      ];
      final noted = [
        for (final row in rows.reversed)
          if (row.notes.trim().isNotEmpty)
            '${_at(row.observedAt)}: ${row.notes.trim()}',
      ];
      final units = {
        for (final row in rows)
          if ((row.unit ?? '').trim().isNotEmpty) row.unit!.trim(),
      };
      result.add(
        _lean({
          'name': rows.first.name.trim(),
          'kind': rows.first.kind.name,
          'entries': rows.length,
          'first': _at(rows.first.observedAt),
          'last': _at(rows.last.observedAt),
          'last_30_days': rows
              .where((row) => !row.observedAt.isBefore(recentFrom))
              .length,
          'mean_score': scores.isEmpty
              ? null
              : _number(scores.reduce((a, b) => a + b) / scores.length),
          'mean_value': values.isEmpty
              ? null
              : _number(values.reduce((a, b) => a + b) / values.length),
          'units': units.toList()..sort(),
          'recent_notes': noted.take(eventNotesPerSeries).toList(),
          'older_notes': noted.length > eventNotesPerSeries
              ? noted.length - eventNotesPerSeries
              : null,
        }),
      );
    }
    result.sort((a, b) {
      final kind = '${a['kind']}'.compareTo('${b['kind']}');
      return kind != 0
          ? kind
          : '${a['name']}'.toLowerCase().compareTo(
              '${b['name']}'.toLowerCase(),
            );
    });
    return result;
  }

  List<Map<String, Object?>> _lists(AgentSnapshot snapshot) {
    final lastMeasured = <String, DateTime>{};
    for (final measurement in snapshot.measurements) {
      final previous = lastMeasured[measurement.biomarkerId];
      if (previous == null || measurement.takenAt.isAfter(previous)) {
        lastMeasured[measurement.biomarkerId] = measurement.takenAt;
      }
    }
    return [
      for (final list in snapshot.lists)
        if (!list.deleted)
          _lean({
            'name': list.name,
            'interval_days': list.dueIntervalDays,
            'items': [
              for (final item in list.items)
                if (!item.deleted)
                  _lean({
                    'biomarker':
                        snapshot
                            .biomarkersById[item.biomarkerId]
                            ?.displayName ??
                        item.biomarkerId,
                    'interval_days': list.intervalFor(item),
                    'last_measured': lastMeasured[item.biomarkerId] == null
                        ? null
                        : _day(lastMeasured[item.biomarkerId]!),
                    'due': _due(list, item, lastMeasured[item.biomarkerId]),
                    'notes': item.notes,
                  }),
            ],
          }),
    ];
  }

  String? _due(
    BiomarkerList list,
    BiomarkerListItem item,
    DateTime? lastMeasured,
  ) {
    final due = list.dueDateFor(item, lastMeasured);
    if (due == null) return null;
    return lastMeasured == null ? 'now (never measured)' : _day(due);
  }

  /// The whole catalog, because a plan is chosen from it: a test this person
  /// has never had is exactly the kind a planner must be able to propose.
  List<Map<String, Object?>> _testCatalog(AgentSnapshot snapshot) {
    final measured = {
      for (final row in snapshot.measurements)
        if (!row.deleted) row.biomarkerId,
    };
    final sorted = [
      for (final biomarker in snapshot.biomarkers)
        if (!biomarker.deleted) biomarker,
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));
    return [
      for (final biomarker in sorted)
        _lean({
          'id': biomarker.id,
          'name': biomarker.displayName,
          'category': biomarker.category,
          'unit': biomarker.defaultUnit,
          'price_eur': biomarker.hasPrice ? biomarker.priceEur : null,
          'calculated': biomarker.isCalculated ? true : null,
          'measured': measured.contains(biomarker.id) ? true : null,
          'synonyms': biomarker.synonyms,
        }),
    ];
  }

  List<Map<String, Object?>> _plans(AgentSnapshot snapshot) {
    final counts = <String, int>{};
    for (final item in snapshot.labPlanItems) {
      final id = item['plan_id']?.toString();
      if (id != null) counts[id] = (counts[id] ?? 0) + 1;
    }
    return [
      for (final plan in snapshot.labPlans)
        _lean({
          'id': plan['id'],
          'title': plan['title'],
          'planned_for': plan['planned_for'],
          'status': plan['status'],
          'tests': counts['${plan['id']}'] ?? 0,
        }),
    ];
  }

  /// Drops keys that state nothing, as the evidence package does: an absent
  /// key and an empty one mean the same "nothing recorded". Numbers and
  /// booleans are kept — a zero and a false are facts.
  static Map<String, Object?> _lean(Map<String, Object?> row) => {
    for (final entry in row.entries)
      if (!_empty(entry.value)) entry.key: entry.value,
  };

  static bool _empty(Object? value) =>
      value == null ||
      (value is String && value.trim().isEmpty) ||
      (value is Iterable && value.isEmpty) ||
      (value is Map && value.isEmpty);

  static String _bound(double? value) => value == null ? '' : _number(value);
}

class _Ledger {
  int doses = 0;
  int skipped = 0;
  DateTime? first;
  DateTime? last;

  void add(SupplementIntake intake) {
    if (intake.skipped) {
      skipped++;
      return;
    }
    doses++;
    if (first == null || intake.takenAt.isBefore(first!)) {
      first = intake.takenAt;
    }
    if (last == null || intake.takenAt.isAfter(last!)) last = intake.takenAt;
  }
}

/// A number without float noise: 10.0 is "10", 0.30000000000000004 is "0.3".
String _number(num value) {
  if (value == value.roundToDouble()) return value.round().toString();
  final fixed = value.toStringAsFixed(3);
  return fixed
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

String _day(DateTime at) {
  final local = at.toLocal();
  return '${local.year}-${_two(local.month)}-${_two(local.day)}';
}

String? _at(DateTime? at) {
  if (at == null) return null;
  final local = at.toLocal();
  return '${_day(local)} ${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');

String _offset(DateTime now) {
  final offset = now.toLocal().timeZoneOffset;
  final sign = offset.isNegative ? '-' : '+';
  final minutes = offset.inMinutes.abs();
  return '$sign${_two(minutes ~/ 60)}:${_two(minutes % 60)}';
}

int _age(DateTime birth, DateTime now) {
  final local = now.toLocal();
  var age = local.year - birth.year;
  if (local.month < birth.month ||
      (local.month == birth.month && local.day < birth.day)) {
    age--;
  }
  return age;
}

/// Shared with the advisor tools so both render values identically.
String formatNumber(num value) => _number(value);
String formatDay(DateTime at) => _day(at);
String formatMoment(DateTime at) => _at(at)!;
