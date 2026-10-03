import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';

import 'ai_models.dart';
import 'chatgpt_auth.dart';

class AiProviderException implements Exception {
  const AiProviderException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() =>
      statusCode == null ? message : '$message (HTTP $statusCode)';
}

/// A subscription's usage limit. It lasts until [resetsAt], so it is not a
/// rate limit to wait out with a few retries, and a run that meets it partway
/// keeps what it already has rather than losing it to the error.
class ProviderUsageLimitException extends AiProviderException {
  const ProviderUsageLimitException({
    this.resetsAt,
    this.planType,
    String? message,
  }) : super(message ?? 'The usage limit has been reached', statusCode: 429);

  /// When the limit lifts, in UTC. Null when the provider did not say.
  final DateTime? resetsAt;

  /// As the provider names it: `plus`, `pro` and so on.
  final String? planType;

  /// English fallback for the services that only surface an error; the UI
  /// phrases this case itself, in the reader's language and local time.
  @override
  String toString() {
    final reset = resetsAt?.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return reset == null
        ? 'ChatGPT usage limit reached.'
        : 'ChatGPT usage limit reached. It resets at '
              '${reset.year}-${two(reset.month)}-${two(reset.day)} '
              '${two(reset.hour)}:${two(reset.minute)}.';
  }
}

