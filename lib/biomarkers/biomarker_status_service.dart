import '../domain/entities.dart';
import 'unit_conversion_service.dart';

/// A deterministic, profile-aware interpretation of one reported result.
///
/// This describes where a value sits relative to saved bounds. It deliberately
/// makes no diagnostic or medical-normality claim.
enum BiomarkerStatusKind {
  neverMeasured,
  below,
  above,
  inPersonalTarget,
  inStoredOptimal,
  withinStoredReference,
  withinLabRange,
  unavailable,
}

enum BiomarkerStatusSource {
  none,
  personalTarget,
  storedReferenceRange,
  labReportedRange,
}

class BiomarkerStatus {
  const BiomarkerStatus({
    required this.kind,
    required this.source,
    required this.label,
    required this.detail,
    this.value,
    this.unit,
    this.usedLow,
    this.usedHigh,
  });

  final BiomarkerStatusKind kind;
  final BiomarkerStatusSource source;
  final String label;
  final String detail;
  final double? value;
  final String? unit;

  /// The finite bounds that produced this status, expressed in [unit].
  final double? usedLow;
  final double? usedHigh;

  bool get isBelow => kind == BiomarkerStatusKind.below;
  bool get isAbove => kind == BiomarkerStatusKind.above;
  bool get isTargetOrOptimal =>
      kind == BiomarkerStatusKind.inPersonalTarget ||
      kind == BiomarkerStatusKind.inStoredOptimal;
  bool get isReferenceOrLab =>
      kind == BiomarkerStatusKind.withinStoredReference ||
      kind == BiomarkerStatusKind.withinLabRange;
}

class BiomarkerStatusBand {
  const BiomarkerStatusBand({
    required this.low,
    required this.high,
    required this.unit,
  });

  final double? low;
  final double? high;
  final String unit;
}

/// Evaluates a reported measurement without relying on a UI, database, or wall
/// clock. Callers should capture [now] once per build when evaluating a list.
class BiomarkerStatusService {
  BiomarkerStatusService({UnitConversionService? conversions})
    : _conversions = conversions ?? UnitConversionService();

  final UnitConversionService _conversions;

  /// Converts the exact band selected during [evaluate] into [toUnit].
  ///
  /// A one-sided band remains one-sided. The conversion fails closed when a
  /// present bound is non-finite or cannot be converted.
  BiomarkerStatusBand? convertUsedBand({
    required BiomarkerStatus status,
    required Biomarker biomarker,
    required String toUnit,
  }) {
    final fromUnit = status.unit;
    final low = status.usedLow;
    final high = status.usedHigh;
    if ((low == null && high == null) ||
        fromUnit == null ||
        fromUnit.trim().isEmpty ||
        toUnit.trim().isEmpty ||
        (low != null && !_finite(low)) ||
        (high != null && !_finite(high))) {
      return null;
    }
    final convertedLow = low == null
        ? null
        : _convertValue(low, fromUnit, toUnit, biomarker);
    final convertedHigh = high == null
        ? null
        : _convertValue(high, fromUnit, toUnit, biomarker);
    if ((low != null && convertedLow == null) ||
        (high != null && convertedHigh == null) ||
        (convertedLow != null &&
            convertedHigh != null &&
            convertedLow > convertedHigh)) {
      return null;
    }
    return BiomarkerStatusBand(
      low: convertedLow,
      high: convertedHigh,
      unit: _conversions.normalizeUnit(toUnit),
    );
  }

