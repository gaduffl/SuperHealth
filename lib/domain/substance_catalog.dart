/// Stable identity for the substances inside supplements.
///
/// An ingredient used to be identified by its free-text `name`, which meant
/// "Vitamin C" and "Vitamin c" were two substances, "B12" and "Vitamin B12"
/// were two more, and every chart and correlation split accordingly. This gives
/// the common ones a canonical id with a display name and synonyms, mirroring
/// `Biomarker.canonicalName`/`synonyms`, which has worked well on that side.
///
/// The catalog is deliberately not exhaustive. An unrecognised ingredient keeps
/// its typed name and is identified by that name folded — no worse than before
/// — so a supplement the catalog has never heard of still works.
library;

class Substance {
  const Substance({
    required this.id,
    required this.displayName,
    this.synonyms = const [],
  });

  /// Stable key, also used by `SubstanceConversions`.
  final String id;
  final String displayName;
  final List<String> synonyms;
}

class SubstanceCatalog {
  const SubstanceCatalog();

  static const substances = <Substance>[
    Substance(
      id: 'vitamin-d',
      displayName: 'Vitamin D',
      synonyms: [
        'vitamin d3',
        'vitamin d 3',
        'cholecalciferol',
        'colecalciferol',
        'cholecalciferol d3',
        'vitamin-d3',
        'vit d',
        'vit d3',
      ],
    ),
    Substance(
      id: 'vitamin-a',
      displayName: 'Vitamin A',
      synonyms: ['retinol', 'retinyl palmitate', 'vit a'],
    ),
    Substance(
      id: 'vitamin-e',
      displayName: 'Vitamin E',
      synonyms: ['tocopherol', 'alpha-tocopherol', 'a-tocopherol', 'vit e'],
    ),
    Substance(
      id: 'vitamin-b12',
      displayName: 'Vitamin B12',
      synonyms: [
        'b12',
        'b 12',
        'cobalamin',
        'methylcobalamin',
        'cyanocobalamin',
        'hydroxocobalamin',
        'vit b12',
      ],
    ),
    Substance(
      id: 'vitamin-c',
      displayName: 'Vitamin C',
      synonyms: ['ascorbic acid', 'ascorbinsäure', 'l-ascorbic acid', 'vit c'],
    ),
    Substance(
      id: 'vitamin-k2',
      displayName: 'Vitamin K2',
      synonyms: [
        'k2',
        'menaquinone',
        'menachinon',
        'mk7',
        'mk-7',
        'vitamin k2 mk7',
        'vitamin k2 mk-7',
      ],
    ),
    Substance(
      id: 'vitamin-b6',
      displayName: 'Vitamin B6',
      synonyms: ['b6', 'pyridoxine', 'pyridoxin'],
    ),
    Substance(
      id: 'folate',
      displayName: 'Folat',
      synonyms: ['folsäure', 'folic acid', 'folate', 'methylfolate', '5-mthf'],
    ),
    Substance(
      id: 'magnesium',
      displayName: 'Magnesium',
      synonyms: ['magnesiumcitrat', 'magnesium citrate', 'magnesium glycinate'],
    ),
    Substance(
      id: 'calcium',
      displayName: 'Calcium',
      synonyms: ['kalzium', 'calciumcarbonat'],
    ),
    Substance(
      id: 'zinc',
      displayName: 'Zink',
      synonyms: ['zinc', 'zinkgluconat', 'zinc picolinate'],
    ),
    // Iron appears in a real library as the element, a salt, and an ion. They
    // are not interchangeable amounts, so only the element and the ion share an
    // id; a named salt keeps its own identity because its mass includes the
    // counter-ion.
    Substance(
      id: 'iron',
      displayName: 'Eisen',
      synonyms: ['iron', 'eisen(ii)-ion', 'eisen ii ion', 'ferrous iron'],
    ),
    Substance(
      id: 'selenium',
      displayName: 'Selen',
      synonyms: ['selenium', 'natriumselenit'],
    ),
    Substance(id: 'iodine', displayName: 'Jod', synonyms: ['iodine', 'iod']),
    Substance(
      id: 'potassium-iodide',
      displayName: 'Kaliumiodid',
      synonyms: ['potassium iodide', 'kaliumjodid'],
    ),
    Substance(
      id: 'levothyroxine',
      displayName: 'Levothyroxin-Natrium',
      synonyms: [
        'levothyroxin natrium',
        'levothyroxine sodium',
        'levothyroxin',
        'l-thyroxin',
      ],
    ),
    Substance(
      id: 'creatine',
      displayName: 'Creatine',
      synonyms: ['kreatin', 'creatine monohydrate', 'kreatin monohydrat'],
    ),
    Substance(
      id: 'omega-3-dha',
      displayName: 'DHA',
      synonyms: ['docosahexaenoic acid', 'docosahexaensäure'],
    ),
    Substance(
      id: 'omega-3-epa',
      displayName: 'EPA',
      synonyms: ['eicosapentaenoic acid', 'eicosapentaensäure'],
    ),
    Substance(
      id: 'coenzyme-q10',
      displayName: 'Coenzym Q10',
      synonyms: ['coq10', 'co-q10', 'ubiquinone', 'ubiquinol', 'coenzyme q10'],
    ),
    // The entries below exist because an interaction rule has to recognise
    // them (see `interaction_rules.dart`); they merge spellings exactly like
    // the ones above. Compounds whose mass is not the substance's own — salts,
    // extracts — stay separate, as iron's salts do.
    Substance(
      id: 'biotin',
      displayName: 'Biotin',
      synonyms: ['d-biotin', 'vitamin b7', 'vit b7', 'vitamin h', 'biotine'],
    ),
    Substance(
      id: 'vitamin-k1',
      displayName: 'Vitamin K1',
      synonyms: [
        'k1',
        'vit k1',
        'phylloquinone',
        'phyllochinon',
        'phytomenadione',
        'phytomenadion',
      ],
    ),
    Substance(
      id: 'st-johns-wort',
      displayName: 'Johanniskraut',
      synonyms: [
        "st. john's wort",
        "st john's wort",
        'st johns wort',
        'hypericum',
        'hypericum perforatum',
        'johanniskrautextrakt',
        'johanniskraut-extrakt',
      ],
    ),
    Substance(
      id: 'ashwagandha',
      displayName: 'Ashwagandha',
      synonyms: [
        'withania somnifera',
        'schlafbeere',
        'ashwagandha extract',
        'ashwagandha-extrakt',
      ],
    ),
    Substance(
      id: 'red-yeast-rice',
      displayName: 'Rotschimmelreis',
      synonyms: [
        'red yeast rice',
        'monascus purpureus',
        'rotschimmelreis-extrakt',
      ],
    ),
    Substance(
      id: 'monacolin-k',
      displayName: 'Monacolin K',
      synonyms: ['monacolin', 'monacolins', 'monacoline', 'monakolin k'],
    ),
    // "Niacin" on an EU label is niacin equivalents and usually nicotinamide,
    // which has none of nicotinic acid's pharmacological effects — so the two
    // forms are separate identities and the generic name is a third.
    Substance(
      id: 'niacin',
      displayName: 'Niacin',
      synonyms: ['vitamin b3', 'vit b3'],
    ),
    Substance(
      id: 'nicotinic-acid',
      displayName: 'Nicotinsäure',
      synonyms: ['nicotinic acid', 'nikotinsäure'],
    ),
    Substance(
      id: 'nicotinamide',
      displayName: 'Nicotinamid',
      synonyms: ['nicotinamide', 'niacinamide', 'niacinamid', 'nikotinamid'],
    ),
    Substance(
      id: 'berberine',
      displayName: 'Berberin',
      synonyms: ['berberine'],
    ),
    Substance(
      id: 'dhea',
      displayName: 'DHEA',
      synonyms: [
        'dehydroepiandrosterone',
        'dehydroepiandrosteron',
        'prasterone',
        'prasteron',
      ],
    ),
    Substance(
      id: 'egcg',
      displayName: 'EGCG',
      synonyms: [
        'epigallocatechin gallate',
        'epigallocatechin-3-gallate',
        'epigallocatechingallat',
      ],
    ),
    Substance(
      id: 'green-tea-extract',
      displayName: 'Grüntee-Extrakt',
      synonyms: [
        'green tea extract',
        'grüntee extrakt',
        'grünteeextrakt',
        'grüner tee extrakt',
      ],
    ),
    Substance(
      id: 'curcumin',
      displayName: 'Curcumin',
      synonyms: ['kurkumin', 'curcuminoids', 'curcuminoide'],
    ),
    Substance(
      id: 'turmeric',
      displayName: 'Kurkuma',
      synonyms: ['turmeric', 'curcuma longa', 'turmeric extract'],
    ),
    Substance(
      id: 'ginkgo',
      displayName: 'Ginkgo',
      synonyms: [
        'ginkgo biloba',
        'ginkgo-biloba-extrakt',
        'ginkgo biloba extract',
      ],
    ),
    Substance(
      id: 'omega-3',
      displayName: 'Omega-3',
      synonyms: [
        'omega-3-fettsäuren',
        'omega-3 fatty acids',
        'fish oil',
        'fischöl',
        'krill oil',
        'krillöl',
      ],
    ),
    Substance(
      id: 'potassium',
      displayName: 'Kalium',
      synonyms: ['potassium', 'kalium-ion', 'potassium ion'],
    ),
    Substance(
      id: 'kelp',
      displayName: 'Meeresalgen (Kelp)',
      synonyms: [
        'kelp',
        'seetang',
        'meeresalgen',
        'braunalgen',
        'ascophyllum nodosum',
        'fucus vesiculosus',
        'blasentang',
      ],
    ),
    Substance(id: 'copper', displayName: 'Kupfer', synonyms: ['copper']),
  ];

