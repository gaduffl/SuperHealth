import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/answer_text.dart';

void main() {
  test('a parenthesised list of references leaves no wreckage', () {
    // Verbatim from a real verification warning. Deleting the references alone
    // would leave "( ; )" mid-sentence, which reads worse than they did.
    const source =
        'Die Auslassung von TSH bleibt klinisch relevant '
        '(documents:legacy-281f4bd36ea82d3de69282657d93796e; '
        'documents:legacy-9048775bed8c6d8ca0f7d3fda22925c3).';

    expect(
      withoutRecordReferences(source),
      'Die Auslassung von TSH bleibt klinisch relevant.',
    );
  });

  test('uuid references go too', () {
    const source =
        'Palpitationen sind belegt '
        '(health_events:426d3f97-f308-464a-96ab-7dec515a63b1; '
        'health_events:6ef6bd4a-fcfc-4320-a518-d9691e6b74d3).';

    expect(withoutRecordReferences(source), 'Palpitationen sind belegt.');
  });

  test('a reference mid-sentence does not eat the sentence', () {
    const source =
        'Der letzte Wert measurements:legacy-627e46b9df34d96f7d50442002d94674 '
        'war unauffällig.';

    expect(withoutRecordReferences(source), 'Der letzte Wert war unauffällig.');
  });

  test('prose that merely contains a colon is untouched', () {
    // The id shape is the whole safety argument: without it, a rule like
    // "word:word" would eat ordinary writing.
    const source =
        'Hinweis: 12 mg pro Tag. Siehe https://example.com/a:b für Details. '
        'Verhältnis 3:1, Referenz: unauffällig.';

    expect(withoutRecordReferences(source), source);
  });

  test('a markdown link survives intact', () {
    const source = 'See [the guideline](https://example.com/lp-a) for context.';

    expect(withoutRecordReferences(source), source);
  });

  test('markdown structure is preserved', () {
    // The text is rendered as markdown, so the cleanup must not disturb list
    // markers, headings or emphasis.
    const source =
        '## Befunde\n\n'
        '- **Lp(a)** deutlich erhöht (measurements:legacy-abc12345def67890).\n'
        '- Ferritin normal.\n';

    expect(
      withoutRecordReferences(source),
      '## Befunde\n\n- **Lp(a)** deutlich erhöht.\n- Ferritin normal.',
    );
  });

  test('a line that was only a reference collapses to nothing', () {
    expect(
      withoutRecordReferences('measurements:legacy-abc12345def67890'),
      isEmpty,
    );
  });

  test('square brackets are cleaned like round ones', () {
    const source = 'Ergebnis stabil [measurements:legacy-abc12345def67890].';

    expect(withoutRecordReferences(source), 'Ergebnis stabil.');
  });

  test('empty text stays empty', () {
    expect(withoutRecordReferences(''), '');
  });

  test('several references in one bracket collapse together', () {
    const source =
        'Die Katalogeinträge beweisen keine aktuelle Einnahme '
        '(conditions_medications_goals_history:ec02feb5-c847-4e36-b54c-247ef84ec862; '
        'supplements:legacy-30efdcd7a5443e601bca63f16f47184f; '
        'supplements:legacy-ccb020d1d87f1ea353fe7f711e9a1615).';

    expect(
      withoutRecordReferences(source),
      'Die Katalogeinträge beweisen keine aktuelle Einnahme.',
    );
  });
}
