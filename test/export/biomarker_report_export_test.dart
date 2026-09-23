import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/biomarker_report_export_service.dart';

void main() {
  final stamp = DateTime(2026, 1, 1);
  final profile = Profile(
    id: 'profile',
    displayName: 'Alex Beispiel',
    dateOfBirth: DateTime(1980, 4, 2),
    createdAt: stamp,
    updatedAt: stamp,
  );

  Biomarker marker(String id, String name, String category, String unit) =>
      Biomarker(
        id: id,
        canonicalName: id,
        displayName: name,
        category: category,
        defaultUnit: unit,
        createdAt: stamp,
        updatedAt: stamp,
      );

  BiomarkerReferenceRange range(String id, String unit, double lo, double hi) =>
      BiomarkerReferenceRange(
        id: '$id-range',
        biomarkerId: id,
        rangeType: 'reference',
        unit: unit,
        low: lo,
        high: hi,
        createdAt: stamp,
        updatedAt: stamp,
      );

  HealthDocument report(String id, DateTime date, String comment) =>
      HealthDocument(
        id: id,
        profileId: 'profile',
        fileName: '$id.pdf',
        documentDate: date,
        labName: 'Labor Muster',
        reportComment: comment,
        createdAt: stamp,
        updatedAt: stamp,
      );

  final draws = [
    (DateTime(2024, 2, 2), 'feb'),
    (DateTime(2024, 9, 11), 'sep'),
    (DateTime(2025, 3, 14), 'mar'),
    (DateTime(2025, 10, 20), 'oct'),
  ];
  final series = {
    'ferritin': [28.0, 95.0, 412.0, 180.0],
    'glucose': [92.0, 118.0, 97.0, 101.0],
    'tg': [140.0, 210.0, 120.0, 110.0],
    'psa': [0.8, 0.9, 1.1, 1.0],
    'tsh': [2.1, 3.9, 4.6, 2.8],
  };
  final units = {
    'ferritin': 'ng/mL',
    'glucose': 'mg/dL',
    'tg': 'mg/dL',
    'psa': 'ng/mL',
    'tsh': 'mIU/L',
  };
  final biomarkers = [
    marker('ferritin', 'Ferritin', 'metabolic', 'ng/mL'),
    marker('glucose', 'Glukose (nüchtern)', 'metabolic', 'mg/dL'),
    marker('tg', 'Triglyceride', 'metabolic', 'mg/dL'),
    marker('psa', 'PSA gesamt', 'tumor_markers', 'ng/mL'),
    marker('tsh', 'TSH', 'thyroid', 'mIU/L'),
  ];
  final measurements = [
    for (final entry in series.entries)
      for (var index = 0; index < draws.length; index++)
        Measurement(
          id: '${entry.key}-$index',
          profileId: 'profile',
          biomarkerId: entry.key,
          documentId: draws[index].$2,
          takenAt: draws[index].$1,
          value: entry.value[index],
          unit: units[entry.key]!,
          notes: entry.key == 'ferritin' && index == 2
              ? 'Zwei Tage nach Eiseninfusion'
              : '',
          createdAt: stamp,
          updatedAt: stamp,
        ),
  ];
  final documents = [
    report('feb', DateTime(2024, 2, 2), 'Probe hämolytisch'),
    report('sep', DateTime(2024, 9, 11), 'Nicht nüchtern (8 h)'),
    report('mar', DateTime(2025, 3, 14), ''),
    report('oct', DateTime(2025, 10, 20), 'Enthält Hinweis auf PSA-Kontrolle'),
  ];
  final ranges = [
    range('ferritin', 'ng/mL', 30, 400),
    range('glucose', 'mg/dL', 70, 100),
    range('tg', 'mg/dL', 0, 150),
    range('psa', 'ng/mL', 0, 4),
    range('tsh', 'mIU/L', 0.4, 4.0),
  ];

  BiomarkerReportRequest request({
    Set<String> excluded = const {},
    Set<String> suppressed = const {},
    bool valueTables = true,
  }) => buildBiomarkerReportRequest(
    profile: profile,
    biomarkers: biomarkers,
    measurements: measurements,
    documents: documents,
    targets: const [],
    referenceRanges: ranges,
    categoryTitle: (category) => category,
    excludedCategories: excluded,
    suppressedDocumentIds: suppressed,
    valueTables: valueTables,
    now: DateTime(2026, 9, 23),
  );

  test('excluding a category removes its charts and names it as missing', () {
    final built = request(excluded: {'tumor_markers'});

    expect(
      built.sections.map((section) => section.category),
      isNot(contains('tumor_markers')),
    );
    expect(built.excludedCategoryTitles, ['tumor_markers']);
    // The October report still fed other charts, so its comment remains
    // available to print; the owner withdraws it in the export dialog.
    expect(built.annotations.reports.map((item) => item.documentId), [
      'feb',
      'sep',
      'oct',
    ]);
  });

  test('the export draws a German PDF with every included chart', () async {
    final file = await BiomarkerReportExportService().build(request());

    expect(file.fileName, 'biomarker-verlauf-2026-09-23.pdf');
    expect(file.mimeType, 'application/pdf');
    expect(ascii.decode(file.bytes.sublist(0, 5)), '%PDF-');
    final out = Platform.environment['BIOMARKER_REPORT_PDF'];
    if (out != null) await File(out).writeAsBytes(file.bytes);
  });

  test(
    'a biomarker with more readings than the table holds still exports',
    () async {
      final many = [
        for (var index = 0; index < 45; index++)
          Measurement(
            id: 'glucose-many-$index',
            profileId: 'profile',
            biomarkerId: 'glucose',
            takenAt: DateTime(2022, 1, 1).add(Duration(days: 20 * index)),
            value: 90 + index % 7,
            unit: 'mg/dL',
            createdAt: stamp,
            updatedAt: stamp,
          ),
      ];
      final built = buildBiomarkerReportRequest(
        profile: profile,
        biomarkers: biomarkers,
        measurements: many,
        documents: const [],
        targets: const [],
        referenceRanges: ranges,
        categoryTitle: (category) => category,
        now: DateTime(2026, 9, 23),
      );

      final file = await BiomarkerReportExportService().build(built);
      expect(file.bytes, isNotEmpty);
    },
  );
}
