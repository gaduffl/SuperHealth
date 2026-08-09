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

/// One prior conversation turn, delivered to providers as a native chat
/// message instead of serialized transcript text.
class ProviderChatMessage {
  const ProviderChatMessage({required this.role, required this.content});

  /// Either `user` or `assistant`.
  final String role;
  final String content;
}

class ProviderRequest {
  const ProviderRequest({
    required this.model,
    required this.systemPrompt,
    required this.userPrompt,
    required this.contextJson,
    this.history = const [],
    this.reasoningLevel,
    this.webSearch = false,
    this.codeExecution = false,
    this.maxOutputTokens = 12000,
    this.requireJson = false,
    this.jsonSchema,
    this.contextFile = false,
    this.contextFileSha256,
    this.promptCacheKey,
  });

  final String model;
  final String systemPrompt;
  final String userPrompt;
  final String contextJson;

  /// Prior turns in order. The current question stays in [userPrompt];
  /// providers place history between the stable context and the prompt.
  final List<ProviderChatMessage> history;
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

  /// Routes calls that share a prompt prefix to the same provider-side cache.
  ///
  /// Automatic prefix caching is best effort and misses when consecutive calls
  /// land on different machines. A lab plan makes two calls over the same
  /// ~800k-token context minutes apart, so a miss costs a second full prefill —
  /// measured at four and a half minutes. Callers pass the same key for every
  /// call in one logical run.
  final String? promptCacheKey;
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

  /// What the provider says the exchange actually cost in tokens.
  ///
  /// Read from [raw] rather than plumbed through each client, because all
  /// three report it in their own response body and none of them needs to know
  /// the app is looking.
  TokenUsage? get usage => TokenUsage.fromResponse(raw);
}

/// Tokens a single exchange consumed, as reported by the provider.
///
/// Reported, not estimated: the app's own pre-flight figure is a byte-based
/// approximation, and showing a guess next to a real number invites treating
/// both as equally solid.
class TokenUsage {
  const TokenUsage({this.inputTokens, this.outputTokens});

  final int? inputTokens;
  final int? outputTokens;

  bool get isEmpty => inputTokens == null && outputTokens == null;

  int? get totalTokens => inputTokens == null && outputTokens == null
      ? null
      : (inputTokens ?? 0) + (outputTokens ?? 0);

  /// Reads the three provider shapes: OpenAI Responses and Anthropic Messages
  /// both nest `usage`, with OpenAI additionally using the older
  /// prompt/completion naming on some endpoints; Gemini reports
  /// `usageMetadata` with its own key names.
  static TokenUsage? fromResponse(Map<String, Object?> raw) {
    int? read(Object? node, List<String> keys) {
      if (node is! Map) return null;
      for (final key in keys) {
        final value = node[key];
        if (value is int) return value;
        if (value is num) return value.toInt();
      }
      return null;
    }

    final usage = raw['usage'];
    final metadata = raw['usageMetadata'];
    final input =
        read(usage, const ['input_tokens', 'prompt_tokens']) ??
        read(metadata, const ['promptTokenCount']);
    final output =
        read(usage, const ['output_tokens', 'completion_tokens']) ??
        read(metadata, const ['candidatesTokenCount']);
    if (input == null && output == null) return null;
    return TokenUsage(inputTokens: input, outputTokens: output);
  }
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
