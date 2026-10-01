import '../domain/entities.dart';
import 'answer_text.dart';
import 'clinical_digest.dart';

/// The verdicts a coverage entry may give, as the model writes them.
const planCoverageVerdicts = ['addressed', 'not_needed'];

/// The `coverage` field of the plan's output schema.
///
/// Ids are an enum where the checklist has any, so a schema-constrained model
/// cannot answer to an item that does not exist. The schema cannot make it
/// answer to every item — that is what [assessPlanCoverage] checks.
Map<String, Object?> planCoverageSchema(List<ReviewItem> checklist) => {
  'type': 'array',
  'items': {
    'type': 'object',
    'properties': {
      'id': checklist.isEmpty
          ? {'type': 'string'}
          : {
              'type': 'string',
              'enum': [for (final item in checklist) item.id],
            },
      'verdict': {'type': 'string', 'enum': planCoverageVerdicts},
      'biomarker_ids': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'why': {'type': 'string'},
    },
    'required': ['id', 'verdict', 'biomarker_ids', 'why'],
    'additionalProperties': false,
  },
};

/// What the coverage array must say, for the draft, the repair and the
/// follow-up alike.
String planCoverageProtocol(List<ReviewItem> checklist) {
  if (checklist.isEmpty) {
    return 'review_checklist is empty: nothing current in this record needs '
        'accounting for, so coverage is an empty array.';
  }
  return 'coverage accounts for every review_checklist item '
      '(${checklist.length}) — each current substance, medicine, condition, '
      'goal, family history entry, finding and optional overdue test — '
      'exactly once, by id:\n'
      '{"id":"checklist id","verdict":"addressed|not_needed",'
      '"biomarker_ids":["planned test ids"],"why":"German sentence"}\n'
      '"addressed": a planned test monitors, screens for or confirms the '
      'item, or the preparation or a warning on a planned test deals with its '
      'effect on that test. biomarker_ids names those planned tests; an item '
      'can only be addressed by tests that are in this plan.\n'
      '"not_needed": the plan needs nothing for it. biomarker_ids is empty, and '
      'why says why for this profile — a recent enough result, no test whose '
      'result would change anything, no effect on any planned test.\n'
      'why is one short German sentence. Coverage is how the plan shows it '
      'considered everything in the record, not only what the priorities '
      'name: judge every item on its own merits, and add a test when one '
      'needs it.';
}

/// The coverage a plan gave, read against the checklist.
class PlanCoverageAssessment {
  const PlanCoverageAssessment({required this.entries, required this.missing});

  /// One entry per checklist item, in checklist order. An item the plan did
  /// not answer validly is [PlanCoverageVerdict.notConsidered].
  final List<PlanCoverage> entries;

  /// The items without a valid verdict.
  final List<ReviewItem> missing;

  bool get complete => missing.isEmpty;
}

/// Reads the model's `coverage` against the checklist and the planned tests.
///
/// Never throws: a missing or malformed verdict is a gap to ask about, then
/// to show, and never a reason to discard a plan. A verdict that claims a test
/// the plan does not contain is not a verdict — "addressed by ferritin" with
/// no ferritin planned would tell the reader something false — so it counts
/// as missing. The first entry for an id wins; ids not on the checklist are
/// ignored.
PlanCoverageAssessment assessPlanCoverage({
  required Object? raw,
  required List<ReviewItem> checklist,
  required Set<String> plannedBiomarkerIds,
}) {
  final answers = <String, Map<dynamic, dynamic>>{};
  if (raw is List) {
    for (final entry in raw.whereType<Map<dynamic, dynamic>>()) {
      final id = '${entry['id'] ?? ''}'.trim();
      if (id.isNotEmpty) answers.putIfAbsent(id, () => entry);
    }
  }
  final entries = <PlanCoverage>[];
  final missing = <ReviewItem>[];
  for (final raw in checklist) {
    // A record's name is optional below the UI — an import or a sync can
    // bring one without — and a plan must never fail to save over a label.
    final item = raw.label.trim().isEmpty
        ? ReviewItem(id: raw.id, label: raw.id, kind: raw.kind)
        : raw;
    final entry = _validEntry(item, answers[item.id], plannedBiomarkerIds);
    if (entry == null) missing.add(item);
    entries.add(
      entry ??
          PlanCoverage(
            id: item.id,
            kind: item.kind,
            label: item.label,
            verdict: PlanCoverageVerdict.notConsidered,
          ),
    );
  }
  return PlanCoverageAssessment(entries: entries, missing: missing);
}

PlanCoverage? _validEntry(
  ReviewItem item,
  Map<dynamic, dynamic>? answer,
  Set<String> planned,
) {
  if (answer == null) return null;
  final verdict = '${answer['verdict'] ?? ''}'.trim().toLowerCase().replaceAll(
    RegExp(r'[\s-]+'),
    '_',
  );
  // References are stripped as everywhere model prose becomes stored content:
  // they made the model point at a row, and nobody reads them afterwards.
  final why = withoutRecordReferences('${answer['why'] ?? ''}'.trim());
  final rawIds = answer['biomarker_ids'];
  final cited = [
    if (rawIds is List)
      for (final id in rawIds)
        if (planned.contains('$id')) '$id',
  ];
  switch (verdict) {
    case 'addressed':
      if (cited.isEmpty) return null;
      return PlanCoverage(
        id: item.id,
        kind: item.kind,
        label: item.label,
        verdict: PlanCoverageVerdict.addressed,
        biomarkerIds: {...cited}.toList(growable: false),
        why: why,
      );
    case 'not_needed':
      if (why.isEmpty) return null;
      return PlanCoverage(
        id: item.id,
        kind: item.kind,
        label: item.label,
        verdict: PlanCoverageVerdict.notNeeded,
        why: why,
      );
  }
  return null;
}
