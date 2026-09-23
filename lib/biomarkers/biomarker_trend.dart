import '../domain/entities.dart';
import 'biomarker_status_service.dart';
import 'unit_conversion_service.dart';

/// One biomarker's measurements on a single unit, with the band it is judged
/// against converted into that unit.
typedef BiomarkerTrendData = ({
  List<({DateTime day, double value})> points,
  String unit,
  double? rangeLow,
  double? rangeHigh,
});

/// The newest measurement per biomarker.
Map<String, Measurement> latestMeasurementsByBiomarker(
  Iterable<Measurement> measurements,
) {
  final latest = <String, Measurement>{};
  for (final measurement in measurements) {
    final existing = latest[measurement.biomarkerId];
    if (existing == null || measurement.takenAt.isAfter(existing.takenAt)) {
      latest[measurement.biomarkerId] = measurement;
    }
  }
  return latest;
}

/// Each biomarker's status against the profile's targets and ranges, judged
/// on its newest measurement.
Map<String, BiomarkerStatus> biomarkerStatusesFor({
  required List<Biomarker> biomarkers,
  required Map<String, Measurement> latestByBiomarker,
  required Profile profile,
  required List<ProfileBiomarkerTarget> targets,
  required List<BiomarkerReferenceRange> referenceRanges,
  DateTime? now,
}) {
  final service = BiomarkerStatusService();
  final at = now ?? DateTime.now();
  return {
    for (final biomarker in biomarkers)
      biomarker.id: service.evaluate(
        biomarker: biomarker,
        measurement: latestByBiomarker[biomarker.id],
        profile: profile,
        targets: targets,
        referenceRanges: referenceRanges,
        now: at,
      ),
  };
}

/// The points a trend chart draws for [biomarker].
///
/// Shared by the dashboard and the PDF export, so the page handed to a doctor
/// can never plot a different unit or band than the screen it was made from.
/// Values are converted onto the status's unit when that works for at least
/// one reading, else onto the newest reading's unit; a reading that cannot be
/// converted is left out rather than plotted on the wrong scale.
BiomarkerTrendData biomarkerTrendData({
  required Biomarker biomarker,
  required List<Measurement> measurements,
  required BiomarkerStatus status,
}) {
  final sorted = measurements.toList()
    ..sort((left, right) => left.takenAt.compareTo(right.takenAt));
  final latest = sorted.last;
  final conversions = UnitConversionService();
  final keys = <String>[
    biomarker.id,
    biomarker.canonicalName,
    biomarker.displayName,
    ...biomarker.synonyms,
  ];

  ({List<({DateTime day, double value})> points, String unit}) build(
    String unit,
  ) {
    final normalizedUnit = conversions.normalizeUnit(unit);
    final points = <({DateTime day, double value})>[];
    for (final measurement in sorted) {
      if (!measurement.value.isFinite) continue;
      final value = conversions.convertValueForBiomarkerKeys(
        measurement.value,
        measurement.unit,
        normalizedUnit,
        keys,
      );
      if (value?.isFinite == true) {
        points.add((day: measurement.takenAt, value: value!));
      }
    }
    return (points: points, unit: normalizedUnit);
  }

  ({List<({DateTime day, double value})> points, String unit}) selected;
  final preferredUnit = status.unit?.trim();
  if (preferredUnit != null && preferredUnit.isNotEmpty) {
    final preferred = build(preferredUnit);
    selected = preferred.points.isNotEmpty ? preferred : build(latest.unit);
  } else {
    selected = build(latest.unit);
  }
  final range = BiomarkerStatusService().convertUsedBand(
    status: status,
    biomarker: biomarker,
    toUnit: selected.unit,
  );
  return (
    points: selected.points,
    unit: selected.unit,
    rangeLow: range?.low,
    rangeHigh: range?.high,
  );
}

/// The dashboard group [biomarker] belongs to. An empty category is `other`,
/// so exporting and excluding use exactly the groups the dashboard shows.
String biomarkerDashboardCategory(Biomarker biomarker) {
  final category = biomarker.category.trim();
  return category.isEmpty ? 'other' : category;
}
