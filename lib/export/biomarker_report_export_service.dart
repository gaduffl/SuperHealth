import 'dart:math' as math;

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../biomarkers/biomarker_trend.dart';
import '../domain/entities.dart';
import 'biomarker_report_annotations.dart';
import 'lab_plan_export_service.dart';

class BiomarkerReportChart {
  const BiomarkerReportChart({required this.biomarker, required this.trend});

  final Biomarker biomarker;
  final BiomarkerTrendData trend;
}

class BiomarkerReportSection {
  const BiomarkerReportSection({
    required this.category,
    required this.title,
    required this.charts,
  });

  final String category;
  final String title;
  final List<BiomarkerReportChart> charts;
}

/// Everything the doctor's PDF shows, resolved before any drawing starts.
class BiomarkerReportRequest {
  const BiomarkerReportRequest({
    required this.patientName,
    required this.generatedAt,
    required this.sections,
    required this.excludedCategoryTitles,
    required this.annotations,
    this.dateOfBirth,
    this.valueTables = true,
  });

  final String patientName;
  final DateTime? dateOfBirth;
  final DateTime generatedAt;
  final List<BiomarkerReportSection> sections;

  /// Named on the first page, so a partial export never reads as the whole
  /// record.
  final List<String> excludedCategoryTitles;
  final BiomarkerExportAnnotations annotations;
  final bool valueTables;

  bool get isEmpty => sections.every((section) => section.charts.isEmpty);
}

/// The dashboard categories that have at least one measured biomarker.
Set<String> biomarkerReportCategories({
  required List<Biomarker> biomarkers,
  required List<Measurement> measurements,
}) {
  final measured = {for (final item in measurements) item.biomarkerId};
  return {
    for (final biomarker in biomarkers)
      if (measured.contains(biomarker.id))
        biomarkerDashboardCategory(biomarker),
  };
}

