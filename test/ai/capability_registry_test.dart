import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/ai_models.dart';

void main() {
  final registry = ProviderCapabilityRegistry();

  test('unknown models receive no speculative controls', () {
    final value = registry.forModel(AiProvider.openai, 'future-model-unknown');
    expect(value.reasoningLevels, isEmpty);
    expect(value.webSearch, isFalse);
    expect(value.codeExecution, isFalse);
  });

  test('documented Gemini model exposes only documented reasoning levels', () {
    final value = registry.forModel(
      AiProvider.gemini,
      'gemini-3.1-pro-preview',
    );
    expect(value.reasoningLevels, ['low', 'medium', 'high']);
    expect(value.webSearch, isTrue);
    expect(value.codeExecution, isTrue);
  });

  test('generic GPT models do not get speculative hosted tools', () {
    final value = registry.forModel(AiProvider.openai, 'gpt-unlisted');
    expect(value.structuredOutput, isTrue);
    expect(value.webSearch, isFalse);
    expect(value.codeExecution, isFalse);
  });
}
