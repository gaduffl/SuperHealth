import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../app/app_controller.dart';
import '../domain/entities.dart';
import 'dialogs.dart';

Future<void> showBiomarkerDetail(
  BuildContext context,
  AppController controller,
  Biomarker biomarker,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (context) => FractionallySizedBox(
    heightFactor: 0.9,
    child: _BiomarkerDetail(controller: controller, biomarker: biomarker),
  ),
);

class _BiomarkerDetail extends StatelessWidget {
  const _BiomarkerDetail({required this.controller, required this.biomarker});

  final AppController controller;
  final Biomarker biomarker;

  @override
  Widget build(BuildContext context) {
    final values =
        controller.measurements
            .where((item) => item.biomarkerId == biomarker.id)
            .toList()
          ..sort((a, b) => a.takenAt.compareTo(b.takenAt));
    final daily = _dailyAverages(values);
    final latest = values.isEmpty ? null : values.last;
    final previous = values.length < 2 ? null : values[values.length - 2];
    return SafeArea(
      top: false,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      biomarker.displayName,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    Text(
                      [
                        if (biomarker.category.isNotEmpty) biomarker.category,
                        if (biomarker.defaultUnit.isNotEmpty)
                          biomarker.defaultUnit,
                        if (biomarker.isTemporary) 'Temporary mapping',
                      ].join(' · '),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: () =>
                    showAddMeasurementDialog(context, controller, biomarker),
                icon: const Icon(Icons.add),
                label: const Text('Result'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _Stat(
                  label: 'Latest',
                  value: latest == null
                      ? '—'
                      : '${latest.value} ${latest.unit}',
                  detail: latest == null
                      ? 'No result'
                      : DateFormat.yMMMd().format(latest.takenAt),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  label: 'Change',
                  value: latest == null || previous == null
                      ? '—'
                      : _signed(latest.value - previous.value),
                  detail: previous == null ? 'Need 2 results' : 'vs previous',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _Stat(
                  label: 'Lab range',
                  value: latest?.labRefLow == null && latest?.labRefHigh == null
                      ? '—'
                      : '${latest?.labRefLow ?? '…'}–${latest?.labRefHigh ?? '…'}',
                  detail: latest?.unit ?? biomarker.defaultUnit,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 18, 12, 10),
              child: values.length < 2
                  ? const SizedBox(
                      height: 180,
                      child: Center(
                        child: Text(
                          'Add at least two results to show a trend.',
                        ),
                      ),
                    )
                  : SizedBox(
                      height: 220,
                      child: CustomPaint(
                        painter: _TrendPainter(
                          values: daily,
                          lineColor: Theme.of(context).colorScheme.primary,
                          gridColor: Theme.of(
                            context,
                          ).colorScheme.outlineVariant,
                          textColor: Theme.of(
                            context,
                          ).colorScheme.onSurfaceVariant,
                          refLow: latest?.labRefLow,
                          refHigh: latest?.labRefHigh,
                          bandColor: Theme.of(
                            context,
                          ).colorScheme.secondaryContainer,
                        ),
                        size: Size.infinite,
                      ),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 18, 4, 6),
            child: Text(
              'History',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          if (values.isEmpty)
            const Card(child: ListTile(title: Text('No recorded results')))
          else
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  for (final value in values.reversed)
                    ListTile(
                      title: Text('${value.value} ${value.unit}'),
                      subtitle: Text(
                        [
                          DateFormat('dd.MM.yyyy').format(value.takenAt),
                          if (value.labRefLow != null ||
                              value.labRefHigh != null)
                            'Lab ref ${value.labRefLow ?? '…'}–${value.labRefHigh ?? '…'}',
                          if (value.extractionConfidence != null)
                            'Parse ${(value.extractionConfidence! * 100).round()}%',
                          if (value.notes.isNotEmpty) value.notes,
                        ].join(' · '),
                      ),
                      trailing: _RangeStatus(measurement: value),
                    ),
                ],
              ),
            ),
          if (biomarker.description.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(biomarker.description),
          ],
        ],
      ),
    );
  }

  List<_DailyValue> _dailyAverages(List<Measurement> values) {
    final grouped = <DateTime, List<double>>{};
    for (final value in values) {
      final day = DateTime(
        value.takenAt.year,
        value.takenAt.month,
        value.takenAt.day,
      );
      grouped.putIfAbsent(day, () => []).add(value.value);
    }
    return grouped.entries
        .map(
          (entry) => _DailyValue(
            entry.key,
            entry.value.reduce((a, b) => a + b) / entry.value.length,
          ),
        )
        .toList()
      ..sort((a, b) => a.date.compareTo(b.date));
  }

  String _signed(double value) =>
      '${value >= 0 ? '+' : ''}${value.toStringAsFixed(2)}';
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.detail});

  final String label;
  final String value;
  final String detail;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