/// Assembles the export from the same trend data the dashboard draws.
BiomarkerReportRequest buildBiomarkerReportRequest({
  required Profile profile,
  required List<Biomarker> biomarkers,
  required List<Measurement> measurements,
  required List<HealthDocument> documents,
  required List<ProfileBiomarkerTarget> targets,
  required List<BiomarkerReferenceRange> referenceRanges,
  required String Function(String category) categoryTitle,
  Set<String> excludedCategories = const {},
  Set<String> suppressedDocumentIds = const {},
  bool valueTables = true,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  final latest = latestMeasurementsByBiomarker(measurements);
  final byBiomarker = <String, List<Measurement>>{};
  for (final measurement in measurements) {
    byBiomarker.putIfAbsent(measurement.biomarkerId, () => []).add(measurement);
  }
  final included = [
    for (final biomarker in biomarkers)
      if (latest.containsKey(biomarker.id) &&
          !excludedCategories.contains(biomarkerDashboardCategory(biomarker)))
        biomarker,
  ];
  final statuses = biomarkerStatusesFor(
    biomarkers: included,
    latestByBiomarker: latest,
    profile: profile,
    targets: targets,
    referenceRanges: referenceRanges,
    now: at,
  );
  final grouped = <String, List<BiomarkerReportChart>>{};
  for (final biomarker in included) {
    grouped
        .putIfAbsent(biomarkerDashboardCategory(biomarker), () => [])
        .add(
          BiomarkerReportChart(
            biomarker: biomarker,
            trend: biomarkerTrendData(
              biomarker: biomarker,
              measurements: byBiomarker[biomarker.id]!,
              status: statuses[biomarker.id]!,
            ),
          ),
        );
  }
  final sections = [
    for (final entry in grouped.entries)
      BiomarkerReportSection(
        category: entry.key,
        title: categoryTitle(entry.key),
        charts: entry.value
          ..sort(
            (a, b) => a.biomarker.displayName.toLowerCase().compareTo(
              b.biomarker.displayName.toLowerCase(),
            ),
          ),
      ),
  ]..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
  final excludedTitles = [
    for (final category in biomarkerReportCategories(
      biomarkers: biomarkers,
      measurements: measurements,
    ))
      if (excludedCategories.contains(category)) categoryTitle(category),
  ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return BiomarkerReportRequest(
    patientName: profile.displayName,
    dateOfBirth: profile.dateOfBirth,
    generatedAt: at,
    sections: sections,
    excludedCategoryTitles: excludedTitles,
    valueTables: valueTables,
    annotations: annotateBiomarkerExport(
      chartedDays: {
        for (final section in sections)
          for (final chart in section.charts)
            chart.biomarker.id: [
              for (final point in chart.trend.points) point.day,
            ],
      },
      measurements: measurements,
      documents: documents,
      suppressedDocumentIds: suppressedDocumentIds,
    ),
  );
}

/// A PDF of the biomarker dashboard for a doctor, in German.
///
/// Two charts per row keep a large panel to a few pages. Nothing is told by
/// colour alone, because the page will be printed and photocopied: a value
/// outside its band is a square rather than a circle, a lab-report comment is
/// a lettered dashed line, and a note on one value is a hollow point with a
/// number. The first page explains all three once.
class BiomarkerReportExportService {
  static const maxTableRows = 30;
  static const _chartHeight = 118.0;
  static const _columnGap = 14.0;
  static const _margin = 32.0;

  static final _inBand = PdfColor.fromInt(0xFF0072B2);
  static final _outOfBand = PdfColor.fromInt(0xFF9C6500);
  static final _band = PdfColor.fromInt(0xFFE3EEF7);
  static const _muted = PdfColors.grey700;

  Future<ExportedFile> build(BiomarkerReportRequest request) async {
    final document = pw.Document(
      title: _text('Biomarker-Verlauf ${request.patientName}'),
      author: 'SuperHealth',
      subject: 'Laborwerte im Verlauf',
    );
    final columnWidth = (PdfPageFormat.a4.width - 2 * _margin - _columnGap) / 2;
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(_margin),
        footer: (context) => _footer(context, request.annotations),
        build: (context) => [
          ..._introduction(request),
          for (final section in request.sections)
            if (section.charts.isNotEmpty)
              ..._section(section, request, columnWidth),
        ],
      ),
    );
    final stamp = DateFormat('yyyy-MM-dd').format(request.generatedAt);
    return ExportedFile(
      fileName: 'biomarker-verlauf-$stamp.pdf',
      mimeType: 'application/pdf',
      bytes: await document.save(),
    );
  }

  List<pw.Widget> _introduction(BiomarkerReportRequest request) {
    final days = [
      for (final section in request.sections)
        for (final chart in section.charts)
          for (final point in chart.trend.points) point.day,
    ]..sort();
    final reports = request.annotations.reports;
    return [
      pw.Text(
        'Biomarker-Verlauf',
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        _text(
          [
            request.patientName,
            if (request.dateOfBirth != null)
              'geb. ${_date(request.dateOfBirth!)}',
          ].join(' · '),
        ),
        style: const pw.TextStyle(fontSize: 11),
      ),
      pw.Text(
        _text(
          [
            'Erstellt am ${_date(request.generatedAt)}',
            if (days.isNotEmpty)
              'Messwerte ${_date(days.first)} – ${_date(days.last)}',
          ].join(' · '),
        ),
        style: const pw.TextStyle(fontSize: 9, color: _muted),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        _text(
          'Enthalten: ${request.sections.where((section) => section.charts.isNotEmpty).map((section) => section.title).join(', ')}',
        ),
        style: const pw.TextStyle(fontSize: 9),
      ),
      if (request.excludedCategoryTitles.isNotEmpty)
        pw.Text(
          _text(
            'Nicht enthalten: ${request.excludedCategoryTitles.join(', ')}',
          ),
          style: const pw.TextStyle(fontSize: 9),
        ),
      pw.SizedBox(height: 10),
      _legend(),
      if (reports.isNotEmpty) ...[
        pw.SizedBox(height: 10),
        pw.Text(
          'Laborberichte mit Kommentar',
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          columnWidths: const {
            0: pw.FixedColumnWidth(22),
            1: pw.FixedColumnWidth(58),
            2: pw.FlexColumnWidth(),
          },
          children: [
            for (final report in reports)
              pw.TableRow(
                verticalAlignment: pw.TableCellVerticalAlignment.top,
                children: [
                  _cell(report.letter, bold: true),
                  _cell(_date(report.date)),
                  _cell(
                    report.labName == null
                        ? report.comment
                        : '${report.labName}: ${report.comment}',
                  ),
                ],
              ),
          ],
        ),
      ],
      pw.SizedBox(height: 6),
    ];
  }

  pw.Widget _legend() {
    pw.Widget entry(pw.Widget symbol, String label) => pw.Padding(
      padding: const pw.EdgeInsets.only(right: 12, bottom: 3),
      child: pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.SizedBox(width: 14, height: 10, child: pw.Center(child: symbol)),
          pw.SizedBox(width: 3),
          pw.Text(label, style: const pw.TextStyle(fontSize: 8)),
        ],
      ),
    );
    pw.Widget painted(void Function(PdfGraphics canvas) paint) =>
        pw.CustomPaint(
          size: const PdfPoint(10, 10),
          painter: (canvas, size) => paint(canvas),
        );
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'Lesehilfe',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Wrap(
            children: [
              entry(
                painted((canvas) => _point(canvas, 5, 5, inBand: true)),
                'Wert im Bereich',
              ),
              entry(
                painted((canvas) => _point(canvas, 5, 5, inBand: false)),
                'Wert außerhalb des Bereichs',
              ),
              entry(
                painted(
                  (canvas) => canvas
                    ..setFillColor(_band)
                    ..drawRect(0, 2, 10, 6)
                    ..fillPath(),
                ),
                'Referenz- bzw. Zielbereich',
              ),
              entry(
                pw.Text(
                  'A',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                'Laborbericht mit Kommentar (gestrichelte Linie)',
              ),
              entry(
                _footnoteBadge(1),
                'Anmerkung zu diesem Einzelwert (unter dem Diagramm)',
              ),
            ],
          ),
        ],
      ),
    );
  }

  List<pw.Widget> _section(
    BiomarkerReportSection section,
    BiomarkerReportRequest request,
    double columnWidth,
  ) {
    final rows = <pw.Widget>[];
    for (var index = 0; index < section.charts.length; index += 2) {
      final pair = section.charts.skip(index).take(2).toList();
      rows.add(
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 12),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: columnWidth,
                child: _chartBlock(pair[0], request, columnWidth),
              ),
              pw.SizedBox(width: _columnGap),
              pw.SizedBox(
                width: columnWidth,
                child: pair.length > 1
                    ? _chartBlock(pair[1], request, columnWidth)
                    : pw.SizedBox(),
              ),
            ],
          ),
        ),
      );
    }
    // The heading travels with its first row, so a page never ends on a
    // category title with nothing under it.
    return [
      pw.Inseparable(
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
              child: pw.Text(
                _text(section.title),
                style: pw.TextStyle(
                  fontSize: 13,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            rows.first,
          ],
        ),
      ),
      ...rows.skip(1),
    ];
  }

  pw.Widget _chartBlock(
    BiomarkerReportChart chart,
    BiomarkerReportRequest request,
    double width,
  ) {
    final trend = chart.trend;
    final annotations = request.annotations.chartFor(chart.biomarker.id);
    final band = _bandLabel(trend);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          _text(chart.biomarker.displayName),
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          _text(
            [
              if (trend.unit.isNotEmpty) trend.unit,
              if (band != null) 'Bereich $band',
            ].join(' · '),
          ),
          style: const pw.TextStyle(fontSize: 7.5, color: _muted),
        ),
        pw.SizedBox(height: 3),
        if (trend.points.isEmpty)
          pw.Text(
            'Keine Werte in einer darstellbaren Einheit.',
            style: const pw.TextStyle(fontSize: 8, color: _muted),
          )
        else
          _chart(trend, annotations, width),
        for (final footnote in annotations.footnotes)
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 2),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _footnoteBadge(footnote.number),
                pw.SizedBox(width: 4),
                pw.Expanded(
                  child: pw.Text(
                    _text(
                      '${_date(footnote.day)} · '
                      '${_valuesOn(trend, footnote.day)} – ${footnote.text}',
                    ),
                    style: const pw.TextStyle(fontSize: 7.5),
                  ),
                ),
              ],
            ),
          ),
        if (request.valueTables && trend.points.isNotEmpty)
          _valueTable(trend, annotations),
      ],
    );
  }

  pw.Widget _chart(
    BiomarkerTrendData trend,
    ChartAnnotations annotations,
    double width,
  ) {
    final geometry = _ChartGeometry(trend, width, _chartHeight);
    const label = pw.TextStyle(fontSize: 6.5, color: _muted);
    final points = trend.points;
    return pw.SizedBox(
      width: width,
      height: _chartHeight,
      child: pw.Stack(
        children: [
          pw.CustomPaint(
            size: PdfPoint(width, _chartHeight),
            painter: (canvas, size) =>
                _paintChart(canvas, trend, annotations, geometry),
          ),
          for (final tick in geometry.valueTicks)
            pw.Positioned(
              left: 0,
              top: geometry.yTop(tick) - 4,
              child: pw.SizedBox(
                width: geometry.left - 3,
                child: pw.Text(
                  _number(tick),
                  style: label,
                  textAlign: pw.TextAlign.right,
                ),
              ),
            ),
          for (final (index, day) in geometry.dayTicks.indexed)
            pw.Positioned(
              left: switch (index) {
                0 => geometry.left,
                _ when index == geometry.dayTicks.length - 1 =>
                  geometry.right - 28,
                _ => geometry.x(day) - 14,
              },
              top: geometry.bottom + 3,
              child: pw.Text(DateFormat('MM/yy').format(day), style: label),
            ),
          for (final line in annotations.reportLines)
            pw.Positioned(
              left: geometry.x(line.day) - 3,
              top: 0,
              child: pw.Text(
                line.letter,
                style: pw.TextStyle(
                  fontSize: 7,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
          for (final footnote in annotations.footnotes)
            if (_highestOn(points, footnote.day) case final value?)
              pw.Positioned(
                left: geometry.x(footnote.day) + 3.5,
                top: geometry.yTop(value) - 9,
                child: pw.Text(
                  '${footnote.number}',
                  style: pw.TextStyle(
                    fontSize: 6.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
        ],
      ),
    );
  }

  void _paintChart(
    PdfGraphics canvas,
    BiomarkerTrendData trend,
    ChartAnnotations annotations,
    _ChartGeometry geometry,
  ) {
    // The painter draws from the bottom-left; the labels above are placed
    // from the top-left. Everything goes through the geometry so both agree.
    double y(double value) => geometry.height - geometry.yTop(value);
    final plotBottom = geometry.height - geometry.bottom;
    final plotTop = geometry.height - geometry.top;

    final low = trend.rangeLow;
    final high = trend.rangeHigh;
    if (low != null || high != null) {
      final from = low == null ? plotBottom : y(low).clamp(plotBottom, plotTop);
      final to = high == null ? plotTop : y(high).clamp(plotBottom, plotTop);
      canvas
        ..setFillColor(_band)
        ..drawRect(
          geometry.left,
          from,
          geometry.right - geometry.left,
          to - from,
        )
        ..fillPath();
    }

    canvas
      ..setStrokeColor(PdfColors.grey500)
      ..setLineWidth(0.5)
      ..drawLine(geometry.left, plotBottom, geometry.right, plotBottom)
      ..drawLine(geometry.left, plotBottom, geometry.left, plotTop)
      ..strokePath();

    for (final line in annotations.reportLines) {
      final x = geometry.x(line.day);
      canvas
        ..saveContext()
        ..setStrokeColor(PdfColors.grey600)
        ..setLineWidth(0.6)
        ..setLineDashPattern([2, 2])
        ..drawLine(x, plotBottom, x, geometry.height - 9)
        ..strokePath()
        ..restoreContext();
    }

    final points = trend.points;
    if (points.length > 1) {
      canvas
        ..setStrokeColor(PdfColors.grey700)
        ..setLineWidth(0.7)
        ..moveTo(geometry.x(points.first.day), y(points.first.value));
      for (final point in points.skip(1)) {
        canvas.lineTo(geometry.x(point.day), y(point.value));
      }
      canvas.strokePath();
    }
    for (final point in points) {
      final inBand =
          (low == null || point.value >= low) &&
          (high == null || point.value <= high);
      _point(
        canvas,
        geometry.x(point.day),
        y(point.value),
        inBand: inBand,
        hollow: annotations.footnoteOn(point.day) != null,
      );
    }
  }

  static void _point(
    PdfGraphics canvas,
    double x,
    double y, {
    required bool inBand,
    bool hollow = false,
  }) {
    final color = inBand ? _inBand : _outOfBand;
    void shape() => inBand
        ? canvas.drawEllipse(x, y, 2.6, 2.6)
        : canvas.drawRect(x - 2.5, y - 2.5, 5, 5);
    canvas
      ..setFillColor(hollow ? PdfColors.white : color)
      ..setStrokeColor(color)
      ..setLineWidth(hollow ? 1 : 0.5);
    shape();
    canvas.fillPath();
    shape();
    canvas.strokePath();
  }

  pw.Widget _valueTable(
    BiomarkerTrendData trend,
    ChartAnnotations annotations,
  ) {
    final rows = trend.points.reversed.take(maxTableRows).toList();
    final hidden = trend.points.length - rows.length;
    const style = pw.TextStyle(fontSize: 7);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 4),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Table(
            border: const pw.TableBorder(
              horizontalInside: pw.BorderSide(
                color: PdfColors.grey300,
                width: 0.4,
              ),
            ),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(
                children: [
                  for (final heading in ['Datum', 'Wert', 'Hinweis'])
                    pw.Text(
                      heading,
                      style: pw.TextStyle(
                        fontSize: 7,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                ],
              ),
              for (final point in rows)
                pw.TableRow(
                  children: [
                    pw.Text(_date(point.day), style: style),
                    pw.Text(
                      _text('${_number(point.value)} ${trend.unit}'.trim()),
                      style: style,
                    ),
                    pw.Text(
                      [
                        ?annotations.letterOn(point.day),
                        if (annotations.footnoteOn(point.day) case final n?)
                          '($n)',
                      ].join(' '),
                      style: style,
                    ),
                  ],
                ),
            ],
          ),
          if (hidden > 0)
            pw.Text(
              '$hidden ältere Werte sind nur im Diagramm dargestellt.',
              style: const pw.TextStyle(fontSize: 6.5, color: _muted),
            ),
        ],
      ),
    );
  }

  pw.Widget _footer(
    pw.Context context,
    BiomarkerExportAnnotations annotations,
  ) {
    const style = pw.TextStyle(fontSize: 6.5, color: _muted);
    // The full comments are on the first page; every page repeats which draw
    // each letter means, so a single printed page still reads on its own.
    final key = [
      for (final report in annotations.reports)
        '${report.letter} = ${_date(report.date)}'
            '${report.labName == null ? '' : ' (${report.labName})'}',
    ].join(' · ');
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Divider(color: PdfColors.grey400, height: 8),
        if (key.isNotEmpty)
          pw.Text(
            _text('Laborberichte: $key – Kommentare auf Seite 1'),
            style: style,
          ),
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Von der Patientin / dem Patienten mit SuperHealth erstellt. '
              'Kein Laborbefund.',
              style: style,
            ),
            pw.Text(
              'Seite ${context.pageNumber}/${context.pagesCount}',
              style: style,
            ),
          ],
        ),
      ],
    );
  }

  static pw.Widget _footnoteBadge(int number) => pw.Container(
    width: 9,
    height: 9,
    alignment: pw.Alignment.center,
    decoration: pw.BoxDecoration(
      shape: pw.BoxShape.circle,
      border: pw.Border.all(width: 0.6),
    ),
    child: pw.Text(
      '$number',
      style: pw.TextStyle(fontSize: 5.5, fontWeight: pw.FontWeight.bold),
    ),
  );

  static pw.Widget _cell(String text, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 3, right: 4),
    child: pw.Text(
      _text(text),
      style: pw.TextStyle(
        fontSize: 8,
        fontWeight: bold ? pw.FontWeight.bold : null,
      ),
    ),
  );

  static String? _bandLabel(BiomarkerTrendData trend) {
    final low = trend.rangeLow;
    final high = trend.rangeHigh;
    if (low != null && high != null) return '${_number(low)}–${_number(high)}';
    if (low != null) return '≥ ${_number(low)}';
    if (high != null) return '≤ ${_number(high)}';
    return null;
  }

  static String _valuesOn(BiomarkerTrendData trend, DateTime day) =>
      [
        for (final point in trend.points)
          if (_sameDay(point.day, day)) _number(point.value),
      ].join(' / ') +
      (trend.unit.isEmpty ? '' : ' ${trend.unit}');

  static double? _highestOn(
    List<({DateTime day, double value})> points,
    DateTime day,
  ) {
    double? highest;
    for (final point in points) {
      if (!_sameDay(point.day, day)) continue;
      highest = highest == null ? point.value : math.max(highest, point.value);
    }
    return highest;
  }
}

