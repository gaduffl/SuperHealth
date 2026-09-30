import '../domain/biomarker_concepts.dart';
import '../domain/entities.dart';
import '../domain/interaction_rules.dart';
import '../domain/medication_catalog.dart';
import '../domain/substance_catalog.dart';
import '../domain/substance_conversions.dart';
import '../domain/units.dart';
import 'exposure_analysis.dart';

/// Whether a finding is about what is taken now or about a value already
/// measured.
enum FindingScope {
  /// Something taken now affects future tests, or two current things
  /// interact.
  current,

  /// A stored measurement was taken while exposed — the value may be off.
  pastMeasurement,
}

/// A stored measurement a rule says may be affected.
class AffectedMeasurement {
  const AffectedMeasurement({
    required this.measurement,
    required this.biomarker,
    required this.direction,
    this.lastExposureAt,
  });

  final Measurement measurement;
  final Biomarker biomarker;
  final EffectDirection direction;

  /// The last matching exposure before the draw, when it has a time.
  final DateTime? lastExposureAt;

  Duration? get exposureBeforeDraw => lastExposureAt == null
      ? null
      : measurement.takenAt.difference(lastExposureAt!);
}

/// How often two things that must be spaced apart were actually taken close
/// together, from the times in the ledger.
class SpacingCheck {
  const SpacingCheck({required this.daysTogether, required this.daysTooClose});

  final int daysTogether;
  final int daysTooClose;
}

/// One rule firing for this profile.
class InteractionFinding {
  const InteractionFinding({
    required this.id,
    required this.rule,
    required this.scope,
    required this.subjects,
    required this.doseKnown,
    this.partners = const [],
    this.supplementIds = const {},
    this.medicationRecordIds = const {},
    this.eventIds = const {},
    this.dailyAmount,
    this.amountUnit,
    this.window,
    this.affectedBiomarkerIds = const {},
    this.measurements = const [],
    this.spacing,
    this.lastExposureAt,
  });

  /// Stable across runs: `finding:<rule>` for a current finding,
  /// `finding:<rule>@<biomarker id>` for a past-measurement one.
  final String id;
  final InteractionRule rule;
  final FindingScope scope;

  /// What set the rule off, as recorded ("Biotin", "L-Thyroxin 75 µg").
  final List<String> subjects;

  /// The other side of an interaction.
  final List<String> partners;
  final Set<String> supplementIds;
  final Set<String> medicationRecordIds;
  final Set<String> eventIds;

  /// Highest daily amount, in the threshold's unit, when one was compared.
  final double? dailyAmount;
  final CanonicalUnit? amountUnit;

  /// False when the rule fired on a match whose amount could not be compared.
  final bool doseKnown;

  /// How long before a draw exposure counts, for this finding.
  final Duration? window;

  /// Catalog biomarkers the rule's tests resolve to.
  final Set<String> affectedBiomarkerIds;
  final List<AffectedMeasurement> measurements;
  final SpacingCheck? spacing;
  final DateTime? lastExposureAt;

  InteractionSeverity get severity => rule.severity;
}

/// Evaluates [interactionRules] against one profile's record.
///
/// Pure and deterministic: the same record and clock produce the same
/// findings, which is what lets the advisor be held to them.
class InteractionFindingsEngine {
  const InteractionFindingsEngine({
    this.rules = interactionRules,
    this.conversions = const SubstanceConversions(),
  });

  final List<InteractionRule> rules;
  final SubstanceConversions conversions;

  static const _catalog = SubstanceCatalog();
  static const _medicationCatalog = MedicationCatalog();

