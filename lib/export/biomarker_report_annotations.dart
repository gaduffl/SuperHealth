import '../domain/entities.dart';

/// A lab report whose comment is printed, under the letter that marks it on
/// every chart it contributed to.
class ReportMark {
  const ReportMark({
    required this.letter,
    required this.documentId,
    required this.date,
    required this.comment,
    this.labName,
  });

  final String letter;
  final String documentId;
  final DateTime date;
  final String comment;
  final String? labName;
}

/// Notes attached to single readings on one chart day, printed as a numbered
/// footnote under that chart.
class PointFootnote {
  const PointFootnote({
    required this.number,
    required this.day,
    required this.text,
  });

  final int number;
  final DateTime day;
  final String text;
}

class ChartAnnotations {
  const ChartAnnotations({
    this.reportLines = const [],
    this.footnotes = const [],
  });

  /// Where a lettered report falls on this chart. Only reports that gave this
  /// biomarker a value are drawn, so a line always sits on a real point.
  final List<({String letter, DateTime day})> reportLines;

  final List<PointFootnote> footnotes;

  int? footnoteOn(DateTime day) {
    for (final footnote in footnotes) {
      if (_sameDay(footnote.day, day)) return footnote.number;
    }
    return null;
  }

  String? letterOn(DateTime day) {
    final letters = [
      for (final line in reportLines)
        if (_sameDay(line.day, day)) line.letter,
    ];
    return letters.isEmpty ? null : letters.join(',');
  }
}

class BiomarkerExportAnnotations {
  const BiomarkerExportAnnotations({
    required this.reports,
    required this.suppressed,
    required this.charts,
  });

  /// Lettered reports, in date order.
  final List<ReportMark> reports;

  /// Reports whose comment would be printed but was switched off. They carry
  /// no letter; they are returned so the export dialog can offer them again.
  final List<ReportMark> suppressed;

  final Map<String, ChartAnnotations> charts;

  ChartAnnotations chartFor(String biomarkerId) =>
      charts[biomarkerId] ?? const ChartAnnotations();
}

/// Links lab-report comments and reading notes to the points of the charts
/// being exported.
///
/// Two kinds of note, two kinds of mark. A report comment is about the whole
/// blood draw ("not fasting"), so it gets one letter for the whole document —
/// the same letter on every chart that report fed — and is explained once. A
/// reading's own note is about that one value, so it gets a footnote number
/// under that chart. Paper has no tooltip; a doctor has to be able to tell
/// "about the draw" from "about this value" at a glance.
///
/// Only reports that gave a value to an exported chart are lettered: a comment
/// can name a panel whose category was deliberately left out of the export.
/// [suppressedDocumentIds] withdraws a comment entirely, letter and lines too,
/// so nothing points at an explanation that is not on the page.
///
/// [chartedDays] names, per exported biomarker, the days it has a plotted
/// point. A reading that could not be converted onto the chart's unit is not
/// plotted, so its notes have no point to attach to and are left out.
BiomarkerExportAnnotations annotateBiomarkerExport({
  required Map<String, List<DateTime>> chartedDays,
  required List<Measurement> measurements,
  required List<HealthDocument> documents,
  Set<String> suppressedDocumentIds = const {},
}) {
  final documentsById = {for (final item in documents) item.id: item};
  final charted = <Measurement>[
    for (final measurement in measurements)
      if (chartedDays[measurement.biomarkerId]?.any(
            (day) => _sameDay(day, measurement.takenAt),
          ) ==
          true)
        measurement,
  ]..sort((a, b) => a.takenAt.compareTo(b.takenAt));

  final firstReading = <String, DateTime>{};
  for (final measurement in charted) {
    final document = documentsById[measurement.documentId];
    if (document == null || document.reportComment.trim().isEmpty) continue;
    firstReading.putIfAbsent(document.id, () => measurement.takenAt);
  }
  final commented =
      [
        for (final entry in firstReading.entries)
          (
            document: documentsById[entry.key]!,
            date: _day(documentsById[entry.key]!.documentDate ?? entry.value),
          ),
      ]..sort((a, b) {
        final byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.document.id.compareTo(b.document.id);
      });

  final reports = <ReportMark>[];
  final suppressed = <ReportMark>[];
  for (final entry in commented) {
    final isSuppressed = suppressedDocumentIds.contains(entry.document.id);
    final mark = ReportMark(
      letter: isSuppressed ? '' : reportLetter(reports.length),
      documentId: entry.document.id,
      date: entry.date,
      comment: entry.document.reportComment.trim(),
      labName: entry.document.labName?.trim().isEmpty == true
          ? null
          : entry.document.labName?.trim(),
    );
    (isSuppressed ? suppressed : reports).add(mark);
  }
  final letterByDocument = {
    for (final report in reports) report.documentId: report.letter,
  };

  final charts = <String, ChartAnnotations>{};
  for (final biomarkerId in chartedDays.keys) {
    final readings = charted.where((item) => item.biomarkerId == biomarkerId);
    final lines = <({String letter, DateTime day})>[];
    final notesByDay = <DateTime, List<String>>{};
    for (final reading in readings) {
      final day = _day(reading.takenAt);
      final document = documentsById[reading.documentId];
      final letter = letterByDocument[reading.documentId];
      if (letter != null &&
          !lines.any((line) => line.letter == letter && line.day == day)) {
        lines.add((letter: letter, day: day));
      }
      final note = reading.notes.trim();
      // A note that repeats its report's comment is already said by the
      // letter, or was deliberately withdrawn with it.
      if (note.isEmpty || note == document?.reportComment.trim()) continue;
      final notes = notesByDay.putIfAbsent(day, () => []);
      if (!notes.contains(note)) notes.add(note);
    }
    final days = notesByDay.keys.toList()..sort();
    charts[biomarkerId] = ChartAnnotations(
      reportLines: lines,
      footnotes: [
        for (var index = 0; index < days.length; index++)
          PointFootnote(
            number: index + 1,
            day: days[index],
            text: notesByDay[days[index]]!.join(' · '),
          ),
      ],
    );
  }
  return BiomarkerExportAnnotations(
    reports: reports,
    suppressed: suppressed,
    charts: charts,
  );
}

/// A, B, … Z, then AA, AB, … — spreadsheet columns, so the order stays
/// readable past twenty-six reports.
String reportLetter(int index) {
  var remaining = index;
  var letters = '';
  do {
    letters = String.fromCharCode(65 + remaining % 26) + letters;
    remaining = remaining ~/ 26 - 1;
  } while (remaining >= 0);
  return letters;
}

DateTime _day(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool _sameDay(DateTime a, DateTime b) => _day(a) == _day(b);