/// Where days and values land inside one chart box, in top-left coordinates.
class _ChartGeometry {
  _ChartGeometry(BiomarkerTrendData trend, this.width, this.height)
    : left = 30,
      right = width - 8,
      top = 12,
      bottom = height - 12 {
    final days = [for (final point in trend.points) point.day];
    _first = days.reduce((a, b) => a.isBefore(b) ? a : b);
    _last = days.reduce((a, b) => a.isAfter(b) ? a : b);
    final values = [
      for (final point in trend.points) point.value,
      ?trend.rangeLow,
      ?trend.rangeHigh,
    ];
    var low = values.reduce(math.min);
    var high = values.reduce(math.max);
    if (high == low) {
      final pad = low == 0 ? 1.0 : low.abs() * 0.1;
      low -= pad;
      high += pad;
    }
    // Round tick values: a doctor reads "100, 150, 200" at a glance and has to
    // parse "32,9 … 407".
    _step = _niceStep((high - low) / 4);
    _low = (low / _step).floor() * _step;
    _high = (high / _step).ceil() * _step;
  }

  static double _niceStep(double raw) {
    final magnitude = math
        .pow(10, (math.log(raw) / math.ln10).floor())
        .toDouble();
    final fraction = raw / magnitude;
    final nice = fraction <= 1
        ? 1
        : fraction <= 2
        ? 2
        : fraction <= 2.5
        ? 2.5
        : fraction <= 5
        ? 5
        : 10;
    return nice * magnitude;
  }

