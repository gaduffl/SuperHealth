import '../domain/entities.dart';

/// A package applied to a plan, and which of the plan's tests it covers.
class AppliedPackage {
  const AppliedPackage({
    required this.package,
    required this.coveredBiomarkerIds,
    required this.individualTotalEur,
    required this.allCoveredWerePriced,
  });

  final BiomarkerPackage package;
  final List<String> coveredBiomarkerIds;

  /// What the covered tests would have cost bought singly, counting only the
  /// ones that had a price of their own.
  final double individualTotalEur;

  /// Whether every covered test had its own price. When false the saving is
  /// unknown rather than zero — the bundle replaced an unknown with a number.
  final bool allCoveredWerePriced;

  double? get savingEur =>
      allCoveredWerePriced ? individualTotalEur - package.priceEur! : null;
}

/// What a tier costs once packages are taken into account.
class LabPlanCosting {
  const LabPlanCosting({
    required this.totalEur,
    required this.appliedPackages,
    required this.individuallyPricedIds,
    required this.unpricedIds,
  });

  final double totalEur;
  final List<AppliedPackage> appliedPackages;

  /// Planned tests paid for singly because no package covered them.
  final List<String> individuallyPricedIds;

  /// Planned tests still without any price, singly or in a package.
  final List<String> unpricedIds;

  int get unpricedCount => unpricedIds.length;
}

/// Costs a set of planned tests, preferring a bundle over its parts.
///
/// Deliberately pure and separate from `LabPlan`, because the choice of which
/// packages to apply is a real decision with trade-offs rather than a sum, and
/// it needs to be readable and testable on its own.
class LabPlanPricing {
  const LabPlanPricing();

  /// A bundle has to cover at least this many planned tests to be considered.
  ///
  /// A package covering one test is just that test's price under another name,
  /// and applying it would make the breakdown harder to read for no gain.
  static const minimumCoverage = 2;

  LabPlanCosting cost({
    required List<LabPlanItem> items,
    required List<BiomarkerPackage> packages,
    required Map<String, Set<String>> membersByPackageId,
  }) {
    final priceById = <String, double?>{};
    for (final item in items) {
      // A plan can list the same biomarker once per tier; the first price wins,
      // and a later unpriced duplicate must not erase it.
      priceById.putIfAbsent(item.biomarkerId, () => null);
      if (hasLabPrice(item.priceEur)) {
        priceById[item.biomarkerId] = item.priceEur;
      }
    }
    final remaining = priceById.keys.toSet();

    // Candidates are scored once against the full plan, then applied in order,
    // skipping any whose tests a better package already took. Greedy rather
    // than exhaustive: the alternative is a set-cover search, and a catalog of
    // hand-entered packages does not justify one.
    final candidates = <_Candidate>[];
    for (final package in packages) {
      if (package.deleted || !package.hasPrice) continue;
      final members = membersByPackageId[package.id] ?? const <String>{};
      final covered = members.where(remaining.contains).toList()..sort();
      if (covered.length < minimumCoverage) continue;
      final individual = covered
          .map((id) => priceById[id])
          .where(hasLabPrice)
          .fold<double>(0, (total, price) => total + price!);
      final allPriced = covered.every((id) => hasLabPrice(priceById[id]));
      // A bundle that costs more than its parts is not a saving, so it is not
      // applied. When a covered test has no price of its own the comparison
      // cannot be made — but the bundle turns an unknown into a number, which
      // is strictly better than leaving the plan unable to state a total.
      if (allPriced && package.priceEur! >= individual) continue;
      candidates.add(
        _Candidate(
          package: package,
          covered: covered,
          individual: individual,
          allPriced: allPriced,
          // Unknown savings sort by how much of the plan they resolve, which
          // keeps the ordering total without inventing a number.
          score: allPriced
              ? individual - package.priceEur!
              : covered.length.toDouble(),
        ),
      );
    }
    candidates.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      // Ties broken by name so the same plan always costs the same way.
      return a.package.name.compareTo(b.package.name);
    });

    final applied = <AppliedPackage>[];
    var total = 0.0;
    for (final candidate in candidates) {
      final covered = candidate.covered.where(remaining.contains).toList();
      if (covered.length < minimumCoverage) continue;
      remaining.removeAll(covered);
      total += candidate.package.priceEur!;
      applied.add(
        AppliedPackage(
          package: candidate.package,
          coveredBiomarkerIds: List.unmodifiable(covered),
          individualTotalEur: covered
              .map((id) => priceById[id])
              .where(hasLabPrice)
              .fold<double>(0, (sum, price) => sum + price!),
          allCoveredWerePriced: covered.every(
            (id) => hasLabPrice(priceById[id]),
          ),
        ),
      );
    }

    final individually = <String>[];
    final unpriced = <String>[];
    for (final id in remaining) {
      final price = priceById[id];
      if (hasLabPrice(price)) {
        total += price!;
        individually.add(id);
      } else {
        unpriced.add(id);
      }
    }
    individually.sort();
    unpriced.sort();

    return LabPlanCosting(
      totalEur: total,
      appliedPackages: List.unmodifiable(applied),
      individuallyPricedIds: List.unmodifiable(individually),
      unpricedIds: List.unmodifiable(unpriced),
    );
  }
}

class _Candidate {
  const _Candidate({
    required this.package,
    required this.covered,
    required this.individual,
    required this.allPriced,
    required this.score,
  });

  final BiomarkerPackage package;
  final List<String> covered;
  final double individual;
  final bool allPriced;
  final double score;
}
