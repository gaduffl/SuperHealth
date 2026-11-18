import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  test('copyWith carries every field it does not replace', () {
    final original = Biomarker(
      id: 'glucose',
      canonicalName: 'glucose',
      displayName: 'Glucose',
      category: 'metabolic',
      defaultUnit: 'mg/dL',
      priceEur: 4.2,
      labName: 'Labor X',
      priceCheckedAt: DateTime.utc(2026, 2, 3),
      description: 'Fasting blood sugar.',
      synonyms: const ['Glukose'],
      isTemporary: true,
      isCalculated: false,
      calculationFormula: 'x',
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 2),
      deleted: true,
    );

    final changed = original.copyWith(category: 'lipids');

    expect(changed.category, 'lipids');
    expect(changed.toMap(), {...original.toMap(), 'category': 'lipids'});
    expect(original.copyWith().toMap(), original.toMap());
  });
}
