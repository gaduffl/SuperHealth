/// Dashboard category labels carried over from the original Biomarkers app.
///
/// Category IDs are stored in data and stay language-neutral. Unknown IDs are
/// deliberately shown as entered instead of being hidden behind "Other".
String biomarkerCategoryLabel(String category, String languageCode) {
  final id = category.trim().toLowerCase();
  final german = languageCode.toLowerCase().startsWith('de');
  final labels = german ? _germanCategoryLabels : _englishCategoryLabels;
  return labels[id] ?? (category.trim().isEmpty ? labels['other']! : category);
}

const _englishCategoryLabels = <String, String>{
  'autoimmune': 'Autoimmune Markers',
  'bone': 'Bone Health',
  'bone_mineral': 'Bone & Mineral Balance',
  'cardiac': 'Cardiac Markers',
  'cbc': 'Complete Blood Count',
  'coagulation': 'Coagulation',
  'electrolytes': 'Electrolytes',
  'gi': 'Gastrointestinal',
  'hormones': 'Hormones',
  'immune': 'Immune Function',
  'inflammation': 'Inflammation Markers',
  'iron': 'Iron Studies',
  'lipids': 'Lipid Panel',
  'liver': 'Liver Function',
  'metabolic': 'Metabolic Health',
  'minerals': 'Essential Minerals',
  'other': 'Other',
  'pancreatic': 'Pancreatic Function',
  'proteins': 'Protein Markers',
  'renal': 'Kidney Function',
  'thyroid': 'Thyroid Function',
  'vitamins': 'Vitamins & Minerals',
};

const _germanCategoryLabels = <String, String>{
  'autoimmune': 'Autoimmun-Marker',
  'bone': 'Knochengesundheit',
  'bone_mineral': 'Knochen & Mineralien',
  'cardiac': 'Herz-Kreislauf',
  'cbc': 'Großes Blutbild',
  'coagulation': 'Gerinnung',
  'electrolytes': 'Elektrolyte',
  'gi': 'Magen-Darm',
  'hormones': 'Hormone',
  'immune': 'Immunsystem',
  'inflammation': 'Entzündungsmarker',
  'iron': 'Eisenstatus',
  'lipids': 'Lipidprofil',
  'liver': 'Leberwerte',
  'metabolic': 'Stoffwechsel',
  'minerals': 'Mineralstoffe',
  'other': 'Sonstige',
  'pancreatic': 'Pankreas',
  'proteins': 'Proteine',
  'renal': 'Nierenfunktion',
  'thyroid': 'Schilddrüsenfunktion',
  'vitamins': 'Vitamine & Mineralstoffe',
};

/// The built-in category IDs, in a stable order.
List<String> get knownBiomarkerCategoryIds =>
    _englishCategoryLabels.keys.toList(growable: false);

/// Filter value for biomarkers that have no category at all.
///
/// It cannot collide with a real category: stored categories are trimmed, and
/// this one is not a word anyone types.
const biomarkerCategoryNoneFilter = '\u0000none';

/// Filter value that keeps every biomarker.
const biomarkerCategoryAllFilter = '\u0000all';

/// Turns what the owner picked or typed into the value stored on a biomarker.
///
/// A built-in category typed by its label, in either language and in any
/// case, is stored as its ID — otherwise typing "Leberwerte" would start a
/// second liver category beside `liver` that no filter would join. Anything
/// else is kept as typed, trimmed, so a custom category stays the owner's.
String normalizeBiomarkerCategory(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return '';
  final lower = trimmed.toLowerCase();
  if (_englishCategoryLabels.containsKey(lower)) return lower;
  for (final labels in [_englishCategoryLabels, _germanCategoryLabels]) {
    for (final entry in labels.entries) {
      if (entry.value.toLowerCase() == lower) return entry.key;
    }
  }
  return trimmed;
}

/// Whether [category] is shown under the catalog's category [filter].
///
/// Categories are compared after [normalizeBiomarkerCategory], so a stored
/// `Liver` or ` liver ` lands under the same entry as `liver`.
bool biomarkerCategoryMatchesFilter(String category, String filter) {
  if (filter == biomarkerCategoryAllFilter) return true;
  final normalized = normalizeBiomarkerCategory(category);
  if (filter == biomarkerCategoryNoneFilter) return normalized.isEmpty;
  return normalized == filter;
}

/// The distinct categories in use, normalized, without the empty one.
Set<String> biomarkerCategoriesInUse(Iterable<String> categories) => {
  for (final category in categories)
    if (normalizeBiomarkerCategory(category).isNotEmpty)
      normalizeBiomarkerCategory(category),
};

/// The label for a biomarker's category in a list row, or null when it has
/// none — an empty category is left out of a row rather than called "Other",
/// which would claim a choice nobody made.
String? biomarkerCategoryRowLabel(String category, String languageCode) {
  final normalized = normalizeBiomarkerCategory(category);
  if (normalized.isEmpty) return null;
  return biomarkerCategoryLabel(normalized, languageCode);
}
