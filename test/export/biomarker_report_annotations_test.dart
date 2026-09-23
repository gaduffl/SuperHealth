import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/domain/entities.dart';
import 'package:super_health/export/biomarker_report_annotations.dart';

void main() {
  final stamp = DateTime(2026, 1, 1);

  HealthDocument report(String id, String comment, {DateTime? date}) =>
      HealthDocument(
        id: id,
        profileId: 'profile',
        fileName: '$id.pdf',
        reportComment: comment,
        documentDate: date,
        labName: 'Labor Muster',
        createdAt: stamp,
        updatedAt: stamp,
      );

  Measurement reading(
    String biomarkerId,
    DateTime takenAt, {
    String? documentId,
    String notes = '',
  }) => Measurement(
    id: '$biomarkerId-${takenAt.toIso8601String()}',
    profileId: 'profile',
    biomarkerId: biomarkerId,
    documentId: documentId,
    takenAt: takenAt,
    value: 1,
    unit: 'mg/dL',
    notes: notes,
    createdAt: stamp,
    updatedAt: stamp,
  );

  test('commented reports are lettered in date order and marked on every '
      'chart they fed', () {
    final january = DateTime(2025, 1, 10, 8);
    final june = DateTime(2025, 6, 3, 9);
    final annotations = annotateBiomarkerExport(
      chartedDays: {
        'glucose': [january, june],
        'tg': [june],
      },
      measurements: [
        reading('glucose', june, documentId: 'june'),
        reading('tg', june, documentId: 'june'),
        reading('glucose', january, documentId: 'january'),
      ],
      documents: [
        report('june', 'Not fasting'),
        report('january', 'Sample haemolysed'),
      ],
    );

    expect(annotations.reports.map((item) => item.letter), ['A', 'B']);
    expect(annotations.reports.first.comment, 'Sample haemolysed');
    expect(annotations.chartFor('glucose').reportLines.map((l) => l.letter), [
      'A',
      'B',
    ]);
    // The same draw carries the same letter on another chart.
    expect(annotations.chartFor('tg').reportLines.single.letter, 'B');
  });

  test('a report without a comment gets no letter', () {
    final day = DateTime(2025, 3, 1);
    final annotations = annotateBiomarkerExport(
      chartedDays: {
        'glucose': [day],
      },
      measurements: [reading('glucose', day, documentId: 'plain')],
      documents: [report('plain', '  ')],
    );

    expect(annotations.reports, isEmpty);
    expect(annotations.chartFor('glucose').reportLines, isEmpty);
  });

  test(
    'a comment from a report that fed only excluded charts is not printed',
    () {
      // Its comment may name the very panel that was left out of the export.
      final day = DateTime(2025, 3, 1);
      final annotations = annotateBiomarkerExport(
        chartedDays: {
          'glucose': [DateTime(2025, 4, 1)],
        },
        measurements: [reading('hiv', day, documentId: 'private')],
        documents: [report('private', 'HIV screen requested')],
      );

      expect(annotations.reports, isEmpty);
      expect(annotations.suppressed, isEmpty);
    },
  );

  test('a withdrawn comment loses its letter and its lines, and the next '
      'report takes the letter', () {
    final first = DateTime(2025, 1, 1);
    final second = DateTime(2025, 2, 1);
    final annotations = annotateBiomarkerExport(
      chartedDays: {
        'glucose': [first, second],
      },
      measurements: [
        reading('glucose', first, documentId: 'one'),
        reading('glucose', second, documentId: 'two'),
      ],
      documents: [report('one', 'Private remark'), report('two', 'Fasting')],
      suppressedDocumentIds: {'one'},
    );

    expect(annotations.reports.single.documentId, 'two');
    expect(annotations.reports.single.letter, 'A');
    expect(annotations.suppressed.single.documentId, 'one');
    expect(annotations.chartFor('glucose').reportLines.single.day, second);
  });

  test('reading notes become per-chart footnotes, one per day, without '
      'repeating the report comment', () {
    final first = DateTime(2025, 1, 1, 8);
    final sameDay = DateTime(2025, 1, 1, 17);
    final later = DateTime(2025, 5, 1);
    final annotations = annotateBiomarkerExport(
      chartedDays: {
        'ferritin': [first, sameDay, later],
      },
      measurements: [
        reading('ferritin', first, notes: 'After iron infusion'),
        reading('ferritin', sameDay, notes: 'After iron infusion'),
        reading('ferritin', sameDay, notes: 'Repeat draw'),
        reading('ferritin', later, documentId: 'may', notes: 'Not fasting'),
      ],
      documents: [report('may', 'Not fasting')],
    );

    final chart = annotations.chartFor('ferritin');
    expect(chart.footnotes, hasLength(1));
    expect(chart.footnotes.single.number, 1);
    expect(chart.footnotes.single.text, 'After iron infusion · Repeat draw');
    expect(chart.footnoteOn(sameDay), 1);
    expect(chart.footnoteOn(later), isNull);
    expect(chart.letterOn(later), 'A');
  });

  test('a reading that is not plotted contributes no note', () {
    final plotted = DateTime(2025, 1, 1);
    final unplotted = DateTime(2025, 2, 1);
    final annotations = annotateBiomarkerExport(
      chartedDays: {
        'tsh': [plotted],
      },
      measurements: [reading('tsh', unplotted, notes: 'Unit unknown')],
      documents: const [],
    );

    expect(annotations.chartFor('tsh').footnotes, isEmpty);
  });

  test('letters continue past Z like spreadsheet columns', () {
    expect(reportLetter(0), 'A');
    expect(reportLetter(25), 'Z');
    expect(reportLetter(26), 'AA');
    expect(reportLetter(27), 'AB');
    expect(reportLetter(52), 'BA');
  });
}
