import 'package:collection/collection.dart';

import '../domain/entities.dart';
import 'unit_conversion_service.dart';

/// Builds deterministic calculated biomarkers from stored source evidence.
///
/// The returned measurements are views, not ledger rows. Re-reading after a
/// source edit or deletion therefore recalculates them without synchronizing a
/// second copy that could become stale.
class CalculatedBiomarkerService {
  CalculatedBiomarkerService({UnitConversionService? unitConversions})
    : _unitConversions = unitConversions ?? UnitConversionService();

  static const homa1CanonicalName = 'homa1_ir';
  static const homa1FallbackId = 'calculated_homa1_ir';
  static const homa1Formula =
      '(fasting_glucose_mmol_l * fasting_insulin_uIU_mL) / 22.5';
  static const homa1Flag = 'calculated:homa1_ir';
  static const sourcePairWindow = Duration(hours: 6);

  static const homa1DisplayName = 'HOMA1-IR (berechnet)';
  static const homa1Description =
      'Calculated HOMA1-IR estimate from fasting glucose and fasting insulin '
      'recorded on the same date. Formula: glucose (mmol/L) × insulin '
      '(µIU/mL) / 22.5. This is HOMA1, not HOMA2-IR.';
  static const homa1Synonyms = <String>[
    'HOMA1',
    'HOMA1-IR',
    'HOMA-IR (HOMA1)',
    'homa1_ir',
  ];

  final UnitConversionService _unitConversions;

  static bool isHoma1(Biomarker biomarker) =>
      biomarker.canonicalName == homa1CanonicalName ||
      biomarker.calculationFormula == homa1Formula;

  static bool isDerivedHoma1Measurement(Measurement measurement) =>
      measurement.conversionStatus == 'calculated' &&
      measurement.flags.contains(homa1Flag);

  /// Adds HOMA1-IR only when the stored rows form a defensible fasting pair.
  ///
  /// Inputs must fall on the same recorded calendar date and either share a
  /// source document or be no more than six hours apart. Each input is used at
  /// most once, and a reported HOMA1 value suppresses a duplicate that day.
  List<Measurement> derive({
    required List<Biomarker> biomarkers,
    required List<Measurement> measurements,
  }) {
    final homa1 = biomarkers.where(isHoma1).firstOrNull;
    if (homa1 == null) return const [];

    final byId = {for (final biomarker in biomarkers) biomarker.id: biomarker};
    final glucose = <_SourceMeasurement>[];
    final insulin = <_SourceMeasurement>[];
    final reportedHomaDays = <String>{};
    for (final measurement in measurements) {
      if (measurement.deleted || isDerivedHoma1Measurement(measurement)) {
        continue;
      }
      if (measurement.biomarkerId == homa1.id) {
        reportedHomaDays.add(_dayKey(measurement.takenAt));
        continue;
      }
      final biomarker = byId[measurement.biomarkerId];
      if (biomarker == null) continue;
      if (_isFastingGlucose(biomarker)) {
        final value = _convertedValue(
          measurement,
          biomarker,
          targetUnit: 'mmol/L',
        );
        if (value != null && value > 0) {
          glucose.add(_SourceMeasurement(measurement, value));
        }
      } else if (_isFastingInsulin(biomarker)) {
        final value = _convertedValue(
          measurement,
          biomarker,
          targetUnit: 'uIU/mL',
        );
        if (value != null && value > 0) {
          insulin.add(_SourceMeasurement(measurement, value));
        }
      }
    }

    final candidates = <_Homa1Pair>[];
    for (final glucoseValue in glucose) {
      for (final insulinValue in insulin) {
        final glucoseMeasurement = glucoseValue.measurement;
        final insulinMeasurement = insulinValue.measurement;
        if (glucoseMeasurement.profileId != insulinMeasurement.profileId ||
            _dayKey(glucoseMeasurement.takenAt) !=
                _dayKey(insulinMeasurement.takenAt)) {
          continue;
        }
        final difference = glucoseMeasurement.takenAt
            .difference(insulinMeasurement.takenAt)
            .abs();
        final sameDocument =
            glucoseMeasurement.documentId != null &&
            glucoseMeasurement.documentId == insulinMeasurement.documentId;
        if (!sameDocument && difference > sourcePairWindow) continue;
        candidates.add(
          _Homa1Pair(
            glucose: glucoseValue,
            insulin: insulinValue,
            sameDocument: sameDocument,
            difference: difference,
          ),
        );
      }
    }
    candidates.sort((left, right) {
      if (left.sameDocument != right.sameDocument) {
        return left.sameDocument ? -1 : 1;
      }
      final time = left.difference.compareTo(right.difference);
      if (time != 0) return time;
      final glucoseId = left.glucose.measurement.id.compareTo(
        right.glucose.measurement.id,
      );
      return glucoseId != 0
          ? glucoseId
          : left.insulin.measurement.id.compareTo(right.insulin.measurement.id);
    });

    final usedGlucose = <String>{};
    final usedInsulin = <String>{};
    final derived = <Measurement>[];
    for (final pair in candidates) {
      final glucoseMeasurement = pair.glucose.measurement;
      final insulinMeasurement = pair.insulin.measurement;
      if (usedGlucose.contains(glucoseMeasurement.id) ||
          usedInsulin.contains(insulinMeasurement.id) ||
          reportedHomaDays.contains(_dayKey(glucoseMeasurement.takenAt))) {
        continue;
      }
      final unrounded =
          pair.glucose.convertedValue * pair.insulin.convertedValue / 22.5;
      if (!unrounded.isFinite || unrounded <= 0) continue;
      final value = (unrounded * 100).roundToDouble() / 100;
      usedGlucose.add(glucoseMeasurement.id);
      usedInsulin.add(insulinMeasurement.id);
      final takenAt =
          glucoseMeasurement.takenAt.isAfter(insulinMeasurement.takenAt)
          ? glucoseMeasurement.takenAt
          : insulinMeasurement.takenAt;
      final createdAt =
          glucoseMeasurement.createdAt.isAfter(insulinMeasurement.createdAt)
          ? glucoseMeasurement.createdAt
          : insulinMeasurement.createdAt;
      final updatedAt =
          glucoseMeasurement.updatedAt.isAfter(insulinMeasurement.updatedAt)
          ? glucoseMeasurement.updatedAt
          : insulinMeasurement.updatedAt;
      derived.add(
        Measurement(
          id:
              '$homa1FallbackId:${glucoseMeasurement.id}:'
              '${insulinMeasurement.id}',
          profileId: glucoseMeasurement.profileId,
          biomarkerId: homa1.id,
          takenAt: takenAt,
          value: value,
          unit: 'index',
          canonicalValue: value,
          canonicalUnit: 'index',
          conversionStatus: 'calculated',
          flags: const [homa1Flag],
          notes:
              'HOMA1-IR calculated from fasting glucose '
              '(${pair.glucose.convertedValue} mmol/L) and fasting insulin '
              '(${pair.insulin.convertedValue} µIU/mL) recorded on the same '
              'date. Formula: glucose × insulin / 22.5. Not HOMA2-IR.',
          createdAt: createdAt,
          updatedAt: updatedAt,
        ),
      );
    }
    derived.sort((a, b) => b.takenAt.compareTo(a.takenAt));
    return derived;
  }

