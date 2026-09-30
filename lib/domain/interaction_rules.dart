/// The curated table of interactions the app checks deterministically.
///
/// A model can know that biotin distorts a TSH assay and still fail to notice
/// the biotin: in a large health record the link has no words in common with
/// the question, and attention to it is a probability. This table moves the
/// *known* high-stakes links out of that probability. Code evaluates every rule
/// against every exposure and every measurement, every time, and the result is
/// shown in the app and handed to the advisor as findings it must address.
///
/// Scope is deliberately what can be checked from the record: supplements and
/// medications against lab values (assay interference, physiological effects,
/// masking, pre-analytical timing), a small set of supplement–drug
/// interactions, and official upper intake levels. Each rule states its source.
/// A rule's absence means "not in this table", never "no interaction exists" —
/// the advisor is still asked to judge every exposure itself.
///
/// Wording is careful on purpose: effects are assay-, dose- and
/// person-dependent, so rules say "can" and point at what to check, and never
/// tell anyone to stop a prescribed medicine.
library;

import 'biomarker_concepts.dart';
import 'localized_text.dart';
import 'medication_catalog.dart';
import 'name_matching.dart';
import 'substance_catalog.dart';
import 'units.dart';

enum InteractionKind {
  /// The substance distorts the measurement, not the body.
  assayInterference,

  /// The circumstances of the sample (timing, exercise, illness) shift it.
  preAnalytic,

  /// A real change in the body that the value will show.
  physiological,

  /// The value looks fine while the underlying problem continues.
  masking,

  /// One thing reduces how much of another is absorbed.
  absorption,

  /// Two things taken together change each other's effect or safety.
  drugInteraction,

  /// An intake above an official tolerable upper intake level.
  upperLimit,
}

enum InteractionSeverity { high, moderate, low }

enum EffectDirection {
  falselyLow,
  falselyHigh,
  raises,
  lowers,

  /// The value looks normal although the condition behind it is not.
  masks,

  /// The effect can go either way.
  unpredictable,
}

class AffectedTest {
  const AffectedTest(this.concept, this.direction);

  final BiomarkerConcept concept;
  final EffectDirection direction;
}

/// What a person takes or does that can set a rule off.
sealed class RuleTrigger {
  const RuleTrigger();
}

/// Something taken, recognised through the substance catalog or by name.
///
/// [substanceIds] are the catalog identities whose recorded amounts count
/// towards a rule's thresholds. [nameKeywords] recognise the family by name —
/// salts such as "Eisen(II)-fumarat", extracts, and products whose ingredients
/// were never broken down — whose amounts are *not* comparable, so a match
/// through them is a match with an unknown dose.
class SubstanceTrigger extends RuleTrigger {
  const SubstanceTrigger({
    required this.label,
    required this.substanceIds,
    this.nameKeywords = const [],
    this.massFactors = const {},
  });

  final LocalizedText label;
  final Set<String> substanceIds;
  final List<String> nameKeywords;

  /// Fraction of a compound's mass that is the substance the threshold is
  /// about, for the few compounds where that is fixed chemistry — potassium
  /// iodide is 76.45% iodine by mass.
  final Map<String, double> massFactors;

  static const _catalog = SubstanceCatalog();

  /// How an ingredient name matches: `dose` when its amount counts towards
  /// thresholds, `name` when it belongs to the family but its amount does not.
  SubstanceMatch? match(String ingredientName) {
    final id = _catalog.idFor(ingredientName);
    if (id != null && (substanceIds.contains(id) || massFactors[id] != null)) {
      return SubstanceMatch(substanceId: id, doseComparable: true);
    }
    if (nameKeywords.any(
      (keyword) => matchesKeyword(ingredientName, keyword),
    )) {
      return SubstanceMatch(substanceId: id, doseComparable: false);
    }
    return null;
  }
}

class SubstanceMatch {
  const SubstanceMatch({
    required this.substanceId,
    required this.doseComparable,
  });

  final String? substanceId;
  final bool doseComparable;
}

/// A medication class, whether recorded as a medication or, for the classes
/// that have a substance identity, logged in the supplement ledger.
class MedicationTrigger extends RuleTrigger {
  const MedicationTrigger(this.classIds);

  final Set<String> classIds;
}

/// Something logged as a symptom or tag, recognised by its name.
class EventTrigger extends RuleTrigger {
  const EventTrigger({required this.label, required this.keywords});

  final LocalizedText label;
  final List<String> keywords;

  bool matchesName(String name) =>
      keywords.any((keyword) => matchesKeyword(name, keyword));
}

/// What to do before a blood draw, written into a lab plan item by code.
///
/// Only for rules where timing changes the result and the fix is a concrete
/// instruction. [mentions] are keywords (see `matchesKeyword`) that show a
/// model-written preparation already says it, so the note is not doubled.
class PreparationNote {
  const PreparationNote(this.text, {required this.mentions});

  final LocalizedText text;
  final List<String> mentions;

  bool isCoveredBy(String preparation) =>
      mentions.any((keyword) => matchesKeyword(preparation, keyword));
}

/// A dose from which a rule applies, and how long before a blood draw an
/// intake at that dose still makes a result suspect.
class DoseThreshold {
  const DoseThreshold(this.amount, this.unit, {required this.lookback});

  final double amount;
  final CanonicalUnit unit;
  final Duration lookback;
}

class InteractionRule {
  const InteractionRule({
    required this.id,
    required this.kind,
    required this.severity,
    required this.trigger,
    required this.title,
    required this.explanation,
    required this.advice,
    required this.source,
    this.partner,
    this.affects = const [],
    this.thresholds = const [],
    this.lookback,
    this.firesWhenDoseUnknown = true,
    this.minimumSpacing,
    this.preparation,
  });

  /// Stable, used in finding ids; never renamed once shipped.
  final String id;
  final InteractionKind kind;
  final InteractionSeverity severity;
  final RuleTrigger trigger;

  /// For an interaction between two things taken: the other one.
  final RuleTrigger? partner;
  final List<AffectedTest> affects;

  /// Ascending by amount. Empty means any amount counts. The highest
  /// threshold reached decides the retrospective window.
  final List<DoseThreshold> thresholds;

  /// How long before a blood draw exposure makes a result suspect, when no
  /// threshold says otherwise. Null: the rule is about ongoing use and is not
  /// checked against past measurements.
  final Duration? lookback;

  /// Whether a match whose amount cannot be compared (a salt, an extract, a
  /// product without ingredients) still fires. True for rules where missing a
  /// case costs more than a spurious line; false where ordinary doses are
  /// harmless and only a known high dose matters.
  final bool firesWhenDoseUnknown;

  /// For two things taken that must be spaced apart: the minimum gap. When
  /// both sides are in the ledger, the times actually logged are checked.
  final Duration? minimumSpacing;

  /// Written into the preparation of a planned test this rule affects.
  final PreparationNote? preparation;

  final LocalizedText title;
  final LocalizedText explanation;
  final LocalizedText advice;
  final String source;
}

const _minerals = SubstanceTrigger(
  label: LocalizedText(
    'Calcium, iron, magnesium or zinc',
    'Calcium, Eisen, Magnesium oder Zink',
  ),
  substanceIds: {'calcium', 'iron', 'magnesium', 'zinc'},
  nameKeywords: [
    'calcium*',
    'kalzium*',
    'eisen*',
    'iron*',
    'ferrous*',
    'ferric*',
    'ferro*',
    'magnesium*',
    'zink*',
    'zinc*',
  ],
);

const _redYeastRice = SubstanceTrigger(
  label: LocalizedText('Red yeast rice', 'Rotschimmelreis'),
  substanceIds: {'red-yeast-rice', 'monacolin-k'},
  nameKeywords: [
    'rotschimmelreis*',
    'red yeast*',
    'monacolin*',
    'monakolin*',
    'monascus*',
  ],
);

const _ashwagandha = SubstanceTrigger(
  label: LocalizedText('Ashwagandha', 'Ashwagandha'),
  substanceIds: {'ashwagandha'},
  nameKeywords: ['ashwagandha*', 'withania*', 'schlafbeere*', 'ksm 66'],
);

const _berberine = SubstanceTrigger(
  label: LocalizedText('Berberine', 'Berberin'),
  substanceIds: {'berberine'},
  nameKeywords: ['berberin*'],
);

const _anticoagulants = MedicationTrigger({
  'vitamin-k-antagonist',
  'doac',
  'antiplatelet',
});

