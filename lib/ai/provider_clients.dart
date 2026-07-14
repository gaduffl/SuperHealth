import 'dart:convert';

import 'package:dio/dio.dart';

import 'ai_models.dart';

class AiProviderException implements Exception {
  const AiProviderException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

abstract class AiProviderClient {
  AiProvider get provider;

  Future<List<AiModelInfo>> listModels(String apiKey);

  Future<ProviderResponse> respond(String apiKey, ProviderRequest request);
}

class AiProviderClientFactory {
  AiProviderClientFactory({Dio? dio, ProviderCapabilityRegistry? capabilities})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 30),
              receiveTimeout: const Duration(minutes: 10),
              sendTimeout: const Duration(minutes: 3),
            ),
          ),
      _capabilities = capabilities ?? ProviderCapabilityRegistry();

  final Dio _dio;
  final ProviderCapabilityRegistry _capabilities;

  AiProviderClient create(AiProvider provider) => switch (provider) {
    AiProvider.openai => OpenAiClient(_dio, _capabilities),
    AiProvider.anthropic => AnthropicClient(_dio, _capabilities),
    AiProvider.gemini => GeminiClient(_dio, _capabilities),
  };
}

abstract class _BaseClient implements AiProviderClient {
  _BaseClient(this.dio, this.capabilityRegistry);

  final Dio dio;
  final ProviderCapabilityRegistry capabilityRegistry;

  void validate(ProviderRequest request) {
    final capabilities = capabilityRegistry.forModel(provider, request.model);
    final reasoning = request.reasoningLevel;
    if (reasoning != null &&
        !capabilities.reasoningLevels.contains(reasoning)) {
      throw AiProviderException(
        'Reasoning level “$reasoning” is not documented for ${request.model}.',
      );
    }
    if (request.webSearch && !capabilities.webSearch) {
      throw AiProviderException(
        'Web search is not documented for ${request.model}.',
      );
    }
    if (request.codeExecution && !capabilities.codeExecution) {
      throw AiProviderException(
        'Code execution is not documented for ${request.model}.',
      );
    }
  }

  Never providerError(String providerName, DioException error) {
    final responseData = error.response?.data;
    var message = '$providerName request failed.';
    if (responseData is Map) {
      final nested = responseData['error'];
      if (nested is Map && nested['message'] != null) {
        message = nested['message'].toString();
      } else if (responseData['message'] != null) {
        message = responseData['message'].toString();
      } else if (nested is String) {
        message = nested;
      }
    }
    throw AiProviderException(message, statusCode: error.response?.statusCode);
  }

  Map<String, Object?> objectMap(Object? value) {
    if (value is Map<String, Object?>) return value;
    if (value is Map) return Map<String, Object?>.from(value);
    throw const AiProviderException('Provider returned an invalid response.');
  }

  List<String> collectUrls(Object? value) {
    final result = <String>{};
    void visit(Object? item) {
      if (item is Map) {
        for (final entry in item.entries) {
          final key = entry.key.toString().toLowerCase();
          final candidate = entry.value?.toString();
          if ((key == 'url' || key == 'uri') &&
              candidate != null &&
              (candidate.startsWith('https://') ||
                  candidate.startsWith('http://'))) {
            result.add(candidate);
          }
          visit(entry.value);
        }
      } else if (item is List) {
        for (final child in item) {
          visit(child);
        }
      }
    }

    visit(value);
    return result.toList(growable: false);
  }
}

class OpenAiClient extends _BaseClient {
  OpenAiClient(super.dio, super.capabilityRegistry);

  static const _baseUrl = 'https://api.openai.com/v1';

  @override
  AiProvider get provider => AiProvider.openai;

  Options _options(String key) => Options(
    headers: {
      'Authorization': 'Bearer $key',
      'Content-Type': 'application/json',
    },
  );

  @override
  Future<List<AiModelInfo>> listModels(String apiKey) async {
    try {
      final response = await dio.get<Map<String, dynamic>>(
        '$_baseUrl/models',
        options: _options(apiKey),
      );
      final rows = response.data?['data'];
      if (rows is! List) return const [];
      final models = rows
          .whereType<Map>()
          .map((row) => Map<String, Object?>.from(row))
          .where((row) => _isLikelyTextModel('${row['id']}'))
          .map(
            (row) => AiModelInfo(
              id: '${row['id']}',
              displayName: '${row['id']}',
              provider: provider,
              createdAt: row['created'] is num
                  ? DateTime.fromMillisecondsSinceEpoch(
                      (row['created'] as num).toInt() * 1000,
                      isUtc: true,
                    )
                  : null,
            ),
          )
          .toList();
      models.sort((a, b) => b.id.compareTo(a.id));
      return models;
    } on DioException catch (error) {
      providerError('OpenAI', error);
    }
  }

