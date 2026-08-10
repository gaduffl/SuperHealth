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

  test('a zero-priced item is unpriced, not free', () {
    // A legacy import writes 0 where its source had no price. Counting that as
    // a real price made a tier total as if those tests cost nothing, which
    // understates what the plan actually asks someone to spend.
    LabPlanItem item(String id, double? price) => LabPlanItem(
      id: id,
      planId: 'plan',
      biomarkerId: 'bio-$id',
      biomarkerName: id,
      tier: LabTier.core,
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
      items: [item('priced', 12), item('zero', 0), item('absent', null)],
    );

    expect(plan.knownTotal(LabTier.core), 12);
    // Both the zero and the null are prices nobody has looked up yet.
    expect(plan.missingPriceCount(LabTier.core), 2);
  });

  test('a cheaper tier names what it gives up and what that would cost', () {
    // A cheaper plan without this is just a shorter list: nothing on screen
    // tells the reader whether the missing tests were reasoned about.
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
        item('apoB', LabTier.core, 10),
        item('lp(a)', LabTier.advanced, 20),
        item('ferritin', LabTier.advanced, 15),
        item('omega-3', LabTier.comprehensive, 40),
      ],
      tierTradeoffs: const {
        LabTier.core: 'Lp(a) is lifelong and was measured last year.',
        LabTier.advanced: 'The fatty acid panel changes no decision now.',
      },
    );

    // The gap is derived from the plan, so it can never disagree with it.
    expect(plan.itemsOmittedVersusNext(LabTier.core).map((i) => i.id), [
      'lp(a)',
      'ferritin',
    ]);
    expect(plan.addedCostOfNext(LabTier.core), 35);
    expect(plan.tradeoffFor(LabTier.core), contains('Lp(a)'));

    expect(plan.itemsOmittedVersusNext(LabTier.advanced).map((i) => i.id), [
      'omega-3',
    ]);
    expect(plan.addedCostOfNext(LabTier.advanced), 40);

    // The largest tier gives up nothing, so it has no next tier, no gap, and
    // no reasoning to show.
    expect(LabPlan.nextTierAfter(LabTier.comprehensive), isNull);
    expect(plan.itemsOmittedVersusNext(LabTier.comprehensive), isEmpty);
    expect(plan.addedCostOfNext(LabTier.comprehensive), 0);
    expect(plan.tradeoffFor(LabTier.comprehensive), isEmpty);
  });

  test('the tradeoffs survive a round trip through the database map', () {
    final now = DateTime(2026, 1, 1);
    final plan = LabPlan(
      id: 'plan',
      profileId: 'profile',
      title: 'Test plan',
      createdAt: now,
      updatedAt: now,
      items: const [],
      tierTradeoffs: const {LabTier.core: 'Reasoning, in the user language.'},
    );

    final restored = LabPlan.fromMap(plan.toMap(), const []);

    expect(restored.tierTradeoffs, {
      LabTier.core: 'Reasoning, in the user language.',
    });
  });

  test('an unreadable tradeoff column costs the plan nothing', () {
    // Plans written before the column exists read back as '{}', and a hand-
    // edited or corrupted value must not take the whole plan with it.
    final now = DateTime(2026, 1, 1);
    final base = LabPlan(
      id: 'plan',
      profileId: 'profile',
      title: 'Test plan',
      createdAt: now,
      updatedAt: now,
      items: const [],
    ).toMap();

    for (final stored in ['', '{}', '{"nonsense":"x","core":""}']) {
      final restored = LabPlan.fromMap({
        ...base,
        'tier_tradeoffs_json': stored,
      }, const []);
      expect(restored.tierTradeoffs, isEmpty, reason: 'stored: $stored');
    }
  });

  test('copyWith carries every field it does not replace', () {
    // Two call sites used to re-list every field by hand to change one, which
    // is how a newly added field silently stops being persisted.
    final now = DateTime(2026, 1, 1);
    final plan = LabPlan(
      id: 'plan',
      profileId: 'profile',
      title: 'Test plan',
      createdAt: now,
      updatedAt: now,
      plannedFor: DateTime(2026, 2, 1),
      contextHash: 'hash',
      provider: 'openai',
      model: 'model',
      verificationWarnings: const ['warn'],
      verificationCitations: const ['cite'],
      items: const [],
      tierTradeoffs: const {LabTier.advanced: 'Kept.'},
    );

    final verified = plan.copyWith(
      status: 'verified',
      verificationSummary: 'Approved.',
      verifiedAt: now,
    );

    expect(verified.status, 'verified');
    expect(verified.tierTradeoffs, {LabTier.advanced: 'Kept.'});
    expect(verified.contextHash, 'hash');
    expect(verified.provider, 'openai');
    expect(verified.model, 'model');
    expect(verified.plannedFor, DateTime(2026, 2, 1));
    expect(verified.verificationWarnings, ['warn']);
    expect(verified.verificationCitations, ['cite']);
  });
}
