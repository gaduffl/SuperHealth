import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/biomarkers/biomarker_status_service.dart';
import 'package:super_health/domain/entities.dart';

void main() {
  final now = DateTime.utc(2026, 7, 18, 10);
  final service = BiomarkerStatusService();

  Biomarker biomarker({String id = 'apo', String name = 'apo_b'}) => Biomarker(
    id: id,
    canonicalName: name,
    displayName: 'ApoB',
    defaultUnit: 'mg/dL',
    createdAt: now,
    updatedAt: now,
  );

  Profile profile({String sex = 'female', DateTime? dob}) => Profile(
    id: 'profile',
    displayName: 'Ari',
    sex: sex,
    dateOfBirth: dob,
    createdAt: now,
    updatedAt: now,
  );

  Measurement measurement({
    double value = 10,
    String unit = 'mg/dL',
    String biomarkerId = 'apo',
    DateTime? takenAt,
    double? labLow,
    double? labHigh,
  }) => Measurement(
    id: 'measurement',
    profileId: 'profile',
    biomarkerId: biomarkerId,
    value: value,
    unit: unit,
    takenAt: takenAt ?? now,
    labRefLow: labLow,
    labRefHigh: labHigh,
    createdAt: now,
    updatedAt: now,
  );

  ProfileBiomarkerTarget target({
    String id = 'target',
    double? low,
    double? high,
    double? borderlineLow,
    double? borderlineHigh,
    String unit = 'mg/dL',
    DateTime? updatedAt,
  }) => ProfileBiomarkerTarget(
    id: id,
    profileId: 'profile',
    biomarkerId: 'apo',
    low: low,
    high: high,
    borderlineLow: borderlineLow,
    borderlineHigh: borderlineHigh,
    unit: unit,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );

  BiomarkerReferenceRange range({
    String id = 'range',
    String? sex,
    int? ageMin,
    int? ageMax,
    double? low,
    double? high,
    double? optimalLow,
    double? optimalHigh,
    String unit = 'mg/dL',
    DateTime? updatedAt,
  }) => BiomarkerReferenceRange(
    id: id,
    biomarkerId: 'apo',
    rangeType: 'reference',
    sex: sex,
    ageMin: ageMin,
    ageMax: ageMax,
    low: low,
    high: high,
    optimalLow: optimalLow,
    optimalHigh: optimalHigh,
    unit: unit,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );

  BiomarkerStatus evaluate({
    Biomarker? item,
    Measurement? result,
    Profile? activeProfile,
    List<ProfileBiomarkerTarget> targets = const [],
    List<BiomarkerReferenceRange> ranges = const [],
  }) => service.evaluate(
    biomarker: item ?? biomarker(),
    measurement: result,
    profile: activeProfile ?? profile(),
    targets: targets,
    referenceRanges: ranges,
    now: now,
  );

  test('target takes precedence and includes exact boundaries', () {
    final status = evaluate(
      result: measurement(value: 10, labLow: 20, labHigh: 30),
      targets: [
        target(low: 10, high: 20, borderlineLow: 11, borderlineHigh: 19),
      ],
      ranges: [range(low: 30, high: 40)],
    );

    expect(status.kind, BiomarkerStatusKind.inPersonalTarget);
    expect(status.source, BiomarkerStatusSource.personalTarget);
    expect(status.detail, contains('Personal target: 10.0–20.0 mg/dL'));
    expect(status.detail, contains('Borderline: 11.0–19.0 mg/dL'));
  });

  test('converts reported units before comparing with a personal target', () {
    final status = evaluate(
      result: measurement(value: 0.85, unit: 'g/L'),
      targets: [target(low: 80, high: 90)],
    );

    expect(status.kind, BiomarkerStatusKind.inPersonalTarget);
    expect(status.value, closeTo(85, 1e-9));
    expect(status.unit, 'mg/dL');
    expect(status.usedLow, 80);
    expect(status.usedHigh, 90);
  });

  test(
    'selected band converts using canonical name then biomarker id fallback',
    () {
      final item = biomarker(id: 'glu', name: 'unregistered_glucose_name');
      final status = evaluate(
        item: item,
        result: measurement(
          biomarkerId: 'glu',
          value: 90,
          unit: 'mg/dL',
          labLow: 80,
          labHigh: 100,
        ),
      );
      final band = service.convertUsedBand(
        status: status,
        biomarker: item,
        toUnit: 'mmol/L',
      );

      expect(status.usedLow, 80);
      expect(status.usedHigh, 100);
      expect(band, isNotNull);
      expect(band!.low, closeTo(4.4408, 1e-4));
      expect(band.high, closeTo(5.551, 1e-4));
      expect(band.unit, 'mmol/L');
    },
  );

  test(
    'selected band conversion fails when a present bound is incompatible',
    () {
      final status = evaluate(
        result: measurement(
          value: 12,
          unit: 'seconds',
          labLow: 10,
          labHigh: 15,
        ),
      );

      expect(status.usedLow, 10);
      expect(status.usedHigh, 15);
      expect(
        service.convertUsedBand(
          status: status,
          biomarker: biomarker(),
          toUnit: 'mg/dL',
        ),
        isNull,
      );
    },
  );

  test(
    'an impossible target conversion falls through to stored then lab bounds',
    () {
      final stored = evaluate(
        result: measurement(
          value: 12,
          unit: 'seconds',
          labLow: 20,
          labHigh: 30,
        ),
        targets: [target(low: 1, high: 2, unit: 'mg/dL')],
        ranges: [range(low: 10, high: 15, unit: 'seconds')],
      );
      final lab = evaluate(
        result: measurement(
          value: 12,
          unit: 'seconds',
          labLow: 10,
          labHigh: 15,
        ),
        targets: [target(low: 1, high: 2, unit: 'mg/dL')],
        ranges: [range(low: 10, high: 15, unit: 'mg/dL')],
      );

      expect(stored.kind, BiomarkerStatusKind.withinStoredReference);
      expect(stored.source, BiomarkerStatusSource.storedReferenceRange);
      expect(lab.kind, BiomarkerStatusKind.withinLabRange);
      expect(lab.source, BiomarkerStatusSource.labReportedRange);
    },
  );

  test('sex mismatches are excluded and age uses the measurement date', () {
    final item = biomarker();
    final activeProfile = profile(dob: DateTime.utc(2000, 7, 19));
    final beforeBirthday = evaluate(
      item: item,
      activeProfile: activeProfile,
      result: measurement(takenAt: DateTime.utc(2026, 7, 18)),
      ranges: [
        range(id: 'male', sex: 'male', low: 1, high: 2),
        range(id: 'age25', ageMax: 25, low: 10, high: 20),
        range(id: 'age26', ageMin: 26, low: 30, high: 40),
      ],
    );
    final onBirthday = evaluate(
      item: item,
      activeProfile: activeProfile,
      result: measurement(takenAt: DateTime.utc(2026, 7, 19), value: 35),
      ranges: [
        range(id: 'age25', ageMax: 25, low: 10, high: 20),
        range(id: 'age26', ageMin: 26, low: 30, high: 40),
      ],
    );

    expect(beforeBirthday.kind, BiomarkerStatusKind.withinStoredReference);
    expect(beforeBirthday.detail, contains('10.0–20.0'));
    expect(onBirthday.kind, BiomarkerStatusKind.withinStoredReference);
    expect(onBirthday.detail, contains('30.0–40.0'));
  });

  test('most specific range and then most recently updated range wins', () {
    final specific = evaluate(
      result: measurement(value: 3.5),
      activeProfile: profile(dob: DateTime.utc(1996, 1, 1)),
      ranges: [
        range(id: 'wide', low: 1, high: 9),
        range(
          id: 'female-age',
          sex: 'female',
          ageMin: 20,
          ageMax: 40,
          low: 3,
          high: 4,
        ),
      ],
    );
    final tie = evaluate(
      result: measurement(value: 10),
      ranges: [
        range(id: 'old', low: 1, high: 9, updatedAt: now),
        range(
          id: 'new',
          low: 1,
          high: 11,
          updatedAt: now.add(const Duration(seconds: 1)),
        ),
      ],
    );

    expect(specific.detail, contains('3.0–4.0'));
    expect(tie.kind, BiomarkerStatusKind.withinStoredReference);
    expect(tie.detail, contains('1.0–11.0'));
  });

  test(
    'stored optimal is distinct from stored reference and one-sided bounds work',
    () {
      final optimal = evaluate(
        result: measurement(value: 15),
        ranges: [range(low: 10, high: 20, optimalLow: 14, optimalHigh: 16)],
      );
      final reference = evaluate(
        result: measurement(value: 12),
        ranges: [range(low: 10, high: 20, optimalLow: 14, optimalHigh: 16)],
      );
      final below = evaluate(
        result: measurement(value: 9),
        ranges: [range(low: 10)],
      );
      final atBoundary = evaluate(
        result: measurement(value: 10),
        ranges: [range(low: 10)],
      );

      expect(optimal.kind, BiomarkerStatusKind.inStoredOptimal);
      expect(optimal.usedLow, 14);
      expect(optimal.usedHigh, 16);
      expect(reference.kind, BiomarkerStatusKind.withinStoredReference);
      expect(reference.usedLow, 10);
      expect(reference.usedHigh, 20);
      expect(below.kind, BiomarkerStatusKind.below);
      expect(below.usedLow, 10);
      expect(below.usedHigh, isNull);
      expect(atBoundary.kind, BiomarkerStatusKind.withinStoredReference);
    },
  );

  test('never measured and unresolved non-finite inputs are explicit', () {
    final never = evaluate(result: null);
    final noBounds = evaluate(result: measurement());
    final nonFiniteValue = evaluate(result: measurement(value: double.nan));
    final nonFiniteBounds = evaluate(
      result: measurement(),
      ranges: [range(low: double.infinity)],
    );

    expect(never.kind, BiomarkerStatusKind.neverMeasured);
    expect(noBounds.kind, BiomarkerStatusKind.unavailable);
    expect(nonFiniteValue.kind, BiomarkerStatusKind.unavailable);
    expect(nonFiniteBounds.kind, BiomarkerStatusKind.unavailable);
  });
}
