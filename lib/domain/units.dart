/// The unit vocabulary for supplements, ingredients, and health events.
///
/// Biomarker units deliberately do **not** use this enum. Lab reports carry an
/// open set of notations — 37 distinct spellings appeared in one real export —
/// and rejecting an unrecognised one would mean refusing to import a genuine
/// report. Those go through `UnitConversionService.normalizeUnit` instead,
/// which canonicalises rather than rejects. This closed enum covers the side of
/// the app where the app itself owns the vocabulary and a typo is a bug, not a
/// fact about the world.
library;

/// The kind of quantity a unit measures.
///
/// Values are only ever compared, summed, or converted **within** one domain.
/// Crossing domains needs substance knowledge the app does not have in general:
/// grams of powder say nothing about international units of vitamin D.
enum UnitDomain {
  mass,
  volume,

  /// Discrete things: capsules, drops, sachets. Countable but not measurable.
  count,

  /// International units. Deliberately its own domain — the mass equivalent of
  /// one IU differs per substance, so a generic IU↔µg factor cannot exist.
  internationalUnit,

  /// Activity equivalents such as retinol equivalents (vitamin A) and
  /// α-tocopherol equivalents (vitamin E). Mass-like in appearance, but the
  /// conversion to plain mass is substance-specific.
  equivalent,
}

/// Every unit a supplement, ingredient, or health event may be recorded in.
enum CanonicalUnit {
  microgram('µg', UnitDomain.mass, 1e-6),
  milligram('mg', UnitDomain.mass, 1e-3),
  gram('g', UnitDomain.mass, 1),

  millilitre('mL', UnitDomain.volume, 1e-3),
  litre('L', UnitDomain.volume, 1),

  piece('unit', UnitDomain.count, 1),
  capsule('capsule', UnitDomain.count, 1),
  tablet('tablet', UnitDomain.count, 1),
  drop('drop', UnitDomain.count, 1),
  scoop('scoop', UnitDomain.count, 1),
  sachet('sachet', UnitDomain.count, 1),
  spray('spray', UnitDomain.count, 1),

  internationalUnit('IU', UnitDomain.internationalUnit, 1),

  /// Retinol equivalents, vitamin A.
  microgramRetinolEquivalent('µg RE', UnitDomain.equivalent, null),

  /// α-tocopherol equivalents, vitamin E.
  milligramAlphaTocopherolEquivalent('mg α-TE', UnitDomain.equivalent, null);

  const CanonicalUnit(this.symbol, this.domain, this.perDomainBase);

  /// How the unit is written. This is the only spelling ever stored.
  final String symbol;

  final UnitDomain domain;

  /// Multiplier onto the domain's base unit — gram for mass, litre for volume,
  /// one item for count. Null where no linear factor exists, which is what
  /// makes the equivalents un-summable without knowing the substance.
  final double? perDomainBase;

  /// Whether two amounts in these units can be added without further knowledge.
  bool commensurableWith(CanonicalUnit other) =>
      domain == other.domain &&
      perDomainBase != null &&
      other.perDomainBase != null;

  static final Map<String, CanonicalUnit> _bySymbol = {
    for (final unit in CanonicalUnit.values) unit.symbol.toLowerCase(): unit,
  };