/// The curated table. Order is presentation order within a severity.
const interactionRules = <InteractionRule>[
  InteractionRule(
    id: 'biotin-streptavidin-immunoassay',
    kind: InteractionKind.assayInterference,
    severity: InteractionSeverity.high,
    trigger: SubstanceTrigger(
      label: LocalizedText('Biotin', 'Biotin'),
      substanceIds: {'biotin'},
      nameKeywords: ['biotin*'],
    ),
    thresholds: [
      DoseThreshold(1, CanonicalUnit.milligram, lookback: Duration(hours: 72)),
      DoseThreshold(100, CanonicalUnit.milligram, lookback: Duration(days: 7)),
    ],
    affects: [
      AffectedTest(BiomarkerConcepts.tsh, EffectDirection.falselyLow),
      AffectedTest(BiomarkerConcepts.ft4, EffectDirection.falselyHigh),
      AffectedTest(BiomarkerConcepts.ft3, EffectDirection.falselyHigh),
      AffectedTest(BiomarkerConcepts.trak, EffectDirection.falselyHigh),
      AffectedTest(BiomarkerConcepts.troponin, EffectDirection.falselyLow),
      AffectedTest(BiomarkerConcepts.pth, EffectDirection.falselyLow),
      AffectedTest(BiomarkerConcepts.hcg, EffectDirection.falselyLow),
      AffectedTest(BiomarkerConcepts.ferritin, EffectDirection.falselyLow),
      AffectedTest(BiomarkerConcepts.psa, EffectDirection.falselyLow),
      AffectedTest(BiomarkerConcepts.lh, EffectDirection.falselyLow),
      AffectedTest(BiomarkerConcepts.fsh, EffectDirection.falselyLow),
      AffectedTest(BiomarkerConcepts.prolactin, EffectDirection.falselyLow),
      AffectedTest(BiomarkerConcepts.insulin, EffectDirection.falselyLow),
      AffectedTest(BiomarkerConcepts.ntProBnp, EffectDirection.falselyLow),
      AffectedTest(BiomarkerConcepts.cortisol, EffectDirection.falselyHigh),
      AffectedTest(BiomarkerConcepts.testosterone, EffectDirection.falselyHigh),
      AffectedTest(BiomarkerConcepts.estradiol, EffectDirection.falselyHigh),
      AffectedTest(BiomarkerConcepts.progesterone, EffectDirection.falselyHigh),
      AffectedTest(BiomarkerConcepts.dheaS, EffectDirection.falselyHigh),
      AffectedTest(BiomarkerConcepts.vitaminD, EffectDirection.falselyHigh),
      AffectedTest(BiomarkerConcepts.vitaminB12, EffectDirection.falselyHigh),
      AffectedTest(BiomarkerConcepts.folate, EffectDirection.falselyHigh),
    ],
    title: LocalizedText(
      'Biotin can distort many blood tests',
      'Biotin kann viele Bluttests verfälschen',
    ),
    explanation: LocalizedText(
      'High-dose biotin interferes with immunoassays that use '
          'streptavidin–biotin binding. Depending on the lab\'s method, TSH, '
          'troponin, parathyroid hormone and ferritin can read falsely low '
          'while free T4, free T3 and several hormones and vitamins read '
          'falsely high — together a pattern that can mimic Graves\' disease.',
      'Hochdosiertes Biotin stört Immunoassays, die mit Streptavidin–Biotin '
          'arbeiten. Je nach Labormethode können TSH, Troponin, Parathormon '
          'und Ferritin falsch niedrig, freies T4, freies T3 sowie mehrere '
          'Hormone und Vitamine falsch hoch ausfallen – zusammen ein Muster, '
          'das einen Morbus Basedow vortäuschen kann.',
    ),
    advice: LocalizedText(
      'Pause biotin before blood tests — at least 72 hours at 1–100 mg a day, '
          'about a week at 100 mg a day or more — and tell the lab you take '
          'it. Read affected values measured while taking it with caution.',
      'Biotin vor Blutabnahmen pausieren – mindestens 72 Stunden bei '
          '1–100 mg pro Tag, etwa eine Woche ab 100 mg pro Tag – und dem Labor '
          'die Einnahme mitteilen. Unter Biotin gemessene betroffene Werte mit '
          'Vorsicht bewerten.',
    ),
    preparation: PreparationNote(
      LocalizedText(
        'Pause biotin for at least 72 h before (about a week from 100 mg a '
            'day) and tell the lab.',
        'Biotin mind. 72 Std. vorher pausieren (ab 100 mg/Tag etwa eine '
            'Woche) und dem Labor mitteilen.',
      ),
      mentions: ['biotin*'],
    ),
    source:
        'FDA Safety Communication on biotin interference with laboratory '
        'tests (2017, updated 2019); ADLM Academy guidance on biotin '
        'interference.',
  ),
  InteractionRule(
    id: 'creatine-raises-creatinine',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: SubstanceTrigger(
      label: LocalizedText('Creatine', 'Kreatin'),
      substanceIds: {'creatine'},
      nameKeywords: ['creatine*', 'kreatin', 'kreatin monohydrat', 'creapure'],
    ),
    lookback: Duration(days: 28),
    affects: [
      AffectedTest(BiomarkerConcepts.creatinine, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.egfr, EffectDirection.lowers),
    ],
    title: LocalizedText(
      'Creatine raises creatinine',
      'Kreatin erhöht den Kreatininwert',
    ),
    explanation: LocalizedText(
      'Creatine supplements are partly converted to creatinine, so serum '
          'creatinine rises and the creatinine-based eGFR falls without any '
          'change in kidney function.',
      'Kreatin wird teilweise zu Kreatinin abgebaut. Das Serum-Kreatinin '
          'steigt und die daraus berechnete eGFR sinkt, ohne dass sich die '
          'Nierenfunktion ändert.',
    ),
    advice: LocalizedText(
      'Interpret creatinine and eGFR with this in mind; if kidney function '
          'matters, ask for cystatin C (or eGFRcr-cys) rather than relying on '
          'creatinine alone.',
      'Kreatinin und eGFR entsprechend einordnen; wenn es auf die '
          'Nierenfunktion ankommt, Cystatin C (bzw. eGFRcr-cys) statt '
          'Kreatinin allein bestimmen lassen.',
    ),
    source:
        'KDIGO 2024 Clinical Practice Guideline for CKD: use cystatin C when '
        'creatinine-based eGFR is less accurate.',
  ),
  InteractionRule(
    id: 'iron-before-iron-studies',
    kind: InteractionKind.preAnalytic,
    severity: InteractionSeverity.moderate,
    trigger: SubstanceTrigger(
      label: LocalizedText('Iron', 'Eisen'),
      substanceIds: {'iron'},
      nameKeywords: ['eisen*', 'iron*', 'ferrous*', 'ferric*', 'ferro*'],
    ),
    lookback: Duration(hours: 24),
    affects: [
      AffectedTest(BiomarkerConcepts.serumIron, EffectDirection.raises),
      AffectedTest(
        BiomarkerConcepts.transferrinSaturation,
        EffectDirection.raises,
      ),
    ],
    title: LocalizedText(
      'Iron taken before the draw inflates iron values',
      'Eisen vor der Blutabnahme verfälscht Eisenwerte',
    ),
    explanation: LocalizedText(
      'A dose of oral iron raises serum iron several-fold for hours, which '
          'also inflates transferrin saturation.',
      'Eine Dosis Eisen erhöht das Serumeisen für Stunden um ein Mehrfaches '
          '– und damit auch die Transferrinsättigung.',
    ),
    advice: LocalizedText(
      'Take no iron supplement in the 24 hours before iron studies; ferritin '
          'is much less affected.',
      '24 Stunden vor Eisenwerten kein Eisenpräparat einnehmen; Ferritin ist '
          'davon deutlich weniger betroffen.',
    ),
    preparation: PreparationNote(
      LocalizedText(
        'No iron supplement in the 24 h before.',
        'Kein Eisenpräparat in den 24 Std. davor.',
      ),
      mentions: ['eisen*', 'iron*'],
    ),
    source:
        'Specimen guidance for iron studies: no iron supplements for 24 h '
        'before collection.',
  ),
  InteractionRule(
    id: 'b12-supplement-serum-level',
    kind: InteractionKind.masking,
    severity: InteractionSeverity.low,
    trigger: SubstanceTrigger(
      label: LocalizedText('Vitamin B12', 'Vitamin B12'),
      substanceIds: {'vitamin-b12'},
      nameKeywords: ['b12', 'cobalamin*', 'methylcobalamin*'],
    ),
    thresholds: [
      DoseThreshold(100, CanonicalUnit.microgram, lookback: Duration(days: 14)),
    ],
    affects: [
      AffectedTest(BiomarkerConcepts.vitaminB12, EffectDirection.raises),
    ],
    title: LocalizedText(
      'B12 supplements make serum B12 look adequate',
      'B12-Präparate lassen den Serum-B12-Wert gut aussehen',
    ),
    explanation: LocalizedText(
      'Under supplementation, serum B12 mainly reflects recent intake, so a '
          'normal or high value says little about how well B12 reaches the '
          'tissues.',
      'Unter Supplementierung spiegelt das Serum-B12 vor allem die letzte '
          'Zufuhr; ein normaler oder hoher Wert sagt wenig darüber, wie gut '
          'B12 in den Geweben ankommt.',
    ),
    advice: LocalizedText(
      'For a real status check prefer holotranscobalamin and methylmalonic '
          'acid, and keep the supplement in mind when reading serum B12.',
      'Für eine echte Statusbestimmung besser Holotranscobalamin und '
          'Methylmalonsäure; bei Serum-B12 die Einnahme mitbedenken.',
    ),
    source:
        'Laboratory guidance on vitamin B12 status markers (holoTC, MMA) '
        'under supplementation.',
  ),
  InteractionRule(
    id: 'high-dose-folate-masks-b12',
    kind: InteractionKind.masking,
    severity: InteractionSeverity.moderate,
    trigger: SubstanceTrigger(
      label: LocalizedText('Folic acid', 'Folsäure'),
      substanceIds: {'folate'},
      nameKeywords: ['folsäure*', 'folat*', 'folic*', 'methylfolat*', '5 mthf'],
    ),
    thresholds: [
      DoseThreshold(1, CanonicalUnit.milligram, lookback: Duration(days: 30)),
    ],
    firesWhenDoseUnknown: false,
    affects: [
      AffectedTest(BiomarkerConcepts.hemoglobin, EffectDirection.masks),
      AffectedTest(BiomarkerConcepts.mcv, EffectDirection.masks),
    ],
    title: LocalizedText(
      'High-dose folate can hide a B12 deficiency',
      'Hochdosierte Folsäure kann einen B12-Mangel verdecken',
    ),
    explanation: LocalizedText(
      'Folic acid of 1 mg a day or more corrects the anaemia of B12 '
          'deficiency — haemoglobin and MCV look normal — while the nerve '
          'damage continues.',
      'Folsäure ab 1 mg pro Tag behebt die Blutarmut eines B12-Mangels – '
          'Hämoglobin und MCV sehen normal aus –, während die '
          'Nervenschädigung weitergeht.',
    ),
    advice: LocalizedText(
      'Check B12 status (holotranscobalamin or methylmalonic acid) rather than '
          'relying on a normal blood count.',
      'B12-Status (Holotranscobalamin oder Methylmalonsäure) prüfen, statt '
          'sich auf ein normales Blutbild zu verlassen.',
    ),
    source:
        'US National Academies tolerable upper intake level for folic acid '
        '(1 mg/day), set because of masking of B12 deficiency.',
  ),
  InteractionRule(
    id: 'vitamin-d-above-upper-level',
    kind: InteractionKind.upperLimit,
    severity: InteractionSeverity.moderate,
    trigger: SubstanceTrigger(
      label: LocalizedText('Vitamin D', 'Vitamin D'),
      substanceIds: {'vitamin-d'},
      nameKeywords: ['cholecalciferol*', 'colecalciferol*', 'vitamin d*'],
    ),
    thresholds: [
      DoseThreshold(100, CanonicalUnit.microgram, lookback: Duration(days: 90)),
    ],
    firesWhenDoseUnknown: false,
    affects: [
      AffectedTest(BiomarkerConcepts.vitaminD, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.calcium, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Vitamin D above the upper level',
      'Vitamin D über der Höchstmenge',
    ),
    explanation: LocalizedText(
      'More than 100 µg (4,000 IU) a day exceeds the EFSA tolerable upper '
          'intake level; over time it can raise calcium.',
      'Mehr als 100 µg (4.000 IE) pro Tag überschreiten die tolerierbare '
          'Höchstmenge der EFSA; auf Dauer kann das Calcium steigen.',
    ),
    advice: LocalizedText(
      'Keep 25-OH vitamin D and calcium under review at this dose, and agree '
          'the dose with a doctor.',
      'Bei dieser Dosis 25-OH-Vitamin D und Calcium im Blick behalten und die '
          'Dosis ärztlich abstimmen.',
    ),
    source:
        'EFSA 2023 scientific opinion: tolerable upper intake level for '
        'vitamin D, 100 µg/day for adults.',
  ),
  InteractionRule(
    id: 'iodine-excess-thyroid',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: SubstanceTrigger(
      label: LocalizedText('Iodine or seaweed', 'Jod oder Algen'),
      substanceIds: {'iodine'},
      massFactors: {'potassium-iodide': 0.7645},
      nameKeywords: [
        'jod*',
        'iod*',
        'kelp*',
        'seetang*',
        'meeresalge*',
        'braunalge*',
        'ascophyllum*',
        'fucus*',
        'blasentang*',
        'kombu*',
        'wakame*',
      ],
    ),
    thresholds: [
      DoseThreshold(500, CanonicalUnit.microgram, lookback: Duration(days: 60)),
    ],
    affects: [
      AffectedTest(BiomarkerConcepts.tsh, EffectDirection.unpredictable),
      AffectedTest(BiomarkerConcepts.ft4, EffectDirection.unpredictable),
    ],
    title: LocalizedText(
      'High iodine intake can disturb thyroid function',
      'Viel Jod kann die Schilddrüsenfunktion stören',
    ),
    explanation: LocalizedText(
      'More than 500 µg of iodine a day — quickly reached with kelp or '
          'seaweed products, whose iodine content varies widely — can push '
          'thyroid function either way, especially with existing thyroid '
          'disease.',
      'Mehr als 500 µg Jod pro Tag – mit Algen- oder Tangprodukten schnell '
          'erreicht, deren Jodgehalt stark schwankt – kann die '
          'Schilddrüsenfunktion in beide Richtungen verschieben, besonders bei '
          'bestehender Schilddrüsenerkrankung.',
    ),
    advice: LocalizedText(
      'Check the iodine content per daily dose and read TSH and free T4 with '
          'it in mind.',
      'Jodgehalt pro Tagesdosis prüfen und TSH sowie freies T4 vor diesem '
          'Hintergrund bewerten.',
    ),
    source:
        'BfR: at most 500 µg iodine/day from all sources; EFSA tolerable upper '
        'intake level 600 µg/day; consumer warnings on iodine in algae '
        'products.',
  ),
  InteractionRule(
    id: 'ashwagandha-thyroid-liver',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: _ashwagandha,
    lookback: Duration(days: 60),
    affects: [
      AffectedTest(BiomarkerConcepts.tsh, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.ft4, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.ft3, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.alt, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.ast, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.bilirubin, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Ashwagandha can affect thyroid and liver values',
      'Ashwagandha kann Schilddrüsen- und Leberwerte beeinflussen',
    ),
    explanation: LocalizedText(
      'Ashwagandha can raise thyroid hormones and lower TSH — cases of '
          'thyrotoxicosis have been reported — and rarely causes liver injury.',
      'Ashwagandha kann Schilddrüsenhormone erhöhen und TSH senken – Fälle '
          'von Schilddrüsenüberfunktion sind beschrieben – und verursacht '
          'selten Leberschäden.',
    ),
    advice: LocalizedText(
      'Mention it whenever thyroid or liver values are assessed; with thyroid '
          'disease or thyroid medication, agree it with a doctor.',
      'Bei der Bewertung von Schilddrüsen- oder Leberwerten erwähnen; bei '
          'Schilddrüsenerkrankung oder -medikation ärztlich abstimmen.',
    ),
    source:
        'Published case reports of ashwagandha-associated thyrotoxicosis; '
        'LiverTox (NIH): Ashwagandha.',
  ),
  InteractionRule(
    id: 'red-yeast-rice-statin-like',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: _redYeastRice,
    lookback: Duration(days: 30),
    affects: [
      AffectedTest(BiomarkerConcepts.ldl, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.ck, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.alt, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Red yeast rice acts like a statin',
      'Rotschimmelreis wirkt wie ein Statin',
    ),
    explanation: LocalizedText(
      'Its monacolin K is chemically identical to lovastatin: it lowers LDL '
          'and can raise CK and liver enzymes. In the EU a daily dose must '
          'stay below 3 mg of monacolins.',
      'Sein Monacolin K ist chemisch identisch mit Lovastatin: Es senkt LDL '
          'und kann CK und Leberwerte erhöhen. In der EU muss eine Tagesdosis '
          'unter 3 mg Monacolinen bleiben.',
    ),
    advice: LocalizedText(
      'Read lipid results as treated values, report muscle pain, and do not '
          'combine it with a statin.',
      'Lipidwerte als behandelte Werte lesen, Muskelschmerzen melden und '
          'nicht mit einem Statin kombinieren.',
    ),
    source:
        'Commission Regulation (EU) 2022/860 (monacolins below 3 mg/day); '
        'EFSA 2018 scientific opinion on monacolins from red yeast rice.',
  ),
  InteractionRule(
    id: 'nicotinic-acid-high-dose',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: SubstanceTrigger(
      label: LocalizedText('Nicotinic acid (niacin)', 'Nicotinsäure (Niacin)'),
      substanceIds: {'nicotinic-acid', 'niacin'},
      nameKeywords: ['nicotinsäure*', 'nikotinsäure*', 'nicotinic acid'],
    ),
    thresholds: [
      DoseThreshold(500, CanonicalUnit.milligram, lookback: Duration(days: 30)),
    ],
    firesWhenDoseUnknown: false,
    affects: [
      AffectedTest(BiomarkerConcepts.alt, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.ast, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.glucose, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.hba1c, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.uricAcid, EffectDirection.raises),
    ],
    title: LocalizedText(
      'High-dose niacin affects liver, glucose and uric acid',
      'Hochdosiertes Niacin beeinflusst Leber, Blutzucker und Harnsäure',
    ),
    explanation: LocalizedText(
      'Nicotinic acid at pharmacological doses (500 mg a day and more) can '
          'raise liver enzymes, blood glucose and uric acid.',
      'Nicotinsäure in pharmakologischer Dosis (ab 500 mg pro Tag) kann '
          'Leberwerte, Blutzucker und Harnsäure erhöhen.',
    ),
    advice: LocalizedText(
      'Keep liver enzymes, glucose/HbA1c and uric acid under review; '
          'nicotinamide does not have these effects.',
      'Leberwerte, Blutzucker/HbA1c und Harnsäure im Blick behalten; '
          'Nicotinamid hat diese Wirkungen nicht.',
    ),
    source: 'LiverTox (NIH): Niacin; nicotinic acid prescribing information.',
  ),
  InteractionRule(
    id: 'berberine-glucose-lipids',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.low,
    trigger: _berberine,
    lookback: Duration(days: 30),
    affects: [
      AffectedTest(BiomarkerConcepts.glucose, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.hba1c, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.ldl, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.triglycerides, EffectDirection.lowers),
    ],
    title: LocalizedText(
      'Berberine lowers glucose and lipids',
      'Berberin senkt Blutzucker und Blutfette',
    ),
    explanation: LocalizedText(
      'Berberine lowers blood glucose, HbA1c and LDL, so values measured while '
          'taking it are treated values.',
      'Berberin senkt Blutzucker, HbA1c und LDL; unter Einnahme gemessene '
          'Werte sind daher behandelte Werte.',
    ),
    advice: LocalizedText(
      'Keep it in mind when reading glucose and lipid results.',
      'Bei der Bewertung von Blutzucker- und Lipidwerten berücksichtigen.',
    ),
    source: 'Meta-analyses of berberine in type 2 diabetes and dyslipidaemia.',
  ),
  InteractionRule(
    id: 'dhea-sex-hormones',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: SubstanceTrigger(
      label: LocalizedText('DHEA', 'DHEA'),
      substanceIds: {'dhea'},
      nameKeywords: ['dhea', 'prasteron*', 'dehydroepiandrosteron*'],
    ),
    lookback: Duration(days: 14),
    affects: [
      AffectedTest(BiomarkerConcepts.dheaS, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.testosterone, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.estradiol, EffectDirection.raises),
    ],
    title: LocalizedText(
      'DHEA raises sex hormone levels',
      'DHEA erhöht Sexualhormonwerte',
    ),
    explanation: LocalizedText(
      'DHEA is converted into androgens and estrogens, so DHEA-S, testosterone '
          'and estradiol measured while taking it do not reflect the body\'s '
          'own production.',
      'DHEA wird zu Androgenen und Östrogenen umgewandelt; unter Einnahme '
          'gemessene DHEA-S-, Testosteron- und Östradiolwerte spiegeln nicht '
          'die körpereigene Produktion.',
    ),
    advice: LocalizedText(
      'Tell whoever assesses hormone results that you take DHEA.',
      'Bei der Bewertung von Hormonwerten die DHEA-Einnahme angeben.',
    ),
    source:
        'Pharmacokinetic studies of oral DHEA (conversion to androgens and '
        'estrogens).',
  ),
  InteractionRule(
    id: 'egcg-liver',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: SubstanceTrigger(
      label: LocalizedText(
        'Green tea extract (EGCG)',
        'Grüntee-Extrakt (EGCG)',
      ),
      substanceIds: {'egcg'},
      nameKeywords: [
        'egcg',
        'epigallocatechin*',
        'grüntee*',
        'green tea*',
        'grüner tee*',
        'camellia sinensis',
      ],
    ),
    thresholds: [
      DoseThreshold(
        800,
        CanonicalUnit.milligram,
        lookback: Duration(days: 120),
      ),
    ],
    firesWhenDoseUnknown: false,
    affects: [
      AffectedTest(BiomarkerConcepts.alt, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.ast, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Concentrated green tea extract can strain the liver',
      'Konzentrierter Grüntee-Extrakt kann die Leber belasten',
    ),
    explanation: LocalizedText(
      'EFSA links 800 mg of EGCG a day or more from supplements, taken for '
          'months, to raised liver enzymes in some people.',
      'Die EFSA bringt 800 mg EGCG pro Tag oder mehr aus '
          'Nahrungsergänzungsmitteln über Monate mit erhöhten Leberwerten bei '
          'einem Teil der Anwender in Verbindung.',
    ),
    advice: LocalizedText(
      'Keep ALT and AST under review and stop if they rise.',
      'ALT und AST im Blick behalten und bei Anstieg absetzen.',
    ),
    source:
        'EFSA ANS Panel 2018: scientific opinion on the safety of green tea '
        'catechins.',
  ),
  InteractionRule(
    id: 'zinc-above-upper-level-copper',
    kind: InteractionKind.upperLimit,
    severity: InteractionSeverity.moderate,
    trigger: SubstanceTrigger(
      label: LocalizedText('Zinc', 'Zink'),
      substanceIds: {'zinc'},
      nameKeywords: ['zink*', 'zinc*'],
    ),
    thresholds: [
      DoseThreshold(25, CanonicalUnit.milligram, lookback: Duration(days: 90)),
    ],
    firesWhenDoseUnknown: false,
    affects: [
      AffectedTest(BiomarkerConcepts.copper, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.neutrophils, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.hemoglobin, EffectDirection.lowers),
    ],
    title: LocalizedText(
      'Zinc above the upper level can deplete copper',
      'Zink über der Höchstmenge kann Kupfer verdrängen',
    ),
    explanation: LocalizedText(
      'Long-term zinc above 25 mg a day (the EFSA upper level) blocks copper '
          'absorption; copper deficiency can cause anaemia and low '
          'neutrophils.',
      'Dauerhaft mehr als 25 mg Zink pro Tag (Höchstmenge der EFSA) hemmt die '
          'Kupferaufnahme; Kupfermangel kann Blutarmut und niedrige '
          'Neutrophile verursachen.',
    ),
    advice: LocalizedText(
      'Reduce to the upper level or below, or have copper and a blood count '
          'checked.',
      'Auf die Höchstmenge oder darunter reduzieren oder Kupfer und Blutbild '
          'kontrollieren lassen.',
    ),
    source:
        'EFSA tolerable upper intake level for zinc (25 mg/day), based on '
        'copper status.',
  ),
  InteractionRule(
    id: 'selenium-above-upper-level',
    kind: InteractionKind.upperLimit,
    severity: InteractionSeverity.moderate,
    trigger: SubstanceTrigger(
      label: LocalizedText('Selenium', 'Selen'),
      substanceIds: {'selenium'},
      nameKeywords: ['selen*'],
    ),
    thresholds: [
      DoseThreshold(255, CanonicalUnit.microgram, lookback: Duration(days: 90)),
    ],
    firesWhenDoseUnknown: false,
    affects: [AffectedTest(BiomarkerConcepts.selenium, EffectDirection.raises)],
    title: LocalizedText(
      'Selenium above the upper level',
      'Selen über der Höchstmenge',
    ),
    explanation: LocalizedText(
      'More than 255 µg of selenium a day exceeds the EFSA upper level; early '
          'signs of excess include hair loss and brittle nails.',
      'Mehr als 255 µg Selen pro Tag überschreiten die Höchstmenge der EFSA; '
          'frühe Zeichen eines Überschusses sind Haarausfall und brüchige '
          'Nägel.',
    ),
    advice: LocalizedText(
      'Reduce the dose, counting every product that contains selenium.',
      'Dosis reduzieren und dabei alle selenhaltigen Produkte '
          'zusammenrechnen.',
    ),
    source:
        'EFSA 2023 scientific opinion: tolerable upper intake level for '
        'selenium (255 µg/day).',
  ),
  InteractionRule(
    id: 'vitamin-b6-above-upper-level',
    kind: InteractionKind.upperLimit,
    severity: InteractionSeverity.moderate,
    trigger: SubstanceTrigger(
      label: LocalizedText('Vitamin B6', 'Vitamin B6'),
      substanceIds: {'vitamin-b6'},
      nameKeywords: ['pyridox*', 'vitamin b6', 'p5p'],
    ),
    thresholds: [
      DoseThreshold(12, CanonicalUnit.milligram, lookback: Duration(days: 90)),
    ],
    firesWhenDoseUnknown: false,
    affects: [
      AffectedTest(BiomarkerConcepts.vitaminB6, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Vitamin B6 above the upper level',
      'Vitamin B6 über der Höchstmenge',
    ),
    explanation: LocalizedText(
      'EFSA lowered the upper level to 12 mg a day in 2023 because long-term '
          'excess causes peripheral neuropathy (tingling, numbness).',
      'Die EFSA hat die Höchstmenge 2023 auf 12 mg pro Tag gesenkt, weil ein '
          'dauerhafter Überschuss periphere Neuropathien (Kribbeln, Taubheit) '
          'verursacht.',
    ),
    advice: LocalizedText(
      'Add up B6 across all products and reduce if above 12 mg a day; with '
          'tingling or numbness, have B6 (PLP) measured.',
      'B6 aus allen Produkten zusammenrechnen und über 12 mg pro Tag '
          'reduzieren; bei Kribbeln oder Taubheit B6 (PLP) messen lassen.',
    ),
    source:
        'EFSA 2023 scientific opinion: tolerable upper intake level for '
        'vitamin B6 (12 mg/day).',
  ),
  InteractionRule(
    id: 'turmeric-liver',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.low,
    trigger: SubstanceTrigger(
      label: LocalizedText('Turmeric / curcumin', 'Kurkuma / Curcumin'),
      substanceIds: {'curcumin', 'turmeric'},
      nameKeywords: ['curcum*', 'kurkum*', 'turmeric*'],
    ),
    lookback: Duration(days: 60),
    affects: [
      AffectedTest(BiomarkerConcepts.alt, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.ast, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.bilirubin, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Turmeric/curcumin: rare liver injury',
      'Kurkuma/Curcumin: seltene Leberschäden',
    ),
    explanation: LocalizedText(
      'Concentrated turmeric and curcumin products, especially '
          'high-bioavailability forms, have been linked to rare cases of liver '
          'injury.',
      'Konzentrierte Kurkuma- und Curcumin-Präparate, besonders solche mit '
          'erhöhter Bioverfügbarkeit, wurden mit seltenen Leberschäden in '
          'Verbindung gebracht.',
    ),
    advice: LocalizedText(
      'Mention it if liver values are raised.',
      'Bei erhöhten Leberwerten erwähnen.',
    ),
    source: 'LiverTox (NIH): Turmeric.',
  ),
  InteractionRule(
    id: 'thyroid-hormone-before-draw',
    kind: InteractionKind.preAnalytic,
    severity: InteractionSeverity.moderate,
    trigger: MedicationTrigger({'thyroid-hormone'}),
    lookback: Duration(hours: 6),
    affects: [AffectedTest(BiomarkerConcepts.ft4, EffectDirection.raises)],
    title: LocalizedText(
      'Thyroid tablet and the timing of thyroid tests',
      'Schilddrüsentablette und der Zeitpunkt von Schilddrüsenwerten',
    ),
    explanation: LocalizedText(
      'Free T4 peaks a few hours after a levothyroxine dose, so a sample drawn '
          'soon after the tablet can overstate it.',
      'Freies T4 erreicht einige Stunden nach der Levothyroxin-Einnahme seinen '
          'Höchstwert; eine Probe kurz nach der Tablette kann es zu hoch '
          'zeigen.',
    ),
    advice: LocalizedText(
      'On thyroid test days, take the tablet after the blood draw.',
      'An Tagen mit Schilddrüsenwerten die Tablette erst nach der '
          'Blutabnahme nehmen.',
    ),
    preparation: PreparationNote(
      LocalizedText(
        'Take the thyroid tablet after the draw.',
        'Schilddrüsentablette erst nach der Blutabnahme nehmen.',
      ),
      mentions: [
        'schilddrüsentablette*',
        'schilddrüsenhormon*',
        'thyroid tablet*',
        'levothyrox*',
        'l thyrox*',
        'thyroxin*',
        'euthyrox*',
      ],
    ),
    source:
        'Common laboratory practice: free T4 peaks roughly 2–4 h after an oral '
        'levothyroxine dose.',
  ),
  InteractionRule(
    id: 'minerals-reduce-thyroid-hormone-absorption',
    kind: InteractionKind.absorption,
    severity: InteractionSeverity.moderate,
    trigger: _minerals,
    partner: MedicationTrigger({'thyroid-hormone'}),
    minimumSpacing: Duration(hours: 4),
    affects: [
      AffectedTest(BiomarkerConcepts.tsh, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.ft4, EffectDirection.lowers),
    ],
    title: LocalizedText(
      'Minerals reduce thyroid hormone absorption',
      'Mineralstoffe vermindern die Aufnahme von Schilddrüsenhormon',
    ),
    explanation: LocalizedText(
      'Calcium, iron, magnesium and zinc bind levothyroxine in the gut. Taken '
          'too close together, less hormone is absorbed and TSH can rise.',
      'Calcium, Eisen, Magnesium und Zink binden Levothyroxin im Darm. Zu '
          'dicht zusammen eingenommen, wird weniger Hormon aufgenommen und das '
          'TSH kann steigen.',
    ),
    advice: LocalizedText(
      'Keep them at least 4 hours apart from the thyroid tablet; an '
          'unexplained TSH rise can come from this.',
      'Mindestens 4 Stunden Abstand zur Schilddrüsentablette halten; ein '
          'unerklärter TSH-Anstieg kann daher kommen.',
    ),
    source:
        'ATA 2014 guidelines for the treatment of hypothyroidism; '
        'levothyroxine product information.',
  ),
  InteractionRule(
    id: 'minerals-block-chelating-drugs',
    kind: InteractionKind.absorption,
    severity: InteractionSeverity.moderate,
    trigger: _minerals,
    partner: MedicationTrigger({'chelating-antibiotic', 'bisphosphonate'}),
    title: LocalizedText(
      'Minerals block some antibiotics and osteoporosis drugs',
      'Mineralstoffe blockieren manche Antibiotika und Osteoporose-Mittel',
    ),
    explanation: LocalizedText(
      'Calcium, iron, magnesium and zinc bind quinolone and tetracycline '
          'antibiotics and oral bisphosphonates, so much less of the drug is '
          'absorbed.',
      'Calcium, Eisen, Magnesium und Zink binden Chinolon- und '
          'Tetrazyklin-Antibiotika sowie orale Bisphosphonate, sodass viel '
          'weniger Wirkstoff aufgenommen wird.',
    ),
    advice: LocalizedText(
      'Follow the spacing in the package leaflet (typically 2–6 hours; '
          'bisphosphonates on an empty stomach, 30 minutes or more before '
          'anything else).',
      'Den Abstand laut Beipackzettel einhalten (meist 2–6 Stunden; '
          'Bisphosphonate nüchtern, mindestens 30 Minuten vor allem anderen).',
    ),
    source:
        'Product information for ciprofloxacin, doxycycline and alendronate.',
  ),
  InteractionRule(
    id: 'vitamin-k-vs-vitamin-k-antagonist',
    kind: InteractionKind.drugInteraction,
    severity: InteractionSeverity.high,
    trigger: SubstanceTrigger(
      label: LocalizedText('Vitamin K', 'Vitamin K'),
      substanceIds: {'vitamin-k1', 'vitamin-k2'},
      nameKeywords: [
        'vitamin k*',
        'phyllo*',
        'phytomenadion*',
        'menachinon*',
        'menaquinon*',
        'mk 7',
        'mk7',
      ],
    ),
    partner: MedicationTrigger({'vitamin-k-antagonist'}),
    affects: [AffectedTest(BiomarkerConcepts.inr, EffectDirection.lowers)],
    title: LocalizedText(
      'Vitamin K counteracts phenprocoumon/warfarin',
      'Vitamin K schwächt Phenprocoumon/Warfarin ab',
    ),
    explanation: LocalizedText(
      'Vitamin K from supplements (K1 or K2) directly opposes vitamin K '
          'antagonists; starting, stopping or changing the dose shifts the '
          'INR.',
      'Vitamin K aus Präparaten (K1 oder K2) wirkt Vitamin-K-Antagonisten '
          'direkt entgegen; Beginn, Absetzen oder Dosisänderung verschieben '
          'den INR.',
    ),
    advice: LocalizedText(
      'Do not change vitamin K intake without the doctor who manages your '
          'anticoagulation; keep it steady and have the INR checked after any '
          'change.',
      'Vitamin-K-Zufuhr nicht ohne die behandelnde Ärztin oder den '
          'behandelnden Arzt ändern; gleichmäßig halten und nach jeder '
          'Änderung den INR kontrollieren lassen.',
    ),
    source: 'Phenprocoumon and warfarin product information.',
  ),
  InteractionRule(
    id: 'st-johns-wort-enzyme-induction',
    kind: InteractionKind.drugInteraction,
    severity: InteractionSeverity.high,
    trigger: SubstanceTrigger(
      label: LocalizedText("St John's wort", 'Johanniskraut'),
      substanceIds: {'st-johns-wort'},
      nameKeywords: ['johanniskraut*', 'hypericum*', 'st john*'],
    ),
    partner: MedicationTrigger({
      'hormonal-contraceptive',
      'oral-estrogen',
      'immunosuppressant',
      'vitamin-k-antagonist',
      'doac',
      'cardiac-glycoside',
      'statin',
      'serotonergic',
    }),
    title: LocalizedText(
      "St John's wort weakens many medicines",
      'Johanniskraut schwächt viele Medikamente ab',
    ),
    explanation: LocalizedText(
      'It induces CYP3A4 and P-glycoprotein, lowering levels of '
          'contraceptives, immunosuppressants, anticoagulants, digoxin and '
          'some statins; with serotonergic drugs it can cause serotonin '
          'syndrome.',
      'Es induziert CYP3A4 und P-Glykoprotein und senkt so die Spiegel von '
          'Verhütungsmitteln, Immunsuppressiva, Gerinnungshemmern, Digoxin und '
          'manchen Statinen; mit serotonergen Mitteln kann ein '
          'Serotoninsyndrom entstehen.',
    ),
    advice: LocalizedText(
      'Do not combine without a doctor or pharmacist; contraception may be '
          'unreliable.',
      'Nicht ohne ärztliche oder pharmazeutische Rücksprache kombinieren; '
          'die Verhütung kann unzuverlässig sein.',
    ),
    source:
        'EMA/HMPC monograph on Hypericum perforatum; product information of '
        'the affected drugs.',
  ),
  InteractionRule(
    id: 'potassium-with-potassium-raising-drugs',
    kind: InteractionKind.drugInteraction,
    severity: InteractionSeverity.high,
    trigger: SubstanceTrigger(
      label: LocalizedText('Potassium', 'Kalium'),
      substanceIds: {'potassium'},
      nameKeywords: ['kalium*', 'potassium*'],
    ),
    partner: MedicationTrigger({'potassium-raising', 'trimethoprim'}),
    affects: [
      AffectedTest(BiomarkerConcepts.potassium, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Potassium supplements with potassium-retaining drugs',
      'Kaliumpräparate mit kaliumsparenden Medikamenten',
    ),
    explanation: LocalizedText(
      'ACE inhibitors, sartans, spironolactone and similar drugs retain '
          'potassium; extra potassium from supplements can push serum '
          'potassium to dangerous levels, particularly with reduced kidney '
          'function.',
      'ACE-Hemmer, Sartane, Spironolacton und ähnliche Mittel halten Kalium im '
          'Körper; zusätzliches Kalium aus Präparaten kann das Serum-Kalium '
          'gefährlich erhöhen, besonders bei eingeschränkter Nierenfunktion.',
    ),
    advice: LocalizedText(
      'Only with medical agreement and regular potassium checks.',
      'Nur nach ärztlicher Absprache und mit regelmäßigen Kaliumkontrollen.',
    ),
    source:
        'ACE inhibitor, sartan and spironolactone product information '
        '(hyperkalaemia with potassium supplements).',
  ),
  InteractionRule(
    id: 'bleeding-risk-with-blood-thinners',
    kind: InteractionKind.drugInteraction,
    severity: InteractionSeverity.low,
    trigger: SubstanceTrigger(
      label: LocalizedText(
        'Omega-3, ginkgo, vitamin E or curcumin',
        'Omega-3, Ginkgo, Vitamin E oder Curcumin',
      ),
      substanceIds: {
        'omega-3',
        'omega-3-epa',
        'omega-3-dha',
        'ginkgo',
        'vitamin-e',
        'curcumin',
        'turmeric',
      },
      nameKeywords: [
        'omega*',
        'fischöl*',
        'fish oil*',
        'krill*',
        'ginkgo*',
        'curcum*',
        'kurkum*',
        'turmeric*',
        'tocopher*',
      ],
    ),
    partner: _anticoagulants,
    title: LocalizedText(
      'Possible extra bleeding risk with blood thinners',
      'Mögliches zusätzliches Blutungsrisiko mit Blutverdünnern',
    ),
    explanation: LocalizedText(
      'High-dose omega-3, ginkgo, vitamin E and curcumin mildly inhibit '
          'platelets; combined with anticoagulants or antiplatelet drugs they '
          'may add to bleeding risk. The evidence is mixed.',
      'Hochdosiertes Omega-3, Ginkgo, Vitamin E und Curcumin hemmen die '
          'Blutplättchen leicht; zusammen mit Gerinnungs- oder '
          'Plättchenhemmern können sie das Blutungsrisiko erhöhen. Die '
          'Datenlage ist uneinheitlich.',
    ),
    advice: LocalizedText(
      'Tell whoever manages the blood thinner, especially before surgery or '
          'dental work.',
      'Die behandelnde Ärztin oder den behandelnden Arzt informieren, '
          'besonders vor Operationen oder Zahnbehandlungen.',
    ),
    source:
        'Anticoagulant product information; EMA/HMPC monograph on Ginkgo '
        'biloba.',
  ),
  InteractionRule(
    id: 'red-yeast-rice-with-statin',
    kind: InteractionKind.drugInteraction,
    severity: InteractionSeverity.high,
    trigger: _redYeastRice,
    partner: MedicationTrigger({'statin'}),
    affects: [
      AffectedTest(BiomarkerConcepts.ck, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.alt, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Red yeast rice on top of a statin',
      'Rotschimmelreis zusätzlich zum Statin',
    ),
    explanation: LocalizedText(
      'Monacolin K is lovastatin; combined with a prescribed statin it adds '
          'to the risk of muscle and liver side effects without being a '
          'controlled dose.',
      'Monacolin K ist Lovastatin; zusammen mit einem verordneten Statin '
          'erhöht es das Risiko für Muskel- und Lebernebenwirkungen, ohne '
          'kontrollierte Dosis.',
    ),
    advice: LocalizedText(
      'Do not combine; discuss it with the prescribing doctor.',
      'Nicht kombinieren; mit der verordnenden Ärztin oder dem verordnenden '
          'Arzt besprechen.',
    ),
    source:
        'EFSA 2018 scientific opinion on monacolins; statin product '
        'information.',
  ),
  InteractionRule(
    id: 'berberine-with-glucose-lowering-drugs',
    kind: InteractionKind.drugInteraction,
    severity: InteractionSeverity.moderate,
    trigger: _berberine,
    partner: MedicationTrigger({
      'metformin',
      'antidiabetic',
      'immunosuppressant',
    }),
    affects: [AffectedTest(BiomarkerConcepts.glucose, EffectDirection.lowers)],
    title: LocalizedText(
      'Berberine adds to glucose-lowering drugs',
      'Berberin verstärkt Blutzuckersenker',
    ),
    explanation: LocalizedText(
      'Berberine lowers glucose on its own and inhibits CYP3A4; with '
          'antidiabetic drugs hypoglycaemia becomes more likely, and '
          'ciclosporin levels can rise.',
      'Berberin senkt selbst den Blutzucker und hemmt CYP3A4; mit '
          'Antidiabetika werden Unterzuckerungen wahrscheinlicher, '
          'Ciclosporin-Spiegel können steigen.',
    ),
    advice: LocalizedText(
      'Agree it with the treating doctor and monitor glucose more closely.',
      'Mit der behandelnden Ärztin oder dem behandelnden Arzt abstimmen und '
          'den Blutzucker engmaschiger kontrollieren.',
    ),
    source:
        'Clinical pharmacology reviews of berberine (glucose lowering, CYP3A4 '
        'inhibition).',
  ),
  InteractionRule(
    id: 'coenzyme-q10-with-vitamin-k-antagonist',
    kind: InteractionKind.drugInteraction,
    severity: InteractionSeverity.low,
    trigger: SubstanceTrigger(
      label: LocalizedText('Coenzyme Q10', 'Coenzym Q10'),
      substanceIds: {'coenzyme-q10'},
      nameKeywords: ['coenzym*', 'coenzyme*', 'q10', 'ubiquin*'],
    ),
    partner: MedicationTrigger({'vitamin-k-antagonist'}),
    affects: [AffectedTest(BiomarkerConcepts.inr, EffectDirection.lowers)],
    title: LocalizedText(
      'Coenzyme Q10 may weaken phenprocoumon/warfarin',
      'Coenzym Q10 kann Phenprocoumon/Warfarin abschwächen',
    ),
    explanation: LocalizedText(
      'CoQ10 is structurally related to vitamin K; case reports describe a '
          'falling INR.',
      'CoQ10 ist strukturell mit Vitamin K verwandt; Fallberichte beschreiben '
          'einen sinkenden INR.',
    ),
    advice: LocalizedText(
      'Keep the dose steady and have the INR checked after starting or '
          'stopping.',
      'Dosis konstant halten und nach Beginn oder Absetzen den INR '
          'kontrollieren lassen.',
    ),
    source: 'Case reports of a reduced warfarin effect with coenzyme Q10.',
  ),
  InteractionRule(
    id: 'ashwagandha-with-thyroid-hormone',
    kind: InteractionKind.drugInteraction,
    severity: InteractionSeverity.moderate,
    trigger: _ashwagandha,
    partner: MedicationTrigger({'thyroid-hormone'}),
    affects: [
      AffectedTest(BiomarkerConcepts.tsh, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.ft4, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Ashwagandha on top of thyroid medication',
      'Ashwagandha zusätzlich zur Schilddrüsenmedikation',
    ),
    explanation: LocalizedText(
      'Ashwagandha can raise thyroid hormone levels; on top of levothyroxine '
          'this can tip into overtreatment.',
      'Ashwagandha kann Schilddrüsenhormone erhöhen; zusätzlich zu '
          'Levothyroxin kann das in eine Überdosierung kippen.',
    ),
    advice: LocalizedText(
      'Check TSH and free T4 after starting or stopping it.',
      'Nach Beginn oder Absetzen TSH und freies T4 kontrollieren.',
    ),
    source: 'Published case reports of ashwagandha-associated thyrotoxicosis.',
  ),
  InteractionRule(
    id: 'metformin-lowers-b12',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: MedicationTrigger({'metformin'}),
    affects: [
      AffectedTest(BiomarkerConcepts.vitaminB12, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.holoTc, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.mma, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.homocysteine, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Metformin lowers vitamin B12 over time',
      'Metformin senkt langfristig Vitamin B12',
    ),
    explanation: LocalizedText(
      'Long-term metformin reduces B12 absorption; a deficiency can develop '
          'over years.',
      'Langfristig vermindert Metformin die B12-Aufnahme; über Jahre kann ein '
          'Mangel entstehen.',
    ),
    advice: LocalizedText(
      'Have B12 status checked periodically, especially with neuropathy or '
          'anaemia.',
      'B12-Status regelmäßig prüfen lassen, besonders bei Neuropathie oder '
          'Blutarmut.',
    ),
    source:
        'ADA Standards of Care in Diabetes: periodic vitamin B12 measurement '
        'on long-term metformin.',
  ),
  InteractionRule(
    id: 'ppi-lowers-magnesium-and-b12',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: MedicationTrigger({'ppi'}),
    affects: [
      AffectedTest(BiomarkerConcepts.magnesium, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.vitaminB12, EffectDirection.lowers),
    ],
    title: LocalizedText(
      'Long-term acid blockers lower magnesium and B12',
      'Säureblocker senken langfristig Magnesium und B12',
    ),
    explanation: LocalizedText(
      'Proton pump inhibitors taken for months to years can cause low '
          'magnesium and reduce B12 absorption.',
      'Protonenpumpenhemmer über Monate bis Jahre können einen '
          'Magnesiummangel verursachen und die B12-Aufnahme vermindern.',
    ),
    advice: LocalizedText(
      'Check magnesium and B12 periodically on long-term use.',
      'Bei Dauereinnahme Magnesium und B12 regelmäßig kontrollieren.',
    ),
    source:
        'FDA Drug Safety Communication (2011): low magnesium with long-term '
        'PPI use.',
  ),
  InteractionRule(
    id: 'statin-ck-and-liver-enzymes',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.low,
    trigger: MedicationTrigger({'statin'}),
    affects: [
      AffectedTest(BiomarkerConcepts.ck, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.alt, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Statins can raise CK and liver enzymes',
      'Statine können CK und Leberwerte erhöhen',
    ),
    explanation: LocalizedText(
      'Statins occasionally raise CK (muscle) and ALT (liver); small increases '
          'are common, large ones rare but relevant.',
      'Statine erhöhen gelegentlich CK (Muskel) und ALT (Leber); leichte '
          'Anstiege sind häufig, starke selten, aber relevant.',
    ),
    advice: LocalizedText(
      'Read CK and ALT with the statin in mind; report unexplained muscle '
          'pain.',
      'CK und ALT mit Blick auf das Statin bewerten; unerklärte '
          'Muskelschmerzen melden.',
    ),
    source: 'Statin product information (CK and transaminase monitoring).',
  ),
  InteractionRule(
    id: 'oral-estrogen-binding-globulins',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: MedicationTrigger({'oral-estrogen'}),
    affects: [
      AffectedTest(BiomarkerConcepts.shbg, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.cortisol, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Oral estrogens raise binding proteins',
      'Orale Östrogene erhöhen Bindungsproteine',
    ),
    explanation: LocalizedText(
      'Oral estrogens, including the combined pill, raise SHBG, '
          'cortisol-binding globulin and thyroxine-binding globulin, so total '
          'hormone levels rise while free levels may not.',
      'Orale Östrogene, auch die kombinierte Pille, erhöhen SHBG, '
          'cortisolbindendes und thyroxinbindendes Globulin; Gesamthormonspiegel '
          'steigen, freie Spiegel oft nicht.',
    ),
    advice: LocalizedText(
      'Prefer free values (free testosterone, free T4) and read total '
          'cortisol with care.',
      'Freie Werte (freies Testosteron, freies T4) bevorzugen und '
          'Gesamt-Cortisol vorsichtig bewerten.',
    ),
    source:
        'Endocrinology references on estrogen effects on binding globulins.',
  ),
  InteractionRule(
    id: 'glucocorticoid-glucose-leukocytes-cortisol',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: MedicationTrigger({'glucocorticoid'}),
    affects: [
      AffectedTest(BiomarkerConcepts.glucose, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.leukocytes, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.cortisol, EffectDirection.unpredictable),
    ],
    title: LocalizedText(
      'Cortisone medication shifts several values',
      'Kortison verschiebt mehrere Werte',
    ),
    explanation: LocalizedText(
      'Systemic glucocorticoids raise blood glucose and white cell counts; '
          'prednisolone also cross-reacts with cortisol immunoassays while '
          'suppressing the body\'s own cortisol.',
      'Systemische Glukokortikoide erhöhen Blutzucker und Leukozyten; '
          'Prednisolon reagiert zudem in Cortisol-Immunoassays mit und '
          'unterdrückt gleichzeitig das körpereigene Cortisol.',
    ),
    advice: LocalizedText(
      'Give the dose and timing when glucose, blood count or cortisol are '
          'assessed.',
      'Bei Blutzucker, Blutbild oder Cortisol Dosis und Einnahmezeitpunkt '
          'angeben.',
    ),
    source:
        'Glucocorticoid product information; cortisol immunoassay package '
        'inserts (prednisolone cross-reactivity).',
  ),
  InteractionRule(
    id: 'diuretic-electrolytes-uric-acid',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: MedicationTrigger({'thiazide-or-loop-diuretic'}),
    affects: [
      AffectedTest(BiomarkerConcepts.potassium, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.sodium, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.uricAcid, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.glucose, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Diuretics shift electrolytes and uric acid',
      'Diuretika verschieben Elektrolyte und Harnsäure',
    ),
    explanation: LocalizedText(
      'Thiazide and loop diuretics can lower potassium and sodium and raise '
          'uric acid and blood glucose.',
      'Thiazid- und Schleifendiuretika können Kalium und Natrium senken sowie '
          'Harnsäure und Blutzucker erhöhen.',
    ),
    advice: LocalizedText(
      'Keep electrolytes, uric acid and glucose under review.',
      'Elektrolyte, Harnsäure und Blutzucker im Blick behalten.',
    ),
    source: 'Thiazide and loop diuretic product information.',
  ),
  InteractionRule(
    id: 'lithium-thyroid-calcium-kidney',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: MedicationTrigger({'lithium'}),
    affects: [
      AffectedTest(BiomarkerConcepts.tsh, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.calcium, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.creatinine, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Lithium affects thyroid, calcium and kidneys',
      'Lithium beeinflusst Schilddrüse, Calcium und Nieren',
    ),
    explanation: LocalizedText(
      'Lithium can cause hypothyroidism (rising TSH), raise calcium through '
          'the parathyroid glands and impair kidney function.',
      'Lithium kann eine Schilddrüsenunterfunktion (steigendes TSH) '
          'verursachen, über die Nebenschilddrüsen das Calcium erhöhen und die '
          'Nierenfunktion beeinträchtigen.',
    ),
    advice: LocalizedText(
      'Regular TSH, calcium and creatinine checks belong to lithium therapy.',
      'Regelmäßige Kontrollen von TSH, Calcium und Kreatinin gehören zur '
          'Lithiumtherapie.',
    ),
    source:
        'Lithium product information (thyroid, calcium and renal '
        'monitoring).',
  ),
  InteractionRule(
    id: 'amiodarone-thyroid-liver',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: MedicationTrigger({'amiodarone'}),
    affects: [
      AffectedTest(BiomarkerConcepts.tsh, EffectDirection.unpredictable),
      AffectedTest(BiomarkerConcepts.ft4, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.alt, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Amiodarone affects thyroid and liver',
      'Amiodaron beeinflusst Schilddrüse und Leber',
    ),
    explanation: LocalizedText(
      'Amiodarone contains large amounts of iodine and can cause both under- '
          'and overactive thyroid; it also raises liver enzymes.',
      'Amiodaron enthält viel Jod und kann sowohl eine Unter- als auch eine '
          'Überfunktion der Schilddrüse auslösen; außerdem erhöht es '
          'Leberwerte.',
    ),
    advice: LocalizedText(
      'TSH, free T4 and liver enzymes need regular monitoring.',
      'TSH, freies T4 und Leberwerte regelmäßig kontrollieren.',
    ),
    source: 'Amiodarone product information.',
  ),
  InteractionRule(
    id: 'testosterone-therapy-blood-count-psa',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.moderate,
    trigger: MedicationTrigger({'testosterone'}),
    affects: [
      AffectedTest(BiomarkerConcepts.hematocrit, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.hemoglobin, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.psa, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.estradiol, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.hdl, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.lh, EffectDirection.lowers),
      AffectedTest(BiomarkerConcepts.fsh, EffectDirection.lowers),
    ],
    title: LocalizedText(
      'Testosterone therapy shifts blood count and hormones',
      'Testosterontherapie verändert Blutbild und Hormone',
    ),
    explanation: LocalizedText(
      'Testosterone raises haematocrit and haemoglobin, can raise PSA and '
          'estradiol, lowers HDL and suppresses LH and FSH.',
      'Testosteron erhöht Hämatokrit und Hämoglobin, kann PSA und Östradiol '
          'erhöhen, senkt HDL und unterdrückt LH und FSH.',
    ),
    advice: LocalizedText(
      'Haematocrit and PSA are the standard safety checks on therapy.',
      'Hämatokrit und PSA sind die üblichen Sicherheitskontrollen unter '
          'Therapie.',
    ),
    source:
        'Endocrine Society 2018 clinical practice guideline on testosterone '
        'therapy.',
  ),
  InteractionRule(
    id: 'trimethoprim-creatinine-potassium',
    kind: InteractionKind.physiological,
    severity: InteractionSeverity.low,
    trigger: MedicationTrigger({'trimethoprim'}),
    affects: [
      AffectedTest(BiomarkerConcepts.creatinine, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.potassium, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Trimethoprim raises creatinine and potassium',
      'Trimethoprim erhöht Kreatinin und Kalium',
    ),
    explanation: LocalizedText(
      'It blocks tubular creatinine secretion — creatinine rises without a '
          'real loss of kidney function — and can raise potassium.',
      'Es hemmt die tubuläre Kreatinin-Sekretion – das Kreatinin steigt ohne '
          'echten Funktionsverlust – und kann Kalium erhöhen.',
    ),
    advice: LocalizedText(
      'Read creatinine and potassium measured during a course accordingly.',
      'Während einer Behandlung gemessenes Kreatinin und Kalium entsprechend '
          'bewerten.',
    ),
    source: 'Trimethoprim product information.',
  ),
  InteractionRule(
    id: 'strenuous-exercise-before-draw',
    kind: InteractionKind.preAnalytic,
    severity: InteractionSeverity.moderate,
    trigger: EventTrigger(
      label: LocalizedText('Strenuous exercise', 'Intensiver Sport'),
      keywords: [
        'sport*',
        'training*',
        'workout*',
        'krafttraining*',
        'kraftsport*',
        'laufen',
        'lauftraining*',
        'dauerlauf*',
        'joggen',
        'jogging',
        'running',
        'morning run',
        'marathon*',
        'halbmarathon*',
        'triathlon*',
        'radfahren',
        'rennrad*',
        'mountainbike*',
        'cycling',
        'gym',
        'fitness*',
        'hiit',
        'crossfit*',
        'intervalltraining*',
        'spinning',
        'fußball*',
        'football',
        'soccer',
        'tennis',
        'squash',
        'rudern',
        'rowing',
        'bouldern',
        'klettern',
        'climbing',
        'schwimmen',
        'swimming',
        'gewichtheben',
        'weightlifting',
        'bodybuilding',
        'wettkampf*',
      ],
    ),
    lookback: Duration(hours: 72),
    affects: [
      AffectedTest(BiomarkerConcepts.ck, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.ast, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.alt, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.ldh, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.myoglobin, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.creatinine, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.troponin, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Hard exercise before the draw',
      'Intensiver Sport vor der Blutabnahme',
    ),
    explanation: LocalizedText(
      'Strenuous exercise releases muscle enzymes: CK can rise many-fold for '
          'days, and AST, ALT, LDH, myoglobin and creatinine can rise too — '
          'mimicking a muscle or liver problem.',
      'Intensiver Sport setzt Muskelenzyme frei: CK kann für Tage um ein '
          'Vielfaches steigen, auch AST, ALT, LDH, Myoglobin und Kreatinin '
          'können ansteigen – und Muskel- oder Leberprobleme vortäuschen.',
    ),
    advice: LocalizedText(
      'Avoid strenuous exercise for 48–72 hours before such tests (longer '
          'after very heavy training), and repeat a raised value after rest.',
      '48–72 Stunden vor solchen Tests auf intensiven Sport verzichten (nach '
          'sehr hartem Training länger) und erhöhte Werte nach einer Pause '
          'wiederholen.',
    ),
    source:
        'Pre-analytical laboratory guidance on exercise before CK and '
        'transaminase testing.',
  ),
  InteractionRule(
    id: 'recent-illness-acute-phase',
    kind: InteractionKind.preAnalytic,
    severity: InteractionSeverity.moderate,
    trigger: EventTrigger(
      label: LocalizedText('Recent illness', 'Kürzliche Erkrankung'),
      keywords: [
        'erkältung*',
        'grippe*',
        'infekt*',
        'infektion*',
        'fieber*',
        'covid*',
        'corona*',
        'influenza',
        'common cold',
        'flu',
        'fever',
        'infection*',
        'bronchitis',
        'sinusitis',
        'nebenhöhlen*',
        'angina',
        'mandelentzündung',
        'tonsillitis',
        'magen darm*',
        'gastroenteritis',
        'blasenentzündung',
        'harnwegsinfekt*',
        'lungenentzündung',
        'pneumonie',
        'pneumonia',
        'husten',
        'cough',
        'halsschmerz*',
        'sore throat',
        'schnupfen',
        'laufnase',
      ],
    ),
    lookback: Duration(days: 14),
    affects: [
      AffectedTest(BiomarkerConcepts.crp, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.ferritin, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.leukocytes, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.serumIron, EffectDirection.lowers),
      AffectedTest(
        BiomarkerConcepts.transferrinSaturation,
        EffectDirection.lowers,
      ),
    ],
    title: LocalizedText(
      'Recent illness distorts inflammation and iron values',
      'Kürzliche Erkrankung verfälscht Entzündungs- und Eisenwerte',
    ),
    explanation: LocalizedText(
      'During and after an infection CRP, white cells and ferritin rise '
          '(ferritin is an acute-phase protein) while serum iron and '
          'transferrin saturation fall.',
      'Während und nach einem Infekt steigen CRP, Leukozyten und Ferritin '
          '(ein Akute-Phase-Protein), während Serumeisen und '
          'Transferrinsättigung sinken.',
    ),
    advice: LocalizedText(
      'Where possible test at least two weeks after recovery, and read '
          'ferritin together with CRP.',
      'Wenn möglich frühestens zwei Wochen nach Genesung testen und Ferritin '
          'immer zusammen mit CRP bewerten.',
    ),
    source:
        'WHO 2020 guideline on ferritin (acute-phase effect); standard '
        'pre-analytical guidance.',
  ),
  InteractionRule(
    id: 'alcohol-before-draw',
    kind: InteractionKind.preAnalytic,
    severity: InteractionSeverity.low,
    trigger: EventTrigger(
      label: LocalizedText('Alcohol', 'Alkohol'),
      keywords: [
        'alkohol*',
        'alcohol*',
        'bier*',
        'beer',
        'wein',
        'rotwein',
        'weißwein',
        'weinschorle',
        'wine',
        'sekt',
        'cocktail*',
        'schnaps',
        'kater',
        'hangover',
      ],
    ),
    lookback: Duration(hours: 72),
    affects: [
      AffectedTest(BiomarkerConcepts.triglycerides, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.ggt, EffectDirection.raises),
      AffectedTest(BiomarkerConcepts.uricAcid, EffectDirection.raises),
    ],
    title: LocalizedText(
      'Alcohol before the draw',
      'Alkohol vor der Blutabnahme',
    ),
    explanation: LocalizedText(
      'Alcohol in the days before a test can raise triglycerides, GGT and '
          'uric acid.',
      'Alkohol in den Tagen vor einem Test kann Triglyceride, Gamma-GT und '
          'Harnsäure erhöhen.',
    ),
    advice: LocalizedText(
      'Avoid alcohol for at least a day, better three, before lipid, liver or '
          'uric acid tests.',
      'Mindestens einen Tag, besser drei, vor Lipid-, Leber- oder '
          'Harnsäuretests auf Alkohol verzichten.',
    ),
    source: 'Standard pre-analytical guidance for lipid and liver tests.',
  ),
];

/// Every medication class referenced by a rule, for validating the table.
Set<String> referencedMedicationClasses() => {
  for (final rule in interactionRules)
    for (final trigger in [rule.trigger, rule.partner])
      if (trigger is MedicationTrigger) ...trigger.classIds,
};

/// Every medication class the catalog defines.
Set<String> knownMedicationClasses() => {
  for (final item in MedicationCatalog.classes) item.id,
};
