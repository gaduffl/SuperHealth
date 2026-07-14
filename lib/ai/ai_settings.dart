import 'package:shared_preferences/shared_preferences.dart';

import 'ai_models.dart';

enum AiTask { advisor, parsing }

class AiTaskSettings {
  const AiTaskSettings({
    required this.provider,
    required this.model,
    this.reasoningLevel,
    this.webSearch = false,
    this.codeExecution = false,
  });

  final AiProvider provider;
  final String model;
  final String? reasoningLevel;
  final bool webSearch;
  final bool codeExecution;

  AiTaskSettings copyWith({
    AiProvider? provider,
    String? model,
    String? reasoningLevel,
    bool clearReasoningLevel = false,
    bool? webSearch,
    bool? codeExecution,
  }) => AiTaskSettings(
    provider: provider ?? this.provider,
    model: model ?? this.model,
    reasoningLevel: clearReasoningLevel
        ? null
        : reasoningLevel ?? this.reasoningLevel,
    webSearch: webSearch ?? this.webSearch,
    codeExecution: codeExecution ?? this.codeExecution,
  );
}

class AiSettingsStore {
  Future<AiTaskSettings?> load(AiTask task) async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = 'ai_${task.name}_';
    final providerName = preferences.getString('${prefix}provider');
    final model = preferences.getString('${prefix}model');
    if (providerName == null || model == null || model.isEmpty) return null;
    final provider = AiProvider.values.where(
      (item) => item.name == providerName,
    );
    if (provider.isEmpty) return null;
    return AiTaskSettings(
      provider: provider.first,
      model: model,
      reasoningLevel: preferences.getString('${prefix}reasoning'),
      webSearch: preferences.getBool('${prefix}web') ?? false,
      codeExecution: preferences.getBool('${prefix}code') ?? false,
    );
  }

  Future<void> save(AiTask task, AiTaskSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    final prefix = 'ai_${task.name}_';
    await Future.wait([
      preferences.setString('${prefix}provider', settings.provider.name),
      preferences.setString('${prefix}model', settings.model),
      preferences.setBool('${prefix}web', settings.webSearch),
      preferences.setBool('${prefix}code', settings.codeExecution),
      if (settings.reasoningLevel == null)
        preferences.remove('${prefix}reasoning')
      else
        preferences.setString('${prefix}reasoning', settings.reasoningLevel!),
    ]);
  }
}
