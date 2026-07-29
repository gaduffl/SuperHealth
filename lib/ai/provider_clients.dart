import 'dart:convert';

import 'package:crypto/crypto.dart';
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

  /// Whether this concrete client implements a documented, code-container
  /// upload path. A model capability alone is not enough: Gemini currently has
  /// no such path in this app, so it must fail instead of silently inlining.
  bool get supportsContextFile => false;

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
    if (request.contextFile && !capabilities.losslessContextFile) {
      throw AiProviderException(
        'Lossless context-file analysis is not documented for ${request.model}.',
      );
    }
    if (request.contextFile && !supportsContextFile) {
      throw AiProviderException(
        '${provider.name} does not have a supported lossless context-file '
        'path in this app.',
      );
    }
    if (request.contextFile && !request.codeExecution) {
      throw const AiProviderException(
        'Lossless context-file analysis requires code execution.',
      );
    }
    if (request.contextFile) {
      final expected = request.contextFileSha256;
      final actual = sha256
          .convert(utf8.encode(request.contextJson))
          .toString();
      if (expected == null || expected != actual) {
        throw const AiProviderException(
          'The context file checksum does not match the exact upload bytes.',
        );
      }
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

  @override
  bool get supportsContextFile => true;

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

  bool _isLikelyTextModel(String id) {
    if (!(id.startsWith('gpt-') || RegExp(r'^o[1-9]').hasMatch(id))) {
      return false;
    }
    const nonTextMarkers = [
      'audio',
      'tts',
      'transcribe',
      'realtime',
      'image',
      'whisper',
      'embedding',
      'moderation',
    ];
    return !nonTextMarkers.any(id.contains);
  }

  @override
  Future<ProviderResponse> respond(
    String apiKey,
    ProviderRequest request,
  ) async {
    validate(request);
    String? contextFileId;
    try {
      if (request.contextFile) {
        contextFileId = await _uploadContext(apiKey, request.contextJson);
      }
      final body = <String, Object?>{
        'model': request.model,
        'store': false,
        'instructions': request.systemPrompt,
        'input': request.contextFile
            ? '${request.userPrompt}\n\nThe complete health evidence package is '
                  'available in the code-interpreter container. Locate '
                  'superhealth-context.json, use code to load every section, '
                  'verify the exact file SHA-256 ${request.contextFileSha256}, and '
                  'follow the coverage protocol before answering.'
            : '${request.userPrompt}\n\n<complete_health_context>\n'
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
          'container': {
            'type': 'auto',
            'memory_limit': '4g',
            if (contextFileId != null) 'file_ids': [contextFileId],
          },
        });
      }
      if (tools.isNotEmpty) body['tools'] = tools;
      if (request.requireJson &&
          capabilityRegistry
              .forModel(provider, request.model)
              .structuredOutput) {
        body['text'] = {
          'format': {'type': 'json_object'},
        };
      }
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
    } finally {
      if (contextFileId != null) {
        try {
          await dio.delete<void>(
            '$_baseUrl/files/$contextFileId',
            options: _options(apiKey),
          );
        } on DioException {
          // The request result is more important than best-effort cleanup.
        }
      }
    }
  }

  Future<String> _uploadContext(String apiKey, String json) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_baseUrl/files',
        data: FormData.fromMap({
          'purpose': 'user_data',
          'file': MultipartFile.fromBytes(
            utf8.encode(json),
            filename: 'superhealth-context.json',
          ),
        }),
        options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
      );
      final id = response.data?['id']?.toString();
      if (id == null || id.isEmpty) {
        throw const AiProviderException(
          'OpenAI did not return a context file ID.',
        );
      }
      return id;
    } on DioException catch (error) {
      providerError('OpenAI context upload', error);
    }
  }
}

class AnthropicClient extends _BaseClient {
  AnthropicClient(super.dio, super.capabilityRegistry);

  static const _baseUrl = 'https://api.anthropic.com/v1';
  static const _filesBeta = 'files-api-2025-04-14';
  static const _fallbackBeta = 'server-side-fallback-2026-07-01';

  /// A server-tool loop can pause several times on a large evidence package;
  /// each resume re-sends the conversation, so keep the cap small.
  static const _maxPauseTurnResumes = 4;

