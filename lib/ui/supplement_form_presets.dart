import '../app/app_localizations.dart';
import '../domain/units.dart';

/// The ways a supplement commonly comes, each with the units it is dosed in.
///
/// The editor used to ask for a free-text form *and* a free-text "stock unit"
/// side by side, with one chip row mixing forms ("softgel") and measures
/// ("g"). That produced records such as "1 g glycine per Powder". A preset
/// ties the two together: the form decides which dose units make sense, and
/// only forms with a real choice (powder: grams or scoops) ask a second
/// question. [other] keeps both as free text for anything unusual.
enum SupplementFormPreset {
  capsule(
    'Capsule',
    'Kapsel',
    [CanonicalUnit.capsule],
    {'capsule', 'capsules', 'kapsel', 'kapseln', 'caps', 'vegicap', 'vegicaps'},
  ),
  tablet(
    'Tablet',
    'Tablette',
    [CanonicalUnit.tablet],
    {'tablet', 'tablets', 'tablette', 'tabletten', 'tab', 'tabs'},
  ),
  softgel(
    'Softgel',
    'Softgel',
    [CanonicalUnit.capsule],
    {'softgel', 'softgels', 'weichkapsel', 'weichkapseln'},
  ),
  powder(
    'Powder',
    'Pulver',
    [CanonicalUnit.gram, CanonicalUnit.scoop],
    {'powder', 'pulver'},
  ),
  liquid(
    'Liquid',
    'Flüssigkeit',
    [CanonicalUnit.millilitre, CanonicalUnit.drop],
    {
      'liquid',
      'flüssigkeit',
      'fluessigkeit',
      'flüssig',
      'oil',
      'öl',
      'saft',
      'syrup',
      'sirup',
    },
  ),
  drops('Drops', 'Tropfen', [CanonicalUnit.drop], {'drop', 'drops', 'tropfen'}),
  sachet(
    'Sachet',
    'Beutel',
    [CanonicalUnit.sachet],
    {'sachet', 'sachets', 'beutel', 'stick', 'sticks'},
  ),
  spray('Spray', 'Spray', [CanonicalUnit.spray], {'spray', 'sprays'}),
  gummy(
    'Gummy',
    'Fruchtgummi',
    [CanonicalUnit.piece],
    {'gummy', 'gummies', 'fruchtgummi', 'fruchtgummis'},
  ),
  other('Other', 'Andere', [], {});

  const SupplementFormPreset(
    this.englishLabel,
    this.germanLabel,
    this.units,
    this._aliases,
  );

  final String englishLabel;
  final String germanLabel;

  /// Dose units this form is counted in, the usual one first. Empty for
  /// [other], where the unit is typed freely.
  final List<CanonicalUnit> units;

  final Set<String> _aliases;

  String label(AppLocalizations strings) =>
      strings.pick(englishLabel, germanLabel);

  /// Whether the dose unit needs a second question, because more than one
  /// unit fits this form.
  bool get offersUnitChoice => units.length > 1 || this == other;

  /// The preset a stored free-text form belongs to, or null when the text is
  /// empty or names something the presets do not cover.
  static SupplementFormPreset? match(String form) {
    final folded = form.trim().toLowerCase();
    if (folded.isEmpty) return null;
    for (final preset in values) {
      if (preset == other) continue;
      if (preset._aliases.contains(folded) ||
          preset.englishLabel.toLowerCase() == folded ||
          preset.germanLabel.toLowerCase() == folded) {
        return preset;
      }
    }
    return null;
  }

  /// Whether [stockUnit] is one of this preset's dose units, in any spelling.
  bool accepts(String stockUnit) {
    final unit = CanonicalUnit.tryParse(stockUnit);
    return unit != null && units.contains(unit);
  }
}

/// Free-text suggestions for [SupplementFormPreset.other], in symbol form.
const otherStockUnitSuggestions = <CanonicalUnit>[
  CanonicalUnit.piece,
  CanonicalUnit.capsule,
  CanonicalUnit.tablet,
  CanonicalUnit.gram,
  CanonicalUnit.scoop,
  CanonicalUnit.millilitre,
  CanonicalUnit.drop,
  CanonicalUnit.sachet,
  CanonicalUnit.spray,
];

/// How a dose unit reads to the person: localized for the count units the app
/// owns ("Kapsel", "Messlöffel"), the symbol for measures ("g", "mL"), and the
/// stored text unchanged for anything typed by hand.
String doseUnitName(AppLocalizations strings, String stockUnit) {
  final unit = CanonicalUnit.tryParse(stockUnit);
  if (unit == null) return stockUnit.trim();
  return switch (unit) {
    CanonicalUnit.capsule => strings.pick('capsule', 'Kapsel'),
    CanonicalUnit.tablet => strings.pick('tablet', 'Tablette'),
    CanonicalUnit.drop => strings.pick('drop', 'Tropfen'),
    CanonicalUnit.scoop => strings.pick('scoop', 'Messlöffel'),
    CanonicalUnit.sachet => strings.pick('sachet', 'Beutel'),
    CanonicalUnit.spray => strings.pick('spray', 'Sprühstoß'),
    CanonicalUnit.piece => strings.pick('piece', 'Stück'),
    _ => unit.symbol,
  };
}

/// Where the editor starts for a product: which preset is selected and which
/// dose unit, so opening and saving an existing product without touching the
/// form section never changes how its stock is counted.
class SupplementFormSelection {
  const SupplementFormSelection(this.preset, this.stockUnit);

  /// Null means nothing chosen yet (a new product).
  final SupplementFormPreset? preset;

  /// The stock unit text to keep. Empty means "not chosen".
  final String stockUnit;

  /// Derives the starting selection from a stored product.
  ///
  /// The stored stock unit wins over the preset's default: an older record
  /// counted in "Powder" keeps "Powder" until the person picks another unit,
  /// because intakes are deducted from stock only when their unit matches.
  /// The one exception is the generic placeholder `unit`, which carries no
  /// meaning, so a single-unit preset (capsule, tablet…) fills it in — those
  /// are all count units, and stock deduction treats every count unit alike.
  factory SupplementFormSelection.fromStored({
    required String form,
    required String stockUnit,
    required String genericStockUnit,
  }) {
    final trimmedForm = form.trim();
    final trimmedUnit = stockUnit.trim();
    final generic =
        trimmedUnit.isEmpty || trimmedUnit.toLowerCase() == genericStockUnit;
    if (trimmedForm.isEmpty && generic) {
      return const SupplementFormSelection(null, '');
    }
    final preset = SupplementFormPreset.match(trimmedForm);
    if (preset == null) {
      return SupplementFormSelection(
        SupplementFormPreset.other,
        generic ? '' : trimmedUnit,
      );
    }
    if (generic) {
      final countOnly =
          preset.units.length == 1 &&
          preset.units.single.domain == UnitDomain.count;
      return SupplementFormSelection(
        preset,
        countOnly ? preset.units.single.symbol : '',
      );
    }
    return SupplementFormSelection(preset, trimmedUnit);
  }
}