/// The usage limit an error payload reports, or null for any other error.
///
/// Codex reads the same three places: an HTTP body's `error`, a stream `error`
/// event's `error`, and a failed response's `response.error`. The reset comes
/// as epoch seconds in `resets_at`.
ProviderUsageLimitException? usageLimitFrom(Object? payload) {
  Map<Object?, Object?>? child(Object? node, String key) {
    final value = node is Map ? node[key] : null;
    return value is Map ? value : null;
  }

  for (final error in [
    child(payload, 'error'),
    child(child(payload, 'response'), 'error'),
  ]) {
    if (error == null) continue;
    if (error['type'] != 'usage_limit_reached' &&
        error['code'] != 'usage_limit_reached') {
      continue;
    }
    final resetsAt = error['resets_at'];
    final message = error['message']?.toString().trim();
    return ProviderUsageLimitException(
      resetsAt: resetsAt is num
          ? DateTime.fromMillisecondsSinceEpoch(
              resetsAt.toInt() * 1000,
              isUtc: true,
            )
          : null,
      planType: error['plan_type']?.toString(),
      message: message == null || message.isEmpty ? null : message,
    );
  }
  return null;
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
  ///
  /// When [ProviderRequest.tools] is non-empty the client runs the tool loop
  /// itself — calling [onToolCalls] between rounds — and returns only the
  /// final answer, because what has to be echoed back between rounds is
  /// provider-specific and only valid verbatim.
  Future<ProviderResponse> respond(
    String apiKey,
    ProviderRequest request, {
    ProviderActivityCallback? onActivity,
    AgentToolHandler? onToolCalls,
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
  AiProviderClientFactory({
    Dio? dio,
    ProviderCapabilityRegistry? capabilities,
    this._chatGpt,
  }) : _dio =
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
  final ChatGptSessionSource? _chatGpt;

  AiProviderClient create(AiProvider provider) => switch (provider) {
    AiProvider.openai => OpenAiClient(_dio, _capabilities),
    AiProvider.anthropic => AnthropicClient(_dio, _capabilities),
    AiProvider.gemini => GeminiClient(_dio, _capabilities),
    AiProvider.chatgpt => ChatGptSubscriptionClient(
      _dio,
      _capabilities,
      _chatGpt,
    ),
  };
}

/// Whether this app runs a client-side tool loop for [provider].
///
/// Gemini is left out deliberately, not by oversight: its stateless
/// function-calling transcript shape is not verified here, and a guessed wire
/// format would break the advisor outright. A provider without a loop gets
/// the full evidence package beside the digest instead of tools.
bool providerSupportsClientTools(AiProvider provider) => switch (provider) {
  AiProvider.openai || AiProvider.anthropic || AiProvider.chatgpt => true,
  AiProvider.gemini => false,
};

/// Rounds of tool calls one answer may take before the model is told to
/// answer with what it has. One further round is allowed for that answer.
const maxToolRounds = 10;

const _toolBudgetExhausted =
    '{"error":"Tool budget for this answer is used up. Answer now with the '
    'information you already have, and say what you could not check."}';

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
    if (request.tools.isNotEmpty && !providerSupportsClientTools(provider)) {
      throw AiProviderException(
        '${provider.name} has no client tool loop in this app.',
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

  /// A tool loop without a handler would stall on the first call.
  void requireToolHandler(ProviderRequest request, AgentToolHandler? handler) {
    if (request.tools.isNotEmpty && handler == null) {
      throw ArgumentError('Tools were offered without a handler to run them.');
    }
  }

  /// Runs one round, answering every call even if the handler returned fewer
  /// results — a call left unanswered is rejected by every provider.
  Future<List<AgentToolResult>> runToolRound(
    List<AgentToolCall> calls,
    int round,
    AgentToolHandler handler,
  ) async {
    final results = round > maxToolRounds
        ? const <AgentToolResult>[]
        : await handler(calls, round);
    final byId = {for (final result in results) result.callId: result};
    return [
      for (final call in calls)
        byId[call.id] ??
            AgentToolResult(
              callId: call.id,
              content: _toolBudgetExhausted,
              isError: true,
            ),
    ];
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
    AgentToolHandler? onToolCalls,
  }) async {
    validate(request);
    requireToolHandler(request, onToolCalls);
    final capabilities = capabilityRegistry.forModel(provider, request.model);
    String? contextFileId;
    try {
      if (request.contextFile) {
        contextFileId = await _uploadContext(apiKey, request.contextJson);
      }
      final contextText = request.contextFile
          ? 'The complete health evidence package is available in the '
                'code-interpreter container. Locate '
                'superhealth-context.json, use code to load every '
                'section, verify the exact file SHA-256 '
                '${request.contextFileSha256}, and follow the coverage '
                'protocol before answering.'
          : '<complete_health_context>\n${request.contextJson}'
                '\n</complete_health_context>';
      final digest = request.digestText;
      // The digest leads: it is the part identical across every round of a
      // turn, and OpenAI caches the longest matching prefix.
      final firstTurn = digest == null
          ? contextText
          : [
              '<clinical_digest>\n$digest\n</clinical_digest>',
              if (request.contextFile || request.contextJson.isNotEmpty)
                contextText,
            ].join('\n\n');
      final input = <Object?>[
        {'role': 'user', 'content': firstTurn},
        for (final turn in request.history)
          {'role': turn.role, 'content': turn.content},
        {'role': 'user', 'content': request.userPrompt},
      ];
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
        if (usablePromptCacheKey(request.promptCacheKey) != null) ...{
          'prompt_cache_key': usablePromptCacheKey(request.promptCacheKey),
          // The default cache lives in memory for a few minutes. That is
          // shorter than a person takes to read a 6,000-character answer and
          // type a follow-up, so a chat's second turn was paying a full
          // prefill of ~310k tokens on a context that had not changed by a
          // single byte. A day is what the API offers, and this context is
          // rebuilt daily anyway.
          'prompt_cache_retention': '24h',
        },
        'instructions': request.systemPrompt,
        // The stable context leads and the varying task prompt comes last so
        // OpenAI's automatic prefix caching serves repeated calls over the
        // same evidence package. History rides as native chat turns.
        'input': input,
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
      for (final spec in request.tools) {
        tools.add({
          'type': 'function',
          'name': spec.name,
          'description': spec.description,
          'parameters': spec.inputSchema,
          // Non-strict: strict mode rejects any schema with an optional
          // property, and a schema error fails the whole call. The toolbox
          // validates arguments itself and answers bad ones with an error.
          'strict': false,
        });
      }
      if (tools.isNotEmpty) body['tools'] = tools;
      // With store: false nothing persists between calls, so a reasoning
      // model's thinking must travel with the transcript as encrypted items,
      // or every tool round starts its reasoning from scratch.
      if (request.tools.isNotEmpty && capabilities.reasoningLevels.isNotEmpty) {
        body['include'] = ['reasoning.encrypted_content'];
      }
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
      var usage = const TokenUsage();
      final citations = <String>{};
      var round = 0;
      while (true) {
        final raw = await _streamResponse(apiKey, body, onActivity);
        _throwIfUnfinished(raw);
        usage = usage + (TokenUsage.fromResponse(raw) ?? const TokenUsage());
        citations.addAll(collectUrls(raw));
        final output = raw['output'] is List
            ? List<Object?>.from(raw['output']! as List)
            : const <Object?>[];
        final calls = [
          for (final item in output.whereType<Map>())
            if (item['type'] == 'function_call') _toolCall(item),
        ];
        if (calls.isEmpty) {
          return ProviderResponse(
            text: _outputText(raw),
            raw: raw,
            responseId: raw['id']?.toString(),
            citations: citations.toList(growable: false),
            aggregateUsage: usage.isEmpty ? null : usage,
            toolRounds: round,
          );
        }
        round += 1;
        if (round > maxToolRounds + 1) {
          throw const AiProviderException(
            'OpenAI kept calling tools without answering.',
          );
        }
        final results = await runToolRound(calls, round, onToolCalls!);
        // The model's own items go back verbatim — reasoning, calls, any
        // preamble — followed by one output per call.
        input.addAll(output);
        for (final result in results) {
          input.add({
            'type': 'function_call_output',
            'call_id': result.callId,
            'output': result.content,
          });
        }
      }
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

  void _throwIfUnfinished(Map<String, Object?> raw) {
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
  }

  String _outputText(Map<String, Object?> raw) {
    final textParts = <String>[];
    final refusals = <String>[];
    final output = raw['output'];
    if (output is List) {
      final messages = [
        for (final item in output.whereType<Map>())
          if (item['type'] == null || item['type'] == 'message') item,
      ];
      // A `commentary` message is the model narrating its progress ("I'll
      // check the intake history"). It reaches the reader only when there is
      // nothing else, never glued onto the front of the answer.
      final answers = messages.where((item) => item['phase'] != 'commentary');
      for (final item in answers.isEmpty ? messages : answers) {
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
    return text;
  }

  AgentToolCall _toolCall(Map<dynamic, dynamic> item) {
    final id = item['call_id']?.toString() ?? item['id']?.toString() ?? '';
    final name = item['name']?.toString() ?? '';
    final arguments = item['arguments'];
    if (arguments is Map) {
      return AgentToolCall(
        id: id,
        name: name,
        input: Map<String, Object?>.from(arguments),
      );
    }
    try {
      final decoded = jsonDecode(arguments?.toString() ?? '{}');
      if (decoded is Map) {
        return AgentToolCall(
          id: id,
          name: name,
          input: Map<String, Object?>.from(decoded),
        );
      }
      return AgentToolCall(
        id: id,
        name: name,
        input: const {},
        inputError: 'arguments are not a JSON object',
      );
    } on FormatException catch (error) {
      return AgentToolCall(
        id: id,
        name: name,
        input: const {},
        inputError: error.message,
      );
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
    final response = await _postResponses(apiKey, body);
    final streamBody = response.data;
    if (streamBody == null) {
      throw const AiProviderException('OpenAI returned an empty stream.');
    }
    final reporter = ActivityReporter(onActivity);
    final items = <Object?>[];
    await for (final event in sseJsonEvents(streamBody)) {
      switch (event['type']) {
        case 'response.output_text.delta':
          reporter.addOutput(event['delta']?.toString() ?? '');
        // Reasoning arrives as a summary rather than the raw trace; it is still
        // the only account this provider gives of what it is doing.
        case 'response.reasoning_summary_text.delta':
          reporter.addThinking(event['delta']?.toString() ?? '');
        case 'response.output_item.done':
          final item = event['item'];
          if (item is Map) items.add(Map<String, Object?>.from(item));
        case 'response.completed' || 'response.incomplete':
          reporter.flush();
          final completed = objectMap(event['response']);
          // The subscription backend ends with a `response.completed` that
          // carries only the id and usage; Codex reads its items from the
          // `output_item.done` events alone. Without this every answer there
          // would look empty.
          final output = completed['output'];
          if ((output is! List || output.isEmpty) && items.isNotEmpty) {
            return {...completed, 'output': items};
          }
          return completed;
        // A failed response used to be returned like a successful one; the
        // caller then found no text and reported "OpenAI returned no text
        // output", throwing away the reason the API had just given.
        case 'response.failed':
          reporter.flush();
          throw usageLimitFrom(event) ??
              AiProviderException(
                describeProviderError(
                  event,
                  'OpenAI reported a failed response.',
                ),
              );
        case 'error':
          throw usageLimitFrom(event) ??
              AiProviderException(
                describeProviderError(event, 'OpenAI reported a stream error.'),
              );
      }
    }
    throw const AiProviderException(
      'OpenAI ended the stream without a final response.',
    );
  }

  /// Opens the stream. The one place the subscription client differs on the
  /// wire, so its endpoint, session and body rules stay out of the loop.
  Future<Response<ResponseBody>> _postResponses(
    String apiKey,
    Map<String, Object?> body,
  ) => retryTransient(
    () => dio.post<ResponseBody>(
      '$_baseUrl/responses',
      data: body,
      options: _options(apiKey).copyWith(responseType: ResponseType.stream),
    ),
  );

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

/// A ChatGPT subscription, through the backend the Codex CLI uses.
///
/// The wire format is the Responses API [OpenAiClient] already speaks, so the
/// loop, streaming and tool round trips are inherited rather than copied — two
/// copies of a tool loop drift. Everything that differs lives in
/// [_postResponses]: the endpoint, a rotating session instead of a key, and the
/// body rules in [subscriptionRequestBody].
class ChatGptSubscriptionClient extends OpenAiClient {
  ChatGptSubscriptionClient(
    super.dio,
    super.capabilityRegistry,
    this._sessions,
  );

  static const baseUrl = 'https://chatgpt.com/backend-api/codex';

  /// Names this app on every request. Codex sends its own name here, and
  /// sending Codex's would pass SuperHealth off as OpenAI's client.
  static const originator = 'superhealth';

  final ChatGptSessionSource? _sessions;

  @override
  AiProvider get provider => AiProvider.chatgpt;

  /// No file upload or code interpreter on the subscription; the capability
  /// registry already says so, and this keeps [validate] refusing even a
  /// model added there by mistake.
  @override
  bool get supportsContextFile => false;

  /// The curated catalog, without a request: see
  /// [ProviderCapabilityRegistry.chatGptModels] for why it is not fetched.
  @override
  Future<List<AiModelInfo>> listModels(String apiKey) async => [
    for (final id in ProviderCapabilityRegistry.chatGptModels)
      AiModelInfo(id: id, displayName: id, provider: provider),
  ];

  /// [apiKey] is ignored. The session is resolved per request because the
  /// access token rotates, and a plan that outlives it needs the new one.
  @override
  Future<Response<ResponseBody>> _postResponses(
    String apiKey,
    Map<String, Object?> body,
  ) async {
    final sessions = _sessions;
    if (sessions == null) {
      throw const ChatGptAuthException(ChatGptAuthFailure.notSignedIn);
    }
    final wire = subscriptionRequestBody(body);
    Future<Response<ResponseBody>> post(ChatGptSession session) async {
      try {
        return await dio.post<ResponseBody>(
          '$baseUrl/responses',
          data: wire,
          options: Options(
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              'ChatGPT-Account-ID': ?session.accountId,
              'originator': originator,
              'Accept': 'text/event-stream',
              'Content-Type': 'application/json',
            },
            responseType: ResponseType.stream,
          ),
        );
      } on DioException catch (error) {
        if (error.response?.statusCode != 429) rethrow;
        // Read before the retry policy sees it: a 429 is retried as a rate
        // limit, but the usage limit lasts until its reset, and retrying it
        // only adds seconds of waiting to an answer that cannot change.
        final decoded = await decodeStreamError(error);
        final limit = usageLimitFrom(decoded);
        if (limit != null) throw limit;
        // The body stream can be read once, so the decoded copy travels on
        // for the provider error message.
        throw DioException(
          requestOptions: error.requestOptions,
          response: Response<Object?>(
            requestOptions: error.requestOptions,
            statusCode: 429,
            headers: error.response!.headers,
            data: decoded,
          ),
          type: error.type,
          error: error.error,
        );
      }
    }

    Future<Response<ResponseBody>> send(ChatGptSession session) =>
        retryTransient(() => post(session));
    try {
      return await send(await sessions.session());
    } on DioException catch (error) {
      // A token can be revoked before its `exp`, as Codex also assumes: one
      // forced renewal and one retry, and a second 401 is reported as is.
      if (error.response?.statusCode != 401) rethrow;
      return send(await sessions.session(forceRefresh: true));
    }
  }
}

/// The Responses body as the subscription backend takes it.
///
/// It refuses `max_output_tokens`, because the plan sets the output budget, and
/// has no `prompt_cache_retention`. An unsupported parameter fails the whole
/// call, so both are dropped rather than sent; `prompt_cache_key` stays, as
/// Codex sends it too. Messages go as typed content parts, the only shape
/// Codex uses there. The API's string shorthand is not something to discover
/// the backend tolerates halfway through a plan.
Map<String, Object?> subscriptionRequestBody(Map<String, Object?> body) {
  final wire = Map<String, Object?>.from(body)
    ..remove('max_output_tokens')
    ..remove('prompt_cache_retention');
  final input = body['input'];
  if (input is List) {
    wire['input'] = [for (final item in input) _typedMessage(item)];
  }
  return wire;
}

/// Rewrites a `{role, content: "text"}` turn into Codex's typed message.
/// Items that already carry a `type` — the model's own output echoed back,
/// tool results — pass through untouched, because they are only valid
/// verbatim.
Object? _typedMessage(Object? item) {
  if (item is! Map || item.containsKey('type')) return item;
  final role = item['role'];
  final content = item['content'];
  if (content is! String) return item;
  return {
    'type': 'message',
    'role': role,
    'content': [
      {
        'type': role == 'assistant' ? 'output_text' : 'input_text',
        'text': content,
      },
    ],
  };
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
    AgentToolHandler? onToolCalls,
  }) async {
    validate(request);
    requireToolHandler(request, onToolCalls);
    final capabilities = capabilityRegistry.forModel(provider, request.model);
    String? contextFileId;
    try {
      if (request.contextFile) {
        contextFileId = await _uploadContext(apiKey, request.contextJson);
      }
      final contextBlocks = request.contextFile
          ? <Map<String, Object?>>[
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
          : <Map<String, Object?>>[
              {
                'type': 'text',
                'text':
                    '<complete_health_context>\n${request.contextJson}'
                    '\n</complete_health_context>',
                'cache_control': {'type': 'ephemeral'},
              },
            ];
      final digest = request.digestText;
      final messages = <Object?>[
        {
          'role': 'user',
          'content': digest == null
              ? contextBlocks
              : [
                  {
                    'type': 'text',
                    'text': '<clinical_digest>\n$digest\n</clinical_digest>',
                    'cache_control': {'type': 'ephemeral'},
                  },
                  if (request.contextFile || request.contextJson.isNotEmpty)
                    ...contextBlocks,
                ],
        },
        for (final turn in request.history)
          {'role': turn.role, 'content': turn.content},
        {'role': 'user', 'content': request.userPrompt},
      ];
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
        'messages': messages,
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
      for (final spec in request.tools) {
        tools.add({
          'name': spec.name,
          'description': spec.description,
          'input_schema': spec.inputSchema,
        });
      }
      if (tools.isNotEmpty) body['tools'] = tools;
      final betas = [
        if (request.contextFile) _filesBeta,
        if (capabilities.refusalFallback) _fallbackBeta,
      ];
      final options = _options(apiKey, betas: betas);

      final reporter = ActivityReporter(onActivity);
      var usage = const TokenUsage();
      final citations = <String>{};
      // Text of the current round only. Anything written before a tool call
      // is preamble ("let me check…"), not the answer.
      var textParts = <String>[];
      var resumes = 0;
      var round = 0;
      // The block carrying the moving cache breakpoint: at most one, so the
      // request never exceeds the four breakpoints the API allows.
      Map<String, Object?>? rolling;
      while (true) {
        final raw = await _streamMessage(body, options, reporter);
        usage = usage + (TokenUsage.fromResponse(raw) ?? const TokenUsage());
        textParts.addAll(_textBlocks(raw));
        citations.addAll(collectUrls(raw));
        final stopReason = raw['stop_reason']?.toString();
        // A server-tool loop that hits its iteration limit pauses the turn.
        // Resume by echoing the assistant content; the reply continues where
        // the paused turn stopped, so text accumulates across resumes.
        if (stopReason == 'pause_turn') {
          if (resumes >= _maxPauseTurnResumes) {
            throw const AiProviderException(
              'Anthropic paused the tool loop repeatedly without finishing. '
              'Try again, or disable web search for this request.',
            );
          }
          resumes += 1;
          messages.add({'role': 'assistant', 'content': raw['content']});
          continue;
        }
        if (stopReason == 'tool_use') {
          final calls = [
            for (final block
                in (raw['content'] as List? ?? const []).whereType<Map>())
              if (block['type'] == 'tool_use')
                AgentToolCall(
                  id: block['id']?.toString() ?? '',
                  name: block['name']?.toString() ?? '',
                  input: block['input'] is Map
                      ? Map<String, Object?>.from(block['input'] as Map)
                      : const {},
                ),
          ];
          if (calls.isNotEmpty) {
            round += 1;
            if (round > maxToolRounds + 1) {
              throw const AiProviderException(
                'Anthropic kept calling tools without answering.',
              );
            }
            final results = await runToolRound(calls, round, onToolCalls!);
            // Echoed verbatim: thinking blocks carry signatures the API
            // checks, and a tool_use without its exact block is rejected.
            messages.add({'role': 'assistant', 'content': raw['content']});
            final resultBlocks = [
              for (final result in results)
                <String, Object?>{
                  'type': 'tool_result',
                  'tool_use_id': result.callId,
                  'content': result.content,
                  if (result.isError) 'is_error': true,
                },
            ];
            rolling?.remove('cache_control');
            resultBlocks.last['cache_control'] = {'type': 'ephemeral'};
            rolling = resultBlocks.last;
            messages.add({'role': 'user', 'content': resultBlocks});
            textParts = [];
            resumes = 0;
            continue;
          }
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
          aggregateUsage: usage.isEmpty ? null : usage,
          toolRounds: round,
        );
      }
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
    AgentToolHandler? onToolCalls,
  }) async {
    // Tools are refused in `validate`: see [providerSupportsClientTools].
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
          '${request.digestText == null ? '' : '<clinical_digest>\n${request.digestText}\n</clinical_digest>\n\n'}'
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