  static final Map<String, String> _lookup = {
    for (final substance in substances) ...{
      _fold(substance.id): substance.id,
      _fold(substance.displayName): substance.id,
      for (final synonym in substance.synonyms) _fold(synonym): substance.id,
    },
  };

  static final Map<String, Substance> _byId = {
    for (final substance in substances) substance.id: substance,
  };

  /// Folds away the differences that are presentation, not identity: case,
  /// surrounding and repeated whitespace, hyphens, and the micro sign.
  static String _fold(String raw) => raw
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[‐‑‒–—−]'), '-')
      .replaceAll(RegExp(r'[\s\-_.]+'), ' ')
      .trim();

  /// A trailing parenthetical usually names the form rather than a different
  /// substance — "Coenzym Q10 (Ubiquinol)" is Coenzym Q10. Stripping it is a
  /// fallback, never the first attempt, so a parenthetical that *is* part of
  /// the identity ("Eisen(II)-Ion") still matches its own entry first.
  static final _trailingParenthetical = RegExp(r'\s*\([^()]*\)\s*$');

  /// The catalog id for [name], or null when the substance is not known.
  String? idFor(String? name) {
    if (name == null) return null;
    final direct = _lookup[_fold(name)];
    if (direct != null) return direct;
    final stripped = name.replaceAll(_trailingParenthetical, '');
    if (stripped.trim().isEmpty || stripped == name) return null;
    return _lookup[_fold(stripped)];
  }

  Substance? byId(String? id) => id == null ? null : _byId[id];

  /// The name to show for [name]: the catalog's spelling when recognised, the
  /// typed name otherwise.
  String displayNameFor(String name) =>
      byId(idFor(name))?.displayName ?? name.trim();

  /// A stable key for grouping an ingredient, whether or not the catalog knows
  /// it. Two spellings of a known substance share a key; an unknown substance
  /// falls back to its own folded name, which is no worse than the old
  /// behaviour.
  String groupingKeyFor(String name) => idFor(name) ?? 'name:${_fold(name)}';
}