  List<InteractionFinding> evaluate({
    required ExposureAnalysis exposure,
    required List<Biomarker> biomarkers,
    required List<Measurement> measurements,
    required List<HealthEvent> events,
  }) {
    final context = _Context(
      exposure: exposure,
      biomarkers: [
        for (final item in biomarkers)
          if (!item.deleted) item,
      ],
      measurements: [
        for (final item in measurements)
          if (!item.deleted) item,
      ]..sort((a, b) => a.takenAt.compareTo(b.takenAt)),
      events: [
        for (final item in events)
          if (!item.deleted) item,
      ]..sort((a, b) => a.observedAt.compareTo(b.observedAt)),
    );
    final findings = <InteractionFinding>[];
    for (final rule in rules) {
      findings.addAll(_evaluateRule(rule, context));
    }
    findings.sort(compareFindings);
    return findings;
  }

  /// Severity first, then what is happening now before what was measured,
  /// then table order so equal findings keep a stable place.
  static int compareFindings(InteractionFinding a, InteractionFinding b) {
    final severity = a.severity.index.compareTo(b.severity.index);
    if (severity != 0) return severity;
    final scope = a.scope.index.compareTo(b.scope.index);
    if (scope != 0) return scope;
    final order = interactionRules
        .indexOf(a.rule)
        .compareTo(interactionRules.indexOf(b.rule));
    return order != 0 ? order : a.id.compareTo(b.id);
  }

  Iterable<InteractionFinding> _evaluateRule(
    InteractionRule rule,
    _Context context,
  ) sync* {
    final partner = rule.partner;
    if (partner != null) {
      final finding = _interaction(rule, partner, context);
      if (finding != null) yield finding;
      return;
    }
    final current = _currentFinding(rule, context);
    if (current != null) yield current;
    yield* _pastFindings(rule, context);
  }

  // ---------------------------------------------------------------- current

  InteractionFinding? _currentFinding(InteractionRule rule, _Context context) {
    final side = _currentSide(rule.trigger, rule, context);
    if (side == null) return null;
    return InteractionFinding(
      id: 'finding:${rule.id}',
      rule: rule,
      scope: FindingScope.current,
      subjects: side.labels,
      supplementIds: side.supplementIds,
      medicationRecordIds: side.medicationRecordIds,
      dailyAmount: side.dailyAmount,
      amountUnit: side.amountUnit,
      doseKnown: side.doseKnown,
      window: side.window,
      affectedBiomarkerIds: context.biomarkerIdsFor(rule),
      lastExposureAt: side.lastAt,
    );
  }

  InteractionFinding? _interaction(
    InteractionRule rule,
    RuleTrigger partner,
    _Context context,
  ) {
    final first = _currentSide(rule.trigger, rule, context);
    if (first == null) return null;
    final second = _currentSide(partner, rule, context, forPartner: true);
    if (second == null) return null;
    final spacing = rule.minimumSpacing == null
        ? null
        : _spacing(rule, partner, context);
    return InteractionFinding(
      id: 'finding:${rule.id}',
      rule: rule,
      scope: FindingScope.current,
      subjects: first.labels,
      partners: second.labels,
      supplementIds: {...first.supplementIds, ...second.supplementIds},
      medicationRecordIds: {
        ...first.medicationRecordIds,
        ...second.medicationRecordIds,
      },
      dailyAmount: first.dailyAmount,
      amountUnit: first.amountUnit,
      doseKnown: first.doseKnown,
      affectedBiomarkerIds: context.biomarkerIdsFor(rule),
      spacing: spacing,
      lastExposureAt: first.lastAt,
    );
  }

