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

/// The most specific description available for a provider error payload.
///
/// Providers nest the reason differently — top level, under `error`, under
/// `response.error` — and reading only one of those places turns a real
/// diagnosis ("context length exceeded", "rate limit") into a shrug. When no
/// known shape matches, the raw event is included rather than dropped: an
/// unrecognised payload is exactly the case where the text matters most.
String describeProviderError(Map<String, Object?> event, String fallback) {
  Object? pick(Object? node, String key) => node is Map ? node[key] : null;

  final candidates = <Object?>[
    event['message'],
    pick(event['error'], 'message'),
    pick(pick(event['response'], 'error'), 'message'),
  ];
  final message = candidates
      .map((value) => value?.toString().trim() ?? '')
      .firstWhere((value) => value.isNotEmpty, orElse: () => '');

  final code = [
    event['code'],
    pick(event['error'], 'code'),
    pick(pick(event['response'], 'error'), 'code'),
  ].firstWhere((value) => value != null, orElse: () => null);

  if (message.isNotEmpty) {
    return code == null ? message : '$message (code $code)';
  }

  // Nothing recognised. Show what actually arrived, bounded, so the next
  // report carries the shape instead of another shrug.
  var raw = jsonEncode(event);
  if (raw.length > 600) raw = '${raw.substring(0, 600)}…';
  return '$fallback Raw event: $raw';
}

/// The cache key if a provider will accept it, otherwise null.
///
/// Caching is an optimisation. The one thing it must never do is cost the
/// caller their answer, so a key that would be rejected is dropped and the
/// request proceeds without it — a cold prefill instead of no plan at all.
/// Truncating instead would be worse: two different catalogs could collide on
/// the shortened key and one could be served the other's prefix.
String? usablePromptCacheKey(String? key) {
  if (key == null) return null;
  final trimmed = key.trim();
  if (trimmed.isEmpty) return null;
  if (trimmed.length > ProviderRequest.promptCacheKeyMaxLength) return null;
  return trimmed;
}

/// Why a response stopped, whichever provider produced it.
///
/// The three providers name this differently, and reading only Anthropic's
/// field logged `null` for every OpenAI call — hiding exactly the outcomes
/// worth catching. A response truncated at the output limit and one that
/// finished cleanly are indistinguishable from length alone, and both look
/// like a plan that simply failed to parse.
String? providerStopReason(Map<String, Object?> raw) {
  // Anthropic: end_turn, max_tokens, refusal, pause_turn.
  final anthropic = raw['stop_reason'];
  if (anthropic != null) return anthropic.toString();

  // OpenAI Responses: completed | incomplete | failed, with the interesting
  // part in a side object — "incomplete" alone does not say why.
  final status = raw['status'];
  if (status != null) {
    final detail = raw['incomplete_details'];
    final reason = detail is Map ? detail['reason'] : null;
    final error = raw['error'];
    final message = error is Map ? error['message'] : null;
    return [
      status.toString(),
      if (reason != null) 'reason=$reason',
      if (message != null) 'error=$message',
    ].join(' ');
  }

  // Gemini reports per-candidate.
  final candidates = raw['candidates'];
  if (candidates is List && candidates.isNotEmpty) {
    final first = candidates.first;
    final finish = first is Map ? first['finishReason'] : null;
    if (finish != null) return finish.toString();
  }
  return null;
}

/// A live sign that a streamed call is still producing.
///
/// Sent while the response is still arriving, so a caller can tell a slow model
/// from a wedged connection. The two are indistinguishable from the outside
/// otherwise, and a minutes-long call gives plenty of time to wonder.
class ProviderActivity {
  const ProviderActivity({
    required this.outputChars,
    required this.thinkingChars,
    this.thinkingTail = '',
  });

  /// Characters of answer text received so far.
  final int outputChars;

  /// Characters of reasoning received so far.
  final int thinkingChars;

  /// The most recent reasoning text, for display. Bounded by the client, since
  /// a whole reasoning trace is far more than a progress card can show.
  final String thinkingTail;

  bool get isThinking => thinkingChars > 0 && outputChars == 0;
  int get totalChars => outputChars + thinkingChars;
}

