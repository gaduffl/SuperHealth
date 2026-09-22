import '../domain/entities.dart';

/// The remarks attached to [biomarkerId] on [day], including the source
/// document's report comment.
///
/// Trend points represent calendar days rather than individual measurements,
/// so every distinct remark for that day belongs in the same tooltip.
String? biomarkerTrendNoteOn({
  required List<Measurement> measurements,
  required List<HealthDocument> documents,
  required String biomarkerId,
  required DateTime day,
}) {
  final notes = <String>[];
  final documentsById = {for (final document in documents) document.id: document};
  for (final measurement in measurements) {
    if (measurement.biomarkerId != biomarkerId) continue;
    final taken = measurement.takenAt;
    if (taken.year != day.year ||
        taken.month != day.month ||
        taken.day != day.day) {
      continue;
    }
    final note = measurement.notes.trim();
    if (note.isNotEmpty && !notes.contains(note)) notes.add(note);
    final documentNote = documentsById[measurement.documentId]?.reportComment
        .trim();
    if (documentNote != null &&
        documentNote.isNotEmpty &&
        !notes.contains(documentNote)) {
      notes.add(documentNote);
    }
  }
  return notes.isEmpty ? null : notes.join(' · ');
}