  /// Whether one side of a rule is present now, and what it consists of.
  ///
  /// Thresholds apply to the rule's own trigger only; a partner is present
  /// or not, whatever its dose.
  _Side? _currentSide(
    RuleTrigger trigger,
    InteractionRule rule,
    _Context context, {
    bool forPartner = false,
  }) {
    switch (trigger) {
      case SubstanceTrigger():
        final now = context.exposure.now;
        final from = now.subtract(ExposureAnalysis.recentWindow);
        final recent = [
          for (final hit in context.matches(trigger))
            if (!hit.event.at.isBefore(from) && !hit.event.at.isAfter(now)) hit,
        ];
        final planned = [
          for (final event in context.exposure.plannedToday)
            if (trigger.match(event.name) case final match?) _Hit(event, match),
        ];
        final hits = [...recent, ...planned];
        if (hits.isEmpty) return null;
        final dose = forPartner || rule.thresholds.isEmpty
            ? null
            : _dose(rule, trigger, hits);
        if (!forPartner && rule.thresholds.isNotEmpty) {
          if (dose!.tier == null &&
              !(dose.unknown && rule.firesWhenDoseUnknown)) {
            return null;
          }
        }
        return _Side(
          labels: context.labelsFor(hits),
          supplementIds: {for (final hit in hits) hit.event.supplementId},
          dailyAmount: dose?.maxDaily,
          amountUnit: dose?.unit,
          doseKnown: dose == null ? true : dose.tier != null,
          window:
              dose?.tier?.lookback ??
              (rule.thresholds.isEmpty
                  ? rule.lookback
                  : rule.thresholds.first.lookback),
          lastAt: recent.isEmpty ? null : recent.last.event.at,
        );
      case MedicationTrigger():
        final records = [
          for (final medication in context.exposure.medications)
            if (medication.current &&
                medication.classIds.any(trigger.classIds.contains))
              medication,
        ];
        final ledger = [
          for (final substance in context.exposure.substances)
            if (substance.current &&
                substance.substanceId != null &&
                _medicationCatalog
                    .classIdsForSubstance(substance.substanceId!)
                    .any(trigger.classIds.contains))
              substance,
        ];
        if (records.isEmpty && ledger.isEmpty) return null;
        return _Side(
          labels: [
            for (final medication in records) medication.record.name,
            for (final substance in ledger) substance.displayName,
          ],
          supplementIds: {
            for (final substance in ledger) ...substance.supplementIds,
          },
          medicationRecordIds: {
            for (final medication in records) medication.record.id,
          },
          doseKnown: true,
          window: rule.lookback,
        );
      case EventTrigger():
        // Events matter only against a specific draw; see `_pastFindings`.
        return null;
    }
  }

  _Dose _dose(InteractionRule rule, SubstanceTrigger trigger, List<_Hit> hits) {
    final unit = rule.thresholds.first.unit;
    final perDay = <String, double>{};
    var unknown = false;
    for (final hit in hits) {
      final amount = _comparableAmount(hit, trigger, unit);
      if (amount == null) {
        unknown = true;
        continue;
      }
      final day = localDayKey(hit.event.at);
      perDay[day] = (perDay[day] ?? 0) + amount;
    }
    final maxDaily = perDay.isEmpty
        ? null
        : perDay.values.reduce((a, b) => a > b ? a : b);
    DoseThreshold? tier;
    if (maxDaily != null) {
      for (final threshold in rule.thresholds) {
        if (maxDaily >= threshold.amount) tier = threshold;
      }
    }
    return _Dose(maxDaily: maxDaily, unit: unit, tier: tier, unknown: unknown);
  }

  /// The event's amount in [unit], or null when it cannot be compared.
  ///
  /// Converted through [SubstanceConversions], which knows the IU of vitamin D
  /// and refuses anything it does not know — a refused conversion counts as an
  /// unknown dose, never as zero.
  double? _comparableAmount(
    _Hit hit,
    SubstanceTrigger trigger,
    CanonicalUnit unit,
  ) {
    if (!hit.match.doseComparable) return null;
    final amount = hit.event.amount;
    final from = CanonicalUnit.tryParse(hit.event.unit);
    if (amount == null || from == null) return null;
    final substanceId = hit.match.substanceId;
    final factor = trigger.massFactors[substanceId] ?? 1;
    final converted = conversions.convert(
      amount: amount,
      from: from,
      to: unit,
      substanceId: substanceId,
    );
    if (converted == null) return null;
    return converted * factor;
  }

  // ---------------------------------------------------------------- past

