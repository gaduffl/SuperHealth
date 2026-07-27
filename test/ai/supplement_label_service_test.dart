import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/api_key_store.dart';
import 'package:super_health/ai/provider_clients.dart';
import 'package:super_health/ai/supplement_label_service.dart';

void main() {
  final service = SupplementLabelService(
    keyStore: ApiKeyStore(),
    clientFactory: AiProviderClientFactory(),
  );

  test('divides label amounts down to a single stock unit', () {
    final parsed = service.decodeLabel('''
{
  "detected_serving_size": 4,
  "ingredients": [
    {"name": "Vitamin C", "amount": 440, "unit": "mg"},
    {"name": "Vitamin D3", "amount": 26, "unit": "µg"}
  ],
  "warnings": []
}
''', servingSize: 4);

    expect(parsed.ingredients.map((item) => item.name), [
      'Vitamin C',
      'Vitamin D3',
    ]);
    expect(parsed.ingredients.first.amount, 110);
    expect(parsed.ingredients.last.amount, 6.5);
    expect(parsed.servingSize, 4);
    expect(parsed.servingSizeDisagrees, isFalse);
  });

  test('flags a serving size that disagrees with the label', () {
    final parsed = service.decodeLabel(
      '{"detected_serving_size": 4, "ingredients": '
      '[{"name": "Zinc", "amount": 40, "unit": "mg"}]}',
      servingSize: 1,
    );

    // The amount is still divided by what the person entered; the mismatch is
    // surfaced rather than silently corrected, because only the person can see
    // the packaging.
    expect(parsed.ingredients.single.amount, 40);
    expect(parsed.servingSizeDisagrees, isTrue);
    expect(parsed.detectedServingSize, 4);
  });

  test('keeps an ingredient the label states without an amount', () {
    final parsed = service.decodeLabel(
      '{"ingredients": [{"name": "Proprietary blend", "amount": null, '
      '"unit": ""}]}',
      servingSize: 2,
    );

    expect(parsed.ingredients.single.name, 'Proprietary blend');
    expect(parsed.ingredients.single.amount, isNull);
    expect(parsed.ingredients.single.toIngredientMap(), {
      'name': 'Proprietary blend',
    });
  });

  test('warns instead of guessing when an amount is unreadable', () {
    final parsed = service.decodeLabel(
      '{"ingredients": [{"name": "Magnesium", "amount": "about 200", '
      '"unit": "mg"}]}',
      servingSize: 1,
    );

    expect(parsed.ingredients.single.amount, isNull);
    expect(parsed.warnings, contains(contains('Magnesium')));
  });

  test('accepts a decimal comma and a fenced or bare array response', () {
    final fenced = service.decodeLabel(
      '```json\n{"ingredients": [{"name": "Zinc", "amount": "7,5", '
      '"unit": "mg"}]}\n```',
      servingSize: 1,
    );
    expect(fenced.ingredients.single.amount, 7.5);

    final bare = service.decodeLabel(
      '[{"name": "Zinc", "amount": 15, "unit": "mg"}]',
      servingSize: 3,
    );
    expect(bare.ingredients.single.amount, 5);
  });

  test('drops a row that carries no ingredient name', () {
    final parsed = service.decodeLabel(
      '{"ingredients": [{"amount": 10, "unit": "mg"}, '
      '{"name": "Iron", "amount": 10, "unit": "mg"}]}',
      servingSize: 1,
    );
    expect(parsed.ingredients.single.name, 'Iron');
  });

  test('rejects a response that is not usable rather than saving nothing', () {
    expect(
      () => service.decodeLabel('I could not read that label.', servingSize: 1),
      throwsA(isA<SupplementLabelFormatException>()),
    );
    expect(
      () => service.decodeLabel('{"warnings": []}', servingSize: 1),
      throwsA(isA<SupplementLabelFormatException>()),
    );
  });

  test('refuses a serving size below one', () {
    expect(
      () => service.decodeLabel('{"ingredients": []}', servingSize: 0),
      throwsA(isA<SupplementLabelFormatException>()),
    );
  });
}
