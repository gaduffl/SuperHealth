import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/analysis/supplement_insights.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  const insights = SupplementInsights();
  final day = DateTime(2026, 5, 1);

  Supplement supplement(String id, List<Map<String, Object?>> ingredients) =>
      Supplement(
        id: id,
        name: id,
        ingredients: ingredients,
        createdAt: day,
        updatedAt: day,
      );

  SupplementIntake intake(
    String id,
    String supplementId, {
    List<Map<String, Object?>> snapshot = const [],
    double dose = 1,
  }) => SupplementIntake(
    id: id,
    profileId: 'p',
    supplementId: supplementId,
    takenAt: day,
    dose: dose,
    unit: 'capsule',
    ingredientSnapshot: snapshot,
    createdAt: day,
    updatedAt: day,
  );

  test('an intake with no snapshot still contributes its exposure', () {
    // 94% of intakes in a real library look exactly like this: logged before
    // the product had its ingredients entered, so the snapshot stayed empty
    // and the exposure total was computed from the remaining 6%.
    final exposure = insights.ingredientExposure(
      intakes: [intake('i1', 's'), intake('i2', 's'), intake('i3', 's')],
      supplements: [
        supplement('s', const [
          {'name': 'Magnesium', 'unit': 'mg', 'amount': 300},
        ]),
      ],
      from: day,
      to: day,
    );

    expect(exposure.single.name, 'Magnesium');
    expect(exposure.single.total, closeTo(900, 1e-9));
  });

  test('the snapshot wins when present, because it records what was taken', () {
    // The product has since been reformulated; the older intake must keep the
    // amount it actually delivered.
    final exposure = insights.ingredientExposure(
      intakes: [
        intake(
          'i1',
          's',
          snapshot: const [
            {'name': 'Magnesium', 'unit': 'mg', 'amount': 100},
          ],
        ),
        intake('i2', 's'),
      ],
      supplements: [
        supplement('s', const [
          {'name': 'Magnesium', 'unit': 'mg', 'amount': 300},
        ]),
      ],
      from: day,
      to: day,
    );

    expect(exposure.single.total, closeTo(400, 1e-9));
  });

  test('spellings of one substance are a single row', () {
    final exposure = insights.ingredientExposure(
      intakes: [
        intake(
          'i1',
          's',
          snapshot: const [
            {'name': 'Vitamin C', 'unit': 'mg', 'amount': 500},
          ],
        ),
        intake(
          'i2',
          's',
          snapshot: const [
            {'name': 'Vitamin c', 'unit': 'mg', 'amount': 500},
          ],
        ),
        intake(
          'i3',
          's',
          snapshot: const [
            {'name': 'B12', 'unit': 'µg', 'amount': 250},
          ],
        ),
        intake(
          'i4',
          's',
          snapshot: const [
            {'name': 'Vitamin B12', 'unit': 'µg', 'amount': 250},
          ],
        ),
      ],
      supplements: const [],
      from: day,
      to: day,
    );

    final byName = {for (final row in exposure) row.name: row.total};
    expect(byName.keys.toSet(), {'Vitamin C', 'Vitamin B12'});
    expect(byName['Vitamin C'], closeTo(1000, 1e-9));
    expect(byName['Vitamin B12'], closeTo(500, 1e-9));
  });

  test('one substance in two units stays two rows', () {
    // Merging identity must not merge magnitude.
    final exposure = insights.ingredientExposure(
      intakes: [
        intake(
          'i1',
          's',
          snapshot: const [
            {'name': 'Vitamin D3', 'unit': 'IU', 'amount': 1000},
          ],
        ),
        intake(
          'i2',
          's',
          snapshot: const [
            {'name': 'Vitamin D3', 'unit': 'µg', 'amount': 25},
          ],
        ),
      ],
      supplements: const [],
      from: day,
      to: day,
    );

    expect(exposure, hasLength(2));
    expect(exposure.map((row) => row.unit).toSet(), {'IU', 'µg'});
  });

  test('a named salt is not summed with the element', () {
    final exposure = insights.ingredientExposure(
      intakes: [
        intake(
          'i1',
          's',
          snapshot: const [
            {'name': 'Eisen', 'unit': 'mg', 'amount': 14},
          ],
        ),
        intake(
          'i2',
          's',
          snapshot: const [
            {
              'name': 'Eisen(II)-sulfat, getrocknetes',
              'unit': 'mg',
              'amount': 45,
            },
          ],
        ),
      ],
      supplements: const [],
      from: day,
      to: day,
    );

    // The salt's mass includes its counter-ion, so adding them would overstate
    // elemental iron.
    expect(exposure, hasLength(2));
  });
}