  Iterable<InteractionFinding> _pastFindings(
    InteractionRule rule,
    _Context context,
  ) sync* {
    final window = rule.thresholds.isNotEmpty
        ? rule.thresholds.last.lookback
        : rule.lookback;
    if (window == null || rule.affects.isEmpty) return;
    // One finding per affected biomarker, each carrying only what was taken
    // before *its* draws — a TSH finding must not borrow the dose that sat
    // before an unrelated troponin test.
    final byBiomarker = <String, _PastAccumulator>{};
    for (final measurement in context.measurements) {
      final match = context.affectedTestFor(rule, measurement.biomarkerId);
      if (match == null) continue;
      final exposure = _exposureBefore(rule, context, measurement.takenAt);
      if (exposure == null) continue;
      byBiomarker
          .putIfAbsent(match.biomarker.id, _PastAccumulator.new)
          .add(
            AffectedMeasurement(
              measurement: measurement,
              biomarker: match.biomarker,
              direction: match.direction,
              lastExposureAt: exposure.lastAt,
            ),
            exposure,
          );
    }
    for (final entry in byBiomarker.entries) {
      final past = entry.value;
      yield InteractionFinding(
        id: 'finding:${rule.id}@${entry.key}',
        rule: rule,
        scope: FindingScope.pastMeasurement,
        subjects: past.subjects.toList()..sort(),
        supplementIds: past.supplementIds,
        eventIds: past.eventIds,
        dailyAmount: past.maxDaily,
        amountUnit: rule.thresholds.isEmpty ? null : rule.thresholds.first.unit,
        doseKnown: past.doseKnown,
        window: past.window,
        affectedBiomarkerIds: {entry.key},
        measurements: past.measurements,
        lastExposureAt: past.measurements.last.lastExposureAt,
      );
    }
  }

  /// What of [rule]'s trigger was present in the window before [drawnAt].
  _Side? _exposureBefore(
    InteractionRule rule,
    _Context context,
    DateTime drawnAt,
  ) {
    switch (rule.trigger) {
      case SubstanceTrigger trigger:
        final hits = context.matches(trigger);
        if (rule.thresholds.isEmpty) {
          final window = rule.lookback!;
          final inWindow = _within(hits, drawnAt, window);
          if (inWindow.isEmpty) return null;
          return _Side(
            labels: context.labelsFor(inWindow),
            supplementIds: {for (final hit in inWindow) hit.event.supplementId},
            doseKnown: true,
            window: window,
            lastAt: inWindow.last.event.at,
          );
        }
        // Highest threshold first: a megadose a week before counts even when
        // nothing was taken in the last three days.
        for (final threshold in rule.thresholds.reversed) {
          final inWindow = _within(hits, drawnAt, threshold.lookback);
          if (inWindow.isEmpty) continue;
          final dose = _dose(rule, trigger, inWindow);
          if (dose.maxDaily != null && dose.maxDaily! >= threshold.amount) {
            return _Side(
              labels: context.labelsFor(inWindow),
              supplementIds: {
                for (final hit in inWindow) hit.event.supplementId,
              },
              dailyAmount: dose.maxDaily,
              amountUnit: dose.unit,
              doseKnown: true,
              window: threshold.lookback,
              lastAt: inWindow.last.event.at,
            );
          }
        }
        if (!rule.firesWhenDoseUnknown) return null;
        final lowest = rule.thresholds.first.lookback;
        final inWindow = _within(hits, drawnAt, lowest);
        final unknown = _dose(rule, trigger, inWindow);
        if (inWindow.isEmpty || !unknown.unknown) return null;
        return _Side(
          labels: context.labelsFor(inWindow),
          supplementIds: {for (final hit in inWindow) hit.event.supplementId},
          doseKnown: false,
          window: lowest,
          lastAt: inWindow.last.event.at,
        );
      case MedicationTrigger trigger:
        // Medication records carry no dose times, so only medicines logged
        // in the supplement ledger can be placed before a draw.
        final window = rule.lookback;
        if (window == null) return null;
        final inWindow = [
          for (final event in context.exposure.events)
            if (_isMedicationEvent(event, trigger) &&
                !event.at.isAfter(drawnAt) &&
                !event.at.isBefore(drawnAt.subtract(window)))
              event,
        ];
        if (inWindow.isEmpty) return null;
        return _Side(
          labels: {
            for (final event in inWindow) _catalog.displayNameFor(event.name),
          }.toList(),
          supplementIds: {for (final event in inWindow) event.supplementId},
          doseKnown: true,
          window: window,
          lastAt: inWindow.last.at,
        );
      case EventTrigger trigger:
        final window = rule.lookback!;
        final from = drawnAt.subtract(window);
        final inWindow = [
          for (final event in context.events)
            if (!event.observedAt.isAfter(drawnAt) &&
                !event.observedAt.isBefore(from) &&
                trigger.matchesName(event.name))
              event,
        ];
        if (inWindow.isEmpty) return null;
        return _Side(
          labels: {for (final event in inWindow) event.name}.toList(),
          eventIds: {for (final event in inWindow) event.id},
          doseKnown: true,
          window: window,
          lastAt: inWindow.last.observedAt,
        );
    }
  }

