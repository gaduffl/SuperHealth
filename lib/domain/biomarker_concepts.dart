/// Laboratory tests named independently of any one catalog.
///
/// Interaction rules have to say "TSH" without knowing how a given catalog
/// spells it. Catalog ids from the legacy import are short codes (`tsh`,
/// `crea`, `vitb12`), but a user-created marker has a UUID and whatever name
/// the lab report printed ("TSH basal", "Thyreotropin", "S-Ferritin (S)").
/// A concept therefore matches on the known ids *and* on a curated alias list,
/// compared after folding case, punctuation and parentheticals away.
library;

import 'entities.dart';
import 'localized_text.dart';
import 'name_matching.dart';

class BiomarkerConcept {
  const BiomarkerConcept({
    required this.id,
    required this.name,
    this.catalogIds = const {},
    this.aliases = const [],
  });

  final String id;
  final LocalizedText name;

  /// Ids used by the shipped catalog. Compared case-insensitively.
  final Set<String> catalogIds;

  /// Whole names, not fragments: "tsh basal" is an alias, "tsh" alone would
  /// also claim "TSH-Rezeptor-Antikörper", which is a different test.
  final List<String> aliases;

  bool matches(Biomarker biomarker) {
    if (catalogIds.contains(biomarker.id.toLowerCase())) return true;
    final folded = {for (final alias in aliases) foldForMatching(alias)};
    for (final candidate in [
      biomarker.id,
      biomarker.canonicalName,
      biomarker.displayName,
      ...biomarker.synonyms,
    ]) {
      if (folded.contains(foldForMatching(candidate))) return true;
      final bare = withoutParentheticals(candidate);
      if (bare != candidate && folded.contains(foldForMatching(bare))) {
        return true;
      }
    }
    return false;
  }
}

/// The tests the interaction rules refer to.
abstract final class BiomarkerConcepts {
  static const tsh = BiomarkerConcept(
    id: 'tsh',
    name: LocalizedText('TSH', 'TSH'),
    catalogIds: {'tsh'},
    aliases: [
      'tsh',
      'tsh basal',
      'basales tsh',
      'tsh 3 generation',
      'thyreotropin',
      'thyrotropin',
      'thyroid stimulating hormone',
      'thyreoidea stimulierendes hormon',
    ],
  );

  static const ft4 = BiomarkerConcept(
    id: 'ft4',
    name: LocalizedText('free T4', 'freies T4'),
    catalogIds: {'ft4'},
    aliases: [
      'ft4',
      'ft 4',
      'free t4',
      'freies t4',
      't4 frei',
      'free thyroxine',
      'freies thyroxin',
    ],
  );

  static const ft3 = BiomarkerConcept(
    id: 'ft3',
    name: LocalizedText('free T3', 'freies T3'),
    catalogIds: {'ft3'},
    aliases: [
      'ft3',
      'ft 3',
      'free t3',
      'freies t3',
      't3 frei',
      'free triiodothyronine',
      'freies trijodthyronin',
    ],
  );

  static const trak = BiomarkerConcept(
    id: 'trak',
    name: LocalizedText('TSH receptor antibodies', 'TSH-Rezeptor-Antikörper'),
    catalogIds: {'trak', 'trab'},
    aliases: [
      'trak',
      'trab',
      'tsh rezeptor antikörper',
      'tsh rezeptor ak',
      'tsh receptor antibodies',
      'tsh receptor antibody',
    ],
  );

  static const troponin = BiomarkerConcept(
    id: 'troponin',
    name: LocalizedText('Troponin', 'Troponin'),
    catalogIds: {'troponin', 'tnt', 'tni', 'hs_tnt', 'hs_tni'},
    aliases: [
      'troponin',
      'troponin t',
      'troponin i',
      'hs troponin t',
      'hs troponin i',
      'hs tnt',
      'hs tni',
      'tnt',
      'tni',
      'hochsensitives troponin t',
      'hochsensitives troponin i',
    ],
  );

  static const pth = BiomarkerConcept(
    id: 'pth',
    name: LocalizedText('Parathyroid hormone', 'Parathormon'),
    catalogIds: {'pth', 'ipth'},
    aliases: [
      'pth',
      'ipth',
      'intact pth',
      'parathormon',
      'intaktes parathormon',
      'parathyroid hormone',
    ],
  );

