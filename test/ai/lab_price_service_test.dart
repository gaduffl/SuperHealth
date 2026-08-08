import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/lab_price_service.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  final createdAt = DateTime(2026, 1, 1);
  Biomarker marker(
    String id, {
    double? price,
    String? lab,
    String name = 'Marker',
  }) => Biomarker(
    id: id,
    canonicalName: id,
    displayName: name,
    priceEur: price,
    labName: lab,
    createdAt: createdAt,
    updatedAt: createdAt,
  );

  String responseFor(
    List<Map<String, Object?>> prices, {
    List<Map<String, Object?>> packagePrices = const [],
  }) => jsonEncode({'prices': prices, 'package_prices': packagePrices});

  group('proposal classification', () {
    test('a sourced euro price close to the stored one is confident', () {
      final set = LabPriceService.parseResponse(
        responseFor([
          {
            'biomarker_id': 'ferritin',
            'price_eur': 21.5,
            'currency': 'EUR',
            'lab_name': 'Labor A',
            'quote': 'Ferritin ..... 21,50 €',
          },
        ]),
        catalog: [marker('ferritin', price: 20, lab: 'Labor A')],
      );
      expect(set.confident, hasLength(1));
      expect(set.needsReview, isEmpty);
      expect(set.confident.single.oldPriceEur, 20);
      expect(set.confident.single.newPriceEur, 21.5);
    });

    test('a price with no quoted line is never pre-ticked', () {
      // Nothing distinguishes a figure the model read from one it produced,
      // and the lab planner spends real money off these numbers.
      final set = LabPriceService.parseResponse(
        responseFor([
          {
            'biomarker_id': 'ferritin',
            'price_eur': 21.5,
            'currency': 'EUR',
            'lab_name': 'Labor A',
            'quote': '',
          },
        ]),
        catalog: [marker('ferritin', price: 20, lab: 'Labor A')],
      );
      expect(set.confident, isEmpty);
      expect(
        set.needsReview.single.reviewReasons,
        contains(LabPriceReviewReason.unsourced),
      );
    });

    test('another currency is surfaced, never converted', () {
      final set = LabPriceService.parseResponse(
        responseFor([
          {
            'biomarker_id': 'ferritin',
            'price_eur': 24,
            'currency': 'CHF',
            'lab_name': 'Labor A',
            'quote': 'Ferritin CHF 24.00',
          },
        ]),
        catalog: [marker('ferritin', price: 20, lab: 'Labor A')],
      );
      final proposal = set.needsReview.single;
      expect(
        proposal.reviewReasons,
        contains(LabPriceReviewReason.foreignCurrency),
      );
      // The figure is carried through untouched: an invented exchange rate
      // would be a second guess stacked on the first.
      expect(proposal.newPriceEur, 24);
      expect(proposal.currency, 'CHF');
    });

    test('a large move needs a look in both directions', () {
      final set = LabPriceService.parseResponse(
        responseFor([
          // A misplaced decimal is the classic version of this.
          {
            'biomarker_id': 'up',
            'price_eur': 200,
            'currency': 'EUR',
            'lab_name': '',
            'quote': 'x',
          },
          {
            'biomarker_id': 'down',
            'price_eur': 2,
            'currency': 'EUR',
            'lab_name': '',
            'quote': 'x',
          },
          {
            'biomarker_id': 'near',
            'price_eur': 22,
            'currency': 'EUR',
            'lab_name': '',
            'quote': 'x',
          },
        ]),
        catalog: [
          marker('up', price: 20, name: 'Up'),
          marker('down', price: 20, name: 'Down'),
          marker('near', price: 20, name: 'Near'),
        ],
      );
      expect(set.needsReview.map((item) => item.targetId).toSet(), {
        'up',
        'down',
      });
      expect(set.confident.single.targetId, 'near');
    });

    test('filling an empty price is offered but never pre-ticked', () {
      // Gap-filling is the point of the feature and also where the model has
      // least to check itself against — nothing stored contradicts it.
      final set = LabPriceService.parseResponse(
        responseFor([
          {
            'biomarker_id': 'new',
            'price_eur': 18,
            'currency': 'EUR',
            'lab_name': 'Labor A',
            'quote': 'Neu 18,00 €',
          },
        ]),
        catalog: [marker('new')],
      );
      expect(set.confident, isEmpty);
      expect(
        set.needsReview.single.reviewReasons,
        contains(LabPriceReviewReason.firstPrice),
      );
    });

    test('a lab that disagrees with the stored one is flagged', () {
      final set = LabPriceService.parseResponse(
        responseFor([
          {
            'biomarker_id': 'ferritin',
            'price_eur': 21,
            'currency': 'EUR',
            'lab_name': 'Labor B',
            'quote': 'Ferritin 21,00 €',
          },
        ]),
        catalog: [marker('ferritin', price: 20, lab: 'Labor A')],
      );
      expect(
        set.needsReview.single.reviewReasons,
        contains(LabPriceReviewReason.conflictingLab),
      );
    });
  });

  group('what is refused outright', () {
    test('a biomarker outside the catalog is dropped, not created', () {
      // Inventing a marker to hang a price on is worse than having no price.
      final set = LabPriceService.parseResponse(
        responseFor([
          {
            'biomarker_id': 'not-in-catalog',
            'price_eur': 30,
            'currency': 'EUR',
            'lab_name': '',
            'quote': 'x',
          },
        ]),
        catalog: [marker('ferritin', price: 20)],
      );
      expect(set.proposals, isEmpty);
      expect(set.unknownTargetIds, ['not-in-catalog']);
    });

    test('a nonsense price is skipped rather than stored', () {
      final set = LabPriceService.parseResponse(
        responseFor([
          for (final value in [0, -5, 'abc'])
            {
              'biomarker_id': 'ferritin',
              'price_eur': value,
              'currency': 'EUR',
              'lab_name': '',
              'quote': 'x',
            },
        ]),
        catalog: [marker('ferritin', price: 20)],
      );
      expect(set.proposals, isEmpty);
    });

    test('a comma decimal is read as a number, not discarded', () {
      // German price lists write 21,50 — refusing them would refuse the
      // common case this feature exists for.
      final set = LabPriceService.parseResponse(
        responseFor([
          {
            'biomarker_id': 'ferritin',
            'price_eur': '21,50',
            'currency': 'EUR',
            'lab_name': '',
            'quote': 'Ferritin 21,50 €',
          },
        ]),
        catalog: [marker('ferritin', price: 20)],
      );
      expect(set.proposals.single.newPriceEur, closeTo(21.5, 1e-9));
    });

    test('a non-JSON reply fails loudly', () {
      expect(
        () => LabPriceService.parseResponse(
          'I could not find a price list.',
          catalog: [marker('ferritin')],
        ),
        throwsA(isA<LabPriceException>()),
      );
    });
  });

  group('reading a price page', () {
    test('markup becomes lines a price list can be read from', () {
      const html = '''
        <html><head><style>.a{color:red}</style>
        <script>var x = "Ferritin 999";</script></head>
        <body><table>
        <tr><td>Ferritin</td><td>21,50&nbsp;&euro;</td></tr>
        <tr><td>Vitamin D</td><td>28,00 &euro;</td></tr>
        </table></body></html>''';
      final text = LabPriceService.htmlToText(html);
      // Script and style bodies are the bulk of a page and none of it is
      // price data — worse, this one contains a decoy figure.
      expect(text, isNot(contains('999')));
      expect(text, isNot(contains('color:red')));
      // Rows stay on their own lines, which is what makes a table readable.
      expect(text, contains('Ferritin\t21,50 €'));
      expect(text, contains('Vitamin D\t28,00 €'));
      expect(text.split('\n').length, 2);
    });

    test('an oversized page is capped rather than sent whole', () {
      final huge = List.filled(20000, '<p>Ferritin 21,50 EUR</p>').join();
      expect(
        LabPriceService.htmlToText(huge).length,
        LabPriceService.maxSourceCharacters,
      );
    });
  });

  group('a stored zero is an absent price', () {
    test('a zero counts as no price, so it is offered as a first price', () {
      // A legacy import writes 0 where its source had no price. Treating that
      // as a real price made a 169-marker catalog report itself fully priced
      // and left every one of them unofferable.
      final set = LabPriceService.parseResponse(
        responseFor([
          {
            'biomarker_id': 'ferritin',
            'price_eur': 21,
            'currency': 'EUR',
            'lab_name': '',
            'quote': 'Ferritin 21,00 €',
          },
        ]),
        catalog: [marker('ferritin', price: 0)],
      );
      expect(
        set.needsReview.single.reviewReasons,
        contains(LabPriceReviewReason.firstPrice),
      );
      // And it must not be compared against as if it were a real figure: every
      // price is an infinite increase over zero.
      expect(
        set.needsReview.single.reviewReasons,
        isNot(contains(LabPriceReviewReason.largeChange)),
      );
    });

    test('hasLabPrice draws the line in one place', () {
      expect(hasLabPrice(null), isFalse);
      expect(hasLabPrice(0), isFalse);
      // A lab test that costs nothing does not exist.
      expect(hasLabPrice(-1), isFalse);
      expect(hasLabPrice(0.01), isTrue);
    });
  });

  group('packages are priced as bundles', () {
    BiomarkerPackage bundle(String id, {double? price, String? lab}) =>
        BiomarkerPackage(
          id: id,
          name: 'Kleines Blutbild',
          priceEur: price,
          labName: lab,
          createdAt: createdAt,
          updatedAt: createdAt,
        );

    test('a bundle price becomes a package proposal, not a biomarker one', () {
      final set = LabPriceService.parseResponse(
        responseFor(
          [],
          packagePrices: [
            {
              'package_id': 'blutbild',
              'price_eur': 15,
              'currency': 'EUR',
              'lab_name': 'Labor A',
              'quote': 'Kleines Blutbild 15,00 €',
            },
          ],
        ),
        catalog: [marker('hb', price: 8)],
        packages: [bundle('blutbild', price: 14, lab: 'Labor A')],
      );
      final proposal = set.proposals.single;
      expect(proposal.isPackage, isTrue);
      expect(proposal.targetId, 'blutbild');
      expect(proposal.newPriceEur, 15);
      // Sourced, in euros, close to the stored bundle price.
      expect(set.confident, hasLength(1));
    });

    test('a package is held to the same review rules as a biomarker', () {
      final set = LabPriceService.parseResponse(
        responseFor(
          [],
          packagePrices: [
            {
              'package_id': 'blutbild',
              'price_eur': 15,
              'currency': 'EUR',
              'lab_name': '',
              'quote': '',
            },
          ],
        ),
        catalog: const [],
        packages: [bundle('blutbild')],
      );
      expect(set.needsReview.single.reviewReasons, {
        LabPriceReviewReason.unsourced,
        LabPriceReviewReason.firstPrice,
      });
    });

    test('a package outside the catalog is dropped, not created', () {
      final set = LabPriceService.parseResponse(
        responseFor(
          [],
          packagePrices: [
            {
              'package_id': 'not-mine',
              'price_eur': 15,
              'currency': 'EUR',
              'lab_name': '',
              'quote': 'x',
            },
          ],
        ),
        catalog: const [],
        packages: [bundle('blutbild')],
      );
      expect(set.proposals, isEmpty);
      expect(set.unknownTargetIds, ['not-mine']);
    });

    test('the catalog names a package by its members, not only its name', () {
      // A lab calls the same bundle something else, so the model needs the
      // tests inside it to recognise a match on a price list.
      final json = LabPriceService.catalogJson(
        [marker('hb', name: 'Haemoglobin')],
        packages: [bundle('blutbild')],
        packageMembers: {
          'blutbild': {'hb'},
        },
      );
      expect(json, contains('"contains":["Haemoglobin"]'));
    });
  });
}