  final double width;
  final double height;
  final double left;
  final double right;
  final double top;
  final double bottom;
  late final DateTime _first;
  late final DateTime _last;
  late final double _low;
  late final double _high;
  late final double _step;

  // Inset so a point on the first or last day is not cut by the axis.
  static const _inset = 6.0;

  double x(DateTime day) {
    final span = _last.difference(_first).inMilliseconds;
    if (span == 0) return (left + right) / 2;
    final share = day.difference(_first).inMilliseconds / span;
    return left + _inset + share * (right - left - 2 * _inset);
  }

  double yTop(double value) =>
      bottom - (value - _low) / (_high - _low) * (bottom - top);

  List<double> get valueTicks => [
    for (var tick = _low; tick <= _high + _step / 2; tick += _step) tick,
  ];

  List<DateTime> get dayTicks {
    if (_last == _first) return [_first];
    final middle = _first.add(
      Duration(milliseconds: _last.difference(_first).inMilliseconds ~/ 2),
    );
    return [_first, middle, _last];
  }
}

final _germanNumber = NumberFormat('#,##0.###', 'de');

/// German decimal comma, with only as many places as the value needs.
String _number(double value) {
  final magnitude = value.abs();
  final places = magnitude >= 100
      ? 0
      : magnitude >= 10
      ? 1
      : magnitude >= 1
      ? 2
      : 3;
  final rounded = double.parse(value.toStringAsFixed(places));
  return _germanNumber.format(rounded);
}

String _date(DateTime value) => DateFormat('dd.MM.yyyy').format(value);

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Text the built-in Helvetica can encode.
///
/// It covers Latin-1 and the Windows-1252 extras (so ä, ß, µ, €, – and ·
/// survive); anything else would print as nothing, which on a medical page
/// is worse than a visible substitute.
String _text(String value) {
  final safe = labPlanPdfSafeText(
    value,
  ).replaceAll('≤', '<=').replaceAll('≥', '>=').replaceAll('→', '->');
  final buffer = StringBuffer();
  for (final rune in safe.runes) {
    buffer.write(
      rune <= 0xFF || _windows1252.contains(rune)
          ? String.fromCharCode(rune)
          : '?',
    );
  }
  return buffer.toString();
}

const _windows1252 = {
  0x20AC, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, 0x02C6, 0x2030, //
  0x0160, 0x2039, 0x0152, 0x017D, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022,
  0x2013, 0x2014, 0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x017E, 0x0178,
};
