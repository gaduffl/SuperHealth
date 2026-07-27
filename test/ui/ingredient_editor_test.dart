import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/supplement_label_service.dart';
import 'package:super_health/ui/ingredient_editor.dart';

void main() {
  test('reads back the ingredients it was built from', () {
    final rows = IngredientRows.from(const [
      {'name': 'Magnesium glycinate', 'amount': 100.0, 'unit': 'mg'},
      {'name': 'Vitamin B6', 'amount': 1.4, 'unit': 'mg'},
    ]);
    addTearDown(rows.dispose);

    expect(rows.parse(), [
      {'name': 'Magnesium glycinate', 'amount': 100.0, 'unit': 'mg'},
      {'name': 'Vitamin B6', 'amount': 1.4, 'unit': 'mg'},
    ]);
  });

  test('starts an empty product with one blank row that saves as nothing', () {
    final rows = IngredientRows.from(const []);
    addTearDown(rows.dispose);

    expect(rows.rows, hasLength(1));
    expect(rows.parse(), isEmpty);
  });

  test('keeps an ingredient without an amount or unit', () {
    final rows = IngredientRows.from(const [
      {'name': 'Proprietary blend'},
    ]);
    addTearDown(rows.dispose);

    expect(rows.parse(), [
      {'name': 'Proprietary blend'},
    ]);
  });

  test('accepts a decimal comma the way the number fields are typed', () {
    final rows = IngredientRows.from(const []);
    addTearDown(rows.dispose);
    rows.rows.single.name.text = 'Zinc';
    rows.rows.single.amount.text = '7,5';
    rows.rows.single.unit.text = 'mg';

    expect(rows.parse()?.single['amount'], 7.5);
  });

  test('refuses to save rather than dropping an unreadable amount', () {
    final rows = IngredientRows.from(const []);
    addTearDown(rows.dispose);
    rows.rows.single.name.text = 'Zinc';
    rows.rows.single.amount.text = 'about ten';

    expect(rows.parse(), isNull);
  });

  test('refuses to save an amount that has no ingredient name', () {
    final rows = IngredientRows.from(const []);
    addTearDown(rows.dispose);
    rows.rows.single.amount.text = '100';
    rows.rows.single.unit.text = 'mg';

    expect(rows.parse(), isNull);
  });

  test('a parsed label replaces the rows and stays editable', () {
    final rows = IngredientRows.from(const [
      {'name': 'Old entry', 'amount': 1.0, 'unit': 'mg'},
    ]);
    addTearDown(rows.dispose);

    rows.replaceAll(const [
      ParsedLabelIngredient(name: 'Vitamin C', amount: 110, unit: 'mg'),
      ParsedLabelIngredient(name: 'Vitamin D3', amount: 6.5, unit: '\u00b5g'),
      ParsedLabelIngredient(name: 'Blend', amount: null, unit: ''),
    ]);

    expect(rows.rows, hasLength(3));
    // Amounts land in the fields as plain numbers, without the trailing zeros
    // the division would otherwise leave behind.
    expect(rows.rows[0].amount.text, '110');
    expect(rows.rows[1].amount.text, '6.5');
    expect(rows.rows[2].amount.text, '');
    expect(rows.parse(), [
      {'name': 'Vitamin C', 'amount': 110.0, 'unit': 'mg'},
      {'name': 'Vitamin D3', 'amount': 6.5, 'unit': '\u00b5g'},
      {'name': 'Blend'},
    ]);
  });

  test('replacing with nothing leaves one blank row to type into', () {
    final rows = IngredientRows.from(const [
      {'name': 'Old entry', 'amount': 1.0, 'unit': 'mg'},
    ]);
    addTearDown(rows.dispose);

    rows.replaceAll(const []);

    expect(rows.rows, hasLength(1));
    expect(rows.parse(), isEmpty);
  });
}
