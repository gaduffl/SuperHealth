import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../analysis/supplement_insights.dart';
import 'design.dart';

/// A multi-series weekly line chart.
///
/// Used for both supplement intake and ingredient exposure. Every series keeps
/// its own unit, so the chart normalises nothing and the caller is expected to
/// only pass series that share a scale worth comparing.
class WeeklySeriesChart extends StatelessWidget {
  const WeeklySeriesChart({
    required this.weeks,
    required this.series,
    required this.colors,
    required this.weekLabel,
    required this.valueLabel,
    required this.semanticLabel,
    this.height = 240,
    super.key,
  });

  final List<DateTime> weeks;
  final List<ExposureSeries> series;
  final Map<String, Color> colors;
  final String Function(DateTime week) weekLabel;
  final String Function(double value) valueLabel;
  final String semanticLabel;
  final double height;

  /// The width each week needs before the axis becomes unreadable.
  ///
  /// A year of data is 52 points; squeezed into a phone's width the line turns
  /// into a smear, so past this density the chart scrolls sideways instead.
  static const minimumWeekWidth = 26.0;

  @override
  Widget build(BuildContext context) {
    if (weeks.isEmpty || series.isEmpty) return const SizedBox.shrink();
    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final needed = weeks.length * minimumWeekWidth;
            if (needed <= constraints.maxWidth) return _chart(context);
            return Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: needed, child: _chart(context)),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _chart(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    var maximum = 0.0;
    for (final item in series) {
      for (final week in weeks) {
        maximum = math.max(maximum, item.weeklyTotals[week] ?? 0);
      }
    }
    if (maximum <= 0) maximum = 1;

    // Roughly five gridlines regardless of magnitude.
    final interval = maximum / 4;
    // With many weeks, labelling every one turns the axis into a smear.
    final labelStride = math.max(1, (weeks.length / 6).ceil());

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (weeks.length - 1).toDouble(),
        minY: 0,
        maxY: maximum * 1.1,
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: scheme.outlineVariant, strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 48,
              interval: interval,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  valueLabel(value),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.round();
                if (index < 0 || index >= weeks.length) {
                  return const SizedBox.shrink();
                }
                if (index % labelStride != 0 && index != weeks.length - 1) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    weekLabel(weeks[index]),
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            // Without these the label is centred on the touched point and
            // simply leaves the plot at either edge, which is where the last
            // reading — the one most worth tapping — always sits.
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipColor: (_) => scheme.inverseSurface,
            getTooltipItems: (spots) => [
              for (final spot in spots)
                if (spot.barIndex < 0 || spot.barIndex >= series.length)
                  null
                else
                  LineTooltipItem(
                    '${series[spot.barIndex].label}: '
                    '${valueLabel(spot.y)}',
                    TextStyle(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ],
          ),
        ),
        lineBarsData: [
          for (final item in series)
            LineChartBarData(
              isCurved: true,
              curveSmoothness: 0.22,
              preventCurveOverShooting: true,
              barWidth: 2.6,
              color: colors[item.key] ?? scheme.primary,
              dotData: FlDotData(
                show: weeks.length <= 14,
                getDotPainter: (spot, _, bar, _) => FlDotCirclePainter(
                  radius: 3,
                  color: bar.color ?? scheme.primary,
                  strokeWidth: 0,
                ),
              ),
              spots: [
                for (var index = 0; index < weeks.length; index++)
                  FlSpot(
                    index.toDouble(),
                    item.weeklyTotals[weeks[index]] ?? 0,
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

/// A stacked weekly adherence chart: taken, skipped, and missed per week.
class AdherenceChart extends StatelessWidget {
  const AdherenceChart({
    required this.values,
    required this.weekLabel,
    required this.semanticLabel,
    this.height = 220,
    super.key,
  });

  final List<WeeklyAdherence> values;
  final String Function(DateTime week) weekLabel;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (values.isEmpty) return const SizedBox.shrink();
    final maximum = values
        .fold<int>(1, (value, item) => math.max(value, item.scheduled))
        .toDouble();
    final labelStride = math.max(1, (values.length / 6).ceil());

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            maxY: maximum * 1.1,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: math.max(1, maximum / 4),
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: scheme.outlineVariant, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItem: (group, _, rod, _) =>
                    group.x < 0 || group.x >= values.length
                    ? null
                    : BarTooltipItem(
                        '${weekLabel(values[group.x].weekStarting)}\n'
                        '${values[group.x].taken} / '
                        '${values[group.x].scheduled}',
                        TextStyle(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 32,
                  interval: math.max(1, maximum / 4),
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      value.round().toString(),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 28,
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index < 0 || index >= values.length) {
                      return const SizedBox.shrink();
                    }
                    if (index % labelStride != 0 &&
                        index != values.length - 1) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        weekLabel(values[index].weekStarting),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var index = 0; index < values.length; index++)
                BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: values[index].scheduled.toDouble(),
                      width: 14,
                      borderRadius: BorderRadius.circular(4),
                      color: scheme.surfaceContainerHighest,
                      rodStackItems: [
                        BarChartRodStackItem(
                          0,
                          values[index].taken.toDouble(),
                          scheme.primary,
                        ),
                        BarChartRodStackItem(
                          values[index].taken.toDouble(),
                          (values[index].taken + values[index].skipped)
                              .toDouble(),
                          scheme.outline,
                        ),
                        BarChartRodStackItem(
                          (values[index].taken + values[index].skipped)
                              .toDouble(),
                          (values[index].taken +
                                  values[index].skipped +
                                  values[index].missed)
                              .toDouble(),
                          scheme.error,
                        ),
                      ],
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A simple daily bar chart, used for the known intake cost trend.
class DailyValueChart extends StatelessWidget {
  const DailyValueChart({
    required this.points,
    required this.dayLabel,
    required this.valueLabel,
    required this.semanticLabel,
    this.height = 170,
    super.key,
  });

  final List<({DateTime day, double value})> points;
  final String Function(DateTime day) dayLabel;
  final String Function(double value) valueLabel;
  final String semanticLabel;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (points.isEmpty) return const SizedBox.shrink();
    final maximum = points.fold<double>(
      0,
      (value, item) => math.max(value, item.value),
    );
    final labelStride = math.max(1, (points.length / 5).ceil());

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: BarChart(
          BarChartData(
            maxY: maximum <= 0 ? 1 : maximum * 1.15,
            gridData: const FlGridData(show: false),
            borderData: FlBorderData(show: false),
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItem: (group, _, rod, _) =>
                    group.x < 0 || group.x >= points.length
                    ? null
                    : BarTooltipItem(
                        '${dayLabel(points[group.x].day)}\n'
                        '${valueLabel(rod.toY)}',
                        TextStyle(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              rightTitles: const AxisTitles(),
              leftTitles: const AxisTitles(),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  getTitlesWidget: (value, meta) {
                    final index = value.round();
                    if (index < 0 || index >= points.length) {
                      return const SizedBox.shrink();
                    }
                    if (index % labelStride != 0 &&
                        index != points.length - 1) {
                      return const SizedBox.shrink();
                    }
                    return SideTitleWidget(
                      meta: meta,
                      child: Text(
                        dayLabel(points[index].day),
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    );
                  },
                ),
              ),
            ),
            barGroups: [
              for (var index = 0; index < points.length; index++)
                BarChartGroupData(
                  x: index,
                  barRods: [
                    BarChartRodData(
                      toY: points[index].value,
                      width: 8,
                      borderRadius: BorderRadius.circular(3),
                      color: scheme.primary,
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A single-series line chart over dated points, used for symptom and
/// biomarker trends.
///
/// Points are placed by their real date rather than by list position, because
/// measurements arrive at irregular intervals and equal spacing would make a
/// six-month gap read like a six-day one — which also has to hold before any
/// dose underlay can be aligned against it honestly.
class TrendChart extends StatelessWidget {
  const TrendChart({
    required this.points,
    required this.dayLabel,
    required this.semanticLabel,
    this.minY,
    this.maxY,
    this.color,
    this.rangeLow,
    this.rangeHigh,
    this.rangeColor,
    this.noteLabel,
    this.doseSeries,
    this.doseColor,
    this.doseValueLabel,
    this.height = 200,
    super.key,
  });

  final List<({DateTime day, double value})> points;
  final String Function(DateTime day) dayLabel;
  final String semanticLabel;
  final double? minY;
  final double? maxY;
  final Color? color;
  final double? rangeLow;
  final double? rangeHigh;
  final Color? rangeColor;

  /// A remark to show under the value when the reading for [day] carries one.
  ///
  /// The remark is often the reason a point sits where it does — a different
  /// lab, a fasting sample, an illness that week — so a chart that hides it
  /// invites the wrong conclusion from the shape of the line.
  final String? Function(DateTime day)? noteLabel;

  /// Optional supplement dose drawn behind the trend on its own right-hand
  /// scale. Its unit is unrelated to the trend's, so the two are never mapped
  /// onto a shared axis.
  final DoseSeries? doseSeries;
  final Color? doseColor;
  final String Function(double value)? doseValueLabel;
  final double height;

  /// The share of the plot height the dose underlay is allowed to occupy, so
  /// it stays legible without competing with the measurement line.
  static const _doseHeightFraction = 0.55;

  /// Milliseconds since epoch, the chart's X unit.
  static double _x(DateTime day) => day.millisecondsSinceEpoch.toDouble();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (points.isEmpty) return const SizedBox.shrink();
    final sorted = points.toList()
      ..sort((left, right) => left.day.compareTo(right.day));
    final values = sorted.map((item) => item.value).toList();
    final finiteRangeLow = rangeLow?.isFinite == true ? rangeLow : null;
    final finiteRangeHigh = rangeHigh?.isFinite == true ? rangeHigh : null;
    final scaleValues = <double>[...values, ?finiteRangeLow, ?finiteRangeHigh];
    final low = minY ?? scaleValues.reduce(math.min);
    final high = maxY ?? scaleValues.reduce(math.max);
    final span = high == low ? 1.0 : high - low;
    final chartLow = low - span * 0.1;
    final chartHigh = high + span * 0.1;
    final accent = color ?? scheme.primary;
    final hasRange = finiteRangeLow != null || finiteRangeHigh != null;
    final annotationLow = (finiteRangeLow ?? chartLow)
        .clamp(chartLow, chartHigh)
        .toDouble();
    final annotationHigh = (finiteRangeHigh ?? chartHigh)
        .clamp(chartLow, chartHigh)
        .toDouble();

    final dose = doseSeries;
    final dosePeak = dose?.peakAverageDailyDose ?? 0;
    final showsDose = dose != null && dose.buckets.isNotEmpty && dosePeak > 0;
    // The underlay spans its own buckets, which usually reach further than the
    // measurements themselves, so the axis has to cover both.
    final firstX = math.min(
      _x(sorted.first.day),
      showsDose ? _x(dose.buckets.first.start) : _x(sorted.first.day),
    );
    final lastX = math.max(
      _x(sorted.last.day),
      showsDose ? _x(dose.buckets.last.end) : _x(sorted.last.day),
    );
    // A single measurement has no span to draw across, so give it one day of
    // padding on either side rather than collapsing the axis to zero width.
    const oneDayMs = 86400000.0;
    final minX = firstX == lastX ? firstX - oneDayMs : firstX;
    final maxX = firstX == lastX ? lastX + oneDayMs : lastX;
    final xSpan = maxX - minX;

    /// Maps a dose onto the primary axis so both can share one plot, with the
    /// dose baseline pinned to the bottom of the chart.
    double doseToChartY(double value) =>
        chartLow +
        (value / dosePeak) * (chartHigh - chartLow) * _doseHeightFraction;

    final doseTint = doseColor ?? scheme.tertiary;

    return Semantics(
      label: showsDose
          ? '$semanticLabel. ${_doseSemanticSuffix(dose)}'
          : semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minX: minX,
            maxX: maxX,
            minY: chartLow,
            maxY: chartHigh,
            rangeAnnotations: RangeAnnotations(
              horizontalRangeAnnotations:
                  hasRange && annotationLow <= annotationHigh
                  ? [
                      HorizontalRangeAnnotation(
                        y1: annotationLow,
                        y2: annotationHigh,
                        color: (rangeColor ?? scheme.secondaryContainer)
                            .withValues(alpha: 0.45),
                      ),
                    ]
                  : const [],
              // Spans with no intake recorded at all are shaded rather than
              // drawn as a zero dose, so a stretch the user never logged is
              // not read as a deliberate pause in supplementation.
              verticalRangeAnnotations: [
                if (showsDose)
                  for (final bucket in dose.buckets)
                    if (!bucket.tracked)
                      VerticalRangeAnnotation(
                        x1: _x(bucket.start),
                        x2: _x(bucket.end),
                        color: scheme.outlineVariant.withValues(alpha: 0.18),
                      ),
              ],
            ),
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: span / 4,
              getDrawingHorizontalLine: (_) =>
                  FlLine(color: scheme.outlineVariant, strokeWidth: 1),
            ),
            borderData: FlBorderData(show: false),
            titlesData: FlTitlesData(
              topTitles: const AxisTitles(),
              // The dose keeps its own scale on the right. Its unit is
              // unrelated to the trend's, so sharing the left axis would
              // invite reading e.g. 4000 IU against ng/mL.
              rightTitles: showsDose
                  ? AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                        interval: (chartHigh - chartLow) / 2,
                        getTitlesWidget: (value, meta) {
                          final fraction =
                              (value - chartLow) / (chartHigh - chartLow);
                          final doseValue =
                              fraction / _doseHeightFraction * dosePeak;
                          if (doseValue < 0 || doseValue > dosePeak * 1.001) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              doseValueLabel?.call(doseValue) ??
                                  _compactNumber(doseValue),
                              style: Theme.of(
                                context,
                              ).textTheme.labelSmall?.copyWith(color: doseTint),
                            ),
                          );
                        },
                      ),
                    )
                  : const AxisTitles(),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 34,
                  interval: span / 2,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      value.toStringAsFixed(span >= 4 ? 0 : 1),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 26,
                  interval: xSpan <= 0 ? null : xSpan / 4,
                  getTitlesWidget: (value, meta) => SideTitleWidget(
                    meta: meta,
                    child: Text(
                      dayLabel(
                        DateTime.fromMillisecondsSinceEpoch(value.round()),
                      ),
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
              ),
            ),
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                fitInsideHorizontally: true,
                fitInsideVertically: true,
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItems: (spots) => [
                  for (final spot in spots)
                    // Only the measurement line carries a tooltip; the dose
                    // underlay is context, and labelling every step would
                    // bury the reading the user actually tapped.
                    if (spot.barIndex != (showsDose ? 1 : 0))
                      null
                    else
                      LineTooltipItem(
                        '${dayLabel(DateTime.fromMillisecondsSinceEpoch(spot.x.round()))}: '
                        '${spot.y.toStringAsFixed(1)}',
                        TextStyle(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
                        children: [
                          if (noteLabel?.call(
                                DateTime.fromMillisecondsSinceEpoch(
                                  spot.x.round(),
                                ),
                              )
                              case final note? when note.trim().isNotEmpty)
                            TextSpan(
                              text: '\n$note',
                              style: TextStyle(
                                color: scheme.onInverseSurface,
                                fontWeight: FontWeight.w400,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                ],
              ),
            ),
            lineBarsData: [
              // Drawn first so it sits behind the reference band and the
              // measurement line. Stepped rather than curved, because each
              // value is a flat average over its whole bucket.
              if (showsDose)
                LineChartBarData(
                  isStepLineChart: true,
                  lineChartStepData: const LineChartStepData(
                    stepDirection: LineChartStepData.stepDirectionForward,
                  ),
                  color: doseTint.withValues(alpha: 0.35),
                  barWidth: 0,
                  dotData: const FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: doseTint.withValues(alpha: 0.18),
                  ),
                  spots: [
                    for (final bucket in dose.buckets)
                      FlSpot(
                        _x(bucket.start),
                        doseToChartY(bucket.averageDailyDose),
                      ),
                    // Closes the final step so the last bucket keeps its full
                    // width instead of ending at its start.
                    FlSpot(
                      _x(dose.buckets.last.end),
                      doseToChartY(dose.buckets.last.averageDailyDose),
                    ),
                  ],
                ),
              LineChartBarData(
                isCurved: true,
                curveSmoothness: 0.2,
                preventCurveOverShooting: true,
                color: accent,
                barWidth: 3,
                dotData: FlDotData(show: sorted.length <= 30),
                belowBarData: BarAreaData(
                  show: true,
                  color: accent.withValues(alpha: 0.12),
                ),
                spots: [
                  for (final point in sorted)
                    FlSpot(_x(point.day), point.value),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _doseSemanticSuffix(DoseSeries dose) {
    final peak = dose.peakAverageDailyDose;
    final label = doseValueLabel?.call(peak) ?? _compactNumber(peak);
    return 'Supplement dose of ${dose.ingredientName} shown behind the trend, '
        'averaged over ${dose.bucketDays} days per step, peaking at '
        '$label ${dose.unit} per day.';
  }
}

/// Keeps an axis label short enough to read at chart scale.
String _compactNumber(double value) {
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}k';
  if (value >= 10) return value.toStringAsFixed(0);
  return value.toStringAsFixed(1);
}

/// A card wrapper that keeps every chart on the same padding and header style.
class ChartCard extends StatelessWidget {
  const ChartCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.legend,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final Widget? legend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          child,
          if (legend != null) ...[
            const SizedBox(height: AppSpacing.md),
            legend!,
          ],
        ],
      ),
    );
  }
}