  @override
  AiProvider get provider => AiProvider.anthropic;

  @override
  bool get supportsContextFile => true;

  Options _options(String key, {List<String> betas = const []}) => Options(
    headers: {
      'x-api-key': key,
      'anthropic-version': '2023-06-01',
      if (betas.isNotEmpty) 'anthropic-beta': betas.join(','),
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
            if (id == null || id.isEmpty || !id.startsWith('claude-')) {
              continue;
            }
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
    final capabilities = capabilityRegistry.forModel(provider, request.model);
    String? contextFileId;
    try {
      if (request.contextFile) {
        contextFileId = await _uploadContext(apiKey, request.contextJson);
      }
      final body = <String, Object?>{
        'model': request.model,
        'max_tokens': request.maxOutputTokens,
        // The stable prefix (system, then the context block below) carries the
        // cache breakpoints; the varying task prompt comes last so repeated
        // calls over the same evidence package are served from cache.
        'system': [
          {
            'type': 'text',
            'text': request.systemPrompt,
            'cache_control': {'type': 'ephemeral'},
          },
        ],
        'messages': [
          {
            'role': 'user',
            'content': request.contextFile
                ? [
                    {
                      'type': 'text',
                      'text':
                          '${request.userPrompt}\n\nThe complete health evidence '
                          'package is attached as superhealth-context.json. Use '
                          'code execution to load every section, verify the exact '
                          'file SHA-256 ${request.contextFileSha256}, and follow '
                          'the coverage protocol before answering.',
                    },
                    {'type': 'container_upload', 'file_id': contextFileId},
                  ]
                : [
                    {
                      'type': 'text',
                      'text':
                          '<complete_health_context>\n${request.contextJson}'
                          '\n</complete_health_context>',
                      'cache_control': {'type': 'ephemeral'},
                    },
                    {'type': 'text', 'text': request.userPrompt},
                  ],
          },
        ],
      };
      // Adaptive thinking is sent whenever the model documents it. On Opus
      // 4.7/4.8 omitting the parameter silently disables thinking; on newer
      // models an explicit adaptive value is the documented no-op default.
      if (capabilities.adaptiveThinking) {
        body['thinking'] = {'type': 'adaptive'};
      }
      final outputConfig = <String, Object?>{};
      if (request.reasoningLevel != null) {
        outputConfig['effort'] = request.reasoningLevel;
      }
      // Structured outputs are not combined with web search: search results
      // carry citation blocks, and citations are documented as incompatible
      // with output_config.format.
      if (request.requireJson &&
          request.jsonSchema != null &&
          capabilities.structuredOutput &&
          !request.webSearch) {
        outputConfig['format'] = {
          'type': 'json_schema',
          'schema': request.jsonSchema,
        };
      }
      if (outputConfig.isNotEmpty) body['output_config'] = outputConfig;
      // A benign health question can trip the frontier safety classifiers;
      // the documented default fallback re-serves it on the recommended
      // model inside the same call instead of failing the whole turn.
      if (capabilities.refusalFallback) body['fallbacks'] = 'default';
      final tools = <Map<String, Object?>>[];
      if (request.webSearch) {
        final toolType = capabilities.webSearchToolType;
        if (toolType == null) {
          throw AiProviderException(
            'No documented web-search tool version for ${request.model}.',
          );
        }
        tools.add({'type': toolType, 'name': 'web_search', 'max_uses': 8});
      }
      if (request.codeExecution) {
        tools.add({
          'type': 'code_execution_20260521',
          'name': 'code_execution',
        });
      }
      if (tools.isNotEmpty) body['tools'] = tools;
      final betas = [
        if (request.contextFile) _filesBeta,
        if (capabilities.refusalFallback) _fallbackBeta,
      ];
      final options = _options(apiKey, betas: betas);

      var raw = objectMap(
        (await _postWithRetry('$_baseUrl/messages', body, options)).data,
      );
      final textParts = <String>[..._textBlocks(raw)];
      final citations = <String>{...collectUrls(raw)};
      // A server-tool loop that hits its iteration limit pauses the turn.
      // Resume by echoing the assistant content; the reply continues where
      // the paused turn stopped, so text accumulates across resumes.
      var resumes = 0;
      while (raw['stop_reason'] == 'pause_turn' &&
          resumes < _maxPauseTurnResumes) {
        resumes += 1;
        final messages = List<Object?>.from(body['messages']! as List)
          ..add({'role': 'assistant', 'content': raw['content']});
        body['messages'] = messages;
        raw = objectMap(
          (await _postWithRetry('$_baseUrl/messages', body, options)).data,
        );
        textParts.addAll(_textBlocks(raw));
        citations.addAll(collectUrls(raw));
      }
      final stopReason = raw['stop_reason']?.toString();
      if (stopReason == 'pause_turn') {
        throw const AiProviderException(
          'Anthropic paused the tool loop repeatedly without finishing. '
          'Try again, or disable web search for this request.',
        );
      }
      if (stopReason == 'refusal') {
        final details = raw['stop_details'];
        final explanation = details is Map
            ? details['explanation']?.toString()
            : null;
        throw AiProviderException(
          explanation == null || explanation.isEmpty
              ? 'Anthropic declined this request for safety reasons.'
              : 'Anthropic declined this request for safety reasons: '
                    '$explanation',
        );
      }
      final text = textParts.join('\n').trim();
      if (stopReason == 'max_tokens') {
        throw const AiProviderException(
          'Anthropic stopped at the output token limit, so the answer is '
          'incomplete. Retry, or reduce the request scope.',
        );
      }
      if (text.isEmpty) {
        throw const AiProviderException('Anthropic returned no text output.');
      }
      return ProviderResponse(
        text: text,
        raw: raw,
        responseId: raw['id']?.toString(),
        citations: citations.toList(growable: false),
      );
    } on DioException catch (error) {
      providerError('Anthropic', error);
    } finally {
      if (contextFileId != null) {
        try {
          await dio.delete<void>(
            '$_baseUrl/files/$contextFileId',
            options: _options(apiKey, betas: const [_filesBeta]),
          );
        } on DioException {
          // The request result is more important than best-effort cleanup.
        }
      }
    }
  }

  List<String> _textBlocks(Map<String, Object?> raw) {
    final content = raw['content'];
    if (content is! List) return const [];
    return [
      for (final block in content.whereType<Map>())
        if (block['type'] == 'text' && block['text'] != null)
          block['text'].toString(),
    ];
  }

  /// Retries transient Anthropic failures (rate limits, overload, server
  /// errors) with exponential backoff, honoring an explicit retry-after.
  Future<Response<Map<String, dynamic>>> _postWithRetry(
    String url,
    Map<String, Object?> body,
    Options options,
  ) async {
    var attempt = 0;
    while (true) {
      try {
        return await dio.post<Map<String, dynamic>>(
          url,
          data: body,
          options: options,
        );
      } on DioException catch (error) {
        final status = error.response?.statusCode;
        const retryable = {429, 500, 502, 503, 529};
        if (attempt >= 2 || status == null || !retryable.contains(status)) {
          rethrow;
        }
        final retryAfter = int.tryParse(
          error.response?.headers.value('retry-after') ?? '',
        );
        final delay = retryAfter != null
            ? Duration(seconds: retryAfter.clamp(1, 60).toInt())
            : Duration(seconds: 2 << attempt);
        attempt += 1;
        await Future<void>.delayed(delay);
      }
    }
  }

  Future<String> _uploadContext(String apiKey, String json) async {
    try {
      final response = await dio.post<Map<String, dynamic>>(
        '$_baseUrl/files',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(
            utf8.encode(json),
            filename: 'superhealth-context.json',
          ),
        }),
        options: Options(
          headers: {
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'anthropic-beta': 'files-api-2025-04-14',
          },
        ),
      );
      final id = response.data?['id']?.toString();
      if (id == null || id.isEmpty) {
        throw const AiProviderException(
          'Anthropic did not return a context file ID.',
        );
      }
      return id;
    } on DioException catch (error) {
      providerError('Anthropic context upload', error);
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
            if (!id.startsWith('gemini-') ||
                id.contains('image') ||
                id.contains('audio') ||
                id.contains('tts')) {
              continue;
            }
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
      if (request.requireJson)
        'response_format': {'type': 'text', 'mime_type': 'application/json'},
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
