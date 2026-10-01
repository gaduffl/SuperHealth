import '../app/app_localizations.dart';

/// How a record lookup reads on a progress line, in the reader's language.
///
/// Shared by the advisor and the lab planner, because both run the same
/// on-device tools and a lookup should not be named two ways. An unknown
/// name falls through unchanged rather than disappearing: a lookup nobody can
/// read is still evidence that work is happening.
String recordLookupLabel(
  AppLocalizations strings,
  String toolName,
) => switch (toolName) {
  'biomarker_history' => strings.pick('biomarker history', 'Biomarker-Verlauf'),
  'lab_report' => strings.pick('lab report', 'Laborbefund'),
  'supplement_details' => strings.pick('product details', 'Produktdetails'),
  'supplement_intakes' => strings.pick('logged doses', 'erfasste Einnahmen'),
  'exposure_before' => strings.pick(
    'what was taken before a draw',
    'Einnahmen vor einer Blutabnahme',
  ),
  'health_events' => strings.pick('symptoms and tags', 'Symptome und Tags'),
  'search_records' => strings.pick('search', 'Suche'),
  'biomarker_catalog' => strings.pick('test catalog', 'Testkatalog'),
  _ => toolName,
};

/// The distinct lookups of one round, named for the reader.
String recordLookupSummary(AppLocalizations strings, List<String> toolNames) =>
    {for (final name in toolNames) recordLookupLabel(strings, name)}.join(', ');