  BiomarkerStatus evaluate({
    required Biomarker biomarker,
    required Measurement? measurement,
    required Profile profile,
    required Iterable<ProfileBiomarkerTarget> targets,
    required Iterable<BiomarkerReferenceRange> referenceRanges,
    required DateTime now,
  }) {
    if (measurement == null) {
      return const BiomarkerStatus(
        kind: BiomarkerStatusKind.neverMeasured,
        source: BiomarkerStatusSource.none,
        label: 'Never measured',
        detail: 'No recorded result',
      );
    }
    if (!_finite(measurement.value) || measurement.unit.trim().isEmpty) {
      return const BiomarkerStatus(
        kind: BiomarkerStatusKind.unavailable,
        source: BiomarkerStatusSource.none,
        label: 'Unavailable',
        detail: 'The reported value or unit cannot be evaluated safely',
      );
    }

    final targetCandidates =
        targets
            .where(
              (target) =>
                  !target.deleted &&
                  target.profileId == profile.id &&
                  target.biomarkerId == biomarker.id,
            )
            .toList()
          ..sort(_targetOrder);
    for (final target in targetCandidates) {
      final bounds = _usableBounds(target.low, target.high);
      if (bounds == null || target.unit.trim().isEmpty) continue;
      final converted = _convert(measurement, target.unit, biomarker);
      if (converted == null) continue;
      return _againstTarget(converted, target, bounds);
    }

    final applicableRanges =
        referenceRanges
            .where((range) => _applies(range, biomarker, profile, measurement))
            .toList()
          ..sort(_rangeOrder);
    for (final range in applicableRanges) {
      final reference = _usableBounds(range.low, range.high);
      final optimal = _usableBounds(range.optimalLow, range.optimalHigh);
      if ((reference == null && optimal == null) || range.unit.trim().isEmpty) {
        continue;
      }
      final converted = _convert(measurement, range.unit, biomarker);
      if (converted == null) continue;
      return _againstStoredRange(converted, range, reference, optimal);
    }

    final labBounds = _usableBounds(
      measurement.labRefLow,
      measurement.labRefHigh,
    );
    if (labBounds != null) {
      return _againstLab(measurement.value, measurement.unit, labBounds);
    }
    return const BiomarkerStatus(
      kind: BiomarkerStatusKind.unavailable,
      source: BiomarkerStatusSource.none,
      label: 'Unavailable',
      detail: 'No usable personal target, stored reference, or lab range',
    );
  }

  BiomarkerStatus _againstTarget(
    double value,
    ProfileBiomarkerTarget target,
    _Bounds bounds,
  ) {
    final detail = _targetDetail(target);
    if (_below(value, bounds)) {
      return BiomarkerStatus(
        kind: BiomarkerStatusKind.below,
        source: BiomarkerStatusSource.personalTarget,
        label: 'Below personal target',
        detail: detail,
        value: value,
        unit: target.unit,
        usedLow: bounds.low,
        usedHigh: bounds.high,
      );
    }
    if (_above(value, bounds)) {
      return BiomarkerStatus(
        kind: BiomarkerStatusKind.above,
        source: BiomarkerStatusSource.personalTarget,
        label: 'Above personal target',
        detail: detail,
        value: value,
        unit: target.unit,
        usedLow: bounds.low,
        usedHigh: bounds.high,
      );
    }
    return BiomarkerStatus(
      kind: BiomarkerStatusKind.inPersonalTarget,
      source: BiomarkerStatusSource.personalTarget,
      label: 'In personal target',
      detail: detail,
      value: value,
      unit: target.unit,
      usedLow: bounds.low,
      usedHigh: bounds.high,
    );
  }

