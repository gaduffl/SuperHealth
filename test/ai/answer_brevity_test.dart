import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/advisor_service.dart';

void main() {
  group('the advisor prompt', () {
    test('forbids the boilerplate every answer used to carry', () {
      const prompt = AdvisorService.systemPrompt;

      for (final banned in [
        'No general disclaimers',
        'consult your doctor',
        'not a doctor',
      ]) {
        expect(prompt, contains(banned));
      }
      expect(prompt, contains('Answer style: short.'));
    });

    test('keeps every safety rule that the boilerplate was not', () {
      // Cutting the disclaimer is a change to what gets *repeated*, not to what
      // gets *said*. If this ever fails, brevity has eaten a safety rule.
      const prompt = AdvisorService.systemPrompt;

      expect(prompt, contains('Do not diagnose.'));
      expect(prompt, contains('Flag urgent red-flag symptoms clearly'));
      expect(
        prompt,
        contains(
          'Never instruct the user to start, stop, or change a '
          'prescription medicine',
        ),
      );
      expect(prompt, contains('Surface possible interactions'));
      // The same rules survive the extra brevity of simple mode.
      final brief = AdvisorService.systemPromptFor(brief: true);
      expect(brief, contains('Do not diagnose.'));
      expect(brief, contains('Flag urgent red-flag symptoms clearly'));
    });

    test('only a simple-mode profile gets the plain-language rule', () {
      final plain = AdvisorService.systemPromptFor(brief: false);
      final brief = AdvisorService.systemPromptFor(brief: true);

      expect(plain, AdvisorService.systemPrompt);
      expect(plain, isNot(contains('simple mode')));
      expect(brief, startsWith(AdvisorService.systemPrompt));
      expect(brief, contains('simple mode'));
      expect(brief, contains('under 120 words'));
    });

    test('the coverage receipt is exempt from the length rule', () {
      // Without this the model trades the receipt away for brevity, and every
      // answer fails validation instead of being short.
      expect(
        AdvisorService.systemPrompt,
        contains('does not count towards its length'),
      );
    });
  });
}
