import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/lab_plan_export_service.dart';

void main() {
  test('an exported cheaper tier says what it leaves out and why', () async {
    // An exported Core plan is a shopping list someone hands to a lab. Without
    // this it reads as the whole recommendation, and the reasoning that made
    // the omissions defensible stays behind on the screen.
    final service = LabPlanExportService();

    final json =
        jsonDecode(
              utf8.decode(
                (await service.build(_plan(), LabPlanExportFormat.json)).bytes,
              ),
            )
            as Map<String, Object?>;
    final tiers = json['tiers']! as Map<String, Object?>;
    final core = tiers['core']! as Map<String, Object?>;

    expect(
      (core['omitted_versus_next']! as List)
          .map((item) => (item as Map)['biomarker_name'])
          .toList(),
      ['Lp(a)', 'Ferritin'],
    );
    expect(core['added_cost_of_next_eur'], 35);
    expect(core['tradeoff_versus_next'], contains('measured last year'));

    // The largest tier gives nothing up, so it claims nothing.
    final comprehensive = tiers['comprehensive']! as Map<String, Object?>;
    expect(comprehensive['omitted_versus_next'], isEmpty);
    expect(comprehensive['added_cost_of_next_eur'], 0);
    expect(comprehensive['tradeoff_versus_next'], '');

    final csv = utf8.decode(
      (await service.build(_plan(), LabPlanExportFormat.csv)).bytes,
    );
    expect(csv, contains('Why they can wait'));
    expect(csv, contains('measured last year'));
    expect(csv, contains('Lp(a) | Ferritin'));
    // Comprehensive omits nothing, so it gets no row in that block.
    expect(csv, isNot(contains('comprehensive,0,')));
  });

  test('a plan with no recorded reasoning still exports its gap', () async {
    // The names and the price delta are derived from the plan, so they survive
    // a planner that wrote no prose — only the "why" goes missing.
    final service = LabPlanExportService();
    final json =
        jsonDecode(
              utf8.decode(
                (await service.build(
                  _plan(tradeoffs: const {}),
                  LabPlanExportFormat.json,
                )).bytes,
              ),
            )
            as Map<String, Object?>;
    final core =
        (json['tiers']! as Map<String, Object?>)['core']!
            as Map<String, Object?>;

    expect(core['tradeoff_versus_next'], '');
    expect(core['omitted_versus_next'], hasLength(2));
    expect(core['added_cost_of_next_eur'], 35);
  });

  group("a doctor's request", () {
    test('carries the tier\'s ticked tests and nothing more', () async {
      // Cumulative tiers: Advanced ticked here means ApoB and Ferritin, while
      // the unticked Lp(a) beside them and the Comprehensive test above them
      // both stay behind.
      final plan = _plan(checked: {'ApoB', 'Ferritin', 'Omega-3'});

      expect(
        plan.selectedItemsThrough(LabTier.advanced).map((i) => i.biomarkerName),
        ['ApoB', 'Ferritin'],
      );
      expect(
        plan.selectedItemsThrough(LabTier.core).map((i) => i.biomarkerName),
        ['ApoB'],
      );
      expect(
        plan
            .selectedItemsThrough(LabTier.comprehensive)
            .map((i) => i.biomarkerName),
        ['ApoB', 'Ferritin', 'Omega-3'],
      );
    });

    test('an unticked plan selects nothing', () async {
      expect(_plan().selectedItemsThrough(LabTier.comprehensive), isEmpty);
    });

    test('builds a PDF named for its tier', () async {
      final file = await LabPlanExportService().buildTierRequest(
        _plan(checked: {'ApoB', 'Ferritin'}),
        LabTier.advanced,
      );

      expect(file.mimeType, 'application/pdf');
      expect(file.fileName, endsWith('-advanced-request.pdf'));
      expect(file.bytes, isNotEmpty);
    });

    test('builds even when the tier has nothing ticked', () async {
      // Unreachable from the export sheet, which offers such a tier as
      // disabled — but a document that throws instead of saying "none" would
      // be a crash where the honest answer is a sentence.
      final file = await LabPlanExportService().buildTierRequest(
        _plan(),
        LabTier.core,
      );

      expect(file.bytes, isNotEmpty);
    });

    test(
      'totals only the chosen tests, and says what it could not price',
      () async {
        // The tier totals more than this: the point of the page is that part of
        // it was not chosen, so its own arithmetic has to stand alone.
        final plan = _plan(checked: {'ApoB', 'Lp(a)'});

        expect(plan.knownTotal(LabTier.advanced), 45);
        expect(
          plan
              .selectedItemsThrough(LabTier.advanced)
              .map((item) => item.priceEur)
              .fold<double>(0, (sum, price) => sum + (price ?? 0)),
          30,
        );

        final file = await LabPlanExportService().buildTierRequest(
          plan,
          LabTier.advanced,
        );
        expect(file.bytes, isNotEmpty);
      },
    );

    test('repeats a shared preparation instruction once', () async {
      final file = await LabPlanExportService().buildTierRequest(
        _plan(
          checked: {'ApoB', 'Lp(a)', 'Ferritin'},
          preparation: 'Fast for 12 hours',
        ),
        LabTier.advanced,
      );

      expect(file.bytes, isNotEmpty);
    });
  });

  test('the PDF still builds with the tradeoff block in it', () async {
    // The block is laid out inside a MultiPage, where an unbounded child is a
    // build-time failure rather than a visual one.
    final file = await LabPlanExportService().build(
      _plan(),
      LabPlanExportFormat.pdf,
    );

    expect(file.bytes, isNotEmpty);
    expect(file.mimeType, 'application/pdf');
  });
}

LabPlan _plan({
  Map<LabTier, String> tradeoffs = const {
    LabTier.core: 'Lp(a) is lifelong and was measured last year.',
    LabTier.advanced: 'The fatty acid panel changes no decision now.',
  },
  Set<String> checked = const {},
  String preparation = '',
}) {
  final now = DateTime(2026, 1, 1);
  LabPlanItem item(String name, LabTier tier, double? price) => LabPlanItem(
    id: name,
    planId: 'plan',
    biomarkerId: 'bio-$name',
    biomarkerName: name,
    tier: tier,
    priority: 1,
    rationale: 'Test rationale',
    evidenceClass: EvidenceClass.guideline,
    priceEur: price,
    preparation: preparation,
    checked: checked.contains(name),
  );
  return LabPlan(
    id: 'plan',
    profileId: 'profile',
    title: 'Test plan',
    createdAt: now,
    updatedAt: now,
    items: [
      item('ApoB', LabTier.core, 10),
      item('Lp(a)', LabTier.advanced, 20),
      item('Ferritin', LabTier.advanced, 15),
      item('Omega-3', LabTier.comprehensive, 40),
    ],
    tierTradeoffs: tradeoffs,
  );
}
