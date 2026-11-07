import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ui/supplement_form_presets.dart';

void main() {
  SupplementFormSelection stored(String form, String unit) =>
      SupplementFormSelection.fromStored(
        form: form,
        stockUnit: unit,
        genericStockUnit: 'unit',
      );

  test('forms are recognised in English and German spellings', () {
    expect(SupplementFormPreset.match('Kapseln'), SupplementFormPreset.capsule);
    expect(SupplementFormPreset.match(' powder '), SupplementFormPreset.powder);
    expect(SupplementFormPreset.match('Pulver'), SupplementFormPreset.powder);
    expect(SupplementFormPreset.match('Softgel'), SupplementFormPreset.softgel);
    expect(SupplementFormPreset.match('Liposomal'), isNull);
    expect(SupplementFormPreset.match(''), isNull);
  });

  test('a preset accepts its units in any spelling', () {
    expect(SupplementFormPreset.powder.accepts('g'), isTrue);
    expect(SupplementFormPreset.powder.accepts('Messlöffel'), isTrue);
    expect(SupplementFormPreset.powder.accepts('Powder'), isFalse);
    expect(SupplementFormPreset.softgel.accepts('Kapsel'), isTrue);
  });

  test('a stored unit always survives opening the editor', () {
    final legacy = stored('Powder', 'Powder');
    expect(legacy.preset, SupplementFormPreset.powder);
    expect(legacy.stockUnit, 'Powder');

    final custom = stored('Liposomal', 'ml');
    expect(custom.preset, SupplementFormPreset.other);
    expect(custom.stockUnit, 'ml');
  });

  test('the generic placeholder is filled only for count-only forms', () {
    expect(stored('Capsule', 'unit').stockUnit, 'capsule');
    expect(stored('Powder', 'unit').stockUnit, '');
    expect(stored('', 'unit').preset, isNull);
  });
}