  static const hcg = BiomarkerConcept(
    id: 'hcg',
    name: LocalizedText('hCG', 'hCG'),
    catalogIds: {'hcg'},
    aliases: [
      'hcg',
      'beta hcg',
      'human chorionic gonadotropin',
      'humanes choriongonadotropin',
    ],
  );

  static const cortisol = BiomarkerConcept(
    id: 'cortisol',
    name: LocalizedText('Cortisol', 'Cortisol'),
    catalogIds: {'cort', 'cortisol'},
    aliases: ['cortisol', 'kortisol', 'cortisol serum'],
  );

  static const testosterone = BiomarkerConcept(
    id: 'testosterone',
    name: LocalizedText('Testosterone', 'Testosteron'),
    catalogIds: {'testo', 'testosterone', 'free_testo'},
    aliases: [
      'testosteron',
      'testosterone',
      'testosteron gesamt',
      'total testosterone',
      'freies testosteron',
      'free testosterone',
    ],
  );

  static const estradiol = BiomarkerConcept(
    id: 'estradiol',
    name: LocalizedText('Estradiol', 'Östradiol'),
    catalogIds: {'e2', 'estradiol'},
    aliases: [
      'estradiol',
      'östradiol',
      'oestradiol',
      'e2',
      '17 beta estradiol',
    ],
  );

  static const progesterone = BiomarkerConcept(
    id: 'progesterone',
    name: LocalizedText('Progesterone', 'Progesteron'),
    catalogIds: {'prog', 'progesterone'},
    aliases: ['progesteron', 'progesterone'],
  );

  static const dheaS = BiomarkerConcept(
    id: 'dhea_s',
    name: LocalizedText('DHEA-S', 'DHEA-S'),
    catalogIds: {'dhea_s', 'dheas'},
    aliases: [
      'dhea s',
      'dheas',
      'dhea sulfat',
      'dhea sulfate',
      'dehydroepiandrosteron sulfat',
      'dehydroepiandrosterone sulfate',
    ],
  );

  static const vitaminD = BiomarkerConcept(
    id: 'vitamin_d',
    name: LocalizedText('25-OH vitamin D', '25-OH-Vitamin D'),
    catalogIds: {'25_oh_d3', 'vitd', 'vitamin_d'},
    aliases: [
      '25 oh vitamin d',
      '25 oh vitamin d3',
      '25 oh d',
      '25 oh d3',
      '25 hydroxy vitamin d',
      '25 hydroxyvitamin d',
      'vitamin d',
      'vitamin d3',
      'vitamin d 25 oh',
      'calcidiol',
    ],
  );

  static const vitaminB12 = BiomarkerConcept(
    id: 'vitamin_b12',
    name: LocalizedText('Vitamin B12', 'Vitamin B12'),
    catalogIds: {'vitb12', 'b12'},
    aliases: ['vitamin b12', 'b12', 'vit b12', 'cobalamin', 'cobalamine'],
  );

  static const holoTc = BiomarkerConcept(
    id: 'holotc',
    name: LocalizedText('Holotranscobalamin', 'Holotranscobalamin'),
    catalogIds: {'holotc', 'holo_tc'},
    aliases: [
      'holotranscobalamin',
      'holo tc',
      'holotc',
      'aktives b12',
      'active b12',
      'aktives vitamin b12',
    ],
  );

  static const mma = BiomarkerConcept(
    id: 'mma',
    name: LocalizedText('Methylmalonic acid', 'Methylmalonsäure'),
    catalogIds: {'mma'},
    aliases: ['mma', 'methylmalonsäure', 'methylmalonic acid'],
  );

  static const folate = BiomarkerConcept(
    id: 'folate',
    name: LocalizedText('Folate', 'Folsäure'),
    catalogIds: {'fol', 'folate'},
    aliases: ['folsäure', 'folat', 'folate', 'folic acid', 'serum folat'],
  );

  static const ferritin = BiomarkerConcept(
    id: 'ferritin',
    name: LocalizedText('Ferritin', 'Ferritin'),
    catalogIds: {'ferritin'},
    aliases: ['ferritin', 'serum ferritin'],
  );

