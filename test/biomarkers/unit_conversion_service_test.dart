import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/biomarkers/unit_conversion_service.dart';

void main() {
  final service = UnitConversionService();

  test('glucose mg/dL to mmol/L conversion', () {
    final result = service.convertValue(90, 'mg/dL', 'mmol/L', 'glu');
    expect(result, closeTo(4.9959, 1e-4));
  });

  test('canonical biomarker names use biomarker-specific conversions', () {
    final apoB = service.convertValue(0.85, 'g/L', 'mg/dL', 'apo_b');
    final vitaminE = service.convertValue(10, 'mg/L', 'µmol/L', 'vitamin_e');
    expect(apoB, closeTo(85, 1e-6));
    expect(vitaminE, closeTo(4.29, 1e-6));
  });

  test('unsupported dimensional conversion never invents a value', () {
    expect(service.convertValue(3, 'mg/dL', 'seconds', 'unknown'), isNull);
  });

  test('mass per volume fallback mg/L to mg/dL', () {
    final result = service.convertValue(15, 'mg/L', 'mg/dL', 'crp');
    expect(result, closeTo(1.5, 1e-6));
  });

  test('insulin uIU/mL to pmol/L', () {
    final result = service.convertValue(12, 'uIU/mL', 'pmol/L', 'ins');
    expect(result, closeTo(72, 1e-6));
  });

  test('cell count conversion 10^9/L to cells/uL', () {
    final result = service.convertValue(5.5, '10^9/L', 'cells/uL', 'wbc');
    expect(result, closeTo(5500, 1e-6));
  });

  test('legacy lab unit spellings normalize without changing values', () {
    final cases = <(double, String, String, String)>[
      (2.4, 'Tsd/µl', '10^9/L', 'lymphs'),
      (5.6, '/nl', '10^9/L', 'wbc'),
      (4.8, '/pl', '10^12/L', 'rbc'),
      (4.8, 'Mio/µl', '10^12/L', 'rbc'),
      (91, 'fl', 'fL', 'mcv'),
      (1.2, 'ng/l', 'pg/mL', 'ft3'),
      (1.1, 'IU/ml', 'IU/mL', 'tpo_ak'),
      (35, 'mg2/dl2', 'mg^2/dL^2', 'ca_po4_produkt'),
    ];

    for (final (value, from, to, biomarker) in cases) {
      expect(
        service.convertValue(value, from, to, biomarker),
        closeTo(value, 1e-9),
        reason: '$biomarker: $from → $to',
      );
    }
  });

  test('legacy biomarker synonyms unlock biomarker-specific conversions', () {
    final phosphate = service.convertValueForBiomarkerKeys(
      1,
      'mg/dl',
      'mmol/L',
      const ['phosphat_anorganisch', 'phosphate'],
    );
    final insulin = service.convertValueForBiomarkerKeys(
      4.6,
      'µU/ml',
      'µIU/mL',
      const ['insulin_nüchtern', 'ins'],
    );
    final tsh = service.convertValueForBiomarkerKeys(
      1.7,
      'mU/l',
      'mIU/L',
      const ['tsh'],
    );
    final egfr = service.convertValueForBiomarkerKeys(
      98,
      'ml/min',
      'mL/min/1.73 m^2',
      const ['gfr_ckd_epi_2021', 'gfr'],
    );
    expect(phosphate, closeTo(0.3229, 1e-9));
    expect(insulin, closeTo(4.6, 1e-9));
    expect(tsh, closeTo(1.7, 1e-9));
    expect(egfr, closeTo(98, 1e-9));
    expect(
      service.convertValue(12, 'U/ml', 'IU/mL', 'thyreoglobulin_ak'),
      isNull,
      reason: 'assay units must not be treated as international units',
    );
  });

  test('amount per volume conversion with suffix preserved', () {
    final result = service.convertValue(
      120,
      'umol/L Trolox-eq.',
      'mg/L Trolox',
      'tac',
    );
    expect(result, closeTo(30.0348, 1e-4));
  });

  test('preferred unit for insulin', () {
    expect(service.getPreferredUnit('ins'), 'uIU/mL');
  });

  test('possible targets include percent for ratio', () {
    final targets = service.getPossibleTargetUnits('ratio', 'homa_ir');
    expect(targets, contains('%'));
  });
}
