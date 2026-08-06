import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/domain/substance_catalog.dart';
import 'package:super_health/domain/substance_conversions.dart';
import 'package:super_health/domain/units.dart';

void main() {
  group('unit vocabulary', () {
    test('the spellings found in a real library all resolve', () {
      // Every distinct supplement-side unit from a real export.
      expect(CanonicalUnit.tryParse('mg'), CanonicalUnit.milligram);
      expect(CanonicalUnit.tryParse('µg'), CanonicalUnit.microgram);
      expect(CanonicalUnit.tryParse('microgram'), CanonicalUnit.microgram);
      expect(CanonicalUnit.tryParse('g'), CanonicalUnit.gram);
      expect(CanonicalUnit.tryParse('unit'), CanonicalUnit.piece);
      expect(CanonicalUnit.tryParse('Capsule'), CanonicalUnit.capsule);
      // "IE" is Internationale Einheiten, written throughout a German library.
      expect(CanonicalUnit.tryParse('IE'), CanonicalUnit.internationalUnit);
      expect(
        CanonicalUnit.tryParse('µg RE'),
        CanonicalUnit.microgramRetinolEquivalent,
      );
      expect(
        CanonicalUnit.tryParse('mg α-TE'),
        CanonicalUnit.milligramAlphaTocopherolEquivalent,
      );
    });

    test('dosage forms are rejected, because they are not units', () {
      // These sit in supplements.stock_unit today. "How many Powder" has no
      // answer, so they must not resolve to something summable.
      expect(CanonicalUnit.tryParse('Powder'), isNull);
      expect(CanonicalUnit.tryParse('Liquid'), isNull);
      expect(CanonicalUnit.isKnown('Powder'), isFalse);
    });

    test('presentation differences fold, real differences do not', () {
      // Greek capital Mu is visually a Latin M, so it must fold to micro
      // before casing does — otherwise "ΜG" silently becomes mg, a
      // thousandfold error.
      expect(CanonicalUnit.tryParse(' ΜG '), CanonicalUnit.microgram);
      expect(CanonicalUnit.tryParse('MG'), CanonicalUnit.milligram);
      expect(CanonicalUnit.tryParse('µg'), CanonicalUnit.microgram);
      expect(CanonicalUnit.tryParse('μg'), CanonicalUnit.microgram);
      // mg and µg are a thousandfold apart and must never fold together.
      expect(CanonicalUnit.tryParse('mg'), isNot(CanonicalUnit.tryParse('µg')));
    });

    test('an unknown unit returns null rather than a nearest guess', () {
      expect(CanonicalUnit.tryParse('bananas'), isNull);
      expect(CanonicalUnit.tryParse(''), isNull);
      expect(CanonicalUnit.tryParse(null), isNull);
      // normalize leaves it alone rather than coercing it.
      expect(CanonicalUnit.normalize('bananas'), 'bananas');
    });

    test('units are only commensurable inside one domain', () {
      expect(
        CanonicalUnit.milligram.commensurableWith(CanonicalUnit.gram),
        isTrue,
      );
      expect(
        CanonicalUnit.milligram.commensurableWith(CanonicalUnit.capsule),
        isFalse,
      );
      // IU is its own domain precisely because no generic mass factor exists.
      expect(
        CanonicalUnit.internationalUnit.commensurableWith(
          CanonicalUnit.microgram,
        ),
        isFalse,
      );
      // Equivalents carry no linear factor at all.
      expect(
        CanonicalUnit.microgramRetinolEquivalent.commensurableWith(
          CanonicalUnit.microgram,
        ),
        isFalse,
      );
    });

    test('within-domain conversion is exact', () {
      expect(
        convertWithinDomain(
          1000,
          CanonicalUnit.microgram,
          CanonicalUnit.milligram,
        ),
        closeTo(1, 1e-12),
      );
      expect(
        convertWithinDomain(2.5, CanonicalUnit.gram, CanonicalUnit.milligram),
        closeTo(2500, 1e-9),
      );
      expect(
        convertWithinDomain(1, CanonicalUnit.gram, CanonicalUnit.capsule),
        isNull,
      );
    });
  });

  group('substance identity', () {
    const catalog = SubstanceCatalog();

    test('the collisions found in a real library merge', () {
      String? id(String name) => catalog.idFor(name);
      expect(id('Vitamin C'), id('Vitamin c'));
      expect(id('B12'), id('Vitamin B12'));
      expect(id('Vitamin K2'), id('Vitamin K2 MK7'));
      expect(id('Levothyroxin-Natrium'), id('Levothyroxin natrium'));
      expect(id('Creatine'), id('creatine'));
      expect(id('Eisen'), id('Eisen(II)-Ion'));
      // A trailing parenthetical names the form, not another substance.
      expect(id('Coenzym Q10'), id('Coenzym Q10 (Ubiquinol)'));
    });

    test('a named salt keeps its own identity', () {
      // Its mass includes the counter-ion, so it is not interchangeable with
      // elemental iron and must not be summed with it.
      expect(catalog.idFor('Eisen(II)-sulfat, getrocknetes'), isNull);
      expect(
        catalog.groupingKeyFor('Eisen(II)-sulfat, getrocknetes'),
        isNot(catalog.groupingKeyFor('Eisen')),
      );
    });

    test('different substances never merge', () {
      expect(catalog.idFor('Vitamin B12'), isNot(catalog.idFor('Vitamin B6')));
      expect(catalog.idFor('Vitamin D3'), isNot(catalog.idFor('Vitamin E')));
      expect(catalog.idFor('Calcium'), isNot(catalog.idFor('Magnesium')));
    });

    test('an unknown substance still groups stably by its own name', () {
      final key = catalog.groupingKeyFor('Wilde-Heidelbeeren-Fruchtpulver');
      expect(key, catalog.groupingKeyFor('wilde heidelbeeren fruchtpulver'));
      expect(key, isNot(catalog.groupingKeyFor('Brokkoli-Blütenpulver')));
      // And it keeps the name the user typed.
      expect(catalog.displayNameFor('Astaxanthin'), 'Astaxanthin');
    });
  });

  group('substance-scoped conversion', () {
    const conversions = SubstanceConversions();

    test('vitamin D converts between IU and micrograms', () {
      // The standard equivalence: 1 µg cholecalciferol = 40 IU.
      expect(
        conversions.convert(
          amount: 1000,
          from: CanonicalUnit.internationalUnit,
          to: CanonicalUnit.microgram,
          substanceId: 'vitamin-d',
        ),
        closeTo(25, 1e-9),
      );
      expect(
        conversions.convert(
          amount: 25,
          from: CanonicalUnit.microgram,
          to: CanonicalUnit.internationalUnit,
          substanceId: 'vitamin-d',
        ),
        closeTo(1000, 1e-9),
      );
    });

    test('the same IU means different masses for different substances', () {
      double? asMicrograms(String substance) => conversions.convert(
        amount: 1000,
        from: CanonicalUnit.internationalUnit,
        to: CanonicalUnit.microgram,
        substanceId: substance,
      );
      // This is exactly why a generic IU factor cannot exist.
      expect(asMicrograms('vitamin-d'), closeTo(25, 1e-9));
      expect(asMicrograms('vitamin-a'), closeTo(300, 1e-6));
      expect(asMicrograms('vitamin-d'), isNot(closeTo(300, 1)));
    });

    test('vitamin E uses the milligram convention of its label', () {
      // 1 IU natural α-tocopherol = 0.67 mg.
      expect(
        conversions.convert(
          amount: 100,
          from: CanonicalUnit.internationalUnit,
          to: CanonicalUnit.milligram,
          substanceId: 'vitamin-e',
        ),
        closeTo(67, 1e-6),
      );
    });

    test('an unknown substance refuses rather than guessing', () {
      expect(
        conversions.convert(
          amount: 1000,
          from: CanonicalUnit.internationalUnit,
          to: CanonicalUnit.microgram,
          substanceId: 'astaxanthin',
        ),
        isNull,
      );
      expect(
        conversions.convert(
          amount: 1000,
          from: CanonicalUnit.internationalUnit,
          to: CanonicalUnit.microgram,
          substanceId: null,
        ),
        isNull,
      );
      expect(conversions.supports('vitamin-b12'), isFalse);
    });

    test('a plain within-domain conversion works without a substance', () {
      expect(
        conversions.convert(
          amount: 1000,
          from: CanonicalUnit.microgram,
          to: CanonicalUnit.milligram,
        ),
        closeTo(1, 1e-12),
      );
    });

    test('counts never convert into mass', () {
      expect(
        conversions.convert(
          amount: 2,
          from: CanonicalUnit.capsule,
          to: CanonicalUnit.milligram,
          substanceId: 'vitamin-d',
        ),
        isNull,
      );
    });
  });
}
