import 'units.dart';

/// Conversions that are only valid for one named substance.
///
/// There is no general IU↔µg factor. One IU of vitamin D is 0.025 µg, one IU of
/// vitamin A is 0.3 µg retinol, and one IU of vitamin E is 0.67 mg — same unit
/// symbol, three different meanings. Applying any of them to the wrong
/// substance silently misreports a dose, which is worse than showing two
/// separate series, so this table is deliberately tiny and covers only the
/// substances where the conversion is both well-defined and needed.
///
/// Sources are the standard equivalences used on European supplement labelling
/// (EU Regulation 1169/2011 Annex XIII for the vitamin A and E equivalents).
class SubstanceConversions {
  const SubstanceConversions();

  /// Substance key → the factors defined for it.
  ///
  /// Keys are matched against the canonical substance id, so "Vitamin D3",
  /// "Vitamin D", and "Cholecalciferol" all resolve here through
  /// [SubstanceCatalog] rather than needing their own entries.
  static const _factors = <String, _SubstanceFactors>{
    'vitamin-d': _SubstanceFactors(
      // 1 IU cholecalciferol = 0.025 µg.
      iuPerMicrogram: 40,
    ),
    'vitamin-a': _SubstanceFactors(
      // 1 IU retinol = 0.3 µg RE.
      iuPerMicrogram: 1 / 0.3,
      equivalentUnit: CanonicalUnit.microgramRetinolEquivalent,
      // Retinol equivalents are µg of retinol, so the mass factor is 1:1.
      massPerEquivalent: 1,
    ),
    'vitamin-e': _SubstanceFactors(
      // 1 IU synthetic α-tocopherol = 0.45 mg; natural = 0.67 mg. Labels in
      // the EU are stated in mg α-TE, so the natural equivalence is used.
      iuPerMilligram: 1 / 0.67,
      equivalentUnit: CanonicalUnit.milligramAlphaTocopherolEquivalent,
      massPerEquivalent: 1,
    ),
  };

  /// Whether a substance-scoped conversion exists at all.
  bool supports(String? substanceId) =>
      substanceId != null && _factors.containsKey(substanceId);

  /// Converts [amount] from [from] to [to] for one substance.
  ///
  /// Falls back to the plain within-domain conversion when both units share a
  /// domain, so callers can use this as the single entry point. Returns null
  /// when the conversion is not defined, which callers must treat as "keep the
  /// series separate" rather than as zero.
  double? convert({
    required double amount,
    required CanonicalUnit from,
    required CanonicalUnit to,
    String? substanceId,
  }) {
    if (from == to) return amount;
    final plain = convertWithinDomain(amount, from, to);
    if (plain != null) return plain;

    final factors = substanceId == null ? null : _factors[substanceId];
    if (factors == null) return null;

    final asBaseMassGrams = _toGrams(amount, from, factors);
    if (asBaseMassGrams == null) return null;
    return _fromGrams(asBaseMassGrams, to, factors);
  }

  /// Everything [from] can be converted into for this substance, for offering
  /// the user a choice rather than guessing one.
  List<CanonicalUnit> targetsFor(CanonicalUnit from, String? substanceId) => [
    for (final candidate in CanonicalUnit.values)
      if (candidate != from &&
          convert(
                amount: 1,
                from: from,
                to: candidate,
                substanceId: substanceId,
              ) !=
              null)
        candidate,
  ];

  /// Everything expressible for this substance is routed through grams, which
  /// keeps the table to one factor per unit rather than one per pair.
  double? _toGrams(double amount, CanonicalUnit from, _SubstanceFactors f) {
    if (from.domain == UnitDomain.mass) {
      return amount * from.perDomainBase!;
    }
    if (from.domain == UnitDomain.internationalUnit) {
      if (f.iuPerMicrogram != null) {
        return amount / f.iuPerMicrogram! * 1e-6;
      }
      if (f.iuPerMilligram != null) {
        return amount / f.iuPerMilligram! * 1e-3;
      }
      return null;
    }
    if (from == f.equivalentUnit && f.massPerEquivalent != null) {
      // The equivalent's own magnitude follows its symbol: µg RE is
      // micrograms, mg α-TE is milligrams.
      final scale = from == CanonicalUnit.microgramRetinolEquivalent
          ? 1e-6
          : 1e-3;
      return amount * f.massPerEquivalent! * scale;
    }
    return null;
  }

  double? _fromGrams(double grams, CanonicalUnit to, _SubstanceFactors f) {
    if (to.domain == UnitDomain.mass) {
      return grams / to.perDomainBase!;
    }
    if (to.domain == UnitDomain.internationalUnit) {
      if (f.iuPerMicrogram != null) return grams / 1e-6 * f.iuPerMicrogram!;
      if (f.iuPerMilligram != null) return grams / 1e-3 * f.iuPerMilligram!;
      return null;
    }
    if (to == f.equivalentUnit && f.massPerEquivalent != null) {
      final scale = to == CanonicalUnit.microgramRetinolEquivalent
          ? 1e-6
          : 1e-3;
      return grams / scale / f.massPerEquivalent!;
    }
    return null;
  }
}

class _SubstanceFactors {
  const _SubstanceFactors({
    this.iuPerMicrogram,
    this.iuPerMilligram,
    this.equivalentUnit,
    this.massPerEquivalent,
  });

  /// How many IU one microgram of the substance is worth.
  final double? iuPerMicrogram;

  /// Used instead of [iuPerMicrogram] where the label convention is milligrams.
  final double? iuPerMilligram;

  final CanonicalUnit? equivalentUnit;

  /// Mass per one activity equivalent, in the equivalent's own magnitude.
  final double? massPerEquivalent;
}