  BiomarkerStatus _againstStoredRange(
    double value,
    BiomarkerReferenceRange range,
    _Bounds? reference,
    _Bounds? optimal,
  ) {
    final detail = _rangeDetail(range);
    if (optimal != null && _inside(value, optimal)) {
      return BiomarkerStatus(
        kind: BiomarkerStatusKind.inStoredOptimal,
        source: BiomarkerStatusSource.storedReferenceRange,
        label: 'In stored optimal band',
        detail: detail,
        value: value,
        unit: range.unit,
        usedLow: optimal.low,
        usedHigh: optimal.high,
      );
    }
    if (reference != null && _below(value, reference)) {
      return BiomarkerStatus(
        kind: BiomarkerStatusKind.below,
        source: BiomarkerStatusSource.storedReferenceRange,
        label: 'Below stored reference',
        detail: detail,
        value: value,
        unit: range.unit,
        usedLow: reference.low,
        usedHigh: reference.high,
      );
    }
    if (reference != null && _above(value, reference)) {
      return BiomarkerStatus(
        kind: BiomarkerStatusKind.above,
        source: BiomarkerStatusSource.storedReferenceRange,
        label: 'Above stored reference',
        detail: detail,
        value: value,
        unit: range.unit,
        usedLow: reference.low,
        usedHigh: reference.high,
      );
    }
    if (reference != null) {
      return BiomarkerStatus(
        kind: BiomarkerStatusKind.withinStoredReference,
        source: BiomarkerStatusSource.storedReferenceRange,
        label: 'Within stored reference',
        detail: detail,
        value: value,
        unit: range.unit,
        usedLow: reference.low,
        usedHigh: reference.high,
      );
    }
    // An optimal-only record is still an explicit selected source.
    if (_below(value, optimal!)) {
      return BiomarkerStatus(
        kind: BiomarkerStatusKind.below,
        source: BiomarkerStatusSource.storedReferenceRange,
        label: 'Below stored optimal band',
        detail: detail,
        value: value,
        unit: range.unit,
        usedLow: optimal.low,
        usedHigh: optimal.high,
      );
    }
    if (_above(value, optimal)) {
      return BiomarkerStatus(
        kind: BiomarkerStatusKind.above,
        source: BiomarkerStatusSource.storedReferenceRange,
        label: 'Above stored optimal band',
        detail: detail,
        value: value,
        unit: range.unit,
        usedLow: optimal.low,
        usedHigh: optimal.high,
      );
    }
    throw StateError('A usable optimal range must classify a finite value.');
  }

  BiomarkerStatus _againstLab(double value, String unit, _Bounds bounds) {
    if (_below(value, bounds)) {
      return BiomarkerStatus(
        kind: BiomarkerStatusKind.below,
        source: BiomarkerStatusSource.labReportedRange,
        label: 'Below lab range',
        detail: 'Lab-reported range: ${_boundsText(bounds)} $unit',
        value: value,
        unit: unit,
        usedLow: bounds.low,
        usedHigh: bounds.high,
      );
    }
    if (_above(value, bounds)) {
      return BiomarkerStatus(
        kind: BiomarkerStatusKind.above,
        source: BiomarkerStatusSource.labReportedRange,
        label: 'Above lab range',
        detail: 'Lab-reported range: ${_boundsText(bounds)} $unit',
        value: value,
        unit: unit,
        usedLow: bounds.low,
        usedHigh: bounds.high,
      );
    }
    return BiomarkerStatus(
      kind: BiomarkerStatusKind.withinLabRange,
      source: BiomarkerStatusSource.labReportedRange,
      label: 'Within lab range',
      detail: 'Lab-reported range: ${_boundsText(bounds)} $unit',
      value: value,
      unit: unit,
      usedLow: bounds.low,
      usedHigh: bounds.high,
    );
  }

  double? _convert(
    Measurement measurement,
    String toUnit,
    Biomarker biomarker,
  ) => _convertValue(measurement.value, measurement.unit, toUnit, biomarker);

  double? _convertValue(
    double value,
    String fromUnit,
    String toUnit,
    Biomarker biomarker,
  ) {
    final primary = _conversions.convertValue(
      value,
      fromUnit,
      toUnit,
      biomarker.canonicalName,
    );
    final fallback =
        primary ??
        (biomarker.id == biomarker.canonicalName
            ? null
            : _conversions.convertValue(value, fromUnit, toUnit, biomarker.id));
    return fallback != null && _finite(fallback) ? fallback : null;
  }

