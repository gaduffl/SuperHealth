import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ui/biomarker_category_localization.dart';

void main() {
  const expectedEnglish = <String, String>{
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
  const expectedGerman = <String, String>{
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

  test('uses every English category name from the original dashboard', () {
    for (final entry in expectedEnglish.entries) {
      expect(biomarkerCategoryLabel(entry.key, 'en'), entry.value);
    }
  });

  test('uses every German category name from the original dashboard', () {
    for (final entry in expectedGerman.entries) {
      expect(biomarkerCategoryLabel(entry.key, 'de-DE'), entry.value);
    }
  });

  test('keeps custom categories and localizes an empty category as other', () {
    expect(biomarkerCategoryLabel('Custom panel', 'en'), 'Custom panel');
    expect(biomarkerCategoryLabel('', 'de'), 'Sonstige');
  });
}
