import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  test('lab plan tiers are cumulative and prices are deterministic', () {
    LabPlanItem item(String id, LabTier tier, double? price) => LabPlanItem(
      id: id,
      planId: 'plan',
      biomarkerId: 'bio-$id',
      biomarkerName: id,
      tier: tier,
      priority: 1,
      rationale: 'Test rationale',
      evidenceClass: EvidenceClass.guideline,
      priceEur: price,
    );

    final now = DateTime(2026, 1, 1);
    final plan = LabPlan(
      id: 'plan',
      profileId: 'profile',
      title: 'Test plan',
      createdAt: now,
      updatedAt: now,
      items: [
        item('core', LabTier.core, 10),
        item('advanced', LabTier.advanced, 20),
        item('comprehensive', LabTier.comprehensive, null),
      ],
    );

    expect(plan.itemsThrough(LabTier.core).map((item) => item.id), ['core']);
    expect(plan.itemsThrough(LabTier.advanced).map((item) => item.id), [
      'core',
      'advanced',
    ]);
    expect(plan.itemsThrough(LabTier.comprehensive), hasLength(3));
    expect(plan.knownTotal(LabTier.comprehensive), 30);
    expect(plan.missingPriceCount(LabTier.comprehensive), 1);
  });
}
