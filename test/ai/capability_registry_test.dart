import 'package:flutter_test/flutter_test.dart';
import 'package:super_health/ai/ai_models.dart';

void main() {
  final registry = ProviderCapabilityRegistry();

  test('registry records the documentation audit date', () {
    expect(ProviderCapabilityRegistry.version, '2026-07-18');
  });

  test('documented model families expose only their audited controls', () {
    final cases =
        <
          ({
            AiProvider provider,
            String id,
            List<String> effort,
            int context,
            bool web,
            bool code,
          })
        >[
          (
            provider: AiProvider.openai,
            id: 'gpt-5.6-sol',
            effort: ['none', 'low', 'medium', 'high', 'xhigh', 'max'],
            context: 1050000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.openai,
            id: 'gpt-5.6',
            effort: ['none', 'low', 'medium', 'high', 'xhigh', 'max'],
            context: 1050000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.anthropic,
            id: 'claude-opus-4-8',
            effort: ['low', 'medium', 'high', 'xhigh', 'max'],
            context: 1000000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.anthropic,
            id: 'claude-fable-5',
            effort: ['low', 'medium', 'high', 'xhigh', 'max'],
            context: 1000000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.anthropic,
            id: 'claude-mythos-5',
            effort: ['low', 'medium', 'high', 'xhigh', 'max'],
            context: 1000000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.anthropic,
            id: 'claude-mythos-preview',
            effort: ['low', 'medium', 'high', 'max'],
            context: 1000000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.anthropic,
            id: 'claude-opus-4-7',
            effort: ['low', 'medium', 'high', 'xhigh', 'max'],
            context: 1000000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.anthropic,
            id: 'claude-opus-4-6',
            effort: ['low', 'medium', 'high', 'max'],
            context: 1000000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.anthropic,
            id: 'claude-sonnet-5',
            effort: ['low', 'medium', 'high', 'xhigh', 'max'],
            context: 1000000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.openai,
            id: 'gpt-5.5-2026-04-23',
            effort: ['none', 'low', 'medium', 'high', 'xhigh'],
            context: 1050000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.openai,
            id: 'gpt-5.4-mini',
            effort: ['none', 'low', 'medium', 'high', 'xhigh'],
            context: 400000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.openai,
            id: 'gpt-5.2',
            effort: ['none', 'low', 'medium', 'high', 'xhigh'],
            context: 400000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.openai,
            id: 'gpt-5',
            effort: ['minimal', 'low', 'medium', 'high'],
            context: 400000,
            web: false,
            code: false,
          ),
          (
            provider: AiProvider.anthropic,
            id: 'claude-sonnet-4-6',
            effort: ['low', 'medium', 'high', 'max'],
            context: 1000000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.anthropic,
            id: 'claude-opus-4-5',
            effort: ['low', 'medium', 'high'],
            context: 200000,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.anthropic,
            id: 'claude-sonnet-4-5',
            effort: [],
            context: 200000,
            web: false,
            code: true,
          ),
          (
            provider: AiProvider.anthropic,
            id: 'claude-haiku-4-5',
            effort: [],
            context: 200000,
            web: false,
            code: true,
          ),
          (
            provider: AiProvider.gemini,
            id: 'gemini-3.1-pro-preview',
            effort: ['low', 'medium', 'high'],
            context: 1048576,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.gemini,
            id: 'gemini-3-flash-preview',
            effort: ['minimal', 'low', 'medium', 'high'],
            context: 1048576,
            web: true,
            code: true,
          ),
          (
            provider: AiProvider.gemini,
            id: 'gemini-3.5-flash',
            effort: ['minimal', 'low', 'medium', 'high'],
            context: 1048576,
            web: true,
            code: true,
          ),
        ];

    for (final item in cases) {
      final value = registry.forModel(item.provider, item.id);
      expect(value.reasoningLevels, item.effort, reason: item.id);
      expect(value.contextWindowTokens, item.context, reason: item.id);
      expect(value.webSearch, item.web, reason: item.id);
      expect(value.codeExecution, item.code, reason: item.id);
      if (item.provider == AiProvider.anthropic && item.code) {
        expect(value.losslessContextFile, isTrue, reason: item.id);
      }
    }
  });

  test('unknown, audio/image, and tool-ineligible models fail closed', () {
    final cases = [
      (AiProvider.openai, 'gpt-unlisted'),
      (AiProvider.openai, 'gpt-5.6-sol-2099-01-01'),
      (AiProvider.openai, 'gpt-realtime-2.1'),
      (AiProvider.openai, 'gpt-image-2'),
      (AiProvider.anthropic, 'claude-future-6'),
      (AiProvider.gemini, 'gemini-live-2.5-flash-preview'),
      (AiProvider.gemini, 'gemini-2.5-flash-native-audio-preview'),
      (AiProvider.gemini, 'gemini-3-pro-image-preview'),
      (AiProvider.gemini, 'gemini-3.1-flash-image-preview'),
    ];
    for (final item in cases) {
      final value = registry.forModel(item.$1, item.$2);
      expect(value.reasoningLevels, isEmpty, reason: item.$2);
      expect(value.webSearch, isFalse, reason: item.$2);
      expect(value.codeExecution, isFalse, reason: item.$2);
      expect(value.losslessContextFile, isFalse, reason: item.$2);
      expect(value.structuredOutput, isFalse, reason: item.$2);
      expect(value.contextWindowTokens, isNull, reason: item.$2);
    }
  });

  test('OpenAI GPT-5.6 exposes documented Code Interpreter', () {
    final value = registry.forModel(AiProvider.openai, 'gpt-5.6-sol');
    expect(value.codeExecution, isTrue);
    expect(value.losslessContextFile, isTrue);
  });

  test('OpenAI Pro models retain their documented family exceptions', () {
    for (final id in ['gpt-5.5-pro', 'gpt-5.5-pro-2026-04-23']) {
      final value = registry.forModel(AiProvider.openai, id);
      expect(value.reasoningLevels, ['medium', 'high', 'xhigh'], reason: id);
      expect(value.webSearch, isTrue, reason: id);
      expect(value.codeExecution, isTrue, reason: id);
      expect(value.losslessContextFile, isTrue, reason: id);
      expect(value.structuredOutput, isTrue, reason: id);
    }
    for (final id in ['gpt-5.4-pro', 'gpt-5.4-pro-2026-03-05']) {
      final value = registry.forModel(AiProvider.openai, id);
      expect(value.reasoningLevels, ['medium', 'high', 'xhigh'], reason: id);
      expect(value.webSearch, isTrue, reason: id);
      expect(value.structuredOutput, isFalse, reason: id);
      expect(value.codeExecution, isFalse, reason: id);
      expect(value.losslessContextFile, isFalse, reason: id);
      expect(value.contextWindowTokens, 1050000, reason: id);
    }
    for (final id in ['gpt-5.2-pro', 'gpt-5.2-pro-2025-12-11']) {
      final value = registry.forModel(AiProvider.openai, id);
      expect(value.reasoningLevels, ['medium', 'high', 'xhigh'], reason: id);
      expect(value.webSearch, isFalse, reason: id);
      expect(value.codeExecution, isFalse, reason: id);
      expect(value.losslessContextFile, isFalse, reason: id);
      expect(value.structuredOutput, isFalse, reason: id);
      expect(value.contextWindowTokens, 400000, reason: id);
    }
    for (final id in ['gpt-5-pro', 'gpt-5-pro-2025-10-06']) {
      final value = registry.forModel(AiProvider.openai, id);
      expect(value.reasoningLevels, ['high'], reason: id);
      expect(value.structuredOutput, isTrue, reason: id);
      expect(value.webSearch, isFalse, reason: id);
      expect(value.codeExecution, isFalse, reason: id);
    }
  });

  test('Gemini text families expose their exact audited capabilities', () {
    final cases = <({String id, List<String> effort})>[
      (id: 'gemini-2.5-pro', effort: ['low', 'medium', 'high']),
      (id: 'gemini-2.5-flash', effort: ['low', 'medium', 'high']),
      (id: 'gemini-2.5-flash-lite', effort: ['low', 'medium', 'high']),
      (id: 'gemini-3.1-pro-preview', effort: ['low', 'medium', 'high']),
      (
        id: 'gemini-3-flash-preview',
        effort: ['minimal', 'low', 'medium', 'high'],
      ),
      (
        id: 'gemini-3.1-flash-lite',
        effort: ['minimal', 'low', 'medium', 'high'],
      ),
      (id: 'gemini-3.5-flash', effort: ['minimal', 'low', 'medium', 'high']),
    ];

    for (final item in cases) {
      final value = registry.forModel(AiProvider.gemini, item.id);
      expect(value.reasoningLevels, item.effort, reason: item.id);
      expect(value.webSearch, isTrue, reason: item.id);
      expect(value.codeExecution, isTrue, reason: item.id);
      expect(value.losslessContextFile, isFalse, reason: item.id);
      expect(value.structuredOutput, isTrue, reason: item.id);
      expect(value.contextWindowTokens, 1048576, reason: item.id);
    }
  });
}
