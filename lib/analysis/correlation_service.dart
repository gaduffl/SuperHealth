import 'dart:math' as math;

import '../data/health_repository.dart';
import '../domain/entities.dart';

class CorrelationResult {
  const CorrelationResult({
    required this.exposure,
    required this.outcome,
    required this.lagDays,
    required this.coefficient,
    required this.sampleSize,
  });

  final String exposure;
  final String outcome;
  final int lagDays;
  final double coefficient;
  final int sampleSize;

  String get strength {
    final magnitude = coefficient.abs();
    if (magnitude >= 0.7) return 'strong';
    if (magnitude >= 0.4) return 'moderate';
    return 'weak';
  }
}

class CorrelationService {
  CorrelationService(this._repository);

  final HealthRepository _repository;

  /// Computes exploratory Pearson correlations from daily aggregates.
  /// Positive lag means the exposure precedes the symptom by that many days.
  Future<List<CorrelationResult>> analyze(
    String profileId, {
    int minimumPairs = 7,
    List<int> lags = const [0, 1, 2],
  }) async {
    final supplements = await _repository.supplements(profileId);
    final supplementNames = {
      for (final item in supplements) item.id: item.name,
    };
    final intakes = await _repository.intakes(profileId);
    final events = await _repository.events(profileId);

    final exposures = <String, Map<DateTime, double>>{};
    for (final intake in intakes.where((item) => !item.skipped)) {
      final name = supplementNames[intake.supplementId] ?? 'Unknown supplement';
      final series = exposures.putIfAbsent('Supplement: $name', () => {});
      final day = _day(intake.takenAt);
      series[day] = (series[day] ?? 0) + intake.dose;
    }
    for (final event in events.where((item) => item.kind == EventKind.tag)) {
      final value = event.numericValue ?? event.score?.toDouble() ?? 1;
      final series = exposures.putIfAbsent('Tag: ${event.name}', () => {});
      final day = _day(event.observedAt);
      series[day] = (series[day] ?? 0) + value;
    }

    final outcomes = <String, Map<DateTime, List<double>>>{};
    for (final event in events.where(
      (item) => item.kind == EventKind.symptom,
    )) {
      final value = event.numericValue ?? event.score?.toDouble();
      if (value == null) continue;
      final day = _day(event.observedAt);
      outcomes
          .putIfAbsent(event.name, () => {})
          .putIfAbsent(day, () => [])
          .add(value);
    }

    final results = <CorrelationResult>[];
    for (final exposure in exposures.entries) {
      for (final outcome in outcomes.entries) {
        final dailyOutcome = outcome.value.map(
          (day, values) =>
              MapEntry(day, values.reduce((a, b) => a + b) / values.length),
        );
        for (final lag in lags) {
          final x = <double>[];
          final y = <double>[];
          for (final entry in dailyOutcome.entries) {
            final exposureDay = entry.key.subtract(Duration(days: lag));
            x.add(exposure.value[exposureDay] ?? 0);
            y.add(entry.value);
          }
          if (x.length < minimumPairs) continue;
          final coefficient = _pearson(x, y);
          if (coefficient == null || coefficient.isNaN) continue;
          results.add(
            CorrelationResult(
              exposure: exposure.key,
              outcome: outcome.key,
              lagDays: lag,
              coefficient: coefficient,
              sampleSize: x.length,
            ),
          );
        }
      }
    }
    results.sort((a, b) => b.coefficient.abs().compareTo(a.coefficient.abs()));
    return results;
  }

  DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);

  double? _pearson(List<double> x, List<double> y) {
    if (x.length != y.length || x.length < 2) return null;
    final meanX = x.reduce((a, b) => a + b) / x.length;
    final meanY = y.reduce((a, b) => a + b) / y.length;
    var numerator = 0.0;
    var sumX = 0.0;
    var sumY = 0.0;
    for (var index = 0; index < x.length; index++) {
      final dx = x[index] - meanX;
      final dy = y[index] - meanY;
      numerator += dx * dy;
      sumX += dx * dx;
      sumY += dy * dy;
    }
    final denominator = math.sqrt(sumX * sumY);
    return denominator == 0 ? null : numerator / denominator;
  }
}