/// Reports that a streamed response is still arriving.
///
/// Called from inside the stream loop, so it must be cheap and must not throw:
/// commentary must never cost the caller their response. Providers without a
/// streaming path never call it.
typedef ProviderActivityCallback = void Function(ProviderActivity activity);

/// Accumulates stream deltas and reports them at a rate a UI can survive.
///
/// A long turn delivers thousands of deltas. Forwarding each one would spend
/// the call rebuilding a progress card, so this coalesces them and emits at
/// most one update per [interval] — plus a final one on [flush], so the last
/// state is never the one that happened to be throttled away.
class ActivityReporter {
  ActivityReporter(this._onActivity, {this.interval = _defaultInterval});

  static const _defaultInterval = Duration(milliseconds: 400);

  /// How much reasoning to keep. A trace runs to thousands of characters; a
  /// progress card shows a couple of lines, and holding the rest would grow
  /// without bound across a long turn.
  static const tailChars = 400;

  final ProviderActivityCallback? _onActivity;
  final Duration interval;

  int _outputChars = 0;
  int _thinkingChars = 0;
  final StringBuffer _tail = StringBuffer();
  DateTime? _lastEmit;

  bool get isEnabled => _onActivity != null;

  void addOutput(String delta) {
    if (_onActivity == null || delta.isEmpty) return;
    _outputChars += delta.length;
    _emit();
  }

  void addThinking(String delta) {
    if (_onActivity == null || delta.isEmpty) return;
    _thinkingChars += delta.length;
    _tail.write(delta);
    // Trimming on write keeps the buffer bounded regardless of trace length.
    if (_tail.length > tailChars * 2) {
      final kept = _tail.toString();
      _tail
        ..clear()
        ..write(kept.substring(kept.length - tailChars));
    }
    _emit();
  }

  /// Emits the current state regardless of the interval. Call once a stream
  /// ends, so the final counts are not lost to throttling.
  void flush() {
    if (_onActivity == null) return;
    _lastEmit = null;
    _emit();
  }

  void _emit() {
    final now = DateTime.now();
    final last = _lastEmit;
    if (last != null && now.difference(last) < interval) return;
    _lastEmit = now;
    final kept = _tail.toString();
    try {
      _onActivity!(
        ProviderActivity(
          outputChars: _outputChars,
          thinkingChars: _thinkingChars,
          thinkingTail: kept.length > tailChars
              ? kept.substring(kept.length - tailChars)
              : kept,
        ),
      );
    } on Object {
      // Commentary must never cost the caller their response.
    }
  }
}

abstract class AiProviderClient {
  AiProvider get provider;

  Future<List<AiModelInfo>> listModels(String apiKey);

  /// [onActivity] is called while a streamed response arrives. It is optional
  /// and best effort: a provider with no streaming path in this app simply
  /// never calls it, and a caller that passes nothing loses only commentary.
  Future<ProviderResponse> respond(
    String apiKey,
    ProviderRequest request, {
    ProviderActivityCallback? onActivity,
  });

  /// The provider's exact token count for the context payload, or null when
  /// no documented counting endpoint exists. Implementations never throw;
  /// callers fall back to the local byte-based estimate on null.
  Future<int?> countContextTokens(
    String apiKey, {
    required String model,
    required String contextJson,
  });
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

  @override
  Future<int?> countContextTokens(
    String apiKey, {
    required String model,
    required String contextJson,
  }) async => null;