  static const psa = BiomarkerConcept(
    id: 'psa',
    name: LocalizedText('PSA', 'PSA'),
    catalogIds: {'psa', 'tpsa', 'fpsa'},
    aliases: [
      'psa',
      'psa gesamt',
      'gesamt psa',
      'total psa',
      'freies psa',
      'free psa',
      'prostata spezifisches antigen',
      'prostate specific antigen',
    ],
  );

  static const lh = BiomarkerConcept(
    id: 'lh',
    name: LocalizedText('LH', 'LH'),
    catalogIds: {'lh'},
    aliases: ['lh', 'luteinisierendes hormon', 'luteinizing hormone'],
  );

  static const fsh = BiomarkerConcept(
    id: 'fsh',
    name: LocalizedText('FSH', 'FSH'),
    catalogIds: {'fsh'},
    aliases: [
      'fsh',
      'follikelstimulierendes hormon',
      'follicle stimulating hormone',
    ],
  );

  static const prolactin = BiomarkerConcept(
    id: 'prolactin',
    name: LocalizedText('Prolactin', 'Prolaktin'),
    catalogIds: {'prl', 'prolactin'},
    aliases: ['prolaktin', 'prolactin'],
  );

  static const insulin = BiomarkerConcept(
    id: 'insulin',
    name: LocalizedText('Insulin', 'Insulin'),
    catalogIds: {'ins', 'insulin'},
    aliases: ['insulin', 'nüchterninsulin', 'fasting insulin'],
  );

  static const ntProBnp = BiomarkerConcept(
    id: 'nt_probnp',
    name: LocalizedText('NT-proBNP', 'NT-proBNP'),
    catalogIds: {'ntprobnp', 'nt_probnp', 'bnp'},
    aliases: ['nt probnp', 'ntprobnp', 'nt pro bnp', 'bnp'],
  );

  static const creatinine = BiomarkerConcept(
    id: 'creatinine',
    name: LocalizedText('Creatinine', 'Kreatinin'),
    catalogIds: {'crea', 'creatinine'},
    aliases: [
      'kreatinin',
      'creatinine',
      'creatinin',
      'kreatinin serum',
      'serum creatinine',
    ],
  );

  static const egfr = BiomarkerConcept(
    id: 'egfr',
    name: LocalizedText('eGFR', 'eGFR'),
    catalogIds: {'gfr', 'gfr_capa', 'egfr'},
    aliases: [
      'egfr',
      'gfr',
      'egfr ckd epi',
      'gfr ckd epi',
      'geschätzte gfr',
      'estimated gfr',
    ],
  );

  static const cystatinC = BiomarkerConcept(
    id: 'cystatin_c',
    name: LocalizedText('Cystatin C', 'Cystatin C'),
    catalogIds: {'cysc', 'cystatin_c'},
    aliases: ['cystatin c', 'cystatin'],
  );

  static const serumIron = BiomarkerConcept(
    id: 'serum_iron',
    name: LocalizedText('Serum iron', 'Serumeisen'),
    catalogIds: {'fe', 'serum_iron'},
    aliases: ['eisen', 'serum eisen', 'serumeisen', 'iron', 'serum iron'],
  );

  static const transferrinSaturation = BiomarkerConcept(
    id: 'transferrin_saturation',
    name: LocalizedText('Transferrin saturation', 'Transferrinsättigung'),
    catalogIds: {'ts', 'tsat', 'transferrin_saturation'},
    aliases: [
      'transferrinsättigung',
      'transferrin sättigung',
      'transferrin saturation',
      'tsat',
    ],
  );

  static const calcium = BiomarkerConcept(
    id: 'calcium',
    name: LocalizedText('Calcium', 'Calcium'),
    catalogIds: {'ca', 'calcium'},
    aliases: ['calcium', 'kalzium', 'calcium gesamt', 'total calcium'],
  );

  static const magnesium = BiomarkerConcept(
    id: 'magnesium',
    name: LocalizedText('Magnesium', 'Magnesium'),
    catalogIds: {'mg', 'magnesium_serum', 'magnesium'},
    aliases: ['magnesium', 'magnesium serum', 'serum magnesium'],
  );