  /// Spellings seen in real data or plausibly typed, mapped onto the canonical
  /// member. Keys are compared lower-cased with the micro sign folded, so only
  /// one casing of each needs listing.
  static const Map<String, CanonicalUnit> _aliases = {
    'ug': CanonicalUnit.microgram,
    'mcg': CanonicalUnit.microgram,
    'microgram': CanonicalUnit.microgram,
    'micrograms': CanonicalUnit.microgram,
    'mikrogramm': CanonicalUnit.microgram,
    'milligram': CanonicalUnit.milligram,
    'milligramm': CanonicalUnit.milligram,
    'mgs': CanonicalUnit.milligram,
    'gram': CanonicalUnit.gram,
    'gramm': CanonicalUnit.gram,
    'grams': CanonicalUnit.gram,
    'ml': CanonicalUnit.millilitre,
    'milliliter': CanonicalUnit.millilitre,
    'millilitre': CanonicalUnit.millilitre,
    'l': CanonicalUnit.litre,
    'liter': CanonicalUnit.litre,
    'litre': CanonicalUnit.litre,
    // "unit" is the placeholder the app itself wrote for years, so it has to
    // keep resolving even though it says nothing about what was taken.
    'unit': CanonicalUnit.piece,
    'units': CanonicalUnit.piece,
    'piece': CanonicalUnit.piece,
    'pieces': CanonicalUnit.piece,
    'stück': CanonicalUnit.piece,
    'stk': CanonicalUnit.piece,
    'capsule': CanonicalUnit.capsule,
    'capsules': CanonicalUnit.capsule,
    'kapsel': CanonicalUnit.capsule,
    'kapseln': CanonicalUnit.capsule,
    'caps': CanonicalUnit.capsule,
    'tablet': CanonicalUnit.tablet,
    'tablets': CanonicalUnit.tablet,
    'tablette': CanonicalUnit.tablet,
    'tabletten': CanonicalUnit.tablet,
    'tab': CanonicalUnit.tablet,
    'drop': CanonicalUnit.drop,
    'drops': CanonicalUnit.drop,
    'tropfen': CanonicalUnit.drop,
    'scoop': CanonicalUnit.scoop,
    'scoops': CanonicalUnit.scoop,
    'messlöffel': CanonicalUnit.scoop,
    'sachet': CanonicalUnit.sachet,
    'sachets': CanonicalUnit.sachet,
    'beutel': CanonicalUnit.sachet,
    'spray': CanonicalUnit.spray,
    'sprays': CanonicalUnit.spray,
    'hub': CanonicalUnit.spray,
    // "IE" is Internationale Einheiten, the German spelling of IU, and appears
    // throughout a German-entered library.
    'iu': CanonicalUnit.internationalUnit,
    'ie': CanonicalUnit.internationalUnit,
    'i.e.': CanonicalUnit.internationalUnit,
    'i.u.': CanonicalUnit.internationalUnit,
    'ug re': CanonicalUnit.microgramRetinolEquivalent,
    'mcg re': CanonicalUnit.microgramRetinolEquivalent,
    'ug-re': CanonicalUnit.microgramRetinolEquivalent,
    'mg a-te': CanonicalUnit.milligramAlphaTocopherolEquivalent,
    'mg at': CanonicalUnit.milligramAlphaTocopherolEquivalent,
    'mg alpha-te': CanonicalUnit.milligramAlphaTocopherolEquivalent,
  };

  /// Folds the spellings that differ only by presentation: surrounding space,
  /// casing, the Unicode micro signs, and the Greek alphas.
  ///
  /// The micro signs are replaced *before* lower-casing, and deliberately
  /// include Greek capital Mu — it is visually identical to a Latin M, so
  /// folding case first would turn "ΜG" into "mg" and inflate a dose by a
  /// thousand. Latin "MG" still means milligrams and is untouched here.
  static String _fold(String raw) => raw
      .trim()
      .replaceAll(RegExp(r'[µμΜ]'), 'u')
      .replaceAll(RegExp(r'[αa]lpha'), 'alpha')
      .replaceAll('α', 'a')
      .replaceAll(RegExp(r'\s+'), ' ')
      .toLowerCase();

  /// The canonical unit [raw] denotes, or null when it is not in the
  /// vocabulary.
  ///
  /// Returning null rather than a guess is the point: an unrecognised
  /// supplement unit is a data-entry mistake worth surfacing, not something to
  /// silently coerce into the nearest match.
  static CanonicalUnit? tryParse(String? raw) {
    if (raw == null) return null;
    final folded = _fold(raw);
    if (folded.isEmpty) return null;
    return _bySymbol[folded] ?? _aliases[folded];
  }

  /// The canonical spelling of [raw], or [raw] trimmed when unrecognised.
  static String normalize(String raw) => tryParse(raw)?.symbol ?? raw.trim();

  /// Whether [raw] is already a spelling the app is willing to store.
  static bool isKnown(String? raw) => tryParse(raw) != null;
}

/// Converts within one domain, e.g. 1000 µg to 1 mg.
///
/// Returns null across domains and for the equivalents, which need the
/// substance-scoped table in `SubstanceConversions` instead.
double? convertWithinDomain(
  double amount,
  CanonicalUnit from,
  CanonicalUnit to,
) {
  if (!from.commensurableWith(to)) return null;
  if (from == to) return amount;
  return amount * from.perDomainBase! / to.perDomainBase!;
}
