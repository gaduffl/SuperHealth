import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/entities.dart';

enum LabPlanExportFormat { pdf, csv, json }

class ExportedFile {
  const ExportedFile({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;
}

class LabPlanExportService {
  Future<ExportedFile> build(LabPlan plan, LabPlanExportFormat format) async =>
      switch (format) {
        LabPlanExportFormat.pdf => _pdf(plan),
        LabPlanExportFormat.csv => _csv(plan),
        LabPlanExportFormat.json => _json(plan),
      };

  String _baseName(LabPlan plan) {
    final date = DateFormat(
      'yyyy-MM-dd',
    ).format(plan.plannedFor ?? plan.createdAt);
    final safeTitle = plan.title
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9äöüß]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return 'superhealth-${safeTitle.isEmpty ? 'lab-plan' : safeTitle}-$date';
  }

  ExportedFile _json(LabPlan plan) {
    final tiers = <String, Object?>{};
    for (final tier in LabTier.values) {
      tiers[tier.name] = {
        'known_total_eur': plan.knownTotal(tier),
        'missing_prices': plan.missingPriceCount(tier),
        'items': plan.itemsThrough(tier).map((item) => item.toMap()).toList(),
      };
    }
    final value = {
      'schema': 'superhealth.lab_plan_export',
      'schema_version': 1,
      'plan': plan.toMap(),
      'tiers_are_cumulative': true,
      'tiers': tiers,
    };
    return ExportedFile(
      fileName: '${_baseName(plan)}.json',
      mimeType: 'application/json',
      bytes: Uint8List.fromList(
        utf8.encode(const JsonEncoder.withIndent('  ').convert(value)),
      ),
    );
  }

  ExportedFile _csv(LabPlan plan) {
    final rows = <List<Object?>>[
      [
        'Tier added',
        'Biomarker',
        'Priority',
        'Evidence',
        'Price EUR',
        'Rationale',
        'Preparation',
      ],
      for (final item in plan.items)
        [
          item.tier.name,
          item.biomarkerName,
          item.priority,
          item.evidenceClass.name,
          item.priceEur,
          item.rationale,
          item.preparation,
        ],
      [],
      ['Cumulative tier', 'Known total EUR', 'Missing prices'],
      for (final tier in LabTier.values)
        [tier.name, plan.knownTotal(tier), plan.missingPriceCount(tier)],
    ];
    return ExportedFile(
      fileName: '${_baseName(plan)}.csv',
      mimeType: 'text/csv',
      bytes: Uint8List.fromList(
        utf8.encode(const ListToCsvConverter().convert(rows)),
      ),
    );
  }

  Future<ExportedFile> _pdf(LabPlan plan) async {
    final document = pw.Document(
      title: plan.title,
      author: 'SuperHealth',
      subject: 'Personal lab visit checklist',
    );
    final planned = plan.plannedFor == null
        ? 'No date set'
        : DateFormat('dd.MM.yyyy').format(plan.plannedFor!);
    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'SuperHealth · ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
          ),
        ),
        build: (context) => [
          pw.Text(
            plan.title,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Text('Planned visit: $planned · Currency: ${plan.currency}'),
          pw.SizedBox(height: 14),
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            color: PdfColors.grey200,
            child: pw.Text(
              'This is a personal planning checklist, not a diagnosis or medical order. '
              'Discuss testing and preparation with a qualified clinician or laboratory.',
              style: const pw.TextStyle(fontSize: 9),
            ),
          ),
          pw.SizedBox(height: 18),
          for (final tier in LabTier.values) ...[
            _tierHeader(plan, tier),
            pw.SizedBox(height: 6),
            ...plan.itemsThrough(tier).map(_pdfItem),
            pw.SizedBox(height: 14),
          ],
        ],
      ),
    );
    return ExportedFile(
      fileName: '${_baseName(plan)}.pdf',
      mimeType: 'application/pdf',
      bytes: await document.save(),
    );
  }

  pw.Widget _tierHeader(LabPlan plan, LabTier tier) {
    final missing = plan.missingPriceCount(tier);
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          _tierLabel(tier),
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Known total: ${plan.knownTotal(tier).toStringAsFixed(2)} EUR'
          '${missing == 0 ? '' : ' + $missing without price'}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ],
    );
  }

  pw.Widget _pdfItem(LabPlanItem item) => pw.Container(
    padding: const pw.EdgeInsets.symmetric(vertical: 5),
    decoration: const pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey300)),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Container(
          width: 12,
          height: 12,
          margin: const pw.EdgeInsets.only(top: 2, right: 8),
          decoration: pw.BoxDecoration(border: pw.Border.all()),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text(
                      item.biomarkerName,
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                  pw.Text(
                    item.priceEur == null
                        ? 'Price missing'
                        : '${item.priceEur!.toStringAsFixed(2)} EUR',
                    style: const pw.TextStyle(fontSize: 9),
                  ),
                ],
              ),
              pw.Text(
                '${item.evidenceClass.name} · ${item.rationale}',
                style: const pw.TextStyle(fontSize: 9),
              ),
              if (item.preparation.isNotEmpty)
                pw.Text(
                  'Preparation: ${item.preparation}',
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey700,
                  ),
                ),
            ],
          ),
        ),
      ],
    ),
  );

  String _tierLabel(LabTier tier) => switch (tier) {
    LabTier.core => 'Core',
    LabTier.advanced => 'Advanced (includes Core)',
    LabTier.comprehensive => 'Comprehensive (includes all)',
  };
}