  bool _isMedicationEvent(DoseEvent event, MedicationTrigger trigger) {
    if (event.fromProductName) return false;
    final id = _catalog.idFor(event.name);
    return id != null &&
        _medicationCatalog
            .classIdsForSubstance(id)
            .any(trigger.classIds.contains);
  }

  static List<_Hit> _within(
    List<_Hit> hits,
    DateTime drawnAt,
    Duration window,
  ) {
    final from = drawnAt.subtract(window);
    return [
      for (final hit in hits)
        if (!hit.event.at.isAfter(drawnAt) && !hit.event.at.isBefore(from)) hit,
    ];
  }

  // ---------------------------------------------------------------- spacing

  /// Days in the recent window on which both sides were logged, and how many
  /// of those had a pair closer than the rule's minimum spacing.
  SpacingCheck? _spacing(
    InteractionRule rule,
    RuleTrigger partner,
    _Context context,
  ) {
    if (rule.trigger is! SubstanceTrigger || partner is! MedicationTrigger) {
      return null;
    }
    final trigger = rule.trigger as SubstanceTrigger;
    final now = context.exposure.now;
    final from = now.subtract(ExposureAnalysis.recentWindow);
    bool recent(DateTime at) => !at.isBefore(from) && !at.isAfter(now);
    final first = [
      for (final hit in context.matches(trigger))
        if (recent(hit.event.at)) hit.event.at,
    ];
    final second = [
      for (final event in context.exposure.events)
        if (recent(event.at) && _isMedicationEvent(event, partner)) event.at,
    ];
    if (first.isEmpty || second.isEmpty) return null;
    final spacing = rule.minimumSpacing!;
    final firstDays = {for (final at in first) localDayKey(at)};
    final secondDays = {for (final at in second) localDayKey(at)};
    final together = firstDays.intersection(secondDays);
    final tooClose = <String>{};
    for (final a in first) {
      for (final b in second) {
        if (a.difference(b).abs() < spacing) tooClose.add(localDayKey(b));
      }
    }
    return SpacingCheck(
      daysTogether: together.length,
      daysTooClose: tooClose.length,
    );
  }
}

class _Hit {
  const _Hit(this.event, this.match);

  final DoseEvent event;
  final SubstanceMatch match;
}

class _Dose {
  const _Dose({
    required this.maxDaily,
    required this.unit,
    required this.tier,
    required this.unknown,
  });

  final double? maxDaily;
  final CanonicalUnit unit;
  final DoseThreshold? tier;
  final bool unknown;
}

