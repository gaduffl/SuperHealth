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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (weeks.isEmpty || series.isEmpty) return const SizedBox.shrink();

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

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LineChart(
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
        ),
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

/// A single-series line chart over dated points, used for symptom trends.
class TrendChart extends StatelessWidget {
  const TrendChart({
    required this.points,
    required this.dayLabel,
    required this.semanticLabel,
    this.minY,
    this.maxY,
    this.color,
    this.height = 200,
    super.key,
  });

  final List<({DateTime day, double value})> points;
  final String Function(DateTime day) dayLabel;
  final String semanticLabel;
  final double? minY;
  final double? maxY;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (points.isEmpty) return const SizedBox.shrink();
    final values = points.map((item) => item.value).toList();
    final low = minY ?? values.reduce(math.min);
    final high = maxY ?? values.reduce(math.max);
    final span = high == low ? 1.0 : high - low;
    final accent = color ?? scheme.primary;
    final labelStride = math.max(1, (points.length / 5).ceil());

    return Semantics(
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: LineChart(
          LineChartData(
            minX: 0,
            maxX: (points.length - 1).toDouble(),
            minY: low - span * 0.1,
            maxY: high + span * 0.1,
            gridData: FlGridData(
              drawVerticalLine: false,
              horizontalInterval: span / 4,
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
                  interval: 1,
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
            lineTouchData: LineTouchData(
              touchTooltipData: LineTouchTooltipData(
                getTooltipColor: (_) => scheme.inverseSurface,
                getTooltipItems: (spots) => [
                  for (final spot in spots)
                    if (spot.x.round() < 0 || spot.x.round() >= points.length)
                      null
                    else
                      LineTooltipItem(
                        '${dayLabel(points[spot.x.round()].day)}: '
                        '${spot.y.toStringAsFixed(1)}',
                        TextStyle(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                ],
              ),
            ),
            lineBarsData: [
              LineChartBarData(
                isCurved: true,
                curveSmoothness: 0.2,
                preventCurveOverShooting: true,
                color: accent,
                barWidth: 3,
                dotData: FlDotData(show: points.length <= 30),
                belowBarData: BarAreaData(
                  show: true,
                  color: accent.withValues(alpha: 0.12),
                ),
                spots: [
                  for (var index = 0; index < points.length; index++)
                    FlSpot(index.toDouble(), points[index].value),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
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