  bool _isLikelyTextModel(String id) =>
      id.startsWith('gpt-') || RegExp(r'^o[1-9]').hasMatch(id);

  @override
  Future<ProviderResponse> respond(
    String apiKey,
    ProviderRequest request,
  ) async {
    validate(request);
    final body = <String, Object?>{
      'model': request.model,
      'store': false,
      'instructions': request.systemPrompt,
      'input':
          '${request.userPrompt}\n\n<complete_health_context>\n'
          '${request.contextJson}\n</complete_health_context>',
      'max_output_tokens': request.maxOutputTokens,
    };
    if (request.reasoningLevel != null) {
      body['reasoning'] = {'effort': request.reasoningLevel};
    }
    final tools = <Map<String, Object?>>[];
    if (request.webSearch) tools.add({'type': 'web_search'});
    if (request.codeExecution) {
      tools.add({
        'type': 'code_interpreter',
        'container': {'type': 'auto', 'memory_limit': '4g'},
      });
    }
    if (tools.isNotEmpty) body['tools'] = tools;
    if (request.requireJson) {
      body['text'] = {
        'format': {'type': 'json_object'},
      };
    }

    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_baseUrl/responses',
        data: body,
        options: _options(apiKey),
      );
      final raw = objectMap(response.data);
      final textParts = <String>[];
      final output = raw['output'];
      if (output is List) {
        for (final item in output.whereType<Map>()) {
          final content = item['content'];
          if (content is! List) continue;
          for (final block in content.whereType<Map>()) {
            if (block['text'] != null) textParts.add(block['text'].toString());
          }
        }
      }
      final text = textParts.join('\n').trim();
      if (text.isEmpty) {
        throw const AiProviderException('OpenAI returned no text output.');
      }
      return ProviderResponse(
        text: text,
        raw: raw,
        responseId: raw['id']?.toString(),
        citations: collectUrls(raw),
      );
    } on DioException catch (error) {
      providerError('OpenAI', error);
    }
  }
}

class AnthropicClient extends _BaseClient {
  AnthropicClient(super.dio, super.capabilityRegistry);

  static const _baseUrl = 'https://api.anthropic.com/v1';

  @override
  AiProvider get provider => AiProvider.anthropic;

  Options _options(String key) => Options(
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      'Content-Type': 'application/json',
    },
  );

  @override
  Future<List<AiModelInfo>> listModels(String apiKey) async {
    final models = <AiModelInfo>[];
    String? afterId;
    try {
      do {
        final response = await dio.get<Map<String, dynamic>>(
          '$_baseUrl/models',
          queryParameters: {'limit': 1000, 'after_id': ?afterId},
          options: _options(apiKey),
        );
        final data = response.data ?? const <String, dynamic>{};
        final rows = data['data'];
        if (rows is List) {
          for (final value in rows.whereType<Map>()) {
            final row = Map<String, Object?>.from(value);
            final id = row['id']?.toString();
            if (id == null || id.isEmpty) continue;
            models.add(
              AiModelInfo(
                id: id,
                displayName: row['display_name']?.toString() ?? id,
                provider: provider,
                createdAt: DateTime.tryParse(
                  row['created_at']?.toString() ?? '',
                ),
              ),
            );
          }
        }
        afterId = data['has_more'] == true ? data['last_id']?.toString() : null;
      } while (afterId != null && afterId.isNotEmpty);
      models.sort((a, b) => b.id.compareTo(a.id));
      return models;
    } on DioException catch (error) {
      providerError('Anthropic', error);
    }
  }

  @override
  Future<ProviderResponse> respond(
    String apiKey,
    ProviderRequest request,
  ) async {
    validate(request);
    final body = <String, Object?>{
      'model': request.model,
      'max_tokens': request.maxOutputTokens,
      'system': request.systemPrompt,
      'messages': [
        {
          'role': 'user',
          'content':
              '${request.userPrompt}\n\n<complete_health_context>\n'
              '${request.contextJson}\n</complete_health_context>',
        },
      ],
    };
    if (request.reasoningLevel != null) {
      body['thinking'] = {'type': 'adaptive'};
      body['output_config'] = {'effort': request.reasoningLevel};
    }
    final tools = <Map<String, Object?>>[];
    if (request.webSearch) {
      tools.add({
        'type': 'web_search_20260209',
        'name': 'web_search',
        'max_uses': 8,
      });
    }
    if (request.codeExecution) {
      tools.add({'type': 'code_execution_20260521', 'name': 'code_execution'});
    }
    if (tools.isNotEmpty) body['tools'] = tools;

    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_baseUrl/messages',
        data: body,
        options: _options(apiKey),
      );
      final raw = objectMap(response.data);
      final content = raw['content'];
      final textParts = <String>[];
      if (content is List) {
        for (final block in content.whereType<Map>()) {
          if (block['type'] == 'text' && block['text'] != null) {
            textParts.add(block['text'].toString());
          }
        }
      }
      final text = textParts.join('\n').trim();
      if (text.isEmpty) {
        throw const AiProviderException('Anthropic returned no text output.');
      }
      return ProviderResponse(
        text: text,
        raw: raw,
        responseId: raw['id']?.toString(),
        citations: collectUrls(raw),
      );
    } on DioException catch (error) {
      providerError('Anthropic', error);
    }
  }
}

