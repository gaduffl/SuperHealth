import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/analysis/lab_plan_pricing.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  const pricing = LabPlanPricing();
  final createdAt = DateTime(2026, 1, 1);

  LabPlanItem item(String biomarkerId, double? price) => LabPlanItem(
    id: 'item-$biomarkerId',
    planId: 'plan',
    biomarkerId: biomarkerId,
    biomarkerName: biomarkerId,
    tier: LabTier.core,
    priority: 1,
    rationale: 'Test rationale',
    evidenceClass: EvidenceClass.guideline,
    priceEur: price,
  );

  BiomarkerPackage package(String id, double? price, {String? name}) =>
      BiomarkerPackage(
        id: id,
        name: name ?? id,
        priceEur: price,
        createdAt: createdAt,
        updatedAt: createdAt,
      );

  LabPlanCosting cost(
    List<LabPlanItem> items,
    List<BiomarkerPackage> packages,
    Map<String, Set<String>> members,
  ) => pricing.cost(
    items: items,
    packages: packages,
    membersByPackageId: members,
  );

  test('with no packages a plan is the sum of its priced tests', () {
    final result = cost(
      [item('a', 10), item('b', 20), item('c', null)],
      [],
      {},
    );
    expect(result.totalEur, 30);
    expect(result.appliedPackages, isEmpty);
    expect(result.unpricedIds, ['c']);
  });

  test('a bundle replaces its parts when it is cheaper', () {
    // The whole point: kleines Blutbild is a dozen markers for less than the
    // dozen cost apart.
    final result = cost(
      [item('hb', 8), item('wbc', 8), item('plt', 8), item('ferritin', 20)],
      [package('blutbild', 15, name: 'Kleines Blutbild')],
      {
        'blutbild': {'hb', 'wbc', 'plt'},
      },
    );
    // 15 for the bundle, 20 for the test it does not cover.
    expect(result.totalEur, 35);
    final applied = result.appliedPackages.single;
    expect(applied.coveredBiomarkerIds, ['hb', 'plt', 'wbc']);
    expect(applied.savingEur, 9);
    expect(result.individuallyPricedIds, ['ferritin']);
  });

  test('a bundle that costs more than its parts is not applied', () {
    final result = cost(
      [item('hb', 4), item('wbc', 4)],
      [package('blutbild', 15)],
      {
        'blutbild': {'hb', 'wbc'},
      },
    );
    expect(result.appliedPackages, isEmpty);
    expect(result.totalEur, 8);
  });

  test('a bundle covering one planned test is not worth applying', () {
    // It is that test's price under another name, and it would only make the
    // breakdown harder to read.
    final result = cost([item('hb', 30)], [package('blutbild', 15)], {
      'blutbild': {'hb', 'wbc', 'plt'},
    });
    expect(result.appliedPackages, isEmpty);
    expect(result.totalEur, 30);
  });

  test('a bundle prices tests that had no price of their own', () {
    // The comparison cannot be made, but the bundle turns an unknown into a
    // number — better than a plan that cannot state a total.
    final result = cost(
      [item('hb', null), item('wbc', null)],
      [package('blutbild', 15)],
      {
        'blutbild': {'hb', 'wbc'},
      },
    );
    expect(result.totalEur, 15);
    expect(result.unpricedIds, isEmpty);
    final applied = result.appliedPackages.single;
    expect(applied.allCoveredWerePriced, isFalse);
    // The saving is unknown, not zero.
    expect(applied.savingEur, isNull);
  });

  test('overlapping bundles do not both charge for the same test', () {
    // Kleines Blutbild is a subset of großes. Applying both would pay twice
    // for the markers they share.
    final result = cost(
      [item('hb', 8), item('wbc', 8), item('plt', 8), item('diff', 8)],
      [
        package('klein', 15, name: 'Kleines Blutbild'),
        package('gross', 22, name: 'Großes Blutbild'),
      ],
      {
        'klein': {'hb', 'wbc', 'plt'},
        'gross': {'hb', 'wbc', 'plt', 'diff'},
      },
    );
    // Großes saves 10 against 32; kleines saves 9 against 24. The larger
    // saving wins, and kleines then covers nothing left.
    expect(result.appliedPackages.single.package.id, 'gross');
    expect(result.totalEur, 22);
    expect(result.individuallyPricedIds, isEmpty);
  });

  test('two disjoint bundles both apply', () {
    final result = cost(
      [item('hb', 8), item('wbc', 8), item('t3', 12), item('t4', 12)],
      [package('blut', 10), package('thyroid', 16)],
      {
        'blut': {'hb', 'wbc'},
        'thyroid': {'t3', 't4'},
      },
    );
    expect(result.appliedPackages.map((item) => item.package.id).toSet(), {
      'blut',
      'thyroid',
    });
    expect(result.totalEur, 26);
  });

  test('a package with no price of its own is ignored', () {
    // Including a zero: a bundle that costs nothing does not exist, and
    // applying it would drop the covered tests out of the total entirely.
    for (final price in [null, 0.0]) {
      final result = cost(
        [item('hb', 8), item('wbc', 8)],
        [package('blutbild', price)],
        {
          'blutbild': {'hb', 'wbc'},
        },
      );
      expect(result.appliedPackages, isEmpty, reason: '$price');
      expect(result.totalEur, 16, reason: '$price');
    }
  });

  test('a deleted package is not applied', () {
    final result = cost(
      [item('hb', 8), item('wbc', 8)],
      [
        BiomarkerPackage(
          id: 'blutbild',
          name: 'Blutbild',
          priceEur: 5,
          createdAt: createdAt,
          updatedAt: createdAt,
          deleted: true,
        ),
      ],
      {
        'blutbild': {'hb', 'wbc'},
      },
    );
    expect(result.appliedPackages, isEmpty);
    expect(result.totalEur, 16);
  });

  test('a duplicated test across tiers keeps its price', () {
    // A plan lists the same biomarker once per tier, and the copy in a later
    // tier may carry no price. It must not erase the one that does.
    final result = cost([item('hb', 8), item('hb', null)], [], {});
    expect(result.totalEur, 8);
    expect(result.unpricedIds, isEmpty);
  });
}