class _RangeStatus extends StatelessWidget {
  const _RangeStatus({required this.measurement});

  final Measurement measurement;

  @override
  Widget build(BuildContext context) {
    final low = measurement.labRefLow;
    final high = measurement.labRefHigh;
    if (low == null && high == null) return const SizedBox.shrink();
    final inside =
        (low == null || measurement.value >= low) &&
        (high == null || measurement.value <= high);
    return Icon(
      inside ? Icons.check_circle_outline : Icons.error_outline,
      color: inside ? Colors.green : Theme.of(context).colorScheme.error,
    );
  }
}

class _DailyValue {
  const _DailyValue(this.date, this.value);

  final DateTime date;
  final double value;
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.values,
    required this.lineColor,
    required this.gridColor,
    required this.textColor,
    required this.bandColor,
    this.refLow,
    this.refHigh,
  });

  final List<_DailyValue> values;
  final Color lineColor;
  final Color gridColor;
  final Color textColor;
  final Color bandColor;
  final double? refLow;
  final double? refHigh;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 46.0;
    const right = 8.0;
    const top = 8.0;
    const bottom = 28.0;
    final chart = Rect.fromLTRB(
      left,
      top,
      size.width - right,
      size.height - bottom,
    );
    var minY = values.map((item) => item.value).reduce(math.min);
    var maxY = values.map((item) => item.value).reduce(math.max);
    if (refLow != null) minY = math.min(minY, refLow!);
    if (refHigh != null) maxY = math.max(maxY, refHigh!);
    final padding = (maxY - minY).abs() * 0.12;
    minY -= padding == 0 ? 1 : padding;
    maxY += padding == 0 ? 1 : padding;

    double y(double value) =>
        chart.bottom - ((value - minY) / (maxY - minY)) * chart.height;
    double x(int index) =>
        chart.left + index / (values.length - 1) * chart.width;

    if (refLow != null || refHigh != null) {
      final bandTop = y(refHigh ?? maxY).clamp(chart.top, chart.bottom);
      final bandBottom = y(refLow ?? minY).clamp(chart.top, chart.bottom);
      canvas.drawRect(
        Rect.fromLTRB(chart.left, bandTop, chart.right, bandBottom),
        Paint()..color = bandColor.withValues(alpha: 0.45),
      );
    }
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var index = 0; index <= 4; index++) {
      final gridY = chart.top + chart.height * index / 4;
      canvas.drawLine(
        Offset(chart.left, gridY),
        Offset(chart.right, gridY),
        gridPaint,
      );
      final label = (maxY - (maxY - minY) * index / 4).toStringAsFixed(1);
      _text(canvas, label, Offset(0, gridY - 6), 10);
    }

    final path = Path()..moveTo(x(0), y(values.first.value));
    for (var index = 1; index < values.length; index++) {
      path.lineTo(x(index), y(values[index].value));
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    for (var index = 0; index < values.length; index++) {
      canvas.drawCircle(
        Offset(x(index), y(values[index].value)),
        4,
        Paint()..color = lineColor,
      );
    }
    _text(
      canvas,
      DateFormat('MM/yy').format(values.first.date),
      Offset(chart.left, chart.bottom + 7),
      10,
    );
    final lastLabel = DateFormat('MM/yy').format(values.last.date);
    final painter = TextPainter(
      text: TextSpan(
        text: lastLabel,
        style: TextStyle(color: textColor, fontSize: 10),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(chart.right - painter.width, chart.bottom + 7),
    );
  }

  void _text(Canvas canvas, String value, Offset offset, double size) {
    final painter = TextPainter(
      text: TextSpan(
        text: value,
        style: TextStyle(color: textColor, fontSize: size),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.refLow != refLow ||
      oldDelegate.refHigh != refHigh;
}