class _Side {
  const _Side({
    required this.labels,
    required this.doseKnown,
    this.supplementIds = const {},
    this.medicationRecordIds = const {},
    this.eventIds = const {},
    this.dailyAmount,
    this.amountUnit,
    this.window,
    this.lastAt,
  });

  final List<String> labels;
  final Set<String> supplementIds;
  final Set<String> medicationRecordIds;
  final Set<String> eventIds;
  final double? dailyAmount;
  final CanonicalUnit? amountUnit;
  final bool doseKnown;
  final Duration? window;
  final DateTime? lastAt;
}

class _PastAccumulator {
  final measurements = <AffectedMeasurement>[];
  final subjects = <String>{};
  final supplementIds = <String>{};
  final eventIds = <String>{};
  var doseKnown = true;
  double? maxDaily;
  Duration? window;

  void add(AffectedMeasurement measurement, _Side exposure) {
    measurements.add(measurement);
    subjects.addAll(exposure.labels);
    supplementIds.addAll(exposure.supplementIds);
    eventIds.addAll(exposure.eventIds);
    doseKnown = doseKnown && exposure.doseKnown;
    final amount = exposure.dailyAmount;
    if (amount != null && (maxDaily == null || amount > maxDaily!)) {
      maxDaily = amount;
    }
    final candidate = exposure.window;
    if (candidate != null && (window == null || candidate > window!)) {
      window = candidate;
    }
  }
}

class _AffectedBiomarker {
  const _AffectedBiomarker(this.biomarker, this.direction);

  final Biomarker biomarker;
  final EffectDirection direction;
}

/// Per-evaluation caches, so each rule matches ingredient names and resolves
/// biomarkers once rather than once per measurement.
class _Context {
  _Context({
    required this.exposure,
    required this.biomarkers,
    required this.measurements,
    required this.events,
  });

  final ExposureAnalysis exposure;
  final List<Biomarker> biomarkers;
  final List<Measurement> measurements;
  final List<HealthEvent> events;

  static const _catalog = SubstanceCatalog();

  final _matches = <SubstanceTrigger, List<_Hit>>{};
  final _conceptBiomarkers = <String, List<Biomarker>>{};
  final _ruleBiomarkers = <String, Map<String, _AffectedBiomarker>>{};

  late final Map<String, Biomarker> _biomarkersById = {
    for (final item in biomarkers) item.id: item,
  };

  List<_Hit> matches(SubstanceTrigger trigger) =>
      _matches.putIfAbsent(trigger, () {
        final byName = <String, SubstanceMatch?>{};
        return [
          for (final event in exposure.events)
            if (byName.putIfAbsent(event.name, () => trigger.match(event.name))
                case final match?)
              _Hit(event, match),
        ];
      });

  List<Biomarker> _biomarkersFor(BiomarkerConcept concept) =>
      _conceptBiomarkers.putIfAbsent(
        concept.id,
        () => [
          for (final item in biomarkers)
            if (concept.matches(item)) item,
        ],
      );

  Map<String, _AffectedBiomarker> _affected(InteractionRule rule) =>
      _ruleBiomarkers.putIfAbsent(rule.id, () {
        final result = <String, _AffectedBiomarker>{};
        for (final test in rule.affects) {
          for (final biomarker in _biomarkersFor(test.concept)) {
            result.putIfAbsent(
              biomarker.id,
              () => _AffectedBiomarker(biomarker, test.direction),
            );
          }
        }
        return result;
      });

  Set<String> biomarkerIdsFor(InteractionRule rule) =>
      _affected(rule).keys.toSet();

  _AffectedBiomarker? affectedTestFor(
    InteractionRule rule,
    String biomarkerId,
  ) {
    if (!_biomarkersById.containsKey(biomarkerId)) return null;
    return _affected(rule)[biomarkerId];
  }

  List<String> labelsFor(List<_Hit> hits) => {
    for (final hit in hits)
      hit.event.fromProductName
          ? hit.event.name
          : _catalog.displayNameFor(hit.event.name),
  }.toList()..sort();
}
