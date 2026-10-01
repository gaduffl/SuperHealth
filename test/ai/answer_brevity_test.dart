import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/advisor_service.dart';

void main() {
  const safetyRules = [
    'Do not diagnose.',
    'Flag urgent red-flag symptoms clearly',
    'Never instruct the user to start, stop, or change a prescription '
        'medicine',
    'Surface possible interactions',
  ];
  const boilerplateBans = [
    'No general disclaimers',
    'consult your doctor',
    'not a doctor',
  ];

  group('the advisor prompt', () {
    test('forbids the boilerplate every answer used to carry', () {
      const prompt = AdvisorService.agentSystemPrompt;

      for (final banned in boilerplateBans) {
        expect(prompt, contains(banned));
      }
      expect(prompt, contains('Answer style: short.'));
    });

    test('keeps every safety rule that the boilerplate was not', () {
      // Cutting the disclaimer is a change to what gets *repeated*, not to what
      // gets *said*. If this ever fails, brevity has eaten a safety rule.
      for (final rule in safetyRules) {
        expect(AdvisorService.agentSystemPrompt, contains(rule));
        // The same rules survive the extra brevity of simple mode.
        expect(
          AdvisorService.agentSystemPromptFor(brief: true),
          contains(rule),
        );
      }
    });

    test('only a simple-mode profile gets the plain-language rule', () {
      final plain = AdvisorService.agentSystemPromptFor(brief: false);
      final brief = AdvisorService.agentSystemPromptFor(brief: true);

      expect(plain, AdvisorService.agentSystemPrompt);
      expect(plain, isNot(contains('simple mode')));
      expect(brief, startsWith(AdvisorService.agentSystemPrompt));
      expect(brief, contains('simple mode'));
      expect(brief, contains('under 120 words'));
    });

    test('the advisor is told findings are computed and not exhaustive', () {
      const prompt = AdvisorService.agentSystemPrompt;
      expect(prompt, contains('do not contradict them'));
      expect(prompt, contains('never evidence that no interaction exists'));
      expect(prompt, contains('review_checklist'));
      // Exempt from the length rule, or the review is traded away for brevity.
      expect(prompt, contains("does not count towards the answer's length"));
    });
  });

  group('the lab planner prompt', () {
    test('keeps every safety rule and the boilerplate ban', () {
      // The planner moved off the evidence-package prompt, so the rules that
      // prompt carried have to hold for the one it uses now.
      const prompt = AdvisorService.labPlannerSystemPrompt;
      for (final rule in [...safetyRules, ...boilerplateBans]) {
        expect(prompt, contains(rule));
      }
    });

    test('reads the digest, the tools and an attached package', () {
      const prompt = AdvisorService.labPlannerSystemPrompt;
      expect(prompt, contains('test_catalog'));
      expect(prompt, contains('When tools are offered'));
      // A provider without a tool loop still gets the package, and with it
      // the old reading rules and the integrity stop.
      expect(prompt, contains('attention index'));
      expect(prompt, contains('report the integrity failure'));
      expect(prompt, contains('never evidence that no interaction exists'));
    });

    test('coverage and the receipt are exempt from any length rule', () {
      // Without this the model trades bookkeeping away for brevity, and the
      // plan fails validation instead of being short.
      const prompt = AdvisorService.labPlannerSystemPrompt;
      expect(prompt, contains('coverage'));
      expect(prompt, contains('no length rule applies to them'));
      // A plan is one JSON object; the chat answer-length rule does not fit it.
      expect(prompt, isNot(contains('Answer style: short.')));
    });
  });
}
