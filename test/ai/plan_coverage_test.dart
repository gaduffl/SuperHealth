import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/clinical_digest.dart';
import 'package:super_health/ai/plan_coverage.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  const checklist = [
    ReviewItem(id: 'exp:biotin', label: 'Biotin', kind: 'substance'),
    ReviewItem(id: 'med:levo', label: 'L-Thyroxin', kind: 'medication'),
    ReviewItem(
      id: 'finding:biotin-streptavidin-immunoassay',
      label: 'Biotin interference',
      kind: 'finding',
    ),
  ];
  const planned = {'tsh', 'ft4'};

  Map<String, Object?> answer(
    String id,
    String verdict, {
    List<String> tests = const [],
    String why = 'Begründung.',
  }) => {'id': id, 'verdict': verdict, 'biomarker_ids': tests, 'why': why};

  test('a complete answer keeps checklist order, kinds and labels', () {
    final assessment = assessPlanCoverage(
      raw: [
        answer('med:levo', 'not_needed'),
        answer('exp:biotin', 'addressed', tests: ['tsh', 'ft4']),
        answer(
          'finding:biotin-streptavidin-immunoassay',
          'addressed',
          tests: ['tsh'],
        ),
      ],
      checklist: checklist,
      plannedBiomarkerIds: planned,
    );

    expect(assessment.complete, isTrue);
    expect(assessment.entries.map((entry) => entry.id), [
      for (final item in checklist) item.id,
    ]);
    expect(assessment.entries.first.kind, 'substance');
    expect(assessment.entries.first.label, 'Biotin');
    expect(assessment.entries.first.biomarkerIds, ['tsh', 'ft4']);
    expect(assessment.entries[1].verdict, PlanCoverageVerdict.notNeeded);
  });

  test('an unanswered item is missing and stored as not considered', () {
    final assessment = assessPlanCoverage(
      raw: [answer('exp:biotin', 'not_needed')],
      checklist: checklist,
      plannedBiomarkerIds: planned,
    );

    expect(assessment.missing.map((item) => item.id), [
      'med:levo',
      'finding:biotin-streptavidin-immunoassay',
    ]);
    expect(
      assessment.entries.where(
        (entry) => entry.verdict == PlanCoverageVerdict.notConsidered,
      ),
      hasLength(2),
    );
  });

  test('"addressed by" a test the plan does not contain is not a verdict', () {
    // "Addressed by ferritin" with no ferritin planned would tell the reader
    // something false. A stray id beside a real one is simply dropped.
    final assessment = assessPlanCoverage(
      raw: [
        answer('exp:biotin', 'addressed', tests: ['ferritin']),
        answer('med:levo', 'addressed', tests: ['ferritin', 'tsh']),
      ],
      checklist: checklist,
      plannedBiomarkerIds: planned,
    );

    expect(assessment.missing.map((item) => item.id), contains('exp:biotin'));
    final levo = assessment.entries.singleWhere(
      (entry) => entry.id == 'med:levo',
    );
    expect(levo.verdict, PlanCoverageVerdict.addressed);
    expect(levo.biomarkerIds, ['tsh']);
  });

  test('"not needed" without a reason is not a verdict', () {
    final assessment = assessPlanCoverage(
      raw: [answer('exp:biotin', 'not_needed', why: '  ')],
      checklist: checklist,
      plannedBiomarkerIds: planned,
    );

    expect(assessment.missing.first.id, 'exp:biotin');
  });

  test('the first answer for an id wins and unknown ids are ignored', () {
    final assessment = assessPlanCoverage(
      raw: [
        answer('exp:biotin', 'not_needed', why: 'Erste Antwort.'),
        answer('exp:biotin', 'addressed', tests: ['tsh']),
        answer('exp:invented', 'not_needed'),
      ],
      checklist: checklist,
      plannedBiomarkerIds: planned,
    );

    final biotin = assessment.entries.first;
    expect(biotin.verdict, PlanCoverageVerdict.notNeeded);
    expect(biotin.why, 'Erste Antwort.');
    expect(
      assessment.entries.map((entry) => entry.id),
      isNot(contains('exp:invented')),
    );
  });

  test('a malformed coverage field is a gap, never a thrown plan', () {
    for (final raw in [
      null,
      'nonsense',
      42,
      <Object?>['x', 7],
    ]) {
      final assessment = assessPlanCoverage(
        raw: raw,
        checklist: checklist,
        plannedBiomarkerIds: planned,
      );
      expect(assessment.missing, hasLength(checklist.length), reason: '$raw');
    }
  });

  test('verdict spellings outside the schema are read where unambiguous', () {
    // A provider without schema-constrained output writes what it likes.
    final assessment = assessPlanCoverage(
      raw: [
        answer('exp:biotin', 'Not needed'),
        answer('med:levo', 'NOT-NEEDED'),
      ],
      checklist: checklist,
      plannedBiomarkerIds: planned,
    );

    expect(assessment.entries[0].verdict, PlanCoverageVerdict.notNeeded);
    expect(assessment.entries[1].verdict, PlanCoverageVerdict.notNeeded);
  });

  test('record references are removed from the reason', () {
    final assessment = assessPlanCoverage(
      raw: [
        answer(
          'exp:biotin',
          'not_needed',
          why:
              'Seit Wochen pausiert '
              '(measurements:0f8fad5b-d9cb-469f-a165-70867728950e).',
        ),
      ],
      checklist: checklist,
      plannedBiomarkerIds: planned,
    );

    expect(assessment.entries.first.why, isNot(contains('0f8fad5b')));
    expect(assessment.entries.first.why, startsWith('Seit Wochen pausiert'));
  });

  test('the schema pins ids to the checklist and every field is required', () {
    final schema = planCoverageSchema(checklist);
    final item = schema['items']! as Map<String, Object?>;
    final properties = item['properties']! as Map<String, Object?>;

    expect((properties['id']! as Map)['enum'], [
      for (final entry in checklist) entry.id,
    ]);
    expect(item['required'], ['id', 'verdict', 'biomarker_ids', 'why']);
    expect(item['additionalProperties'], isFalse);
    // An empty enum is not a valid schema, so an empty checklist allows any
    // string — there is nothing to answer to anyway.
    final empty = planCoverageSchema(const []);
    final emptyItem = empty['items']! as Map<String, Object?>;
    expect(
      ((emptyItem['properties']! as Map)['id']! as Map).containsKey('enum'),
      isFalse,
    );
  });

  test('an item without a name is labelled by its id, never left blank', () {
    // A blank label would fail the plan's save validation, and a plan must
    // not be lost over the name of one record.
    final assessment = assessPlanCoverage(
      raw: const [],
      checklist: const [
        ReviewItem(id: 'record-1', label: ' ', kind: 'condition'),
      ],
      plannedBiomarkerIds: planned,
    );

    expect(assessment.entries.single.label, 'record-1');
  });

  test('the protocol names how many items must be answered', () {
    expect(planCoverageProtocol(checklist), contains('(3)'));
    expect(planCoverageProtocol(const []), contains('empty array'));
  });
}