  double? _convertedValue(
    Measurement measurement,
    Biomarker biomarker, {
    required String targetUnit,
  }) {
    final keys = [
      biomarker.id,
      biomarker.canonicalName,
      biomarker.displayName,
      ...biomarker.synonyms,
    ];
    final canonicalValue = measurement.canonicalValue;
    final canonicalUnit = measurement.canonicalUnit;
    if (canonicalValue?.isFinite == true &&
        canonicalUnit?.trim().isNotEmpty == true) {
      final converted = _unitConversions.convertValueForBiomarkerKeys(
        canonicalValue!,
        canonicalUnit!,
        targetUnit,
        keys,
      );
      if (converted?.isFinite == true) return converted;
    }
    final converted = _unitConversions.convertValueForBiomarkerKeys(
      measurement.value,
      measurement.unit,
      targetUnit,
      keys,
    );
    return converted?.isFinite == true ? converted : null;
  }

  static bool _isFastingGlucose(Biomarker biomarker) {
    if (_normalized(biomarker.canonicalName) == 'glu') return true;
    final terms = _terms(biomarker);
    final glucose = terms.any(
      (term) => term.contains('glucose') || term.contains('glukose'),
    );
    return glucose && terms.any(_saysFasting);
  }

  static bool _isFastingInsulin(Biomarker biomarker) {
    if (_normalized(biomarker.canonicalName) == 'ins') return true;
    final terms = _terms(biomarker);
    return terms.any((term) => term.contains('insulin')) &&
        terms.any(_saysFasting);
  }

  static bool _saysFasting(String value) =>
      value.contains('fasting') ||
      value.contains('nuchtern') ||
      value.contains('nuechtern') ||
      value.contains('fpg');

  static List<String> _terms(Biomarker biomarker) => [
    biomarker.canonicalName,
    biomarker.displayName,
    ...biomarker.synonyms,
  ].map(_normalized).toList(growable: false);

  static String _normalized(String value) => value
      .trim()
      .toLowerCase()
      .replaceAll('ü', 'u')
      .replaceAll('ä', 'a')
      .replaceAll('ö', 'o')
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_');

  static String _dayKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class _SourceMeasurement {
  const _SourceMeasurement(this.measurement, this.convertedValue);

  final Measurement measurement;
  final double convertedValue;
}

class _Homa1Pair {
  const _Homa1Pair({
    required this.glucose,
    required this.insulin,
    required this.sameDocument,
    required this.difference,
  });

  final _SourceMeasurement glucose;
  final _SourceMeasurement insulin;
  final bool sameDocument;
  final Duration difference;
}
