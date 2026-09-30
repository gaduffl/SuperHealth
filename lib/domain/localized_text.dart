/// A piece of curated reference text in both app languages.
///
/// Curated data (interaction rules, medication classes) is shown in the UI and
/// has no untranslated fallback path, so every entry carries both languages at
/// the point it is written rather than being translated later.
class LocalizedText {
  const LocalizedText(this.en, this.de);

  final String en;
  final String de;

  String pick({required bool german}) => german ? de : en;
}
