/// Loose, deterministic matching of free-text names against curated vocabularies.
///
/// Medication, supplement and biomarker names are typed by people and pasted
/// from lab reports, so they arrive as "L-Thyroxin Henning 75 µg",
/// "Eisen(II)-fumarat" or "TSH basal (3. Gen.)". Exact comparison would miss
/// every one of those. Matching is on whole words instead, which is loose enough
/// to find the name inside decoration and strict enough that "ass" (aspirin)
/// does not fire inside "Massage".
library;

final _nonWord = RegExp(r'[^a-z0-9äöüß]+');

/// Lower-cases and reduces everything that is not a letter or digit to a single
/// space, so punctuation, hyphens and brackets stop being part of identity.
String foldForMatching(String raw) =>
    raw.toLowerCase().replaceAll(_nonWord, ' ').trim();

/// Whether [phrase] occurs in [text] as a run of whole words.
///
/// Both sides are folded, so callers may pass either raw or folded strings.
bool containsPhrase(String text, String phrase) {
  final folded = foldForMatching(phrase);
  if (folded.isEmpty) return false;
  return ' ${foldForMatching(text)} '.contains(' $folded ');
}

/// Whether some word in [text] starts with [prefix] (itself folded).
///
/// For families spelled as compounds: "eisen" matches "Eisen(II)-fumarat" and
/// "Eisenbisglycinat", "magnesium" matches "Magnesiumcitrat". Multi-word
/// prefixes must start at a word boundary and may run into the next word.
bool containsWordPrefix(String text, String prefix) {
  final folded = foldForMatching(prefix);
  if (folded.isEmpty) return false;
  return ' ${foldForMatching(text)}'.contains(' $folded');
}

/// One curated keyword against free text: `word*` matches any word starting
/// with `word`, anything else must occur as whole words.
///
/// Prefixes are for compounds ("eisen*" for "Eisenbisglycinat"); whole words
/// are for short or ambiguous stems, where a prefix would misfire — "lauf*"
/// would match "Laufnase" (a runny nose) as exercise, "wein*" would match
/// "Weinen" (crying) as alcohol.
bool matchesKeyword(String text, String keyword) => keyword.endsWith('*')
    ? containsWordPrefix(text, keyword.substring(0, keyword.length - 1))
    : containsPhrase(text, keyword);

/// Strips every parenthetical, which on lab reports and labels names a method,
/// a sample type or a salt form ("Ferritin (S)", "Biotin (D-Biotin)") rather
/// than a different thing.
String withoutParentheticals(String raw) =>
    raw.replaceAll(RegExp(r'\([^()]*\)'), ' ').trim();