  static const potassium = BiomarkerConcept(
    id: 'potassium',
    name: LocalizedText('Potassium', 'Kalium'),
    catalogIds: {'k', 'potassium'},
    aliases: ['kalium', 'potassium'],
  );

  static const sodium = BiomarkerConcept(
    id: 'sodium',
    name: LocalizedText('Sodium', 'Natrium'),
    catalogIds: {'na', 'sodium'},
    aliases: ['natrium', 'sodium'],
  );

  static const uricAcid = BiomarkerConcept(
    id: 'uric_acid',
    name: LocalizedText('Uric acid', 'Harnsäure'),
    catalogIds: {'uric_acid'},
    aliases: ['harnsäure', 'uric acid', 'urat'],
  );

  static const glucose = BiomarkerConcept(
    id: 'glucose',
    name: LocalizedText('Glucose', 'Glukose'),
    catalogIds: {'glu', 'glucose'},
    aliases: [
      'glucose',
      'glukose',
      'nüchternglucose',
      'nüchternglukose',
      'fasting glucose',
      'blutzucker',
    ],
  );

  static const hba1c = BiomarkerConcept(
    id: 'hba1c',
    name: LocalizedText('HbA1c', 'HbA1c'),
    catalogIds: {'hba1c'},
    aliases: [
      'hba1c',
      'hb a1c',
      'glykohämoglobin',
      'glycated hemoglobin',
      'glykiertes hämoglobin',
    ],
  );

  static const ldl = BiomarkerConcept(
    id: 'ldl',
    name: LocalizedText('LDL cholesterol', 'LDL-Cholesterin'),
    catalogIds: {'ldl', 'ldl_c', 'ldl_friedewald'},
    aliases: ['ldl', 'ldl c', 'ldl cholesterin', 'ldl cholesterol'],
  );

  static const hdl = BiomarkerConcept(
    id: 'hdl',
    name: LocalizedText('HDL cholesterol', 'HDL-Cholesterin'),
    catalogIds: {'hdl', 'hdl_c'},
    aliases: ['hdl', 'hdl c', 'hdl cholesterin', 'hdl cholesterol'],
  );

  static const triglycerides = BiomarkerConcept(
    id: 'triglycerides',
    name: LocalizedText('Triglycerides', 'Triglyceride'),
    catalogIds: {'tg', 'triglyceride', 'triglycerides'},
    aliases: ['triglyceride', 'triglyzeride', 'triglycerides', 'tg'],
  );

  static const ck = BiomarkerConcept(
    id: 'ck',
    name: LocalizedText('Creatine kinase (CK)', 'Creatinkinase (CK)'),
    catalogIds: {'ck', 'cpk', 'creatine_kinase'},
    aliases: ['ck', 'cpk', 'creatinkinase', 'kreatinkinase', 'creatine kinase'],
  );

  static const alt = BiomarkerConcept(
    id: 'alt',
    name: LocalizedText('ALT (GPT)', 'ALT (GPT)'),
    catalogIds: {'alt', 'gpt'},
    aliases: [
      'alt',
      'gpt',
      'alt gpt',
      'gpt alt',
      'alanin aminotransferase',
      'alanine aminotransferase',
    ],
  );

  static const ast = BiomarkerConcept(
    id: 'ast',
    name: LocalizedText('AST (GOT)', 'AST (GOT)'),
    catalogIds: {'ast', 'got'},
    aliases: [
      'ast',
      'got',
      'ast got',
      'got ast',
      'aspartat aminotransferase',
      'aspartate aminotransferase',
    ],
  );

  static const ggt = BiomarkerConcept(
    id: 'ggt',
    name: LocalizedText('GGT', 'Gamma-GT'),
    catalogIds: {'ggt'},
    aliases: [
      'ggt',
      'gamma gt',
      'gamma glutamyltransferase',
      'gamma glutamyl transferase',
    ],
  );

  static const ldh = BiomarkerConcept(
    id: 'ldh',
    name: LocalizedText('LDH', 'LDH'),
    catalogIds: {'ldh'},
    aliases: ['ldh', 'laktatdehydrogenase', 'lactate dehydrogenase'],
  );

