/// Cleans model prose of the bookkeeping it was asked to produce.
///
/// The system prompts tell the model to "reference important source rows as
/// section:id", and that instruction earns its place: it forces the model to
/// point at a row that exists rather than assert from memory. The *reader*
/// gains nothing from `measurements:legacy-f28b9d8954ad02871d43f0de33c9f6cf` —
/// it is a primary key in a private database, not something anyone can look up
/// — and a paragraph carrying four of them is hard to read.
///
/// So the reference is still demanded, and removed once it has done its work.
library;

/// A `section:id` reference, as the prompts ask for them.
///
/// The id shape is what makes this safe to run over arbitrary prose: it matches
/// only a `legacy-` hex key or a full UUID, so ordinary text containing a colon
/// — `Note: 12 mg`, `https://example.com` — cannot be caught by it.
final _recordReference = RegExp(
  r'\b[a-z][a-z0-9_]*:'
  r'(?:legacy-[0-9a-f]{8,}|'
  r'[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})\b',
);

/// A bracketed group left holding nothing but separators.
final _emptyBrackets = RegExp(r'[(\[]\s*[;,§\s]*\s*[)\]]');

/// Separators that piled up where references were removed.
final _danglingSeparators = RegExp(r'([(\[])\s*[;,]\s*|\s*[;,]\s*([)\]])');

final _spaceBeforePunctuation = RegExp(r'\s+([,.;:!?)\]])');
final _repeatedSpaces = RegExp(r'[ \t]{2,}');
final _blankLinePileUp = RegExp(r'\n{3,}');

/// Removes `section:id` references and tidies what they leave behind.
///
/// Deleting the reference alone is not enough: they arrive in parenthesised
/// lists — `(measurements:legacy-abc…; health_events:1234…)` — and removing
/// the contents leaves `( ; )` sitting in the middle of a sentence, which reads
/// worse than the reference did.
String withoutRecordReferences(String text) {
  if (text.isEmpty) return text;
  var result = text.replaceAll(_recordReference, '');
  // Repeated because removing one empty group can expose another around it.
  for (var pass = 0; pass < 3; pass++) {
    final before = result;
    result = result
        .replaceAllMapped(
          _danglingSeparators,
          (match) => match.group(1) ?? match.group(2) ?? '',
        )
        .replaceAll(_emptyBrackets, '');
    if (result == before) break;
  }
  return result
      .replaceAll(_repeatedSpaces, ' ')
      .replaceAllMapped(_spaceBeforePunctuation, (match) => match.group(1)!)
      .replaceAll(_blankLinePileUp, '\n\n')
      .trim();
}
