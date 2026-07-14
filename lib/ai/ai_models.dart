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
    this.structuredOutput = false,
    this.contextWindowTokens,
  });

  final List<String> reasoningLevels;
  final bool webSearch;
  final bool codeExecution;
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
  static const version = '2026-07-14';

  ModelCapabilities forModel(AiProvider provider, String model) =>
      switch (provider) {
        AiProvider.openai => _openAi(model),
        AiProvider.anthropic => _anthropic(model),
        AiProvider.gemini => _gemini(model),
      };

  ModelCapabilities _openAi(String id) {
    if (id.startsWith('gpt-5.6')) {
      return const ModelCapabilities(
        reasoningLevels: ['none', 'low', 'medium', 'high', 'xhigh', 'max'],
        webSearch: true,
        codeExecution: true,
        structuredOutput: true,
        contextWindowTokens: 1050000,
      );
    }
    if (RegExp(r'^gpt-5\.[45]').hasMatch(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['none', 'low', 'medium', 'high', 'xhigh'],
        webSearch: true,
        codeExecution: true,
        structuredOutput: true,
      );
    }
    if (RegExp(r'^(o3|o4)').hasMatch(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high'],
        webSearch: true,
        codeExecution: true,
        structuredOutput: true,
      );
    }
    if (id.startsWith('gpt-')) {
      return const ModelCapabilities(structuredOutput: true);
    }
    return const ModelCapabilities();
  }

  ModelCapabilities _anthropic(String id) {
    final fullEffort = RegExp(
      r'(claude-(fable-5|mythos-5|opus-4-[78]|sonnet-5))',
    ).hasMatch(id);
    if (fullEffort) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high', 'xhigh', 'max'],
        webSearch: true,
        codeExecution: true,
        structuredOutput: true,
      );
    }
    if (RegExp(r'claude-(opus|sonnet)-4-6').hasMatch(id)) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high', 'max'],
        webSearch: true,
        codeExecution: true,
        structuredOutput: true,
      );
    }
    if (id.contains('claude-opus-4-5')) {
      return const ModelCapabilities(
        reasoningLevels: ['low', 'medium', 'high'],
        webSearch: true,
        codeExecution: true,
        structuredOutput: true,
      );
    }
    return const ModelCapabilities();
  }

  ModelCapabilities _gemini(String id) {
    List<String> levels = const [];
    if (id.contains('gemini-3.5-flash') || id.contains('gemini-3-flash')) {
      levels = const ['minimal', 'low', 'medium', 'high'];
    } else if (id.contains('gemini-3.1-pro') ||
        id.contains('gemini-2.5-pro') ||
        id.contains('gemini-2.5-flash')) {
      levels = const ['low', 'medium', 'high'];
    } else if (id.contains('gemini-3-pro')) {
      levels = const ['low', 'high'];
    } else if (id.contains('flash-lite-image')) {
      levels = const ['minimal', 'high'];
    }
    if (id.contains('gemini-3') || id.contains('gemini-2.5')) {
      return ModelCapabilities(
        reasoningLevels: levels,
        webSearch: true,
        codeExecution: true,
        structuredOutput: true,
      );
    }
    return const ModelCapabilities();
  }
}
