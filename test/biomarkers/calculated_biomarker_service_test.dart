import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/biomarkers/calculated_biomarker_service.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  final service = CalculatedBiomarkerService();
  final now = DateTime(2026, 8, 22, 8);

  test('calculates HOMA1-IR from the legacy fasting source markers', () {
    final result = service.derive(
      biomarkers: [
        _marker(
          'homa',
          CalculatedBiomarkerService.homa1CanonicalName,
          CalculatedBiomarkerService.homa1DisplayName,
          unit: 'index',
          calculated: true,
        ),
        _marker('glucose', 'glu', 'Glucose (nüchtern)', unit: 'mg/dL'),
        _marker('insulin', 'ins', 'Insulin (nüchtern)', unit: 'µIU/mL'),
      ],
      measurements: [
        _measurement('glucose-result', 'glucose', 90, 'mg/dL', now),
        _measurement('insulin-result', 'insulin', 5, 'µIU/mL', now),
      ],
    );

    expect(result, hasLength(1));
    expect(result.single.biomarkerId, 'homa');
    expect(result.single.value, closeTo(1.11, 0.01));
    expect(result.single.unit, 'index');
    expect(result.single.isCalculated, isTrue);
    expect(
      result.single.flags,
      contains(CalculatedBiomarkerService.homa1Flag),
    );
    expect(result.single.notes, contains('Not HOMA2-IR'));
  });

  test('does not treat an unspecified glucose marker as fasting', () {
    final result = service.derive(
      biomarkers: [
        _marker(
          'homa',
          CalculatedBiomarkerService.homa1CanonicalName,
          CalculatedBiomarkerService.homa1DisplayName,
          unit: 'index',
          calculated: true,
        ),
        _marker('glucose', 'glucose', 'Glucose', unit: 'mg/dL'),
        _marker('insulin', 'ins', 'Insulin (nüchtern)', unit: 'µIU/mL'),
      ],
      measurements: [
        _measurement('glucose-result', 'glucose', 90, 'mg/dL', now),
        _measurement('insulin-result', 'insulin', 5, 'µIU/mL', now),
      ],
    );

    expect(result, isEmpty);
  });

  test('requires a defensible same-date source pair', () {
    final markers = [
      _marker(
        'homa',
        CalculatedBiomarkerService.homa1CanonicalName,
        CalculatedBiomarkerService.homa1DisplayName,
        unit: 'index',
        calculated: true,
      ),
      _marker('glucose', 'glu', 'Glucose (nüchtern)', unit: 'mg/dL'),
      _marker('insulin', 'ins', 'Insulin (nüchtern)', unit: 'µIU/mL'),
    ];
    final farApart = service.derive(
      biomarkers: markers,
      measurements: [
        _measurement('glucose-result', 'glucose', 90, 'mg/dL', now),
        _measurement(
          'insulin-result',
          'insulin',
          5,
          'µIU/mL',
          now.add(const Duration(hours: 8)),
        ),
      ],
    );
    final sameDocument = service.derive(
      biomarkers: markers,
      measurements: [
        _measurement(
          'glucose-result',
          'glucose',
          90,
          'mg/dL',
          now,
          documentId: 'report',
        ),
        _measurement(
          'insulin-result',
          'insulin',
          5,
          'µIU/mL',
          now.add(const Duration(hours: 8)),
          documentId: 'report',
        ),
      ],
    );

    expect(farApart, isEmpty);
    expect(sameDocument, hasLength(1));
  });

  test('a reported HOMA1 value prevents a duplicate on that date', () {
    final result = service.derive(
      biomarkers: [
        _marker(
          'homa',
          CalculatedBiomarkerService.homa1CanonicalName,
          CalculatedBiomarkerService.homa1DisplayName,
          unit: 'index',
          calculated: true,
        ),
        _marker('glucose', 'glu', 'Glucose (nüchtern)', unit: 'mg/dL'),
        _marker('insulin', 'ins', 'Insulin (nüchtern)', unit: 'µIU/mL'),
      ],
      measurements: [
        _measurement('reported-homa', 'homa', 1.2, 'index', now),
        _measurement('glucose-result', 'glucose', 90, 'mg/dL', now),
        _measurement('insulin-result', 'insulin', 5, 'µIU/mL', now),
      ],
    );

    expect(result, isEmpty);
  });
}

Biomarker _marker(
  String id,
  String canonicalName,
  String displayName, {
  required String unit,
  bool calculated = false,
}) => Biomarker(
  id: id,
  canonicalName: canonicalName,
  displayName: displayName,
  defaultUnit: unit,
  isCalculated: calculated,
  calculationFormula: calculated
      ? CalculatedBiomarkerService.homa1Formula
      : null,
  createdAt: DateTime(2026),
  updatedAt: DateTime(2026),
);

Measurement _measurement(
  String id,
  String biomarkerId,
  double value,
  String unit,
  DateTime takenAt, {
  String? documentId,
}) => Measurement(
  id: id,
  profileId: 'profile',
  biomarkerId: biomarkerId,
  documentId: documentId,
  takenAt: takenAt,
  value: value,
  unit: unit,
  createdAt: takenAt,
  updatedAt: takenAt,
);
