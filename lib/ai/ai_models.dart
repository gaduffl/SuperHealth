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
    this.adaptiveThinking = false,
    this.webSearchToolType,
    this.refusalFallback = false,
  });

  final List<String> reasoningLevels;
  final bool webSearch;
  final bool codeExecution;
  final bool losslessContextFile;
  final bool structuredOutput;
  final int? contextWindowTokens;

  /// Anthropic only: the model documents `thinking: {"type": "adaptive"}`.
  /// On Opus 4.7/4.8 omitting the parameter disables thinking entirely, so
  /// supported models always send it instead of coupling it to the effort
  /// selection.
  final bool adaptiveThinking;

  /// Anthropic only: the exact documented server-tool type for web search.
  /// Newer models use the dynamic-filtering variant; older ones the basic
  /// variant. Null when web search is not documented for the model.
  final String? webSearchToolType;

  /// Anthropic only: the model documents the server-side `fallbacks`
  /// parameter, so a safety-classifier refusal is re-served by the
  /// recommended fallback model inside the same call.
  final bool refusalFallback;
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
    this.jsonSchema,
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

  /// Optional JSON schema enforced through provider structured outputs when
  /// [requireJson] is set and the model documents schema-constrained output.
  /// Providers without a schema path fall back to their JSON-mode controls.
  final Map<String, Object?>? jsonSchema;
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
  static const version = '2026-07-29';

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
    // Frontier models with documented server-side refusal fallbacks.
    if (const {
      'claude-fable-5',
      'claude-mythos-5',
      'claude-opus-5',
    }.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high', 'xhigh', 'max'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        structuredOutput: true,
        contextWindowTokens: 1000000,
        adaptiveThinking: true,
        webSearchToolType: 'web_search_20260209',
        refusalFallback: true,
      );
    }
    if (const {'claude-opus-4-8', 'claude-sonnet-5'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high', 'xhigh', 'max'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        structuredOutput: true,
        contextWindowTokens: 1000000,
        adaptiveThinking: true,
        webSearchToolType: 'web_search_20260209',
      );
    }
    // Structured outputs are not documented for Opus 4.7, unlike 4.8.
    if (id == 'claude-opus-4-7') {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high', 'xhigh', 'max'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        contextWindowTokens: 1000000,
        adaptiveThinking: true,
        webSearchToolType: 'web_search_20260209',
      );
    }
    // Mythos Preview predates adaptive thinking and the dynamic-filtering
    // web-search variant; it keeps effort control and the basic search tool.
    if (id == 'claude-mythos-preview') {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high', 'max'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        contextWindowTokens: 1000000,
        webSearchToolType: 'web_search_20250305',
      );
    }
    if (const {'claude-opus-4-6', 'claude-sonnet-4-6'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high', 'max'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        contextWindowTokens: 1000000,
        adaptiveThinking: true,
        webSearchToolType: 'web_search_20260209',
      );
    }
    if (const {'claude-opus-4-5', 'claude-opus-4-5-20251101'}.contains(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high'],
        webSearch: true,
        codeExecution: true,
        losslessContextFile: true,
        structuredOutput: true,
        contextWindowTokens: 200000,
        webSearchToolType: 'web_search_20250305',
      );
    }
    if (const {'claude-haiku-4-5', 'claude-haiku-4-5-20251001'}.contains(id)) {
      return const ModelCapabilities(
        codeExecution: true,
        losslessContextFile: true,
        structuredOutput: true,
        contextWindowTokens: 200000,
      );
    }
    if (const {
      'claude-sonnet-4-5',
      'claude-sonnet-4-5-20250929',
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
