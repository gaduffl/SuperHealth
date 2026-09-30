import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/domain/biomarker_concepts.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/domain/interaction_rules.dart';
import 'package:super_health/domain/localized_text.dart';
import 'package:super_health/domain/medication_catalog.dart';
import 'package:super_health/domain/name_matching.dart';
import 'package:super_health/domain/substance_catalog.dart';

Biomarker _marker(String id, String name, {List<String> synonyms = const []}) {
  final now = DateTime.utc(2026, 1, 1);
  return Biomarker(
    id: id,
    canonicalName: name,
    displayName: name,
    synonyms: synonyms,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('the curated table', () {
    test('every rule id is unique and stable-looking', () {
      final ids = [for (final rule in interactionRules) rule.id];
      expect(ids.toSet(), hasLength(ids.length));
      for (final id in ids) {
        expect(id, matches(RegExp(r'^[a-z0-9]+(-[a-z0-9]+)*$')));
      }
    });

    test('every rule is written in both languages and names its source', () {
      for (final rule in interactionRules) {
        for (final text in [rule.title, rule.explanation, rule.advice]) {
          expect(text.en.trim(), isNotEmpty, reason: rule.id);
          expect(text.de.trim(), isNotEmpty, reason: rule.id);
          expect(text.en, isNot(text.de), reason: '${rule.id} is untranslated');
        }
        expect(rule.source.trim(), isNotEmpty, reason: rule.id);
      }
    });

    test('rules only refer to medication classes the catalog defines', () {
      expect(
        referencedMedicationClasses().difference(knownMedicationClasses()),
        isEmpty,
      );
    });

    test('thresholds ascend and share one unit per rule', () {
      for (final rule in interactionRules) {
        for (var i = 1; i < rule.thresholds.length; i++) {
          expect(
            rule.thresholds[i].amount,
            greaterThan(rule.thresholds[i - 1].amount),
            reason: rule.id,
          );
          expect(
            rule.thresholds[i].unit,
            rule.thresholds.first.unit,
            reason: rule.id,
          );
        }
      }
    });

    test('a rule checked against past draws names the tests it affects', () {
      for (final rule in interactionRules) {
        final retrospective =
            rule.partner == null &&
            (rule.lookback != null || rule.thresholds.isNotEmpty);
        if (retrospective) {
          expect(rule.affects, isNotEmpty, reason: rule.id);
        }
      }
    });

    test('substance ids named by rules exist in the substance catalog', () {
      const catalog = SubstanceCatalog();
      for (final rule in interactionRules) {
        for (final trigger in [rule.trigger, rule.partner]) {
          if (trigger is! SubstanceTrigger) continue;
          for (final id in {
            ...trigger.substanceIds,
            ...trigger.massFactors.keys,
          }) {
            expect(catalog.byId(id), isNotNull, reason: '${rule.id}: $id');
          }
        }
      }
    });
  });

  group('substance identity', () {
    const catalog = SubstanceCatalog();

    test('no synonym is claimed by two substances', () {
      for (final substance in SubstanceCatalog.substances) {
        for (final name in [substance.displayName, ...substance.synonyms]) {
          expect(catalog.idFor(name), substance.id, reason: name);
        }
      }
    });

    test('biotin spellings merge and a salt of iron stays a family match', () {
      expect(catalog.idFor('Biotin (D-Biotin)'), 'biotin');
      expect(catalog.idFor('Vitamin B7'), 'biotin');
      const iron = SubstanceTrigger(
        label: LocalizedText('Iron', 'Eisen'),
        substanceIds: {'iron'},
        nameKeywords: ['eisen*'],
      );
      expect(iron.match('Eisen')!.doseComparable, isTrue);
      final salt = iron.match('Eisen(II)-fumarat');
      expect(salt, isNotNull);
      expect(salt!.doseComparable, isFalse);
    });

    test('niacin, nicotinic acid and nicotinamide stay three identities', () {
      expect({
        catalog.idFor('Niacin'),
        catalog.idFor('Nicotinsäure'),
        catalog.idFor('Niacinamide'),
      }, hasLength(3));
    });
  });

  group('biomarker concepts', () {
    test('match the spellings lab reports use', () {
      expect(
        BiomarkerConcepts.tsh.matches(_marker('x1', 'TSH basal (3. Gen.)')),
        isTrue,
      );
      expect(BiomarkerConcepts.tsh.matches(_marker('tsh', 'Anything')), isTrue);
      expect(BiomarkerConcepts.ft4.matches(_marker('x2', 'freies T4')), isTrue);
      expect(
        BiomarkerConcepts.ferritin.matches(_marker('x3', 'Ferritin (S)')),
        isTrue,
      );
      expect(
        BiomarkerConcepts.creatinine.matches(
          _marker('x4', 'Something', synonyms: ['Kreatinin']),
        ),
        isTrue,
      );
    });

    test('TSH receptor antibodies are not TSH', () {
      final trak = _marker('x5', 'TSH-Rezeptor-Antikörper');
      expect(BiomarkerConcepts.tsh.matches(trak), isFalse);
      expect(BiomarkerConcepts.trak.matches(trak), isTrue);
    });
  });

  group('medication names', () {
    const catalog = MedicationCatalog();

    test('recognise a class inside brand, strength and combinations', () {
      expect(catalog.classIdsFor('L-Thyroxin Henning 75 µg'), {
        'thyroid-hormone',
      });
      expect(
        catalog.classIdsFor('Ramipril/HCT 5/25 mg'),
        containsAll(['potassium-raising', 'thiazide-or-loop-diuretic']),
      );
      expect(catalog.classIdsFor('ASS 100'), {'antiplatelet'});
    });

    test('match whole words only', () {
      expect(catalog.classIdsFor('Massage'), isEmpty);
      expect(catalog.classIdsFor('Klassische Homöopathie'), isEmpty);
    });
  });

  group('event keywords', () {
    final exercise =
        interactionRules
                .singleWhere(
                  (rule) => rule.id == 'strenuous-exercise-before-draw',
                )
                .trigger
            as EventTrigger;
    final alcohol =
        interactionRules
                .singleWhere((rule) => rule.id == 'alcohol-before-draw')
                .trigger
            as EventTrigger;

    test('a runny nose is not a run and crying is not wine', () {
      expect(exercise.matchesName('Laufnase'), isFalse);
      expect(exercise.matchesName('Krafttraining Beine'), isTrue);
      expect(exercise.matchesName('Laufen'), isTrue);
      expect(alcohol.matchesName('Weinen'), isFalse);
      expect(alcohol.matchesName('Rotwein'), isTrue);
    });

    test('prefix and whole-word keywords behave as documented', () {
      expect(matchesKeyword('Eisenbisglycinat', 'eisen*'), isTrue);
      expect(matchesKeyword('Reiseisen', 'eisen*'), isFalse);
      expect(matchesKeyword('Weinschorle', 'wein'), isFalse);
    });
  });
}
