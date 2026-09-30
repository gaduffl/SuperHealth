import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/lab_planner_service.dart';
import 'package:super_health/analysis/exposure_analysis.dart';
import 'package:super_health/analysis/interaction_findings.dart';
import 'package:super_health/domain/entities.dart';

final _now = DateTime.utc(2026, 9, 30, 12);

LabPlanItem _item(String biomarkerId, {String preparation = ''}) => LabPlanItem(
  id: 'item-$biomarkerId',
  planId: 'plan',
  biomarkerId: biomarkerId,
  biomarkerName: biomarkerId.toUpperCase(),
  tier: LabTier.core,
  priority: 1,
  rationale: 'Because.',
  evidenceClass: EvidenceClass.guideline,
  priceEur: 12.5,
  preparation: preparation,
  checked: true,
  createdAt: _now,
  updatedAt: _now,
);

LabPlan _plan(List<LabPlanItem> items) => LabPlan(
  id: 'plan',
  profileId: 'p',
  title: 'Plan',
  createdAt: _now,
  updatedAt: _now,
  items: items,
);

List<InteractionFinding> _findings({required Duration lastBiotinAgo}) {
  final supplement = Supplement(
    id: 'hair',
    name: 'Hair',
    ingredients: const [
      {'name': 'Biotin', 'amount': 10, 'unit': 'mg'},
    ],
    createdAt: _now,
    updatedAt: _now,
  );
  final at = _now.subtract(lastBiotinAgo);
  final exposure = ExposureAnalysis.build(
    supplements: [supplement],
    schedules: const [],
    intakes: [
      SupplementIntake(
        id: 'dose',
        profileId: 'p',
        supplementId: 'hair',
        takenAt: at,
        dose: 1,
        unit: 'capsule',
        createdAt: _now,
        updatedAt: _now,
      ),
    ],
    records: const [],
    now: _now,
  );
  Biomarker marker(String id) => Biomarker(
    id: id,
    canonicalName: id,
    displayName: id,
    createdAt: _now,
    updatedAt: _now,
  );
  return const InteractionFindingsEngine().evaluate(
    exposure: exposure,
    biomarkers: [marker('tsh'), marker('crea')],
    measurements: [
      Measurement(
        id: 'm',
        profileId: 'p',
        biomarkerId: 'tsh',
        takenAt: at.add(const Duration(hours: 10)),
        value: 0.3,
        unit: 'mU/L',
        createdAt: _now,
        updatedAt: _now,
      ),
    ],
    events: const [],
  );
}

void main() {
  test('a current finding writes its note into the tests it affects, once', () {
    final plan = withFindingPreparation(
      _plan([_item('tsh'), _item('crea', preparation: 'Nüchtern.')]),
      _findings(lastBiotinAgo: const Duration(days: 1)),
    );

    expect(
      plan.items.first.preparation,
      'Biotin mind. 72 Std. vorher pausieren (ab 100 mg/Tag etwa eine '
      'Woche) und dem Labor mitteilen.',
    );
    expect(plan.items.last.preparation, 'Nüchtern.');
  });

  test('a preparation that already mentions it is left as the model wrote '
      'it', () {
    final plan = withFindingPreparation(
      _plan([_item('tsh', preparation: 'Biotin 3 Tage vorher absetzen.')]),
      _findings(lastBiotinAgo: const Duration(days: 1)),
    );

    expect(plan.items.single.preparation, 'Biotin 3 Tage vorher absetzen.');
  });

  test('a finding about a past draw alone adds no preparation', () {
    // Biotin stopped months ago: the old TSH is suspect, a new draw is not.
    final findings = _findings(lastBiotinAgo: const Duration(days: 120));
    expect(
      findings.map((finding) => finding.scope),
      everyElement(FindingScope.pastMeasurement),
    );

    final plan = withFindingPreparation(_plan([_item('tsh')]), findings);

    expect(plan.items.single.preparation, isEmpty);
  });

  test('copyWith carries every field it does not replace', () {
    final item = _item('tsh', preparation: 'Old.');
    final copy = item.copyWith(preparation: 'New.');

    expect(copy.preparation, 'New.');
    expect(
      copy.toMap()..remove('preparation'),
      item.toMap()..remove('preparation'),
    );
    expect(item.copyWith(checked: false).checked, isFalse);
  });
}