class GeminiClient extends _BaseClient {
  GeminiClient(super.dio, super.capabilityRegistry);

  static const _baseUrl = 'https://generativelanguage.googleapis.com/v1beta';

  @override
  AiProvider get provider => AiProvider.gemini;

  Options _options(String key) => Options(
    headers: {'x-goog-api-key': key, 'Content-Type': 'application/json'},
  );

  @override
  Future<List<AiModelInfo>> listModels(String apiKey) async {
    final models = <AiModelInfo>[];
    String? pageToken;
    try {
      do {
        final response = await dio.get<Map<String, dynamic>>(
          '$_baseUrl/models',
          queryParameters: {'pageSize': 1000, 'pageToken': ?pageToken},
          options: _options(apiKey),
        );
        final data = response.data ?? const <String, dynamic>{};
        final rows = data['models'];
        if (rows is List) {
          for (final value in rows.whereType<Map>()) {
            final row = Map<String, Object?>.from(value);
            final methods = row['supportedGenerationMethods'];
            if (methods is List && !methods.contains('generateContent')) {
              continue;
            }
            final name = row['name']?.toString() ?? '';
            final id = name.replaceFirst(RegExp(r'^models/'), '');
            if (!id.startsWith('gemini-')) continue;
            models.add(
              AiModelInfo(
                id: id,
                displayName: row['displayName']?.toString() ?? id,
                provider: provider,
                description: row['description']?.toString(),
              ),
            );
          }
        }
        pageToken = data['nextPageToken']?.toString();
      } while (pageToken != null && pageToken.isNotEmpty);
      models.sort((a, b) => b.id.compareTo(a.id));
      return models;
    } on DioException catch (error) {
      providerError('Gemini', error);
    }
  }

  @override
  Future<ProviderResponse> respond(
    String apiKey,
    ProviderRequest request,
  ) async {
    validate(request);
    final body = <String, Object?>{
      'model': request.model,
      'store': false,
      'system_instruction': request.systemPrompt,
      'input':
          '${request.userPrompt}\n\n<complete_health_context>\n'
          '${request.contextJson}\n</complete_health_context>',
      'generation_config': {
        'max_output_tokens': request.maxOutputTokens,
        if (request.reasoningLevel != null)
          'thinking_level': request.reasoningLevel,
      },
    };
    final tools = <Map<String, Object?>>[];
    if (request.webSearch) tools.add({'type': 'google_search'});
    if (request.codeExecution) tools.add({'type': 'code_execution'});
    if (tools.isNotEmpty) body['tools'] = tools;

    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_baseUrl/interactions',
        data: body,
        options: _options(apiKey),
      );
      final raw = objectMap(response.data);
      final textParts = <String>[];
      void readSteps(Object? value) {
        if (value is! List) return;
        for (final step in value.whereType<Map>()) {
          if (step['type'] != 'model_output') continue;
          final content = step['content'];
          if (content is String) {
            textParts.add(content);
          } else if (content is List) {
            for (final block in content.whereType<Map>()) {
              if (block['text'] != null) {
                textParts.add(block['text'].toString());
              }
            }
          }
        }
      }

      readSteps(raw['steps']);
      readSteps(raw['outputs']);
      final text = textParts.join('\n').trim();
      if (text.isEmpty) {
        throw const AiProviderException('Gemini returned no text output.');
      }
      return ProviderResponse(
        text: text,
        raw: raw,
        responseId: raw['id']?.toString(),
        citations: collectUrls(raw),
      );
    } on DioException catch (error) {
      providerError('Gemini', error);
    } on FormatException catch (error) {
      throw AiProviderException(
        'Gemini response parsing failed: ${error.message}',
      );
    }
  }
}

String prettyProviderResponse(ProviderResponse response) =>
    const JsonEncoder.withIndent('  ').convert(response.raw);