  bool _applies(
    BiomarkerReferenceRange range,
    Biomarker biomarker,
    Profile profile,
    Measurement measurement,
  ) {
    if (range.deleted || range.biomarkerId != biomarker.id) return false;
    final rangeSex = _normalizeSex(range.sex);
    if (rangeSex != null && rangeSex != _normalizeSex(profile.sex))
      return false;
    if (range.ageMin == null && range.ageMax == null) return true;
    final age = _ageOn(profile.dateOfBirth, measurement.takenAt);
    return age != null &&
        (range.ageMin == null || age >= range.ageMin!) &&
        (range.ageMax == null || age <= range.ageMax!);
  }

  static int _targetOrder(ProfileBiomarkerTarget a, ProfileBiomarkerTarget b) {
    final updated = b.updatedAt.compareTo(a.updatedAt);
    return updated != 0 ? updated : a.id.compareTo(b.id);
  }

  static int _rangeOrder(BiomarkerReferenceRange a, BiomarkerReferenceRange b) {
    final sex = _hasSex(b).compareTo(_hasSex(a));
    if (sex != 0) return sex;
    final bounded = _hasAgeBound(b).compareTo(_hasAgeBound(a));
    if (bounded != 0) return bounded;
    final span = _ageSpan(a).compareTo(_ageSpan(b));
    if (span != 0) return span;
    final updated = b.updatedAt.compareTo(a.updatedAt);
    return updated != 0 ? updated : a.id.compareTo(b.id);
  }

  static bool _hasSex(BiomarkerReferenceRange range) =>
      _normalizeSex(range.sex) != null;
  static bool _hasAgeBound(BiomarkerReferenceRange range) =>
      range.ageMin != null || range.ageMax != null;
  static int _ageSpan(BiomarkerReferenceRange range) {
    const minAge = 0;
    const maxAge = 200;
    return (range.ageMax ?? maxAge) - (range.ageMin ?? minAge);
  }

  static int? _ageOn(DateTime? dateOfBirth, DateTime date) {
    if (dateOfBirth == null) return null;
    var age = date.year - dateOfBirth.year;
    if (date.month < dateOfBirth.month ||
        (date.month == dateOfBirth.month && date.day < dateOfBirth.day)) {
      age--;
    }
    return age < 0 ? null : age;
  }

  static String? _normalizeSex(String? value) {
    final normalized = value?.trim().toLowerCase();
    return normalized == null || normalized.isEmpty ? null : normalized;
  }

  static _Bounds? _usableBounds(double? low, double? high) {
    if (low == null && high == null) return null;
    if ((low != null && !_finite(low)) || (high != null && !_finite(high))) {
      return null;
    }
    if (low != null && high != null && low > high) return null;
    return _Bounds(low, high);
  }

  static bool _finite(double value) => value.isFinite;
  static bool _below(double value, _Bounds bounds) =>
      bounds.low != null && value < bounds.low!;
  static bool _above(double value, _Bounds bounds) =>
      bounds.high != null && value > bounds.high!;
  static bool _inside(double value, _Bounds bounds) =>
      !_below(value, bounds) && !_above(value, bounds);

  static String _targetDetail(ProfileBiomarkerTarget target) {
    final borderline = _usableBounds(
      target.borderlineLow,
      target.borderlineHigh,
    );
    return [
      'Personal target: ${_boundsText(_Bounds(target.low, target.high))} ${target.unit}',
      if (borderline != null)
        'Borderline: ${_boundsText(borderline)} ${target.unit}',
    ].join(' · ');
  }

  static String _rangeDetail(BiomarkerReferenceRange range) => [
    if (_usableBounds(range.low, range.high) case final reference?)
      'Stored reference: ${_boundsText(reference)} ${range.unit}',
    if (_usableBounds(range.optimalLow, range.optimalHigh) case final optimal?)
      'Stored optimal: ${_boundsText(optimal)} ${range.unit}',
  ].join(' · ');

  static String _boundsText(_Bounds bounds) =>
      '${bounds.low?.toString() ?? '…'}–${bounds.high?.toString() ?? '…'}';
}

class _Bounds {
  const _Bounds(this.low, this.high);
  final double? low;
  final double? high;
}
