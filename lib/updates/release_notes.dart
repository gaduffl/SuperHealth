const releaseSummaryMaxCharacters = 240;
const releaseSummaryMaxItems = 3;

/// A short, plain-text preview of the release's own notes.
///
/// Our releases have English and German sections. Unsectioned notes from an
/// external update server remain usable, without showing Markdown syntax.
String briefReleaseNotes(String notes, {required String languageCode}) {
  final lines = notes.replaceAll('\r\n', '\n').split('\n');
  final localized = <String, List<String>>{};
  String? section;
  final languageHeading = RegExp(
    r'^##\s+(English|Deutsch)\s*$',
    caseSensitive: false,
  );
  for (final line in lines) {
    final heading = languageHeading.firstMatch(line.trim());
    if (heading != null) {
      section = heading.group(1)!.toLowerCase() == 'deutsch' ? 'de' : 'en';
      localized.putIfAbsent(section, () => []);
    } else if (RegExp(r'^#{1,2}\s').hasMatch(line.trim())) {
      section = null;
    } else if (section != null) {
      localized[section]!.add(line);
    }
  }
  final selected = localized.isEmpty
      ? lines
      : localized[languageCode == 'de' ? 'de' : 'en'] ?? const <String>[];
  final summary = selected
      .where((line) => line.trim().isNotEmpty && !line.trim().startsWith('#'))
      .map((line) {
        var text = line.trim().replaceFirst(
          RegExp(r'^(?:[-*+]\s+|\d+[.)]\s+)'),
          '',
        );
        text = text.replaceAllMapped(
          RegExp(r'\[([^\]]+)\]\([^)]+\)'),
          (match) => match.group(1)!,
        );
        return text.replaceAll(RegExp(r'\*\*|__|`'), '').trim();
      })
      .where((line) => line.isNotEmpty)
      .take(releaseSummaryMaxItems)
      .join('\n');
  if (summary.runes.length <= releaseSummaryMaxCharacters) return summary;
  var prefix = String.fromCharCodes(
    summary.runes.take(releaseSummaryMaxCharacters - 1),
  );
  final boundary = prefix.lastIndexOf(RegExp(r'\s'));
  if (boundary > prefix.length ~/ 2) prefix = prefix.substring(0, boundary);
  return '${prefix.trimRight()}…';
}
