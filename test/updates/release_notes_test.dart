import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/updates/release_notes.dart';

const _localized = '''
# 0.51.0+87

## English
- Faster charts.
- More reliable reminders.

## Deutsch
- Schnellere Diagramme.
- Zuverlässigere Erinnerungen.
''';

void main() {
  test('the summary contains only the requested language', () {
    expect(
      briefReleaseNotes(_localized, languageCode: 'en'),
      'Faster charts.\nMore reliable reminders.',
    );
    expect(
      briefReleaseNotes(_localized, languageCode: 'de'),
      'Schnellere Diagramme.\nZuverlässigere Erinnerungen.',
    );
  });

  test('plain and Markdown notes from an update server stay readable', () {
    expect(
      briefReleaseNotes('Faster charts', languageCode: 'en'),
      'Faster charts',
    );
    expect(
      briefReleaseNotes(
        '# Release\n- **Faster charts**\n1. Fixed `reminders`\n- [Details](https://example.org)',
        languageCode: 'en',
      ),
      'Faster charts\nFixed reminders\nDetails',
    );
  });

  test('missing notes or a missing translation stay missing', () {
    expect(briefReleaseNotes(' \n ', languageCode: 'de'), isEmpty);
    expect(
      briefReleaseNotes('## English\n- Faster charts.', languageCode: 'de'),
      isEmpty,
    );
  });

  test('long notes are bounded and mark the shortened preview', () {
    final notes = List.filled(100, 'A useful improvement.').join(' ');
    final summary = briefReleaseNotes(notes, languageCode: 'en');
    expect(
      summary.runes.length,
      lessThanOrEqualTo(releaseSummaryMaxCharacters),
    );
    expect(summary, endsWith('…'));
    expect(summary, startsWith('A useful improvement.'));
  });

  test('shortening notes does not split a Unicode code point', () {
    final summary = briefReleaseNotes(
      List.filled(300, '😀').join(),
      languageCode: 'en',
    );
    expect(summary.runes.length, releaseSummaryMaxCharacters);
    expect(summary, endsWith('…'));
    expect(summary, isNot(contains('\uFFFD')));
  });

  test('only the first three change items are previewed', () {
    expect(
      briefReleaseNotes('- One\n- Two\n- Three\n- Four', languageCode: 'en'),
      'One\nTwo\nThree',
    );
  });

  test(
    'the published notes match this version and are brief in both languages',
    () {
      final notes = File('RELEASE_NOTES.md').readAsStringSync();
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final version = RegExp(
        r'^version: (.+)$',
        multiLine: true,
      ).firstMatch(pubspec)!.group(1)!;
      expect(notes.split('\n').first, '# $version');
      final headings = RegExp(
        r'^## (English|Deutsch)$',
        multiLine: true,
      ).allMatches(notes).toList();
      expect(headings.map((heading) => heading.group(1)), [
        'English',
        'Deutsch',
      ]);
      for (var index = 0; index < headings.length; index++) {
        final section = notes.substring(
          headings[index].end,
          index + 1 < headings.length
              ? headings[index + 1].start
              : notes.length,
        );
        final items = section
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .toList();
        expect(items.length, inInclusiveRange(1, releaseSummaryMaxItems));
        expect(items.every((item) => item.startsWith('- ')), isTrue);
        final text = items.map((item) => item.substring(2)).join('\n');
        expect(
          text.runes.length,
          lessThanOrEqualTo(releaseSummaryMaxCharacters),
        );
        expect(
          briefReleaseNotes(notes, languageCode: index == 0 ? 'en' : 'de'),
          text,
        );
      }
    },
  );
}
