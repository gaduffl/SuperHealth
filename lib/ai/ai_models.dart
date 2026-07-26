enum AiProvider { openai, anthropic, gemini }

class AiModelInfo {
  const AiModelInfo({
    required this.id,
    required this.displayName,
    required this.provider,
    this.createdAt,
    this.description,
  });

  final String id;
  final String displayName;
  final AiProvider provider;
  final DateTime? createdAt;
  final String? description;
}

class ModelCapabilities {
  const ModelCapabilities({
    this.reasoningLevels = const [],
    this.webSearch = false,
    this.codeExecution = false,
    this.losslessContextFile = false,
    this.structuredOutput = false,
    this.contextWindowTokens,
  });

  final List<String> reasoningLevels;
  final bool webSearch;
  final bool codeExecution;
  final bool losslessContextFile;
  final bool structuredOutput;
  final int? contextWindowTokens;
}

class ProviderRequest {
  const ProviderRequest({
    required this.model,
    required this.systemPrompt,
    required this.userPrompt,
    required this.contextJson,
    this.reasoningLevel,
    this.webSearch = false,
    this.codeExecution = false,
    this.maxOutputTokens = 12000,
    this.requireJson = false,
    this.contextFile = false,
    this.contextFileSha256,
  });

  final String model;
  final String systemPrompt;
  final String userPrompt;
  final String contextJson;
  final String? reasoningLevel;
  final bool webSearch;
  final bool codeExecution;
  final int maxOutputTokens;
  final bool requireJson;
  final bool contextFile;
  final String? contextFileSha256;
}

class ProviderResponse {
  const ProviderResponse({
    required this.text,
    required this.raw,
    this.responseId,
    this.citations = const [],
  });

  final String text;
  final Map<String, Object?> raw;
  final String? responseId;
  final List<String> citations;
}

/// Versioned from provider documentation. Unknown models intentionally receive
/// no reasoning/tool controls until their support is known.
class ProviderCapabilityRegistry {
  static const version = '2026-07-18';

  ModelCapabilities forModel(AiProvider provider, String model) =>
      switch (provider) {
        AiProvider.openai => _openAi(model),
        AiProvider.anthropic => _anthropic(model),
        AiProvider.gemini => _gemini(model),
      };

  ModelCapabilities _openAi(String id) {
    if (const {
      'gpt-5.6',
      'gpt-5.6-sol',
      'gpt-5.6-terra',
      'gpt-5.6-luna',
    }.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['none', 'low', 'medium', 'high', 'xhigh', 'max'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        structuredOutput: true,
        contextWindowTokens: 1050000,
      );
    }
    if (const {'gpt-4.1', 'gpt-4.1-mini', 'gpt-4.1-nano'}.contains(id)) {
      return const ModelCapabilities(
        webSearch: true,
        structuredOutput: true,
        contextWindowTokens: 1047576,
      );
    }
    if (const {'o3', 'o3-mini', 'o4-mini'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high'],
        webSearch: true,
        structuredOutput: true,
        contextWindowTokens: 200000,
      );
    }
    if (const {'gpt-5.5', 'gpt-5.5-2026-04-23'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['none', 'low', 'medium', 'high', 'xhigh'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        structuredOutput: true,
        contextWindowTokens: 1050000,
      );
    }
    if (const {'gpt-5.5-pro', 'gpt-5.5-pro-2026-04-23'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['medium', 'high', 'xhigh'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        structuredOutput: true,
        contextWindowTokens: 1050000,
      );
    }
    if (const {'gpt-5.4', 'gpt-5.4-2026-03-05'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['none', 'low', 'medium', 'high', 'xhigh'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        structuredOutput: true,
        contextWindowTokens: 1050000,
      );
    }
    if (const {'gpt-5.4-mini', 'gpt-5.4-nano'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['none', 'low', 'medium', 'high', 'xhigh'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        structuredOutput: true,
        contextWindowTokens: 400000,
      );
    }
    if (const {'gpt-5.4-pro', 'gpt-5.4-pro-2026-03-05'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['medium', 'high', 'xhigh'],
        webSearch: true,
        contextWindowTokens: 1050000,
      );
    }
    if (const {'gpt-5.2', 'gpt-5.2-2025-12-11'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['none', 'low', 'medium', 'high', 'xhigh'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        structuredOutput: true,
        contextWindowTokens: 400000,
      );
    }
    if (id == 'gpt-5.2-codex') {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high', 'xhigh'],
        codeExecution: true,
        losslessContextFile: true,
        structuredOutput: true,
        contextWindowTokens: 400000,
      );
    }
    if (const {'gpt-5.2-pro', 'gpt-5.2-pro-2025-12-11'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['medium', 'high', 'xhigh'],
        contextWindowTokens: 400000,
      );
    }
    if (const {'gpt-5', 'gpt-5-2025-08-07'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['minimal', 'low', 'medium', 'high'],
        structuredOutput: true,
        contextWindowTokens: 400000,
      );
    }
    if (const {'gpt-5-pro', 'gpt-5-pro-2025-10-06'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['high'],
        structuredOutput: true,
        contextWindowTokens: 400000,
      );
    }
    return const ModelCapabilities();
  }

  ModelCapabilities _anthropic(String id) {
    if (const {
      'claude-fable-5',
      'claude-mythos-5',
      'claude-opus-4-8',
      'claude-opus-4-7',
      'claude-sonnet-5',
    }.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high', 'xhigh', 'max'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        contextWindowTokens: 1000000,
      );
    }
    if (id == 'claude-mythos-preview') {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high', 'max'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        contextWindowTokens: 1000000,
      );
    }
    if (const {'claude-opus-4-6', 'claude-sonnet-4-6'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high', 'max'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        contextWindowTokens: 1000000,
      );
    }
    if (const {'claude-opus-4-5', 'claude-opus-4-5-20251101'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        contextWindowTokens: 200000,
      );
    }
    if (const {
      'claude-sonnet-4-5',
      'claude-sonnet-4-5-20250929',
      'claude-haiku-4-5',
      'claude-haiku-4-5-20251001',
    }.contains(id)) {
      return const ModelCapabilities(
        codeExecution: true,
        losslessContextFile: true,
        contextWindowTokens: 200000,
      );
    }
    return const ModelCapabilities();
  }

  ModelCapabilities _gemini(String id) {
    if (id == 'gemini-3.1-pro-preview') {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high'],
        webSearch: true,
        codeExecution: true,
        structuredOutput: true,
        contextWindowTokens: 1048576,
      );
    }
    if (const {
      'gemini-3-flash-preview',
      'gemini-3.1-flash-lite',
    }.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['minimal', 'low', 'medium', 'high'],
        webSearch: true,
        codeExecution: true,
        structuredOutput: true,
        contextWindowTokens: 1048576,
      );
    }
    if (id == 'gemini-3.5-flash') {
      return const ModelCapabilities(
        reasoningLevels: ['minimal', 'low', 'medium', 'high'],
        webSearch: true,
        codeExecution: true,
        structuredOutput: true,
        contextWindowTokens: 1048576,
      );
    }
    if (const {
      'gemini-2.5-pro',
      'gemini-2.5-flash',
      'gemini-2.5-flash-lite',
    }.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high'],
        webSearch: true,
        codeExecution: true,
        structuredOutput: true,
        contextWindowTokens: 1048576,
      );
    }
    return const ModelCapabilities();
  }
}