  static const bilirubin = BiomarkerConcept(
    id: 'bilirubin',
    name: LocalizedText('Bilirubin', 'Bilirubin'),
    catalogIds: {'bilirubin', 'bili'},
    aliases: [
      'bilirubin',
      'bilirubin gesamt',
      'gesamtbilirubin',
      'total bilirubin',
    ],
  );

  static const copper = BiomarkerConcept(
    id: 'copper',
    name: LocalizedText('Copper', 'Kupfer'),
    catalogIds: {'cu', 'copper'},
    aliases: ['kupfer', 'copper', 'serum kupfer'],
  );

  static const selenium = BiomarkerConcept(
    id: 'selenium',
    name: LocalizedText('Selenium', 'Selen'),
    catalogIds: {'se', 'selenium'},
    aliases: ['selen', 'selenium'],
  );

  static const vitaminB6 = BiomarkerConcept(
    id: 'vitamin_b6',
    name: LocalizedText('Vitamin B6', 'Vitamin B6'),
    catalogIds: {'vitb6', 'b6', 'plp'},
    aliases: [
      'vitamin b6',
      'b6',
      'pyridoxal 5 phosphat',
      'pyridoxal 5 phosphate',
      'plp',
    ],
  );

  static const leukocytes = BiomarkerConcept(
    id: 'leukocytes',
    name: LocalizedText('White blood cells', 'Leukozyten'),
    catalogIds: {'wbc'},
    aliases: ['leukozyten', 'leukocytes', 'white blood cells', 'wbc'],
  );

  static const neutrophils = BiomarkerConcept(
    id: 'neutrophils',
    name: LocalizedText('Neutrophils', 'Neutrophile'),
    catalogIds: {'neut'},
    aliases: [
      'neutrophile',
      'neutrophils',
      'neutrophile granulozyten',
      'neutrophile absolut',
    ],
  );

  static const hemoglobin = BiomarkerConcept(
    id: 'hemoglobin',
    name: LocalizedText('Haemoglobin', 'Hämoglobin'),
    catalogIds: {'hb', 'hemoglobin'},
    aliases: ['hämoglobin', 'hemoglobin', 'haemoglobin', 'hb'],
  );

  static const hematocrit = BiomarkerConcept(
    id: 'hematocrit',
    name: LocalizedText('Haematocrit', 'Hämatokrit'),
    catalogIds: {'hct', 'hkt', 'hematocrit'},
    aliases: ['hämatokrit', 'hematocrit', 'haematocrit', 'hkt', 'hct'],
  );

  static const mcv = BiomarkerConcept(
    id: 'mcv',
    name: LocalizedText('MCV', 'MCV'),
    catalogIds: {'mcv'},
    aliases: [
      'mcv',
      'mittleres erythrozytenvolumen',
      'mean corpuscular volume',
    ],
  );

  static const crp = BiomarkerConcept(
    id: 'crp',
    name: LocalizedText('CRP', 'CRP'),
    catalogIds: {'crp', 'hscrp'},
    aliases: [
      'crp',
      'hs crp',
      'crp hs',
      'hscrp',
      'c reaktives protein',
      'c reactive protein',
      'hochsensitives crp',
    ],
  );

  static const inr = BiomarkerConcept(
    id: 'inr',
    name: LocalizedText('INR / Quick', 'INR / Quick'),
    catalogIds: {'inr', 'quick'},
    aliases: [
      'inr',
      'quick',
      'quick wert',
      'thromboplastinzeit',
      'prothrombin time',
      'pt inr',
    ],
  );

  static const shbg = BiomarkerConcept(
    id: 'shbg',
    name: LocalizedText('SHBG', 'SHBG'),
    catalogIds: {'shbg'},
    aliases: [
      'shbg',
      'sexualhormon bindendes globulin',
      'sex hormone binding globulin',
    ],
  );

  static const myoglobin = BiomarkerConcept(
    id: 'myoglobin',
    name: LocalizedText('Myoglobin', 'Myoglobin'),
    catalogIds: {'myoglobin'},
    aliases: ['myoglobin'],
  );

  static const homocysteine = BiomarkerConcept(
    id: 'homocysteine',
    name: LocalizedText('Homocysteine', 'Homocystein'),
    catalogIds: {'hcy'},
    aliases: ['homocystein', 'homocysteine'],
  );
}
