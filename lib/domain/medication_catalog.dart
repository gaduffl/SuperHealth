/// Medication classes the interaction rules refer to.
///
/// Medications are free text in `named_health_records` ("L-Thyroxin Henning
/// 75", "Ramipril/HCT 5/25 mg"), so a class matches when one of its aliases
/// occurs as whole words anywhere in the name. That is deliberately generous:
/// for an interaction check a false "this looks like a statin" costs one line
/// of text, a missed statin costs the check.
///
/// Some medicines are also logged as supplements — levothyroxine is in the
/// substance catalog because real libraries track it with doses and times.
/// [MedicationClass.substanceIds] lets such a ledger entry count as the
/// medication, so an interaction does not depend on where it was recorded.
library;

import 'localized_text.dart';
import 'name_matching.dart';

class MedicationClass {
  const MedicationClass({
    required this.id,
    required this.name,
    required this.aliases,
    this.substanceIds = const {},
  });

  final String id;
  final LocalizedText name;
  final List<String> aliases;
  final Set<String> substanceIds;

  bool matchesName(String medicationName) =>
      aliases.any((alias) => containsPhrase(medicationName, alias));
}

class MedicationCatalog {
  const MedicationCatalog();

  static const thyroidHormone = MedicationClass(
    id: 'thyroid-hormone',
    name: LocalizedText('Thyroid hormone', 'Schilddrüsenhormon'),
    aliases: [
      'levothyroxin',
      'levothyroxine',
      'l thyroxin',
      'l thyrox',
      'thyroxin',
      'euthyrox',
      'eltroxin',
      'berlthyrox',
      'synthroid',
      'tirosint',
      'thyronajod',
      'jodthyrox',
      'novothyral',
      'prothyrid',
      'liothyronin',
      'liothyronine',
      'thybon',
      'cytomel',
    ],
    substanceIds: {'levothyroxine'},
  );

  static const vitaminKAntagonist = MedicationClass(
    id: 'vitamin-k-antagonist',
    name: LocalizedText('Vitamin K antagonist', 'Vitamin-K-Antagonist'),
    aliases: [
      'phenprocoumon',
      'marcumar',
      'falithrom',
      'phenpro',
      'warfarin',
      'coumadin',
      'acenocoumarol',
      'sintrom',
    ],
  );

  static const directOralAnticoagulant = MedicationClass(
    id: 'doac',
    name: LocalizedText(
      'Direct oral anticoagulant',
      'Direktes orales Antikoagulans',
    ),
    aliases: [
      'apixaban',
      'eliquis',
      'rivaroxaban',
      'xarelto',
      'edoxaban',
      'lixiana',
      'dabigatran',
      'pradaxa',
    ],
  );

  static const antiplatelet = MedicationClass(
    id: 'antiplatelet',
    name: LocalizedText('Antiplatelet drug', 'Thrombozytenhemmer'),
    aliases: [
      'acetylsalicylsäure',
      'acetylsalicylic acid',
      'ass',
      'aspirin',
      'clopidogrel',
      'plavix',
      'prasugrel',
      'efient',
      'ticagrelor',
      'brilique',
    ],
  );

  static const metformin = MedicationClass(
    id: 'metformin',
    name: LocalizedText('Metformin', 'Metformin'),
    aliases: [
      'metformin',
      'glucophage',
      'siofor',
      'janumet',
      'velmetia',
      'eucreas',
      'synjardy',
      'xigduo',
    ],
  );

  static const otherAntidiabetic = MedicationClass(
    id: 'antidiabetic',
    name: LocalizedText('Glucose-lowering drug', 'Blutzuckersenker'),
    aliases: [
      'insulin',
      'glimepirid',
      'glimepiride',
      'gliclazid',
      'gliclazide',
      'glibenclamid',
      'sitagliptin',
      'januvia',
      'empagliflozin',
      'jardiance',
      'dapagliflozin',
      'forxiga',
      'semaglutid',
      'semaglutide',
      'ozempic',
      'rybelsus',
      'liraglutid',
      'liraglutide',
      'victoza',
      'dulaglutid',
      'trulicity',
      'tirzepatid',
      'tirzepatide',
      'mounjaro',
      'pioglitazon',
      'pioglitazone',
    ],
  );

