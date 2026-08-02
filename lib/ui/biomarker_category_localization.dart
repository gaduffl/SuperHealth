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