  Never providerError(
    String providerName,
    DioException error, {
    Object? decodedBody,
  }) {
    final responseData = decodedBody ?? error.response?.data;
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

  /// Streamed requests deliver error bodies as a byte stream; decode it so
  /// [providerError] can surface the provider's own message.
  Future<Object?> decodeStreamError(DioException error) async {
    final data = error.response?.data;
    if (data is! ResponseBody) return null;
    try {
      final bytes = <int>[];
      await for (final chunk in data.stream) {
        bytes.addAll(chunk);
      }
      return jsonDecode(utf8.decode(bytes, allowMalformed: true));
    } on Object {
      return null;
    }
  }

  /// Retries transient failures (rate limits, overload, server errors) with
  /// exponential backoff, honoring an explicit retry-after header. Errors
  /// after a stream has started are not retried; a partial turn is not
  /// safely repeatable.
  Future<T> retryTransient<T>(Future<T> Function() send) async {
    var attempt = 0;
    while (true) {
      try {
        return await send();
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

  /// Parses a server-sent-event byte stream into its JSON data events.
  Stream<Map<String, Object?>> sseJsonEvents(ResponseBody body) async* {
    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (!line.startsWith('data:')) continue;
      final payload = line.substring(5).trim();
      if (payload.isEmpty || payload == '[DONE]') continue;
      Object? decoded;
      try {
        decoded = jsonDecode(payload);
      } on FormatException {
        continue; // Keep-alive comments and partial frames are not events.
      }
      if (decoded is Map) yield Map<String, Object?>.from(decoded);
    }
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
    ProviderRequest request, {
    ProviderActivityCallback? onActivity,
  }) async {
    validate(request);
    final capabilities = capabilityRegistry.forModel(provider, request.model);
    String? contextFileId;
    try {
      if (request.contextFile) {
        contextFileId = await _uploadContext(apiKey, request.contextJson);
      }
      final body = <String, Object?>{
        'model': request.model,
        'store': false,
        'stream': true,
        // Without this, two calls over the same context can land on different
        // machines and each pay a full prefill. The key only routes; it never
        // changes what is sent — so an unusable one is dropped rather than
        // sent. An over-long key was rejected with HTTP 400, and a request
        // that dies before the first token because of a caching *hint* is a
        // far worse outcome than a cold prefill.
        if (usablePromptCacheKey(request.promptCacheKey) != null)
          'prompt_cache_key': usablePromptCacheKey(request.promptCacheKey),
        'instructions': request.systemPrompt,
        // The stable context leads and the varying task prompt comes last so
        // OpenAI's automatic prefix caching serves repeated calls over the
        // same evidence package. History rides as native chat turns.
        'input': [
          {
            'role': 'user',
            'content': request.contextFile
                ? 'The complete health evidence package is available in the '
                      'code-interpreter container. Locate '
                      'superhealth-context.json, use code to load every '
                      'section, verify the exact file SHA-256 '
                      '${request.contextFileSha256}, and follow the coverage '
                      'protocol before answering.'
                : '<complete_health_context>\n${request.contextJson}'
                      '\n</complete_health_context>',
          },
          for (final turn in request.history)
            {'role': turn.role, 'content': turn.content},
          {'role': 'user', 'content': request.userPrompt},
        ],
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
      if (request.requireJson && capabilities.structuredOutput) {
        final schema = request.jsonSchema;
        body['text'] = {
          'format': schema == null
              ? {'type': 'json_object'}
              : {
                  'type': 'json_schema',
                  'name': 'superhealth_response',
                  'strict': true,
                  'schema': schema,
                },
        };
      }
      final raw = await _streamResponse(apiKey, body, onActivity);
      final status = raw['status']?.toString();
      if (status == 'failed') {
        final error = raw['error'];
        throw AiProviderException(
          error is Map && error['message'] != null
              ? 'OpenAI request failed: ${error['message']}'
              : 'OpenAI request failed.',
        );
      }
      if (status == 'incomplete') {
        final details = raw['incomplete_details'];
        final reason = details is Map ? details['reason']?.toString() : null;
        throw AiProviderException(
          reason == 'max_output_tokens'
              ? 'OpenAI stopped at the output token limit, so the answer is '
                    'incomplete. Retry, or reduce the request scope.'
              : 'OpenAI returned an incomplete response'
                    '${reason == null ? '' : ' ($reason)'}.',
        );
      }
      final textParts = <String>[];
      final refusals = <String>[];
      final output = raw['output'];
      if (output is List) {
        for (final item in output.whereType<Map>()) {
          if (item['type'] != null && item['type'] != 'message') continue;
          final content = item['content'];
          if (content is! List) continue;
          for (final block in content.whereType<Map>()) {
            if (block['type'] == 'refusal' && block['refusal'] != null) {
              refusals.add(block['refusal'].toString());
            } else if (block['text'] != null) {
              textParts.add(block['text'].toString());
            }
          }
        }
      }
      final text = textParts.join('\n').trim();
      if (text.isEmpty && refusals.isNotEmpty) {
        throw AiProviderException(
          'OpenAI declined this request: ${refusals.join(' ')}',
        );
      }
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
      providerError(
        'OpenAI',
        error,
        decodedBody: await decodeStreamError(error),
      );
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

  /// Streams a Responses API call and returns the final response object from
  /// its terminal event, keeping the connection alive through long
  /// high-effort turns.
  Future<Map<String, Object?>> _streamResponse(
    String apiKey,
    Map<String, Object?> body,
    ProviderActivityCallback? onActivity,
  ) async {
    final response = await retryTransient(
      () => dio.post<ResponseBody>(
        '$_baseUrl/responses',
        data: body,
        options: _options(apiKey).copyWith(responseType: ResponseType.stream),
      ),
    );
    final streamBody = response.data;
    if (streamBody == null) {
      throw const AiProviderException('OpenAI returned an empty stream.');
    }
    final reporter = ActivityReporter(onActivity);
    await for (final event in sseJsonEvents(streamBody)) {
      switch (event['type']) {
        case 'response.output_text.delta':
          reporter.addOutput(event['delta']?.toString() ?? '');
        // Reasoning arrives as a summary rather than the raw trace; it is still
        // the only account this provider gives of what it is doing.
        case 'response.reasoning_summary_text.delta':
          reporter.addThinking(event['delta']?.toString() ?? '');
        case 'response.completed' || 'response.incomplete':
          reporter.flush();
          return objectMap(event['response']);
        // A failed response used to be returned like a successful one; the
        // caller then found no text and reported "OpenAI returned no text
        // output", throwing away the reason the API had just given.
        case 'response.failed':
          reporter.flush();
          throw AiProviderException(
            describeProviderError(event, 'OpenAI reported a failed response.'),
          );
        case 'error':
          throw AiProviderException(
            describeProviderError(event, 'OpenAI reported a stream error.'),
          );
      }
    }
    throw const AiProviderException(
      'OpenAI ended the stream without a final response.',
    );
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
    ProviderRequest request, {
    ProviderActivityCallback? onActivity,
  }) async {
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
        'stream': true,
        // The stable prefix (system, then the context turn below) carries the
        // cache breakpoints; history rides as native chat turns and the
        // varying task prompt comes last so repeated calls over the same
        // evidence package are served from cache.
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
                          'The complete health evidence package is attached '
                          'as superhealth-context.json. Use code execution to '
                          'load every section, verify the exact file SHA-256 '
                          '${request.contextFileSha256}, and follow the '
                          'coverage protocol before answering.',
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
                  ],
          },
          for (final turn in request.history)
            {'role': turn.role, 'content': turn.content},
          {'role': 'user', 'content': request.userPrompt},
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

      final reporter = ActivityReporter(onActivity);
      var raw = await _streamMessage(body, options, reporter);
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
        raw = await _streamMessage(body, options, reporter);
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
      providerError(
        'Anthropic',
        error,
        decodedBody: await decodeStreamError(error),
      );
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

  @override
  Future<int?> countContextTokens(
    String apiKey, {
    required String model,
    required String contextJson,
  }) async {
    try {
      final response = await retryTransient(
        () => dio.post<Map<String, dynamic>>(
          '$_baseUrl/messages/count_tokens',
          data: {
            'model': model,
            'messages': [
              {'role': 'user', 'content': contextJson},
            ],
          },
          options: _options(apiKey),
        ),
      );
      final tokens = response.data?['input_tokens'];
      return tokens is num ? tokens.toInt() : null;
    } on DioException {
      // Counting is an accuracy upgrade, never a gate; the caller falls back
      // to the local estimate.
      return null;
    }
  }

  /// Streams a Messages API call over SSE and reassembles the complete
  /// message, keeping the connection alive through long high-effort turns.
  Future<Map<String, Object?>> _streamMessage(
    Map<String, Object?> body,
    Options options,
    ActivityReporter reporter,
  ) async {
    final response = await retryTransient(
      () => dio.post<ResponseBody>(
        '$_baseUrl/messages',
        data: body,
        options: options.copyWith(responseType: ResponseType.stream),
      ),
    );
    final streamBody = response.data;
    if (streamBody == null) {
      throw const AiProviderException('Anthropic returned an empty stream.');
    }
    Map<String, Object?>? message;
    final blocks = <int, Map<String, Object?>>{};
    final partialJson = <int, StringBuffer>{};
    await for (final event in sseJsonEvents(streamBody)) {
      switch (event['type']) {
        case 'message_start':
          message = Map<String, Object?>.from(objectMap(event['message']));
        case 'content_block_start':
          final index = (event['index'] as num?)?.toInt() ?? 0;
          blocks[index] = Map<String, Object?>.from(
            objectMap(event['content_block']),
          );
        case 'content_block_delta':
          final index = (event['index'] as num?)?.toInt() ?? 0;
          final block = blocks[index];
          final delta = event['delta'];
          if (block == null || delta is! Map) break;
          switch (delta['type']) {
            case 'text_delta':
              final text = delta['text']?.toString() ?? '';
              block['text'] = '${block['text'] ?? ''}$text';
              reporter.addOutput(text);
            case 'thinking_delta':
              final thinking = delta['thinking']?.toString() ?? '';
              block['thinking'] = '${block['thinking'] ?? ''}$thinking';
              reporter.addThinking(thinking);
            case 'signature_delta':
              block['signature'] =
                  '${block['signature'] ?? ''}${delta['signature'] ?? ''}';
            case 'input_json_delta':
              (partialJson[index] ??= StringBuffer()).write(
                delta['partial_json'] ?? '',
              );
            case 'citations_delta':
              final existing = block['citations'];
              block['citations'] = [
                if (existing is List) ...existing,
                if (delta['citation'] != null) delta['citation'],
              ];
          }
        case 'content_block_stop':
          final index = (event['index'] as num?)?.toInt() ?? 0;
          final partial = partialJson.remove(index);
          final block = blocks[index];
          if (partial != null && block != null && partial.isNotEmpty) {
            try {
              block['input'] = jsonDecode(partial.toString());
            } on FormatException {
              // Keep the block as announced; a resume echoes it verbatim.
            }
          }
        case 'message_delta':
          if (message == null) break;
          final delta = event['delta'];
          if (delta is Map) {
            for (final entry in delta.entries) {
              message[entry.key.toString()] = entry.value;
            }
          }
          final usage = event['usage'];
          if (usage is Map) {
            final existing = message['usage'];
            message['usage'] = {if (existing is Map) ...existing, ...usage};
          }
        case 'error':
          throw AiProviderException(
            describeProviderError(event, 'Anthropic reported a stream error.'),
          );
      }
    }
    // Emit the final counts, which the interval would otherwise have swallowed.
    reporter.flush();
    if (message == null) {
      throw const AiProviderException(
        'Anthropic ended the stream without a message.',
      );
    }
    final ordered = blocks.keys.toList()..sort();
    message['content'] = [for (final index in ordered) blocks[index]];
    return message;
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
  /// [onActivity] is never called: this client posts and waits rather than
  /// streaming, so there is no intermediate state to report. A caller shows
  /// "no live detail" rather than a frozen count.
  Future<ProviderResponse> respond(
    String apiKey,
    ProviderRequest request, {
    ProviderActivityCallback? onActivity,
  }) async {
    validate(request);
    // This client has no documented native multi-turn wire shape in the app,
    // so history is serialized between the stable context and the task
    // prompt; context-first ordering keeps the prefix cache-friendly.
    final historyAppendix = request.history.isEmpty
        ? ''
        : '\n\n<conversation_history>\n'
              '${jsonEncode([
                for (final turn in request.history) {'role': turn.role, 'content': turn.content},
              ])}'
              '\n</conversation_history>';
    final body = <String, Object?>{
      'model': request.model,
      'store': false,
      'system_instruction': request.systemPrompt,
      'input':
          '<complete_health_context>\n${request.contextJson}'
          '\n</complete_health_context>$historyAppendix'
          '\n\n${request.userPrompt}',
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
      final response = await retryTransient(
        () => dio.post<Map<String, dynamic>>(
          '$_baseUrl/interactions',
          data: body,
          options: _options(apiKey),
        ),
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