  static const protonPumpInhibitor = MedicationClass(
    id: 'ppi',
    name: LocalizedText('Proton pump inhibitor', 'Protonenpumpenhemmer'),
    aliases: [
      'omeprazol',
      'omeprazole',
      'pantoprazol',
      'pantoprazole',
      'esomeprazol',
      'esomeprazole',
      'lansoprazol',
      'lansoprazole',
      'rabeprazol',
      'rabeprazole',
      'dexlansoprazol',
      'dexlansoprazole',
      'pantozol',
      'nexium',
      'antra',
      'agopton',
      'pariet',
    ],
  );

  static const statin = MedicationClass(
    id: 'statin',
    name: LocalizedText('Statin', 'Statin'),
    aliases: [
      'atorvastatin',
      'simvastatin',
      'rosuvastatin',
      'pravastatin',
      'fluvastatin',
      'lovastatin',
      'pitavastatin',
      'sortis',
      'zocor',
      'crestor',
      'inegy',
    ],
  );

  static const potassiumRaising = MedicationClass(
    id: 'potassium-raising',
    name: LocalizedText(
      'ACE inhibitor, ARB or potassium-sparing diuretic',
      'ACE-Hemmer, Sartan oder kaliumsparendes Diuretikum',
    ),
    aliases: [
      'ramipril',
      'enalapril',
      'lisinopril',
      'captopril',
      'perindopril',
      'benazepril',
      'delix',
      'candesartan',
      'valsartan',
      'losartan',
      'irbesartan',
      'telmisartan',
      'olmesartan',
      'sacubitril',
      'entresto',
      'spironolacton',
      'spironolactone',
      'aldactone',
      'eplerenon',
      'eplerenone',
      'amilorid',
      'amiloride',
      'triamteren',
      'triamterene',
      'finerenon',
      'finerenone',
    ],
  );

  static const diuretic = MedicationClass(
    id: 'thiazide-or-loop-diuretic',
    name: LocalizedText(
      'Thiazide or loop diuretic',
      'Thiazid- oder Schleifendiuretikum',
    ),
    aliases: [
      'hydrochlorothiazid',
      'hydrochlorothiazide',
      'hct',
      'hctz',
      'chlortalidon',
      'chlorthalidone',
      'indapamid',
      'indapamide',
      'xipamid',
      'furosemid',
      'furosemide',
      'lasix',
      'torasemid',
      'torasemide',
      'piretanid',
    ],
  );

  static const lithium = MedicationClass(
    id: 'lithium',
    name: LocalizedText('Lithium', 'Lithium'),
    aliases: ['lithium', 'quilonum', 'hypnorex'],
  );

  static const amiodarone = MedicationClass(
    id: 'amiodarone',
    name: LocalizedText('Amiodarone', 'Amiodaron'),
    aliases: ['amiodaron', 'amiodarone', 'cordarex'],
  );

  static const glucocorticoid = MedicationClass(
    id: 'glucocorticoid',
    name: LocalizedText('Systemic glucocorticoid', 'Systemisches Kortison'),
    aliases: [
      'prednisolon',
      'prednisolone',
      'prednison',
      'prednisone',
      'methylprednisolon',
      'methylprednisolone',
      'dexamethason',
      'dexamethasone',
      'hydrocortison',
      'hydrocortisone',
      'decortin',
      'urbason',
    ],
  );

  static const oralEstrogen = MedicationClass(
    id: 'oral-estrogen',
    name: LocalizedText(
      'Oral estrogen or combined pill',
      'Orales Östrogen oder kombinierte Pille',
    ),
    aliases: [
      'ethinylestradiol',
      'estradiol',
      'östradiol',
      'estradiolvalerat',
      'östrogen',
      'estrogen',
      'antibabypille',
      'pille',
      'combined pill',
      'hormonersatztherapie',
    ],
  );

  static const hormonalContraceptive = MedicationClass(
    id: 'hormonal-contraceptive',
    name: LocalizedText('Hormonal contraceptive', 'Hormonelle Verhütung'),
    aliases: [
      'ethinylestradiol',
      'antibabypille',
      'pille',
      'minipille',
      'kontrazeptivum',
      'contraceptive',
      'levonorgestrel',
      'desogestrel',
      'etonogestrel',
      'dienogest',
      'drospirenon',
      'drospirenone',
      'chlormadinon',
      'nomegestrol',
    ],
  );

