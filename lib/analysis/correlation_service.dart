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
    this.spearmanCoefficient,
    this.pValue,
    this.adjustedPValue,
  });

  final String exposure;
  final String outcome;
  final int lagDays;
  final double coefficient;
  final int sampleSize;

  /// Rank-based (Spearman) correlation, when both series have variation.
  ///
  /// [coefficient] remains the Pearson correlation for compatibility with
  /// existing callers. Spearman can be more informative when the association
  /// is monotonic but not linear.
  final double? spearmanCoefficient;

  /// Approximate two-sided Pearson correlation p-value.
  ///
  /// This is an exploratory estimate, not evidence of a causal effect. Daily
  /// observations may be autocorrelated, which can make it overconfident.
  final double? pValue;

  /// [pValue] after Benjamini-Hochberg correction across this analysis run.
  final double? adjustedPValue;

  /// Whether the Benjamini-Hochberg adjusted p-value is at most 0.05.
  bool get isStatisticallySignificant =>
      adjustedPValue != null && adjustedPValue! <= 0.05;

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

  /// Computes exploratory correlations from daily aggregates.
  ///
  /// [coefficient] is Pearson's linear correlation and
  /// [CorrelationResult.spearmanCoefficient] is the rank-based alternative.
  /// Positive lag means the exposure precedes the symptom by that many days.
  /// Results describe associations only; they do not establish causation.
  ///
  /// P-values are approximate two-sided Pearson tests and are adjusted with
  /// Benjamini-Hochberg across all returned comparisons. They should be read
  /// cautiously for time-series data, where successive daily observations are
  /// often not independent.
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

    // Correlation and its p-value are not useful below three pairs, even if a
    // caller passes a smaller threshold.
    final requiredPairs = math.max(3, minimumPairs);
    final uniqueLags = lags.toSet().toList()..sort();
    final candidates = <_CorrelationCandidate>[];
    for (final exposure in exposures.entries) {
      for (final outcome in outcomes.entries) {
        final dailyOutcome = outcome.value.map(
          (day, values) =>
              MapEntry(day, values.reduce((a, b) => a + b) / values.length),
        );
        for (final lag in uniqueLags) {
          final x = <double>[];
          final y = <double>[];
          for (final entry in dailyOutcome.entries) {
            final exposureDay = entry.key.subtract(Duration(days: lag));
            final exposureValue = exposure.value[exposureDay] ?? 0;
            // Do not let malformed imported numeric data contaminate every
            // comparison. Values remain paired when a bad observation is
            // excluded.
            if (!exposureValue.isFinite || !entry.value.isFinite) continue;
            x.add(exposureValue);
            y.add(entry.value);
          }
          if (x.length < requiredPairs) continue;
          final coefficient = _pearson(x, y);
          if (coefficient == null || !coefficient.isFinite) continue;
          candidates.add(
            _CorrelationCandidate(
              exposure: exposure.key,
              outcome: outcome.key,
              lagDays: lag,
              coefficient: coefficient,
              spearmanCoefficient: _spearman(x, y),
              sampleSize: x.length,
              pValue: _pearsonPValue(coefficient, x.length),
            ),
          );
        }
      }
    }

    final adjustedPValues = _benjaminiHochberg(
      candidates.map((candidate) => candidate.pValue).toList(),
    );
    final results = <CorrelationResult>[
      for (var index = 0; index < candidates.length; index++)
        CorrelationResult(
          exposure: candidates[index].exposure,
          outcome: candidates[index].outcome,
          lagDays: candidates[index].lagDays,
          coefficient: candidates[index].coefficient,
          spearmanCoefficient: candidates[index].spearmanCoefficient,
          sampleSize: candidates[index].sampleSize,
          pValue: candidates[index].pValue,
          adjustedPValue: adjustedPValues[index],
        ),
    ];
    results.sort(_compareResults);
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
    if (denominator == 0 || !denominator.isFinite) return null;
    // Round-off can produce a value microscopically outside [-1, 1].
    return (numerator / denominator).clamp(-1.0, 1.0).toDouble();
  }

  double? _spearman(List<double> x, List<double> y) =>
      _pearson(_averageRanks(x), _averageRanks(y));

  List<double> _averageRanks(List<double> values) {
    final indices = List<int>.generate(values.length, (index) => index)
      ..sort((a, b) => values[a].compareTo(values[b]));
    final ranks = List<double>.filled(values.length, 0);
    var start = 0;
    while (start < indices.length) {
      var end = start + 1;
      while (end < indices.length &&
          values[indices[end]] == values[indices[start]]) {
        end++;
      }
      // Ranks are one-based; ties receive their average rank.
      final rank = (start + 1 + end) / 2;
      for (var index = start; index < end; index++) {
        ranks[indices[index]] = rank;
      }
      start = end;
    }
    return ranks;
  }

  double? _pearsonPValue(double coefficient, int sampleSize) {
    if (sampleSize < 3 || !coefficient.isFinite) return null;
    final degreesOfFreedom = sampleSize - 2;
    final r = coefficient.abs().clamp(0.0, 1.0).toDouble();
    if (r == 1) return 0;
    final tSquared = (r * r * degreesOfFreedom) / (1 - r * r);
    if (!tSquared.isFinite) return 0;
    // For a t statistic, the two-sided tail probability is I_x(v/2, 1/2),
    // where x = v / (v + t^2).
    final x = degreesOfFreedom / (degreesOfFreedom + tSquared);
    return _regularizedIncompleteBeta(
      x,
      degreesOfFreedom / 2,
      0.5,
    ).clamp(0.0, 1.0).toDouble();
  }

  List<double?> _benjaminiHochberg(List<double?> pValues) {
    final indexed = <({int index, double value})>[
      for (var index = 0; index < pValues.length; index++)
        if (pValues[index] != null && pValues[index]!.isFinite)
          (index: index, value: pValues[index]!.clamp(0.0, 1.0).toDouble()),
    ]..sort((a, b) => a.value.compareTo(b.value));
    final adjusted = List<double?>.filled(pValues.length, null);
    var runningMinimum = 1.0;
    for (var index = indexed.length - 1; index >= 0; index--) {
      final corrected = (indexed[index].value * indexed.length / (index + 1))
          .clamp(0.0, 1.0)
          .toDouble();
      runningMinimum = math.min(runningMinimum, corrected);
      adjusted[indexed[index].index] = runningMinimum;
    }
    return adjusted;
  }

  int _compareResults(CorrelationResult a, CorrelationResult b) {
    final magnitude = b.coefficient.abs().compareTo(a.coefficient.abs());
    if (magnitude != 0) return magnitude;
    final exposure = a.exposure.compareTo(b.exposure);
    if (exposure != 0) return exposure;
    final outcome = a.outcome.compareTo(b.outcome);
    if (outcome != 0) return outcome;
    return a.lagDays.compareTo(b.lagDays);
  }

  double _regularizedIncompleteBeta(double x, double a, double b) {
    if (x <= 0) return 0;
    if (x >= 1) return 1;
    final beta = math.exp(
      _logGamma(a + b) -
          _logGamma(a) -
          _logGamma(b) +
          a * math.log(x) +
          b * math.log(1 - x),
    );
    if (x < (a + 1) / (a + b + 2)) {
      return beta * _betaContinuedFraction(x, a, b) / a;
    }
    return 1 - beta * _betaContinuedFraction(1 - x, b, a) / b;
  }

  double _betaContinuedFraction(double x, double a, double b) {
    const maxIterations = 200;
    const epsilon = 3e-14;
    const tiny = 1e-300;
    final qab = a + b;
    final qap = a + 1;
    final qam = a - 1;
    var c = 1.0;
    var d = 1 - qab * x / qap;
    if (d.abs() < tiny) d = tiny;
    d = 1 / d;
    var fraction = d;
    for (var iteration = 1; iteration <= maxIterations; iteration++) {
      final twiceIteration = 2 * iteration;
      var aa =
          iteration *
          (b - iteration) *
          x /
          ((qam + twiceIteration) * (a + twiceIteration));
      d = 1 + aa * d;
      if (d.abs() < tiny) d = tiny;
      c = 1 + aa / c;
      if (c.abs() < tiny) c = tiny;
      d = 1 / d;
      fraction *= d * c;
      aa =
          -(a + iteration) *
          (qab + iteration) *
          x /
          ((a + twiceIteration) * (qap + twiceIteration));
      d = 1 + aa * d;
      if (d.abs() < tiny) d = tiny;
      c = 1 + aa / c;
      if (c.abs() < tiny) c = tiny;
      d = 1 / d;
      final delta = d * c;
      fraction *= delta;
      if ((delta - 1).abs() < epsilon) break;
    }
    return fraction;
  }

  double _logGamma(double value) {
    const coefficients = [
      676.5203681218851,
      -1259.1392167224028,
      771.32342877765313,
      -176.61502916214059,
      12.507343278686905,
      -0.13857109526572012,
      9.9843695780195716e-6,
      1.5056327351493116e-7,
    ];
    if (value < 0.5) {
      return math.log(math.pi) -
          math.log(math.sin(math.pi * value)) -
          _logGamma(1 - value);
    }
    var adjusted = value - 1;
    var series = 0.99999999999980993;
    for (var index = 0; index < coefficients.length; index++) {
      series += coefficients[index] / (adjusted + index + 1);
    }
    final t = adjusted + coefficients.length - 0.5;
    return 0.5 * math.log(2 * math.pi) +
        (adjusted + 0.5) * math.log(t) -
        t +
        math.log(series);
  }
}

class _CorrelationCandidate {
  const _CorrelationCandidate({
    required this.exposure,
    required this.outcome,
    required this.lagDays,
    required this.coefficient,
    required this.spearmanCoefficient,
    required this.sampleSize,
    required this.pValue,
  });

  final String exposure;
  final String outcome;
  final int lagDays;
  final double coefficient;
  final double? spearmanCoefficient;
  final int sampleSize;
  final double? pValue;
}
