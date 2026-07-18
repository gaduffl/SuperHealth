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