  static const testosterone = MedicationClass(
    id: 'testosterone',
    name: LocalizedText('Testosterone therapy', 'Testosterontherapie'),
    aliases: [
      'testosteron',
      'testosterone',
      'testogel',
      'nebido',
      'tostran',
      'testim',
      'trt',
    ],
  );

  static const serotonergic = MedicationClass(
    id: 'serotonergic',
    name: LocalizedText('Serotonergic drug', 'Serotonerges Medikament'),
    aliases: [
      'sertralin',
      'sertraline',
      'citalopram',
      'escitalopram',
      'fluoxetin',
      'fluoxetine',
      'paroxetin',
      'paroxetine',
      'fluvoxamin',
      'fluvoxamine',
      'venlafaxin',
      'venlafaxine',
      'duloxetin',
      'duloxetine',
      'sumatriptan',
      'rizatriptan',
      'zolmitriptan',
      'tramadol',
    ],
  );

  static const immunosuppressant = MedicationClass(
    id: 'immunosuppressant',
    name: LocalizedText('Immunosuppressant', 'Immunsuppressivum'),
    aliases: [
      'ciclosporin',
      'cyclosporine',
      'tacrolimus',
      'sirolimus',
      'everolimus',
    ],
  );

  static const cardiacGlycoside = MedicationClass(
    id: 'cardiac-glycoside',
    name: LocalizedText('Digoxin / digitoxin', 'Digoxin / Digitoxin'),
    aliases: ['digoxin', 'digitoxin', 'lanicor', 'digimerck'],
  );

  static const chelatingAntibiotic = MedicationClass(
    id: 'chelating-antibiotic',
    name: LocalizedText(
      'Quinolone or tetracycline antibiotic',
      'Chinolon- oder Tetrazyklin-Antibiotikum',
    ),
    aliases: [
      'ciprofloxacin',
      'levofloxacin',
      'moxifloxacin',
      'ofloxacin',
      'norfloxacin',
      'doxycyclin',
      'doxycycline',
      'minocyclin',
      'minocycline',
      'tetracyclin',
      'tetracycline',
    ],
  );

  static const bisphosphonate = MedicationClass(
    id: 'bisphosphonate',
    name: LocalizedText('Oral bisphosphonate', 'Orales Bisphosphonat'),
    aliases: [
      'alendronat',
      'alendronate',
      'alendronsäure',
      'risedronat',
      'risedronate',
      'ibandronat',
      'ibandronate',
      'fosamax',
    ],
  );

  static const trimethoprim = MedicationClass(
    id: 'trimethoprim',
    name: LocalizedText('Trimethoprim', 'Trimethoprim'),
    aliases: [
      'trimethoprim',
      'cotrimoxazol',
      'co trimoxazol',
      'cotrimoxazole',
      'co trimoxazole',
    ],
  );

  static const classes = <MedicationClass>[
    thyroidHormone,
    vitaminKAntagonist,
    directOralAnticoagulant,
    antiplatelet,
    metformin,
    otherAntidiabetic,
    protonPumpInhibitor,
    statin,
    potassiumRaising,
    diuretic,
    lithium,
    amiodarone,
    glucocorticoid,
    oralEstrogen,
    hormonalContraceptive,
    testosterone,
    serotonergic,
    immunosuppressant,
    cardiacGlycoside,
    chelatingAntibiotic,
    bisphosphonate,
    trimethoprim,
  ];

  static final Map<String, MedicationClass> _byId = {
    for (final item in classes) item.id: item,
  };

  MedicationClass? byId(String id) => _byId[id];

  /// Every class whose alias appears in [name]. A combination product
  /// ("Ramipril/HCT") belongs to each class it contains.
  Set<String> classIdsFor(String name) => {
    for (final item in classes)
      if (item.matchesName(name)) item.id,
  };

  /// Every class a supplement-ledger substance stands for.
  Set<String> classIdsForSubstance(String substanceId) => {
    for (final item in classes)
      if (item.substanceIds.contains(substanceId)) item.id,
  };
}
